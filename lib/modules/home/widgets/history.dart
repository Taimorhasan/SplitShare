import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/routes/app_routes.dart';
import '../../../controllers/expense_controller.dart';
import '../../../controllers/shell_controller.dart';
import '../../../controllers/trip_controller.dart';
import '../../../core/ui.dart';

enum HistoryKind { expense, payment, groupPayment, groupPayback }

/// One line of the user's history: a classic expense or payment, or a
/// payment / pay-back inside a group.
class HistoryEntry {
  final String id;
  final DateTime at;
  final HistoryKind kind;
  final String title;
  final String subtitle;

  /// The full amount of the transaction.
  final double amount;
  final String currency;

  /// Signed effect on me. Expenses and group payments: + I get back,
  /// − I owe. Payments and pay-backs: + I received, − I paid.
  final double myEffect;

  /// The expense was part of a settle-up (no balance left on it).
  final bool settled;

  /// False when I'm neither the payer nor a sharer.
  final bool involved;

  final IconData icon;

  /// Category colour for expenses; null = primary tint (group items).
  final Color? color;
  final VoidCallback? onTap;

  const HistoryEntry({
    required this.id,
    required this.at,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.currency,
    required this.myEffect,
    required this.icon,
    this.settled = false,
    this.involved = true,
    this.color,
    this.onTap,
  });

  bool get isPayment =>
      kind == HistoryKind.payment || kind == HistoryKind.groupPayback;
}

double _num(dynamic v) => v is num ? v.toDouble() : 0.0;

/// Every transaction the signed-in user is part of, newest first.
/// Callers wrap in `Obx` and touch `ExpenseController.to.recentActivity`
/// and `TripController.to.trips` so this rebuilds.
List<HistoryEntry> buildHistory() {
  final ec = ExpenseController.to;
  final me = ec.currentUid;
  final out = <HistoryEntry>[];

  for (final e in ec.recentActivity) {
    final id = e['id']?.toString() ?? '';
    final at = Fmt.toDate(e['createdAt']) ??
        Fmt.toDate(e['date']) ??
        DateTime.now(); // pending write
    final isPayment = ExpenseController.isPayment(e);
    final style = ExpenseCategories.of(
      e['category']?.toString(),
      isPayment: isPayment,
    );
    final currency = (e['currencyCode'] ?? 'USD').toString();
    final amount = _num(e['amount']);
    final payer = ExpenseController.payerOf(e);
    final paidBy = e['paidBy'];
    final payerName = payer == me
        ? 'You'
        : ((paidBy is Map ? paidBy['name'] : null) ?? ec.nameFor(payer))
            .toString();
    final splits = Map<String, dynamic>.from(e['individualSplits'] ?? {});
    void open() {
      if (id.isNotEmpty) AppNav.openExpense(id);
    }

    if (isPayment) {
      final receiver =
          splits.keys.firstWhere((k) => k != payer, orElse: () => '');
      final receiverName = receiver == me ? 'you' : ec.nameFor(receiver);
      out.add(HistoryEntry(
        id: 'e:$id',
        at: at,
        kind: HistoryKind.payment,
        title: '$payerName paid $receiverName',
        subtitle: 'Payment',
        amount: amount,
        currency: currency,
        myEffect: payer == me
            ? -amount
            : receiver == me
                ? amount
                : 0,
        involved: payer == me || receiver == me,
        icon: style.icon,
        color: style.color,
        onTap: open,
      ));
      continue;
    }

    final category = (e['category'] ?? 'Other').toString();
    out.add(HistoryEntry(
      id: 'e:$id',
      at: at,
      kind: HistoryKind.expense,
      title: (e['description'] ?? 'Expense').toString(),
      subtitle: '$payerName paid · $category',
      amount: amount,
      currency: currency,
      myEffect: ec.myNetOn(e),
      settled: e['isSettled'] == true ||
          (me != null &&
              payer != me &&
              ((e['settledPairs'] as List?)
                      ?.contains(ExpenseController.pairKey(me, payer)) ??
                  false)),
      involved: me != null && (payer == me || splits.containsKey(me)),
      icon: style.icon,
      color: style.color,
      onTap: open,
    ));
  }

  if (me != null && Get.isRegistered<TripController>()) {
    for (final trip in TripController.to.trips) {
      final mine = trip.people.firstWhereOrNull((p) => p.uid == me);
      if (mine == null) continue;
      void open() =>
          Get.toNamed(AppRoutes.tripDetail, arguments: {'id': trip.id});
      String who(String personId) =>
          personId == mine.id ? 'You' : trip.nameOf(personId);

      for (final pay in trip.payments) {
        final shares = TripMath.sharesOf(pay, trip.people);
        final iPaid = pay.personId == mine.id;
        if (!iPaid && !shares.containsKey(mine.id)) continue;
        final myShare = shares[mine.id] ?? 0;
        final effectCents = iPaid ? pay.cents - myShare : -myShare;
        out.add(HistoryEntry(
          id: 't:${trip.id}:${pay.id}',
          at: pay.at,
          kind: HistoryKind.groupPayment,
          title: pay.note.trim().isEmpty ? 'Payment' : pay.note.trim(),
          subtitle: '${who(pay.personId)} paid in ${trip.title}',
          amount: pay.cents / 100,
          currency: trip.currencyCode,
          myEffect: effectCents / 100,
          icon: Icons.groups_rounded,
          onTap: open,
        ));
      }

      for (final s in trip.settlements) {
        final iPaid = s.fromId == mine.id;
        if (!iPaid && s.toId != mine.id) continue;
        out.add(HistoryEntry(
          id: 's:${trip.id}:${s.id}',
          at: s.at,
          kind: HistoryKind.groupPayback,
          title: iPaid
              ? 'You paid ${trip.nameOf(s.toId)} back'
              : '${trip.nameOf(s.fromId)} paid you back',
          subtitle: 'In ${trip.title}',
          amount: s.cents / 100,
          currency: trip.currencyCode,
          myEffect: (iPaid ? -s.cents : s.cents) / 100,
          icon: Icons.handshake_outlined,
          onTap: open,
        ));
      }
    }
  }

  out.sort((a, b) => b.at.compareTo(a.at));
  return out;
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "Today", "Yesterday", "Mon, 24 Nov" (year added when not this year).
String historyDayLabel(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  final base = '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';
  return d.year == now.year ? base : '$base ${d.year}';
}

/// History grouped by day: a small day header, then one card per day with
/// the rows separated by dividers.
class HistoryList extends StatelessWidget {
  final List<HistoryEntry> entries;
  final int? limit;

  const HistoryList(this.entries, {super.key, this.limit});

  @override
  Widget build(BuildContext context) {
    final shown = limit == null ? entries : entries.take(limit!).toList();
    final days = <String, List<HistoryEntry>>{};
    for (final e in shown) {
      (days[historyDayLabel(e.at)] ??= []).add(e);
    }
    final firstDay = days.keys.isEmpty ? null : days.keys.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final day in days.entries) ...[
          Padding(
            padding: EdgeInsets.only(
              top: day.key == firstDay ? 0 : AppSpacing.lg,
              bottom: AppSpacing.sm,
              left: AppSpacing.xs,
            ),
            child: Text(
              day.key,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          AppCard(
            padding: EdgeInsets.zero,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: Column(
                children: [
                  for (var i = 0; i < day.value.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 1,
                        thickness: 1,
                        indent: AppSpacing.lg + 40 + AppSpacing.md,
                        color: AppColors.border,
                      ),
                    HistoryRow(
                      key: ValueKey(day.value[i].id),
                      entry: day.value[i],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class HistoryRow extends StatelessWidget {
  final HistoryEntry entry;
  const HistoryRow({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final money = Fmt.money(e.amount, currencyCode: e.currency);
    final effect = Fmt.money(e.myEffect.abs(), currencyCode: e.currency);
    final hasEffect = e.myEffect.abs() >= 0.005;

    final String caption;
    final Color captionColor;
    if (e.isPayment) {
      if (!hasEffect) {
        caption = 'payment';
        captionColor = AppColors.textMuted;
      } else if (e.myEffect > 0) {
        caption = 'you received';
        captionColor = AppColors.positive;
      } else {
        caption = 'you paid';
        captionColor = AppColors.textSecondary;
      }
    } else if (!e.involved) {
      caption = 'not involved';
      captionColor = AppColors.textMuted;
    } else if (hasEffect) {
      caption = e.myEffect > 0 ? 'you get $effect' : 'you owe $effect';
      captionColor = e.myEffect > 0 ? AppColors.positive : AppColors.negative;
    } else {
      caption = e.settled ? 'settled' : 'no share';
      captionColor = AppColors.textMuted;
    }

    final tint = e.color ?? AppColors.primary;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: e.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              IconBadge(icon: e.icon, color: tint, size: 40, iconSize: 20),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      e.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    money,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    caption,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: captionColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

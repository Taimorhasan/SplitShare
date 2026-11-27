import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';

import '../../controllers/friend_controller.dart';
import '../../controllers/trip_controller.dart';
import '../../core/ui.dart';
import 'group_list.dart' show GroupTypePicker;

/// One trip: everyone logs what they paid; the screen shows each person's
/// share and the fewest "X pays Y" transfers that settle everything.
///
/// Arguments: `{'id': String}` (required).
class TripDetailScreen extends StatefulWidget {
  const TripDetailScreen({super.key});

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> {
  late final String? _id;
  Stream<Trip?>? _stream;
  Trip? _last;
  bool _fewest = false;
  final Set<String> _collapsed = {};

  @override
  void initState() {
    super.initState();
    final args = Get.arguments;
    final raw = args is Map ? args['id']?.toString() : null;
    _id = (raw == null || raw.isEmpty) ? null : raw;
    if (_id != null) _stream = TripController.to.tripStream(_id);
  }

  void _retry() {
    if (_id != null) setState(() => _stream = TripController.to.tripStream(_id));
  }

  String _money(Trip t, int cents) =>
      Fmt.money(cents / 100, currencyCode: t.currencyCode);

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    try {
      await action();
      if (success != null) AppToast.success(success);
    } catch (e) {
      AppToast.error(e is TripException ? e.message : AppToast.friendly(e));
    }
  }

  String _splitLabel(Trip trip, TripPayment pay) {
    final sharers = pay.sharers(trip.people);
    if (sharers.length == trip.people.length) return 'split between everyone';
    if (sharers.length <= 3) {
      return 'split: ${sharers.map((id) => Fmt.firstName(trip.nameOf(id))).join(', ')}';
    }
    return 'split between ${sharers.length} people';
  }

  Future<void> _deletePayment(Trip trip, TripPayment pay) async {
    final ok = await AppDialogs.confirm(
      title: 'Delete this payment?',
      message: '${trip.nameOf(pay.personId)} paid ${_money(trip, pay.cents)}'
          "${pay.note.isEmpty ? '' : ' for ${pay.note}'}. Everyone's accounts will "
          'be recalculated.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    await _run(() => TripController.to.deletePayment(trip.id, pay.id),
        success: 'Payment deleted.');
  }

  // ------------------------------------------------------------- actions

  Future<void> _addPeople(Trip trip) async {
    final entries = await AppDialogs.sheet<List<Map<String, dynamic>>>(
      title: 'Add people',
      child: _AddPeopleSheet(trip: trip),
    );
    if (entries == null || entries.isEmpty) return;
    try {
      final added = await TripController.to.addPeople(trip.id, entries);
      if (added == 0) {
        AppToast.info('They\'re already in this group.');
      } else {
        AppToast.success('Added $added ${added == 1 ? 'person' : 'people'}.');
      }
    } catch (e) {
      AppToast.error(e is TripException ? e.message : AppToast.friendly(e));
    }
  }

  Future<void> _addPayment(Trip trip, {String? personId, TripPayment? edit}) async {
    if (trip.people.length < 2 && edit == null) {
      AppToast.info('Add the people on this group first.', title: 'Who came?');
      await _addPeople(trip);
      return;
    }
    await AppDialogs.sheet<void>(
      title: edit == null ? 'Add payment' : 'Edit payment',
      child: _PaymentSheet(trip: trip, initialPersonId: personId, edit: edit),
    );
  }

  Future<void> _markPaid(Trip trip, TripTransfer t) async {
    final ok = await AppDialogs.confirm(
      title: 'Mark as paid?',
      message: '${trip.nameOf(t.fromId)} paid ${trip.nameOf(t.toId)} '
          '${_money(trip, t.cents)}.',
      confirmLabel: 'Mark paid',
      icon: Icons.check_circle_rounded,
    );
    if (!ok) return;
    await _run(() => TripController.to.markTransferPaid(trip.id, t),
        success: 'Payment recorded.');
  }

  Future<void> _personMenu(Trip trip, TripPerson person) async {
    final action = await AppDialogs.sheet<String>(
      title: person.name,
      child: Builder(
        builder: (ctx) => Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppListTile(
                icon: Icons.add_card_rounded,
                title: 'Add a payment by ${person.name}',
                onTap: () => Navigator.of(ctx).pop('pay'),
              ),
              AppListTile(
                icon: Icons.edit_rounded,
                title: 'Rename',
                onTap: () => Navigator.of(ctx).pop('rename'),
              ),
              if (person.uid != trip.ownerUid)
                AppListTile(
                  icon: Icons.person_remove_rounded,
                  title: 'Remove from group',
                  subtitle: 'Their payments are removed too',
                  destructive: true,
                  onTap: () => Navigator.of(ctx).pop('remove'),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'pay':
        await _addPayment(trip, personId: person.id);
      case 'rename':
        final name = await AppDialogs.sheet<String>(
          title: 'Rename',
          child: _TextSheet(initial: person.name, label: 'Name', button: 'Save'),
        );
        if (name != null) {
          await _run(() => TripController.to.renamePerson(trip.id, person.id, name));
        }
      case 'remove':
        final ok = await AppDialogs.confirm(
          title: 'Remove ${person.name}?',
          message: 'Their payments and pay-backs in this group will be deleted '
              'and everyone\'s shares recalculated.',
          confirmLabel: 'Remove',
          destructive: true,
        );
        if (ok) {
          await _run(() => TripController.to.removePerson(trip.id, person.id),
              success: '${person.name} removed.');
        }
    }
  }

  Future<void> _menu(Trip trip, String action) async {
    switch (action) {
      case 'edit':
        await AppDialogs.sheet<void>(
          title: 'Group details',
          child: EditTripSheet(trip: trip),
        );
      case 'share':
        await SharePlus.instance.share(ShareParams(
          text: TripController.shareText(trip),
          subject: trip.title,
        ));
      case 'delete':
        final ok = await AppDialogs.confirm(
          title: 'Delete "${trip.title}"?',
          message: 'All its payments will be deleted for everyone. '
              'This can\'t be undone.',
          confirmLabel: 'Delete',
          destructive: true,
        );
        if (!ok) return;
        try {
          await TripController.to.deleteTrip(trip.id);
          if (!mounted) return;
          AppToast.success('Group deleted.');
          Navigator.of(context).pop();
        } catch (e) {
          AppToast.error(AppToast.friendly(e));
        }
    }
  }

  // ------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    if (_id == null) return _unavailable('Group');
    return StreamBuilder<Trip?>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(
            appBar: AppTopBar(title: _last?.title ?? 'Group'),
            body: ErrorState(
              title: 'Couldn\'t load this group',
              onRetry: _retry,
            ),
          );
        }
        if (snap.connectionState == ConnectionState.waiting && _last == null) {
          return const Scaffold(
            appBar: AppTopBar(title: 'Group'),
            body: SkeletonList(count: 5),
          );
        }
        final trip = snap.data;
        if (trip == null) return _unavailable(_last?.title ?? 'Group');
        _last = trip;
        return _content(trip);
      },
    );
  }

  Widget _unavailable(String title) => Scaffold(
        appBar: AppTopBar(title: title),
        body: EmptyState(
          icon: Icons.luggage_rounded,
          color: AppColors.textSecondary,
          title: 'This group isn\'t available',
          message: 'It may have been deleted, or you were removed from it.',
          actionLabel: 'Go back',
          onAction: () => Navigator.of(context).maybePop(),
        ),
      );

  Widget _content(Trip trip) {
    final summary = trip.summary;
    final plan = _fewest ? trip.simplifiedPlan : trip.plan;
    final isOwner = TripController.to.isOwner(trip);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppTopBar(
        title: trip.title,
        subtitle: '${trip.people.length} '
            '${trip.people.length == 1 ? 'person' : 'people'} · ${trip.currencyCode}',
        actions: [
          AppIconButton(
            icon: Icons.ios_share_rounded,
            tooltip: 'Share summary',
            onPressed: () => _menu(trip, 'share'),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (a) => _menu(trip, a),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Rename / currency')),
              const PopupMenuItem(value: 'share', child: Text('Share summary')),
              if (isOwner)
                PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete group', style: TextStyle(color: AppColors.error)),
                ),
            ],
            child: const AppIconButton(icon: Icons.more_horiz_rounded, onPressed: null),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.page, AppSpacing.sm, AppSpacing.page, 120),
        children: [
          FadeSlideIn(child: _hero(trip)),

          // ---- Who pays whom
          SectionHeader(
            title: 'Who pays whom',
            padding: const EdgeInsets.only(top: AppSpacing.xxl, bottom: AppSpacing.md),
          ),
          if (trip.payments.isEmpty)
            _hint(
              Icons.lightbulb_rounded,
              'Add a payment whenever someone pays. SplitShare works out who '
              'owes whom automatically.',
            )
          else ...[
            _PlanModeToggle(
              fewest: _fewest,
              onChanged: (v) => setState(() => _fewest = v),
            ),
            const SizedBox(height: AppSpacing.md),
            if (plan.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline_rounded,
                        color: AppColors.textMuted, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Everyone is settled up.',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < plan.length; i++) ...[
                      if (i > 0)
                        Divider(height: 1, thickness: 1, color: AppColors.border),
                      FadeSlideIn(
                        index: i,
                        child: _TransferCard(
                          from: trip.person(plan[i].fromId),
                          to: trip.person(plan[i].toId),
                          amount: _money(trip, plan[i].cents),
                          onPaid: () => _markPaid(trip, plan[i]),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            _HowItWorks(fewest: _fewest),
          ],

          // ---- Everyone's account (one block per person)
          SectionHeader(
            title: 'Everyone\'s account',
            actionLabel: 'Add people',
            onAction: () => _addPeople(trip),
            padding: const EdgeInsets.only(top: AppSpacing.xl, bottom: AppSpacing.md),
          ),
          if (trip.people.length < 2)
            AppCard(
              child: Column(
                children: [
                  Text(
                    'Add everyone who is in this group — friends from SplitShare, '
                    'people from your contacts, or just type their names.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppButton.secondary(
                    label: 'Add people',
                    icon: Icons.group_add_rounded,
                    height: 46,
                    onPressed: () => _addPeople(trip),
                  ),
                ],
              ),
            )
          else
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < summary.length; i++) ...[
                    if (i > 0)
                      Divider(height: 1, thickness: 1, color: AppColors.border),
                    _PersonBlock(
                      trip: trip,
                      summary: summary[i],
                      money: (c) => _money(trip, c),
                      expanded: !_collapsed.contains(summary[i].person.id),
                      onToggle: () => setState(() {
                        final id = summary[i].person.id;
                        _collapsed.contains(id) ? _collapsed.remove(id) : _collapsed.add(id);
                      }),
                      onMenu: () => _personMenu(trip, summary[i].person),
                      onAddPayment: () => _addPayment(trip, personId: summary[i].person.id),
                    ),
                  ],
                ],
              ),
            ),

          // ---- Payments
          SectionHeader(
            title: 'Payments (${trip.payments.length})',
            padding: const EdgeInsets.only(top: AppSpacing.xl, bottom: AppSpacing.sm),
          ),
          if (trip.payments.isEmpty)
            _hint(Icons.receipt_long_rounded,
                'No payments yet. Tap "Add payment" whenever someone pays.')
          else ...[
            const SwipeHint(),
            AppCard(
              padding: EdgeInsets.zero,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: Column(
                  children: [
                    for (var i = 0; i < trip.payments.length; i++) ...[
                      if (i > 0)
                        Divider(height: 1, thickness: 1, color: AppColors.border),
                      SwipeActions(
                        key: ValueKey('pay-${trip.payments[i].id}'),
                        radius: 0,
                        onEdit: () => _addPayment(trip, edit: trip.payments[i]),
                        onDelete: () => _deletePayment(trip, trip.payments[i]),
                        child: _PaymentRow(
                          payment: trip.payments[i],
                          person: trip.person(trip.payments[i].personId),
                          amount: _money(trip, trip.payments[i].cents),
                          splitLabel: _splitLabel(trip, trip.payments[i]),
                          onTap: () => _addPayment(trip, edit: trip.payments[i]),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],

          // ---- Paid back
          if (trip.settlements.isNotEmpty) ...[
            const SectionHeader(
              title: 'Paid back',
              padding: EdgeInsets.only(top: AppSpacing.xl, bottom: AppSpacing.md),
            ),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (i, s) in trip.settlements.indexed) ...[
                    if (i > 0)
                      Divider(height: 1, thickness: 1, color: AppColors.border),
                    ListTile(
                      leading: Icon(Icons.check_circle_outline_rounded,
                          color: AppColors.textMuted),
                      title: Text(
                        '${trip.nameOf(s.fromId)} paid ${trip.nameOf(s.toId)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14.5,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        '${_money(trip, s.cents)} · ${Fmt.relative(s.at)}',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                      trailing: TextButton(
                        onPressed: () async {
                          final ok = await AppDialogs.confirm(
                            title: 'Undo this pay-back?',
                            message: 'It will count as unpaid again.',
                            confirmLabel: 'Undo',
                          );
                          if (ok) {
                            await _run(
                                () => TripController.to.undoSettlement(trip.id, s.id));
                          }
                        },
                        child: const Text('Undo'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],

          // ---- Final tally: who receives, who gives
          if (trip.payments.isNotEmpty) ...[
            const SectionHeader(
              title: 'In the end',
              padding: EdgeInsets.only(top: AppSpacing.xl, bottom: AppSpacing.md),
            ),
            _FinalTally(trip: trip, money: (c) => _money(trip, c)),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, 12, AppSpacing.page, 12),
          decoration: BoxDecoration(
            color: AppColors.background,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: AppButton(
            label: 'Add payment',
            icon: Icons.add_rounded,
            onPressed: () => _addPayment(trip),
          ),
        ),
      ),
    );
  }

  Widget _hero(Trip trip) {
    final n = trip.people.length;
    final m = trip.payments.length;
    final each = n == 0 ? 0 : trip.totalCents / n / 100;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: BalanceCard(
        label: 'Total spent',
        amount: _money(trip, trip.totalCents),
        caption: '$n ${n == 1 ? 'person' : 'people'} · '
            '$m ${m == 1 ? 'payment' : 'payments'}'
            '${n == 0 ? '' : ' · ${Fmt.money(each, currencyCode: trip.currencyCode)} each'}',
      ),
    );
  }

  Widget _hint(IconData icon, String text) => AppCard(
        child: Row(
          children: [
            Icon(icon, color: AppColors.textMuted, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(text,
                  style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary)),
            ),
          ],
        ),
      );
}

// ===================================================================== rows

class _TransferCard extends StatelessWidget {
  final TripPerson? from;
  final TripPerson? to;
  final String amount;
  final VoidCallback onPaid;

  const _TransferCard({
    required this.from,
    required this.to,
    required this.amount,
    required this.onPaid,
  });

  @override
  Widget build(BuildContext context) {
    final fromName = from?.name ?? 'Someone';
    final toName = to?.name ?? 'Someone';
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        children: [
          Row(
            children: [
              AppAvatar(name: fromName, imageUrl: from?.avatarUrl, radius: 18),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    children: [
                      Text(
                        amount,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Container(height: 1, color: AppColors.border),
                          ),
                          Icon(Icons.arrow_forward_rounded,
                              size: 16, color: AppColors.textMuted),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              AppAvatar(name: toName, imageUrl: to?.avatarUrl, radius: 18),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
                    children: [
                      TextSpan(
                        text: fromName,
                        style: TextStyle(
                            fontWeight: FontWeight.w700, color: AppColors.negative),
                      ),
                      const TextSpan(text: ' pays '),
                      TextSpan(
                        text: toName,
                        style: TextStyle(
                            fontWeight: FontWeight.w700, color: AppColors.positive),
                      ),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 36,
                child: OutlinedButton.icon(
                  onPressed: onPaid,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Mark paid'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Pair by pair" (default, easiest to follow) vs "Fewest payments".
class _PlanModeToggle extends StatelessWidget {
  final bool fewest;
  final ValueChanged<bool> onChanged;
  const _PlanModeToggle({required this.fewest, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, IconData icon, bool value) {
      final selected = fewest == value;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(value),
          child: AnimatedContainer(
            duration: AppMotion.normal,
            curve: AppMotion.curve,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? AppColors.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(
                color: selected ? AppColors.border : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 16,
                    color: selected ? AppColors.primary : AppColors.textMuted),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: selected ? AppColors.primary : AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          seg('Pair by pair', Icons.compare_arrows_rounded, false),
          seg('Fewest payments', Icons.bolt_rounded, true),
        ],
      ),
    );
  }
}

/// Plain-language explanation of the maths.
class _HowItWorks extends StatelessWidget {
  final bool fewest;
  const _HowItWorks({required this.fewest});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          leading: Icon(Icons.calculate_rounded, color: AppColors.primary),
          title: Text(
            'How is this calculated?',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          shape: const Border(),
          collapsedShape: const Border(),
          children: [
            _step('1', 'Each payment is shared equally by the people you picked '
                'for it (everyone, unless you chose otherwise).'),
            _step('2', 'For every two people we add up what each owes the other. '
                'Example: Ali owes Ahad 2,000 and Ahad owes Ali 1,875.'),
            _step('3', 'Then we cancel them out: Ali pays Ahad only the '
                'difference, 125.'),
            if (fewest)
              _step('4', '"Fewest payments" goes one step further and re-routes '
                  'money so the group needs as few transfers as possible. '
                  'Everyone ends up with exactly the same result.'),
            _step('✓', 'Tap "Mark paid" when someone pays back. It updates '
                'everyone\'s account straight away.'),
          ],
        ),
      ),
    );
  }

  Widget _step(String n, String text) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 18,
              child: Text(n,
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13.5,
                      height: 1.4,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 13.5, height: 1.4, color: AppColors.textPrimary)),
            ),
          ],
        ),
      );
}

/// One person's account: what they paid, their share, and — with every
/// other person — what each owes the other and what's left after cancelling.
class _PersonBlock extends StatelessWidget {
  final Trip trip;
  final TripPersonSummary summary;
  final String Function(int cents) money;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onMenu;
  final VoidCallback onAddPayment;

  const _PersonBlock({
    required this.trip,
    required this.summary,
    required this.money,
    required this.expanded,
    required this.onToggle,
    required this.onMenu,
    required this.onAddPayment,
  });

  @override
  Widget build(BuildContext context) {
    final p = summary.person;
    final b = summary.balanceCents;
    final Color tone = b > 0
        ? AppColors.positive
        : b < 0
            ? AppColors.negative
            : AppColors.textMuted;
    final String status = b > 0
        ? 'gets back ${money(b)}'
        : b < 0
            ? 'owes ${money(-b)}'
            : 'settled';
    final views = trip.pairsFor(p.id);

    return Material(
      color: Colors.transparent,
      child: Column(
        children: [
          // Header
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 6, 12),
              child: Row(
                children: [
                  AppAvatar(name: p.name, imageUrl: p.avatarUrl, radius: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                p.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            if (p.uid != null) ...[
                              const SizedBox(width: 5),
                              Icon(Icons.verified_rounded,
                                  size: 14, color: AppColors.primary),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          status,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: tone,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Options',
                    onPressed: onMenu,
                    icon: Icon(Icons.more_vert_rounded, color: AppColors.textMuted),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: AppMotion.normal,
                    child: Icon(Icons.expand_more_rounded,
                        color: AppColors.textMuted),
                  ),
                  const SizedBox(width: 6),
                ],
              ),
            ),
          ),
          // Paid / share strip
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                _stat('Paid', money(summary.paidCents), AppColors.textPrimary),
                Container(width: 1, height: 18, color: AppColors.border),
                const SizedBox(width: 12),
                _stat('Share', money(summary.shareCents), AppColors.textPrimary),
              ],
            ),
          ),
          AnimatedSize(
            duration: AppMotion.normal,
            curve: AppMotion.curve,
            alignment: Alignment.topCenter,
            child: !expanded
                ? const SizedBox(height: 14, width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Column(
                      children: [
                        if (views.isEmpty)
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'No shared payments yet.',
                                  style: TextStyle(
                                      fontSize: 13, color: AppColors.textSecondary),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: onAddPayment,
                                icon: const Icon(Icons.add_rounded, size: 18),
                                label: Text('Add ${Fmt.firstName(p.name)}\'s payment'),
                              ),
                            ],
                          )
                        else
                          for (final (i, v) in views.indexed) ...[
                            if (i > 0)
                              Divider(
                                  height: 1, thickness: 1, color: AppColors.border),
                            _PairRow(
                              me: p,
                              other: trip.person(v.otherId),
                              view: v,
                              money: money,
                            ),
                          ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color) => Expanded(
        child: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Row(
            children: [
              Text('$label ',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(value,
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700, color: color)),
                ),
              ),
            ],
          ),
        ),
      );
}

/// "Ali owes Ahad 2,000 · Ahad owes Ali 1,875 → Ali pays Ahad 125".
class _PairRow extends StatelessWidget {
  final TripPerson me;
  final TripPerson? other;
  final TripPairView view;
  final String Function(int cents) money;

  const _PairRow({
    required this.me,
    required this.other,
    required this.view,
    required this.money,
  });

  @override
  Widget build(BuildContext context) {
    final meName = Fmt.firstName(me.name);
    final otherName = Fmt.firstName(other?.name ?? 'Someone');
    final net = view.net;
    final String result;
    final Color tone;
    if (net > 0) {
      result = '$otherName pays $meName ${money(net)}';
      tone = AppColors.positive;
    } else if (net < 0) {
      result = '$meName pays $otherName ${money(-net)}';
      tone = AppColors.negative;
    } else {
      result = 'All even';
      tone = AppColors.textMuted;
    }

    Widget line(String text, int cents, Color color) => Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(
            children: [
              Expanded(
                child: Text(text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
              ),
              Text(money(cents),
                  style: TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppAvatar(name: other?.name ?? '?', imageUrl: other?.avatarUrl, radius: 15),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'With ${other?.name ?? 'Someone'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (view.theyOwe > 0)
                  line('$otherName owes $meName', view.theyOwe, AppColors.positive),
                if (view.iOwe > 0)
                  line('$meName owes $otherName', view.iOwe, AppColors.negative),
                if (view.theyPaidBack > 0)
                  line('$otherName paid back', view.theyPaidBack, AppColors.textSecondary),
                if (view.iPaidBack > 0)
                  line('$meName paid back', view.iPaidBack, AppColors.textSecondary),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      net == 0 ? Icons.check_circle_rounded : Icons.subdirectory_arrow_right_rounded,
                      size: 16,
                      color: tone,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        result,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: tone,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  final TripPayment payment;
  final TripPerson? person;
  final String amount;
  final String splitLabel;
  final VoidCallback onTap;

  const _PaymentRow({
    required this.payment,
    required this.person,
    required this.amount,
    required this.splitLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = person?.name ?? 'Someone';
    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          AppAvatar(name: name, imageUrl: person?.avatarUrl, radius: 21),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  payment.note.isEmpty ? '$name paid' : payment.note,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${payment.note.isEmpty ? '' : 'Paid by $name · '}$splitLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                amount,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                Fmt.relative(payment.at),
                style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
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

// =================================================================== sheets

/// Avatar tile used to pick people: tap to select, animated ring + tick.
class _PersonTile extends StatelessWidget {
  final TripPerson person;
  final bool selected;
  final VoidCallback onTap;
  final Color? tint;
  Color get color => tint ?? AppColors.primary;

  const _PersonTile({
    required this.person,
    required this.selected,
    required this.onTap,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            AnimatedContainer(
              duration: AppMotion.normal,
              curve: AppMotion.curve,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? color : AppColors.border,
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      shape: BoxShape.circle,
                    ),
                    child: AnimatedOpacity(
                      duration: AppMotion.fast,
                      opacity: selected ? 1 : 0.55,
                      child: AppAvatar(
                          name: person.name, imageUrl: person.avatarUrl, radius: 24),
                    ),
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: AnimatedScale(
                      scale: selected ? 1 : 0,
                      duration: AppMotion.normal,
                      curve: Curves.easeOutBack,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.surface, width: 2),
                        ),
                        child: Icon(Icons.check_rounded,
                            size: 12, color: AppColors.onPrimary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            AnimatedDefaultTextStyle(
              duration: AppMotion.fast,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppColors.textPrimary : AppColors.textSecondary,
              ),
              child: Text(
                Fmt.firstName(person.name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Add/edit a payment: who paid, how much, split between whom, what for.
class _PaymentSheet extends StatefulWidget {
  final Trip trip;
  final String? initialPersonId;
  final TripPayment? edit;

  const _PaymentSheet({required this.trip, this.initialPersonId, this.edit});

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  final _form = GlobalKey<FormState>();
  late final _amount = TextEditingController(
    text: widget.edit == null ? '' : _plain(widget.edit!.cents / 100),
  )..addListener(_refresh);
  late final _note = TextEditingController(text: widget.edit?.note ?? '');
  late String? _payerId = widget.edit?.personId ?? widget.initialPersonId;
  late Set<String> _among = widget.edit == null
      ? widget.trip.people.map((p) => p.id).toSet()
      : widget.edit!.sharers(widget.trip.people).toSet();
  bool _saving = false;

  List<TripPerson> get _people => widget.trip.people;
  bool get _everyone => _among.length == _people.length;

  static String _plain(double v) {
    var s = v.toStringAsFixed(2);
    if (s.endsWith('00')) return s.substring(0, s.length - 3);
    if (s.endsWith('0')) s = s.substring(0, s.length - 1);
    return s;
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save({bool addAnother = false}) async {
    if (_saving) return;
    if (_payerId == null) {
      AppToast.warning('Tap the person who paid.');
      return;
    }
    if (_among.isEmpty) {
      AppToast.warning('Pick at least one person to split it between.');
      return;
    }
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final amount = double.parse(_amount.text.trim());
    // Store [] for "everyone" so people added later are included too.
    final among = _everyone ? <String>[] : _among.toList();
    try {
      final ctrl = TripController.to;
      if (widget.edit == null) {
        await ctrl.addPayment(widget.trip.id,
            personId: _payerId!, amount: amount, note: _note.text, splitAmong: among);
      } else {
        await ctrl.updatePayment(widget.trip.id, widget.edit!.id,
            personId: _payerId!, amount: amount, note: _note.text, splitAmong: among);
      }
      if (!mounted) return;
      final who = widget.trip.nameOf(_payerId!);
      AppToast.success(
          '$who paid ${Fmt.money(amount, currencyCode: widget.trip.currencyCode)}.',
          title: widget.edit == null ? 'Payment added' : 'Payment updated');
      if (addAnother) {
        setState(() {
          _saving = false;
          _amount.clear();
          _note.clear();
          _payerId = null;
          _among = _people.map((p) => p.id).toSet();
        });
      } else {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.error(e is TripException ? e.message : AppToast.friendly(e));
    }
  }

  Future<void> _delete() async {
    final ok = await AppDialogs.confirm(
      title: 'Delete this payment?',
      message: 'Everyone\'s accounts will be recalculated.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    try {
      await TripController.to.deletePayment(widget.trip.id, widget.edit!.id);
      if (!mounted) return;
      AppToast.success('Payment deleted.');
      Navigator.of(context).pop();
    } catch (e) {
      AppToast.error(AppToast.friendly(e));
    }
  }

  Widget _label(String text, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Row(
          children: [
            Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            ),
            ?trailing,
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final currency = widget.trip.currencyCode;
    final symbol = Currencies.symbolFor(currency);
    final amount = double.tryParse(_amount.text.trim());
    final cents = amount == null ? 0 : TripMath.toCents(amount);
    final each = _among.isEmpty ? 0 : cents / _among.length / 100;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. Who paid
            _label('1. Who paid?'),
            SizedBox(
              height: 98,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _people.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final p = _people[i];
                  return _PersonTile(
                    person: p,
                    selected: p.id == _payerId,
                    onTap: () => setState(() => _payerId = p.id),
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // 2. How much
            _label('2. How much?'),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  Text(symbol,
                      style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textSecondary)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _amount,
                      autofocus: widget.edit == null && _payerId != null,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [amountInputFormatter],
                      validator: Validators.amount,
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.5,
                      ),
                      decoration: const InputDecoration(
                        hintText: '0',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                        fillColor: Colors.transparent,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // 3. Split between
            _label(
              '3. Split between',
              trailing: TextButton(
                onPressed: () => setState(() {
                  _among = _everyone ? <String>{} : _people.map((p) => p.id).toSet();
                }),
                child: Text(_everyone ? 'Clear' : 'Everyone'),
              ),
            ),
            Wrap(
              spacing: 6,
              runSpacing: 10,
              children: [
                for (final p in _people)
                  _PersonTile(
                    person: p,
                    selected: _among.contains(p.id),
                    tint: AppColors.positive,
                    onTap: () => setState(() {
                      _among.contains(p.id) ? _among.remove(p.id) : _among.add(p.id);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            AnimatedSwitcher(
              duration: AppMotion.fast,
              child: Container(
                key: ValueKey('$cents-${_among.length}'),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  children: [
                    Icon(Icons.call_split_rounded,
                        color: AppColors.primary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _among.isEmpty
                            ? 'Pick who shares this payment'
                            : cents == 0
                                ? 'Split equally between ${_among.length} '
                                    '${_among.length == 1 ? 'person' : 'people'}'
                                : '${Fmt.money(each, currencyCode: currency)} each · '
                                    '${_everyone ? 'everyone' : '${_among.length} people'}',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // 4. What for
            AppTextField(
              controller: _note,
              label: 'What for? (optional)',
              hint: 'e.g. Petrol, dinner, hotel, donation',
              prefixIcon: Icons.notes_rounded,
              maxLength: 60,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              label: widget.edit == null ? 'Add payment' : 'Save changes',
              icon: Icons.check_rounded,
              loading: _saving,
              onPressed: () => _save(),
            ),
            if (widget.edit == null) ...[
              const SizedBox(height: AppSpacing.sm),
              AppButton.outline(
                label: 'Save & add another',
                icon: Icons.playlist_add_rounded,
                height: 48,
                onPressed: _saving ? null : () => _save(addAnother: true),
              ),
            ] else ...[
              const SizedBox(height: AppSpacing.sm),
              AppButton.danger(
                label: 'Delete payment',
                icon: Icons.delete_outline_rounded,
                height: 48,
                onPressed: _saving ? null : _delete,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Add people by typing names, from friends, or from phone contacts.
/// Pops with a list of {name, uid?, avatarUrl?}.
class _AddPeopleSheet extends StatefulWidget {
  final Trip trip;
  const _AddPeopleSheet({required this.trip});

  @override
  State<_AddPeopleSheet> createState() => _AddPeopleSheetState();
}

class _AddPeopleSheetState extends State<_AddPeopleSheet> {
  final _name = TextEditingController();
  final _picked = <Map<String, dynamic>>[];
  bool _loadingContacts = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool _alreadyIn(String name, String? uid) {
    final lower = name.trim().toLowerCase();
    bool same(String? pUid, String pName) =>
        (uid != null && pUid == uid) ||
        (uid == null && pUid == null && pName.toLowerCase() == lower);
    return widget.trip.people.any((p) => same(p.uid, p.name)) ||
        _picked.any((p) => same(p['uid'] as String?, p['name'].toString()));
  }

  void _addTyped() {
    final n = _name.text.trim();
    if (n.isEmpty) return;
    if (_alreadyIn(n, null)) {
      AppToast.info('$n is already on the list.');
      return;
    }
    setState(() {
      _picked.add({'name': n});
      _name.clear();
    });
  }

  void _toggleFriend(Map<String, dynamic> f) {
    final uid = f['uid']?.toString();
    setState(() {
      final i = _picked.indexWhere((p) => p['uid'] == uid);
      if (i >= 0) {
        _picked.removeAt(i);
      } else {
        _picked.add({
          'name': (f['name'] ?? 'Friend').toString(),
          'uid': uid,
          'avatarUrl': (f['avatarUrl'] ?? '').toString(),
        });
      }
    });
  }

  Future<void> _fromContacts() async {
    if (_loadingContacts) return;
    setState(() => _loadingContacts = true);
    try {
      final status = await FlutterContacts.permissions.request(PermissionType.read);
      if (status != PermissionStatus.granted && status != PermissionStatus.limited) {
        AppToast.warning(
          'Allow contacts access in your phone settings to pick people from '
          'your contacts.',
          title: 'No access to contacts',
        );
        return;
      }
      final contacts = await FlutterContacts.getAll(properties: {ContactProperty.name});
      final names = contacts
          .map((c) => (c.displayName ?? '').trim())
          .where((n) => n.isNotEmpty)
          .toSet()
          .toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      if (!mounted) return;
      if (names.isEmpty) {
        AppToast.info('No contacts with names were found.');
        return;
      }
      final chosen = await AppDialogs.sheet<List<String>>(
        title: 'From contacts',
        child: _ContactsPicker(names: names),
      );
      if (chosen == null || !mounted) return;
      setState(() {
        for (final n in chosen) {
          if (!_alreadyIn(n, null)) _picked.add({'name': n});
        }
      });
    } catch (e) {
      AppToast.error('Couldn\'t read your contacts.');
      debugPrint('Contacts error: $e');
    } finally {
      if (mounted) setState(() => _loadingContacts = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inTrip = widget.trip.people.map((p) => p.uid).whereType<String>().toSet();
    final friends = FriendController.to.friends
        .where((f) => !inTrip.contains(f['uid']))
        .toList();

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: AppTextField(
                    controller: _name,
                    label: 'Type a name',
                    hint: 'e.g. Ali',
                    prefixIcon: Icons.person_add_alt_1_rounded,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _addTyped(),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 54,
                  child: AppButton(
                    label: 'Add',
                    expand: false,
                    onPressed: _addTyped,
                  ),
                ),
              ],
            ),
            if (_picked.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in _picked)
                    InputChip(
                      avatar: AppAvatar(
                        name: p['name'].toString(),
                        imageUrl: p['avatarUrl']?.toString(),
                        radius: 11,
                      ),
                      label: Text(p['name'].toString()),
                      onDeleted: () => setState(() => _picked.remove(p)),
                    ),
                ],
              ),
            ],
            if (!kIsWeb) ...[
              const SizedBox(height: AppSpacing.lg),
              AppButton.outline(
                label: 'Pick from phone contacts',
                icon: Icons.contacts_rounded,
                height: 48,
                loading: _loadingContacts,
                onPressed: _fromContacts,
              ),
            ],
            if (friends.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xl),
              const Text(
                'Your SplitShare friends',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                'They\'ll be able to open this group too.',
                style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final f in friends)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.trailing,
                  value: _picked.any((p) => p['uid'] == f['uid']),
                  onChanged: (_) => _toggleFriend(f),
                  secondary: AppAvatar(
                    name: (f['name'] ?? '?').toString(),
                    imageUrl: f['avatarUrl']?.toString(),
                    radius: 18,
                  ),
                  title: Text(
                    (f['name'] ?? 'Friend').toString(),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    (f['email'] ?? '').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: _picked.isEmpty
                  ? 'Add people'
                  : 'Add ${_picked.length} ${_picked.length == 1 ? 'person' : 'people'}',
              icon: Icons.check_rounded,
              onPressed: _picked.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(List<Map<String, dynamic>>.from(_picked)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Searchable multi-select list of contact names.
class _ContactsPicker extends StatefulWidget {
  final List<String> names;
  const _ContactsPicker({required this.names});

  @override
  State<_ContactsPicker> createState() => _ContactsPickerState();
}

class _ContactsPickerState extends State<_ContactsPicker> {
  final _search = TextEditingController();
  final _selected = <String>{};
  String _q = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = _q.isEmpty
        ? widget.names
        : widget.names.where((n) => n.toLowerCase().contains(_q)).toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
            child: AppSearchField(
              controller: _search,
              hint: 'Search contacts',
              onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text('No matching contacts',
                        style: TextStyle(color: AppColors.textSecondary)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final n = list[i];
                      return CheckboxListTile(
                        value: _selected.contains(n),
                        onChanged: (_) => setState(() =>
                            _selected.contains(n) ? _selected.remove(n) : _selected.add(n)),
                        secondary: AppAvatar(name: n, radius: 18),
                        title: Text(n, maxLines: 1, overflow: TextOverflow.ellipsis),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: AppButton(
              label: _selected.isEmpty ? 'Select people' : 'Add ${_selected.length}',
              onPressed: _selected.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(_selected.toList()),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rename / currency for a trip.
class EditTripSheet extends StatefulWidget {
  final Trip trip;
  const EditTripSheet({super.key, required this.trip});

  @override
  State<EditTripSheet> createState() => EditTripSheetState();
}

class EditTripSheetState extends State<EditTripSheet> {
  late final _title = TextEditingController(text: widget.trip.title);
  late String _currency = widget.trip.currencyCode;
  late String _type = widget.trip.icon;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await TripController.to
          .updateDetails(widget.trip.id,
              title: _title.text, currencyCode: _currency, icon: _type);
      if (!mounted) return;
      AppToast.success('Group updated.');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.error(e is TripException ? e.message : AppToast.friendly(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          GroupTypePicker(
            selected: _type,
            onChanged: (t) => setState(() => _type = t),
          ),
          const SizedBox(height: AppSpacing.xl),
          AppTextField(
            controller: _title,
            label: 'Group name',
            prefixIcon: GroupTypes.of(_type).icon,
            maxLength: 40,
            textCapitalization: TextCapitalization.sentences,
          ),
          const Text('Currency',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final code in Currencies.symbols.keys)
                ChoiceChip(
                  label: Text('${Currencies.symbolFor(code)} $code'),
                  selected: code == _currency,
                  onSelected: (_) => setState(() => _currency = code),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),
          AppButton(label: 'Save', loading: _saving, onPressed: _save),
        ],
      ),
    );
  }
}

/// Single text input sheet; pops with the entered text.
class _TextSheet extends StatefulWidget {
  final String initial;
  final String label;
  final String button;
  const _TextSheet({required this.initial, required this.label, required this.button});

  @override
  State<_TextSheet> createState() => _TextSheetState();
}

class _TextSheetState extends State<_TextSheet> {
  late final _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _ctrl.text.trim();
    if (v.isEmpty) {
      AppToast.warning('Enter a name.');
      return;
    }
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppTextField(
            controller: _ctrl,
            label: widget.label,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(label: widget.button, onPressed: _submit),
        ],
      ),
    );
  }
}

/// Small closing block: how much each person receives or gives in total.
class _FinalTally extends StatelessWidget {
  final Trip trip;
  final String Function(int cents) money;
  const _FinalTally({required this.trip, required this.money});

  @override
  Widget build(BuildContext context) {
    final receivers = trip.summary.where((s) => s.balanceCents > 0).toList()
      ..sort((a, b) => b.balanceCents.compareTo(a.balanceCents));
    final givers = trip.summary.where((s) => s.balanceCents < 0).toList()
      ..sort((a, b) => a.balanceCents.compareTo(b.balanceCents));
    final even = trip.summary.where((s) => s.balanceCents == 0).toList();

    Widget row(TripPersonSummary s, String verb, Color color) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              AppAvatar(name: s.person.name, imageUrl: s.person.avatarUrl, radius: 14),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${s.person.name} $verb',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
                ),
              ),
              if (s.balanceCents != 0)
                Text(
                  money(s.balanceCents.abs()),
                  style: TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w700, color: color),
                ),
            ],
          ),
        );

    Widget column(String title, IconData icon, Color color, List<Widget> rows) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 17, color: color),
                const SizedBox(width: 6),
                Text(title,
                    style: TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700, color: color)),
              ],
            ),
            const SizedBox(height: 4),
            ...rows,
          ],
        );

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (receivers.isEmpty && givers.isEmpty)
            Padding(
              padding: EdgeInsets.all(8),
              child: Text('Everyone is even — nobody gives or receives anything.',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
          if (receivers.isNotEmpty)
            column('Receiving', Icons.south_west_rounded, AppColors.positive, [
              for (final s in receivers) row(s, 'receives', AppColors.positive),
            ]),
          if (receivers.isNotEmpty && givers.isNotEmpty)
            Divider(height: 20, thickness: 1, color: AppColors.border),
          if (givers.isNotEmpty)
            column('Giving', Icons.north_east_rounded, AppColors.negative, [
              for (final s in givers) row(s, 'gives', AppColors.negative),
            ]),
          if (even.isNotEmpty && (receivers.isNotEmpty || givers.isNotEmpty))
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '${even.map((s) => Fmt.firstName(s.person.name)).join(', ')} '
                '${even.length == 1 ? 'is' : 'are'} even.',
                style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}

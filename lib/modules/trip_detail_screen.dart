import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';

import '../controllers/friend_controller.dart';
import '../controllers/trip_controller.dart';
import '../core/ui.dart';

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
        AppToast.info('They\'re already in this trip.');
      } else {
        AppToast.success('Added $added ${added == 1 ? 'person' : 'people'}.');
      }
    } catch (e) {
      AppToast.error(e is TripException ? e.message : AppToast.friendly(e));
    }
  }

  Future<void> _addPayment(Trip trip, {String? personId, TripPayment? edit}) async {
    if (trip.people.length < 2 && edit == null) {
      AppToast.info('Add the people on this trip first.', title: 'Who came?');
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
                iconColor: AppColors.secondary,
                title: 'Rename',
                onTap: () => Navigator.of(ctx).pop('rename'),
              ),
              if (person.uid != trip.ownerUid)
                AppListTile(
                  icon: Icons.person_remove_rounded,
                  title: 'Remove from trip',
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
          message: 'Their payments and pay-backs in this trip will be deleted '
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
          title: 'Trip details',
          child: _EditTripSheet(trip: trip),
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
          AppToast.success('Trip deleted.');
          Navigator.of(context).pop();
        } catch (e) {
          AppToast.error(AppToast.friendly(e));
        }
    }
  }

  // ------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    if (_id == null) return _unavailable('Trip');
    return StreamBuilder<Trip?>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(
            appBar: AppTopBar(title: _last?.title ?? 'Trip'),
            body: ErrorState(
              title: 'Couldn\'t load this trip',
              onRetry: _retry,
            ),
          );
        }
        if (snap.connectionState == ConnectionState.waiting && _last == null) {
          return const Scaffold(
            appBar: AppTopBar(title: 'Trip'),
            body: SkeletonList(count: 5),
          );
        }
        final trip = snap.data;
        if (trip == null) return _unavailable(_last?.title ?? 'Trip');
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
          title: 'This trip isn\'t available',
          message: 'It may have been deleted, or you were removed from it.',
          actionLabel: 'Go back',
          onAction: () => Navigator.of(context).maybePop(),
        ),
      );

  Widget _content(Trip trip) {
    final summary = trip.summary;
    final plan = TripMath.settlePlan(summary);
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
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete trip', style: TextStyle(color: AppColors.error)),
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
              'Log what each person paid. As soon as there are payments, '
              'SplitShare shows the fewest transfers to settle up.',
            )
          else if (plan.isEmpty)
            AppCard(
              color: AppColors.positiveLight,
              shadow: false,
              child: const Row(
                children: [
                  IconBadge(
                    icon: Icons.celebration_rounded,
                    color: AppColors.positive,
                    filled: true,
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Everyone is settled up!',
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
            for (var i = 0; i < plan.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: FadeSlideIn(
                  index: i,
                  child: _TransferCard(
                    from: trip.person(plan[i].fromId),
                    to: trip.person(plan[i].toId),
                    amount: _money(trip, plan[i].cents),
                    onPaid: () => _markPaid(trip, plan[i]),
                  ),
                ),
              ),

          // ---- People
          SectionHeader(
            title: 'People',
            actionLabel: 'Add people',
            onAction: () => _addPeople(trip),
            padding: const EdgeInsets.only(top: AppSpacing.xl, bottom: AppSpacing.md),
          ),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                for (var i = 0; i < summary.length; i++) ...[
                  if (i > 0) const Divider(indent: 70, endIndent: 16),
                  _PersonRow(
                    summary: summary[i],
                    money: (c) => _money(trip, c),
                    onTap: () => _personMenu(trip, summary[i].person),
                  ),
                ],
                if (trip.people.length < 2)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: AppButton.secondary(
                      label: 'Add the people on this trip',
                      icon: Icons.group_add_rounded,
                      height: 46,
                      onPressed: () => _addPeople(trip),
                    ),
                  ),
              ],
            ),
          ),

          // ---- Payments
          SectionHeader(
            title: 'Payments (${trip.payments.length})',
            padding: const EdgeInsets.only(top: AppSpacing.xl, bottom: AppSpacing.md),
          ),
          if (trip.payments.isEmpty)
            _hint(Icons.receipt_long_rounded,
                'No payments yet. Tap "Add payment" whenever someone pays.')
          else
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  for (var i = 0; i < trip.payments.length; i++) ...[
                    if (i > 0) const Divider(indent: 70, endIndent: 16),
                    _PaymentRow(
                      payment: trip.payments[i],
                      person: trip.person(trip.payments[i].personId),
                      amount: _money(trip, trip.payments[i].cents),
                      onTap: () => _addPayment(trip, edit: trip.payments[i]),
                    ),
                  ],
                ],
              ),
            ),

          // ---- Paid back
          if (trip.settlements.isNotEmpty) ...[
            const SectionHeader(
              title: 'Paid back',
              padding: EdgeInsets.only(top: AppSpacing.xl, bottom: AppSpacing.md),
            ),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  for (final s in trip.settlements)
                    ListTile(
                      leading: const IconBadge(
                        icon: Icons.check_rounded,
                        color: AppColors.positive,
                        size: 40,
                        iconSize: 20,
                      ),
                      title: Text(
                        '${trip.nameOf(s.fromId)} paid ${trip.nameOf(s.toId)}',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
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
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, 12, AppSpacing.page, 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            boxShadow: AppShadows.soft,
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
    final each = n == 0 ? 0 : trip.totalCents / n / 100;
    return AppCard(
      gradient: AppColors.heroGradient,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total spent',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _money(trip, trip.totalCents),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              _heroStat('Each person', Fmt.money(each, currencyCode: trip.currencyCode)),
              _heroStat('People', '$n'),
              _heroStat('Payments', '${trip.payments.length}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroStat(String label, String value) => Expanded(
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _hint(IconData icon, String text) => AppCard(
        color: AppColors.surfaceMuted,
        shadow: false,
        child: Row(
          children: [
            Icon(icon, color: AppColors.textMuted, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(text,
                  style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary)),
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
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        children: [
          Row(
            children: [
              AppAvatar(name: fromName, imageUrl: from?.avatarUrl, radius: 20),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    children: [
                      Text(
                        amount,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 2,
                              decoration: const BoxDecoration(
                                gradient: AppColors.brandGradient,
                              ),
                            ),
                          ),
                          const Icon(Icons.arrow_forward_rounded,
                              size: 18, color: AppColors.secondary),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              AppAvatar(name: toName, imageUrl: to?.avatarUrl, radius: 20),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                    children: [
                      TextSpan(
                        text: fromName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, color: AppColors.negative),
                      ),
                      const TextSpan(text: ' pays '),
                      TextSpan(
                        text: toName,
                        style: const TextStyle(
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
                child: FilledButton.tonalIcon(
                  onPressed: onPaid,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Mark paid'),
                  style: FilledButton.styleFrom(
                    foregroundColor: AppColors.positive,
                    backgroundColor: AppColors.positiveLight,
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

class _PersonRow extends StatelessWidget {
  final TripPersonSummary summary;
  final String Function(int cents) money;
  final VoidCallback onTap;

  const _PersonRow({required this.summary, required this.money, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final b = summary.balanceCents;
    final Color color;
    final String caption;
    if (b > 0) {
      color = AppColors.positive;
      caption = 'gets back';
    } else if (b < 0) {
      color = AppColors.negative;
      caption = 'owes';
    } else {
      color = AppColors.textMuted;
      caption = 'settled';
    }
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            AppAvatar(
              name: summary.person.name,
              imageUrl: summary.person.avatarUrl,
              radius: 21,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          summary.person.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (summary.person.uid != null) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.verified_rounded,
                            size: 14, color: AppColors.primary),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Paid ${money(summary.paidCents)} · Share ${money(summary.shareCents)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  caption,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: color.withValues(alpha: 0.85),
                  ),
                ),
                if (b != 0)
                  Text(
                    money(b.abs()),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  final TripPayment payment;
  final TripPerson? person;
  final String amount;
  final VoidCallback onTap;

  const _PaymentRow({
    required this.payment,
    required this.person,
    required this.amount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = person?.name ?? 'Someone';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${payment.note.isEmpty ? '' : '$name · '}${Fmt.relative(payment.at)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              amount,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =================================================================== sheets

/// Add/edit a payment: who paid, how much, what for.
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
  );
  late final _note = TextEditingController(text: widget.edit?.note ?? '');
  late String? _personId = widget.edit?.personId ?? widget.initialPersonId;
  bool _saving = false;

  static String _plain(double v) {
    var s = v.toStringAsFixed(2);
    if (s.endsWith('00')) return s.substring(0, s.length - 3);
    if (s.endsWith('0')) s = s.substring(0, s.length - 1);
    return s;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save({bool addAnother = false}) async {
    if (_saving) return;
    if (_personId == null) {
      AppToast.warning('Choose who paid.');
      return;
    }
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final amount = double.parse(_amount.text.trim());
    try {
      final ctrl = TripController.to;
      if (widget.edit == null) {
        await ctrl.addPayment(widget.trip.id,
            personId: _personId!, amount: amount, note: _note.text);
      } else {
        await ctrl.updatePayment(widget.trip.id, widget.edit!.id,
            personId: _personId!, amount: amount, note: _note.text);
      }
      if (!mounted) return;
      final who = widget.trip.nameOf(_personId!);
      AppToast.success(
          '$who paid ${Fmt.money(amount, currencyCode: widget.trip.currencyCode)}.',
          title: widget.edit == null ? 'Payment added' : 'Payment updated');
      if (addAnother) {
        setState(() {
          _saving = false;
          _amount.clear();
          _note.clear();
          _personId = null;
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
      message: 'Everyone\'s shares will be recalculated.',
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

  @override
  Widget build(BuildContext context) {
    final symbol = Currencies.symbolFor(widget.trip.currencyCode);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Who paid?',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in widget.trip.people)
                  ChoiceChip(
                    avatar: AppAvatar(name: p.name, imageUrl: p.avatarUrl, radius: 11),
                    label: Text(p.name),
                    selected: p.id == _personId,
                    onSelected: (_) => setState(() => _personId = p.id),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            AppTextField(
              controller: _amount,
              label: 'Amount',
              hint: '0',
              prefixIcon: Icons.payments_rounded,
              suffix: Padding(
                padding: const EdgeInsets.only(right: 16, top: 14),
                child: Text(symbol,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [amountInputFormatter],
              autofocus: widget.edit == null && _personId != null,
              validator: Validators.amount,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              controller: _note,
              label: 'What for? (optional)',
              hint: 'e.g. Petrol, dinner, hotel',
              prefixIcon: Icons.notes_rounded,
              maxLength: 60,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: AppSpacing.lg),
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
              const Text(
                'They\'ll be able to open this trip too.',
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
                ? const Center(
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
class _EditTripSheet extends StatefulWidget {
  final Trip trip;
  const _EditTripSheet({required this.trip});

  @override
  State<_EditTripSheet> createState() => _EditTripSheetState();
}

class _EditTripSheetState extends State<_EditTripSheet> {
  late final _title = TextEditingController(text: widget.trip.title);
  late String _currency = widget.trip.currencyCode;
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
          .updateDetails(widget.trip.id, title: _title.text, currencyCode: _currency);
      if (!mounted) return;
      AppToast.success('Trip updated.');
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
          AppTextField(
            controller: _title,
            label: 'Trip name',
            prefixIcon: Icons.luggage_rounded,
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

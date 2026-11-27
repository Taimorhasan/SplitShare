import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/expense_controller.dart';
import '../controllers/friend_controller.dart';
import '../controllers/profile_controller.dart';
import '../app/routes/app_routes.dart';
import '../controllers/shell_controller.dart';
import '../controllers/trip_controller.dart';
import '../core/ui.dart';

/// Lists everyone the user owes / who owes the user, and records payments.
///
/// Arguments (optional): `{'uid': String}` → opens that person's payment
/// sheet once balances are available.
class SettleUpScreen extends StatefulWidget {
  const SettleUpScreen({super.key});

  @override
  State<SettleUpScreen> createState() => _SettleUpScreenState();
}

class _SettleUpScreenState extends State<SettleUpScreen> {
  String? _autoUid;
  bool _autoHandled = false;
  Worker? _loadingWorker;

  ExpenseController get _ctrl => ExpenseController.to;

  @override
  void initState() {
    super.initState();
    final args = Get.arguments;
    final uid = args is Map ? args['uid']?.toString() : null;
    if (uid != null && uid.isNotEmpty) {
      _autoUid = uid;
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoOpen());
    }
  }

  @override
  void dispose() {
    _loadingWorker?.dispose();
    super.dispose();
  }

  void _maybeAutoOpen() {
    final uid = _autoUid;
    if (!mounted || uid == null || _autoHandled) return;
    if (_ctrl.isLoading.value) {
      _loadingWorker ??= ever<bool>(_ctrl.isLoading, (loading) {
        if (!loading) {
          // Balances are published a frame after loading flips; give them a moment.
          Future.delayed(const Duration(milliseconds: 250), _maybeAutoOpen);
        }
      });
      return;
    }
    _autoHandled = true;
    _loadingWorker?.dispose();
    _loadingWorker = null;

    final entry = _ctrl.settleUpData[uid];
    if (entry == null) {
      final friend = FriendController.to.friendByUid(uid);
      var name = (friend?['name'] ?? _ctrl.nameFor(uid)).toString();
      if (name == 'Unknown' || name.isEmpty) name = 'them';
      AppToast.info('You\'re all settled with $name', title: 'Nothing to settle');
      return;
    }
    final byCurrency = Map<String, double>.from(entry['byCurrency'] as Map);
    final pref = ProfileController.to.currencyCode.value;
    final primary = byCurrency[pref] ??
        byCurrency.values.reduce((a, b) => a.abs() >= b.abs() ? a : b);
    _openSheet(
      uid: uid,
      name: (entry['name'] ?? 'Friend').toString(),
      avatarUrl: (entry['avatarUrl'] ?? '').toString(),
      iOwe: primary < 0,
    );
  }

  void _openSheet({
    required String uid,
    required String name,
    required String avatarUrl,
    required bool iOwe,
  }) {
    AppDialogs.sheet<void>(
      title: iOwe ? 'Pay ${Fmt.firstName(name)}' : 'Record a payment',
      child: _PaymentSheet(uid: uid, name: name, avatarUrl: avatarUrl, iOwe: iOwe),
    );
  }

  /// Everyone I have a balance with, combining friends/groups expenses and
  /// every Lain Dain trip, netted per person and currency.
  List<_Combined> _combine() {
    final byKey = <String, _Combined>{};
    for (final entry in _ctrl.settleUpData.values) {
      final raw = entry['byCurrency'];
      if (raw is! Map) continue;
      final uid = (entry['uid'] ?? '').toString();
      final c = byKey.putIfAbsent(
        uid,
        () => _Combined(
          key: uid,
          uid: uid,
          name: (entry['name'] ?? 'Friend').toString(),
          avatarUrl: (entry['avatarUrl'] ?? '').toString(),
        ),
      );
      c.expenses.addAll(Map<String, double>.from(raw));
    }
    TripController.to.myBalances().forEach((key, t) {
      final c = byKey.putIfAbsent(
        key,
        () => _Combined(key: key, uid: t.uid, name: t.name, avatarUrl: t.avatarUrl),
      );
      t.byCurrency.forEach((cur, v) => c.trips[cur] = (c.trips[cur] ?? 0) + v);
      c.tripLines.addAll(t.trips);
      if (c.avatarUrl.isEmpty) c.avatarUrl = t.avatarUrl;
    });
    final list = byKey.values.where((c) => c.total.isNotEmpty).toList();
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const AppTopBar(title: 'Settle up', subtitle: 'Friends & groups'),
      body: Obx(() {
        final pref = ProfileController.to.currencyCode.value;
        // Reactive dependencies.
        _ctrl.settleUpData.length;
        TripController.to.trips.length;
        final people = _combine();
        final Widget child;

        if (_ctrl.isLoading.value && people.isEmpty) {
          child = const _SettleSkeleton(key: ValueKey('loading'));
        } else if (_ctrl.hasError.value && people.isEmpty) {
          child = ErrorState(
            key: const ValueKey('error'),
            onRetry: _ctrl.refreshData,
          );
        } else if (people.isEmpty) {
          child = EmptyState(
            key: const ValueKey('empty'),
            icon: Icons.celebration_rounded,
            color: AppColors.positive,
            orbitIcons: const [
              Icons.check_circle_rounded,
              Icons.favorite_rounded,
              Icons.star_rounded,
            ],
            title: 'All settled up!',
            message: 'Nobody owes anything right now, with friends or in groups.',
            actionLabel: 'Add expense',
            actionIcon: Icons.add_rounded,
            onAction: () => AppNav.addExpense(),
          );
        } else {
          double key(_Combined c) {
            final m = c.total;
            return (m[pref] ?? m.values.fold<double>(0, (a, b) => a.abs() >= b.abs() ? a : b));
          }

          final give = people.where((c) => key(c) < 0).toList()
            ..sort((a, b) => key(a).compareTo(key(b)));
          final receive = people.where((c) => key(c) > 0).toList()
            ..sort((a, b) => key(b).compareTo(key(a)));

          final owe = <String, double>{};
          final owed = <String, double>{};
          for (final c in people) {
            c.total.forEach((cur, v) {
              if (v < 0) {
                owe[cur] = (owe[cur] ?? 0) - v;
              } else {
                owed[cur] = (owed[cur] ?? 0) + v;
              }
            });
          }

          var index = 0;
          child = RefreshIndicator(
            key: const ValueKey('data'),
            color: AppColors.primary,
            onRefresh: () async {
              TripController.to.fetchTrips();
              await _ctrl.refreshData();
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                AppSpacing.sm,
                AppSpacing.page,
                AppSpacing.xxxl,
              ),
              children: [
                FadeSlideIn(
                  index: index++,
                  child: _SummaryCard(owe: owe, owed: owed, preferred: pref),
                ),
                if (give.isNotEmpty) ...[
                  SectionHeader(
                    title: 'You have to give (${give.length})',
                    padding:
                        const EdgeInsets.only(top: AppSpacing.xxl, bottom: AppSpacing.md),
                  ),
                  FadeSlideIn(
                    index: index++,
                    child: _PeopleCard(
                      children: [
                        for (final c in give)
                          _CombinedTile(
                        person: c,
                        preferred: pref,
                        onRecord: c.uid == null || c.expenses.isEmpty
                            ? null
                            : () => _openSheet(
                                  uid: c.uid!,
                                  name: c.name,
                                  avatarUrl: c.avatarUrl,
                                  iOwe: (c.expenses[pref] ??
                                          c.expenses.values.first) <
                                      0,
                                ),
                          ),
                      ],
                    ),
                  ),
                ],
                if (receive.isNotEmpty) ...[
                  SectionHeader(
                    title: 'You will receive (${receive.length})',
                    padding:
                        const EdgeInsets.only(top: AppSpacing.xxl, bottom: AppSpacing.md),
                  ),
                  FadeSlideIn(
                    index: index++,
                    child: _PeopleCard(
                      children: [
                        for (final c in receive)
                          _CombinedTile(
                        person: c,
                        preferred: pref,
                        onRecord: c.uid == null || c.expenses.isEmpty
                            ? null
                            : () => _openSheet(
                                  uid: c.uid!,
                                  name: c.name,
                                  avatarUrl: c.avatarUrl,
                                  iOwe: (c.expenses[pref] ??
                                          c.expenses.values.first) <
                                      0,
                                ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        }

        return AnimatedSwitcher(duration: AppMotion.normal, child: child);
      }),
    );
  }
}

/// One person's combined position with me.
class _Combined {
  final String key;
  final String? uid;
  final String name;
  String avatarUrl;

  /// Signed, positive = they owe me.
  final Map<String, double> expenses = {};
  final Map<String, double> trips = {};
  final List<({String tripId, String title, double amount, String currency})> tripLines =
      [];

  _Combined({required this.key, required this.uid, required this.name, required this.avatarUrl});

  /// Expenses + Lain Dain, cancelled against each other.
  Map<String, double> get total {
    final m = <String, double>{...expenses};
    trips.forEach((cur, v) => m[cur] = (m[cur] ?? 0) + v);
    m.removeWhere((_, v) => v.abs() < 0.005);
    return m;
  }
}

// ==================================================================== widgets

class _SummaryCard extends StatelessWidget {
  final Map<String, double> owe;
  final Map<String, double> owed;
  final String preferred;

  const _SummaryCard({
    required this.owe,
    required this.owed,
    required this.preferred,
  });

  @override
  Widget build(BuildContext context) {
    final net = (owed[preferred] ?? 0) - (owe[preferred] ?? 0);
    final label = net > 0.005
        ? 'Overall, you are owed'
        : net < -0.005
            ? 'Overall, you owe'
            : 'Net balance';
    final others = <String, double>{};
    for (final c in {...owe.keys, ...owed.keys}) {
      if (c == preferred) continue;
      final v = (owed[c] ?? 0) - (owe[c] ?? 0);
      if (v.abs() >= 0.005) others[c] = v;
    }
    var caption = 'You get back ${Fmt.multi(owed, preferred: preferred)}'
        ' · you owe ${Fmt.multi(owe, preferred: preferred)}'
        '\nIncludes friends and groups';
    if (others.isNotEmpty) {
      caption = 'Net ${Fmt.multi(others, preferred: preferred, absolute: false)}'
          ' in other currencies\n$caption';
    }
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: KhataTotal(
        label: label,
        amount: Fmt.money(net.abs(), currencyCode: preferred),
        caption: caption,
        color: net < -0.005 ? AppColors.negative : null,
      ),
    );
  }
}

/// One section's people: rows in a single ruled block.
class _PeopleCard extends StatelessWidget {
  final List<Widget> children;
  const _PeopleCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Divider(height: 1, thickness: 1, color: AppColors.border),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// One person: the overall amount (after cancelling everything) plus where
/// it comes from — friends & groups, and each Lain Dain trip.
class _CombinedTile extends StatelessWidget {
  final _Combined person;
  final String preferred;
  final VoidCallback? onRecord;

  const _CombinedTile({
    required this.person,
    required this.preferred,
    required this.onRecord,
  });

  @override
  Widget build(BuildContext context) {
    final total = person.total;
    final primary =
        total[preferred] ?? total.values.fold<double>(0, (a, b) => a.abs() >= b.abs() ? a : b);
    final iGive = primary < 0;
    final tone = iGive ? AppColors.negative : AppColors.positive;
    final first = Fmt.firstName(person.name);
    final amount = Fmt.multi(total, preferred: preferred);
    final headline = iGive ? 'You give $first' : '$first gives you';

    String part(Map<String, double> m) {
      final v = m[preferred] ?? (m.isEmpty ? 0 : m.values.first);
      final text = Fmt.multi(m, preferred: preferred);
      return v < 0 ? 'you owe $text' : '$first owes you $text';
    }

    Widget line(IconData icon, String label, String value, {VoidCallback? onTap}) =>
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
            child: Row(
              children: [
                Icon(icon, size: 16, color: AppColors.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    value,
                    textAlign: TextAlign.end,
                    maxLines: 2,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (onTap != null)
                  Icon(Icons.chevron_right_rounded,
                      size: 18, color: AppColors.textMuted),
              ],
            ),
          ),
        );

    final hasBoth = person.expenses.isNotEmpty && person.tripLines.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md + 2,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AppAvatar(name: person.name, imageUrl: person.avatarUrl, radius: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        person.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasBoth ? 'Total after cancelling everything' : 'In total',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      headline,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: tone,
                      ),
                    ),
                    Text(
                      amount,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: iGive ? AppColors.negative : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.only(left: 52),
              child: Column(
                children: [
                  if (person.expenses.isNotEmpty)
                    line(Icons.receipt_long_rounded, 'Friends & groups',
                        part(person.expenses)),
                  for (final t in person.tripLines)
                    line(
                      Icons.luggage_rounded,
                      'Group · ${t.title}',
                      part({t.currency: t.amount}),
                      onTap: () =>
                          Get.toNamed(AppRoutes.tripDetail, arguments: {'id': t.tripId}),
                    ),
                ],
              ),
            ),
            if (onRecord != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: iGive ? 'Pay $first' : 'Record / remind',
                      icon: iGive ? Icons.send_rounded : Icons.handshake_rounded,
                      height: 44,
                      variant:
                          iGive ? AppButtonVariant.primary : AppButtonVariant.success,
                      onPressed: onRecord,
                    ),
                  ),
                ],
              ),
              if (person.tripLines.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Payments here settle shared expenses. Mark group '
                    'pay-backs inside the group.',
                    style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                  ),
                ),
            ] else if (person.tripLines.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Tap a group to mark the pay-back there.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                ),
              ),
          ],
        ),
    );
  }
}

class _PaymentSheet extends StatefulWidget {
  final String uid;
  final String name;
  final String avatarUrl;

  /// True when the current user owes [name] (so the user is paying).
  final bool iOwe;

  const _PaymentSheet({
    required this.uid,
    required this.name,
    required this.avatarUrl,
    required this.iOwe,
  });

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  /// Absolute outstanding balance per currency in this sheet's direction.
  late final Map<String, double> _balances;
  late final List<String> _currencies;
  String? _currency;

  /// Which action is running: 'record' | 'settle' | 'remind'.
  String? _busy;

  ExpenseController get _ctrl => ExpenseController.to;

  @override
  void initState() {
    super.initState();
    final all = _ctrl.balanceWith(widget.uid);
    _balances = {
      for (final e in all.entries)
        if (widget.iOwe ? e.value < -0.005 : e.value > 0.005) e.key: e.value.abs(),
    };
    final pref = ProfileController.to.currencyCode.value;
    _currencies = _balances.keys.toList()
      ..sort((a, b) {
        if (a == pref) return -1;
        if (b == pref) return 1;
        return a.compareTo(b);
      });
    if (_currencies.isNotEmpty) _selectCurrency(_currencies.first);
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  static String _plain(double v) {
    final s = v.toStringAsFixed(2);
    return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
  }

  void _selectCurrency(String code) {
    _currency = code;
    _amountCtrl.text = _plain(_balances[code] ?? 0);
  }

  String get _first => Fmt.firstName(widget.name);

  String? _validateAmount(String? v) {
    final value = double.tryParse((v ?? '').trim());
    if (value == null || value <= 0) return 'Enter an amount above zero';
    final balance = _balances[_currency] ?? 0;
    if (value > balance + 0.01) {
      return 'That\'s more than the ${Fmt.money(balance, currencyCode: _currency)} balance';
    }
    return null;
  }

  Future<void> _record() async {
    if (_busy != null || _currency == null) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final amount = double.parse(_amountCtrl.text.trim());
    final currency = _currency!;
    setState(() => _busy = 'record');
    try {
      await _ctrl.recordPayment(
        friendUid: widget.uid,
        friendName: widget.name,
        amount: amount,
        currencyCode: currency,
        iPaid: widget.iOwe,
        note: _noteCtrl.text,
      );
      if (!mounted) return;
      final money = Fmt.money(amount, currencyCode: currency);
      await AppDialogs.success(
        title: 'Payment recorded',
        message: widget.iOwe ? 'You paid $_first $money' : '$_first paid you $money',
      );
      if (mounted) Navigator.of(context).pop();
    } on ExpenseValidationException catch (e) {
      AppToast.warning(e.message);
    } catch (e) {
      AppToast.error(AppToast.friendly(e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _settleAll() async {
    if (_busy != null) return;
    final all = _ctrl.balanceWith(widget.uid);
    final ok = await AppDialogs.confirm(
      title: 'Settle everything with $_first?',
      message: 'This marks every open expense between you and ${widget.name} as '
          'settled in all currencies'
          '${all.isEmpty ? '' : ' (${Fmt.multi(all, preferred: _currency ?? 'USD', absolute: false)})'}. '
          'Use it when the full balance was paid outside the app.',
      confirmLabel: 'Settle all',
      icon: Icons.handshake_rounded,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = 'settle');
    try {
      final count = await _ctrl.settleUpWithFriend(widget.uid);
      if (!mounted) return;
      if (count == 0) {
        Navigator.of(context).pop();
        AppToast.info('You\'re already settled with $_first');
        return;
      }
      await AppDialogs.success(
        title: 'All settled!',
        message: 'You and $_first are now settled up.',
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      AppToast.error(AppToast.friendly(e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _remind() async {
    if (_busy != null) return;
    setState(() => _busy = 'remind');
    try {
      await _ctrl.sendReminder(widget.uid);
      if (!mounted) return;
      Navigator.of(context).pop();
      AppToast.success('We\'ve nudged $_first about the balance', title: 'Reminder sent');
    } on ExpenseValidationException catch (e) {
      AppToast.warning(e.message);
    } catch (e) {
      AppToast.error(AppToast.friendly(e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ProfileController.to;
    final myName = profile.name.value.isEmpty ? 'You' : profile.name.value;

    Widget person(String name, String label, String avatar) => Expanded(
          child: Column(
            children: [
              AppAvatar(name: name, imageUrl: avatar, radius: 28),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        );

    final me = person(myName, 'You', profile.avatarUrl.value);
    final them = person(widget.name, _first, widget.avatarUrl);

    if (_currencies.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconBadge(
              icon: Icons.verified_rounded,
              color: AppColors.positive,
              size: 60,
              iconSize: 30,
            ),
            const SizedBox(height: 14),
            Text(
              'You\'re all settled with $_first',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 20),
            AppButton.outline(
              label: 'Close',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
    }

    final busy = _busy != null;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              child: Row(
                children: [
                  if (widget.iOwe) me else them,
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: AppColors.textSecondary,
                    size: 24,
                  ),
                  if (widget.iOwe) them else me,
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.iOwe ? 'You → $_first' : '$_first → You',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            if (_currencies.length > 1) ...[
              const SizedBox(height: 18),
              Text(
                'Currency',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final code in _currencies)
                    _CurrencyChip(
                      label: '$code · ${Fmt.money(_balances[code]!, currencyCode: code)}',
                      selected: code == _currency,
                      onTap: busy
                          ? null
                          : () => setState(() => _selectCurrency(code)),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            AppTextField(
              controller: _amountCtrl,
              label: 'Amount (${Currencies.symbolFor(_currency)})',
              prefixIcon: Icons.payments_rounded,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [amountInputFormatter],
              validator: _validateAmount,
              enabled: !busy,
              helperText:
                  'Full balance: ${Fmt.money(_balances[_currency] ?? 0, currencyCode: _currency)} · edit for a partial payment',
            ),
            const SizedBox(height: 14),
            AppTextField(
              controller: _noteCtrl,
              hint: 'Add a note (optional)',
              prefixIcon: Icons.sticky_note_2_outlined,
              maxLength: 120,
              enabled: !busy,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 8),
            AppButton(
              label: 'Record payment',
              icon: Icons.check_rounded,
              variant: AppButtonVariant.success,
              loading: _busy == 'record',
              onPressed: busy && _busy != 'record' ? null : _record,
            ),
            if (!widget.iOwe) ...[
              const SizedBox(height: 10),
              AppButton.secondary(
                label: 'Send reminder',
                icon: Icons.notifications_active_rounded,
                loading: _busy == 'remind',
                onPressed: busy && _busy != 'remind' ? null : _remind,
              ),
            ],
            const SizedBox(height: 10),
            AppButton.outline(
              label: 'Settle all balances',
              icon: Icons.handshake_rounded,
              loading: _busy == 'settle',
              onPressed: busy && _busy != 'settle' ? null : _settleAll,
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrencyChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _CurrencyChip({required this.label, required this.selected, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.normal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: selected ? AppColors.primary : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.onPrimary : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _SettleSkeleton extends StatelessWidget {
  const _SettleSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, 0),
      children: const [
        Skeleton(width: 120, height: 12),
        SizedBox(height: 8),
        Skeleton(width: 200, height: 40),
        SizedBox(height: 12),
        Skeleton(width: 240, height: 12),
        SizedBox(height: 28),
        Skeleton(width: 90, height: 16),
        SizedBox(height: 14),
        SkeletonList(count: 4, shrinkWrap: true, padding: EdgeInsets.zero),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/expense_controller.dart';
import '../controllers/friend_controller.dart';
import '../controllers/profile_controller.dart';
import '../controllers/shell_controller.dart';
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

class _BalanceRow {
  final String uid;
  final String name;
  final String avatarUrl;

  /// Signed amounts (positive = owed to me), only one direction per row.
  final Map<String, double> byCurrency;
  final double sortKey;

  const _BalanceRow(this.uid, this.name, this.avatarUrl, this.byCurrency, this.sortKey);
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

  ({List<_BalanceRow> owe, List<_BalanceRow> owed}) _split(String pref) {
    final owe = <_BalanceRow>[];
    final owed = <_BalanceRow>[];
    for (final entry in _ctrl.settleUpData.values) {
      final raw = entry['byCurrency'];
      if (raw is! Map) continue;
      final map = Map<String, double>.from(raw);
      final neg = Map.fromEntries(map.entries.where((e) => e.value < -0.005));
      final pos = Map.fromEntries(map.entries.where((e) => e.value > 0.005));
      double key(Map<String, double> m) =>
          (m[pref] ?? m.values.fold<double>(0.0, (a, b) => a.abs() >= b.abs() ? a : b)).abs();
      final uid = (entry['uid'] ?? '').toString();
      final name = (entry['name'] ?? 'Friend').toString();
      final avatar = (entry['avatarUrl'] ?? '').toString();
      if (neg.isNotEmpty) owe.add(_BalanceRow(uid, name, avatar, neg, key(neg)));
      if (pos.isNotEmpty) owed.add(_BalanceRow(uid, name, avatar, pos, key(pos)));
    }
    owe.sort((a, b) => b.sortKey.compareTo(a.sortKey));
    owed.sort((a, b) => b.sortKey.compareTo(a.sortKey));
    return (owe: owe, owed: owed);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const AppTopBar(title: 'Settle up'),
      body: Obx(() {
        final pref = ProfileController.to.currencyCode.value;
        final data = _ctrl.settleUpData;
        final Widget child;

        if (_ctrl.isLoading.value && data.isEmpty) {
          child = const _SettleSkeleton(key: ValueKey('loading'));
        } else if (_ctrl.hasError.value && data.isEmpty) {
          child = ErrorState(
            key: const ValueKey('error'),
            onRetry: _ctrl.refreshData,
          );
        } else if (data.isEmpty) {
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
            message: 'Nobody owes anything right now. Add an expense when you share a bill.',
            actionLabel: 'Add expense',
            actionIcon: Icons.add_rounded,
            onAction: () => AppNav.addExpense(),
          );
        } else {
          final groups = _split(pref);
          var index = 0;
          child = RefreshIndicator(
            key: const ValueKey('data'),
            color: AppColors.primary,
            onRefresh: _ctrl.refreshData,
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
                  child: _SummaryCard(
                    owe: Map<String, double>.from(_ctrl.iOweByCurrency),
                    owed: Map<String, double>.from(_ctrl.owedToMeByCurrency),
                    preferred: pref,
                  ),
                ),
                if (groups.owe.isNotEmpty) ...[
                  const SectionHeader(
                    title: 'You owe',
                    padding: EdgeInsets.only(top: AppSpacing.xxl, bottom: AppSpacing.md),
                  ),
                  for (final row in groups.owe)
                    FadeSlideIn(
                      index: index++,
                      child: _PersonBalanceTile(
                        row: row,
                        preferred: pref,
                        onTap: () => _openSheet(
                          uid: row.uid,
                          name: row.name,
                          avatarUrl: row.avatarUrl,
                          iOwe: true,
                        ),
                      ),
                    ),
                ],
                if (groups.owed.isNotEmpty) ...[
                  const SectionHeader(
                    title: 'Owes you',
                    padding: EdgeInsets.only(top: AppSpacing.xxl, bottom: AppSpacing.md),
                  ),
                  for (final row in groups.owed)
                    FadeSlideIn(
                      index: index++,
                      child: _PersonBalanceTile(
                        row: row,
                        preferred: pref,
                        onTap: () => _openSheet(
                          uid: row.uid,
                          name: row.name,
                          avatarUrl: row.avatarUrl,
                          iOwe: false,
                        ),
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
    Widget column(String label, Map<String, double> m, IconData icon) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 15, color: Colors.white.withValues(alpha: 0.8)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                Fmt.multi(m, preferred: preferred),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        );

    return AppCard(
      gradient: AppColors.heroGradient,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                column('You owe', owe, Icons.call_made_rounded),
                Container(
                  width: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  color: Colors.white.withValues(alpha: 0.2),
                ),
                column('You are owed', owed, Icons.call_received_rounded),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.touch_app_rounded, size: 14, color: Colors.white),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Tap a person to record a payment',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonBalanceTile extends StatelessWidget {
  final _BalanceRow row;
  final String preferred;
  final VoidCallback onTap;

  const _PersonBalanceTile({
    required this.row,
    required this.preferred,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final iOwe = row.byCurrency.values.any((v) => v < 0);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            AppAvatar(name: row.name, imageUrl: row.avatarUrl, radius: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    iOwe ? 'Tap to pay' : 'Tap to record or remind',
                    style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: BalanceLabel(byCurrency: row.byCurrency, preferredCurrency: preferred),
            ),
          ],
        ),
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
                style: const TextStyle(
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
            const IconBadge(
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
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Row(
                children: [
                  if (widget.iOwe) me else them,
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      gradient: AppColors.positiveGradient,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
                  ),
                  if (widget.iOwe) them else me,
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.iOwe ? 'You → $_first' : '$_first → You',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            if (_currencies.length > 1) ...[
              const SizedBox(height: 18),
              const Text(
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
            color: selected ? Colors.white : AppColors.textPrimary,
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
        Skeleton(height: 132, radius: AppRadius.lg),
        SizedBox(height: 28),
        Skeleton(width: 90, height: 16),
        SizedBox(height: 14),
        SkeletonList(count: 4, shrinkWrap: true, padding: EdgeInsets.zero),
      ],
    );
  }
}

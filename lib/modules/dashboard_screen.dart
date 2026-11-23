import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../app/routes/app_routes.dart';
import '../controllers/expense_controller.dart';
import '../controllers/friend_controller.dart';
import '../controllers/group_controller.dart';
import '../controllers/notification_controller.dart';
import '../controllers/profile_controller.dart';
import '../controllers/shell_controller.dart';
import '../core/ui.dart';
import 'widgets/expense_tile.dart';

/// Home tab: greeting, balance overview, quick actions, monthly insight,
/// people balances and recent activity.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ec = ExpenseController.to;
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: ec.refreshData,
        child: Obx(() {
          final loading = ec.isLoading.value;
          final error = ec.hasError.value;
          final isNew = ec.recentActivity.isEmpty && ec.settleUpData.isEmpty;

          final String stateKey;
          final Widget body;
          if (error && isNew) {
            stateKey = 'error';
            body = Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxxl),
              child: ErrorState(
                title: 'Couldn\'t load your balances',
                onRetry: ec.refreshData,
              ),
            );
          } else if (loading && isNew) {
            stateKey = 'loading';
            body = const _DashboardSkeleton();
          } else if (isNew) {
            stateKey = 'new';
            body = const _NewUserContent();
          } else {
            stateKey = 'content';
            body = const _DashboardContent();
          }

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: AppSpacing.xxxl * 2),
            children: [
              const FadeSlideIn(child: _Header()),
              AnimatedSwitcher(
                duration: AppMotion.normal,
                switchInCurve: AppMotion.curve,
                child: KeyedSubtree(key: ValueKey(stateKey), child: body),
              ),
            ],
          );
        }),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header();

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final profile = ProfileController.to;
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.md,
        AppSpacing.page,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Obx(
                  () => Text(
                    '${_greeting()}, ${Fmt.firstName(profile.name.value)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.headlineSmall,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Here\'s where you stand today',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Obx(
            () => AppIconButton(
              icon: Icons.notifications_none_rounded,
              tooltip: 'Notifications',
              badgeCount: NotificationController.to.unreadCount,
              onPressed: () => Get.toNamed(AppRoutes.notifications),
            ),
          ),
          const SizedBox(width: AppSpacing.sm + 2),
          Tooltip(
            message: 'Profile',
            child: Pressable(
              onTap: () => AppNav.toTab(AppTab.profile),
              child: Obx(
                () => Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: AppShadows.soft,
                  ),
                  child: AppAvatar(
                    name: profile.name.value,
                    imageUrl: profile.avatarUrl.value,
                    radius: 22,
                    ring: true,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Main content
// ---------------------------------------------------------------------------

class _DashboardContent extends StatelessWidget {
  const _DashboardContent();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FadeSlideIn(index: 1, child: _HeroBalanceCard()),
        FadeSlideIn(index: 2, child: _QuickActions()),
        FadeSlideIn(index: 3, child: _MonthInsight()),
        FadeSlideIn(index: 4, child: _BalancesSection()),
        FadeSlideIn(index: 5, child: _RecentActivitySection()),
      ],
    );
  }
}

/// Animated money value: counts smoothly to the new amount on change.
class _AnimatedMoney extends StatelessWidget {
  final double value;
  final String currency;
  final TextStyle? style;
  final bool signed;

  const _AnimatedMoney({
    required this.value,
    required this.currency,
    this.style,
    this.signed = false,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: const Duration(milliseconds: 700),
      curve: AppMotion.curve,
      builder: (_, v, _) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          Fmt.money(v, currencyCode: currency, signed: signed),
          maxLines: 1,
          style: style,
        ),
      ),
    );
  }
}

class _HeroBalanceCard extends StatelessWidget {
  const _HeroBalanceCard();

  @override
  Widget build(BuildContext context) {
    final ec = ExpenseController.to;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.md,
        AppSpacing.page,
        0,
      ),
      child: Obx(() {
        final cur = ProfileController.to.currencyCode.value;
        final owed = Map<String, double>.from(ec.owedToMeByCurrency);
        final owe = Map<String, double>.from(ec.iOweByCurrency);
        final owedMain = owed[cur] ?? 0;
        final oweMain = owe[cur] ?? 0;
        final net = owedMain - oweMain;

        final otherNets = <String, double>{};
        for (final c in {...owed.keys, ...owe.keys}) {
          if (c == cur) continue;
          final v = (owed[c] ?? 0) - (owe[c] ?? 0);
          if (v.abs() >= 0.005) otherNets[c] = v;
        }
        final otherOwed = Map<String, double>.from(owed)..remove(cur);
        final otherOwe = Map<String, double>.from(owe)..remove(cur);

        final caption = net > 0.005
            ? 'Overall, you are owed'
            : net < -0.005
                ? 'Overall, you owe'
                : 'You\'re all settled up';

        return Container(
          decoration: BoxDecoration(
            gradient: AppColors.heroGradient,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            boxShadow: AppShadows.glow(AppColors.primary),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            child: Stack(
              children: [
                Positioned(
                  top: -60,
                  right: -40,
                  child: _Circle(size: 180, opacity: 0.10),
                ),
                Positioned(
                  bottom: -70,
                  left: -30,
                  child: _Circle(size: 160, opacity: 0.07),
                ),
                Positioned(
                  top: 40,
                  right: 60,
                  child: _Circle(size: 36, opacity: 0.08),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Total balance',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          _HeroPill(label: cur),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _AnimatedMoney(
                        value: net,
                        currency: cur,
                        signed: true,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        caption,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (otherNets.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Plus ${Fmt.multi(otherNets, preferred: cur, absolute: false)} in other currencies',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      Row(
                        children: [
                          Expanded(
                            child: _HeroStat(
                              icon: Icons.south_west_rounded,
                              label: 'You are owed',
                              value: owedMain,
                              currency: cur,
                              others: otherOwed,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: _HeroStat(
                              icon: Icons.north_east_rounded,
                              label: 'You owe',
                              value: oweMain,
                              currency: cur,
                              others: otherOwe,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      AppButton.secondary(
                        label: 'Settle up',
                        icon: Icons.handshake_rounded,
                        height: 48,
                        onPressed: () => Get.toNamed(AppRoutes.settleUp),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _Circle extends StatelessWidget {
  final double size;
  final double opacity;
  const _Circle({required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: opacity),
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  final String label;
  const _HeroPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value;
  final String currency;
  final Map<String, double> others;

  const _HeroStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.currency,
    required this.others,
  });

  @override
  Widget build(BuildContext context) {
    final hasOthers = others.values.any((v) => v.abs() >= 0.005);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 12, color: Colors.white),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _AnimatedMoney(
            value: value,
            currency: currency,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (hasOthers)
            Text(
              '+ ${Fmt.multi(others, preferred: currency)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick actions
// ---------------------------------------------------------------------------

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.xl,
        AppSpacing.page,
        0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _QuickAction(
              icon: Icons.add_rounded,
              label: 'Add expense',
              color: AppColors.primary,
              onTap: () => AppNav.addExpense(),
            ),
          ),
          Expanded(
            child: _QuickAction(
              icon: Icons.handshake_rounded,
              label: 'Settle up',
              color: AppColors.positive,
              onTap: () => Get.toNamed(AppRoutes.settleUp),
            ),
          ),
          Expanded(
            child: _QuickAction(
              icon: Icons.group_add_rounded,
              label: 'New group',
              color: AppColors.secondary,
              onTap: () => Get.toNamed(AppRoutes.createGroup),
            ),
          ),
          Expanded(
            child: _QuickAction(
              icon: Icons.person_add_alt_1_rounded,
              label: 'Add friend',
              color: AppColors.accent,
              onTap: () => Get.toNamed(AppRoutes.addFriends),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Pressable(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                boxShadow: AppShadows.soft,
              ),
              alignment: Alignment.center,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 22),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// This month insight
// ---------------------------------------------------------------------------

class _MonthInsight extends StatelessWidget {
  const _MonthInsight();

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December',
  ];

  @override
  Widget build(BuildContext context) {
    final ec = ExpenseController.to;
    return Obx(() {
      final cur = ProfileController.to.currencyCode.value;
      final byCurrency = Map<String, double>.from(ec.monthSpendByCurrency)
        ..removeWhere((_, v) => v < 0.005);
      final byCategory = Map<String, double>.from(ec.monthSpendByCategory)
        ..removeWhere((_, v) => v < 0.005);
      if (byCurrency.isEmpty) return const SizedBox.shrink();

      final main = byCurrency[cur];
      final others = Map<String, double>.from(byCurrency)..remove(cur);
      final cats = byCategory.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final catTotal = cats.fold<double>(0, (a, e) => a + e.value);

      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.xxl,
          AppSpacing.page,
          0,
        ),
        child: AppCard(
          padding: const EdgeInsets.all(AppSpacing.lg + 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const IconBadge(
                    icon: Icons.insights_rounded,
                    color: AppColors.primary,
                    size: 36,
                    iconSize: 19,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  const Expanded(
                    child: Text(
                      'This month',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  StatusPill(
                    label: _months[DateTime.now().month - 1].toUpperCase(),
                    color: AppColors.primary,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              const Text(
                'Your share of expenses',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              if (main != null)
                _AnimatedMoney(
                  value: main,
                  currency: cur,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    color: AppColors.textPrimary,
                  ),
                )
              else
                Text(
                  Fmt.multi(byCurrency, preferred: cur),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              if (main != null && others.isNotEmpty)
                Text(
                  '+ ${Fmt.multi(others, preferred: cur)}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              if (cats.isNotEmpty && catTotal > 0) ...[
                const SizedBox(height: AppSpacing.lg),
                _CategoryBar(entries: cats, total: catTotal),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.lg,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final e in cats.take(6))
                      _LegendItem(
                        style: ExpenseCategories.of(e.key),
                        label: e.key,
                        percent: e.value / catTotal * 100,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
    });
  }
}

class _CategoryBar extends StatelessWidget {
  final List<MapEntry<String, double>> entries;
  final double total;

  const _CategoryBar({required this.entries, required this.total});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: AppMotion.curve,
      builder: (_, t, child) => ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Align(
          alignment: Alignment.centerLeft,
          widthFactor: t,
          child: child,
        ),
      ),
      child: SizedBox(
        height: 12,
        child: Row(
          children: [
            for (var i = 0; i < entries.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              Expanded(
                flex: (entries[i].value / total * 1000).round().clamp(1, 1000),
                child: ColoredBox(
                  color: ExpenseCategories.of(entries[i].key).color,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final CategoryStyle style;
  final String label;
  final double percent;

  const _LegendItem({
    required this.style,
    required this.label,
    required this.percent,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: style.color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '${percent < 1 ? '<1' : percent.round()}%',
          style: const TextStyle(
            fontSize: 12.5,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Balances with people
// ---------------------------------------------------------------------------

class _BalancesSection extends StatelessWidget {
  const _BalancesSection();

  static double _weight(Map<String, double> m) =>
      m.values.fold(0.0, (a, v) => a + v.abs());

  @override
  Widget build(BuildContext context) {
    final ec = ExpenseController.to;
    return Obx(() {
      final cur = ProfileController.to.currencyCode.value;
      final people = ec.settleUpData.values
          .map((p) => {
                ...p,
                'byCurrency': Map<String, double>.from(
                  (p['byCurrency'] as Map?) ?? const {},
                ),
              })
          .toList()
        ..sort((a, b) => _weight(b['byCurrency'] as Map<String, double>)
            .compareTo(_weight(a['byCurrency'] as Map<String, double>)));
      final shown = people.take(5).toList();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Balances',
            actionLabel: 'See all',
            onAction: () => AppNav.toTab(AppTab.friends),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
            child: shown.isEmpty
                ? const AppCard(
                    child: Row(
                      children: [
                        IconBadge(
                          icon: Icons.verified_rounded,
                          color: AppColors.positive,
                        ),
                        SizedBox(width: AppSpacing.md + 2),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'You\'re all settled up',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'No one owes anyone right now.',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                : AppCard(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: Column(
                      children: [
                        for (var i = 0; i < shown.length; i++) ...[
                          if (i > 0)
                            const Divider(
                              height: 1,
                              indent: 70,
                              endIndent: AppSpacing.lg,
                              color: AppColors.border,
                            ),
                          _PersonRow(person: shown[i], currency: cur),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      );
    });
  }
}

class _PersonRow extends StatelessWidget {
  final Map<String, dynamic> person;
  final String currency;

  const _PersonRow({required this.person, required this.currency});

  @override
  Widget build(BuildContext context) {
    final uid = person['uid'].toString();
    final name = (person['name'] ?? 'Someone').toString();
    final avatar = (person['avatarUrl'] ?? '').toString();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => AppNav.openFriend(
          uid,
          data: {'name': name, 'avatarUrl': avatar},
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              AppAvatar(name: name, imageUrl: avatar, radius: 20),
              const SizedBox(width: AppSpacing.md + 2),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: BalanceLabel(
                  byCurrency: person['byCurrency'] as Map<String, double>,
                  preferredCurrency: currency,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Recent activity
// ---------------------------------------------------------------------------

class _RecentActivitySection extends StatelessWidget {
  const _RecentActivitySection();

  @override
  Widget build(BuildContext context) {
    final ec = ExpenseController.to;
    return Obx(() {
      final items = ec.recentActivity.take(6).toList();
      if (items.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Recent activity',
            actionLabel: 'See all',
            onAction: () => Get.toNamed(AppRoutes.activity),
          ),
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                0,
                AppSpacing.page,
                AppSpacing.md - 2,
              ),
              child: FadeSlideIn(
                key: ValueKey(items[i]['id']),
                index: i,
                child: ExpenseTile(expense: items[i]),
              ),
            ),
        ],
      );
    });
  }
}

// ---------------------------------------------------------------------------
// New user
// ---------------------------------------------------------------------------

class _NewUserContent extends StatelessWidget {
  const _NewUserContent();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FadeSlideIn(
          index: 1,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.md,
              AppSpacing.page,
              0,
            ),
            child: Container(
              decoration: BoxDecoration(
                gradient: AppColors.heroGradient,
                borderRadius: BorderRadius.circular(AppRadius.xl),
                boxShadow: AppShadows.glow(AppColors.primary),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.xl),
                child: Stack(
                  children: [
                    const Positioned(
                      top: -50,
                      right: -40,
                      child: _Circle(size: 170, opacity: 0.10),
                    ),
                    const Positioned(
                      bottom: -60,
                      left: -30,
                      child: _Circle(size: 140, opacity: 0.07),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Welcome to SplitShare',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 21,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.4,
                                  ),
                                ),
                                SizedBox(height: AppSpacing.sm),
                                Text(
                                  'Split bills with friends and groups, and always know who owes what.',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13.5,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.16),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.receipt_long_rounded,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const FadeSlideIn(index: 2, child: _QuickActions()),
        const FadeSlideIn(index: 3, child: _GetStartedCard()),
      ],
    );
  }
}

class _GetStartedCard extends StatelessWidget {
  const _GetStartedCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.xxl,
        AppSpacing.page,
        0,
      ),
      child: Obx(() {
        final hasFriend = FriendController.to.friends.isNotEmpty;
        final hasGroup = GroupController.to.groups.isNotEmpty;
        final hasExpense = ExpenseController.to.recentActivity.isNotEmpty;
        final done = [hasFriend, hasGroup, hasExpense].where((d) => d).length;

        return AppCard(
          padding: const EdgeInsets.all(AppSpacing.lg + 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Get started',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  StatusPill(
                    label: '$done OF 3 DONE',
                    color: done == 3 ? AppColors.positive : AppColors.primary,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: done / 3),
                  duration: AppMotion.slow,
                  curve: AppMotion.curve,
                  builder: (_, v, _) => LinearProgressIndicator(
                    value: v,
                    minHeight: 6,
                    backgroundColor: AppColors.surfaceMuted,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              _ChecklistItem(
                icon: Icons.person_add_alt_1_rounded,
                title: 'Add a friend',
                subtitle: 'Find people by name, email or QR code',
                done: hasFriend,
                onTap: () => Get.toNamed(AppRoutes.addFriends),
              ),
              _ChecklistItem(
                icon: Icons.group_add_rounded,
                title: 'Create a group',
                subtitle: 'For trips, housemates or a night out',
                done: hasGroup,
                onTap: () => Get.toNamed(AppRoutes.createGroup),
              ),
              _ChecklistItem(
                icon: Icons.receipt_long_rounded,
                title: 'Add your first expense',
                subtitle: 'Split a bill and we\'ll do the maths',
                done: hasExpense,
                onTap: () => AppNav.addExpense(),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _ChecklistItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool done;
  final VoidCallback onTap;

  const _ChecklistItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.done,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Row(
            children: [
              AnimatedContainer(
                duration: AppMotion.normal,
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: done ? AppColors.positive : AppColors.primaryLight,
                  shape: BoxShape.circle,
                ),
                child: AnimatedSwitcher(
                  duration: AppMotion.normal,
                  child: Icon(
                    done ? Icons.check_rounded : icon,
                    key: ValueKey(done),
                    size: 20,
                    color: done ? Colors.white : AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md + 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color:
                            done ? AppColors.textMuted : AppColors.textPrimary,
                        decoration: done ? TextDecoration.lineThrough : null,
                        decorationColor: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(
                done ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
                color: done ? AppColors.positive : AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Skeleton
// ---------------------------------------------------------------------------

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.md,
        AppSpacing.page,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Skeleton(height: 250, radius: AppRadius.xl),
          const SizedBox(height: AppSpacing.xl),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (var i = 0; i < 4; i++)
                const Column(
                  children: [
                    Skeleton.circle(size: 58),
                    SizedBox(height: AppSpacing.sm),
                    Skeleton(width: 54, height: 10),
                  ],
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),
          const Skeleton(width: 120, height: 16),
          const SizedBox(height: AppSpacing.md),
          const SkeletonList(
            count: 4,
            shrinkWrap: true,
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

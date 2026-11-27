import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../app/routes/app_routes.dart';
import '../controllers/balances.dart';
import '../controllers/expense_controller.dart';
import '../controllers/friend_controller.dart';
import '../controllers/group_controller.dart';
import '../controllers/notification_controller.dart';
import '../controllers/profile_controller.dart';
import '../controllers/shell_controller.dart';
import '../controllers/trip_controller.dart';
import '../core/ui.dart';
import 'trips_screen.dart' show GroupsHub;
import 'widgets/history.dart';

/// Home tab: your name, the balance card, then who owes whom.
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
          final isNew = ec.recentActivity.isEmpty && ec.settleUpData.isEmpty && TripController.to.trips.isEmpty;

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
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.lg,
        AppSpacing.page,
        0,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _greeting(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Obx(
                  () => Text(
                    Fmt.firstName(profile.name.value),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
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
                () => AppAvatar(
                  name: profile.name.value,
                  imageUrl: profile.avatarUrl.value,
                  radius: 20,
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
        FadeSlideIn(index: 1, child: _NetBalance()),
        FadeSlideIn(index: 2, child: _BalancesSection()),
        FadeSlideIn(index: 3, child: _QuickActions()),
        FadeSlideIn(index: 4, child: _MonthInsight()),
        FadeSlideIn(index: 5, child: _HistorySection()),
      ],
    );
  }
}

/// The page's one total: net balance in the user's currency, on the
/// pistachio card with the owed / owe split bar.
class _NetBalance extends StatelessWidget {
  const _NetBalance();

  @override
  Widget build(BuildContext context) {
    final ec = ExpenseController.to;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.xl,
        AppSpacing.page,
        0,
      ),
      child: Obx(() {
        final cur = ProfileController.to.currencyCode.value;
        ec.balances.length;
        TripController.to.trips.length;
        // Friends & groups, cancelled per person.
        final totals = Balances.totals();
        final owed = totals.owed;
        final owe = totals.owe;
        final owedMain = owed[cur] ?? 0;
        final oweMain = owe[cur] ?? 0;
        final net = owedMain - oweMain;

        final otherNets = <String, double>{};
        for (final c in {...owed.keys, ...owe.keys}) {
          if (c == cur) continue;
          final v = (owed[c] ?? 0) - (owe[c] ?? 0);
          if (v.abs() >= 0.005) otherNets[c] = v;
        }

        final caption = otherNets.isEmpty
            ? null
            : 'Plus ${Fmt.multi(otherNets, preferred: cur, absolute: false)} in other currencies';
        final youOwe = net < -0.005;
        final settled = net.abs() < 0.005;

        return KhataTotal(
          label: settled
              ? "You're all settled up"
              : youOwe
              ? 'Overall, you owe'
              : 'Overall, you get back',
          amount: Fmt.money(net.abs(), currencyCode: cur),
          caption: caption,
          color: youOwe ? AppColors.negative : null,
          owed: owedMain,
          owe: oweMain,
          owedLabel: 'Owed to you ${Fmt.money(owedMain, currencyCode: cur)}',
          oweLabel: 'You owe ${Fmt.money(oweMain, currencyCode: cur)}',
        );
      }),
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
        AppSpacing.page - AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.page - AppSpacing.sm,
        0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _QuickAction(
              icon: Icons.add_rounded,
              label: 'Add expense',
              onTap: () => AppNav.addExpense(),
            ),
          ),
          Expanded(
            child: _QuickAction(
              icon: Icons.handshake_outlined,
              label: 'Settle up',
              onTap: () => Get.toNamed(AppRoutes.settleUp),
            ),
          ),
          Expanded(
            child: _QuickAction(
              icon: Icons.group_add_outlined,
              label: 'New group',
              onTap: GroupsHub.startNewGroup,
            ),
          ),
          Expanded(
            child: _QuickAction(
              icon: Icons.person_add_alt_outlined,
              label: 'Add friend',
              onTap: () => Get.toNamed(AppRoutes.addFriends),
            ),
          ),
        ],
      ),
    );
  }
}

/// A plain icon + label button: no tile, no tint.
class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + 2),
            child: Column(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: AppColors.primary, size: 24),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
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

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title: _months[DateTime.now().month - 1]),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: Text(
                          'Your share of expenses',
                          style: TextStyle(
                            fontSize: 13.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Flexible(
                        child: Text(
                          main != null
                              ? Fmt.money(main, currencyCode: cur)
                              : Fmt.multi(byCurrency, preferred: cur),
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (main != null && others.isNotEmpty)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '+ ${Fmt.multi(others, preferred: cur)}',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  if (cats.isNotEmpty && catTotal > 0) ...[
                    const SizedBox(height: AppSpacing.md),
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
          ),
        ],
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm / 2),
      child: SizedBox(
        height: 8,
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
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: style.color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '${percent < 1 ? '<1' : percent.round()}%',
          style: TextStyle(
            fontSize: 12.5,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Balances with people — one ruled udhaar list
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
      ec.settleUpData.length;
      TripController.to.trips.length;
      // Everyone, including group people who aren't on SplitShare.
      final people = Balances.everyone()
          .entries
          .map((e) {
            final info = Balances.personInfo(e.key);
            return <String, dynamic>{
              'uid': e.key,
              'name': info.name,
              'avatarUrl': info.avatarUrl,
              'byCurrency': e.value,
            };
          })
          .toList()
        ..sort((a, b) => _weight(b['byCurrency'] as Map<String, double>)
            .compareTo(_weight(a['byCurrency'] as Map<String, double>)));
      final shown = people.take(10).toList();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Friends',
            actionLabel: 'All friends',
            onAction: () => AppNav.toTab(AppTab.friends),
          ),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
              child: Text(
                "You're all settled up. No one owes anyone right now.",
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
              ),
            )
          else
            SizedBox(
              height: 132,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
                itemCount: shown.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (_, i) =>
                    _PersonRow(person: shown[i], currency: cur),
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
    final byCurrency = person['byCurrency'] as Map<String, double>;

    final nonZero =
        byCurrency.entries.where((e) => e.value.abs() >= 0.005).toList();
    final primary = nonZero.isEmpty
        ? 0.0
        : (byCurrency[currency] ?? nonZero.first.value);
    final dir = BalanceDirectionX.fromNet(primary);
    final mixed = nonZero.any((e) => e.value.sign != primary.sign);

    final String words;
    final String amount;
    final Color wordsColor;
    final Color amountColor;
    if (nonZero.isEmpty) {
      words = 'settled';
      amount = Fmt.money(0, currencyCode: currency);
      wordsColor = AppColors.textMuted;
      amountColor = AppColors.textMuted;
    } else if (mixed) {
      words = 'mixed';
      amount = Fmt.multi(byCurrency, preferred: currency, absolute: false);
      wordsColor = AppColors.textSecondary;
      amountColor = AppColors.textPrimary;
    } else if (dir == BalanceDirection.youOwe) {
      words = 'you owe';
      amount = '- ${Fmt.multi(byCurrency, preferred: currency)}';
      wordsColor = AppColors.negative;
      amountColor = AppColors.negative;
    } else {
      words = 'owes you';
      amount = Fmt.multi(byCurrency, preferred: currency);
      wordsColor = AppColors.textSecondary;
      amountColor = AppColors.textPrimary;
    }

    final shortAmount = nonZero.isEmpty
        ? amount
        : mixed
        ? amount
        : dir == BalanceDirection.youOwe
        ? '− ${Fmt.multi(byCurrency, preferred: currency)}'
        : '+ ${Fmt.multi(byCurrency, preferred: currency)}';
    final shownColor = nonZero.isEmpty || mixed
        ? amountColor
        : dir == BalanceDirection.youOwe
        ? AppColors.negative
        : AppColors.positive;

    return Semantics(
      button: true,
      label: '$name, $words, $amount',
      excludeSemantics: true,
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        radius: AppRadius.lg,
        onTap: () => uid.startsWith('name:')
            ? Get.toNamed(AppRoutes.settleUp)
            : AppNav.openFriend(uid, data: {'name': name, 'avatarUrl': avatar}),
        child: SizedBox(
          width: 104,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppAvatar(name: name, imageUrl: avatar, radius: 18),
              const Spacer(),
              Text(
                Fmt.firstName(name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                shortAmount,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: shownColor,
                ),
              ),
              Text(
                words,
                maxLines: 1,
                style: TextStyle(fontSize: 12, color: wordsColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// History
// ---------------------------------------------------------------------------

/// Latest transactions: expenses, payments and group payments / pay-backs.
class _HistorySection extends StatelessWidget {
  const _HistorySection();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      ExpenseController.to.recentActivity.length;
      TripController.to.trips.length;
      final entries = buildHistory();
      if (entries.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'History',
            actionLabel: 'See all',
            onAction: () => Get.toNamed(AppRoutes.activity),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
            child: HistoryList(entries, limit: 15),
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
              AppSpacing.xl,
              AppSpacing.page,
              0,
            ),
            child: Obx(
              () => KhataTotal(
                label: 'Net balance',
                amount: Fmt.money(
                  0,
                  currencyCode: ProfileController.to.currencyCode.value,
                ),
                caption: 'A clean page. Split bills with friends and groups, '
                    'and always know who owes what.',
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
    return Obx(() {
      final hasFriend = FriendController.to.friends.isNotEmpty;
      final hasGroup = GroupController.to.groups.isNotEmpty;
      final hasExpense = ExpenseController.to.recentActivity.isNotEmpty;
      final done = [hasFriend, hasGroup, hasExpense].where((d) => d).length;
      final divider = Divider(
        height: 1,
        thickness: 1,
        indent: AppSpacing.lg,
        endIndent: AppSpacing.lg,
        color: AppColors.border,
      );

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.xxl,
              AppSpacing.page,
              AppSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Get started',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                        ),
                  ),
                ),
                Text(
                  '$done of 3 done',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: done == 3
                        ? AppColors.positive
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
            child: AppCard(
              padding: EdgeInsets.zero,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: Column(
                  children: [
                    _ChecklistItem(
                      icon: Icons.person_add_alt_outlined,
                      title: 'Add a friend',
                      subtitle: 'Find people by name, email or QR code',
                      done: hasFriend,
                      onTap: () => Get.toNamed(AppRoutes.addFriends),
                    ),
                    divider,
                    _ChecklistItem(
                      icon: Icons.group_add_outlined,
                      title: 'Create a group',
                      subtitle: 'For travel, housemates or a night out',
                      done: hasGroup,
                      onTap: GroupsHub.startNewGroup,
                    ),
                    divider,
                    _ChecklistItem(
                      icon: Icons.receipt_long_outlined,
                      title: 'Add your first expense',
                      subtitle: 'Split a bill and we\'ll do the maths',
                      done: hasExpense,
                      onTap: () => AppNav.addExpense(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    });
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
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md + 2,
          ),
          child: Row(
            children: [
              AnimatedSwitcher(
                duration: AppMotion.normal,
                child: Icon(
                  done ? Icons.check_rounded : icon,
                  key: ValueKey(done),
                  size: 22,
                  color: done ? AppColors.textMuted : AppColors.primary,
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
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (done)
                Text(
                  'done',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                )
              else
                Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
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
    return const Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.xl,
        AppSpacing.page,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Skeleton(width: 90, height: 12),
          SizedBox(height: AppSpacing.sm),
          Skeleton(width: 200, height: 40),
          SizedBox(height: AppSpacing.md),
          Skeleton(width: 240, height: 12),
          SizedBox(height: AppSpacing.xxl),
          SkeletonList(
            count: 4,
            shrinkWrap: true,
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../app/routes/app_routes.dart';
import '../controllers/expense_controller.dart';
import '../controllers/group_controller.dart';
import '../controllers/shell_controller.dart';
import '../core/ui.dart';

/// Groups tab (lives inside the shell — no bottom bar of its own).
class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  GroupController get _groups => GroupController.to;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    _groups.fetchGroups();
    // Wait for the first snapshot (or give up after a few seconds).
    await Future.any([
      _groups.isLoading.stream.firstWhere((loading) => !loading),
      Future<void>.delayed(const Duration(seconds: 5)),
    ]);
  }

  void _create() => Get.toNamed(AppRoutes.createGroup);

  List<Map<String, dynamic>> _filter(List<Map<String, dynamic>> groups) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return groups;
    return groups
        .where((g) => (g['name'] ?? '').toString().toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Obx(() {
              final n = _groups.groups.length;
              return TabHeader(
                title: 'Groups',
                subtitle: _groups.isLoading.value && n == 0
                    ? 'Loading your groups…'
                    : '$n group${n == 1 ? '' : 's'}',
                actions: [
                  AppIconButton(
                    icon: Icons.add_rounded,
                    tooltip: 'New group',
                    onPressed: _create,
                  ),
                ],
              );
            }),
            Expanded(
              child: Obx(() {
                final all = _groups.groups.toList();
                final Widget child;
                if (_groups.isLoading.value && all.isEmpty) {
                  child = const _GroupsSkeleton(key: ValueKey('loading'));
                } else if (_groups.hasError.value && all.isEmpty) {
                  child = ErrorState(
                    key: const ValueKey('error'),
                    title: 'Couldn\'t load your groups',
                    onRetry: _groups.fetchGroups,
                  );
                } else if (all.isEmpty) {
                  child = RefreshIndicator(
                    key: const ValueKey('empty'),
                    onRefresh: _refresh,
                    child: LayoutBuilder(
                      builder: (context, c) => SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: c.maxHeight),
                          child: EmptyState(
                            icon: Icons.groups_rounded,
                            title: 'No groups yet',
                            message:
                                'Create a group for trips, homes, couples or '
                                'events and keep shared costs in one place.',
                            orbitIcons: const [
                              Icons.flight_takeoff_rounded,
                              Icons.home_rounded,
                              Icons.favorite_rounded,
                            ],
                            actionLabel: 'Create group',
                            actionIcon: Icons.add_rounded,
                            onAction: _create,
                          ),
                        ),
                      ),
                    ),
                  );
                } else {
                  child = _buildList(all);
                }
                return AnimatedSwitcher(
                  duration: AppMotion.normal,
                  child: child,
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> all) {
    final shown = _filter(all);
    return RefreshIndicator(
      key: const ValueKey('list'),
      onRefresh: _refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.sm,
          AppSpacing.page,
          AppSpacing.xxxl,
        ),
        itemCount: 2 + (shown.isEmpty ? 1 : shown.length),
        itemBuilder: (context, i) {
          if (i == 0) {
            return FadeSlideIn(child: _SummaryStrip(groups: all));
          }
          if (i == 1) {
            return Padding(
              padding: const EdgeInsets.only(
                top: AppSpacing.lg,
                bottom: AppSpacing.lg,
              ),
              child: AppSearchField(
                controller: _searchCtrl,
                hint: 'Search groups',
                onChanged: (v) => setState(() => _query = v),
              ),
            );
          }
          if (shown.isEmpty) {
            return Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxl),
              child: EmptyState(
                icon: Icons.search_off_rounded,
                title: 'No matching groups',
                message: 'Nothing matches "${_query.trim()}". '
                    'Try another name.',
                illustrationSize: 130,
                actionLabel: 'Clear search',
                onAction: () {
                  _searchCtrl.clear();
                  setState(() => _query = '');
                },
              ),
            );
          }
          final g = shown[i - 2];
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: FadeSlideIn(
              key: ValueKey(g['id']),
              index: i - 2,
              child: _GroupCard(group: g),
            ),
          );
        },
      ),
    );
  }
}

/// Net direction for a group from the current user's point of view.
BalanceDirection _directionOf(Map<String, double> byCurrency, String preferred) {
  if (byCurrency.isEmpty) return BalanceDirection.settled;
  final primary = byCurrency[preferred] ?? byCurrency.values.first;
  return BalanceDirectionX.fromNet(primary);
}

class _SummaryStrip extends StatelessWidget {
  final List<Map<String, dynamic>> groups;
  const _SummaryStrip({required this.groups});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final ctrl = ExpenseController.to;
      ctrl.openExpenses.length; // rebuild when balances change
      var owe = 0;
      var owed = 0;
      for (final g in groups) {
        final id = g['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final dir = _directionOf(
          ctrl.groupBalance(id),
          (g['currencyCode'] ?? 'USD').toString(),
        );
        if (dir == BalanceDirection.youOwe) owe++;
        if (dir == BalanceDirection.owedToYou) owed++;
      }
      final settled = groups.length - owe - owed;
      return Row(
        children: [
          Expanded(
            child: _SummaryTile(
              label: 'You owe in',
              count: owe,
              color: AppColors.negative,
              icon: Icons.arrow_outward_rounded,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: _SummaryTile(
              label: 'Owed in',
              count: owed,
              color: AppColors.positive,
              icon: Icons.south_west_rounded,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: _SummaryTile(
              label: 'Settled',
              count: settled,
              color: AppColors.primary,
              icon: Icons.check_rounded,
            ),
          ),
        ],
      );
    });
  }
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;

  const _SummaryTile({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon: icon, color: color, size: 30, iconSize: 16),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: count == 0 ? AppColors.textMuted : color,
            ),
          ),
          Text(
            '$label ${count == 1 ? 'group' : 'groups'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  final Map<String, dynamic> group;
  const _GroupCard({required this.group});

  @override
  Widget build(BuildContext context) {
    final id = group['id']?.toString() ?? '';
    final type = GroupTypes.of(group['icon']?.toString());
    final members = GroupController.membersOf(group);
    final currency = (group['currencyCode'] ?? 'USD').toString();
    final name = (group['name'] ?? 'Group').toString();

    return AppCard(
      onTap: () => AppNav.openGroup(group),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(icon: type.icon, color: type.color, size: 50, iconSize: 24),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${type.name} · Active ${Fmt.relative(group['lastActive'] ?? group['createdAt']).toLowerCase()}',
                      maxLines: 1,
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
              const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Divider(height: 1, color: AppColors.border),
          ),
          Row(
            children: [
              AvatarStack(people: members, radius: 12),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '${members.length} member${members.length == 1 ? '' : 's'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Obx(() {
                  final ctrl = ExpenseController.to;
                  ctrl.openExpenses.length;
                  return BalanceLabel(
                    byCurrency: id.isEmpty ? const {} : ctrl.groupBalance(id),
                    preferredCurrency: currency,
                  );
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GroupsSkeleton extends StatelessWidget {
  const _GroupsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.sm,
        AppSpacing.page,
        AppSpacing.xxl,
      ),
      children: [
        Row(
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.md),
              const Expanded(child: Skeleton(height: 92, radius: AppRadius.lg)),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        const Skeleton(height: 50, radius: AppRadius.md),
        const SizedBox(height: AppSpacing.lg),
        for (var i = 0; i < 4; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Skeleton(width: 50, height: 50, radius: 16),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Skeleton(width: 110 + i * 24.0, height: 14),
                            const SizedBox(height: 8),
                            const Skeleton(width: 90, height: 11),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const Row(
                    children: [
                      Skeleton(width: 70, height: 24, radius: 12),
                      Spacer(),
                      Skeleton(width: 64, height: 16),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

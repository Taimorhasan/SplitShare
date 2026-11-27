import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/expense_controller.dart';
import '../../controllers/group_controller.dart';
import '../../controllers/shell_controller.dart';
import '../../core/ui.dart';
import '../../controllers/trip_controller.dart';
import 'legacy/legacy_group_detail_screen.dart' show EditGroupSheet;
import 'group_list.dart' show GroupList, GroupsHub;

/// Groups tab (lives inside the shell — no bottom bar of its own).
class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  GroupController get _groups => GroupController.to;

  /// Swipe-left action: the creator deletes the group, others leave it.
  Future<void> _deleteOrLeave(Map<String, dynamic> g, bool isCreator) async {
    final name = (g['name'] ?? 'this group').toString();
    final id = g['id'].toString();
    final ok = await AppDialogs.confirm(
      title: isCreator ? 'Delete "$name"?' : 'Leave "$name"?',
      message: isCreator
          ? "The group will be removed for every member. Its expenses stay in "
                "everyone's history and balances."
          : 'You can only leave once your balance in this group is settled.',
      confirmLabel: isCreator ? 'Delete' : 'Leave',
      destructive: true,
      icon: isCreator ? Icons.delete_outline_rounded : Icons.logout_rounded,
    );
    if (!ok) return;
    try {
      if (isCreator) {
        await _groups.deleteGroup(id);
        AppToast.success('"$name" was deleted.');
      } else {
        await _groups.leaveGroup(id);
        AppToast.success('You left "$name".');
      }
    } on GroupException catch (e) {
      AppToast.warning(e.message, title: "Can't leave yet");
    } catch (e) {
      AppToast.error(AppToast.friendly(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final trips = TripController.to;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Obx(() {
              final n = trips.trips.length;
              return TabHeader(
                title: 'Groups',
                subtitle: trips.isLoading.value && n == 0
                    ? 'Loading your groups…'
                    : n == 0
                    ? 'Trips, home, dinners — split anything'
                    : '$n group${n == 1 ? '' : 's'}',
                actions: [
                  AppIconButton(
                    icon: Icons.add_rounded,
                    tooltip: 'New group',
                    onPressed: GroupsHub.startNewGroup,
                  ),
                ],
              );
            }),
            Expanded(
              child: Obx(() {
                // Older-style groups (before groups and give-and-take
                // merged) stay reachable underneath.
                final legacy = _groups.groups.toList();
                return GroupList(
                  footer: legacy.isEmpty ? null : _olderGroups(legacy),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _olderGroups(List<Map<String, dynamic>> all) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xl, bottom: AppSpacing.sm),
          child: Text(
            'Older groups',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Text(
            'Made before groups got the new give-and-take calculator. '
            'Their expenses still count in your balances.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ),
        AppCard(
          padding: EdgeInsets.zero,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg - 1),
            child: Column(
              children: [
                for (var j = 0; j < all.length; j++) ...[
                  if (j > 0) const Divider(height: 1),
                  Builder(
                    builder: (_) {
                      final g = all[j];
                      final isCreator = GroupController.to.isCreator(g);
                      return SwipeActions(
                        key: ValueKey('swipe-${g['id']}'),
                        radius: 0,
                        onEdit: () => AppDialogs.sheet<void>(
                          title: 'Edit group',
                          child: EditGroupSheet(
                            groupId: g['id'].toString(),
                            group: g,
                          ),
                        ),
                        onDelete: () => _deleteOrLeave(g, isCreator),
                        deleteLabel: isCreator ? 'Delete' : 'Leave',
                        deleteIcon: isCreator
                            ? Icons.delete_outline_rounded
                            : Icons.logout_rounded,
                        child: _GroupRow(group: g),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _GroupRow extends StatelessWidget {
  final Map<String, dynamic> group;
  const _GroupRow({required this.group});

  @override
  Widget build(BuildContext context) {
    final id = group['id']?.toString() ?? '';
    final type = GroupTypes.of(group['icon']?.toString());
    final members = GroupController.membersOf(group);
    final currency = (group['currencyCode'] ?? 'USD').toString();
    final name = (group['name'] ?? 'Group').toString();
    final active = Fmt.relative(
      group['lastActive'] ?? group['createdAt'],
    ).toLowerCase();

    // Solid surface so the swipe background stays hidden until dragged.
    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: () => AppNav.openGroup(group),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              IconBadge(
                icon: type.icon,
                color: type.color,
                size: 44,
                iconSize: 22,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${type.name} · ${members.length} '
                      '${members.length == 1 ? 'member' : 'members'} · '
                      'active $active',
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
        ),
      ),
    );
  }
}

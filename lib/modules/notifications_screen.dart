import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../app/routes/app_routes.dart';
import '../controllers/friend_controller.dart';
import '../controllers/group_controller.dart';
import '../controllers/notification_controller.dart';
import '../controllers/shell_controller.dart';
import '../core/ui.dart';

/// In-app notification inbox.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  NotificationController get _nc => NotificationController.to;

  /// Ids swiped away locally, hidden until the stream confirms the delete.
  final Set<String> _removed = {};
  bool _markingAll = false;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _nc.ensureListening();
  }

  Future<void> _markAllRead() async {
    if (_markingAll) return;
    setState(() => _markingAll = true);
    try {
      await _nc.markAllAsRead();
      AppToast.success('All notifications marked as read');
    } catch (e) {
      AppToast.error(AppToast.friendly(e));
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  Future<void> _clearAll() async {
    if (_clearing) return;
    final ok = await AppDialogs.confirm(
      title: 'Clear all notifications?',
      message: 'This permanently removes every notification in your inbox.',
      confirmLabel: 'Clear all',
      destructive: true,
      icon: Icons.delete_sweep_rounded,
    );
    if (!ok || !mounted) return;
    setState(() => _clearing = true);
    try {
      await _nc.clearAll();
      AppToast.success('Notifications cleared');
    } catch (e) {
      AppToast.error(AppToast.friendly(e));
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  Future<void> _delete(Map<String, dynamic> n) async {
    final id = n['id'].toString();
    setState(() => _removed.add(id));
    try {
      await _nc.deleteNotification(id);
      AppToast.success('Notification deleted', title: 'Deleted');
    } catch (e) {
      if (mounted) setState(() => _removed.remove(id));
      AppToast.error(AppToast.friendly(e));
    }
  }

  void _open(Map<String, dynamic> n) {
    final id = n['id']?.toString();
    if (id != null && n['isRead'] != true) {
      // Don't block navigation on the write; it syncs in the background.
      _nc.markAsRead(id).catchError((Object e) {
        debugPrint('markAsRead failed: $e');
      });
    }

    final data = Map<String, dynamic>.from((n['data'] as Map?) ?? const {});
    final type = n['type']?.toString();
    final fromUid = n['fromUid']?.toString();

    void openPerson(String? uid) {
      if (uid == null || uid.isEmpty) return;
      final f = FriendController.to.friendByUid(uid);
      AppNav.openFriend(
        uid,
        data: f == null
            ? null
            : {
                'name': f['name'],
                'avatarUrl': f['avatarUrl'],
                'email': f['email'],
              },
      );
    }

    switch (type) {
      case 'friend_request':
        Get.toNamed(AppRoutes.friendRequests);
      case 'friend_accepted':
        openPerson(data['fromUid']?.toString() ?? fromUid);
      case 'expense':
        final expenseId = data['expenseId']?.toString();
        if (expenseId != null && expenseId.isNotEmpty) {
          AppNav.openExpense(expenseId);
        }
      case 'payment':
      case 'reminder':
        openPerson(fromUid ?? data['fromUid']?.toString());
      case 'group':
        final groupId = data['groupId']?.toString();
        final g = groupId == null ? null : GroupController.to.groupById(groupId);
        if (g != null) {
          AppNav.openGroup(g);
        } else {
          AppToast.info('You\'re no longer in this group');
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: Obx(() {
          final unread = _nc.unreadCount;
          final hasAny = _nc.notifications.isNotEmpty;
          return AppTopBar(
            title: 'Notifications',
            subtitle: unread > 0 ? '$unread unread' : null,
            actions: [
              if (unread > 0)
                AppIconButton(
                  icon: Icons.done_all_rounded,
                  tooltip: 'Mark all read',
                  size: 42,
                  onPressed: _markingAll ? null : _markAllRead,
                ),
              if (hasAny) ...[
                const SizedBox(width: AppSpacing.sm),
                AppIconButton(
                  icon: Icons.delete_sweep_outlined,
                  tooltip: 'Clear all',
                  size: 42,
                  color: AppColors.error,
                  onPressed: _clearing ? null : _clearAll,
                ),
              ],
            ],
          );
        }),
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          _nc.fetchNotifications();
          await Future.delayed(const Duration(milliseconds: 500));
        },
        child: Obx(_buildBody),
      ),
    );
  }

  Widget _buildBody() {
    final list = _nc.notifications
        .where((n) => !_removed.contains(n['id']?.toString()))
        .toList();
    final loading = _nc.isLoading.value;
    final error = _nc.hasError.value;

    final Widget child;
    if (error && list.isEmpty) {
      child = _FillScroll(
        key: const ValueKey('error'),
        child: ErrorState(
          title: 'Couldn\'t load notifications',
          onRetry: _nc.fetchNotifications,
        ),
      );
    } else if (loading && list.isEmpty) {
      child = const SkeletonList(
        key: ValueKey('loading'),
        count: 7,
        padding: EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.sm,
          AppSpacing.page,
          AppSpacing.xxl,
        ),
      );
    } else if (list.isEmpty) {
      child = const _FillScroll(
        key: ValueKey('empty'),
        child: EmptyState(
          icon: Icons.notifications_none_rounded,
          title: 'You\'re all caught up',
          message:
              'New expenses, payments, reminders and friend requests will appear here.',
          orbitIcons: [
            Icons.receipt_long_rounded,
            Icons.payments_rounded,
            Icons.person_add_rounded,
          ],
        ),
      );
    } else {
      final rows = <Object>[];
      String? current;
      for (final n in list) {
        final label = Fmt.dayGroup(n['createdAt']);
        if (label != current) {
          rows.add(label);
          current = label;
        }
        rows.add(n);
      }
      child = ListView.builder(
        key: const ValueKey('list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.xs,
          AppSpacing.page,
          AppSpacing.xxxl,
        ),
        itemCount: rows.length,
        itemBuilder: (context, i) {
          final row = rows[i];
          if (row is String) return _SectionLabel(label: row, first: i == 0);
          final n = row as Map<String, dynamic>;
          final id = n['id'].toString();
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md - 2),
            child: FadeSlideIn(
              key: ValueKey('fade-$id'),
              index: i.clamp(0, 8),
              child: Dismissible(
                key: ValueKey(id),
                direction: DismissDirection.endToStart,
                background: const _DeleteBackground(),
                onDismissed: (_) => _delete(n),
                child: _NotificationCard(
                  notification: n,
                  onTap: () => _open(n),
                ),
              ),
            ),
          );
        },
      );
    }
    return AnimatedSwitcher(duration: AppMotion.normal, child: child);
  }
}

class _NotificationCard extends StatelessWidget {
  final Map<String, dynamic> notification;
  final VoidCallback onTap;

  const _NotificationCard({required this.notification, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final unread = n['isRead'] != true;
    final rawColor = n['iconColor'];
    final color = rawColor is int ? Color(rawColor) : AppColors.primary;
    final title = (n['title'] ?? 'Notification').toString();
    final message = (n['message'] ?? '').toString();

    return AppCard(
      onTap: onTap,
      color: unread ? AppColors.primaryLight : AppColors.surface,
      border: unread
          ? Border.all(color: AppColors.primary.withValues(alpha: 0.14))
          : null,
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(
            icon: NotificationController.iconFromName(n['iconName']?.toString()),
            color: color,
            size: 44,
            iconSize: 21,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight:
                              unread ? FontWeight.w700 : FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (unread)
                      Container(
                        width: 9,
                        height: 9,
                        margin: const EdgeInsets.only(left: 8, top: 5),
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
                if (message.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    message,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(
                      Icons.schedule_rounded,
                      size: 13,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      Fmt.relative(n['createdAt']),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textMuted,
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

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
      decoration: BoxDecoration(
        gradient: AppColors.negativeGradient,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Delete',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          SizedBox(width: AppSpacing.sm),
          Icon(Icons.delete_outline_rounded, color: Colors.white),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final bool first;

  const _SectionLabel({required this.label, required this.first});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: first ? AppSpacing.sm : AppSpacing.lg,
        bottom: AppSpacing.sm + 2,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          const Expanded(child: Divider(color: AppColors.border, height: 1)),
        ],
      ),
    );
  }
}

/// Makes a full-height state widget pull-to-refreshable.
class _FillScroll extends StatelessWidget {
  final Widget child;
  const _FillScroll({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: child,
          ),
        ],
      ),
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';

import '../app/routes/app_routes.dart';
import '../controllers/expense_controller.dart';
import '../controllers/friend_controller.dart';
import '../controllers/group_controller.dart';
import '../controllers/shell_controller.dart';
import '../core/ui.dart';
import 'widgets/expense_tile.dart';

/// Group detail. Opened with the group map in `Get.arguments` (must contain
/// `id`); then follows the live group document.
class GroupDetailScreen extends StatefulWidget {
  const GroupDetailScreen({super.key});

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen>
    with SingleTickerProviderStateMixin {
  late final Map<String, dynamic>? _initial;
  late final String? _id;
  Stream<Map<String, dynamic>?>? _groupStream;
  Stream<List<Map<String, dynamic>>>? _expensesStream;
  late final TabController _tabs = TabController(length: 3, vsync: this);
  bool _busy = false;
  String? _busyMessage;

  @override
  void initState() {
    super.initState();
    final args = Get.arguments;
    _initial = args is Map ? Map<String, dynamic>.from(args) : null;
    final raw = _initial?['id']?.toString();
    final id = (raw == null || raw.isEmpty) ? null : raw;
    _id = id;
    if (id != null) {
      _groupStream = GroupController.to.groupStream(id);
      _expensesStream = ExpenseController.to.groupExpensesStream(id);
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _retryGroup() {
    final id = _id;
    if (id == null) return;
    setState(() => _groupStream = GroupController.to.groupStream(id));
  }

  void _retryExpenses() {
    final id = _id;
    if (id == null) return;
    setState(() => _expensesStream = ExpenseController.to.groupExpensesStream(id));
  }

  Future<void> _refreshExpenses() async {
    _retryExpenses();
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }

  void _close() {
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_id == null) return _unavailable();
    return StreamBuilder<Map<String, dynamic>?>(
      stream: _groupStream,
      initialData: _initial,
      builder: (context, snap) {
        if (snap.hasError) {
          final text = snap.error.toString();
          if (text.contains('permission-denied')) return _unavailable();
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppTopBar(title: (_initial?['name'] ?? 'Group').toString()),
            body: ErrorState(
              title: 'Couldn\'t load this group',
              onRetry: _retryGroup,
            ),
          );
        }
        final group = snap.data;
        if (group == null) return _unavailable();
        final g = {...group, 'id': _id};
        return LoadingOverlay(
          visible: _busy,
          message: _busyMessage,
          child: _buildContent(g),
        );
      },
    );
  }

  Widget _unavailable() {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const AppTopBar(title: 'Group'),
      body: EmptyState(
        icon: Icons.group_off_rounded,
        color: AppColors.textSecondary,
        title: 'This group isn\'t available',
        message: 'It may have been deleted, or you\'re no longer a member.',
        actionLabel: 'Go back',
        actionIcon: Icons.arrow_back_rounded,
        onAction: _close,
      ),
    );
  }

  // ---------- Layout ----------

  Widget _buildContent(Map<String, dynamic> group) {
    final media = MediaQuery.of(context);
    final topPad = media.padding.top;
    const toolbar = 60.0;
    final heroContent = media.textScaler.scale(196);
    final expanded = toolbar + heroContent;
    final type = GroupTypes.of(group['icon']?.toString());
    final dark = Color.lerp(type.color, AppColors.primaryDark, 0.55)!;
    final name = (group['name'] ?? 'Group').toString();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            pinned: true,
            expandedHeight: expanded,
            toolbarHeight: toolbar,
            backgroundColor: dark,
            surfaceTintColor: Colors.transparent,
            systemOverlayStyle: SystemUiOverlayStyle.light,
            automaticallyImplyLeading: false,
            leadingWidth: 64,
            leading: Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Center(
                child: AppIconButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  tooltip: 'Back',
                  size: 40,
                  color: Colors.white,
                  background: Colors.white.withValues(alpha: 0.18),
                  onPressed: _close,
                ),
              ),
            ),
            actions: [
              _OverflowMenu(onSelected: (a) => _onMenu(a, group), isCreator: GroupController.to.isCreator(group)),
              const SizedBox(width: 16),
            ],
            flexibleSpace: LayoutBuilder(
              builder: (context, c) {
                final min = toolbar + topPad;
                final max = expanded + topPad;
                final t = ((c.maxHeight - min) / (max - min)).clamp(0.0, 1.0);
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [type.color, dark],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
                    Positioned(
                      right: -40,
                      top: -30,
                      child: Icon(
                        type.icon,
                        size: 200,
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
                    // Collapsed title
                    Positioned(
                      left: 72,
                      right: 72,
                      top: topPad,
                      height: toolbar,
                      child: IgnorePointer(
                        child: Opacity(
                          opacity: (1 - t * 2.5).clamp(0.0, 1.0),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Expanded hero
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Opacity(
                        opacity: ((t - 0.25) / 0.75).clamp(0.0, 1.0),
                        child: _Hero(group: group, type: type),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          SliverToBoxAdapter(child: _buildActions(group)),
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabBarDelegate(
              TabBar(
                controller: _tabs,
                indicator: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  boxShadow: AppShadows.soft,
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                indicatorPadding: const EdgeInsets.all(4),
                dividerColor: Colors.transparent,
                labelColor: AppColors.textPrimary,
                unselectedLabelColor: AppColors.textSecondary,
                labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                unselectedLabelStyle:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                overlayColor: const WidgetStatePropertyAll(Colors.transparent),
                splashFactory: NoSplash.splashFactory,
                tabs: const [
                  Tab(text: 'Expenses'),
                  Tab(text: 'Balances'),
                  Tab(text: 'Members'),
                ],
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabs,
          children: [
            _expensesTab(group),
            _balancesTab(group),
            _membersTab(group),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(Map<String, dynamic> group) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.lg,
        AppSpacing.page,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: _QuickAction(
              icon: Icons.add_rounded,
              label: 'Add expense',
              color: AppColors.primary,
              filled: true,
              onTap: () => _addExpense(group),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: _QuickAction(
              icon: Icons.handshake_rounded,
              label: 'Settle up',
              color: AppColors.positive,
              onTap: () => Get.toNamed(AppRoutes.settleUp),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: _QuickAction(
              icon: Icons.account_balance_wallet_rounded,
              label: 'Balances',
              color: AppColors.secondary,
              onTap: () => _tabs.animateTo(1),
            ),
          ),
        ],
      ),
    );
  }

  void _addExpense(Map<String, dynamic> group) {
    AppNav.addExpense(arguments: {
      'groupId': _id,
      'groupName': (group['name'] ?? 'Group').toString(),
      'currencyCode': (group['currencyCode'] ?? 'USD').toString(),
      'members': GroupController.membersOf(group),
    });
  }

  // ---------- Expenses tab ----------

  Widget _expensesTab(Map<String, dynamic> group) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _expensesStream,
      builder: (context, snap) {
        final Widget child;
        if (snap.hasError) {
          child = ErrorState(
            key: const ValueKey('err'),
            title: 'Couldn\'t load expenses',
            onRetry: _retryExpenses,
          );
        } else if (!snap.hasData) {
          child = const SkeletonList(
            key: ValueKey('loading'),
            count: 5,
            padding: EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.lg,
              AppSpacing.page,
              AppSpacing.lg,
            ),
          );
        } else if (snap.data!.isEmpty) {
          child = RefreshIndicator(
            key: const ValueKey('empty'),
            onRefresh: _refreshExpenses,
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                EmptyState(
                  icon: Icons.receipt_long_rounded,
                  title: 'No expenses yet',
                  message: 'Add the first shared expense and SplitShare will '
                      'keep track of who owes whom.',
                  illustrationSize: 140,
                  actionLabel: 'Add expense',
                  actionIcon: Icons.add_rounded,
                  onAction: () => _addExpense(group),
                ),
              ],
            ),
          );
        } else {
          child = _expenseList(snap.data!);
        }
        return AnimatedSwitcher(duration: AppMotion.normal, child: child);
      },
    );
  }

  Widget _expenseList(List<Map<String, dynamic>> expenses) {
    DateTime when(Map<String, dynamic> e) =>
        Fmt.toDate(e['date']) ?? Fmt.toDate(e['createdAt']) ?? DateTime.now();
    final sorted = [...expenses]..sort((a, b) => when(b).compareTo(when(a)));

    // Flatten into headers + rows.
    final items = <Object>[];
    String? last;
    for (final e in sorted) {
      final label = Fmt.dayGroup(when(e));
      if (label != last) {
        items.add(label);
        last = label;
      }
      items.add(e);
    }

    return RefreshIndicator(
      key: const ValueKey('list'),
      onRefresh: _refreshExpenses,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.sm,
          AppSpacing.page,
          AppSpacing.xxxl,
        ),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final item = items[i];
          if (item is String) {
            return Padding(
              padding: EdgeInsets.only(
                top: i == 0 ? AppSpacing.sm : AppSpacing.lg,
                bottom: AppSpacing.sm,
                left: 2,
              ),
              child: Text(
                item.toUpperCase(),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: AppColors.textMuted,
                ),
              ),
            );
          }
          final e = item as Map<String, dynamic>;
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: FadeSlideIn(
              key: ValueKey(e['id']),
              index: i,
              child: ExpenseTile(expense: e),
            ),
          );
        },
      ),
    );
  }

  // ---------- Balances tab ----------

  Widget _balancesTab(Map<String, dynamic> group) {
    final currency = (group['currencyCode'] ?? 'USD').toString();
    return Obx(() {
      final ctrl = ExpenseController.to;
      ctrl.openExpenses.length;
      if (ctrl.isLoading.value && ctrl.openExpenses.isEmpty) {
        return const SkeletonList(
          count: 4,
          padding: EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.lg,
            AppSpacing.page,
            AppSpacing.lg,
          ),
        );
      }
      if (ctrl.hasError.value) {
        return ErrorState(
          title: 'Couldn\'t load balances',
          onRetry: ctrl.refreshData,
        );
      }
      final me = ctrl.currentUid;
      final byMember = ctrl.groupMemberBalances(_id!);
      final mine = ctrl.groupBalance(_id);
      final members = GroupController.membersOf(group);

      if (byMember.isEmpty) {
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            EmptyState(
              icon: Icons.verified_rounded,
              color: AppColors.positive,
              title: 'All settled up',
              message: 'Nobody owes anything in this group right now.',
              illustrationSize: 140,
              actionLabel: 'Add expense',
              actionIcon: Icons.add_rounded,
              onAction: () => _addExpense(group),
            ),
          ],
        );
      }

      // Members first (in group order), then anyone who left but still has a balance.
      final rows = <Map<String, dynamic>>[
        for (final m in members)
          if (m['uid'] != me) m,
        for (final uid in byMember.keys)
          if (uid != me && !members.any((m) => m['uid'] == uid))
            {'uid': uid, 'name': ctrl.nameFor(uid), 'avatarUrl': ''},
      ]..sort((a, b) {
          final ab = byMember.containsKey(a['uid']) ? 0 : 1;
          final bb = byMember.containsKey(b['uid']) ? 0 : 1;
          return ab.compareTo(bb);
        });

      return ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.lg,
          AppSpacing.page,
          AppSpacing.xxxl,
        ),
        children: [
          AppCard(
            child: Row(
              children: [
                const IconBadge(
                  icon: Icons.account_balance_wallet_rounded,
                  color: AppColors.primary,
                ),
                const SizedBox(width: AppSpacing.md),
                const Expanded(
                  child: Text(
                    'Your position in this group',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: BalanceLabel(byCurrency: mine, preferredCurrency: currency),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const Padding(
            padding: EdgeInsets.only(left: 2, bottom: AppSpacing.sm),
            child: Text(
              'WITH EACH MEMBER',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: AppColors.textMuted,
              ),
            ),
          ),
          for (var i = 0; i < rows.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: FadeSlideIn(
                index: i,
                child: _BalanceRow(
                  person: rows[i],
                  byCurrency: byMember[rows[i]['uid']] ?? const {},
                  currency: currency,
                ),
              ),
            ),
        ],
      );
    });
  }

  // ---------- Members tab ----------

  Widget _membersTab(Map<String, dynamic> group) {
    final members = GroupController.membersOf(group);
    final me = ExpenseController.to.currentUid;
    final creator = group['createdBy']?.toString();
    final sorted = [...members]..sort((a, b) {
        if (a['uid'] == me) return -1;
        if (b['uid'] == me) return 1;
        return (a['name'] ?? '').toString().toLowerCase().compareTo(
              (b['name'] ?? '').toString().toLowerCase(),
            );
      });

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.lg,
        AppSpacing.page,
        AppSpacing.xxxl,
      ),
      children: [
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: AppListTile(
            icon: Icons.person_add_alt_1_rounded,
            title: 'Add members',
            subtitle: 'Invite friends to this group',
            onTap: () => _showAddMembers(group),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: AppSpacing.sm),
          child: Text(
            '${members.length} ${members.length == 1 ? 'MEMBER' : 'MEMBERS'}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: AppColors.textMuted,
            ),
          ),
        ),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            children: [
              for (var i = 0; i < sorted.length; i++) ...[
                if (i > 0)
                  const Divider(height: 1, indent: 70, color: AppColors.border),
                _memberRow(sorted[i], isMe: sorted[i]['uid'] == me,
                    isCreator: sorted[i]['uid'] == creator),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _memberRow(Map<String, dynamic> m,
      {required bool isMe, required bool isCreator}) {
    final uid = (m['uid'] ?? '').toString();
    final name = (m['name'] ?? 'Member').toString();
    final email = (m['email'] ?? '').toString();
    final isFriend = !isMe && FriendController.to.isAlreadyFriend(uid);
    return InkWell(
      onTap: isFriend
          ? () => AppNav.openFriend(uid, data: {
                'name': name,
                'avatarUrl': m['avatarUrl'],
                'email': email,
              })
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            AppAvatar(name: name, imageUrl: m['avatarUrl']?.toString(), radius: 21),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          isMe ? '$name (You)' : name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (email.isNotEmpty)
                    Text(
                      email,
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
            if (isCreator) ...[
              const SizedBox(width: AppSpacing.sm),
              const StatusPill(
                label: 'Creator',
                color: AppColors.warning,
                icon: Icons.star_rounded,
              ),
            ],
            if (isFriend)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
              ),
          ],
        ),
      ),
    );
  }

  // ---------- Menu actions ----------

  void _onMenu(_MenuAction a, Map<String, dynamic> group) {
    switch (a) {
      case _MenuAction.edit:
        _showEdit(group);
      case _MenuAction.addMembers:
        _showAddMembers(group);
      case _MenuAction.share:
        _share(group);
      case _MenuAction.leave:
        _leave(group);
      case _MenuAction.delete:
        _delete(group);
    }
  }

  void _showEdit(Map<String, dynamic> group) {
    AppDialogs.sheet<void>(
      title: 'Edit group',
      child: _EditGroupSheet(groupId: _id!, group: group),
    );
  }

  void _showAddMembers(Map<String, dynamic> group) {
    AppDialogs.sheet<void>(
      title: 'Add members',
      child: _AddMembersSheet(groupId: _id!, group: group),
    );
  }

  Future<void> _share(Map<String, dynamic> group) async {
    final ctrl = ExpenseController.to;
    final me = ctrl.currentUid;
    final name = (group['name'] ?? 'Group').toString();
    final currency = (group['currencyCode'] ?? 'USD').toString();
    final members = GroupController.membersOf(group);
    final byMember = ctrl.groupMemberBalances(_id!);

    final buf = StringBuffer()
      ..writeln('$name — SplitShare summary')
      ..writeln('${members.length} members · $currency')
      ..writeln();
    final lines = <String>[];
    byMember.forEach((uid, map) {
      if (uid == me) return;
      final member = members.firstWhereOrNull((m) => m['uid'] == uid);
      final who = (member?['name'] ?? ctrl.nameFor(uid)).toString();
      final owesMe = Map.fromEntries(map.entries.where((e) => e.value > 0));
      final iOwe = Map.fromEntries(map.entries.where((e) => e.value < 0));
      if (owesMe.isNotEmpty) {
        lines.add('• $who owes me ${Fmt.multi(owesMe, preferred: currency)}');
      }
      if (iOwe.isNotEmpty) {
        lines.add('• I owe $who ${Fmt.multi(iOwe, preferred: currency)}');
      }
    });
    if (lines.isEmpty) {
      buf.writeln('Everyone is settled up.');
    } else {
      buf.writeln('Balances with me:');
      lines.forEach(buf.writeln);
      final mine = ctrl.groupBalance(_id);
      final dir = mine.isEmpty
          ? BalanceDirection.settled
          : BalanceDirectionX.fromNet(mine[currency] ?? mine.values.first);
      buf
        ..writeln()
        ..writeln(dir == BalanceDirection.settled
            ? 'Overall I\'m settled up.'
            : dir == BalanceDirection.owedToYou
                ? 'Overall I\'m owed ${Fmt.multi(mine, preferred: currency)}.'
                : 'Overall I owe ${Fmt.multi(mine, preferred: currency)}.');
    }
    buf
      ..writeln()
      ..write('Shared from SplitShare');

    try {
      await SharePlus.instance.share(
        ShareParams(text: buf.toString(), subject: '$name — balances'),
      );
    } catch (e) {
      AppToast.error(AppToast.friendly(e), title: 'Couldn\'t share');
    }
  }

  Future<void> _leave(Map<String, dynamic> group) async {
    final name = (group['name'] ?? 'this group').toString();
    final ok = await AppDialogs.confirm(
      title: 'Leave "$name"?',
      message: 'You\'ll stop seeing this group. You can only leave once your '
          'balance in it is settled.',
      confirmLabel: 'Leave',
      destructive: true,
      icon: Icons.logout_rounded,
    );
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _busyMessage = 'Leaving group…';
    });
    try {
      await GroupController.to.leaveGroup(_id!);
      if (!mounted) return;
      _close();
      AppToast.success('You left "$name".');
    } on GroupException catch (e) {
      if (mounted) setState(() => _busy = false);
      AppToast.warning(e.message, title: 'Can\'t leave yet');
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      AppToast.error(AppToast.friendly(e));
    }
  }

  Future<void> _delete(Map<String, dynamic> group) async {
    final name = (group['name'] ?? 'this group').toString();
    final ok = await AppDialogs.confirm(
      title: 'Delete "$name"?',
      message: 'The group will be removed for every member. Its expenses stay '
          'in everyone\'s history and balances. This can\'t be undone.',
      confirmLabel: 'Delete',
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _busyMessage = 'Deleting group…';
    });
    try {
      await GroupController.to.deleteGroup(_id!);
      if (!mounted) return;
      _close();
      AppToast.success('"$name" was deleted.');
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      AppToast.error(AppToast.friendly(e), title: 'Couldn\'t delete group');
    }
  }
}

// =====================================================================
// Header pieces
// =====================================================================

class _Hero extends StatelessWidget {
  final Map<String, dynamic> group;
  final CategoryStyle type;
  const _Hero({required this.group, required this.type});

  @override
  Widget build(BuildContext context) {
    final members = GroupController.membersOf(group);
    final currency = (group['currencyCode'] ?? 'USD').toString();
    final id = group['id'].toString();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        0,
        AppSpacing.page,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconBadge(icon: type.icon, color: Colors.white, size: 56, iconSize: 28),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (group['name'] ?? 'Group').toString(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${members.length} member${members.length == 1 ? '' : 's'} · $currency',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              boxShadow: AppShadows.medium,
            ),
            child: Row(
              children: [
                AvatarStack(people: members, radius: 13, max: 4),
                const SizedBox(width: AppSpacing.sm),
                const Expanded(
                  child: Text(
                    'Your balance',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                Flexible(
                  flex: 2,
                  child: Obx(() {
                    final ctrl = ExpenseController.to;
                    ctrl.openExpenses.length;
                    return BalanceLabel(
                      byCurrency: ctrl.groupBalance(id),
                      preferredCurrency: currency,
                    );
                  }),
                ),
              ],
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
  final bool filled;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      gradient: filled ? AppColors.brandGradient : null,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconBadge(
            icon: icon,
            color: filled ? Colors.white : color,
            size: 38,
            iconSize: 20,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: filled ? Colors.white : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

enum _MenuAction { edit, addMembers, share, leave, delete }

class _OverflowMenu extends StatelessWidget {
  final ValueChanged<_MenuAction> onSelected;
  final bool isCreator;
  const _OverflowMenu({required this.onSelected, required this.isCreator});

  PopupMenuItem<_MenuAction> _item(
    _MenuAction value,
    IconData icon,
    String label, {
    bool destructive = false,
  }) {
    final color = destructive ? AppColors.error : AppColors.textPrimary;
    return PopupMenuItem(
      value: value,
      height: 48,
      child: Row(
        children: [
          Icon(icon, size: 20, color: destructive ? AppColors.error : AppColors.textSecondary),
          const SizedBox(width: AppSpacing.md),
          Text(
            label,
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_MenuAction>(
      tooltip: 'More options',
      onSelected: onSelected,
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      itemBuilder: (_) => [
        _item(_MenuAction.edit, Icons.edit_rounded, 'Edit group'),
        _item(_MenuAction.addMembers, Icons.person_add_alt_1_rounded, 'Add members'),
        _item(_MenuAction.share, Icons.ios_share_rounded, 'Share summary'),
        const PopupMenuDivider(),
        _item(_MenuAction.leave, Icons.logout_rounded, 'Leave group', destructive: true),
        if (isCreator)
          _item(_MenuAction.delete, Icons.delete_outline_rounded, 'Delete group',
              destructive: true),
      ],
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: const Icon(Icons.more_horiz_rounded, color: Colors.white),
      ),
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  _TabBarDelegate(this.tabBar);

  static const double _height = 68;

  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, 8, AppSpacing.page, 8),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: AppColors.border),
        ),
        child: tabBar,
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) =>
      oldDelegate.tabBar != tabBar;
}

class _BalanceRow extends StatelessWidget {
  final Map<String, dynamic> person;
  final Map<String, double> byCurrency;
  final String currency;

  const _BalanceRow({
    required this.person,
    required this.byCurrency,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final uid = (person['uid'] ?? '').toString();
    final name = (person['name'] ?? 'Member').toString();
    final hasBalance = byCurrency.isNotEmpty;
    return AppCard(
      onTap: hasBalance
          ? () => Get.toNamed(AppRoutes.settleUp, arguments: {'uid': uid})
          : null,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          AppAvatar(name: name, imageUrl: person['avatarUrl']?.toString(), radius: 21),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (hasBalance)
                  const Text(
                    'Tap to settle up',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: BalanceLabel(byCurrency: byCurrency, preferredCurrency: currency),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// Sheets
// =====================================================================

class _EditGroupSheet extends StatefulWidget {
  final String groupId;
  final Map<String, dynamic> group;
  const _EditGroupSheet({required this.groupId, required this.group});

  @override
  State<_EditGroupSheet> createState() => _EditGroupSheetState();
}

class _EditGroupSheetState extends State<_EditGroupSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _nameCtrl =
      TextEditingController(text: (widget.group['name'] ?? '').toString());
  late String _type = GroupTypes.of(widget.group['icon']?.toString()).name;
  late String _currency = (widget.group['currencyCode'] ?? 'USD').toString();
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await GroupController.to.updateGroup(
        widget.groupId,
        name: _nameCtrl.text.trim(),
        icon: _type,
        currencyCode: _currency,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      AppToast.success('Group updated.');
    } on GroupException catch (e) {
      if (mounted) setState(() => _saving = false);
      AppToast.warning(e.message);
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      AppToast.error(AppToast.friendly(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(
              controller: _nameCtrl,
              label: 'Group name',
              prefixIcon: Icons.edit_rounded,
              maxLength: 40,
              textCapitalization: TextCapitalization.sentences,
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return 'Give your group a name';
                if (t.length < 2) return 'Name is too short';
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            const _SheetLabel('Group type'),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final t in GroupTypes.all)
                  _Chip(
                    label: t.name,
                    icon: t.icon,
                    color: t.color,
                    selected: _type == t.name,
                    onTap: () => setState(() => _type = t.name),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            const _SheetLabel('Default currency'),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final code in Currencies.symbols.keys)
                  _Chip(
                    label: '${Currencies.symbolFor(code)} $code',
                    color: AppColors.primary,
                    selected: _currency == code,
                    onTap: () => setState(() => _currency = code),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Changing the currency only affects new expenses.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xxl),
            AppButton(
              label: 'Save changes',
              icon: Icons.check_rounded,
              loading: _saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}

class _AddMembersSheet extends StatefulWidget {
  final String groupId;
  final Map<String, dynamic> group;
  const _AddMembersSheet({required this.groupId, required this.group});

  @override
  State<_AddMembersSheet> createState() => _AddMembersSheetState();
}

class _AddMembersSheetState extends State<_AddMembersSheet> {
  final _searchCtrl = TextEditingController();
  final Set<String> _selected = {};
  String _query = '';
  bool _saving = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    if (_selected.isEmpty) return;
    setState(() => _saving = true);
    try {
      await GroupController.to.addMembers(widget.groupId, _selected.toList());
      if (!mounted) return;
      final n = _selected.length;
      Navigator.of(context).pop();
      AppToast.success('Added $n ${n == 1 ? 'member' : 'members'}.');
    } on GroupException catch (e) {
      if (mounted) setState(() => _saving = false);
      AppToast.warning(e.message);
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      AppToast.error(AppToast.friendly(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final inGroup = ((widget.group['members'] as List?) ?? const [])
        .map((e) => e.toString())
        .toSet();
    final maxHeight = MediaQuery.of(context).size.height * 0.7;

    return Obx(() {
      final friends = FriendController.to.friends
          .where((f) => !inGroup.contains((f['uid'] ?? '').toString()))
          .toList();

      if (friends.isEmpty) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const IconBadge(
                icon: Icons.person_search_rounded,
                color: AppColors.primary,
                size: 60,
                iconSize: 30,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                FriendController.to.friends.isEmpty
                    ? 'You don\'t have any friends yet'
                    : 'All your friends are already here',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              const Text(
                'Add friends on SplitShare to invite them to this group.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.xl),
              AppButton(
                label: 'Add friends',
                icon: Icons.person_add_rounded,
                onPressed: () {
                  Navigator.of(context).pop();
                  Get.toNamed(AppRoutes.addFriends);
                },
              ),
            ],
          ),
        );
      }

      final q = _query.trim().toLowerCase();
      final shown = q.isEmpty
          ? friends
          : friends.where((f) {
              return (f['name'] ?? '').toString().toLowerCase().contains(q) ||
                  (f['email'] ?? '').toString().toLowerCase().contains(q);
            }).toList();

      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: math.max(320, maxHeight)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
              child: AppSearchField(
                controller: _searchCtrl,
                hint: 'Search friends',
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Flexible(
              child: shown.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(AppSpacing.xxl),
                      child: Text(
                        'No friends match "${_query.trim()}"',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: shown.length,
                      itemBuilder: (context, i) {
                        final f = shown[i];
                        final uid = (f['uid'] ?? '').toString();
                        final name = (f['name'] ?? 'Friend').toString();
                        final email = (f['email'] ?? '').toString();
                        final sel = _selected.contains(uid);
                        return InkWell(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          onTap: () => setState(() {
                            sel ? _selected.remove(uid) : _selected.add(uid);
                          }),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                AppAvatar(
                                  name: name,
                                  imageUrl: f['avatarUrl']?.toString(),
                                  radius: 20,
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
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      if (email.isNotEmpty)
                                        Text(
                                          email,
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
                                Checkbox(
                                  value: sel,
                                  activeColor: AppColors.primary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  onChanged: (_) => setState(() {
                                    sel ? _selected.remove(uid) : _selected.add(uid);
                                  }),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              child: AppButton(
                label: _selected.isEmpty
                    ? 'Select friends to add'
                    : 'Add ${_selected.length} '
                        '${_selected.length == 1 ? 'member' : 'members'}',
                icon: Icons.group_add_rounded,
                loading: _saving,
                onPressed: _selected.isEmpty ? null : _add,
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _SheetLabel extends StatelessWidget {
  final String text;
  const _SheetLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: AppSpacing.sm),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      );
}

class _Chip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        padding: EdgeInsets.symmetric(horizontal: icon == null ? 14 : 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.12) : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: selected ? color : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 17, color: selected ? color : AppColors.textSecondary),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: selected ? color : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

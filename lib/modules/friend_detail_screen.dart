import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../app/routes/app_routes.dart';
import '../controllers/expense_controller.dart';
import '../controllers/friend_controller.dart';
import '../controllers/profile_controller.dart';
import '../controllers/shell_controller.dart';
import '../core/ui.dart';
import 'widgets/expense_tile.dart';

/// Profile of one person: live balance, quick actions and every expense
/// shared with them. Works for friends and for non-friends you share
/// expenses with.
///
/// Arguments: `{'uid': String, 'name'?, 'avatarUrl'?, 'email'?}`.
class FriendDetailScreen extends StatefulWidget {
  const FriendDetailScreen({super.key});

  @override
  State<FriendDetailScreen> createState() => _FriendDetailScreenState();
}

class _FriendDetailScreenState extends State<FriendDetailScreen> {
  late final Map<String, dynamic> _args;
  late final String _uid;
  Map<String, dynamic>? _fetched;
  Stream<List<Map<String, dynamic>>>? _sharedStream;

  bool _sendingRequest = false;
  bool _reminding = false;
  bool _removing = false;

  FriendController get _friends => FriendController.to;
  ExpenseController get _expenses => ExpenseController.to;

  @override
  void initState() {
    super.initState();
    final raw = Get.arguments;
    _args = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    _uid = (_args['uid'] ?? '').toString();
    if (_uid.isEmpty) return;
    _sharedStream = _expenses.sharedWithStream(_uid);
    if (_friends.friendByUid(_uid) == null) _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    final user = await _friends.getUser(_uid);
    if (!mounted || user == null) return;
    setState(() => _fetched = user);
  }

  void _retryShared() {
    setState(() => _sharedStream = _expenses.sharedWithStream(_uid));
  }

  /// Merges route args, a one-off fetched profile and the live friend doc.
  Map<String, dynamic> _person() {
    final friend = _friends.friendByUid(_uid);
    final settle = _expenses.settleUpData[_uid];
    final merged = <String, dynamic>{};
    void take(Map<String, dynamic>? src) {
      if (src == null) return;
      src.forEach((k, v) {
        if (v == null) return;
        if (v is String && v.trim().isEmpty) return;
        merged[k] = v;
      });
    }

    take(
      settle == null
          ? null
          : {
              'name': settle['name'] == 'Unknown' ? null : settle['name'],
              'avatarUrl': settle['avatarUrl'],
            },
    );
    take(_args);
    take(_fetched);
    take(friend);
    return merged;
  }

  String _nameOf(Map<String, dynamic> p) {
    final n = (p['name'] ?? '').toString().trim();
    return n.isEmpty ? 'SplitShare user' : n;
  }

  // ---------- Actions ----------

  Future<void> _sendRequest() async {
    if (_sendingRequest) return;
    setState(() => _sendingRequest = true);
    await _friends.sendFriendRequest(_uid);
    if (mounted) setState(() => _sendingRequest = false);
  }

  void _addExpense(Map<String, dynamic> p) {
    AppNav.addExpense(
      arguments: {
        'friend': {
          'uid': _uid,
          'name': _nameOf(p),
          'avatarUrl': (p['avatarUrl'] ?? '').toString(),
        },
      },
    );
  }

  void _settleUp(bool hasBalance, String name) {
    if (!hasBalance) {
      AppToast.info(
        'You and ${Fmt.firstName(name)} are all square.',
        title: 'Nothing to settle',
      );
      return;
    }
    Get.toNamed(AppRoutes.settleUp, arguments: {'uid': _uid});
  }

  Future<void> _remind(String name) async {
    if (_reminding) return;
    setState(() => _reminding = true);
    try {
      await _expenses.sendReminder(_uid);
      AppToast.success(
        'We\'ve nudged ${Fmt.firstName(name)} about what they owe.',
        title: 'Reminder sent',
      );
    } on ExpenseValidationException catch (e) {
      AppToast.info(e.message);
    } catch (e) {
      AppToast.error(AppToast.friendly(e), title: 'Couldn\'t send reminder');
    } finally {
      if (mounted) setState(() => _reminding = false);
    }
  }

  Future<void> _openMenu(String name) async {
    final remove = await AppDialogs.sheet<bool>(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.lg,
        ),
        child: Builder(
          builder: (ctx) => AppListTile(
            icon: Icons.person_remove_rounded,
            title: 'Remove friend',
            subtitle: 'Shared expenses and balances are kept',
            destructive: true,
            onTap: () => Navigator.of(ctx).pop(true),
          ),
        ),
      ),
    );
    if (remove == true) await _removeFriend(name);
  }

  Future<void> _removeFriend(String name) async {
    if (_removing) return;
    final ok = await AppDialogs.confirm(
      title: 'Remove ${Fmt.firstName(name)}?',
      message:
          'You\'ll no longer be friends. Expenses you share stay on both your accounts and any open balance still counts.',
      confirmLabel: 'Remove',
      destructive: true,
      icon: Icons.person_remove_rounded,
    );
    if (!ok || !mounted) return;
    setState(() => _removing = true);
    final removed = await _friends.removeFriend(_uid);
    if (!mounted) return;
    setState(() => _removing = false);
    if (removed) {
      AppToast.success(
        '$name was removed from your friends.',
        title: 'Friend removed',
      );
      Navigator.of(context).maybePop();
    }
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    if (_uid.isEmpty) {
      return Scaffold(
        appBar: const AppTopBar(title: 'Friend'),
        body: EmptyState(
          icon: Icons.person_off_rounded,
          title: 'Person not found',
          message: 'We couldn\'t open this profile.',
          actionLabel: 'Go back',
          onAction: () => Navigator.of(context).maybePop(),
        ),
      );
    }

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: Obx(() {
          final p = _person();
          final isFriend = _friends.isAlreadyFriend(_uid);
          return AppTopBar(
            title: _nameOf(p),
            actions: [
              if (isFriend)
                AppIconButton(
                  icon: Icons.more_horiz_rounded,
                  tooltip: 'More',
                  size: 42,
                  onPressed: _removing ? null : () => _openMenu(_nameOf(p)),
                ),
            ],
          );
        }),
      ),
      body: LoadingOverlay(
        visible: _removing,
        message: 'Removing…',
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                AppSpacing.sm,
                AppSpacing.page,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: Obx(() {
                  final p = _person();
                  final preferred = ProfileController.to.currencyCode.value;
                  final balance = _expenses.balanceWith(_uid);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FadeSlideIn(index: 0, child: _header(p)),
                      const SizedBox(height: AppSpacing.xl),
                      FadeSlideIn(
                        index: 1,
                        child: _BalanceCard(
                          name: _nameOf(p),
                          balance: balance,
                          preferred: preferred,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      FadeSlideIn(index: 2, child: _actions(p, balance)),
                    ],
                  );
                }),
              ),
            ),
            const SliverToBoxAdapter(
              child: SectionHeader(title: 'Shared expenses'),
            ),
            _sharedList(),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxxl)),
          ],
        ),
      ),
    );
  }

  Widget _header(Map<String, dynamic> p) {
    final name = _nameOf(p);
    final email = (p['email'] ?? '').toString();
    final friend = _friends.friendByUid(_uid);
    final isFriend = friend != null;
    final addedAt = friend?['addedAt'];
    final pending = _friends.sentRequests.contains(_uid);
    final incoming = _friends.friendRequests.firstWhereOrNull(
      (r) => r['fromUid'] == _uid,
    );

    return Column(
      children: [
        AppAvatar(
          name: name,
          imageUrl: (p['avatarUrl'] ?? '').toString(),
          radius: 46,
          ring: true,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          name,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (email.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            email,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        if (isFriend)
          StatusPill(
            label: Fmt.date(addedAt).isEmpty
                ? 'FRIENDS'
                : 'FRIENDS SINCE ${Fmt.date(addedAt).toUpperCase()}',
            color: AppColors.positive,
            icon: Icons.check_circle_rounded,
          )
        else ...[
          const StatusPill(
            label: 'NOT IN YOUR FRIENDS',
            color: AppColors.textSecondary,
            icon: Icons.person_outline_rounded,
          ),
          const SizedBox(height: AppSpacing.md),
          if (pending && incoming == null)
            const AppButton.outline(
              label: 'Request sent',
              icon: Icons.schedule_rounded,
              onPressed: null,
              expand: false,
              height: 42,
            )
          else
            AppButton.secondary(
              label: incoming != null ? 'Accept friend request' : 'Add friend',
              icon: Icons.person_add_alt_1_rounded,
              loading:
                  _sendingRequest ||
                  (incoming != null &&
                      _friends.busyRequests.contains(incoming['id'])),
              expand: false,
              height: 42,
              onPressed: _sendRequest,
            ),
        ],
      ],
    );
  }

  Widget _actions(Map<String, dynamic> p, Map<String, double> balance) {
    final name = _nameOf(p);
    final hasBalance = balance.values.any((v) => v.abs() >= 0.005);
    final owesMe = balance.values.any((v) => v >= 0.005);
    return AppCard(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.md,
        horizontal: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: _ActionTile(
              icon: Icons.add_rounded,
              label: 'Add expense',
              color: AppColors.primary,
              onTap: () => _addExpense(p),
            ),
          ),
          Expanded(
            child: _ActionTile(
              icon: Icons.handshake_rounded,
              label: 'Settle up',
              color: AppColors.positive,
              dimmed: !hasBalance,
              onTap: () => _settleUp(hasBalance, name),
            ),
          ),
          if (owesMe)
            Expanded(
              child: _ActionTile(
                icon: Icons.notifications_active_rounded,
                label: 'Remind',
                color: AppColors.warning,
                loading: _reminding,
                onTap: () => _remind(name),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sharedList() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _sharedStream,
      builder: (context, snap) {
        if (snap.hasError) {
          return SliverToBoxAdapter(
            child: ErrorState(
              title: 'Couldn\'t load shared expenses',
              onRetry: _retryShared,
            ),
          );
        }
        if (!snap.hasData) {
          return const SliverToBoxAdapter(
            child: SkeletonList(count: 3, shrinkWrap: true),
          );
        }
        final items = List<Map<String, dynamic>>.from(snap.data!);
        if (items.isEmpty) {
          return SliverToBoxAdapter(
            child: Builder(
              builder: (context) {
                final name = _nameOf(_person());
                return EmptyState(
                  icon: Icons.receipt_long_rounded,
                  illustrationSize: 130,
                  title: 'Nothing shared yet',
                  message:
                      'Expenses you split with ${Fmt.firstName(name)} — in groups or one-to-one — will show up here.',
                  actionLabel: 'Add an expense',
                  actionIcon: Icons.add_rounded,
                  onAction: () => _addExpense(_person()),
                );
              },
            ),
          );
        }

        // Build "header, tile, tile, header, tile..." rows grouped by day.
        final rows = <Object>[];
        String? current;
        for (final e in items) {
          final label = Fmt.dayGroup(e['createdAt'] ?? e['date']);
          if (label != current) {
            rows.add(label);
            current = label;
          }
          rows.add(e);
        }

        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
          sliver: SliverList.builder(
            itemCount: rows.length,
            itemBuilder: (_, i) {
              final row = rows[i];
              if (row is String) {
                return Padding(
                  padding: EdgeInsets.only(
                    top: i == 0 ? 0 : AppSpacing.lg,
                    bottom: AppSpacing.sm,
                    left: 4,
                  ),
                  child: Text(
                    row.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: AppColors.textMuted,
                    ),
                  ),
                );
              }
              final e = row as Map<String, dynamic>;
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: FadeSlideIn(
                  key: ValueKey('exp-${e['id']}'),
                  index: i,
                  child: ExpenseTile(expense: e),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final String name;
  final Map<String, double> balance;
  final String preferred;

  const _BalanceCard({
    required this.name,
    required this.balance,
    required this.preferred,
  });

  @override
  Widget build(BuildContext context) {
    final owed = <String, double>{};
    final owe = <String, double>{};
    balance.forEach((cur, v) {
      if (v >= 0.005) owed[cur] = v;
      if (v <= -0.005) owe[cur] = -v;
    });
    final first = Fmt.firstName(name);

    final settled = owed.isEmpty && owe.isEmpty;
    final primary =
        balance[preferred] ??
        (balance.values.where((v) => v.abs() >= 0.005).firstOrNull ?? 0);
    final dir = BalanceDirectionX.fromNet(primary);

    if (settled) {
      return AppCard(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Row(
          children: [
            const IconBadge(
              icon: Icons.verified_rounded,
              color: AppColors.positive,
              size: 52,
              iconSize: 26,
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'All settled up',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'You and $first don\'t owe each other anything.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final gradient = dir == BalanceDirection.youOwe
        ? AppColors.negativeGradient
        : AppColors.positiveGradient;

    Widget line(String caption, Map<String, double> m, {bool big = true}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            caption,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontWeight: FontWeight.w600,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            Fmt.multi(m, preferred: preferred),
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: big ? 30 : 20,
              letterSpacing: -0.5,
            ),
          ),
        ],
      );
    }

    final owedFirst = dir != BalanceDirection.youOwe;
    final blocks = <Widget>[
      if (owedFirst && owed.isNotEmpty) line('$first owes you', owed),
      if (owe.isNotEmpty)
        line('You owe $first', owe, big: !owedFirst || owed.isEmpty),
      if (!owedFirst && owed.isNotEmpty)
        line('$first owes you', owed, big: false),
    ];

    return AppCard(
      gradient: gradient,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < blocks.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.md),
                  blocks[i],
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              owedFirst ? Icons.south_west_rounded : Icons.north_east_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool dimmed;
  final bool loading;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.dimmed = false,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Pressable(
        onTap: loading ? null : onTap,
        child: AnimatedOpacity(
          duration: AppMotion.fast,
          opacity: dimmed ? 0.45 : 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.xs,
              horizontal: 2,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  alignment: Alignment.center,
                  child: AnimatedSwitcher(
                    duration: AppMotion.fast,
                    child: loading
                        ? SizedBox(
                            key: const ValueKey('l'),
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: color,
                            ),
                          )
                        : Icon(
                            icon,
                            key: const ValueKey('i'),
                            color: color,
                            size: 24,
                          ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
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

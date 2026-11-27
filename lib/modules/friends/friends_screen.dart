import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../app/routes/app_routes.dart';
import '../../controllers/balances.dart';
import '../../controllers/expense_controller.dart';
import '../../controllers/friend_controller.dart';
import '../../controllers/profile_controller.dart';
import '../../controllers/shell_controller.dart';
import '../../core/ui.dart';

/// Friends tab (lives inside the shell — no bottom bar here).
///
/// Only about friends: add people, answer requests, and see who you're
/// friends with in the app. Each row hints at the open balance (expenses and
/// groups combined, via [Balances.withPerson]); tap a friend for both sides.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  FriendController get _friends => FriendController.to;
  ExpenseController get _expenses => ExpenseController.to;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    _friends.refreshFriends();
    await _expenses.refreshData();
  }

  bool _matches(Map<String, dynamic> friend) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final name = (friend['name'] ?? '').toString().toLowerCase();
    final email = (friend['email'] ?? '').toString().toLowerCase();
    return name.contains(q) || email.contains(q);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          TabHeader(
            title: 'Friends',
            actions: [
              Obx(
                () => AppIconButton(
                  icon: Icons.mark_email_unread_outlined,
                  tooltip: 'Friend requests',
                  badgeCount: _friends.friendRequests.length,
                  onPressed: () => Get.toNamed(AppRoutes.friendRequests),
                ),
              ),
              AppIconButton(
                icon: Icons.person_add_alt_1_rounded,
                tooltip: 'Add friends',
                onPressed: () => Get.toNamed(AppRoutes.addFriends),
              ),
            ],
          ),
          Expanded(child: Obx(_buildBody)),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final friends = _friends.friends.toList();
    final loading = _friends.isLoading.value;
    final error = _friends.hasError.value;
    final requests = _friends.friendRequests.length;
    final preferred = ProfileController.to.currencyCode.value;
    // Read balances here, inside the Obx, so rows update when expenses or
    // groups change.
    final balances = {
      for (final f in friends)
        (f['uid'] ?? '').toString(): Balances.withPerson(
          (f['uid'] ?? '').toString(),
        ),
    };

    Widget child;
    if (loading && friends.isEmpty) {
      child = const _FriendsSkeleton(key: ValueKey('loading'));
    } else if (error && friends.isEmpty) {
      child = ErrorState(
        key: const ValueKey('error'),
        title: "Couldn't load your friends",
        onRetry: _refresh,
      );
    } else {
      child = _buildList(
        friends: friends,
        balances: balances,
        requests: requests,
        preferred: preferred,
      );
    }

    return AnimatedSwitcher(duration: AppMotion.normal, child: child);
  }

  Widget _buildList({
    required List<Map<String, dynamic>> friends,
    required Map<String, Map<String, double>> balances,
    required int requests,
    required String preferred,
  }) {
    final visible = friends.where(_matches).toList()
      ..sort(
        (a, b) => (a['name'] ?? '').toString().toLowerCase().compareTo(
          (b['name'] ?? '').toString().toLowerCase(),
        ),
      );
    final nobody = friends.isEmpty;
    final noResults = !nobody && visible.isEmpty;

    var index = 0;
    return RefreshIndicator(
      key: const ValueKey('list'),
      onRefresh: _refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.sm,
              AppSpacing.page,
              0,
            ),
            sliver: SliverList.list(
              children: [
                if (requests > 0) ...[
                  FadeSlideIn(
                    index: index++,
                    child: _RequestsBanner(count: requests),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                if (!nobody)
                  FadeSlideIn(
                    index: index++,
                    child: AppSearchField(
                      controller: _searchCtrl,
                      hint: 'Search friends',
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
              ],
            ),
          ),
          if (nobody)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.people_alt_rounded,
                title: 'No friends yet',
                message:
                    'Add friends to split bills, track who owes what and settle up in a tap.',
                actionLabel: 'Add friends',
                actionIcon: Icons.person_add_alt_1_rounded,
                onAction: () => Get.toNamed(AppRoutes.addFriends),
                orbitIcons: const [
                  Icons.receipt_long_rounded,
                  Icons.qr_code_2_rounded,
                  Icons.handshake_rounded,
                ],
              ),
            )
          else if (noResults)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.search_off_rounded,
                color: AppColors.secondary,
                illustrationSize: 140,
                title: 'No matches',
                message: 'No friend matches "${_query.trim()}".',
                actionLabel: 'Clear search',
                onAction: () {
                  _searchCtrl.clear();
                  setState(() => _query = '');
                },
              ),
            )
          else ...[
            SliverToBoxAdapter(
              child: SectionHeader(
                title: 'Your friends · ${visible.length}',
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page,
                  AppSpacing.xl,
                  AppSpacing.page,
                  AppSpacing.md,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
              sliver: SliverToBoxAdapter(
                // One ruled block, rows separated by hairlines.
                child: AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < visible.length; i++) ...[
                        if (i > 0) const Divider(height: 1, indent: 72),
                        FadeSlideIn(
                          key: ValueKey('friend-${visible[i]['uid']}'),
                          index: index + i,
                          child: _FriendRow(
                            friend: visible[i],
                            balance:
                                balances[(visible[i]['uid'] ?? '')
                                    .toString()] ??
                                const {},
                            preferred: preferred,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ],
      ),
    );
  }
}

class _RequestsBanner extends StatelessWidget {
  final int count;
  const _RequestsBanner({required this.count});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () => Get.toNamed(AppRoutes.friendRequests),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          IconBadge(
            icon: Icons.person_add_alt_1_rounded,
            color: AppColors.primary,
            size: 40,
            iconSize: 20,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count friend request${count == 1 ? '' : 's'} waiting',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Tap to review and accept',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: AppColors.primary),
        ],
      ),
    );
  }
}

class _FriendRow extends StatelessWidget {
  final Map<String, dynamic> friend;
  final Map<String, double> balance;
  final String preferred;

  const _FriendRow({
    required this.friend,
    required this.balance,
    required this.preferred,
  });

  @override
  Widget build(BuildContext context) {
    final uid = (friend['uid'] ?? '').toString();
    final name = (friend['name'] ?? '').toString().trim();
    final email = (friend['email'] ?? '').toString().trim();
    final avatar = (friend['avatarUrl'] ?? '').toString();
    final displayName = name.isEmpty || name == 'Unknown'
        ? 'SplitShare user'
        : name;

    return InkWell(
      onTap: () => AppNav.openFriend(
        uid,
        data: {'name': displayName, 'avatarUrl': avatar, 'email': email},
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            AppAvatar(name: displayName, imageUrl: avatar, radius: 23),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (email.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: BalanceLabel(
                byCurrency: balance,
                preferredCurrency: preferred,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FriendsSkeleton extends StatelessWidget {
  const _FriendsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.sm,
        AppSpacing.page,
        0,
      ),
      children: const [
        Skeleton(height: 48, radius: AppRadius.md),
        SizedBox(height: AppSpacing.xl),
        SkeletonList(count: 5, padding: EdgeInsets.zero, shrinkWrap: true),
      ],
    );
  }
}

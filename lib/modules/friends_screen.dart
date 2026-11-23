import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../app/routes/app_routes.dart';
import '../controllers/expense_controller.dart';
import '../controllers/friend_controller.dart';
import '../controllers/profile_controller.dart';
import '../controllers/shell_controller.dart';
import '../core/ui.dart';

enum _FriendFilter { all, owesYou, youOwe, settled }

extension on _FriendFilter {
  String get label => switch (this) {
    _FriendFilter.all => 'All',
    _FriendFilter.owesYou => 'Owes you',
    _FriendFilter.youOwe => 'You owe',
    _FriendFilter.settled => 'Settled',
  };
}

/// Friends tab (lives inside the shell — no bottom bar here).
///
/// Balances are computed live from open expenses via [ExpenseController]
/// (never from fields stored on the friend document).
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  _FriendFilter _filter = _FriendFilter.all;

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

  /// Overall direction of a per-currency balance map (same rule as
  /// [BalanceLabel]: preferred currency first, else the first non-zero).
  static BalanceDirection _direction(Map<String, double> m, String preferred) {
    final nonZero = m.entries.where((e) => e.value.abs() >= 0.005).toList();
    if (nonZero.isEmpty) return BalanceDirection.settled;
    final primary = m[preferred] ?? nonZero.first.value;
    return BalanceDirectionX.fromNet(primary);
  }

  bool _matches(Map<String, dynamic> person, String preferred) {
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      final name = (person['name'] ?? '').toString().toLowerCase();
      final email = (person['email'] ?? '').toString().toLowerCase();
      if (!name.contains(q) && !email.contains(q)) return false;
    }
    if (_filter == _FriendFilter.all) return true;
    final uid = (person['uid'] ?? '').toString();
    final dir = _direction(_expenses.balanceWith(uid), preferred);
    return switch (_filter) {
      _FriendFilter.owesYou => dir == BalanceDirection.owedToYou,
      _FriendFilter.youOwe => dir == BalanceDirection.youOwe,
      _FriendFilter.settled => dir == BalanceDirection.settled,
      _FriendFilter.all => true,
    };
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
    // Touch the reactive balance maps so this Obx rebuilds when they change.
    final settle = Map<String, Map<String, dynamic>>.from(
      _expenses.settleUpData,
    );
    _expenses.balances.length;

    final friendUids = friends.map((f) => (f['uid'] ?? '').toString()).toSet();
    final me = _expenses.currentUid;
    final others =
        settle.values.where((p) {
          final uid = (p['uid'] ?? '').toString();
          return uid.isNotEmpty && uid != me && !friendUids.contains(uid);
        }).toList()..sort(
          (a, b) => (a['name'] ?? '').toString().toLowerCase().compareTo(
            (b['name'] ?? '').toString().toLowerCase(),
          ),
        );

    Widget child;
    if (loading && friends.isEmpty) {
      child = const _FriendsSkeleton(key: ValueKey('loading'));
    } else if (error && friends.isEmpty) {
      child = ErrorState(
        key: const ValueKey('error'),
        title: 'Couldn\'t load your friends',
        onRetry: _refresh,
      );
    } else {
      child = _buildList(
        friends: friends,
        others: others,
        requests: requests,
        preferred: preferred,
      );
    }

    return AnimatedSwitcher(duration: AppMotion.normal, child: child);
  }

  Widget _buildList({
    required List<Map<String, dynamic>> friends,
    required List<Map<String, dynamic>> others,
    required int requests,
    required String preferred,
  }) {
    final visibleFriends = friends
        .where((f) => _matches(f, preferred))
        .toList();
    final visibleOthers = others.where((o) => _matches(o, preferred)).toList();
    final nobody = friends.isEmpty && others.isEmpty;
    final noResults =
        !nobody && visibleFriends.isEmpty && visibleOthers.isEmpty;

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
                FadeSlideIn(
                  index: index++,
                  child: _SummaryCard(preferred: preferred),
                ),
                if (!nobody) ...[
                  const SizedBox(height: AppSpacing.lg),
                  FadeSlideIn(
                    index: index++,
                    child: AppSearchField(
                      controller: _searchCtrl,
                      hint: 'Search friends',
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  FadeSlideIn(
                    index: index++,
                    child: _FilterChips(
                      selected: _filter,
                      onSelected: (f) => setState(() => _filter = f),
                    ),
                  ),
                ],
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
                message: _query.trim().isNotEmpty
                    ? 'Nobody matches "${_query.trim()}"${_filter == _FriendFilter.all ? '' : ' in ${_filter.label}'}.'
                    : 'No one in ${_filter.label} right now.',
                actionLabel: 'Clear filters',
                onAction: () {
                  _searchCtrl.clear();
                  setState(() {
                    _query = '';
                    _filter = _FriendFilter.all;
                  });
                },
              ),
            )
          else ...[
            if (visibleFriends.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: SectionHeader(
                  title: 'Your friends · ${visibleFriends.length}',
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.page,
                    AppSpacing.xl,
                    AppSpacing.page,
                    AppSpacing.md,
                  ),
                ),
              ),
              _personList(visibleFriends, preferred, index, isFriend: true),
            ],
            if (visibleOthers.isNotEmpty) ...[
              const SliverToBoxAdapter(
                child: SectionHeader(
                  title: 'Others you share expenses with',
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.page,
                    AppSpacing.xl,
                    AppSpacing.page,
                    AppSpacing.md,
                  ),
                ),
              ),
              _personList(
                visibleOthers,
                preferred,
                index + visibleFriends.length,
                isFriend: false,
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ],
      ),
    );
  }

  Widget _personList(
    List<Map<String, dynamic>> people,
    String preferred,
    int startIndex, {
    required bool isFriend,
  }) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
      sliver: SliverList.separated(
        itemCount: people.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (_, i) {
          final p = people[i];
          final uid = (p['uid'] ?? '').toString();
          return FadeSlideIn(
            key: ValueKey('person-$uid'),
            index: startIndex + i,
            child: _PersonRow(
              person: p,
              isFriend: isFriend,
              balance: _expenses.balanceWith(uid),
              preferred: preferred,
            ),
          );
        },
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
      color: AppColors.primaryLight,
      shadow: false,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          const IconBadge(
            icon: Icons.person_add_alt_1_rounded,
            color: AppColors.primary,
            filled: true,
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
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Tap to review and accept',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.primary),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String preferred;
  const _SummaryCard({required this.preferred});

  @override
  Widget build(BuildContext context) {
    final ctrl = ExpenseController.to;
    return Obx(() {
      final owed = Map<String, double>.from(ctrl.owedToMeByCurrency);
      final owe = Map<String, double>.from(ctrl.iOweByCurrency);
      final allClear =
          owed.values.every((v) => v.abs() < 0.005) &&
          owe.values.every((v) => v.abs() < 0.005);
      return AppCard(
        gradient: AppColors.heroGradient,
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  allClear
                      ? Icons.verified_rounded
                      : Icons.account_balance_wallet_rounded,
                  color: Colors.white.withValues(alpha: 0.85),
                  size: 18,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    allClear ? 'You\'re all settled up' : 'Your balances',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _SummaryCell(
                      label: 'You are owed',
                      icon: Icons.south_west_rounded,
                      value: Fmt.multi(owed, preferred: preferred),
                    ),
                  ),
                  Container(
                    width: 1,
                    margin: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                  Expanded(
                    child: _SummaryCell(
                      label: 'You owe',
                      icon: Icons.north_east_rounded,
                      value: Fmt.multi(owe, preferred: preferred),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _SummaryCell extends StatelessWidget {
  final String label;
  final IconData icon;
  final String value;
  const _SummaryCell({
    required this.label,
    required this.icon,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
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
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }
}

class _FilterChips extends StatelessWidget {
  final _FriendFilter selected;
  final ValueChanged<_FriendFilter> onSelected;
  const _FilterChips({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _FriendFilter.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (_, i) {
          final f = _FriendFilter.values[i];
          final active = f == selected;
          return Pressable(
            onTap: () => onSelected(f),
            child: AnimatedContainer(
              duration: AppMotion.fast,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(
                  color: active ? AppColors.primary : AppColors.border,
                ),
              ),
              child: Text(
                f.label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  final Map<String, dynamic> person;
  final bool isFriend;
  final Map<String, double> balance;
  final String preferred;

  const _PersonRow({
    required this.person,
    required this.isFriend,
    required this.balance,
    required this.preferred,
  });

  @override
  Widget build(BuildContext context) {
    final uid = (person['uid'] ?? '').toString();
    final name = (person['name'] ?? '').toString().trim();
    final email = (person['email'] ?? '').toString().trim();
    final avatar = (person['avatarUrl'] ?? '').toString();
    final displayName = name.isEmpty || name == 'Unknown'
        ? 'SplitShare user'
        : name;
    final subtitle = email.isNotEmpty
        ? email
        : (isFriend ? '' : 'Not in your friends');

    return AppCard(
      onTap: () => AppNav.openFriend(
        uid,
        data: {'name': displayName, 'avatarUrl': avatar, 'email': email},
      ),
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
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
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
        Skeleton(height: 132, radius: AppRadius.lg),
        SizedBox(height: AppSpacing.lg),
        Skeleton(height: 48, radius: AppRadius.md),
        SizedBox(height: AppSpacing.xl),
        SkeletonList(count: 5, padding: EdgeInsets.zero, shrinkWrap: true),
      ],
    );
  }
}

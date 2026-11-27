import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../app/routes/app_routes.dart';
import '../controllers/friend_controller.dart';
import '../controllers/shell_controller.dart';
import '../core/ui.dart';

/// Incoming friend requests with accept / decline and animated removal.
class FriendRequestsScreen extends StatefulWidget {
  const FriendRequestsScreen({super.key});

  @override
  State<FriendRequestsScreen> createState() => _FriendRequestsScreenState();
}

class _FriendRequestsScreenState extends State<FriendRequestsScreen> {
  final _listKey = GlobalKey<AnimatedListState>();
  late List<Map<String, dynamic>> _items;
  Worker? _worker;

  /// requestId -> 'accept' | 'decline' (which button shows the spinner).
  final _action = <String, String>{};

  FriendController get _ctrl => FriendController.to;

  static const _animDuration = Duration(milliseconds: 320);

  @override
  void initState() {
    super.initState();
    _items = List<Map<String, dynamic>>.from(_ctrl.friendRequests);
    _worker = ever<List<Map<String, dynamic>>>(_ctrl.friendRequests, _sync);
  }

  @override
  void dispose() {
    _worker?.dispose();
    super.dispose();
  }

  String _idOf(Map<String, dynamic> r) => (r['id'] ?? '').toString();

  /// Diffs the live list against what is on screen and animates changes.
  void _sync(List<Map<String, dynamic>> next) {
    if (!mounted) return;
    final list = _listKey.currentState;
    final wasEmpty = _items.isEmpty;
    final nextIds = next.map(_idOf).toSet();

    // Removals (iterate backwards so indices stay valid).
    for (var i = _items.length - 1; i >= 0; i--) {
      final item = _items[i];
      if (!nextIds.contains(_idOf(item))) {
        _items.removeAt(i);
        _action.remove(_idOf(item));
        list?.removeItem(
          i,
          (context, animation) => _animated(item, animation, removing: true),
          duration: _animDuration,
        );
      }
    }

    // Insertions / updates, in the order of the live list.
    for (var i = 0; i < next.length; i++) {
      final id = _idOf(next[i]);
      final existing = _items.indexWhere((r) => _idOf(r) == id);
      if (existing == -1) {
        final at = i.clamp(0, _items.length);
        _items.insert(at, next[i]);
        list?.insertItem(at, duration: _animDuration);
      } else {
        _items[existing] = next[i];
      }
    }

    // Rebuild for empty <-> list switches and updated fields (e.g. sentAt).
    if (wasEmpty != _items.isEmpty || list == null || next.isNotEmpty) {
      setState(() {});
    }
  }

  Future<void> _accept(Map<String, dynamic> r) async {
    final id = _idOf(r);
    if (_ctrl.busyRequests.contains(id)) return;
    setState(() => _action[id] = 'accept');
    await _ctrl.acceptFriendRequest(r);
    if (mounted) setState(() => _action.remove(id));
  }

  Future<void> _decline(Map<String, dynamic> r) async {
    final id = _idOf(r);
    if (_ctrl.busyRequests.contains(id)) return;
    setState(() => _action[id] = 'decline');
    await _ctrl.ignoreFriendRequest(id);
    if (mounted) setState(() => _action.remove(id));
  }

  Future<void> _refresh() async {
    _ctrl.refreshFriends();
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppTopBar(title: 'Friend requests'),
      body: Obx(() {
        // Subscribe to the reactive lists used below.
        _ctrl.friendRequests.length;
        _ctrl.busyRequests.length;
        final loading = _ctrl.isLoading.value;

        Widget child;
        if (loading && _items.isEmpty) {
          child = const SkeletonList(
            key: ValueKey('loading'),
            count: 3,
            padding: EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.sm,
              AppSpacing.page,
              AppSpacing.page,
            ),
          );
        } else if (_items.isEmpty) {
          child = RefreshIndicator(
            key: const ValueKey('empty'),
            onRefresh: _refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.mark_email_read_rounded,
                    title: 'No pending requests',
                    message:
                        'When someone wants to add you, their request will appear here.',
                    actionLabel: 'Add friends',
                    actionIcon: Icons.person_add_alt_1_rounded,
                    onAction: () => Get.offNamed(AppRoutes.addFriends),
                    orbitIcons: const [
                      Icons.qr_code_2_rounded,
                      Icons.alternate_email_rounded,
                    ],
                  ),
                ),
              ],
            ),
          );
        } else {
          child = RefreshIndicator(
            key: const ValueKey('list'),
            onRefresh: _refresh,
            child: AnimatedList(
              key: _listKey,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                AppSpacing.sm,
                AppSpacing.page,
                AppSpacing.xxxl,
              ),
              initialItemCount: _items.length,
              itemBuilder: (context, i, animation) =>
                  _animated(_items[i], animation, index: i),
            ),
          );
        }
        return AnimatedSwitcher(duration: AppMotion.normal, child: child);
      }),
    );
  }

  Widget _animated(
    Map<String, dynamic> r,
    Animation<double> animation, {
    bool removing = false,
    int index = 0,
  }) {
    final curved = CurvedAnimation(parent: animation, curve: AppMotion.curve);
    final card = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RequestCard(
          request: r,
          acceptLoading: !removing && _action[_idOf(r)] == 'accept',
          declineLoading: !removing && _action[_idOf(r)] == 'decline',
          busy: removing || _ctrl.busyRequests.contains(_idOf(r)),
          onAccept: () => _accept(r),
          onDecline: () => _decline(r),
        ),
        const Divider(height: 1),
      ],
    );
    return SizeTransition(
      sizeFactor: curved,
      child: FadeTransition(
        opacity: curved,
        child: removing ? card : FadeSlideIn(index: index, child: card),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final bool acceptLoading;
  final bool declineLoading;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _RequestCard({
    required this.request,
    required this.acceptLoading,
    required this.declineLoading,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
  });

  static String _sentLabel(dynamic sentAt) {
    final rel = Fmt.relative(sentAt);
    if (rel == 'Just now' || rel == 'Yesterday') {
      return 'Sent ${rel.toLowerCase()}';
    }
    if (rel.endsWith('ago')) return 'Sent $rel';
    return 'Sent on $rel';
  }

  @override
  Widget build(BuildContext context) {
    final rawName = (request['fromName'] ?? '').toString().trim();
    final name = rawName.isEmpty ? 'SplitShare user' : rawName;
    final email = (request['fromEmail'] ?? '').toString();
    final avatar = (request['fromAvatarUrl'] ?? '').toString();
    final fromUid = (request['fromUid'] ?? '').toString();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Pressable(
            onTap: fromUid.isEmpty
                ? null
                : () => AppNav.openFriend(
                    fromUid,
                    data: {'name': name, 'email': email, 'avatarUrl': avatar},
                  ),
            child: Row(
              children: [
                AppAvatar(name: name, imageUrl: avatar, radius: 26),
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
                          fontSize: 16,
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
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 13,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              _sentLabel(request['sentAt']),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: AppButton.outline(
                  label: 'Decline',
                  height: 44,
                  loading: declineLoading,
                  onPressed: busy && !declineLoading ? null : onDecline,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppButton(
                  label: 'Accept',
                  icon: Icons.check_rounded,
                  height: 44,
                  loading: acceptLoading,
                  onPressed: busy && !acceptLoading ? null : onAccept,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

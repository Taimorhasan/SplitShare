import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart'
    show ContactProperty, FlutterContacts, PermissionStatus, PermissionType;
import 'package:get/get.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../../app/routes/app_routes.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/expense_controller.dart';
import '../../controllers/friend_controller.dart';
import '../../controllers/group_controller.dart';
import '../../controllers/profile_controller.dart';
import '../../controllers/shell_controller.dart';
import '../../core/ui.dart';

/// Find people on SplitShare: search, QR codes, friend codes, contacts,
/// invites and suggestions from shared groups / expenses.
class AddFriendsScreen extends StatefulWidget {
  const AddFriendsScreen({super.key});

  @override
  State<AddFriendsScreen> createState() => _AddFriendsScreenState();
}

class _AddFriendsScreenState extends State<AddFriendsScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  String _query = '';

  /// uids with a friend request in flight (per-row spinners).
  final _adding = <String>{}.obs;

  bool _contactsLoading = false;
  bool _resolving = false;

  FriendController get _friends => FriendController.to;

  String? get _myUid => AuthController.instance.user?.uid;

  @override
  void initState() {
    super.initState();
    // Don't show stale results from an earlier visit.
    _friends.searchResults.clear();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ---------- Search ----------

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    _debounce?.cancel();
    if (value.trim().length < 2) {
      _friends.searchResults.clear();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _friends.searchUsers(value);
    });
  }

  // ---------- Friend actions ----------

  Future<void> _add(String uid) async {
    if (_adding.contains(uid)) return;
    _adding.add(uid);
    try {
      await _friends.sendFriendRequest(uid);
    } finally {
      _adding.remove(uid);
    }
  }

  Future<void> _accept(Map<String, dynamic> request) =>
      _friends.acceptFriendRequest(request);

  void _openProfile(Map<String, dynamic> user) {
    final uid = (user['uid'] ?? '').toString();
    if (uid.isEmpty) return;
    AppNav.openFriend(
      uid,
      data: {
        'name': user['name'],
        'email': user['email'],
        'avatarUrl': user['avatarUrl'],
      },
    );
  }

  // ---------- Sharing ----------

  Future<void> _share(String text, {String? subject}) async {
    try {
      await SharePlus.instance.share(ShareParams(text: text, subject: subject));
    } catch (e) {
      AppToast.error(AppToast.friendly(e), title: 'Couldn\'t open share sheet');
    }
  }

  String get _codeLine {
    final uid = _myUid;
    return uid == null ? '' : ' Add me with my friend code: $uid';
  }

  void _inviteFriends() => _share(
    'I\'m using SplitShare to split bills and keep track of who owes what. '
    'Download it and let\'s split expenses together!$_codeLine',
    subject: 'Join me on SplitShare',
  );

  void _inviteQuery(String query) => _share(
    'Hi $query! I\'m using SplitShare to split bills with friends. '
    'Install it so we can split expenses together.$_codeLine',
    subject: 'Join me on SplitShare',
  );

  // ---------- My QR code ----------

  void _showMyQr() {
    final uid = _myUid;
    if (uid == null) {
      AppToast.error('Please sign in again to see your code.');
      return;
    }
    AppDialogs.sheet<void>(
      title: 'My QR code',
      child: _MyQrSheet(
        uid: uid,
        onShare: () => _share(
          'Add me on SplitShare! Open the app → Friends → Add friends → Enter code: $uid',
          subject: 'Add me on SplitShare',
        ),
      ),
    );
  }

  // ---------- Codes (scan / enter) ----------

  Future<void> _scan() async {
    final result = await Get.toNamed(AppRoutes.scanQr);
    if (!mounted) return;
    if (result is String && result.trim().isNotEmpty) {
      await _resolve(result);
    }
  }

  Future<void> _enterCode() async {
    final code = await AppDialogs.sheet<String>(
      title: 'Enter friend code',
      child: const _EnterCodeSheet(),
    );
    if (!mounted || code == null || code.trim().isEmpty) return;
    await _resolve(code);
  }

  static String _normalizeCode(String raw) {
    var code = raw.trim();
    final m = RegExp(
      r'splitshare://user/([^/\s]+)',
      caseSensitive: false,
    ).firstMatch(code);
    if (m != null) code = m.group(1)!;
    return code;
  }

  Future<void> _resolve(String raw) async {
    if (_resolving) return;
    final uid = _normalizeCode(raw);
    if (uid.isEmpty || uid.contains('/') || uid.length > 128) {
      AppToast.warning(
        'That code doesn\'t look right. Check it and try again.',
        title: 'Invalid code',
      );
      return;
    }
    if (uid == _myUid) {
      AppToast.info(
        'That\'s your own friend code — share it with friends instead.',
        title: 'That\'s you!',
      );
      return;
    }

    setState(() => _resolving = true);
    final user = await _friends.getUser(uid);
    if (!mounted) return;
    setState(() => _resolving = false);

    if (user == null) {
      AppToast.warning(
        'Double-check the code and try again.',
        title: 'No SplitShare user found',
      );
      return;
    }

    final name = (user['name'] ?? 'this person').toString();
    if (_friends.isAlreadyFriend(uid)) {
      final open = await AppDialogs.confirm(
        title: 'Already friends',
        message: 'You and $name are already friends. Open their profile?',
        confirmLabel: 'View profile',
        icon: Icons.people_alt_rounded,
      );
      if (open && mounted) _openProfile(user);
      return;
    }

    await AppDialogs.sheet<void>(
      child: _ConfirmUserSheet(user: user, adding: _adding, onAdd: _add),
    );
  }

  // ---------- Contacts ----------

  Future<void> _findFromContacts() async {
    if (_contactsLoading) return;
    final proceed = await AppDialogs.confirm(
      title: 'Find friends from contacts',
      message:
          'SplitShare checks your contacts\' email addresses to find people already on the app. Your contacts are not stored or shared.',
      confirmLabel: 'Continue',
      icon: Icons.contacts_rounded,
    );
    if (!proceed || !mounted) return;

    setState(() => _contactsLoading = true);
    try {
      final status = await FlutterContacts.permissions.request(
        PermissionType.read,
      );
      if (status != PermissionStatus.granted &&
          status != PermissionStatus.limited) {
        final blocked =
            status == PermissionStatus.permanentlyDenied ||
            status == PermissionStatus.restricted;
        AppToast.warning(
          blocked
              ? 'Contacts access is turned off. Enable it for SplitShare in your device settings.'
              : 'We need access to your contacts to find friends. You can still search by name or email.',
          title: 'Contacts access needed',
        );
        return;
      }

      final contacts = await FlutterContacts.getAll(
        properties: {ContactProperty.name, ContactProperty.email},
      );
      final emails = <String>{
        for (final c in contacts)
          for (final e in c.emails)
            if (e.address.trim().isNotEmpty) e.address.trim(),
      }.toList();

      final matches = emails.isEmpty
          ? <Map<String, dynamic>>[]
          : await _friends.findUsersByEmails(emails);
      if (!mounted) return;
      setState(() => _contactsLoading = false);

      await AppDialogs.sheet<void>(
        title: matches.isEmpty
            ? 'From your contacts'
            : '${matches.length} contact${matches.length == 1 ? '' : 's'} on SplitShare',
        child: _ContactMatchesSheet(
          matches: matches,
          adding: _adding,
          onAdd: _add,
          onAccept: _accept,
          onInvite: _inviteFriends,
        ),
      );
    } catch (e) {
      AppToast.error(AppToast.friendly(e), title: 'Couldn\'t read contacts');
    } finally {
      if (mounted && _contactsLoading) setState(() => _contactsLoading = false);
    }
  }

  // ---------- Suggestions ----------

  List<Map<String, dynamic>> _suggestions() {
    final me = _myUid;
    final friendUids = _friends.friends
        .map((f) => f['uid']?.toString())
        .toSet();
    final byUid = <String, Map<String, dynamic>>{};

    void consider(Map<String, dynamic> p) {
      final uid = (p['uid'] ?? '').toString();
      if (uid.isEmpty || uid == me || friendUids.contains(uid)) return;
      final name = (p['name'] ?? '').toString();
      final existing = byUid[uid];
      final usable = name.isNotEmpty && name != 'Unknown' && name != 'Member';
      if (existing == null) {
        byUid[uid] = {
          'uid': uid,
          'name': usable ? name : 'SplitShare user',
          'email': (p['email'] ?? '').toString(),
          'avatarUrl': (p['avatarUrl'] ?? '').toString(),
        };
      } else {
        if (usable && existing['name'] == 'SplitShare user') {
          existing['name'] = name;
        }
        if ((existing['email'] as String).isEmpty) {
          existing['email'] = (p['email'] ?? '').toString();
        }
        if ((existing['avatarUrl'] as String).isEmpty) {
          existing['avatarUrl'] = (p['avatarUrl'] ?? '').toString();
        }
      }
    }

    for (final p in ExpenseController.to.settleUpData.values) {
      consider(p);
    }
    for (final g in GroupController.to.groups) {
      for (final m in GroupController.membersOf(g)) {
        consider(m);
      }
    }
    return byUid.values.take(12).toList();
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final searching = _query.trim().isNotEmpty;
    return Scaffold(
      appBar: AppTopBar(
        title: 'Add friends',
        actions: [
          Obx(
            () => AppIconButton(
              icon: Icons.mark_email_unread_outlined,
              tooltip: 'Friend requests',
              size: 42,
              badgeCount: _friends.friendRequests.length,
              onPressed: () => Get.toNamed(AppRoutes.friendRequests),
            ),
          ),
        ],
      ),
      body: LoadingOverlay(
        visible: _resolving || _contactsLoading,
        message: _contactsLoading
            ? 'Checking your contacts…'
            : 'Looking up code…',
        child: GestureDetector(
          onTap: AppNav.unfocus,
          behavior: HitTestBehavior.translucent,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.sm,
              AppSpacing.page,
              AppSpacing.xxxl,
            ),
            children: [
              AppSearchField(
                controller: _searchCtrl,
                hint: 'Search by name or email',
                onChanged: _onQueryChanged,
              ),
              AnimatedSwitcher(
                duration: AppMotion.normal,
                child: searching
                    ? KeyedSubtree(
                        key: const ValueKey('results'),
                        child: _results(),
                      )
                    : KeyedSubtree(key: const ValueKey('home'), child: _home()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _results() {
    final q = _query.trim();
    if (q.length < 2) {
      return const Padding(
        padding: EdgeInsets.only(top: AppSpacing.xl),
        child: _Hint(
          icon: Icons.keyboard_rounded,
          text: 'Keep typing — enter at least 2 characters.',
        ),
      );
    }
    return Obx(() {
      final busy = _friends.isSearching.value || (_debounce?.isActive ?? false);
      final results = _friends.searchResults.toList();
      if (busy && results.isEmpty) {
        return const Padding(
          padding: EdgeInsets.only(top: AppSpacing.lg),
          child: SkeletonList(
            count: 3,
            padding: EdgeInsets.zero,
            shrinkWrap: true,
          ),
        );
      }
      if (results.isEmpty) {
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.lg),
          child: AppCard(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              children: [
                IconBadge(
                  icon: Icons.person_search_rounded,
                  color: AppColors.secondary,
                  size: 56,
                  iconSize: 28,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'No one found for "$q"',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Try their full email address, or the start of their name. Not on SplitShare yet? Invite them!',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.lg),
                AppButton(
                  label: 'Invite $q',
                  icon: Icons.ios_share_rounded,
                  height: 46,
                  onPressed: () => _inviteQuery(q),
                ),
              ],
            ),
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: '${results.length} result${results.length == 1 ? '' : 's'}',
            padding: const EdgeInsets.only(
              top: AppSpacing.xl,
              bottom: AppSpacing.md,
            ),
          ),
          _RuledList(
            children: [
              for (var i = 0; i < results.length; i++)
                FadeSlideIn(
                  key: ValueKey('r-${results[i]['uid']}'),
                  index: i,
                  child: _UserRow(
                    user: results[i],
                    adding: _adding,
                    onAdd: _add,
                    onAccept: _accept,
                    card: false,
                    onTap: () => _openProfile(results[i]),
                  ),
                ),
            ],
          ),
        ],
      );
    });
  }

  Widget _home() {
    final actions = <_ActionData>[
      _ActionData(
        icon: Icons.qr_code_2_rounded,
        color: AppColors.primary,
        title: 'My QR code',
        subtitle: 'Let friends scan you',
        onTap: _showMyQr,
      ),
      _ActionData(
        icon: Icons.qr_code_scanner_rounded,
        color: AppColors.secondary,
        title: 'Scan QR code',
        subtitle: 'Add someone instantly',
        onTap: _scan,
      ),
      _ActionData(
        icon: Icons.pin_rounded,
        color: AppColors.accent,
        title: 'Enter friend code',
        subtitle: 'Paste a shared code',
        onTap: _enterCode,
      ),
      if (!kIsWeb)
        _ActionData(
          icon: Icons.contacts_rounded,
          color: AppColors.positive,
          title: 'Find from contacts',
          subtitle: 'See who\'s on SplitShare',
          onTap: _findFromContacts,
        ),
      _ActionData(
        icon: Icons.ios_share_rounded,
        color: AppColors.warning,
        title: 'Invite friends',
        subtitle: 'Share a link to the app',
        onTap: _inviteFriends,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, AppSpacing.md, 4, 0),
          child: _Hint(
            icon: Icons.info_outline_rounded,
            text: 'Search by the start of a name, or an exact email address.',
            compact: true,
          ),
        ),
        const SectionHeader(
          title: 'More ways to connect',
          padding: EdgeInsets.only(top: AppSpacing.xl, bottom: AppSpacing.md),
        ),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 68),
                FadeSlideIn(
                  index: i,
                  child: AppListTile(
                    icon: actions[i].icon,
                    iconColor: actions[i].color,
                    title: actions[i].title,
                    subtitle: actions[i].subtitle,
                    onTap: actions[i].onTap,
                  ),
                ),
              ],
            ],
          ),
        ),
        Obx(() {
          // Reactive sources for suggestions.
          _friends.friends.length;
          ExpenseController.to.settleUpData.length;
          GroupController.to.groups.length;
          final people = _suggestions();
          if (people.isEmpty) return const SizedBox.shrink();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeader(
                title: 'People you may know',
                padding: EdgeInsets.only(
                  top: AppSpacing.xxl,
                  bottom: AppSpacing.md,
                ),
              ),
              _RuledList(
                children: [
                  for (var i = 0; i < people.length; i++)
                    FadeSlideIn(
                      key: ValueKey('s-${people[i]['uid']}'),
                      index: i + actions.length,
                      child: _UserRow(
                        user: people[i],
                        adding: _adding,
                        onAdd: _add,
                        onAccept: _accept,
                        card: false,
                        caption: 'In your groups or expenses',
                        onTap: () => _openProfile(people[i]),
                      ),
                    ),
                ],
              ),
            ],
          );
        }),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Pieces
// ---------------------------------------------------------------------------

class _Hint extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool compact;
  const _Hint({required this.icon, required this.text, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: compact
          ? MainAxisAlignment.start
          : MainAxisAlignment.center,
      children: [
        Icon(icon, size: 16, color: AppColors.textMuted),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _ActionData {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionData({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
}

/// Rows in one hairline-ruled block.
class _RuledList extends StatelessWidget {
  final List<Widget> children;
  const _RuledList({required this.children});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// One user with a state-aware trailing button
/// (Add / Requested / Friends / Accept).
class _UserRow extends StatelessWidget {
  final Map<String, dynamic> user;
  final RxSet<String> adding;
  final Future<void> Function(String uid) onAdd;
  final Future<void> Function(Map<String, dynamic> request) onAccept;
  final VoidCallback? onTap;
  final String? caption;
  final bool card;

  const _UserRow({
    required this.user,
    required this.adding,
    required this.onAdd,
    required this.onAccept,
    this.onTap,
    this.caption,
    this.card = true,
  });

  @override
  Widget build(BuildContext context) {
    final uid = (user['uid'] ?? '').toString();
    final rawName = (user['name'] ?? '').toString().trim();
    final name = rawName.isEmpty ? 'SplitShare user' : rawName;
    final email = (user['email'] ?? '').toString();
    final subtitle = email.isNotEmpty ? email : (caption ?? '');
    final ctrl = FriendController.to;

    final row = Row(
      children: [
        AppAvatar(
          name: name,
          imageUrl: (user['avatarUrl'] ?? '').toString(),
          radius: 22,
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
                  fontSize: 15,
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
        Obx(() {
          if (ctrl.isAlreadyFriend(uid)) {
            return StatusPill(
              label: 'Friends',
              color: AppColors.positive,
              icon: Icons.check_rounded,
            );
          }
          final incoming = ctrl.friendRequests.firstWhereOrNull(
            (r) => r['fromUid'] == uid,
          );
          if (incoming != null) {
            return AppButton(
              label: 'Accept',
              variant: AppButtonVariant.success,
              expand: false,
              height: 38,
              loading: ctrl.busyRequests.contains(incoming['id']),
              onPressed: () => onAccept(incoming),
            );
          }
          if (ctrl.sentRequests.contains(uid)) {
            return StatusPill(
              label: 'Requested',
              color: AppColors.textSecondary,
              icon: Icons.schedule_rounded,
            );
          }
          return AppButton.secondary(
            label: 'Add',
            icon: Icons.person_add_alt_1_rounded,
            expand: false,
            height: 38,
            loading: adding.contains(uid),
            onPressed: () => onAdd(uid),
          );
        }),
      ],
    );

    if (!card) {
      return Pressable(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: row,
        ),
      );
    }
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: row,
    );
  }
}

class _MyQrSheet extends StatelessWidget {
  final String uid;
  final VoidCallback onShare;
  const _MyQrSheet({required this.uid, required this.onShare});

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: uid));
    AppToast.success(
      'Send it to a friend so they can add you.',
      title: 'Code copied',
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ProfileController.to;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xxl,
        AppSpacing.sm,
        AppSpacing.xxl,
        AppSpacing.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Obx(() {
                  final name = profile.name.value.trim().isEmpty
                      ? 'You'
                      : profile.name.value.trim();
                  return Row(
                    children: [
                      AppAvatar(
                        name: name,
                        imageUrl: profile.avatarUrl.value,
                        radius: 22,
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
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              'Scan to add me on SplitShare',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }),
                const SizedBox(height: AppSpacing.lg),
                // Fixed dark-on-white in both themes so any camera can read it.
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: QrImageView(
                    data: 'splitshare://user/$uid',
                    size: 200,
                    padding: EdgeInsets.zero,
                    backgroundColor: Colors.white,
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                    semanticsLabel: 'Your SplitShare QR code',
                    eyeStyle: QrEyeStyle(
                      eyeShape: QrEyeShape.circle,
                      color: AppLogo.ink,
                    ),
                    dataModuleStyle: QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.circle,
                      color: AppLogo.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Your friend code',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    uid,
                    maxLines: 1,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                AppIconButton(
                  icon: Icons.copy_rounded,
                  tooltip: 'Copy code',
                  size: 40,
                  color: AppColors.primary,
                  background: AppColors.primaryLight,
                  onPressed: _copy,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton(
            label: 'Share my code',
            icon: Icons.ios_share_rounded,
            onPressed: onShare,
          ),
        ],
      ),
    );
  }
}

class _EnterCodeSheet extends StatefulWidget {
  const _EnterCodeSheet();

  @override
  State<_EnterCodeSheet> createState() => _EnterCodeSheetState();
}

class _EnterCodeSheetState extends State<_EnterCodeSheet> {
  final _formKey = GlobalKey<FormState>();
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      AppToast.info('Your clipboard is empty.');
      return;
    }
    _ctrl.text = text;
    _formKey.currentState?.validate();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(_ctrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xxl,
        AppSpacing.sm,
        AppSpacing.xxl,
        AppSpacing.xxl,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Ask your friend to open Add friends → My QR code and share their code with you.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              controller: _ctrl,
              hint: 'Paste or type a friend code',
              prefixIcon: Icons.pin_rounded,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              suffix: IconButton(
                tooltip: 'Paste',
                icon: const Icon(Icons.content_paste_rounded, size: 20),
                onPressed: _paste,
              ),
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return 'Enter a friend code';
                if (t.length < 6) return 'That code looks too short';
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: 'Find friend',
              icon: Icons.search_rounded,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmUserSheet extends StatelessWidget {
  final Map<String, dynamic> user;
  final RxSet<String> adding;
  final Future<void> Function(String uid) onAdd;

  const _ConfirmUserSheet({
    required this.user,
    required this.adding,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final uid = (user['uid'] ?? '').toString();
    final rawName = (user['name'] ?? '').toString().trim();
    final name = rawName.isEmpty ? 'SplitShare user' : rawName;
    final email = (user['email'] ?? '').toString();
    final ctrl = FriendController.to;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xxl,
        AppSpacing.md,
        AppSpacing.xxl,
        AppSpacing.xxl,
      ),
      child: Column(
        children: [
          AppAvatar(
            name: name,
            imageUrl: (user['avatarUrl'] ?? '').toString(),
            radius: 40,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge,
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
          const SizedBox(height: AppSpacing.xl),
          Obx(() {
            final incoming = ctrl.friendRequests.firstWhereOrNull(
              (r) => r['fromUid'] == uid,
            );
            final sent = ctrl.sentRequests.contains(uid);
            if (ctrl.isAlreadyFriend(uid)) {
              return AppButton(
                label: 'You\'re friends — view profile',
                icon: Icons.person_rounded,
                onPressed: () {
                  Navigator.of(context).pop();
                  AppNav.openFriend(uid, data: user);
                },
              );
            }
            if (sent && incoming == null) {
              return const AppButton.outline(
                label: 'Request sent',
                icon: Icons.schedule_rounded,
                onPressed: null,
              );
            }
            return AppButton(
              label: incoming != null
                  ? 'Accept friend request'
                  : 'Send friend request',
              icon: Icons.person_add_alt_1_rounded,
              loading:
                  adding.contains(uid) ||
                  (incoming != null &&
                      ctrl.busyRequests.contains(incoming['id'])),
              onPressed: () async {
                final nav = Navigator.of(context);
                await onAdd(uid);
                if (nav.mounted &&
                    (ctrl.sentRequests.contains(uid) ||
                        ctrl.isAlreadyFriend(uid))) {
                  nav.pop();
                }
              },
            );
          }),
        ],
      ),
    );
  }
}

class _ContactMatchesSheet extends StatelessWidget {
  final List<Map<String, dynamic>> matches;
  final RxSet<String> adding;
  final Future<void> Function(String uid) onAdd;
  final Future<void> Function(Map<String, dynamic> request) onAccept;
  final VoidCallback onInvite;

  const _ContactMatchesSheet({
    required this.matches,
    required this.adding,
    required this.onAdd,
    required this.onAccept,
    required this.onInvite,
  });

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xxl,
          AppSpacing.sm,
          AppSpacing.xxl,
          AppSpacing.xxl,
        ),
        child: Column(
          children: [
            AppIllustration(
              icon: Icons.contacts_rounded,
              color: AppColors.positive,
              size: 130,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'None of your contacts are on SplitShare yet',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Invite them and start splitting bills together.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: 'Invite friends',
              icon: Icons.ios_share_rounded,
              onPressed: onInvite,
            ),
          ],
        ),
      );
    }
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.6,
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xxl,
          AppSpacing.sm,
          AppSpacing.xxl,
          AppSpacing.xxl,
        ),
        itemCount: matches.length,
        separatorBuilder: (_, _) => Divider(height: 1, color: AppColors.border),
        itemBuilder: (_, i) => _UserRow(
          user: matches[i],
          adding: adding,
          onAdd: onAdd,
          onAccept: onAccept,
          card: false,
        ),
      ),
    );
  }
}

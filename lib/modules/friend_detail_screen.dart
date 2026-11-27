import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../app/routes/app_routes.dart';
import '../controllers/balances.dart';
import '../controllers/expense_controller.dart';
import '../controllers/trip_controller.dart';
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
    // Only group balances left? Settle them right here.
    if (Balances.expensesWith(_uid).isEmpty) {
      _markTripsPaid(name);
      return;
    }
    Get.toNamed(AppRoutes.settleUp, arguments: {'uid': _uid});
  }

  bool _settlingTrips = false;

  /// Records pay-backs in every group shared with this person.
  Future<void> _markTripsPaid(String name) async {
    if (_settlingTrips) return;
    final first = Fmt.firstName(name);
    final owed = Balances.tripsWith(_uid);
    final pref = ProfileController.to.currencyCode.value;
    final v = owed[pref] ?? (owed.isEmpty ? 0 : owed.values.first);
    final ok = await AppDialogs.confirm(
      title: 'Mark group balances as paid?',
      message: v < 0
          ? 'You paid $first ${Fmt.multi(owed, preferred: pref)} for your groups. '
                'This records it in every group you share.'
          : '$first paid you ${Fmt.multi(owed, preferred: pref)} for your groups. '
                'This records it in every group you share.',
      confirmLabel: 'Mark paid',
      icon: Icons.check_circle_rounded,
    );
    if (!ok || !mounted) return;
    setState(() => _settlingTrips = true);
    try {
      final n = await TripController.to.settleAllWith(_uid);
      AppToast.success(
        n == 0
            ? 'Nothing left to settle in your groups.'
            : 'Recorded in $n ${n == 1 ? 'group' : 'groups'}.',
        title: 'Groups settled',
      );
    } catch (e) {
      AppToast.error(AppToast.friendly(e));
    } finally {
      if (mounted) setState(() => _settlingTrips = false);
    }
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
                  _expenses.balances.length;
                  // Expenses + groups, cancelled against each other (net),
                  // and the two directions kept apart (gross).
                  final balance = Balances.withPerson(_uid);
                  final gross = Balances.grossWith(_uid);
                  final tripLines = Balances.tripLinesWith(_uid);
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
                          theyOwe: gross.theyOwe,
                          iOwe: gross.iOwe,
                          preferred: preferred,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      FadeSlideIn(index: 2, child: _actions(p, balance)),
                      if (tripLines.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.lg),
                        FadeSlideIn(
                          index: 3,
                          child: _GroupsCard(
                            name: _nameOf(p),
                            lines: tripLines,
                            preferred: preferred,
                            busy: _settlingTrips,
                            onMarkPaid: () => _markTripsPaid(_nameOf(p)),
                          ),
                        ),
                      ],
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
                ? 'Friends'
                : 'Friends since ${Fmt.date(addedAt)}',
            color: AppColors.positive,
            icon: Icons.check_circle_rounded,
          )
        else ...[
          StatusPill(
            label: 'Not in your friends',
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
    // Reminders are sent for friends & groups debts.
    final owesMe = Balances.expensesWith(_uid).values.any((v) => v >= 0.005);
    // Three buttons don't have room for icons on a phone.
    final compact = owesMe;
    return Row(
      children: [
        Expanded(
          child: AppButton(
            label: 'Add expense',
            icon: compact ? null : Icons.add_rounded,
            height: 46,
            onPressed: () => _addExpense(p),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Opacity(
            // Still tappable: explains there's nothing to settle.
            opacity: hasBalance ? 1 : 0.5,
            child: AppButton.outline(
              label: 'Settle up',
              icon: compact ? null : Icons.handshake_rounded,
              height: 46,
              onPressed: () => _settleUp(hasBalance, name),
            ),
          ),
        ),
        if (owesMe) ...[
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: AppButton.outline(
              label: 'Remind',
              height: 46,
              loading: _reminding,
              onPressed: () => _remind(name),
            ),
          ),
        ],
      ],
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

        // Group by day: a plain day label, then one ruled block of rows.
        final days = <({String label, List<Map<String, dynamic>> items})>[];
        for (final e in items) {
          final label = Fmt.dayGroup(e['createdAt'] ?? e['date']);
          if (days.isEmpty || days.last.label != label) {
            days.add((label: label, items: [e]));
          } else {
            days.last.items.add(e);
          }
        }

        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
          sliver: SliverList.builder(
            itemCount: days.length,
            itemBuilder: (_, i) {
              final day = days[i];
              return FadeSlideIn(
                key: ValueKey('day-${day.label}'),
                index: i,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(
                        top: i == 0 ? 0 : AppSpacing.xl,
                        bottom: AppSpacing.sm,
                        left: 2,
                      ),
                      child: Text(
                        day.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    AppCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (var j = 0; j < day.items.length; j++) ...[
                            if (j > 0) const Divider(height: 1),
                            ExpenseTile(
                              key: ValueKey('exp-${day.items[j]['id']}'),
                              expense: day.items[j],
                              card: false,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// Both directions side by side ("You owe Ali" / "Ali owes you") on a split
/// bar, with the overall net as the headline.
class _BalanceCard extends StatelessWidget {
  final String name;

  /// Net per currency, positive = they owe me.
  final Map<String, double> balance;
  final Map<String, double> theyOwe;
  final Map<String, double> iOwe;
  final String preferred;

  const _BalanceCard({
    required this.name,
    required this.balance,
    required this.theyOwe,
    required this.iOwe,
    required this.preferred,
  });

  @override
  Widget build(BuildContext context) {
    final first = Fmt.firstName(name);

    if (theyOwe.isEmpty && iOwe.isEmpty) {
      return KhataTotal(
        label: 'All settled up',
        amount: Fmt.money(0, currencyCode: preferred),
        color: AppColors.textMuted,
        caption: "You and $first don't owe each other anything.",
      );
    }

    // The bar compares one currency: the preferred one if it is involved,
    // else the first one that is.
    final barCur = theyOwe.containsKey(preferred) || iOwe.containsKey(preferred)
        ? preferred
        : (theyOwe.keys.followedBy(iOwe.keys)).first;

    final nonZero = balance.values.where((v) => v.abs() >= 0.005).toList();
    final primary = balance[preferred] ?? nonZero.firstOrNull ?? 0;
    final dir = BalanceDirectionX.fromNet(primary);
    final mixed = nonZero.any((v) => v.sign != primary.sign);

    return KhataTotal(
      label: switch (dir) {
        _ when mixed => 'Overall balance',
        BalanceDirection.owedToYou => 'Overall you get back',
        BalanceDirection.youOwe => 'Overall you owe',
        BalanceDirection.settled => 'All settled up',
      },
      amount: Fmt.multi(balance, preferred: preferred, absolute: !mixed),
      color: mixed
          ? null
          : switch (dir) {
              BalanceDirection.youOwe => AppColors.negative,
              BalanceDirection.settled => AppColors.textMuted,
              BalanceDirection.owedToYou => null,
            },
      owed: theyOwe[barCur] ?? 0,
      owe: iOwe[barCur] ?? 0,
      owedLabel: '$first owes you\n${Fmt.multi(theyOwe, preferred: preferred)}',
      oweLabel: 'You owe $first\n${Fmt.multi(iOwe, preferred: preferred)}',
      caption: dir == BalanceDirection.settled && !mixed
          ? 'What you owe each other cancels out.'
          : null,
    );
  }
}

/// Group balances with this person, group by group, and a one-tap way to
/// record that they've been paid.
class _GroupsCard extends StatelessWidget {
  final String name;
  final List<({String tripId, String title, double amount, String currency})>
  lines;
  final String preferred;
  final bool busy;
  final VoidCallback onMarkPaid;

  const _GroupsCard({
    required this.name,
    required this.lines,
    required this.preferred,
    required this.busy,
    required this.onMarkPaid,
  });

  @override
  Widget build(BuildContext context) {
    final first = Fmt.firstName(name);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.groups_rounded,
                size: 18,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'In groups',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final l in lines)
            InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: () => Get.toNamed(
                AppRoutes.tripDetail,
                arguments: {'id': l.tripId},
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      l.amount > 0
                          ? '$first owes you ${Fmt.money(l.amount, currencyCode: l.currency)}'
                          : 'You owe ${Fmt.money(-l.amount, currencyCode: l.currency)}',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: l.amount > 0
                            ? AppColors.positive
                            : AppColors.negative,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: AppColors.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          AppButton(
            label: 'Mark group balances as paid',
            icon: Icons.check_circle_rounded,
            variant: AppButtonVariant.success,
            height: 46,
            loading: busy,
            onPressed: onMarkPaid,
          ),
        ],
      ),
    );
  }
}

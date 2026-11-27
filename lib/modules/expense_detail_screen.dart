import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../app/routes/app_routes.dart';
import '../controllers/expense_controller.dart';
import '../controllers/friend_controller.dart';
import '../controllers/group_controller.dart';
import '../controllers/profile_controller.dart';
import '../controllers/shell_controller.dart';
import '../core/ui.dart';

/// Live detail view of one expense or payment. Arguments: `{'id': String}`.
class ExpenseDetailScreen extends StatefulWidget {
  const ExpenseDetailScreen({super.key});

  @override
  State<ExpenseDetailScreen> createState() => _ExpenseDetailScreenState();
}

class _ExpenseDetailScreenState extends State<ExpenseDetailScreen> {
  String? _id;
  Stream<Map<String, dynamic>?>? _stream;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    final args = Get.arguments;
    final id = args is Map ? args['id']?.toString() : (args is String ? args : null);
    if (id != null && id.isNotEmpty) {
      _id = id;
      _stream = ExpenseController.to.expenseStream(id);
    }
  }

  void _retry() {
    final id = _id;
    if (id == null) return;
    setState(() => _stream = ExpenseController.to.expenseStream(id));
  }

  static double _num(dynamic v) => v is num ? v.toDouble() : 0.0;

  Future<void> _delete(Map<String, dynamic> e) async {
    final isPayment = ExpenseController.isPayment(e);
    final ok = await AppDialogs.confirm(
      title: isPayment ? 'Delete payment?' : 'Delete expense?',
      message: isPayment
          ? 'This payment will be removed and balances recalculated for everyone involved.'
          : '"${e['description'] ?? 'This expense'}" will be removed for everyone involved. This can\'t be undone.',
      confirmLabel: 'Delete',
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!ok || !mounted) return;
    setState(() => _deleting = true);
    try {
      await ExpenseController.to.deleteExpense(e);
      if (!mounted) return;
      Navigator.of(context).pop();
      AppToast.success(isPayment ? 'Payment deleted' : 'Expense deleted');
    } catch (err) {
      AppToast.error(AppToast.friendly(err));
      if (mounted) setState(() => _deleting = false);
    }
  }

  void _edit(Map<String, dynamic> e) {
    Get.toNamed(AppRoutes.addExpense, arguments: {'expense': e});
  }

  @override
  Widget build(BuildContext context) {
    if (_stream == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: const AppTopBar(title: 'Expense'),
        body: EmptyState(
          icon: Icons.receipt_long_rounded,
          title: 'Expense not found',
          message: 'This link doesn\'t point to an expense.',
          actionLabel: 'Go back',
          onAction: () => Navigator.of(context).maybePop(),
        ),
      );
    }

    return StreamBuilder<Map<String, dynamic>?>(
      stream: _stream,
      builder: (context, snap) {
        final e = snap.data;
        final loading = snap.connectionState == ConnectionState.waiting && !snap.hasData;
        final ctrl = ExpenseController.to;
        final canModify = e != null && ctrl.canModify(e);
        final isPayment = e != null && ExpenseController.isPayment(e);

        Widget body;
        if (snap.hasError && e == null) {
          body = ErrorState(onRetry: _retry);
        } else if (loading) {
          body = const _DetailSkeleton();
        } else if (e == null) {
          body = EmptyState(
            icon: Icons.delete_sweep_rounded,
            color: AppColors.textSecondary,
            title: 'This expense was deleted',
            message: 'Someone removed it, so it no longer affects any balances.',
            actionLabel: 'Go back',
            actionIcon: Icons.arrow_back_rounded,
            onAction: () => Navigator.of(context).maybePop(),
          );
        } else {
          body = _DetailBody(expense: e, num: _num);
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppTopBar(
            title: isPayment ? 'Payment' : 'Expense',
            actions: [
              if (canModify && !isPayment) ...[
                AppIconButton(
                  icon: Icons.edit_rounded,
                  tooltip: 'Edit',
                  size: 42,
                  onPressed: _deleting ? null : () => _edit(e),
                ),
                const SizedBox(width: 8),
              ],
              if (canModify)
                AppIconButton(
                  icon: Icons.delete_outline_rounded,
                  tooltip: 'Delete',
                  size: 42,
                  color: AppColors.error,
                  onPressed: _deleting ? null : () => _delete(e),
                ),
            ],
          ),
          body: LoadingOverlay(
            visible: _deleting,
            message: 'Deleting…',
            child: AnimatedSwitcher(
              duration: AppMotion.normal,
              child: KeyedSubtree(
                key: ValueKey(e == null ? (loading ? 'loading' : 'empty') : 'data'),
                child: body,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DetailBody extends StatelessWidget {
  final Map<String, dynamic> expense;
  final double Function(dynamic) num;

  const _DetailBody({required this.expense, required this.num});

  String _nameFor(String uid, Map<String, dynamic> names) {
    final ctrl = ExpenseController.to;
    if (uid == ctrl.currentUid) return 'You';
    final n = names[uid]?.toString();
    return (n != null && n.isNotEmpty) ? n : ctrl.nameFor(uid);
  }

  String _avatarFor(String uid) {
    if (uid == ExpenseController.to.currentUid) {
      return ProfileController.to.avatarUrl.value;
    }
    return (FriendController.to.friendByUid(uid)?['avatarUrl'] ?? '').toString();
  }

  /// Name used for initials / colour (never "You").
  String _avatarName(String uid, Map<String, dynamic> names) {
    if (uid == ExpenseController.to.currentUid) {
      final n = ProfileController.to.name.value;
      return n.isEmpty ? 'You' : n;
    }
    return _nameFor(uid, names);
  }

  bool _pairSettled(String a, String b) {
    if (expense['isSettled'] == true) return true;
    final pairs = (expense['settledPairs'] as List?)?.map((x) => x.toString()) ?? const [];
    return pairs.contains(ExpenseController.pairKey(a, b));
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = ExpenseController.to;
    final me = ctrl.currentUid;
    final e = expense;
    final isPayment = ExpenseController.isPayment(e);
    final style = ExpenseCategories.of(e['category']?.toString(), isPayment: isPayment);
    final currency = (e['currencyCode'] ?? 'USD').toString();
    final amount = num(e['amount']);
    final payer = ExpenseController.payerOf(e);
    final names = e['participantNames'] is Map
        ? Map<String, dynamic>.from(e['participantNames'] as Map)
        : <String, dynamic>{};
    final paidBy = e['paidBy'] is Map ? e['paidBy'] as Map : const {};
    if (payer.isNotEmpty && !names.containsKey(payer) && paidBy['name'] != null) {
      names[payer] = paidBy['name'];
    }
    final splits = e['individualSplits'] is Map
        ? Map<String, dynamic>.from(e['individualSplits'] as Map)
        : <String, dynamic>{};
    final creator = (e['createdBy'] ?? payer).toString();
    final creatorName = _nameFor(creator, names);
    final canModify = ctrl.canModify(e);
    final groupId = e['groupId']?.toString();
    final notes = (e['notes'] ?? '').toString().trim();
    final receiptUrl = (e['receiptUrl'] ?? '').toString();

    final sections = <Widget>[
      isPayment
          ? _paymentHeader(currency, amount, payer, splits, names)
          : _expenseHeader(context, style, currency, amount),
      const SizedBox(height: AppSpacing.md),
      _metaRow(e, creator == me ? 'you' : creatorName),
      if (groupId != null && groupId.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.md),
        Align(
          alignment: Alignment.centerLeft,
          child: _GroupChip(groupId: groupId),
        ),
      ],
      if (!isPayment) ...[
        const SizedBox(height: AppSpacing.xl),
        _positionCard(ctrl, me, payer, splits, currency),
        const SectionHeader(
          title: 'Paid by',
          padding: EdgeInsets.only(top: AppSpacing.xxl, bottom: AppSpacing.md),
        ),
        AppCard(
          padding: const EdgeInsets.all(14),
          child: _PersonRow(
            name: _nameFor(payer, names),
            avatarName: _avatarName(payer, names),
            avatarUrl: _avatarFor(payer),
            subtitle: payer == me ? 'You paid the full bill' : 'Paid the full bill',
            trailing: Text(
              Fmt.money(amount, currencyCode: currency),
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),
        SectionHeader(
          title: 'Split ${_splitLabel(e['splitType']?.toString())}',
          padding: const EdgeInsets.only(top: AppSpacing.xxl, bottom: AppSpacing.md),
        ),
        _splitCard(me, payer, splits, names, currency),
      ],
      if (notes.isNotEmpty) ...[
        const SectionHeader(
          title: 'Notes',
          padding: EdgeInsets.only(top: AppSpacing.xxl, bottom: AppSpacing.md),
        ),
        AppCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.sticky_note_2_outlined, color: AppColors.warning, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  notes,
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.45,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
      if (AppImage.canShow(receiptUrl)) ...[
        const SectionHeader(
          title: 'Receipt',
          padding: EdgeInsets.only(top: AppSpacing.xxl, bottom: AppSpacing.md),
        ),
        _ReceiptThumb(url: receiptUrl, heroTag: 'receipt_${e['id']}'),
      ],
      if (!canModify) ...[
        const SizedBox(height: AppSpacing.xxl),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline_rounded, size: 15, color: AppColors.textMuted),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Only $creatorName can edit this ${isPayment ? 'payment' : 'expense'}',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
              ),
            ),
          ],
        ),
      ],
    ];

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.sm,
        AppSpacing.page,
        AppSpacing.xxxl,
      ),
      itemCount: sections.length,
      itemBuilder: (_, i) => FadeSlideIn(index: i, child: sections[i]),
    );
  }

  static String _splitLabel(String? type) => switch (type) {
        'Percent' => 'by percentage',
        'Exact' => 'by exact amounts',
        'Full' => '— full amount owed',
        _ => 'equally',
      };

  Widget _expenseHeader(
    BuildContext context,
    CategoryStyle style,
    String currency,
    double amount,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: KhataTotal(
        label: (expense['description'] ?? 'Expense').toString(),
        amount: Fmt.money(amount, currencyCode: currency),
        caption: style.name,
        trailing: IconBadge(
          icon: style.icon,
          color: AppColors.onHero,
          size: 40,
          iconSize: 20,
        ),
      ),
    );
  }

  Widget _paymentHeader(
    String currency,
    double amount,
    String payer,
    Map<String, dynamic> splits,
    Map<String, dynamic> names,
  ) {
    final receiver = splits.keys.firstWhere(
      (k) => k != payer && num(splits[k]) > 0,
      orElse: () => splits.keys.firstWhere((k) => k != payer, orElse: () => ''),
    );
    final payerName = _nameFor(payer, names);
    final receiverName = receiver.isEmpty ? 'someone' : _nameFor(receiver, names);

    Widget person(String uid, String label) => Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppAvatar(
                name: _avatarName(uid, names),
                imageUrl: _avatarFor(uid),
                radius: 16,
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KhataTotal(
            label: 'Payment',
            amount: Fmt.money(amount, currencyCode: currency),
            caption: '$payerName paid $receiverName',
          ),
          const SizedBox(height: AppSpacing.lg),
          Semantics(
            label: '$payerName to $receiverName',
            excludeSemantics: true,
            child: Row(
              children: [
                person(payer, payerName),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                ),
                person(receiver, receiverName),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaRow(Map<String, dynamic> e, String creatorName) {
    final date = Fmt.date(e['date'] ?? e['createdAt']);
    final updated = e['updatedAt'] != null;
    return Text(
      '$date · Added by $creatorName${updated ? ' · edited ${Fmt.relative(e['updatedAt'])}' : ''}',
      style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
    );
  }

  Widget _positionCard(
    ExpenseController ctrl,
    String? me,
    String payer,
    Map<String, dynamic> splits,
    String currency,
  ) {
    final net = ctrl.myNetOn(expense);
    final myShare = me == null ? 0.0 : num(splits[me]);
    final involved = me != null && (splits.containsKey(me) || payer == me);

    late final IconData icon;
    late final Color color;
    late final String title;
    String? subtitle;

    if (net > 0.005) {
      icon = Icons.call_received_rounded;
      color = AppColors.positive;
      title = 'You lent ${Fmt.money(net, currencyCode: currency)}';
      subtitle = 'Your share: ${Fmt.money(myShare, currencyCode: currency)}';
    } else if (net < -0.005) {
      icon = Icons.call_made_rounded;
      color = AppColors.negative;
      title = 'You borrowed ${Fmt.money(-net, currencyCode: currency)}';
      subtitle = 'You owe ${_nameFor(payer, const {})} for your share';
    } else if (!involved) {
      icon = Icons.visibility_outlined;
      color = AppColors.textSecondary;
      title = 'You\'re not part of this split';
    } else {
      final hasDebts = splits.entries.any((s) => s.key != payer && num(s.value) > 0);
      final settled = expense['isSettled'] == true ||
          (payer == me
              ? hasDebts
              : _pairSettled(me, payer));
      icon = settled ? Icons.verified_rounded : Icons.check_circle_outline_rounded;
      color = settled ? AppColors.positive : AppColors.textSecondary;
      title = settled ? 'All settled up' : 'You don\'t owe anything';
      if (myShare > 0) {
        subtitle = 'Your share: ${Fmt.money(myShare, currencyCode: currency)}';
      }
    }

    return AppCard(
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: AppSpacing.md + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                    color: color == AppColors.negative
                        ? AppColors.negative
                        : AppColors.textPrimary,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _splitCard(
    String? me,
    String payer,
    Map<String, dynamic> splits,
    Map<String, dynamic> names,
    String currency,
  ) {
    final uids = splits.keys.toList()
      ..sort((a, b) {
        if (a == payer) return -1;
        if (b == payer) return 1;
        if (a == me) return -1;
        if (b == me) return 1;
        return _nameFor(a, names).toLowerCase().compareTo(_nameFor(b, names).toLowerCase());
      });

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Column(
        children: [
          for (var i = 0; i < uids.length; i++) ...[
            if (i > 0) Divider(height: 1, color: AppColors.border),
            _splitRow(uids[i], me, payer, splits, names, currency),
          ],
        ],
      ),
    );
  }

  Widget _splitRow(
    String uid,
    String? me,
    String payer,
    Map<String, dynamic> splits,
    Map<String, dynamic> names,
    String currency,
  ) {
    final share = num(splits[uid]);
    final name = _nameFor(uid, names);
    final isPayer = uid == payer;
    final settled = !isPayer && share > 0 && _pairSettled(uid, payer);

    String subtitle;
    if (isPayer) {
      subtitle = 'Paid · share ${Fmt.money(share, currencyCode: currency)}';
    } else if (share <= 0) {
      subtitle = 'Not sharing';
    } else {
      final verb = uid == me ? 'owe' : 'owes';
      subtitle = settled
          ? 'Settled with ${_nameFor(payer, names)}'
          : '$verb ${_nameFor(payer, names)}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: _PersonRow(
        name: name,
        avatarName: _avatarName(uid, names),
        avatarUrl: _avatarFor(uid),
        subtitle: subtitle,
        trailing: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              Fmt.money(share, currencyCode: currency),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: settled || isPayer || share <= 0
                    ? AppColors.textSecondary
                    : AppColors.textPrimary,
                decoration: settled ? TextDecoration.lineThrough : null,
              ),
            ),
            if (settled) ...[
              const SizedBox(height: 2),
              Text(
                'settled',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  final String name;
  final String avatarName;
  final String avatarUrl;
  final String subtitle;
  final Widget trailing;

  const _PersonRow({
    required this.name,
    required this.avatarName,
    required this.avatarUrl,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AppAvatar(name: avatarName, imageUrl: avatarUrl, radius: 20),
        const SizedBox(width: 12),
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
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        trailing,
      ],
    );
  }
}

class _GroupChip extends StatelessWidget {
  final String groupId;
  const _GroupChip({required this.groupId});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final group = GroupController.to.groupById(groupId);
      final name = (group?['name'] ?? 'Group').toString();
      final type = GroupTypes.of(group?['icon']?.toString());
      return Pressable(
        onTap: () => AppNav.openGroup(group ?? {'id': groupId}),
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconBadge(icon: type.icon, color: type.color, size: 26, iconSize: 15),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textMuted),
            ],
          ),
        ),
      );
    });
  }
}

class _ReceiptThumb extends StatelessWidget {
  final String url;
  final String heroTag;
  const _ReceiptThumb({required this.url, required this.heroTag});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(10),
      onTap: () => Navigator.of(context).push(
        PageRouteBuilder<void>(
          opaque: false,
          barrierColor: Colors.black,
          transitionDuration: AppMotion.slow,
          reverseTransitionDuration: AppMotion.normal,
          pageBuilder: (_, _, _) => _ReceiptViewer(url: url, heroTag: heroTag),
          transitionsBuilder: (_, anim, _, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
      ),
      child: Row(
        children: [
          Hero(
            tag: heroTag,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: AppImage(
                url: url,
                width: 72,
                height: 72,
                fit: BoxFit.cover,
                placeholder: const Skeleton(width: 72, height: 72, radius: 0),
                error: SizedBox(
                  width: 72,
                  height: 72,
                  child: ColoredBox(
                    color: AppColors.surfaceMuted,
                    child: Icon(Icons.broken_image_rounded, color: AppColors.textMuted),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Receipt photo',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Tap to view full size',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Icon(Icons.open_in_full_rounded, size: 20, color: AppColors.textMuted),
        ],
      ),
    );
  }
}

class _ReceiptViewer extends StatelessWidget {
  final String url;
  final String heroTag;
  const _ReceiptViewer({required this.url, required this.heroTag});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Center(
                child: Hero(
                  tag: heroTag,
                  child: AppImage(
                    url: url,
                    fit: BoxFit.contain,
                    placeholder: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                    error: const Center(
                      child: Text(
                        'Couldn\'t load the receipt',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: AppIconButton(
                icon: Icons.close_rounded,
                tooltip: 'Close',
                color: Colors.white,
                background: Colors.white.withValues(alpha: 0.16),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.lg, AppSpacing.page, 0),
      children: const [
        Align(
          alignment: Alignment.centerLeft,
          child: Skeleton(width: 140, height: 14),
        ),
        SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: Skeleton(width: 200, height: 40),
        ),
        SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: Skeleton(width: 220, height: 12),
        ),
        SizedBox(height: 28),
        Skeleton(height: 72, radius: AppRadius.lg),
        SizedBox(height: 28),
        SkeletonList(count: 3, shrinkWrap: true, padding: EdgeInsets.zero),
      ],
    );
  }
}

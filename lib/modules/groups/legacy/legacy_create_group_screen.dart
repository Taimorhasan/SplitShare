import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../controllers/expense_controller.dart';
import '../../../controllers/friend_controller.dart';
import '../../../controllers/group_controller.dart';
import '../../../controllers/profile_controller.dart';
import '../../../controllers/shell_controller.dart';
import '../../../core/ui.dart';

/// Create a new group: name, type, currency, members and an optional
/// starting expense split equally.
class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  static const _defaultType = 'Trip';

  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();

  String _type = _defaultType;
  late String _currency = ProfileController.to.currencyCode.value;
  late final String _initialCurrency = _currency;

  /// Selected friend uids, in selection order.
  final List<String> _selected = [];
  String _query = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(_onChanged);
    _amountCtrl.addListener(_onChanged);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _searchCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  bool get _dirty =>
      _nameCtrl.text.trim().isNotEmpty ||
      _selected.isNotEmpty ||
      _amountCtrl.text.trim().isNotEmpty ||
      _type != _defaultType ||
      _currency != _initialCurrency;

  double? get _amount {
    final v = double.tryParse(_amountCtrl.text.trim());
    return (v == null || v <= 0) ? null : v;
  }

  Map<String, dynamic>? _friend(String uid) =>
      FriendController.to.friendByUid(uid);

  void _toggle(String uid) {
    setState(() {
      if (_selected.contains(uid)) {
        _selected.remove(uid);
        if (_selected.isEmpty) _amountCtrl.clear();
      } else {
        _selected.add(uid);
      }
    });
  }

  Future<void> _handleBack() async {
    if (_saving) return;
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    final discard = await AppDialogs.confirm(
      title: 'Discard this group?',
      message: 'Your changes haven\'t been saved.',
      confirmLabel: 'Discard',
      cancelLabel: 'Keep editing',
      destructive: true,
    );
    if (discard && mounted) Navigator.of(context).pop();
  }

  Future<void> _create() async {
    if (_saving) return;
    AppNav.unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final name = _nameCtrl.text.trim();
    final amount = _selected.isEmpty ? null : _amount;
    final profile = ProfileController.to;
    final me = ExpenseController.to.currentUid;

    setState(() => _saving = true);
    try {
      final id = await GroupController.to.createGroup(
        name,
        List<String>.from(_selected),
        {'icon': _type, 'currencyCode': _currency},
      );

      final friendMembers = _selected.map((uid) {
        final f = _friend(uid) ?? const {};
        return <String, dynamic>{
          'uid': uid,
          'name': (f['name'] ?? 'Member').toString(),
          'email': (f['email'] ?? '').toString(),
          'avatarUrl': (f['avatarUrl'] ?? '').toString(),
        };
      }).toList();

      var expenseFailed = false;
      if (amount != null && me != null) {
        try {
          await ExpenseController.to.addExpenseFromInput(
            amountText: amount.toStringAsFixed(2),
            description: 'Starting expense',
            category: 'Other',
            date: DateTime.now(),
            paidByUser: {
              'uid': me,
              'name': profile.name.value.isEmpty ? 'You' : profile.name.value,
            },
            splitType: 'Equally',
            notes: '',
            splitWith: friendMembers
                .map(
                  (m) => {
                    'uid': m['uid'],
                    'name': m['name'],
                    'avatarUrl': m['avatarUrl'],
                  },
                )
                .toList(),
            splitValuesByUid: const {},
            currencyCode: _currency,
            groupId: id,
          );
        } catch (_) {
          expenseFailed = true;
        }
      }

      if (!mounted) return;
      if (expenseFailed) {
        AppToast.warning(
          'The group was created, but the starting expense couldn\'t be '
          'added. You can add it from the group.',
          title: 'Group created',
        );
      } else {
        AppToast.success('"$name" is ready to go.', title: 'Group created');
      }
      Get.offNamed(
        AppRoutes.groupDetail,
        arguments: {
          'id': id,
          'name': name,
          'icon': _type,
          'currencyCode': _currency,
          'createdBy': me,
          'members': [?me, ..._selected],
          'memberDetails': [
            if (me != null)
              {
                'uid': me,
                'name': profile.name.value,
                'email': profile.email.value,
                'avatarUrl': profile.avatarUrl.value,
              },
            ...friendMembers,
          ],
        },
      );
    } on GroupException catch (e) {
      if (mounted) setState(() => _saving = false);
      AppToast.error(e.message, title: 'Couldn\'t create group');
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      AppToast.error(AppToast.friendly(e), title: 'Couldn\'t create group');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppTopBar(title: 'New group', onBack: _handleBack),
        body: GestureDetector(
          onTap: AppNav.unfocus,
          behavior: HitTestBehavior.translucent,
          child: Form(
            key: _formKey,
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                AppSpacing.sm,
                AppSpacing.page,
                AppSpacing.xxxl,
              ),
              children: [
                FadeSlideIn(child: _buildPreview()),
                const SizedBox(height: AppSpacing.xxl),
                FadeSlideIn(
                  index: 1,
                  child: AppTextField(
                    controller: _nameCtrl,
                    label: 'Group name',
                    hint: 'e.g. Lisbon trip, Flat 4B',
                    prefixIcon: Icons.edit_rounded,
                    maxLength: 40,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.done,
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return 'Give your group a name';
                      if (t.length < 2) return 'Name is too short';
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                FadeSlideIn(index: 2, child: _buildTypePicker()),
                const SizedBox(height: AppSpacing.xxl),
                FadeSlideIn(index: 3, child: _buildCurrencyPicker()),
                const SizedBox(height: AppSpacing.xxl),
                FadeSlideIn(index: 4, child: _buildMembers()),
                const SizedBox(height: AppSpacing.xxl),
                FadeSlideIn(index: 5, child: _buildStartingExpense()),
              ],
            ),
          ),
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.md,
            AppSpacing.page,
            AppSpacing.md,
          ),
          child: SafeArea(
            top: false,
            child: AppButton(
              label: _selected.isEmpty
                  ? 'Create group'
                  : 'Create group with ${_selected.length + 1} people',
              icon: Icons.check_rounded,
              loading: _saving,
              onPressed: _nameCtrl.text.trim().isEmpty ? null : _create,
            ),
          ),
        ),
      ),
    );
  }

  // ---------- Sections ----------

  Widget _label(String text, {String? trailing}) => Padding(
    padding: const EdgeInsets.only(left: 2, bottom: AppSpacing.sm),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
      ],
    ),
  );

  Widget _buildPreview() {
    final style = GroupTypes.of(_type);
    final profile = ProfileController.to;
    final name = _nameCtrl.text.trim();
    final people = <Map<String, dynamic>>[
      {
        'name': profile.name.value.isEmpty ? 'You' : profile.name.value,
        'avatarUrl': profile.avatarUrl.value,
      },
      for (final uid in _selected)
        {
          'name': (_friend(uid)?['name'] ?? 'Member').toString(),
          'avatarUrl': (_friend(uid)?['avatarUrl'] ?? '').toString(),
        },
    ];
    return AnimatedContainer(
      duration: AppMotion.normal,
      curve: AppMotion.curve,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: AppMotion.normal,
            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
            child: IconBadge(
              key: ValueKey(_type),
              icon: style.icon,
              color: style.color,
              size: 56,
              iconSize: 28,
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? 'Your group name' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: name.isEmpty
                        ? AppColors.textMuted
                        : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${style.name} · $_currency · ${people.length} '
                  '${people.length == 1 ? 'member' : 'members'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                AvatarStack(people: people, radius: 13, max: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Group type'),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final t in GroupTypes.all)
              _ChoiceChip(
                label: t.name,
                icon: t.icon,
                color: t.color,
                selected: _type == t.name,
                onTap: () => setState(() => _type = t.name),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildCurrencyPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Currency', trailing: Currencies.names[_currency]),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final code in Currencies.symbols.keys)
              _ChoiceChip(
                label: '${Currencies.symbolFor(code)} $code',
                color: AppColors.primary,
                selected: _currency == code,
                onTap: () => setState(() => _currency = code),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildMembers() {
    return Obx(() {
      final friendCtrl = FriendController.to;
      final friends = friendCtrl.friends.toList();
      final q = _query.trim().toLowerCase();
      final filtered = q.isEmpty
          ? friends
          : friends.where((f) {
              final n = (f['name'] ?? '').toString().toLowerCase();
              final e = (f['email'] ?? '').toString().toLowerCase();
              return n.contains(q) || e.contains(q);
            }).toList();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label(
            'Members',
            trailing: _selected.isEmpty ? null : '${_selected.length} selected',
          ),
          if (friendCtrl.isLoading.value && friends.isEmpty)
            const SkeletonList(
              count: 3,
              shrinkWrap: true,
              padding: EdgeInsets.zero,
            )
          else if (friends.isEmpty)
            AppCard(
              child: Column(
                children: [
                  IconBadge(
                    icon: Icons.person_add_alt_1_rounded,
                    color: AppColors.primary,
                    size: 52,
                    iconSize: 26,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'No friends to add yet',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Add friends first, then invite them here. You can also '
                    'create the group now and add members later.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppButton.secondary(
                    label: 'Add friends',
                    icon: Icons.person_add_rounded,
                    height: 46,
                    expand: false,
                    onPressed: () => Get.toNamed(AppRoutes.addFriends),
                  ),
                ],
              ),
            )
          else ...[
            if (_selected.isNotEmpty) ...[
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [for (final uid in _selected) _selectedChip(uid)],
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            if (friends.length > 5) ...[
              AppSearchField(
                controller: _searchCtrl,
                hint: 'Search friends',
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: filtered.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Text(
                        'No friends match "${_query.trim()}"',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    )
                  : Column(
                      children: [
                        for (var i = 0; i < filtered.length; i++) ...[
                          if (i > 0)
                            Divider(
                              height: 1,
                              indent: 68,
                              color: AppColors.border,
                            ),
                          _friendRow(filtered[i]),
                        ],
                      ],
                    ),
            ),
          ],
        ],
      );
    });
  }

  Widget _selectedChip(String uid) {
    final f = _friend(uid);
    final name = (f?['name'] ?? 'Member').toString();
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppAvatar(
            name: name,
            imageUrl: f?['avatarUrl']?.toString(),
            radius: 12,
          ),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              Fmt.firstName(name),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
          InkWell(
            onTap: () => _toggle(uid),
            customBorder: const CircleBorder(),
            child: Padding(
              padding: EdgeInsets.all(4),
              child: Icon(
                Icons.close_rounded,
                size: 16,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _friendRow(Map<String, dynamic> f) {
    final uid = (f['uid'] ?? f['id'] ?? '').toString();
    final name = (f['name'] ?? 'Friend').toString();
    final email = (f['email'] ?? '').toString();
    final selected = _selected.contains(uid);
    return InkWell(
      onTap: uid.isEmpty ? null : () => _toggle(uid),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                    style: TextStyle(
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
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            Checkbox(
              value: selected,
              onChanged: uid.isEmpty ? null : (_) => _toggle(uid),
              activeColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStartingExpense() {
    final enabled = _selected.isNotEmpty;
    final amount = _amount;
    final people = _selected.length + 1;
    final String helper;
    if (!enabled) {
      helper = 'Select at least one member to add a starting expense.';
    } else if (amount == null) {
      helper =
          'Optional. Something you already paid for the group — it\'s '
          'split equally between all $people members.';
    } else {
      helper =
          'You paid ${Fmt.money(amount, currencyCode: _currency)}, split '
          'equally between $people people — everyone\'s share is '
          '${Fmt.money(amount / people, currencyCode: _currency)}.';
    }
    return AnimatedOpacity(
      duration: AppMotion.fast,
      opacity: enabled ? 1 : 0.6,
      child: AppTextField(
        controller: _amountCtrl,
        label: 'Starting expense (optional)',
        hint: '0.00',
        enabled: enabled && !_saving,
        prefixIcon: Icons.receipt_long_rounded,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [amountInputFormatter],
        helperText: helper,
        validator: (v) {
          if (!enabled || (v ?? '').trim().isEmpty) return null;
          return Validators.amount(v);
        },
      ),
    );
  }
}

/// Selectable pill used for group types and currencies.
class _ChoiceChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceChip({
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
        padding: EdgeInsets.symmetric(
          horizontal: icon == null ? 14 : 12,
          vertical: 9,
        ),
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
              Icon(
                icon,
                size: 17,
                color: selected ? color : AppColors.textSecondary,
              ),
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

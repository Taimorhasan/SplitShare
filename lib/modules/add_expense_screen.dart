import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import '../app/routes/app_routes.dart';
import '../controllers/expense_controller.dart';
import '../controllers/friend_controller.dart';
import '../controllers/group_controller.dart';
import '../controllers/profile_controller.dart';
import '../controllers/shell_controller.dart';
import '../core/ui.dart';

/// 'Full' = no split: whoever paid is owed the whole amount.
const _splitTypes = ['Equally', 'Percent', 'Exact', 'Full'];

/// Add / edit an expense.
///
/// Arguments (all optional, via `Get.arguments`): `groupId`, `groupName`,
/// `currencyCode`, `members` (preselected people), `friend` (one preselected
/// person) and `expense` (full expense doc → edit mode).
///
/// Every per-person value is keyed by uid, never by name.
class AddExpenseScreen extends StatefulWidget {
  const AddExpenseScreen({super.key});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _splitCtrls = <String, TextEditingController>{};

  late final String _me;
  late String _currency;
  String _category = ExpenseCategories.all.first.name;
  DateTime _date = DateTime.now();

  /// People sharing the expense, excluding the current user.
  final List<Map<String, dynamic>> _people = [];

  /// Extra pickable people (group members) besides friends.
  final List<Map<String, dynamic>> _extraCandidates = [];

  late String _payerUid;
  String _splitType = 'Equally';

  File? _receipt;
  String? _existingReceiptUrl;
  bool _removeExistingReceipt = false;

  bool _notesOpen = false;
  bool _saving = false;

  String? _groupId;
  String? _groupName;
  String? _expenseId;
  String _initialSignature = '';

  bool get _isEdit => _expenseId != null;

  List<String> get _everyone => [_me, ..._people.map((p) => p['uid'] as String)];

  // ---------------------------------------------------------------- lifecycle

  @override
  void initState() {
    super.initState();
    _me = ExpenseController.to.currentUid ?? '';
    _payerUid = _me;
    _currency = ProfileController.to.currencyCode.value;

    final raw = Get.arguments;
    final args = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final expense = args['expense'];
    if (expense is Map) {
      _prefill(Map<String, dynamic>.from(expense));
    } else {
      _applyArgs(args);
    }
    _amountCtrl.addListener(_rebuild);
    _initialSignature = _signature();
    _ready = true;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    _notesCtrl.dispose();
    for (final c in _splitCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// False while initState prefills controllers (their listeners must not
  /// call setState before the first build).
  bool _ready = false;

  void _rebuild() {
    if (_ready && mounted) setState(() {});
  }

  // ---------------------------------------------------------------- helpers

  static double _num(dynamic v) => v is num ? v.toDouble() : 0.0;

  static String? _nonEmpty(dynamic v) {
    final s = v?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }

  /// `12` → "12", `12.5` → "12.5", `12.25` → "12.25".
  static String _plain(double v) {
    if (v == v.truncateToDouble()) return v.toInt().toString();
    var s = v.toStringAsFixed(2);
    if (s.endsWith('0')) s = s.substring(0, s.length - 1);
    return s;
  }

  /// Splits [total] units into [n] integer parts that sum exactly to [total].
  static List<int> _distribute(int total, int n) {
    if (n <= 0) return const [];
    final base = total ~/ n;
    final rem = total % n;
    return List.generate(n, (i) => base + (i < rem ? 1 : 0));
  }

  double? get _amount {
    final v = double.tryParse(_amountCtrl.text.trim());
    return (v == null || v <= 0) ? null : v;
  }

  TextEditingController _ctrlFor(String uid) => _splitCtrls.putIfAbsent(
        uid,
        () => TextEditingController()..addListener(_rebuild),
      );

  double _valueOf(String uid) =>
      double.tryParse(_ctrlFor(uid).text.trim()) ?? 0;

  String _nameOf(String uid) {
    if (uid == _me) return 'You';
    final p = _people.firstWhereOrNull((p) => p['uid'] == uid);
    return (p?['name'] ?? ExpenseController.to.nameFor(uid)).toString();
  }

  String _avatarOf(String uid) {
    if (uid == _me) return ProfileController.to.avatarUrl.value;
    final p = _people.firstWhereOrNull((p) => p['uid'] == uid) ??
        _extraCandidates.firstWhereOrNull((p) => p['uid'] == uid) ??
        FriendController.to.friendByUid(uid);
    return (p?['avatarUrl'] ?? '').toString();
  }

  Map<String, dynamic>? _personFrom(Map raw) {
    final uid = _nonEmpty(raw['uid']);
    if (uid == null || uid == _me) return null;
    final friend = FriendController.to.friendByUid(uid);
    return {
      'uid': uid,
      'name': _nonEmpty(raw['name']) ??
          _nonEmpty(friend?['name']) ??
          ExpenseController.to.nameFor(uid),
      'avatarUrl':
          _nonEmpty(raw['avatarUrl']) ?? _nonEmpty(friend?['avatarUrl']) ?? '',
    };
  }

  void _addCandidate(Map<String, dynamic> p) {
    if (_extraCandidates.any((c) => c['uid'] == p['uid'])) return;
    _extraCandidates.add(p);
  }

  void _addPersonRaw(Map<String, dynamic> p) {
    if (_people.any((c) => c['uid'] == p['uid'])) return;
    _people.add(p);
  }

  /// Fills group name / members from the cached group, if any.
  void _resolveGroup() {
    final id = _groupId;
    if (id == null) return;
    final group = GroupController.to.groupById(id);
    if (group == null) return;
    _groupName ??= _nonEmpty(group['name']);
    for (final m in GroupController.membersOf(group)) {
      final p = _personFrom(m);
      if (p != null) _addCandidate(p);
    }
  }

  void _applyArgs(Map<String, dynamic> args) {
    _groupId = _nonEmpty(args['groupId']);
    _groupName = _nonEmpty(args['groupName']);
    final cur = _nonEmpty(args['currencyCode']);
    if (cur != null && Currencies.symbols.containsKey(cur)) _currency = cur;

    final members = args['members'];
    if (members is List) {
      for (final m in members) {
        if (m is! Map) continue;
        final p = _personFrom(m);
        if (p == null) continue;
        _addCandidate(p);
        _addPersonRaw(p);
      }
    }
    final friend = args['friend'];
    if (friend is Map) {
      final p = _personFrom(friend);
      if (p != null) _addPersonRaw(p);
    }
    _resolveGroup();
  }

  void _prefill(Map<String, dynamic> e) {
    _expenseId = _nonEmpty(e['id']);
    final amount = _num(e['amount']);
    if (amount > 0) _amountCtrl.text = _plain(amount);
    _descCtrl.text = (e['description'] ?? '').toString();
    final cat = e['category']?.toString();
    _category = ExpenseCategories.all.any((c) => c.name == cat)
        ? cat!
        : ExpenseCategories.all.last.name;
    _date = Fmt.toDate(e['date']) ?? DateTime.now();
    _notesCtrl.text = (e['notes'] ?? '').toString();
    _notesOpen = _notesCtrl.text.trim().isNotEmpty;
    final cur = _nonEmpty(e['currencyCode']);
    if (cur != null && Currencies.symbols.containsKey(cur)) _currency = cur;
    _groupId = _nonEmpty(e['groupId']);
    _existingReceiptUrl = _nonEmpty(e['receiptUrl']);

    final names = e['participantNames'] is Map
        ? Map<String, dynamic>.from(e['participantNames'] as Map)
        : <String, dynamic>{};
    final splits = e['individualSplits'] is Map
        ? Map<String, dynamic>.from(e['individualSplits'] as Map)
        : <String, dynamic>{};
    final involved = (e['involvedUsers'] as List?)
            ?.map((x) => x.toString())
            .toList() ??
        splits.keys.toList();

    for (final uid in involved) {
      if (uid == _me || uid.isEmpty) continue;
      final p = _personFrom({'uid': uid, 'name': names[uid]});
      if (p != null) _addPersonRaw(p);
    }

    final payer = ExpenseController.payerOf(e);
    _payerUid = payer.isEmpty ? _me : payer;
    if (_payerUid != _me && !_people.any((p) => p['uid'] == _payerUid)) {
      final paidBy = e['paidBy'] is Map ? e['paidBy'] as Map : const {};
      final p = _personFrom({'uid': _payerUid, 'name': paidBy['name']});
      if (p != null) _addPersonRaw(p);
    }

    var type = _splitTypes.contains(e['splitType']) ? e['splitType'] as String : 'Equally';
    // Older expenses may have someone with a zero share under "Equally"
    // (e.g. a payer who didn't share). Keep their exact amounts instead of
    // silently re-splitting.
    if (type == 'Equally' && _everyone.any((u) => _num(splits[u]) <= 0)) {
      type = 'Exact';
    }
    _splitType = type;

    if (type == 'Exact') {
      for (final u in _everyone) {
        _ctrlFor(u).text = _plain(_num(splits[u]));
      }
    } else if (type == 'Percent' && amount > 0) {
      // Recompute percentages from stored amounts, in hundredths of a
      // percent, nudging the largest share so the total is exactly 100.
      final hundredths = {
        for (final u in _everyone) u: (_num(splits[u]) / amount * 10000).round(),
      };
      final diff = 10000 - hundredths.values.fold<int>(0, (a, b) => a + b);
      if (diff != 0 && hundredths.isNotEmpty) {
        final top = hundredths.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
        hundredths[top] = hundredths[top]! + diff;
      }
      hundredths.forEach((u, h) => _ctrlFor(u).text = _plain(h / 100));
    }
    _resolveGroup();
  }

  String _signature() => [
        _amountCtrl.text.trim(),
        _descCtrl.text.trim(),
        _notesCtrl.text.trim(),
        _category,
        '${_date.year}-${_date.month}-${_date.day}',
        _currency,
        _people.map((p) => p['uid']).join(','),
        _payerUid,
        _splitType,
        if (_splitType == 'Percent' || _splitType == 'Exact')
          _everyone.map((u) => _ctrlFor(u).text.trim()).join(','),
        _receipt?.path ?? '',
        '$_removeExistingReceipt',
      ].join('|');

  bool get _isDirty => _signature() != _initialSignature;

  // ---------------------------------------------------------------- actions

  Future<void> _attemptPop() async {
    if (_saving) return;
    if (_isDirty) {
      final ok = await AppDialogs.confirm(
        title: 'Discard changes?',
        message: _isEdit
            ? 'Your edits to this expense will be lost.'
            : 'This expense hasn\'t been saved yet.',
        confirmLabel: 'Discard',
        cancelLabel: 'Keep editing',
        destructive: true,
      );
      if (!ok) return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _setPeople(List<Map<String, dynamic>> people) {
    final keep = people.map((p) => p['uid'] as String).toSet();
    final removed = _splitCtrls.keys.where((u) => u != _me && !keep.contains(u)).toList();
    for (final u in removed) {
      _splitCtrls.remove(u)?.dispose();
    }
    _people
      ..clear()
      ..addAll(people);
    if (!_everyone.contains(_payerUid)) _payerUid = _me;
    if (_splitType != 'Equally') _fillEvenly(silent: true);
    setState(() {});
  }

  void _setSplitType(String type) {
    if (type == _splitType) return;
    _splitType = type;
    if (type != 'Equally') _fillEvenly(silent: true);
    setState(() {});
  }

  /// Fills Percent / Exact inputs with an even split that totals exactly.
  void _fillEvenly({bool silent = false}) {
    final uids = _everyone;
    if (_splitType == 'Percent') {
      final parts = _distribute(10000, uids.length);
      for (var i = 0; i < uids.length; i++) {
        _ctrlFor(uids[i]).text = _plain(parts[i] / 100);
      }
    } else if (_splitType == 'Exact') {
      final amount = _amount;
      if (amount == null) {
        if (!silent) AppToast.warning('Enter the total amount first');
        return;
      }
      final parts = _distribute((amount * 100).round(), uids.length);
      for (var i = 0; i < uids.length; i++) {
        _ctrlFor(uids[i]).text = _plain(parts[i] / 100);
      }
    }
  }

  Future<void> _pickCurrency() async {
    AppNav.unfocus();
    final code = await AppDialogs.sheet<String>(
      title: 'Currency',
      child: _CurrencySheet(selected: _currency),
    );
    if (code != null && mounted) setState(() => _currency = code);
  }

  Future<void> _pickDate() async {
    AppNav.unfocus();
    final now = DateTime.now();
    final last = DateTime(now.year + 1, now.month, now.day);
    final first = DateTime(2000);
    var initial = _date;
    if (initial.isAfter(last)) initial = last;
    if (initial.isBefore(first)) initial = first;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: 'Expense date',
      builder: (ctx, child) {
        final theme = Theme.of(ctx);
        return Theme(
          data: theme.copyWith(
            colorScheme: theme.colorScheme.copyWith(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: AppColors.surface,
              onSurface: AppColors.textPrimary,
            ),
            datePickerTheme: DatePickerThemeData(
              backgroundColor: AppColors.surface,
              surfaceTintColor: Colors.transparent,
              headerBackgroundColor: AppColors.primary,
              headerForegroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.xl),
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      setState(() {
        _date = DateTime(picked.year, picked.month, picked.day, _date.hour, _date.minute);
      });
    }
  }

  Future<void> _pickPeople() async {
    AppNav.unfocus();
    final result = await AppDialogs.sheet<List<Map<String, dynamic>>>(
      title: 'Split with',
      child: _PeoplePickerSheet(
        me: _me,
        current: List<Map<String, dynamic>>.from(_people),
        extra: List<Map<String, dynamic>>.from(_extraCandidates),
      ),
    );
    if (result != null && mounted) _setPeople(result);
  }

  Future<void> _pickPayer() async {
    AppNav.unfocus();
    final uids = _everyone;
    final picked = await AppDialogs.sheet<String>(
      title: 'Who paid?',
      child: Builder(
        builder: (ctx) => ListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
          itemCount: uids.length,
          itemBuilder: (_, i) {
            final uid = uids[i];
            final selected = uid == _payerUid;
            return _SelectRow(
              selected: selected,
              leading: AppAvatar(
                name: uid == _me ? ProfileController.to.name.value : _nameOf(uid),
                imageUrl: _avatarOf(uid),
                radius: 20,
              ),
              title: _nameOf(uid),
              onTap: () => Navigator.of(ctx).pop(uid),
            );
          },
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _payerUid = picked);
  }

  Future<void> _pickReceipt() async {
    AppNav.unfocus();
    final hasReceipt = _receipt != null ||
        (_existingReceiptUrl != null && !_removeExistingReceipt);
    final source = await AppDialogs.sheet<String>(
      title: 'Receipt',
      child: Builder(
        builder: (ctx) => Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppListTile(
                icon: Icons.photo_camera_rounded,
                title: 'Take a photo',
                onTap: () => Navigator.of(ctx).pop('camera'),
              ),
              AppListTile(
                icon: Icons.photo_library_rounded,
                iconColor: AppColors.secondary,
                title: 'Choose from gallery',
                onTap: () => Navigator.of(ctx).pop('gallery'),
              ),
              if (hasReceipt)
                AppListTile(
                  icon: Icons.delete_outline_rounded,
                  title: 'Remove receipt',
                  destructive: true,
                  onTap: () => Navigator.of(ctx).pop('remove'),
                ),
            ],
          ),
        ),
      ),
    );
    if (source == null || !mounted) return;
    if (source == 'remove') {
      _removeReceipt();
      return;
    }
    try {
      final image = await ImagePicker().pickImage(
        source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 1600,
      );
      if (image != null && mounted) {
        setState(() => _receipt = File(image.path));
      }
    } catch (e) {
      AppToast.error(
        source == 'camera'
            ? 'Couldn\'t open the camera. Check camera permissions and try again.'
            : 'Couldn\'t open your photos. Check permissions and try again.',
      );
    }
  }

  void _removeReceipt() {
    setState(() {
      if (_receipt != null) {
        _receipt = null;
      } else if (_existingReceiptUrl != null) {
        _removeExistingReceipt = true;
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    AppNav.unfocus();
    final amountError = Validators.amount(_amountCtrl.text);
    if (amountError != null) {
      AppToast.warning(amountError);
      return;
    }
    if (!(_formKey.currentState?.validate() ?? true)) {
      AppToast.warning('Please add a description');
      return;
    }
    if (_people.isEmpty) {
      AppToast.warning('Add at least one person to split with');
      return;
    }

    setState(() => _saving = true);
    try {
      final ctrl = ExpenseController.to;
      final paidBy = <String, dynamic>{
        'uid': _payerUid,
        'name': _payerUid == _me ? 'You' : _nameOf(_payerUid),
      };
      final values = (_splitType == 'Equally' || _splitType == 'Full')
          ? <String, double>{}
          : {for (final u in _everyone) u: _valueOf(u)};
      final splitWith = _people
          .map((p) => <String, dynamic>{
                'uid': p['uid'],
                'name': p['name'],
                'avatarUrl': p['avatarUrl'] ?? '',
              })
          .toList();

      if (_isEdit) {
        await ctrl.updateExpenseFromInput(
          expenseId: _expenseId!,
          amountText: _amountCtrl.text,
          description: _descCtrl.text,
          category: _category,
          date: _date,
          paidByUser: paidBy,
          splitType: _splitType,
          notes: _notesCtrl.text,
          splitWith: splitWith,
          splitValuesByUid: values,
          currencyCode: _currency,
          groupId: _groupId,
          receiptFile: _receipt,
          removeReceipt: _removeExistingReceipt && _receipt == null,
        );
      } else {
        await ctrl.addExpenseFromInput(
          amountText: _amountCtrl.text,
          description: _descCtrl.text,
          category: _category,
          date: _date,
          paidByUser: paidBy,
          splitType: _splitType,
          notes: _notesCtrl.text,
          splitWith: splitWith,
          splitValuesByUid: values,
          currencyCode: _currency,
          groupId: _groupId,
          receiptFile: _receipt,
        );
      }
      if (!mounted) return;
      _initialSignature = _signature();
      await AppDialogs.success(
        title: _isEdit ? 'Changes saved' : 'Expense added',
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } on ExpenseValidationException catch (e) {
      AppToast.warning(e.message);
    } catch (e) {
      AppToast.error(AppToast.friendly(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _attemptPop();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppTopBar(
          title: _isEdit ? 'Edit expense' : 'Add expense',
          onBack: _attemptPop,
        ),
        body: Column(
          children: [
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.page,
                    AppSpacing.xs,
                    AppSpacing.page,
                    AppSpacing.xxxl,
                  ),
                  children: [
                    if (_groupId != null) ...[
                      Center(child: _groupChip()),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    _amountCard(),
                    const SizedBox(height: AppSpacing.xl),
                    AppTextField(
                      controller: _descCtrl,
                      label: 'Description',
                      hint: 'What was it for?',
                      prefixIcon: Icons.edit_note_rounded,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.done,
                      maxLength: 80,
                      validator: (v) => Validators.required(v, 'Description'),
                    ),
                    _sectionTitle('Category'),
                    _categoryChips(),
                    _sectionTitle('Date'),
                    _dateCard(),
                    _sectionTitle('Split with'),
                    _peopleCard(),
                    _sectionTitle('Paid by'),
                    _payerCard(),
                    _sectionTitle('How to split'),
                    _splitTypeControl(),
                    const SizedBox(height: AppSpacing.md),
                    _splitDetails(),
                    _sectionTitle('Notes & receipt'),
                    _notesSection(),
                    const SizedBox(height: AppSpacing.md),
                    _receiptSection(),
                  ],
                ),
              ),
            ),
            _bottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) => SectionHeader(
        title: title,
        padding: const EdgeInsets.only(top: AppSpacing.xl, bottom: AppSpacing.md),
      );

  Widget _groupChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.groups_rounded, size: 16, color: AppColors.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'in ${_groupName ?? 'group'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _amountCard() {
    final symbol = Currencies.symbolFor(_currency);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      child: Column(
        children: [
          const Text(
            'Total amount',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                symbol,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 80),
                  child: IntrinsicWidth(
                    child: TextField(
                      controller: _amountCtrl,
                      autofocus: !_isEdit,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [amountInputFormatter],
                      textAlign: TextAlign.center,
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(
                        fontSize: 44,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        letterSpacing: -1,
                      ),
                      decoration: const InputDecoration(
                        hintText: '0.00',
                        hintStyle: TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.w800,
                          color: AppColors.border,
                          letterSpacing: -1,
                        ),
                        filled: false,
                        isCollapsed: true,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 4),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Pressable(
            onTap: _pickCurrency,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      '$_currency · ${Currencies.names[_currency] ?? _currency}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.expand_more_rounded, size: 18, color: AppColors.primary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (final c in ExpenseCategories.all) ...[
            _CategoryChip(
              style: c,
              selected: c.name == _category,
              onTap: () => setState(() => _category = c.name),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    );
  }

  Widget _dateCard() {
    final today = DateTime.now();
    final isToday = _date.year == today.year &&
        _date.month == today.month &&
        _date.day == today.day;
    return AppCard(
      onTap: _pickDate,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          const IconBadge(
            icon: Icons.calendar_today_rounded,
            color: AppColors.primary,
            size: 40,
            iconSize: 19,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              isToday ? 'Today, ${Fmt.date(_date)}' : Fmt.date(_date),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
        ],
      ),
    );
  }

  Widget _peopleCard() {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_people.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.md, left: 2),
              child: Text(
                'Add at least one person to share this expense with.',
                style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary),
              ),
            ),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final p in _people)
                _PersonChip(
                  name: p['name'].toString(),
                  avatarUrl: p['avatarUrl']?.toString(),
                  onRemove: () => _setPeople(
                    _people.where((x) => x['uid'] != p['uid']).toList(),
                  ),
                ),
              Pressable(
                onTap: _pickPeople,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_add_alt_1_rounded, size: 17, color: AppColors.primary),
                      SizedBox(width: 6),
                      Text(
                        'Add people',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _payerCard() {
    final name = _nameOf(_payerUid);
    return AppCard(
      onTap: _pickPayer,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          AppAvatar(
            name: _payerUid == _me ? ProfileController.to.name.value : name,
            imageUrl: _avatarOf(_payerUid),
            radius: 20,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              _payerUid == _me ? 'You paid' : '$name paid',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const Text(
            'Change',
            style: TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
              fontSize: 13.5,
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.primary, size: 20),
        ],
      ),
    );
  }

  Widget _splitTypeControl() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          for (final type in _splitTypes)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _setSplitType(type),
                child: AnimatedContainer(
                  duration: AppMotion.normal,
                  curve: AppMotion.curve,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color: type == _splitType ? AppColors.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    boxShadow: type == _splitType ? AppShadows.soft : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        switch (type) {
                          'Percent' => Icons.percent_rounded,
                          'Exact' => Icons.tune_rounded,
                          'Full' => Icons.east_rounded,
                          _ => Icons.drag_handle_rounded,
                        },
                        size: 16,
                        color: type == _splitType ? AppColors.primary : AppColors.textMuted,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          type,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: type == _splitType
                                ? AppColors.primary
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// "Full amount": the payer is owed everything; nobody else's share is
  /// deducted from the payer.
  Widget _fullAmountDetails(List<String> uids, double? amount) {
    final owers = uids.where((u) => u != _payerUid).toList();
    final shares = (amount == null || owers.isEmpty)
        ? null
        : _distribute((amount * 100).round(), owers.length);
    final payerName = _payerUid == _me ? 'You' : _nameOf(_payerUid);
    final String headline;
    if (owers.isEmpty) {
      headline = 'Add the person who owes this amount';
    } else if (owers.length == 1) {
      final who = owers.first == _me ? 'You owe' : '${_nameOf(owers.first)} owes';
      headline = '$who ${payerName == 'You' ? 'you' : payerName} the full amount';
    } else {
      headline = '$payerName paid — the others owe the full amount';
    }
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconBadge(
                icon: Icons.east_rounded,
                color: AppColors.positive,
                size: 30,
                iconSize: 16,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  headline,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            "No split — the payer's own share is zero.",
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < owers.length; i++)
            _ShareRow(
              name: _nameOf(owers[i]),
              avatarName: owers[i] == _me
                  ? ProfileController.to.name.value
                  : _nameOf(owers[i]),
              avatarUrl: _avatarOf(owers[i]),
              trailing: Text(
                shares == null
                    ? '—'
                    : Fmt.money(shares[i] / 100, currencyCode: _currency),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _splitDetails() {
    final uids = _everyone;
    final amount = _amount;

    if (_splitType == 'Full') return _fullAmountDetails(uids, amount);

    if (_splitType == 'Equally') {
      final shares = amount == null
          ? null
          : _distribute((amount * 100).round(), uids.length);
      return AppCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              uids.length < 2
                  ? 'Add people to see each share'
                  : 'Split equally between ${uids.length} people',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            for (var i = 0; i < uids.length; i++)
              _ShareRow(
                name: _nameOf(uids[i]),
                avatarName: uids[i] == _me ? ProfileController.to.name.value : _nameOf(uids[i]),
                avatarUrl: _avatarOf(uids[i]),
                trailing: Text(
                  shares == null ? '—' : Fmt.money(shares[i] / 100, currencyCode: _currency),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    final isPercent = _splitType == 'Percent';
    final sum = uids.fold(0.0, (s, u) => s + _valueOf(u));
    final double target = isPercent ? 100 : (amount ?? 0);
    final remaining = target - sum;
    final valid = target > 0 && remaining.abs() <= 0.01;
    final Color statusColor = valid
        ? AppColors.positive
        : remaining < 0
            ? AppColors.negative
            : AppColors.warning;
    String fmt(double v) =>
        isPercent ? '${_plain(double.parse(v.toStringAsFixed(2)))}%' : Fmt.money(v, currencyCode: _currency);
    final status = valid
        ? '${isPercent ? '100%' : fmt(target)} ✓'
        : remaining < 0
            ? '${fmt(-remaining)} over'
            : '${fmt(remaining)} left';

    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: AppMotion.normal,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  _fillEvenly();
                  setState(() {});
                },
                icon: const Icon(Icons.auto_fix_high_rounded, size: 17),
                label: const Text('Split evenly'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final uid in uids)
            _ShareRow(
              name: _nameOf(uid),
              avatarName: uid == _me ? ProfileController.to.name.value : _nameOf(uid),
              avatarUrl: _avatarOf(uid),
              caption: isPercent && amount != null
                  ? Fmt.money(amount * _valueOf(uid) / 100, currencyCode: _currency)
                  : null,
              trailing: SizedBox(
                width: 116,
                child: TextField(
                  controller: _ctrlFor(uid),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [amountInputFormatter],
                  textAlign: TextAlign.end,
                  textInputAction: TextInputAction.next,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '0',
                    prefixText: isPercent ? null : '${Currencies.symbolFor(_currency)} ',
                    suffixText: isPercent ? '%' : null,
                    fillColor: AppColors.surfaceMuted,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _notesSection() {
    if (!_notesOpen) {
      return AppCard(
        onTap: () => setState(() => _notesOpen = true),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: const Row(
          children: [
            IconBadge(
              icon: Icons.sticky_note_2_rounded,
              color: AppColors.warning,
              size: 40,
              iconSize: 19,
            ),
            SizedBox(width: 14),
            Expanded(
              child: Text(
                'Add a note',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Icon(Icons.add_rounded, color: AppColors.textMuted),
          ],
        ),
      );
    }
    return AppTextField(
      controller: _notesCtrl,
      hint: 'Anything others should know? (optional)',
      prefixIcon: Icons.sticky_note_2_outlined,
      maxLines: 3,
      maxLength: 300,
      textCapitalization: TextCapitalization.sentences,
      autofocus: _notesCtrl.text.isEmpty,
      suffix: IconButton(
        tooltip: 'Hide notes',
        icon: const Icon(Icons.expand_less_rounded),
        onPressed: () {
          if (_notesCtrl.text.trim().isEmpty) {
            _notesCtrl.clear();
            AppNav.unfocus();
            setState(() => _notesOpen = false);
          } else {
            AppNav.unfocus();
          }
        },
      ),
    );
  }

  Widget _receiptSection() {
    final showExisting = _receipt == null &&
        _existingReceiptUrl != null &&
        !_removeExistingReceipt;

    if (_receipt == null && !showExisting) {
      return AppCard(
        onTap: _pickReceipt,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: const Row(
          children: [
            IconBadge(
              icon: Icons.receipt_long_rounded,
              color: AppColors.accent,
              size: 40,
              iconSize: 19,
            ),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add receipt photo',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Camera or gallery',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Icon(Icons.add_a_photo_rounded, color: AppColors.textMuted, size: 20),
          ],
        ),
      );
    }

    final Widget thumb = _receipt != null
        ? Image.file(_receipt!, fit: BoxFit.cover, width: 64, height: 64)
        : CachedNetworkImage(
            imageUrl: _existingReceiptUrl!,
            fit: BoxFit.cover,
            width: 64,
            height: 64,
            placeholder: (_, _) => const Skeleton(width: 64, height: 64, radius: 0),
            errorWidget: (_, _, _) => const ColoredBox(
              color: AppColors.surfaceMuted,
              child: Icon(Icons.broken_image_rounded, color: AppColors.textMuted),
            ),
          );

    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: thumb,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Receipt attached',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _receipt != null ? 'Uploads when you save' : 'Saved with this expense',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          AppIconButton(
            icon: Icons.swap_horiz_rounded,
            tooltip: 'Replace',
            size: 38,
            background: AppColors.surfaceMuted,
            onPressed: _pickReceipt,
          ),
          const SizedBox(width: 8),
          AppIconButton(
            icon: Icons.close_rounded,
            tooltip: 'Remove',
            size: 38,
            color: AppColors.error,
            background: AppColors.negativeLight,
            onPressed: _removeReceipt,
          ),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: AppShadows.soft,
      ),
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, 12, AppSpacing.page, 12),
      child: SafeArea(
        top: false,
        child: AppButton(
          label: _isEdit ? 'Save changes' : 'Save expense',
          icon: Icons.check_rounded,
          loading: _saving,
          onPressed: _save,
        ),
      ),
    );
  }
}

// ==================================================================== widgets

class _CategoryChip extends StatelessWidget {
  final CategoryStyle style;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.style,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.normal,
        curve: AppMotion.curve,
        padding: const EdgeInsets.fromLTRB(8, 7, 14, 7),
        decoration: BoxDecoration(
          color: selected ? style.color : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: selected ? style.color : AppColors.border),
          boxShadow: selected ? AppShadows.glow(style.color) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: selected ? Colors.white.withValues(alpha: 0.22) : style.tint,
                shape: BoxShape.circle,
              ),
              child: Icon(
                style.icon,
                size: 16,
                color: selected ? Colors.white : style.color,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              style.name,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonChip extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final VoidCallback onRemove;

  const _PersonChip({
    required this.name,
    required this.avatarUrl,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppAvatar(name: name, imageUrl: avatarUrl, radius: 13),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 2),
          Semantics(
            button: true,
            label: 'Remove $name',
            child: InkResponse(
              onTap: onRemove,
              radius: 18,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close_rounded, size: 17, color: AppColors.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareRow extends StatelessWidget {
  final String name;
  final String avatarName;
  final String? avatarUrl;
  final String? caption;
  final Widget trailing;

  const _ShareRow({
    required this.name,
    required this.avatarName,
    required this.avatarUrl,
    required this.trailing,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          AppAvatar(name: avatarName, imageUrl: avatarUrl, radius: 17),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (caption != null)
                  Text(
                    caption!,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          trailing,
        ],
      ),
    );
  }
}

/// A tappable row with a trailing check when selected (used in sheets).
class _SelectRow extends StatelessWidget {
  final Widget leading;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _SelectRow({
    required this.leading,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primaryLight : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                      ),
                  ],
                ),
              ),
              AnimatedOpacity(
                duration: AppMotion.fast,
                opacity: selected ? 1 : 0,
                child: const Icon(Icons.check_circle_rounded, color: AppColors.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CurrencySheet extends StatelessWidget {
  final String selected;
  const _CurrencySheet({required this.selected});

  @override
  Widget build(BuildContext context) {
    final codes = Currencies.symbols.keys.toList();
    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      itemCount: codes.length,
      itemBuilder: (ctx, i) {
        final code = codes[i];
        return _SelectRow(
          selected: code == selected,
          leading: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              Currencies.symbolFor(code),
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
          title: Currencies.names[code] ?? code,
          subtitle: code,
          onTap: () => Navigator.of(ctx).pop(code),
        );
      },
    );
  }
}

/// Multi-select people picker over friends + group members.
class _PeoplePickerSheet extends StatefulWidget {
  final String me;
  final List<Map<String, dynamic>> current;
  final List<Map<String, dynamic>> extra;

  const _PeoplePickerSheet({
    required this.me,
    required this.current,
    required this.extra,
  });

  @override
  State<_PeoplePickerSheet> createState() => _PeoplePickerSheetState();
}

class _PeoplePickerSheetState extends State<_PeoplePickerSheet> {
  final _searchCtrl = TextEditingController();
  late final Set<String> _selected =
      widget.current.map((p) => p['uid'].toString()).toSet();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _candidates() {
    final byUid = <String, Map<String, dynamic>>{};
    void add(Map raw) {
      final uid = raw['uid']?.toString() ?? '';
      if (uid.isEmpty || uid == widget.me || byUid.containsKey(uid)) return;
      byUid[uid] = {
        'uid': uid,
        'name': (raw['name'] ?? 'Unknown').toString(),
        'avatarUrl': (raw['avatarUrl'] ?? '').toString(),
        'email': (raw['email'] ?? '').toString(),
      };
    }

    widget.current.forEach(add);
    widget.extra.forEach(add);
    FriendController.to.friends.forEach(add);
    final list = byUid.values.toList()
      ..sort((a, b) => a['name'].toString().toLowerCase().compareTo(b['name'].toString().toLowerCase()));
    return list;
  }

  void _done(List<Map<String, dynamic>> all) {
    // Keep the existing order, then append newly picked people.
    final result = <Map<String, dynamic>>[
      for (final p in widget.current)
        if (_selected.contains(p['uid'])) p,
    ];
    for (final p in all) {
      if (_selected.contains(p['uid']) && !result.any((r) => r['uid'] == p['uid'])) {
        result.add({'uid': p['uid'], 'name': p['name'], 'avatarUrl': p['avatarUrl']});
      }
    }
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.72;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Obx(() {
        final fc = FriendController.to;
        final all = _candidates();
        final loading = fc.isLoading.value && all.isEmpty;

        if (loading) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: SkeletonList(count: 4, shrinkWrap: true),
          );
        }

        if (all.isEmpty) {
          return EmptyState(
            icon: Icons.group_add_rounded,
            title: 'No friends yet',
            message: 'Add friends first, then you can split expenses with them.',
            actionLabel: 'Add friends',
            actionIcon: Icons.person_add_alt_1_rounded,
            illustrationSize: 130,
            onAction: () {
              Navigator.of(context).pop();
              Get.toNamed(AppRoutes.addFriends);
            },
          );
        }

        final q = _query.trim().toLowerCase();
        final filtered = q.isEmpty
            ? all
            : all
                .where((p) =>
                    p['name'].toString().toLowerCase().contains(q) ||
                    p['email'].toString().toLowerCase().contains(q))
                .toList();

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: AppSearchField(
                controller: _searchCtrl,
                hint: 'Search people',
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Flexible(
              child: filtered.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No one matches "$_query"',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final p = filtered[i];
                        final uid = p['uid'].toString();
                        final checked = _selected.contains(uid);
                        return InkWell(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          onTap: () => setState(() {
                            checked ? _selected.remove(uid) : _selected.add(uid);
                          }),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            child: Row(
                              children: [
                                AppAvatar(
                                  name: p['name'].toString(),
                                  imageUrl: p['avatarUrl'].toString(),
                                  radius: 20,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p['name'].toString(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      if (p['email'].toString().isNotEmpty)
                                        Text(
                                          p['email'].toString(),
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
                                  value: checked,
                                  activeColor: AppColors.primary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  onChanged: (v) => setState(() {
                                    v == true ? _selected.add(uid) : _selected.remove(uid);
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
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppButton(
                    label: _selected.isEmpty
                        ? 'Done'
                        : 'Done · ${_selected.length} selected',
                    icon: Icons.check_rounded,
                    onPressed: () => _done(all),
                  ),
                  const SizedBox(height: 4),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      Get.toNamed(AppRoutes.addFriends);
                    },
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                    label: const Text('Add a new friend'),
                    style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                  ),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }
}

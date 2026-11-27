import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../app/routes/app_routes.dart';
import '../controllers/shell_controller.dart';
import '../controllers/trip_controller.dart';
import '../core/ui.dart';
import 'trips_screen.dart' show GroupsHub;

/// The centre "+" button: amount first, then where it goes.
///
/// Type the amount, tap a group, tap who paid and who it was for, and the
/// sheet shows each person's share live before you save. Splitting with a
/// single friend, settling up and starting a group are one tap away.
class QuickAdd {
  QuickAdd._();

  static Future<void> show() {
    HapticFeedback.lightImpact();
    return AppDialogs.sheet<void>(child: const _QuickAddSheet());
  }
}

class _QuickAddSheet extends StatefulWidget {
  const _QuickAddSheet();

  @override
  State<_QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends State<_QuickAddSheet> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String? _groupId;
  String? _payerId;
  Set<String> _sharers = {};
  bool _saving = false;

  String? get _myUid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    final trips = TripController.to.trips;
    if (trips.isNotEmpty) _pick(trips.first);
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Trip? get _group =>
      TripController.to.trips.firstWhereOrNull((t) => t.id == _groupId);

  void _pick(Trip g) {
    _groupId = g.id;
    final me = g.people.firstWhereOrNull((p) => p.uid == _myUid);
    _payerId = (me ?? g.people.first).id;
    _sharers = g.people.map((p) => p.id).toSet();
  }

  double get _value =>
      double.tryParse(_amount.text.replaceAll(',', '').trim()) ?? 0;

  Future<void> _save() async {
    final g = _group;
    if (_saving || g == null || _payerId == null) return;
    if (_value <= 0) {
      AppToast.info('Type how much was paid first.');
      return;
    }
    if (_sharers.isEmpty) {
      AppToast.info('Pick at least one person it was for.');
      return;
    }
    setState(() => _saving = true);
    try {
      final everyone = _sharers.length == g.people.length;
      await TripController.to.addPayment(
        g.id,
        personId: _payerId!,
        amount: _value,
        note: _note.text.trim(),
        splitAmong: everyone ? const [] : _sharers.toList(),
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop();
      AppToast.success(
        '${Fmt.money(_value, currencyCode: g.currencyCode)} added to ${g.title}.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.error(e is TripException ? e.message : AppToast.friendly(e));
    }
  }

  void _go(VoidCallback action) {
    Navigator.of(context).pop();
    action();
  }

  @override
  Widget build(BuildContext context) {
    final groups = TripController.to.trips.toList();
    final g = _group;
    final cur = g?.currencyCode ?? 'PKR';
    final label = TextStyle(
      fontSize: 13.5,
      fontWeight: FontWeight.w700,
      color: AppColors.textSecondary,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ---- The amount, big, first ------------------------------------
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            decoration: BoxDecoration(
              color: AppColors.hero,
              borderRadius: BorderRadius.circular(AppRadius.xl),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How much was paid?',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onHeroSoft,
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      Currencies.symbolFor(cur),
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: AppColors.onHeroSoft,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _amount,
                        autofocus: true,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        onChanged: (_) => setState(() {}),
                        cursorColor: AppColors.onHero,
                        style: TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.2,
                          color: AppColors.onHero,
                        ),
                        decoration: InputDecoration(
                          hintText: '0',
                          hintStyle: TextStyle(
                            fontSize: 42,
                            fontWeight: FontWeight.w800,
                            color: AppColors.onHeroSoft.withValues(alpha: 0.45),
                          ),
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                TextField(
                  controller: _note,
                  textCapitalization: TextCapitalization.sentences,
                  style: TextStyle(fontSize: 15, color: AppColors.onHero),
                  cursorColor: AppColors.onHero,
                  decoration: InputDecoration(
                    hintText: 'What was it for? (optional)',
                    hintStyle: TextStyle(color: AppColors.onHeroSoft),
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 6),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),

          // ---- Which group -----------------------------------------------
          const SizedBox(height: AppSpacing.xl),
          Text('Add it to', style: label),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final t in groups) ...[
                  _GroupChip(
                    group: t,
                    selected: t.id == _groupId,
                    onTap: () => setState(() => _pick(t)),
                  ),
                  const SizedBox(width: 8),
                ],
                ActionChip(
                  avatar: Icon(Icons.add_rounded, size: 18, color: AppColors.primary),
                  label: const Text('New group'),
                  onPressed: () => _go(GroupsHub.startNewGroup),
                ),
              ],
            ),
          ),

          if (g != null) ...[
            // ---- Who paid ------------------------------------------------
            const SizedBox(height: AppSpacing.lg),
            Text('Who paid?', style: label),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in g.people)
                  ChoiceChip(
                    avatar: AppAvatar(name: p.name, imageUrl: p.avatarUrl, radius: 11),
                    label: Text(p.uid == _myUid ? 'You' : Fmt.firstName(p.name)),
                    selected: p.id == _payerId,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _payerId = p.id),
                  ),
              ],
            ),

            // ---- For whom ------------------------------------------------
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(child: Text('Split between', style: label)),
                TextButton(
                  onPressed: () => setState(() {
                    _sharers = _sharers.length == g.people.length
                        ? {}
                        : g.people.map((p) => p.id).toSet();
                  }),
                  child: Text(_sharers.length == g.people.length
                      ? 'Clear'
                      : 'Everyone'),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in g.people)
                  FilterChip(
                    label: Text(p.uid == _myUid ? 'You' : Fmt.firstName(p.name)),
                    selected: _sharers.contains(p.id),
                    onSelected: (on) => setState(() {
                      on ? _sharers.add(p.id) : _sharers.remove(p.id);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _Preview(
              group: g,
              amount: _value,
              payerId: _payerId,
              sharers: _sharers,
              myUid: _myUid,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: 'Add to ${g.title}',
              icon: Icons.check_rounded,
              loading: _saving,
              onPressed: _save,
            ),
          ] else ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Start a group for a trip, your flat or a dinner, and add '
              'payments here in two taps.',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
          ],

          // ---- Other ways ------------------------------------------------
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              Expanded(
                child: _Shortcut(
                  icon: Icons.person_outline_rounded,
                  label: 'With a friend',
                  onTap: () => _go(() => AppNav.addExpense()),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Shortcut(
                  icon: Icons.handshake_outlined,
                  label: 'Settle up',
                  onTap: () => _go(() => Get.toNamed(AppRoutes.settleUp)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Live result: what each person's share is and where *you* end up.
class _Preview extends StatelessWidget {
  final Trip group;
  final double amount;
  final String? payerId;
  final Set<String> sharers;
  final String? myUid;

  const _Preview({
    required this.group,
    required this.amount,
    required this.payerId,
    required this.sharers,
    required this.myUid,
  });

  @override
  Widget build(BuildContext context) {
    final cur = group.currencyCode;
    final String text;
    Color color = AppColors.textSecondary;
    if (amount <= 0 || sharers.isEmpty || payerId == null) {
      text = 'Type an amount to see the split.';
    } else {
      final cents = TripMath.toCents(amount);
      final shares = TripMath.equalShares(cents, sharers.length);
      final each = shares.isEmpty ? 0 : shares.first;
      final me = group.people.firstWhereOrNull((p) => p.uid == myUid);
      final iPaid = me != null && me.id == payerId;
      final iShare = me != null && sharers.contains(me.id);
      final payer = group.nameOf(payerId!);
      final eachTxt = Fmt.money(each / 100, currencyCode: cur);
      if (iPaid) {
        final back = cents - (iShare ? each : 0);
        text = back > 0
            ? '$eachTxt each · you get back ${Fmt.money(back / 100, currencyCode: cur)}'
            : 'Only you — nothing to split.';
        color = back > 0 ? AppColors.positive : AppColors.textSecondary;
      } else if (iShare) {
        text = '$eachTxt each · you owe ${Fmt.firstName(payer)} $eachTxt';
        color = AppColors.negative;
      } else {
        text = '$eachTxt each · not your share';
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(Icons.calculate_outlined, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupChip extends StatelessWidget {
  final Trip group;
  final bool selected;
  final VoidCallback onTap;
  const _GroupChip({required this.group, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final type = GroupTypes.of(group.icon);
    return ChoiceChip(
      avatar: Icon(type.icon, size: 18, color: type.color),
      label: Text(group.title),
      selected: selected,
      selectedColor: type.tint,
      showCheckmark: false,
      onSelected: (_) => onTap(),
    );
  }
}

class _Shortcut extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Shortcut({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

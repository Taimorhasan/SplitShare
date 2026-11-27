import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../app/routes/app_routes.dart';
import '../controllers/profile_controller.dart';
import '../controllers/trip_controller.dart';
import '../core/ui.dart';
import 'trip_detail_screen.dart' show EditTripSheet;

/// Groups run on the give-and-take engine: everyone logs what they paid,
/// each payment is split among the people it was for, and the app works out
/// who pays whom, pair by pair. People don't need the app to be in a group.
///
/// (Stored as `trips/{id}` in Firestore — the class names say "trip" for
/// historical reasons; everything the user sees says "group".)
class GroupsHub {
  GroupsHub._();

  /// Asks for a name, type and currency, creates the group and opens it.
  static Future<void> startNewGroup() async {
    final id = await AppDialogs.sheet<String>(
      title: 'New group',
      child: const NewGroupSheet(),
    );
    if (id != null) {
      Get.toNamed(AppRoutes.tripDetail, arguments: {'id': id});
    }
  }

  static void open(Trip group) =>
      Get.toNamed(AppRoutes.tripDetail, arguments: {'id': group.id});

  static Future<void> editGroup(Trip group) => AppDialogs.sheet<void>(
        title: 'Group details',
        child: EditTripSheet(trip: group),
      );

  static Future<void> deleteGroup(Trip group) async {
    if (!TripController.to.isOwner(group)) {
      AppToast.info('Only the person who created "${group.title}" can delete it.');
      return;
    }
    final ok = await AppDialogs.confirm(
      title: 'Delete "${group.title}"?',
      message: 'All its payments will be deleted for everyone. '
          "This can't be undone.",
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    try {
      await TripController.to.deleteTrip(group.id);
      AppToast.success('Group deleted.');
    } catch (e) {
      AppToast.error(AppToast.friendly(e));
    }
  }

  /// My balance in [group] in cents: + others owe me, − I owe.
  /// Null when I'm not one of its people.
  static int? myBalanceCents(Trip group) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    final me = group.people.firstWhereOrNull((p) => p.uid == uid);
    if (me == null) return null;
    return group.summary
        .firstWhereOrNull((s) => s.person.id == me.id)
        ?.balanceCents;
  }
}

/// Stand-alone list page (route `/trips`); the Groups tab shows the same
/// [GroupList].
class TripsScreen extends StatelessWidget {
  const TripsScreen({super.key});

  /// Kept for older call-sites.
  static Future<void> startNewTrip() => GroupsHub.startNewGroup();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppTopBar(
        title: 'Groups',
        actions: [
          AppIconButton(
            icon: Icons.add_rounded,
            tooltip: 'New group',
            onPressed: GroupsHub.startNewGroup,
          ),
        ],
      ),
      body: const GroupList(),
    );
  }
}

/// Every group the user is in, newest activity first, as colour-coded cards.
/// [footer] is shown under the list (the Groups tab puts older groups there).
class GroupList extends StatefulWidget {
  final Widget? footer;
  const GroupList({super.key, this.footer});

  @override
  State<GroupList> createState() => _GroupListState();
}

class _GroupListState extends State<GroupList> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = TripController.to;
    return Obx(() {
      if (ctrl.isLoading.value && ctrl.trips.isEmpty) {
        return const SkeletonList(count: 4);
      }
      if (ctrl.hasError.value && ctrl.trips.isEmpty) {
        return ErrorState(
          title: "Couldn't load your groups",
          message: 'Check your connection and try again.',
          onRetry: ctrl.fetchTrips,
        );
      }
      final all = ctrl.trips.toList();
      if (all.isEmpty && widget.footer == null) {
        return const _EmptyGroups();
      }
      final q = _query.trim().toLowerCase();
      final shown = q.isEmpty
          ? all
          : all.where((g) => g.title.toLowerCase().contains(q)).toList();

      return RefreshIndicator(
        onRefresh: () async {
          ctrl.fetchTrips();
          await Future<void>.delayed(const Duration(milliseconds: 500));
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.page, AppSpacing.sm, AppSpacing.page, AppSpacing.xxxl * 2),
          children: [
            if (all.isEmpty)
              const _EmptyGroups(compact: true)
            else ...[
              if (all.length > 4) ...[
                AppSearchField(
                  controller: _search,
                  hint: 'Search groups',
                  onChanged: (v) => setState(() => _query = v),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              const SwipeHint(),
              for (var i = 0; i < shown.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: FadeSlideIn(
                    index: i,
                    child: SwipeActions(
                      key: ValueKey('group-${shown[i].id}'),
                      onEdit: () => GroupsHub.editGroup(shown[i]),
                      onDelete: () => GroupsHub.deleteGroup(shown[i]),
                      radius: AppRadius.lg,
                      child: GroupCard(group: shown[i]),
                    ),
                  ),
                ),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                  child: Text(
                    'No group matches "${_query.trim()}".',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
            ],
            ?widget.footer,
          ],
        ),
      );
    });
  }
}

class _EmptyGroups extends StatelessWidget {
  final bool compact;
  const _EmptyGroups({this.compact = false});

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.groups_rounded,
      illustrationSize: compact ? 120 : 170,
      title: 'Start your first group',
      message: 'A trip, the flat, a dinner — add who was there, log what each '
          'person paid, and SplitShare works out exactly who pays whom. '
          "Friends don't need the app.",
      actionLabel: 'New group',
      actionIcon: Icons.add_rounded,
      onAction: GroupsHub.startNewGroup,
    );
  }
}

/// One group: type tile, name, people, total, and where *you* stand.
class GroupCard extends StatelessWidget {
  final Trip group;
  const GroupCard({super.key, required this.group});

  @override
  Widget build(BuildContext context) {
    final type = GroupTypes.of(group.icon);
    final cur = group.currencyCode;
    final mine = GroupsHub.myBalanceCents(group) ?? 0;
    final total = Fmt.money(group.totalCents / 100, currencyCode: cur);

    final (String status, Color fg, Color bg) = group.payments.isEmpty
        ? ('No payments yet', AppColors.textSecondary, AppColors.surfaceMuted)
        : mine > 0
            ? (
                'You get back ${Fmt.money(mine / 100, currencyCode: cur)}',
                AppColors.positive,
                AppColors.positiveLight,
              )
            : mine < 0
                ? (
                    'You owe ${Fmt.money(-mine / 100, currencyCode: cur)}',
                    AppColors.negative,
                    AppColors.negativeLight,
                  )
                : group.isSettled
                    ? ('All settled', AppColors.textSecondary, AppColors.surfaceMuted)
                    : ("You're even", AppColors.textSecondary, AppColors.surfaceMuted);

    return Semantics(
      button: true,
      label: '${group.title}, ${type.name} group, '
          '${group.people.length} people, total $total, $status',
      excludeSemantics: true,
      child: AppCard(
        onTap: () => GroupsHub.open(group),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: type.tint,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(type.icon, color: type.color, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${group.people.length} '
                        '${group.people.length == 1 ? 'person' : 'people'} · '
                        '${Fmt.relative(group.updatedAt ?? group.createdAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      total,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'spent',
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                AvatarStack(
                  people: group.people
                      .map((p) => {'name': p.name, 'avatarUrl': p.avatarUrl})
                      .toList(),
                  radius: 13,
                  max: 5,
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal row of group types (Trip, Home, Food…).
class GroupTypePicker extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;
  const GroupTypePicker({super.key, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final t in GroupTypes.all)
          ChoiceChip(
            avatar: Icon(t.icon, size: 18, color: t.name == selected ? t.color : AppColors.textSecondary),
            label: Text(t.name),
            selected: t.name == selected,
            selectedColor: t.tint,
            showCheckmark: false,
            onSelected: (_) => onChanged(t.name),
          ),
      ],
    );
  }
}

class NewGroupSheet extends StatefulWidget {
  const NewGroupSheet({super.key});

  @override
  State<NewGroupSheet> createState() => _NewGroupSheetState();
}

class _NewGroupSheetState extends State<NewGroupSheet> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  late String _currency = ProfileController.to.currencyCode.value;
  String _type = 'Trip';
  bool _saving = false;

  static const _ideas = {
    'Trip': ['Murree weekend', 'Road trip', 'Hunza tour'],
    'Home': ['Flat bills', 'Hostel room', 'Groceries'],
    'Couple': ['Us two', 'Date nights'],
    'Food': ['Dinner out', 'Iftar', 'BBQ night'],
    'Bills': ['Electricity', 'Internet', 'Rent'],
    'Work': ['Office lunch', 'Team outing'],
    'Event': ['Birthday', 'Wedding gift', 'Party'],
    'Other': ['Cricket kit', 'Picnic'],
  };

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_saving || !(_form.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final id = await TripController.to.createTrip(
        title: _title.text,
        currencyCode: _currency,
        icon: _type,
      );
      if (!mounted) return;
      Navigator.of(context).pop(id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.error(
        e is TripException ? e.message : AppToast.friendly(e),
        title: "Couldn't create group",
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = TextStyle(
      fontSize: 13.5,
      fontWeight: FontWeight.w700,
      color: AppColors.textPrimary,
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('What kind of group?', style: label),
            const SizedBox(height: AppSpacing.sm),
            GroupTypePicker(
              selected: _type,
              onChanged: (t) => setState(() => _type = t),
            ),
            const SizedBox(height: AppSpacing.xl),
            AppTextField(
              controller: _title,
              label: 'Group name',
              hint: 'e.g. ${(_ideas[_type] ?? const ['Murree weekend']).first}',
              prefixIcon: GroupTypes.of(_type).icon,
              maxLength: 40,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _create(),
              validator: (v) => Validators.required(v, 'A name'),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final idea in _ideas[_type] ?? const <String>[])
                  ActionChip(
                    label: Text(idea),
                    onPressed: () => setState(() => _title.text = idea),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('Currency', style: label),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final code in Currencies.symbols.keys)
                  ChoiceChip(
                    label: Text('${Currencies.symbolFor(code)} $code'),
                    selected: code == _currency,
                    onSelected: (_) => setState(() => _currency = code),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxl),
            AppButton(
              label: 'Create group',
              icon: Icons.arrow_forward_rounded,
              loading: _saving,
              onPressed: _create,
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../app/routes/app_routes.dart';
import '../controllers/profile_controller.dart';
import '../controllers/trip_controller.dart';
import '../core/ui.dart';

/// "Trip Split": list of trips / days out. Each trip is a small calculator
/// where people log what they paid and the app works out who pays whom.
class TripsScreen extends StatelessWidget {
  const TripsScreen({super.key});

  static Future<void> startNewTrip() async {
    final id = await AppDialogs.sheet<String>(
      title: 'New trip',
      child: const _NewTripSheet(),
    );
    if (id != null) {
      Get.toNamed(AppRoutes.tripDetail, arguments: {'id': id});
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = TripController.to;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppTopBar(
        title: 'Trip Split',
        subtitle: 'Log who paid, see who owes whom',
        actions: [
          AppIconButton(
            icon: Icons.add_rounded,
            tooltip: 'New trip',
            onPressed: startNewTrip,
          ),
        ],
      ),
      body: Obx(() {
        if (ctrl.isLoading.value && ctrl.trips.isEmpty) {
          return const SkeletonList(count: 4);
        }
        if (ctrl.hasError.value && ctrl.trips.isEmpty) {
          return ErrorState(
            title: 'Couldn\'t load your trips',
            message: 'Check your connection. If this keeps happening, the '
                'latest Firestore rules may not be deployed yet.',
            onRetry: ctrl.fetchTrips,
          );
        }
        if (ctrl.trips.isEmpty) {
          return EmptyState(
            icon: Icons.luggage_rounded,
            color: AppColors.accent,
            orbitIcons: const [
              Icons.restaurant_rounded,
              Icons.local_taxi_rounded,
              Icons.hotel_rounded,
            ],
            title: 'Split a trip or a day out',
            message: 'Add everyone who came, log what each person paid, and '
                'SplitShare tells you exactly who pays whom at the end. '
                'Friends don\'t need the app.',
            actionLabel: 'Start a trip',
            actionIcon: Icons.add_rounded,
            onAction: startNewTrip,
          );
        }
        final trips = ctrl.trips.toList();
        return RefreshIndicator(
          onRefresh: () async {
            ctrl.fetchTrips();
            await Future<void>.delayed(const Duration(milliseconds: 500));
          },
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.page, AppSpacing.sm, AppSpacing.page, AppSpacing.xxxl),
            itemCount: trips.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (_, i) => FadeSlideIn(
              index: i,
              child: _TripCard(trip: trips[i]),
            ),
          ),
        );
      }),
      floatingActionButton: Obx(() => TripController.to.trips.isEmpty
          ? const SizedBox.shrink()
          : FloatingActionButton.extended(
              heroTag: 'new_trip',
              onPressed: startNewTrip,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New trip',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            )),
    );
  }
}

class _TripCard extends StatelessWidget {
  final Trip trip;
  const _TripCard({required this.trip});

  @override
  Widget build(BuildContext context) {
    final plan = trip.plan;
    final settled = trip.isSettled;
    final money = Fmt.money(trip.totalCents / 100, currencyCode: trip.currencyCode);
    return AppCard(
      onTap: () => Get.toNamed(AppRoutes.tripDetail, arguments: {'id': trip.id}),
      child: Row(
        children: [
          const IconBadge(
            icon: Icons.luggage_rounded,
            color: AppColors.accent,
            size: 50,
            iconSize: 24,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trip.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${trip.people.length} '
                  '${trip.people.length == 1 ? 'person' : 'people'} · '
                  '${Fmt.relative(trip.updatedAt ?? trip.createdAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 8),
                AvatarStack(
                  people: trip.people
                      .map((p) => {'name': p.name, 'avatarUrl': p.avatarUrl})
                      .toList(),
                  radius: 12,
                  max: 5,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                money,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              if (trip.payments.isEmpty)
                const StatusPill(label: 'NO PAYMENTS', color: AppColors.textMuted)
              else if (settled)
                const StatusPill(
                  label: 'SETTLED',
                  color: AppColors.positive,
                  icon: Icons.check_rounded,
                )
              else
                StatusPill(
                  label: '${plan.length} TO PAY',
                  color: AppColors.warning,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NewTripSheet extends StatefulWidget {
  const _NewTripSheet();

  @override
  State<_NewTripSheet> createState() => _NewTripSheetState();
}

class _NewTripSheetState extends State<_NewTripSheet> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  late String _currency = ProfileController.to.currencyCode.value;
  bool _saving = false;

  static const _ideas = ['Weekend trip', 'Dinner out', 'Road trip', 'Picnic', 'Party'];

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
      );
      if (!mounted) return;
      Navigator.of(context).pop(id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.error(
        e is TripException ? e.message : AppToast.friendly(e),
        title: 'Couldn\'t create trip',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(
              controller: _title,
              label: 'Trip name',
              hint: 'e.g. Murree weekend',
              prefixIcon: Icons.luggage_rounded,
              autofocus: true,
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
                for (final idea in _ideas)
                  ActionChip(
                    label: Text(idea),
                    onPressed: () => setState(() => _title.text = idea),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            const Text(
              'Currency',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
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
              label: 'Create trip',
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

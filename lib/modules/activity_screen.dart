import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/expense_controller.dart';
import '../controllers/shell_controller.dart';
import '../core/ui.dart';
import '../controllers/trip_controller.dart';
import 'widgets/history.dart';

enum _ActivityFilter { all, expenses, payments, youOwe, youreOwed }

extension on _ActivityFilter {
  String get label => switch (this) {
        _ActivityFilter.all => 'All',
        _ActivityFilter.expenses => 'Expenses',
        _ActivityFilter.payments => 'Payments',
        _ActivityFilter.youOwe => 'You owe',
        _ActivityFilter.youreOwed => 'You\'re owed',
      };
}

/// Full, searchable history: expenses, payments and group payments /
/// pay-backs, newest first. Expense pages load as you scroll.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  String _query = '';
  _ActivityFilter _filter = _ActivityFilter.all;

  ExpenseController get _ec => ExpenseController.to;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 400) _loadMore();
  }

  void _loadMore() {
    if (_ec.hasMoreActivity.value && !_ec.isLoadingMore.value) {
      _ec.loadMoreActivity();
    }
  }

  bool get _isFiltering =>
      _query.trim().isNotEmpty || _filter != _ActivityFilter.all;

  void _clearFilters() {
    _search.clear();
    AppNav.unfocus();
    setState(() {
      _query = '';
      _filter = _ActivityFilter.all;
    });
  }

  bool _matches(HistoryEntry e) {
    switch (_filter) {
      case _ActivityFilter.all:
        break;
      case _ActivityFilter.expenses:
        if (e.isPayment) return false;
      case _ActivityFilter.payments:
        if (!e.isPayment) return false;
      case _ActivityFilter.youOwe:
        if (e.isPayment || e.myEffect > -0.005) return false;
      case _ActivityFilter.youreOwed:
        if (e.isPayment || e.myEffect < 0.005) return false;
    }
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return e.title.toLowerCase().contains(q) ||
        e.subtitle.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppTopBar(title: 'History'),
      body: GestureDetector(
        onTap: AppNav.unfocus,
        behavior: HitTestBehavior.translucent,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                AppSpacing.xs,
                AppSpacing.page,
                AppSpacing.md,
              ),
              child: AppSearchField(
                controller: _search,
                hint: 'Search description, person, group or category',
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
              child: Row(
                children: [
                  for (final f in _ActivityFilter.values) ...[
                    _FilterChip(
                      label: f.label,
                      selected: _filter == f,
                      onTap: () => setState(() => _filter = f),
                    ),
                    if (f != _ActivityFilter.values.last)
                      const SizedBox(width: AppSpacing.sm),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                onRefresh: _ec.refreshData,
                child: Obx(_buildBody),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    _ec.recentActivity.length;
    TripController.to.trips.length;
    final all = buildHistory();
    final loading = _ec.isLoading.value;
    final error = _ec.hasError.value;
    final hasMore = _ec.hasMoreActivity.value;
    final loadingMore = _ec.isLoadingMore.value;

    final Widget child;
    if (all.isEmpty && error) {
      child = _FillScroll(
        key: const ValueKey('error'),
        child: ErrorState(onRetry: _ec.refreshData),
      );
    } else if (all.isEmpty && loading) {
      child = const SkeletonList(
        key: ValueKey('loading'),
        count: 7,
        padding: EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.sm,
          AppSpacing.page,
          AppSpacing.xxl,
        ),
      );
    } else if (all.isEmpty) {
      child = _FillScroll(
        key: const ValueKey('empty'),
        child: EmptyState(
          icon: Icons.receipt_long_rounded,
          title: 'No history yet',
          message: 'Expenses, payments and group payments you\'re part of '
              'will show up here.',
          actionLabel: 'Add expense',
          actionIcon: Icons.add_rounded,
          onAction: () => AppNav.addExpense(),
          orbitIcons: const [
            Icons.restaurant_rounded,
            Icons.flight_takeoff_rounded,
            Icons.payments_rounded,
          ],
        ),
      );
    } else {
      final rows = all.where(_matches).toList();
      if (rows.isEmpty && !hasMore) {
        child = _FillScroll(
          key: const ValueKey('no-results'),
          child: EmptyState(
            icon: Icons.search_off_rounded,
            title: 'No matches',
            message: _isFiltering
                ? 'Nothing matches your search or filter.'
                : 'Nothing to show here.',
            color: AppColors.textSecondary,
            actionLabel: _isFiltering ? 'Clear filters' : null,
            actionIcon: Icons.filter_alt_off_rounded,
            onAction: _isFiltering ? _clearFilters : null,
          ),
        );
      } else {
        // If the filtered result is too short to scroll, keep paging in
        // the background so matching older items are found.
        if (hasMore && !loadingMore) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_scroll.hasClients) return;
            final pos = _scroll.position;
            if (pos.maxScrollExtent <= 400) _loadMore();
          });
        }
        child = ListView(
          key: const ValueKey('list'),
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.sm,
            AppSpacing.page,
            AppSpacing.xxxl,
          ),
          children: [
            HistoryList(rows),
            _ListFooter(
              loadingMore: loadingMore || (hasMore && rows.isEmpty),
              hasMore: hasMore,
            ),
          ],
        );
      }
    }

    return AnimatedSwitcher(duration: AppMotion.normal, child: child);
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.onPrimary : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ListFooter extends StatelessWidget {
  final bool loadingMore;
  final bool hasMore;

  const _ListFooter({required this.loadingMore, required this.hasMore});

  @override
  Widget build(BuildContext context) {
    if (loadingMore || hasMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'You\'re all caught up',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Makes a full-height state widget pull-to-refreshable.
class _FillScroll extends StatelessWidget {
  final Widget child;
  const _FillScroll({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: child,
          ),
        ],
      ),
    );
  }
}

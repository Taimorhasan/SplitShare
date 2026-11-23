import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/expense_controller.dart';
import '../controllers/shell_controller.dart';
import '../core/ui.dart';
import 'widgets/expense_tile.dart';

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

/// Full, searchable, paginated activity feed.
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

  bool _matches(Map<String, dynamic> e) {
    final isPayment = ExpenseController.isPayment(e);
    switch (_filter) {
      case _ActivityFilter.all:
        break;
      case _ActivityFilter.expenses:
        if (isPayment) return false;
      case _ActivityFilter.payments:
        if (!isPayment) return false;
      case _ActivityFilter.youOwe:
        if (isPayment || _ec.myNetOn(e) > -0.005) return false;
      case _ActivityFilter.youreOwed:
        if (isPayment || _ec.myNetOn(e) < 0.005) return false;
    }
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final payerUid = ExpenseController.payerOf(e);
    final paidBy = e['paidBy'];
    final payerName =
        (paidBy is Map ? paidBy['name'] : null)?.toString() ?? _ec.nameFor(payerUid);
    final haystack = [
      e['description'],
      payerName,
      _ec.nameFor(payerUid),
      isPayment ? 'payment' : e['category'],
    ].whereType<Object>().map((s) => s.toString().toLowerCase());
    return haystack.any((s) => s.contains(q));
  }

  /// Flattens the filtered list into section labels + expense rows.
  List<Object> _rows(List<Map<String, dynamic>> source) {
    final rows = <Object>[];
    String? current;
    for (final e in source) {
      if (!_matches(e)) continue;
      final label = Fmt.dayGroup(e['createdAt'] ?? e['date']);
      if (label != current) {
        rows.add(label);
        current = label;
      }
      rows.add(e);
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppTopBar(title: 'Activity'),
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
                hint: 'Search description, person or category',
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
    final all = _ec.recentActivity.toList();
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
          title: 'No activity yet',
          message:
              'Expenses and payments you\'re part of will show up here.',
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
      final rows = _rows(all);
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
        child = ListView.builder(
          key: const ValueKey('list'),
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.xs,
            AppSpacing.page,
            AppSpacing.xxxl,
          ),
          itemCount: rows.length + 1,
          itemBuilder: (context, i) {
            if (i == rows.length) {
              return _ListFooter(
                loadingMore: loadingMore || (hasMore && rows.isEmpty),
                hasMore: hasMore,
              );
            }
            final row = rows[i];
            if (row is String) {
              return _SectionLabel(label: row, first: i == 0);
            }
            final e = row as Map<String, dynamic>;
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md - 2),
              child: FadeSlideIn(
                key: ValueKey(e['id']),
                index: i.clamp(0, 8),
                child: ExpenseTile(expense: e),
              ),
            );
          },
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
            boxShadow: selected ? AppShadows.glow(AppColors.primary) : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final bool first;

  const _SectionLabel({required this.label, required this.first});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: first ? AppSpacing.sm : AppSpacing.lg,
        bottom: AppSpacing.sm + 2,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          const Expanded(child: Divider(color: AppColors.border, height: 1)),
        ],
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
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_rounded, size: 18, color: AppColors.positive),
          SizedBox(width: AppSpacing.sm),
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

import 'package:flutter/material.dart';
import '../../../controllers/expense_controller.dart';
import '../../../controllers/shell_controller.dart';
import '../../../core/ui.dart';

/// The single expense / payment row used everywhere (dashboard, activity,
/// group detail, friend detail). Tapping opens the expense detail screen.
///
/// Right side shows the current user's position on that expense:
/// "you lent $5" (ink), "you borrowed $5" (red), "settled" or
/// "not involved".
///
/// Prefer `card: false` with the rows inside one [AppCard] (or straight on
/// the page) separated by dividers. `card: true` draws a single
/// hairline-ruled block for a lone row.
class ExpenseTile extends StatelessWidget {
  final Map<String, dynamic> expense;
  final VoidCallback? onTap;
  final bool showDate;
  final bool card;

  /// Row padding when [card] is false.
  final EdgeInsetsGeometry padding;

  const ExpenseTile({
    super.key,
    required this.expense,
    this.onTap,
    this.showDate = true,
    this.card = true,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.md,
    ),
  });

  @override
  Widget build(BuildContext context) {
    final ctrl = ExpenseController.to;
    final isPayment = ExpenseController.isPayment(expense);
    final style = ExpenseCategories.of(
      expense['category']?.toString(),
      isPayment: isPayment,
    );
    final currency = (expense['currencyCode'] ?? 'USD').toString();
    final amount = (expense['amount'] is num)
        ? (expense['amount'] as num).toDouble()
        : 0.0;
    final payerUid = ExpenseController.payerOf(expense);
    final me = ctrl.currentUid;
    final payerName = payerUid == me
        ? 'You'
        : ((expense['paidBy'] is Map ? expense['paidBy']['name'] : null) ??
                ctrl.nameFor(payerUid))
            .toString();

    final splits = Map<String, dynamic>.from(expense['individualSplits'] ?? {});
    final settledForMe = expense['isSettled'] == true ||
        (me != null &&
            payerUid != me &&
            ((expense['settledPairs'] as List?)
                    ?.contains(ExpenseController.pairKey(me, payerUid)) ??
                false));
    final net = ctrl.myNetOn(expense);
    final involved = me != null && (splits.containsKey(me) || payerUid == me);

    String rightCaption;
    String? rightAmount;
    Color rightColor;

    if (isPayment) {
      final receiver = splits.keys.firstWhere(
        (k) => k != payerUid,
        orElse: () => '',
      );
      rightCaption = payerUid == me
          ? 'you paid'
          : receiver == me
              ? 'you received'
              : 'payment';
      rightAmount = Fmt.money(amount, currencyCode: currency);
      rightColor = AppColors.positive;
    } else if (!involved) {
      rightCaption = 'not involved';
      rightColor = AppColors.textMuted;
    } else if (net.abs() >= 0.005) {
      rightCaption = net > 0 ? 'you lent' : 'you borrowed';
      rightAmount = Fmt.money(net.abs(), currencyCode: currency);
      rightColor = net > 0 ? AppColors.positive : AppColors.negative;
    } else if (settledForMe || expense['isSettled'] == true) {
      rightCaption = 'settled';
      rightColor = AppColors.textMuted;
    } else {
      rightCaption = 'no balance';
      rightColor = AppColors.textMuted;
    }

    final subtitle = isPayment
        ? Fmt.relative(expense['createdAt'] ?? expense['date'])
        : '$payerName paid ${Fmt.money(amount, currencyCode: currency)}'
            '${showDate ? ' · ${Fmt.shortDate(expense['date'] ?? expense['createdAt'])}' : ''}';

    final row = Row(
      children: [
        IconBadge(icon: style.icon, color: style.color, size: 40, iconSize: 20),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (expense['description'] ?? 'Expense').toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
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
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              rightCaption,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: rightColor,
              ),
            ),
            if (rightAmount != null) ...[
              const SizedBox(height: 2),
              Text(
                rightAmount,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: rightColor,
                ),
              ),
            ],
          ],
        ),
      ],
    );

    final tap = onTap ??
        () {
          final id = expense['id']?.toString();
          if (id != null) AppNav.openExpense(id);
        };

    if (!card) {
      return Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: tap,
          child: Padding(padding: padding, child: row),
        ),
      );
    }
    return AppCard(
      onTap: tap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md + 2,
      ),
      child: row,
    );
  }
}

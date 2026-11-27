import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../formatters.dart';

/// Balance direction from the current user's point of view.
enum BalanceDirection { owedToYou, youOwe, settled }

extension BalanceDirectionX on BalanceDirection {
  Color get color => switch (this) {
        BalanceDirection.owedToYou => AppColors.positive,
        BalanceDirection.youOwe => AppColors.negative,
        BalanceDirection.settled => AppColors.textMuted,
      };

  String get label => switch (this) {
        BalanceDirection.owedToYou => 'owes you',
        BalanceDirection.youOwe => 'you owe',
        BalanceDirection.settled => 'settled up',
      };

  static BalanceDirection fromNet(double net) {
    if (net > 0.005) return BalanceDirection.owedToYou;
    if (net < -0.005) return BalanceDirection.youOwe;
    return BalanceDirection.settled;
  }
}

/// Right-aligned balance label: small caption + coloured amount.
///
/// [byCurrency] is a signed net map (positive = owed to you).
class BalanceLabel extends StatelessWidget {
  final Map<String, double> byCurrency;
  final String preferredCurrency;
  final CrossAxisAlignment alignment;

  const BalanceLabel({
    super.key,
    required this.byCurrency,
    required this.preferredCurrency,
    this.alignment = CrossAxisAlignment.end,
  });

  @override
  Widget build(BuildContext context) {
    final nonZero =
        byCurrency.entries.where((e) => e.value.abs() >= 0.005).toList();
    if (nonZero.isEmpty) {
      return Column(
        crossAxisAlignment: alignment,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'settled up',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
        ],
      );
    }

    // Direction from the preferred currency if present, else the first entry.
    final primary = byCurrency[preferredCurrency] ?? nonZero.first.value;
    final dir = BalanceDirectionX.fromNet(primary);
    final mixed = nonZero.any((e) => e.value.sign != primary.sign);

    return Column(
      crossAxisAlignment: alignment,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          mixed ? 'mixed' : dir.label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: dir.color.withValues(alpha: 0.85),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          mixed
              ? Fmt.multi(byCurrency,
                  preferred: preferredCurrency, absolute: false)
              : Fmt.multi(byCurrency, preferred: preferredCurrency),
          textAlign:
              alignment == CrossAxisAlignment.end ? TextAlign.end : TextAlign.start,
          style: TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
            color: dir.color,
          ),
        ),
      ],
    );
  }
}

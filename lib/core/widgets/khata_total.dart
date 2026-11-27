import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../app_theme.dart';

/// SplitShare's balance card: the one number a screen is about, set big on a
/// soft colour block (pistachio by default, pomegranate tint when you owe,
/// quiet cream when settled). Paise are set smaller, the way you'd write
/// them on a receipt.
///
/// Pass [owed] and [owe] to show the split bar: green for what comes back,
/// pomegranate for what you owe.
class KhataTotal extends StatelessWidget {
  /// Small plain label above the amount ("Overall, you get back").
  final String label;

  /// The formatted amount ("Rs 3,652.50").
  final String amount;

  /// One or two short lines under the amount.
  final String? caption;

  /// Pass [AppColors.negative] when the total is money you owe, or
  /// [AppColors.textMuted] when it is settled. Null = the pistachio card.
  final Color? color;

  /// Optional split bar values (same currency, both >= 0).
  final double? owed;
  final double? owe;
  final String? owedLabel;
  final String? oweLabel;

  /// Optional widget at the top-right (e.g. a category icon).
  final Widget? trailing;

  final double size;
  final CrossAxisAlignment alignment;

  const KhataTotal({
    super.key,
    required this.label,
    required this.amount,
    this.caption,
    this.color,
    this.owed,
    this.owe,
    this.owedLabel,
    this.oweLabel,
    this.trailing,
    this.size = 42,
    this.alignment = CrossAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final Color soft;
    if (color == null) {
      bg = AppColors.hero;
      fg = AppColors.onHero;
      soft = AppColors.onHeroSoft;
    } else if (color == AppColors.negative) {
      bg = AppColors.negativeLight;
      fg = AppColors.negative;
      soft = AppColors.isDark ? AppColors.negative : AppColors.textSecondary;
    } else {
      bg = AppColors.surfaceMuted;
      fg = color!;
      soft = AppColors.textSecondary;
    }

    // "Rs 3,652.50" -> "Rs 3,652" + ".50"
    final m = RegExp(r'^(.*\d)(\.\d{1,2})$').firstMatch(amount);
    final whole = m?.group(1) ?? amount;
    final cents = m?.group(2);

    final hasBar = owed != null && owe != null && (owed! + owe!) > 0.004;
    final share = hasBar ? (owed! / (owed! + owe!)).clamp(0.0, 1.0) : 0.0;
    final centered = alignment == CrossAxisAlignment.center;

    return Semantics(
      label: '$label $amount${caption == null ? '' : '. $caption'}',
      container: true,
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        child: Column(
          crossAxisAlignment: alignment,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    label,
                    textAlign: centered ? TextAlign.center : TextAlign.start,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: soft,
                    ),
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: AppSpacing.md),
                  trailing!,
                ],
              ],
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: centered ? Alignment.center : Alignment.centerLeft,
              child: Text.rich(
                TextSpan(
                  text: whole,
                  children: [
                    if (cents != null)
                      TextSpan(
                        text: cents,
                        style: TextStyle(
                          fontSize: size * 0.58,
                          color: fg.withValues(alpha: 0.7),
                        ),
                      ),
                  ],
                ),
                maxLines: 1,
                style: TextStyle(
                  fontSize: size,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.2,
                  height: 1.1,
                  color: fg,
                ),
              ),
            ),
            if (hasBar) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: SizedBox(
                  height: 10,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (share > 0)
                        Expanded(
                          flex: (share * 1000).round().clamp(1, 1000),
                          child: ColoredBox(color: AppColors.positive),
                        ),
                      if (share < 1)
                        Expanded(
                          flex: ((1 - share) * 1000).round().clamp(1, 1000),
                          child: ColoredBox(color: AppColors.negative),
                        ),
                    ],
                  ),
                ),
              ),
              if (owedLabel != null || oweLabel != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        owedLabel ?? '',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.positive,
                        ),
                      ),
                    ),
                    Text(
                      oweLabel ?? '',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.negative,
                      ),
                    ),
                  ],
                ),
              ],
            ],
            if (caption != null) ...[
              const SizedBox(height: 10),
              Text(
                caption!,
                textAlign: centered ? TextAlign.center : TextAlign.start,
                style: TextStyle(
                  fontSize: 13.5,
                  color: soft,
                  height: 1.35,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

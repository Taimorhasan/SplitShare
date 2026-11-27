import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../app_theme.dart';
import 'pressable.dart';

enum AppButtonVariant { primary, secondary, outline, danger, ghost, success }

/// The one button used across the app. Flat ink, no gradients or glows.
///
/// * Shows a spinner and ignores taps while [loading] is true, which prevents
///   duplicate submissions.
/// * `onPressed: null` renders a disabled state.
class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final IconData? icon;
  final bool loading;
  final bool expand;
  final double height;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.loading = false,
    this.expand = true,
    this.height = 52,
  });

  const AppButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = true,
    this.height = 52,
  }) : variant = AppButtonVariant.secondary;

  const AppButton.outline({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = true,
    this.height = 52,
  }) : variant = AppButtonVariant.outline;

  const AppButton.danger({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = true,
    this.height = 52,
  }) : variant = AppButtonVariant.danger;

  bool get _enabled => onPressed != null && !loading;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg, BorderSide? border) = switch (variant) {
      AppButtonVariant.primary => (AppColors.primary, AppColors.onPrimary, null),
      AppButtonVariant.success => (AppColors.positive, AppColors.onPrimary, null),
      AppButtonVariant.danger => (AppColors.negativeLight, AppColors.negative, null),
      AppButtonVariant.secondary => (AppColors.primaryLight, AppColors.primary, null),
      AppButtonVariant.outline => (
          AppColors.surface,
          AppColors.textPrimary,
          BorderSide(color: AppColors.border),
        ),
      AppButtonVariant.ghost => (Colors.transparent, AppColors.primary, null),
    };

    final content = AnimatedSwitcher(
      duration: AppMotion.fast,
      child: loading
          ? SizedBox(
              key: const ValueKey('loading'),
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: fg),
            )
          : Row(
              key: const ValueKey('label'),
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: fg, size: 19),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
    );

    final button = AnimatedOpacity(
      duration: AppMotion.fast,
      opacity: onPressed == null ? 0.45 : 1,
      child: Container(
        height: height,
        width: expand ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: border != null ? Border.fromBorderSide(border) : null,
        ),
        alignment: Alignment.center,
        child: content,
      ),
    );

    return Semantics(
      button: true,
      enabled: _enabled,
      label: label,
      child: Pressable(
        onTap: _enabled ? onPressed : null,
        child: button,
      ),
    );
  }
}

/// Square icon button on a hairline-ruled surface: headers and toolbars.
class AppIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;
  final Color? background;
  final int badgeCount;
  final double size;

  const AppIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color,
    this.background,
    this.badgeCount = 0,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    final btn = Pressable(
      onTap: onPressed,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: background ?? AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: background == null ? Border.all(color: AppColors.border) : null,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Icon(icon, size: 21, color: color ?? AppColors.textPrimary),
            if (badgeCount > 0)
              Positioned(
                top: 5,
                right: 5,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: AppColors.negative,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(color: AppColors.surface, width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    badgeCount > 9 ? '9+' : '$badgeCount',
                    style: TextStyle(
                      color: AppColors.onPrimary,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

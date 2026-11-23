import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../app_theme.dart';
import 'pressable.dart';

enum AppButtonVariant { primary, secondary, outline, danger, ghost, success }

/// The one button used across the app.
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
    this.height = 54,
  });

  const AppButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = true,
    this.height = 54,
  }) : variant = AppButtonVariant.secondary;

  const AppButton.outline({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = true,
    this.height = 54,
  }) : variant = AppButtonVariant.outline;

  const AppButton.danger({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = true,
    this.height = 54,
  }) : variant = AppButtonVariant.danger;

  bool get _enabled => onPressed != null && !loading;

  @override
  Widget build(BuildContext context) {
    final Gradient? gradient;
    final Color bg;
    final Color fg;
    BorderSide? border;
    List<BoxShadow>? shadow;

    switch (variant) {
      case AppButtonVariant.primary:
        gradient = AppColors.brandGradient;
        bg = AppColors.primary;
        fg = Colors.white;
        shadow = _enabled ? AppShadows.glow(AppColors.primary) : null;
        break;
      case AppButtonVariant.success:
        gradient = AppColors.positiveGradient;
        bg = AppColors.positive;
        fg = Colors.white;
        shadow = _enabled ? AppShadows.glow(AppColors.positive) : null;
        break;
      case AppButtonVariant.danger:
        gradient = null;
        bg = AppColors.negativeLight;
        fg = AppColors.error;
        break;
      case AppButtonVariant.secondary:
        gradient = null;
        bg = AppColors.primaryLight;
        fg = AppColors.primary;
        break;
      case AppButtonVariant.outline:
        gradient = null;
        bg = AppColors.surface;
        fg = AppColors.textPrimary;
        border = const BorderSide(color: AppColors.border);
        break;
      case AppButtonVariant.ghost:
        gradient = null;
        bg = Colors.transparent;
        fg = AppColors.primary;
        break;
    }

    final content = AnimatedSwitcher(
      duration: AppMotion.fast,
      child: loading
          ? SizedBox(
              key: const ValueKey('loading'),
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: fg),
            )
          : Row(
              key: const ValueKey('label'),
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: fg, size: 20),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
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
        padding: const EdgeInsets.symmetric(horizontal: 22),
        decoration: BoxDecoration(
          gradient: gradient,
          color: gradient == null ? bg : null,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: border != null ? Border.fromBorderSide(border) : null,
          boxShadow: shadow,
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

/// Round icon button with a soft surface — used in headers and toolbars.
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
          boxShadow: background == null ? AppShadows.soft : null,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Icon(icon, size: 22, color: color ?? AppColors.textPrimary),
            if (badgeCount > 0)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: AppColors.negative,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    badgeCount > 9 ? '9+' : '$badgeCount',
                    style: const TextStyle(
                      color: Colors.white,
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

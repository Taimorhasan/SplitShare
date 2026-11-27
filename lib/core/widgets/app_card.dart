import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../app_theme.dart';
import 'pressable.dart';

/// A soft card: surface ground with a thin border, no shadow.
/// [shadow] is kept for API compatibility and now means "draw the rule".
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? color;
  final Gradient? gradient;
  final double radius;
  final bool shadow;
  final BoxBorder? border;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    this.onLongPress,
    this.color,
    this.gradient,
    this.radius = AppRadius.lg,
    this.shadow = true,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? AppColors.surface) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: border ??
            (shadow && gradient == null && color == null
                ? Border.all(color: AppColors.border)
                : null),
      ),
      child: child,
    );
    if (onTap == null && onLongPress == null) return box;
    return Pressable(
      onTap: onTap,
      onLongPress: onLongPress,
      pressedScale: 0.98,
      child: box,
    );
  }
}

/// Rounded square tinted icon — used for categories, settings rows, etc.
class IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;
  final bool filled;

  const IconBadge({
    super.key,
    required this.icon,
    required this.color,
    this.size = 44,
    this.iconSize = 22,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, color: filled ? AppColors.onPrimary : color, size: iconSize),
    );
  }
}

/// Section title with optional trailing action.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.page,
      AppSpacing.xxl,
      AppSpacing.page,
      AppSpacing.md,
    ),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
            ),
          ),
          if (actionLabel != null && onAction != null)
            Pressable(
              onTap: onAction,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      actionLabel!,
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Small pill label: `PENDING`, `SETTLED`, `ADMIN`...
class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// A tappable settings / navigation row used in lists.
class AppListTile extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;
  final bool showChevron;

  const AppListTile({
    super.key,
    required this.icon,
    required this.title,
    this.iconColor,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.destructive = false,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.error : (iconColor ?? AppColors.primary);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              IconBadge(icon: icon, color: color, size: 40, iconSize: 20),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: destructive
                            ? AppColors.error
                            : AppColors.textPrimary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              ?trailing,
              if (trailing == null && showChevron && onTap != null)
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textMuted,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

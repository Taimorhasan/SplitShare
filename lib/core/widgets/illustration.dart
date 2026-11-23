import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../app_colors.dart';

/// Vector illustration composed from shapes + icons.
///
/// Rendered entirely in code so it is crisp at any resolution, themable,
/// and adds no asset weight. Gently floats when [animate] is true.
class AppIllustration extends StatefulWidget {
  final IconData icon;
  final Color color;
  final Color? secondaryColor;
  final double size;
  final IconData? badgeIcon;
  final List<IconData> orbitIcons;
  final bool animate;

  const AppIllustration({
    super.key,
    required this.icon,
    this.color = AppColors.primary,
    this.secondaryColor,
    this.size = 180,
    this.badgeIcon,
    this.orbitIcons = const [],
    this.animate = true,
  });

  @override
  State<AppIllustration> createState() => _AppIllustrationState();
}

class _AppIllustrationState extends State<AppIllustration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _ctrl.repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final c1 = widget.color;
    final c2 = widget.secondaryColor ?? AppColors.secondary;

    return RepaintBoundary(
      child: SizedBox(
        width: s,
        height: s,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final t = _ctrl.value * 2 * math.pi;
            final float = math.sin(t) * s * 0.025;
            return Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // Outer halo
                Container(
                  width: s,
                  height: s,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        c1.withValues(alpha: 0.16),
                        c1.withValues(alpha: 0.02),
                      ],
                    ),
                  ),
                ),
                // Inner ring
                Container(
                  width: s * 0.72,
                  height: s * 0.72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c1.withValues(alpha: 0.08),
                    border: Border.all(
                      color: c1.withValues(alpha: 0.12),
                      width: 1.5,
                    ),
                  ),
                ),
                // Decorative dots
                Positioned(
                  top: s * 0.12,
                  right: s * 0.16,
                  child: _dot(s * 0.05, c2.withValues(alpha: 0.5)),
                ),
                Positioned(
                  bottom: s * 0.16,
                  left: s * 0.12,
                  child: _dot(s * 0.035, c1.withValues(alpha: 0.45)),
                ),
                Positioned(
                  top: s * 0.28,
                  left: s * 0.06,
                  child: _dot(s * 0.025, AppColors.accent.withValues(alpha: 0.6)),
                ),
                // Main tile
                Transform.translate(
                  offset: Offset(0, float),
                  child: Transform.rotate(
                    angle: -0.08,
                    child: Container(
                      width: s * 0.44,
                      height: s * 0.44,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [c1, c2],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(s * 0.13),
                        boxShadow: [
                          BoxShadow(
                            color: c1.withValues(alpha: 0.35),
                            blurRadius: s * 0.14,
                            offset: Offset(0, s * 0.06),
                          ),
                        ],
                      ),
                      child: Icon(widget.icon, color: Colors.white, size: s * 0.22),
                    ),
                  ),
                ),
                // Badge
                if (widget.badgeIcon != null)
                  Positioned(
                    right: s * 0.22,
                    bottom: s * 0.24 - float,
                    child: Container(
                      width: s * 0.17,
                      height: s * 0.17,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.10),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(widget.badgeIcon, color: c1, size: s * 0.095),
                    ),
                  ),
                // Orbiting mini icons
                for (var i = 0; i < widget.orbitIcons.length; i++)
                  _orbit(i, t, s, i.isEven ? c1 : c2),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _orbit(int i, double t, double s, Color color) {
    final count = widget.orbitIcons.length;
    final double angle;
    if (widget.badgeIcon != null) {
      // Keep clear of the badge (bottom-right, ~20°–80°): spread the orbit
      // icons over the remaining arc from 110° round to 360°.
      const start = 110 * math.pi / 180;
      const sweep = 250 * math.pi / 180;
      angle = count == 1 ? start + sweep / 2 : start + sweep * i / (count - 1);
    } else {
      angle = (2 * math.pi / count) * i - math.pi / 3;
    }
    final radius = s * 0.40;
    final bob = math.sin(t + i) * s * 0.02;
    return Transform.translate(
      offset: Offset(
        math.cos(angle) * radius,
        math.sin(angle) * radius + bob,
      ),
      child: Container(
        width: s * 0.15,
        height: s * 0.15,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(s * 0.05),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(widget.orbitIcons[i], color: color, size: s * 0.08),
      ),
    );
  }

  Widget _dot(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

/// The SplitShare brand mark (gradient wallet tile with a "split" badge).
///
/// This widget is the single source of truth for the logo: the launcher /
/// web / desktop icons are rendered from it by `tool/render_app_icon_test.dart`.
class AppLogo extends StatelessWidget {
  final double size;
  final bool withShadow;

  /// Corner radius as a fraction of [size] (0 = square, for full-bleed icons).
  final double cornerRadius;

  /// Draw only the glyph + badge on a transparent background
  /// (Android adaptive-icon foreground).
  final bool foregroundOnly;

  const AppLogo({
    super.key,
    this.size = 72,
    this.withShadow = true,
    this.cornerRadius = 0.3,
    this.foregroundOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: foregroundOnly ? null : AppColors.brandGradient,
        borderRadius: BorderRadius.circular(size * cornerRadius),
        boxShadow: withShadow && !foregroundOnly
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.4),
                  blurRadius: size * 0.35,
                  offset: Offset(0, size * 0.12),
                ),
              ]
            : null,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.account_balance_wallet_rounded,
            color: Colors.white,
            size: size * 0.5,
          ),
          Positioned(
            right: size * 0.16,
            top: size * 0.16,
            child: Container(
              width: size * 0.18,
              height: size * 0.18,
              decoration: const BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.call_split_rounded,
                  color: Colors.white, size: size * 0.12),
            ),
          ),
        ],
      ),
    );
  }
}

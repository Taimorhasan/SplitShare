import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../app_colors.dart';

/// Quiet, static spot illustration: a small card with the subject's icon,
/// one ruled line and a short accent double line.
///
/// No floating, orbiting or glowing parts. [orbitIcons] and [animate] are
/// accepted for API compatibility and ignored; [badgeIcon] shows as a small
/// mark on the card's corner.
class AppIllustration extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final Color? secondaryColor;
  final double size;
  final IconData? badgeIcon;
  final List<IconData> orbitIcons;
  final bool animate;

  const AppIllustration({
    super.key,
    required this.icon,
    this.color,
    this.secondaryColor,
    this.size = 180,
    this.badgeIcon,
    this.orbitIcons = const [],
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    final ink = color ?? AppColors.primary;
    final s = size * 0.62; // the card itself; keeps empty states compact
    return SizedBox(
      width: s,
      height: s * 0.82,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border, width: 1.2),
              ),
              padding: EdgeInsets.fromLTRB(s * 0.14, s * 0.12, s * 0.14, s * 0.1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: ink, size: s * 0.26),
                  const Spacer(),
                  Container(height: 1, color: AppColors.border),
                  SizedBox(height: s * 0.08),
                  Container(width: s * 0.42, height: 1.5, color: AppColors.rule),
                  SizedBox(height: s * 0.03),
                  Container(width: s * 0.42, height: 1.5, color: AppColors.rule),
                ],
              ),
            ),
          ),
          if (badgeIcon != null)
            Positioned(
              right: -s * 0.08,
              top: -s * 0.08,
              child: Container(
                padding: EdgeInsets.all(s * 0.05),
                decoration: BoxDecoration(
                  color: ink,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.background, width: 2),
                ),
                child: Icon(badgeIcon, color: AppColors.onPrimary, size: s * 0.12),
              ),
            ),
        ],
      ),
    );
  }
}

/// The SplitShare mark: a coin split in two — a saffron half and a pistachio
/// half pulling apart on a warm espresso tile. Drawn with a painter so it is
/// crisp at every size; also rendered into the launcher icons
/// (`tool/render_app_icon_test.dart`).
class AppLogo extends StatelessWidget {
  final double size;
  final bool withShadow;

  /// Corner radius as a fraction of [size] (0 = square, for full-bleed icons).
  final double cornerRadius;

  /// Draw only the coin on a transparent background
  /// (Android adaptive-icon foreground, splash).
  final bool foregroundOnly;

  /// Fixed brand colours, the same in light and dark, so the mark matches
  /// the launcher icon everywhere.
  static const brand = Color(0xFF1C1813); // espresso tile / splash ground
  static const badge = Color(0xFFF4A62A); // saffron half
  static const pista = Color(0xFFA9D18E); // pistachio half
  static const cream = Color(0xFFFFF8EC); // splash text
  static const ink = Color(0xFF23201A); // dark espresso (QR modules)

  const AppLogo({
    super.key,
    this.size = 72,
    this.withShadow = true,
    this.cornerRadius = 0.24,
    this.foregroundOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _SplitCoinPainter(
          background: foregroundOnly ? null : brand,
          cornerRadius: cornerRadius,
        ),
      ),
    );
  }
}

class _SplitCoinPainter extends CustomPainter {
  final Color? background;
  final double cornerRadius;
  _SplitCoinPainter({required this.background, required this.cornerRadius});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    if (background != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Offset.zero & size, Radius.circular(s * cornerRadius)),
        Paint()..color = background!,
      );
    }

    final c = Offset(size.width / 2, size.height / 2);
    final r = s * 0.30;
    // A vertical cut; the two halves slide apart sideways and one rides a
    // little higher than the other, like a coin being shared out.
    const angle = -math.pi / 2;
    final dir = Offset(math.cos(angle), math.sin(angle));
    final n = Offset(-dir.dy, dir.dx);
    final gap = s * 0.035;
    final lift = s * 0.06;

    Path half(int side) {
      final far = s * 2;
      final plane = Path()
        ..moveTo(c.dx - dir.dx * far, c.dy - dir.dy * far)
        ..lineTo(c.dx + dir.dx * far, c.dy + dir.dy * far)
        ..lineTo(c.dx + dir.dx * far + n.dx * far * side,
            c.dy + dir.dy * far + n.dy * far * side)
        ..lineTo(c.dx - dir.dx * far + n.dx * far * side,
            c.dy - dir.dy * far + n.dy * far * side)
        ..close();
      final coin = Path()..addOval(Rect.fromCircle(center: c, radius: r));
      return Path.combine(PathOperation.intersect, coin, plane)
          .shift(_offset(n, dir, gap, lift, side));
    }

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.018
      ..color = const Color(0x33000000);
    void ringOn(int side) {
      canvas.save();
      canvas.clipPath(half(side));
      canvas.drawCircle(c + _offset(n, dir, gap, lift, side), r * 0.74, ring);
      canvas.restore();
    }

    canvas.drawPath(half(-1), Paint()..color = AppLogo.badge);
    ringOn(-1);
    canvas.drawPath(half(1), Paint()..color = AppLogo.pista);
    ringOn(1);
  }

  static Offset _offset(Offset n, Offset dir, double gap, double lift, int side) =>
      n * (gap * side) + dir * (lift * -side / 2);

  @override
  bool shouldRepaint(_SplitCoinPainter old) =>
      old.background != background || old.cornerRadius != cornerRadius;
}

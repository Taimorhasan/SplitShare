import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'formatters.dart';
import 'widgets/app_image.dart';

/// User avatar: network photo with cached loading, falling back to coloured
/// initials derived from the name (stable colour per person).
class AppAvatar extends StatelessWidget {
  final String? imageUrl;
  final String name;
  final double radius;
  final Color? backgroundColor;
  final bool ring;

  const AppAvatar({
    super.key,
    this.imageUrl,
    required this.name,
    this.radius = 24,
    this.backgroundColor,
    this.ring = false,
  });

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim() ?? '';
    final color = backgroundColor ?? AppColors.forKey(name);
    final size = radius * 2;

    final initials = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: AppColors.isDark ? 0.22 : 0.12),
      ),
      child: Text(
        Fmt.initials(name),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.72,
          letterSpacing: 0.3,
        ),
      ),
    );

    final Widget avatar = AppImage.canShow(url)
        ? ClipOval(
            child: AppImage(
              url: url,
              width: size,
              height: size,
              memCacheWidth: (size * 2.5).round(),
              placeholder: initials,
              error: initials,
            ),
          )
        : initials;

    if (!ring) return SizedBox(width: size, height: size, child: avatar);

    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surface,
      ),
      child: avatar,
    );
  }
}

/// Overlapping avatars, e.g. group members.
class AvatarStack extends StatelessWidget {
  final List<Map<String, dynamic>> people;
  final double radius;
  final int max;

  const AvatarStack({
    super.key,
    required this.people,
    this.radius = 14,
    this.max = 4,
  });

  @override
  Widget build(BuildContext context) {
    final shown = people.take(max).toList();
    final extra = people.length - shown.length;
    final step = radius * 1.35;
    final count = shown.length + (extra > 0 ? 1 : 0);
    if (count == 0) return const SizedBox.shrink();
    final width = step * (count - 1) + radius * 2 + 5;

    return SizedBox(
      width: width,
      height: radius * 2 + 5,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * step,
              child: AppAvatar(
                name: (shown[i]['name'] ?? '?').toString(),
                imageUrl: shown[i]['avatarUrl']?.toString(),
                radius: radius,
                ring: true,
              ),
            ),
          if (extra > 0)
            Positioned(
              left: shown.length * step,
              child: Container(
                width: radius * 2 + 5,
                height: radius * 2 + 5,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.surface, width: 2.5),
                ),
                alignment: Alignment.center,
                child: Text(
                  '+$extra',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: radius * 0.7,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

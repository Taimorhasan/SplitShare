import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../app_theme.dart';
import 'app_button.dart';
import 'illustration.dart';

/// Friendly empty state with illustration and optional call to action.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;
  final Color color;
  final List<IconData> orbitIcons;
  final double illustrationSize;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.color = AppColors.primary,
    this.orbitIcons = const [],
    this.illustrationSize = 170,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxxl,
          vertical: AppSpacing.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIllustration(
              icon: icon,
              color: color,
              size: illustrationSize,
              orbitIcons: orbitIcons,
            ),
            const SizedBox(height: AppSpacing.xxl),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.xxl),
              AppButton(
                label: actionLabel!,
                icon: actionIcon,
                onPressed: onAction,
                expand: false,
                height: 48,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Error state with a retry button.
class ErrorState extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;

  const ErrorState({
    super.key,
    this.title = 'Couldn\'t load this',
    this.message = 'Check your connection and try again.',
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.cloud_off_rounded,
      color: AppColors.negative,
      title: title,
      message: message,
      actionLabel: onRetry == null ? null : 'Try again',
      actionIcon: Icons.refresh_rounded,
      onAction: onRetry,
    );
  }
}

/// Shimmering placeholder block.
class Skeleton extends StatefulWidget {
  final double width;
  final double height;
  final double radius;

  const Skeleton({
    super.key,
    this.width = double.infinity,
    this.height = 14,
    this.radius = 8,
  });

  const Skeleton.circle({super.key, double size = 44})
      : width = size,
        height = size,
        radius = 999;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final v = _ctrl.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1.5 + v * 3, 0),
              end: Alignment(-0.5 + v * 3, 0),
              colors: const [
                Color(0xFFEDEFF5),
                Color(0xFFF7F8FB),
                Color(0xFFEDEFF5),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A list of skeleton rows mimicking list tiles.
class SkeletonList extends StatelessWidget {
  final int count;
  final EdgeInsetsGeometry padding;
  final bool shrinkWrap;

  const SkeletonList({
    super.key,
    this.count = 6,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.page),
    this.shrinkWrap = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: padding,
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      itemCount: count,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          children: [
            const Skeleton.circle(size: 44),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Skeleton(width: 120 + (i % 3) * 30.0, height: 13),
                  const SizedBox(height: 8),
                  const Skeleton(width: 90, height: 11),
                ],
              ),
            ),
            const Skeleton(width: 56, height: 16),
          ],
        ),
      ),
    );
  }
}

/// Fades + slides a child in, staggered by [index]. Use for list items.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration delayStep;
  final Offset offset;

  const FadeSlideIn({
    super.key,
    required this.child,
    this.index = 0,
    this.delayStep = const Duration(milliseconds: 45),
    this.offset = const Offset(0, 0.06),
  });

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: AppMotion.slow,
  );
  late final Animation<double> _fade =
      CurvedAnimation(parent: _ctrl, curve: AppMotion.curve);
  late final Animation<Offset> _slide = Tween(
    begin: widget.offset,
    end: Offset.zero,
  ).animate(_fade);

  @override
  void initState() {
    super.initState();
    final capped = widget.index.clamp(0, 10);
    Future.delayed(widget.delayStep * capped, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

/// Full-screen dimmed overlay with spinner, for blocking operations.
class LoadingOverlay extends StatelessWidget {
  final bool visible;
  final String? message;
  final Widget child;

  const LoadingOverlay({
    super.key,
    required this.visible,
    required this.child,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        IgnorePointer(
          ignoring: !visible,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: AppMotion.normal,
            child: Container(
              color: Colors.black.withValues(alpha: 0.25),
              alignment: Alignment.center,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  boxShadow: AppShadows.medium,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    if (message != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        message!,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

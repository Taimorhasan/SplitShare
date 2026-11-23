import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'app_colors.dart';

/// Consistent, non-blocking user feedback (toasts).
///
/// Implemented with our own [OverlayEntry] rather than `Get.snackbar` on
/// purpose: in GetX 4.x, `Get.back()` closes an open snackbar *instead of*
/// popping the route/dialog/sheet, which silently breaks "toast then go back"
/// flows. Our overlay is invisible to GetX, so navigation always works.
class AppToast {
  AppToast._();

  static OverlayEntry? _entry;
  static GlobalKey<_ToastViewState>? _viewKey;
  static Timer? _timer;

  static void success(String message, {String title = 'Done'}) =>
      _show(title, message, AppColors.positive, Icons.check_circle_rounded);

  static void error(String message, {String title = 'Something went wrong'}) =>
      _show(title, message, AppColors.error, Icons.error_rounded);

  static void info(String message, {String title = 'Heads up'}) =>
      _show(title, message, AppColors.primary, Icons.info_rounded);

  static void warning(String message, {String title = 'Please check'}) =>
      _show(title, message, AppColors.warning, Icons.warning_amber_rounded);

  static void _remove() {
    _timer?.cancel();
    _entry?.remove();
    _entry = null;
    _viewKey = null;
  }

  static Future<void> dismiss() async {
    _timer?.cancel();
    final key = _viewKey;
    if (key?.currentState != null) await key!.currentState!.hide();
    _remove();
  }

  static void _show(String title, String message, Color color, IconData icon) {
    final overlay = Get.key.currentState?.overlay;
    if (overlay == null) {
      debugPrint('Toast ($title): $message');
      return;
    }
    _remove();
    if (color == AppColors.error) HapticFeedback.lightImpact();

    final key = GlobalKey<_ToastViewState>();
    _viewKey = key;
    _entry = OverlayEntry(
      builder: (_) => _ToastView(
        key: key,
        title: title,
        message: message,
        color: color,
        icon: icon,
        onDismissed: _remove,
      ),
    );
    overlay.insert(_entry!);
    _timer = Timer(const Duration(milliseconds: 3200), dismiss);
  }

  /// Maps raw exceptions (Firebase, network...) to a friendly sentence.
  static String friendly(Object error) {
    final text = error.toString();
    if (text.contains('permission-denied')) {
      return 'You don\'t have permission to do that.';
    }
    if (text.contains('unavailable') || text.contains('network')) {
      return 'You appear to be offline. Check your connection and try again.';
    }
    if (text.contains('deadline-exceeded') || text.contains('TimeoutException')) {
      return 'The request took too long. Please try again.';
    }
    if (text.contains('not-found')) {
      return 'That item no longer exists.';
    }
    final cleaned = text
        .replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), '')
        .replaceFirst('Exception: ', '');
    return cleaned.length > 140 ? '${cleaned.substring(0, 140)}…' : cleaned;
  }
}

class _ToastView extends StatefulWidget {
  final String title;
  final String message;
  final Color color;
  final IconData icon;
  final VoidCallback onDismissed;

  const _ToastView({
    super.key,
    required this.title,
    required this.message,
    required this.color,
    required this.icon,
    required this.onDismissed,
  });

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    reverseDuration: const Duration(milliseconds: 220),
  )..forward();

  late final Animation<double> _curve =
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);

  Future<void> hide() async {
    if (!mounted) return;
    await _ctrl.reverse();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top + 8;
    return Positioned(
      top: top,
      left: 16,
      right: 16,
      child: SafeArea(
        top: false,
        bottom: false,
        child: AnimatedBuilder(
          animation: _curve,
          builder: (_, child) => Opacity(
            opacity: _curve.value,
            child: Transform.translate(
              offset: Offset(0, -24 * (1 - _curve.value)),
              child: child,
            ),
          ),
          child: Dismissible(
            key: const ValueKey('toast'),
            direction: DismissDirection.up,
            onDismissed: (_) => widget.onDismissed(),
            child: Semantics(
              liveRegion: true,
              label: '${widget.title}. ${widget.message}',
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border(
                      left: BorderSide(color: widget.color, width: 4),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: widget.color.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(widget.icon, color: widget.color, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.title,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.message,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13.5,
                                color: AppColors.textSecondary,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../app_colors.dart';
import '../app_theme.dart';
import 'app_button.dart';
import 'app_card.dart';

/// Standard dialogs and bottom sheets.
class AppDialogs {
  AppDialogs._();

  /// Confirmation dialog. Resolves to `true` only if the user confirms.
  static Future<bool> confirm({
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool destructive = false,
    IconData? icon,
  }) async {
    final color = destructive ? AppColors.error : AppColors.primary;
    final result = await Get.dialog<bool>(
      Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconBadge(
                icon: icon ??
                    (destructive
                        ? Icons.warning_amber_rounded
                        : Icons.help_outline_rounded),
                color: color,
                size: 60,
                iconSize: 30,
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14.5,
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: AppButton.outline(
                      label: cancelLabel,
                      height: 48,
                      onPressed: () => Get.back(result: false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: destructive
                        ? _DangerFilledButton(
                            label: confirmLabel,
                            onPressed: () => Get.back(result: true),
                          )
                        : AppButton(
                            label: confirmLabel,
                            height: 48,
                            onPressed: () => Get.back(result: true),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      barrierColor: Colors.black.withValues(alpha: 0.35),
      transitionDuration: AppMotion.normal,
      transitionCurve: AppMotion.curve,
    );
    return result ?? false;
  }

  /// Shows a modal bottom sheet with an optional title.
  static Future<T?> sheet<T>({
    required Widget child,
    String? title,
    bool scrollControlled = true,
  }) {
    return Get.bottomSheet<T>(
      SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(Get.context!).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              if (title != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 6),
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                )
              else
                const SizedBox(height: 12),
              Flexible(child: child),
            ],
          ),
        ),
      ),
      backgroundColor: AppColors.surface,
      isScrollControlled: scrollControlled,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      enterBottomSheetDuration: AppMotion.normal,
      exitBottomSheetDuration: AppMotion.fast,
    );
  }

  /// Animated success celebration dialog that closes itself.
  static Future<void> success({
    required String title,
    String? message,
    Duration autoClose = const Duration(milliseconds: 1600),
  }) async {
    HapticFeedback.mediumImpact();
    var closed = false;
    Future.delayed(autoClose, () {
      if (!closed && (Get.isDialogOpen ?? false)) Get.back();
    });
    await Get.dialog(
      Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 48),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.4, end: 1),
                duration: const Duration(milliseconds: 550),
                curve: Curves.elasticOut,
                builder: (_, v, child) => Transform.scale(scale: v, child: child),
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    gradient: AppColors.positiveGradient,
                    shape: BoxShape.circle,
                    boxShadow: AppShadows.glow(AppColors.positive),
                  ),
                  child: const Icon(Icons.check_rounded,
                      color: Colors.white, size: 48),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: 6),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ],
          ),
        ),
      ),
      barrierDismissible: true,
    );
    closed = true;
  }
}

class _DangerFilledButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const _DangerFilledButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.error,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }
}

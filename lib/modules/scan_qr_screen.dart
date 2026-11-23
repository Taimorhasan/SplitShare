import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../core/ui.dart';

/// Full-screen QR scanner. Pops with the scanned user's uid (String) when a
/// SplitShare code (`splitshare://user/<uid>` or a bare uid) is detected.
class ScanQrScreen extends StatefulWidget {
  const ScanQrScreen({super.key});

  @override
  State<ScanQrScreen> createState() => _ScanQrScreenState();
}

class _ScanQrScreenState extends State<ScanQrScreen>
    with SingleTickerProviderStateMixin {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  bool _handled = false;
  DateTime? _lastInvalidToast;

  static final _uriPattern = RegExp(
    r'^splitshare://user/([A-Za-z0-9]{20,40})/?$',
    caseSensitive: false,
  );
  static final _barePattern = RegExp(r'^[A-Za-z0-9]{20,40}$');

  @override
  void dispose() {
    _anim.dispose();
    unawaited(_controller.dispose());
    super.dispose();
  }

  static String? parseCode(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null;
    final m = _uriPattern.firstMatch(value);
    if (m != null) return m.group(1);
    if (_barePattern.hasMatch(value)) return value;
    return null;
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled || !mounted) return;
    var sawSomething = false;
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw == null || raw.isEmpty) continue;
      sawSomething = true;
      final uid = parseCode(raw);
      if (uid != null) {
        _handled = true;
        HapticFeedback.mediumImpact();
        unawaited(_controller.stop());
        // Navigator.pop (not Get.back) so an open toast can't swallow the pop.
        Navigator.of(context).pop(uid);
        return;
      }
    }
    if (sawSomething) {
      final now = DateTime.now();
      if (_lastInvalidToast == null ||
          now.difference(_lastInvalidToast!) > const Duration(seconds: 3)) {
        _lastInvalidToast = now;
        HapticFeedback.lightImpact();
        AppToast.warning(
          'Ask your friend to open Add friends → My QR code.',
          title: 'That\'s not a SplitShare code',
        );
      }
    }
  }

  void _close() {
    if (_handled) return;
    _handled = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) =>
                _ScannerError(error: error, onFallback: _close),
          ),
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (context, state, _) {
              if (state.error != null) return const SizedBox.shrink();
              return Stack(
                fit: StackFit.expand,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final size = constraints.biggest;
                      final side = (size.shortestSide * 0.68).clamp(
                        200.0,
                        300.0,
                      );
                      final window = Rect.fromCenter(
                        center: Offset(size.width / 2, size.height * 0.45),
                        width: side,
                        height: side,
                      );
                      return Stack(
                        children: [
                          Positioned.fill(
                            child: AnimatedBuilder(
                              animation: _anim,
                              builder: (_, _) => CustomPaint(
                                painter: _ScanOverlayPainter(
                                  window: window,
                                  progress: _anim.value,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: AppSpacing.page,
                            right: AppSpacing.page,
                            top: window.bottom + AppSpacing.xxl,
                            child: const Column(
                              children: [
                                Text(
                                  'Scan a friend\'s code',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  'Point your camera at the QR code in their SplitShare app (Add friends → My QR code).',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13.5,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.sm,
                      ),
                      child: Row(
                        children: [
                          _GlassButton(
                            icon: Icons.close_rounded,
                            tooltip: 'Close',
                            onTap: _close,
                          ),
                          const Expanded(
                            child: Text(
                              'Scan QR code',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (state.torchState == TorchState.unavailable)
                            const SizedBox(width: 44)
                          else
                            _GlassButton(
                              icon: state.torchState == TorchState.on
                                  ? Icons.flash_on_rounded
                                  : Icons.flash_off_rounded,
                              tooltip: state.torchState == TorchState.on
                                  ? 'Turn torch off'
                                  : 'Turn torch on',
                              active: state.torchState == TorchState.on,
                              onTap: () => unawaited(_controller.toggleTorch()),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  const _GlassButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Icon(
            icon,
            color: active ? AppColors.textPrimary : Colors.white,
          ),
        ),
      ),
    );
  }
}

/// Dims everything except a rounded scan window, draws pulsing corner
/// brackets and a sweeping scan line.
class _ScanOverlayPainter extends CustomPainter {
  final Rect window;
  final double progress;

  _ScanOverlayPainter({required this.window, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    const radius = Radius.circular(AppRadius.xl);
    final hole = RRect.fromRectAndRadius(window, radius);

    final overlay = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(hole),
    );
    canvas.drawPath(
      overlay,
      Paint()..color = Colors.black.withValues(alpha: 0.62),
    );

    // Corner brackets, gently breathing outwards.
    final inset = -2 - 4 * Curves.easeInOut.transform(progress);
    final r = window.inflate(-inset);
    const len = 34.0;
    const cr = AppRadius.xl;
    final bracket = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;

    void corner(Offset a, Offset ctrl, Offset b) {
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(
          ctrl.dx + (a.dx - ctrl.dx).sign * cr * (a.dx == ctrl.dx ? 0 : 1),
          ctrl.dy + (a.dy - ctrl.dy).sign * cr * (a.dy == ctrl.dy ? 0 : 1),
        )
        ..quadraticBezierTo(
          ctrl.dx,
          ctrl.dy,
          ctrl.dx + (b.dx - ctrl.dx).sign * cr * (b.dx == ctrl.dx ? 0 : 1),
          ctrl.dy + (b.dy - ctrl.dy).sign * cr * (b.dy == ctrl.dy ? 0 : 1),
        )
        ..lineTo(b.dx, b.dy);
      canvas.drawPath(path, bracket);
    }

    final l = r.left, t = r.top, rt = r.right, b = r.bottom;
    const ext = len + cr;
    corner(Offset(l, t + ext), Offset(l, t), Offset(l + ext, t));
    corner(Offset(rt - ext, t), Offset(rt, t), Offset(rt, t + ext));
    corner(Offset(rt, b - ext), Offset(rt, b), Offset(rt - ext, b));
    corner(Offset(l + ext, b), Offset(l, b), Offset(l, b - ext));

    // Sweeping scan line.
    final y = window.top + 18 + (window.height - 36) * progress;
    final lineRect = Rect.fromLTWH(
      window.left + 18,
      y - 1.5,
      window.width - 36,
      3,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(lineRect, const Radius.circular(2)),
      Paint()
        ..shader = LinearGradient(
          colors: [
            AppColors.accent.withValues(alpha: 0),
            AppColors.accent,
            AppColors.accent.withValues(alpha: 0),
          ],
        ).createShader(lineRect),
    );
    final glowRect = Rect.fromLTWH(
      window.left + 18,
      y - 14,
      window.width - 36,
      28,
    );
    canvas.drawRect(
      glowRect,
      Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.accent.withValues(alpha: 0.22),
            AppColors.accent.withValues(alpha: 0),
          ],
        ).createShader(glowRect),
    );
  }

  @override
  bool shouldRepaint(_ScanOverlayPainter old) =>
      old.progress != progress || old.window != window;
}

class _ScannerError extends StatelessWidget {
  final MobileScannerException error;
  final VoidCallback onFallback;

  const _ScannerError({required this.error, required this.onFallback});

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    final unsupported = error.errorCode == MobileScannerErrorCode.unsupported;
    return ColoredBox(
      color: AppColors.background,
      child: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: AppIconButton(
                  icon: Icons.close_rounded,
                  tooltip: 'Close',
                  onPressed: onFallback,
                ),
              ),
            ),
            Expanded(
              child: EmptyState(
                icon: denied
                    ? Icons.no_photography_rounded
                    : Icons.videocam_off_rounded,
                color: denied ? AppColors.warning : AppColors.primary,
                title: denied
                    ? 'Camera access needed'
                    : unsupported
                    ? 'Scanning isn\'t supported here'
                    : 'Camera unavailable',
                message: denied
                    ? 'Allow camera access in your device settings to scan QR codes — or enter your friend\'s code instead.'
                    : unsupported
                    ? 'This device can\'t scan QR codes. Ask your friend for their friend code instead.'
                    : 'We couldn\'t start the camera. You can enter your friend\'s code instead.',
                actionLabel: 'Enter code instead',
                actionIcon: Icons.keyboard_rounded,
                onAction: onFallback,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

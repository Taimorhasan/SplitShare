import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/routes/app_routes.dart';
import '../core/ui.dart';
import '../firebase_options.dart';
import '../main.dart' show firebaseInitError, registerControllers;

/// Animated brand intro shown on every launch, then routes to:
/// onboarding (first run) → home (already signed in) → login.
///
/// It starts on the exact frame of the native Android launch screen (solid
/// brand indigo with the white SplitShare mark, 108dp, centred) so the
/// hand-over from the OS splash to Flutter is seamless.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _introDuration = Duration(milliseconds: 1500);

  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: _introDuration);

  // 0.00–0.45  white tile grows in behind the mark
  late final Animation<double> _tile = CurvedAnimation(
    parent: _ctrl,
    curve: const Interval(0.0, 0.45, curve: Curves.easeOutBack),
  );
  // 0.10–0.55  mark lifts upward to make room for the wordmark
  late final Animation<double> _lift = CurvedAnimation(
    parent: _ctrl,
    curve: const Interval(0.10, 0.55, curve: Curves.easeInOutCubic),
  );
  // 0.40–0.85  wordmark + tagline fade/slide in
  late final Animation<double> _text = CurvedAnimation(
    parent: _ctrl,
    curve: const Interval(0.40, 0.85, curve: Curves.easeOutCubic),
  );
  // 0.00–1.00  background warms from solid indigo into the hero gradient
  late final Animation<double> _bg = CurvedAnimation(
    parent: _ctrl,
    curve: Curves.easeInOut,
  );

  Object? _error;
  bool _retrying = false;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _error = firebaseInitError;
    _ctrl.forward();
    if (_error == null) unawaited(_continue());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Resolves the destination while the intro plays, then navigates once both
  /// are done.
  Future<void> _continue() async {
    final intro = _ctrl.isCompleted
        ? Future<void>.value()
        : _ctrl.forward().orCancel.catchError((_) {});
    final route = await _resolveRoute();
    await intro;
    // A short hold on the finished frame so the brand registers.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted || _navigated) return;
    _navigated = true;
    Get.offAllNamed(route);
  }

  Future<String> _resolveRoute() async {
    var onboarded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      onboarded = prefs.getBool('onboarding_complete') ?? false;
    } catch (e) {
      debugPrint('Splash: could not read preferences: $e');
    }
    if (!onboarded) return AppRoutes.onboarding;

    // Wait for Firebase to restore the persisted session instead of reading
    // `currentUser` immediately (it can still be null right after start-up,
    // which used to send signed-in users to the login screen).
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      try {
        user = await FirebaseAuth.instance
            .authStateChanges()
            .first
            .timeout(const Duration(seconds: 4));
      } catch (_) {
        user = FirebaseAuth.instance.currentUser;
      }
    }
    return user != null ? AppRoutes.home : AppRoutes.login;
  }

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform);
      }
      registerControllers();
      firebaseInitError = null;
      if (!mounted) return;
      setState(() {
        _error = null;
        _retrying = false;
      });
      unawaited(_continue());
    } catch (e) {
      debugPrint('Firebase retry failed: $e');
      firebaseInitError = e;
      if (!mounted) return;
      setState(() {
        _error = e;
        _retrying = false;
      });
      AppToast.error('Still unable to connect. Check your internet connection.',
          title: 'Connection problem');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: AppColors.primary,
      ),
      child: Scaffold(
        backgroundColor: AppColors.primary,
        body: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final size = MediaQuery.sizeOf(context);
            final lift = -size.height * 0.07 * _lift.value;
            return Stack(
              fit: StackFit.expand,
              children: [
                // Background: solid indigo → hero gradient.
                Opacity(
                  opacity: _bg.value,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(gradient: AppColors.heroGradient),
                  ),
                ),
                // Soft decorative glows.
                Positioned(
                  top: -size.width * 0.35,
                  right: -size.width * 0.3,
                  child: _Glow(size: size.width * 0.9, opacity: 0.10 * _bg.value),
                ),
                Positioned(
                  bottom: -size.width * 0.4,
                  left: -size.width * 0.35,
                  child: _Glow(size: size.width, opacity: 0.08 * _bg.value),
                ),
                // Mark + tile, centred exactly like the native splash.
                Center(
                  child: Transform.translate(
                    offset: Offset(0, lift),
                    child: SizedBox(
                      width: 140,
                      height: 140,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Transform.scale(
                            scale: 0.4 + 0.6 * _tile.value,
                            child: Opacity(
                              opacity: _tile.value.clamp(0.0, 1.0),
                              child: Container(
                                width: 112,
                                height: 112,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(34),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.28),
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.18),
                                      blurRadius: 30,
                                      offset: const Offset(0, 14),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Same artwork + size as the native launch drawable.
                          const AppLogo(
                            size: 108,
                            foregroundOnly: true,
                            withShadow: false,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Wordmark, tagline and loader / error.
                Align(
                  alignment: Alignment.center,
                  child: Transform.translate(
                    offset: Offset(0, lift + 120 + 24 * (1 - _text.value)),
                    child: Opacity(
                      opacity: _text.value,
                      child: Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: AppSpacing.page),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'SplitShare',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 36,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              'Split bills. Stay friends.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xxxl),
                            AnimatedSwitcher(
                              duration: AppMotion.normal,
                              child: _error == null
                                  ? const _LoadingDots(key: ValueKey('loading'))
                                  : _ErrorBlock(
                                      key: const ValueKey('error'),
                                      retrying: _retrying,
                                      onRetry: _retry,
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  final double size;
  final double opacity;
  const _Glow({required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            Colors.white.withValues(alpha: opacity),
            Colors.white.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}

/// Three gently pulsing dots.
class _LoadingDots extends StatefulWidget {
  const _LoadingDots({super.key});

  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 12,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = (_c.value - i * 0.18) % 1.0;
            final t = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.35 + 0.65 * t),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  final bool retrying;
  final VoidCallback onRetry;

  const _ErrorBlock({super.key, required this.retrying, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const IconBadge(icon: Icons.cloud_off_rounded, color: AppColors.error),
          const SizedBox(height: AppSpacing.md),
          Text("Couldn't connect", style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'SplitShare could not start its services. Check your internet '
            'connection and try again.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: 'Retry',
            icon: Icons.refresh_rounded,
            loading: retrying,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

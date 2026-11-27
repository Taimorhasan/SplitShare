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
/// brand ink with the white SplitShare mark, 108dp, centred) so the
/// hand-over from the OS splash to Flutter is seamless.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _introDuration = Duration(milliseconds: 900);

  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: _introDuration);

  // 0.00–0.50  the mark settles upward to make room for the wordmark
  late final Animation<double> _lift = CurvedAnimation(
    parent: _ctrl,
    curve: const Interval(0.0, 0.5, curve: Curves.easeInOutCubic),
  );
  // 0.40–0.90  wordmark + tagline fade in
  late final Animation<double> _text = CurvedAnimation(
    parent: _ctrl,
    curve: const Interval(0.40, 0.90, curve: Curves.easeOutCubic),
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
    await Future<void>.delayed(const Duration(milliseconds: 80));
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
    // Follows the app's Appearance setting: espresso with cream text in
    // dark, the cream page with ink text in light (matching the native
    // launch screen, which uses the same two colours).
    final dark = AppColors.isDark;
    final ground = dark ? AppLogo.brand : AppColors.background;
    final title = dark ? AppLogo.cream : AppColors.textPrimary;
    final tagline =
        dark ? AppLogo.cream.withValues(alpha: 0.82) : AppColors.textSecondary;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: ground,
        systemNavigationBarIconBrightness:
            dark ? Brightness.light : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: ground,
        body: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final size = MediaQuery.sizeOf(context);
            final lift = -size.height * 0.07 * _lift.value;
            return Stack(
              fit: StackFit.expand,
              children: [
                // Same artwork, size and position as the native launch drawable.
                Center(
                  child: Transform.translate(
                    offset: Offset(0, lift),
                    child: const AppLogo(
                      size: 108,
                      foregroundOnly: true,
                      withShadow: false,
                    ),
                  ),
                ),
                // Wordmark, tagline and loader / error.
                Align(
                  alignment: Alignment.center,
                  child: Transform.translate(
                    offset: Offset(0, lift + 110 + 8 * (1 - _text.value)),
                    child: Opacity(
                      opacity: _text.value,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.page),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'SplitShare',
                              style: TextStyle(
                                color: title,
                                fontSize: 34,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.6,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              'Split bills. Stay friends.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: tagline,
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
                color: AppLogo.badge.withValues(alpha: 0.35 + 0.65 * t),
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
          IconBadge(icon: Icons.cloud_off_rounded, color: AppColors.error),
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

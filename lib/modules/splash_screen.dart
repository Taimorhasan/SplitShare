import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/routes/app_routes.dart';
import '../core/ui.dart';
import '../firebase_options.dart';
import '../main.dart' show firebaseInitError, registerControllers;

/// Brand moment shown on launch. Decides where to go next:
/// onboarding (first run) → home (signed in) → login.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final Animation<double> _logoScale = Tween<double>(begin: 0.6, end: 1)
      .animate(CurvedAnimation(
          parent: _ctrl, curve: const Interval(0, 0.7, curve: Curves.easeOutBack)));
  late final Animation<double> _logoFade = CurvedAnimation(
      parent: _ctrl, curve: const Interval(0, 0.5, curve: Curves.easeOut));
  late final Animation<double> _textFade = CurvedAnimation(
      parent: _ctrl, curve: const Interval(0.35, 1, curve: Curves.easeOut));
  late final Animation<Offset> _textSlide =
      Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(
              parent: _ctrl,
              curve: const Interval(0.35, 1, curve: AppMotion.curve)));

  Object? _error;
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    _ctrl.forward();
    _error = firebaseInitError;
    if (_error == null) _continue();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    // Let the brand animation play briefly, while resolving the route.
    final minDelay = Future<void>.delayed(const Duration(milliseconds: 900));
    String route;
    try {
      final prefs = await SharedPreferences.getInstance();
      final onboarded = prefs.getBool('onboarding_complete') ?? false;
      if (!onboarded) {
        route = AppRoutes.onboarding;
      } else if (FirebaseAuth.instance.currentUser != null) {
        route = AppRoutes.home;
      } else {
        route = AppRoutes.login;
      }
    } catch (e) {
      debugPrint('Splash routing failed: $e');
      route = FirebaseAuth.instance.currentUser != null
          ? AppRoutes.home
          : AppRoutes.login;
    }
    await minDelay;
    if (!mounted) return;
    Get.offAllNamed(route);
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
      _continue();
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
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.primaryLight, AppColors.background],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.page),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - AppSpacing.page * 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FadeTransition(
                      opacity: _logoFade,
                      child: ScaleTransition(
                        scale: _logoScale,
                        child: const AppLogo(size: 96),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    FadeTransition(
                      opacity: _textFade,
                      child: SlideTransition(
                        position: _textSlide,
                        child: Column(
                          children: [
                            Text('SplitShare',
                                style: theme.textTheme.displaySmall),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              'Split bills. Stay friends.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyLarge
                                  ?.copyWith(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxxl),
                    AnimatedSwitcher(
                      duration: AppMotion.normal,
                      child: _error == null
                          ? const SizedBox(
                              key: ValueKey('loading'),
                              width: 26,
                              height: 26,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.6, color: AppColors.primary),
                            )
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
        children: [
          const IconBadge(icon: Icons.cloud_off_rounded, color: AppColors.error),
          const SizedBox(height: AppSpacing.md),
          Text("Couldn't connect", style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'SplitShare could not start its services. Check your internet connection and try again.',
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

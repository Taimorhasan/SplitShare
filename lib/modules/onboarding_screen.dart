import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/routes/app_routes.dart';
import '../core/ui.dart';

class _OnboardingPage {
  final IconData icon;
  final IconData badgeIcon;
  final List<IconData> orbitIcons;
  final Color color;
  final Color secondaryColor;
  final String title;
  final String body;

  const _OnboardingPage({
    required this.icon,
    required this.badgeIcon,
    required this.orbitIcons,
    required this.color,
    required this.secondaryColor,
    required this.title,
    required this.body,
  });
}

const _pages = [
  _OnboardingPage(
    icon: Icons.receipt_long_rounded,
    badgeIcon: Icons.call_split_rounded,
    orbitIcons: [
      Icons.restaurant_rounded,
      Icons.percent_rounded,
      Icons.local_taxi_rounded,
      Icons.calculate_rounded,
    ],
    color: AppColors.primary,
    secondaryColor: AppColors.secondary,
    title: 'Split any bill, any way',
    body:
        'Dinner, rent or a road trip — split equally, by percentage or by exact amounts in a few taps.',
  ),
  _OnboardingPage(
    icon: Icons.groups_rounded,
    badgeIcon: Icons.sync_alt_rounded,
    orbitIcons: [
      Icons.home_rounded,
      Icons.person_add_alt_1_rounded,
      Icons.flight_takeoff_rounded,
    ],
    color: AppColors.accent,
    secondaryColor: AppColors.primary,
    title: 'Groups & friends, always in sync',
    body:
        'Create groups for trips, homes and events. Balances update live, so everyone knows who owes what.',
  ),
  _OnboardingPage(
    icon: Icons.handshake_rounded,
    badgeIcon: Icons.check_rounded,
    orbitIcons: [
      Icons.notifications_active_rounded,
      Icons.payments_rounded,
      Icons.verified_rounded,
    ],
    color: AppColors.positive,
    secondaryColor: AppColors.accent,
    title: 'Settle up & stay notified',
    body:
        'Record payments, send friendly reminders and get notified the moment something changes.',
  ),
];

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;
  bool _finishing = false;

  bool get _isLast => _index == _pages.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarding_complete', true);
    } catch (e) {
      debugPrint('Could not save onboarding flag: $e');
    }
    if (!mounted) return;
    Get.offAllNamed(AppRoutes.login);
  }

  void _next() {
    if (_isLast) {
      _finish();
    } else {
      _controller.nextPage(duration: AppMotion.slow, curve: AppMotion.curve);
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _pages[_index];
    final size = MediaQuery.sizeOf(context);
    final illustrationSize = (size.height * 0.34).clamp(180.0, 300.0);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: AnimatedContainer(
        duration: AppMotion.slow,
        curve: AppMotion.curve,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              page.color.withValues(alpha: 0.10),
              AppColors.background,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.page, AppSpacing.sm, AppSpacing.sm, 0),
                child: Row(
                  children: [
                    const AppLogo(size: 34, withShadow: false),
                    const SizedBox(width: AppSpacing.sm),
                    Text('SplitShare',
                        style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    AnimatedOpacity(
                      duration: AppMotion.normal,
                      opacity: _isLast ? 0 : 1,
                      child: TextButton(
                        onPressed: _isLast ? null : _finish,
                        child: const Text('Skip'),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _pages.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) => _PageContent(
                    page: _pages[i],
                    illustrationSize: illustrationSize,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.page,
                    AppSpacing.md, AppSpacing.page, AppSpacing.xl),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < _pages.length; i++)
                          AnimatedContainer(
                            duration: AppMotion.normal,
                            curve: AppMotion.curve,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: i == _index ? 26 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: i == _index
                                  ? page.color
                                  : page.color.withValues(alpha: 0.25),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.pill),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    AppButton(
                      label: _isLast ? 'Get started' : 'Next',
                      icon: _isLast
                          ? Icons.rocket_launch_rounded
                          : Icons.arrow_forward_rounded,
                      onPressed: _next,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageContent extends StatelessWidget {
  final _OnboardingPage page;
  final double illustrationSize;

  const _PageContent({required this.page, required this.illustrationSize});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppIllustration(
                icon: page.icon,
                color: page.color,
                secondaryColor: page.secondaryColor,
                badgeIcon: page.badgeIcon,
                orbitIcons: page.orbitIcons,
                size: illustrationSize,
              ),
              const SizedBox(height: AppSpacing.xxxl),
              Text(
                page.title,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.md),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Text(
                  page.body,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}

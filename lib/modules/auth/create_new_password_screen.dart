import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/routes/app_routes.dart';
import '../../controllers/auth_controller.dart';
import '../../core/ui.dart';

/// "Check your inbox" screen shown after a password reset email is sent.
/// Expects `Get.arguments = {'email': String}`.
class CreateNewPasswordScreen extends StatefulWidget {
  const CreateNewPasswordScreen({super.key});

  @override
  State<CreateNewPasswordScreen> createState() =>
      _CreateNewPasswordScreenState();
}

class _CreateNewPasswordScreenState extends State<CreateNewPasswordScreen> {
  static const _cooldownSeconds = 30;

  late final String? _email = _readEmail();
  Timer? _timer;
  int _remaining = 0;
  bool _sending = false;

  static String? _readEmail() {
    final args = Get.arguments;
    if (args is Map) {
      final e = args['email'];
      if (e is String && e.trim().isNotEmpty) return e.trim();
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    // An email was just sent on the previous screen.
    if (_email != null) _startCooldown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    _remaining = _cooldownSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _remaining--);
      if (_remaining <= 0) t.cancel();
    });
  }

  Future<void> _resend() async {
    final email = _email;
    if (email == null || _sending || _remaining > 0) return;
    setState(() => _sending = true);
    final ok = await AuthController.instance.sendPasswordResetEmail(email);
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) {
      AppToast.success('We sent a new reset link to $email.',
          title: 'Email sent');
      setState(_startCooldown);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final email = _email;
    final illustration =
        (MediaQuery.sizeOf(context).height * 0.22).clamp(140.0, 200.0);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppTopBar(
        title: 'Check your inbox',
        onBack: () => Get.offAllNamed(AppRoutes.login),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.page, AppSpacing.sm, AppSpacing.page, AppSpacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: AppIllustration(
                  icon: Icons.mark_email_read_rounded,
                  badgeIcon: Icons.check_rounded,
                  size: illustration,
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              FadeSlideIn(
                child: Column(
                  children: [
                    Text('Reset link sent',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      email != null
                          ? 'We sent a password reset link to'
                          : 'If an account exists for that email, we sent it a password reset link.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (email != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        email,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 15.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              const FadeSlideIn(
                index: 1,
                child: AppCard(
                  child: Column(
                    children: [
                      _Step(
                        number: 1,
                        text: 'Open the email and tap the reset link.',
                      ),
                      Divider(height: AppSpacing.xl),
                      _Step(
                        number: 2,
                        text: 'Choose a new password on the page that opens.',
                      ),
                      Divider(height: AppSpacing.xl),
                      _Step(
                        number: 3,
                        text:
                            'Come back here and sign in with your new password.',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                "Can't find it? Check your spam or promotions folder.",
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.xxl),
              FadeSlideIn(
                index: 2,
                child: AppButton(
                  label: 'Back to sign in',
                  icon: Icons.login_rounded,
                  onPressed: () => Get.offAllNamed(AppRoutes.login),
                ),
              ),
              if (email != null) ...[
                const SizedBox(height: AppSpacing.md),
                AppButton.outline(
                  label: _remaining > 0
                      ? 'Resend email in ${_remaining}s'
                      : 'Resend email',
                  icon: Icons.refresh_rounded,
                  loading: _sending,
                  onPressed: _remaining > 0 ? null : _resend,
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              Center(
                child: TextButton(
                  onPressed: () => Get.offNamed(AppRoutes.resetPassword),
                  child: const Text('Use a different email'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int number;
  final String text;

  const _Step({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 22,
          child: Text(
            '$number.',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
          ),
        ),
      ],
    );
  }
}

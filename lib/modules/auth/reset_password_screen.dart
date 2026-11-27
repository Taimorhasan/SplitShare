import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/routes/app_routes.dart';
import '../../controllers/auth_controller.dart';
import '../../core/ui.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  AuthController get _auth => AuthController.instance;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_auth.isLoading.value) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    final email = _emailController.text.trim();
    final ok = await _auth.sendPasswordResetEmail(email);
    if (!mounted || !ok) return;
    Get.offNamed(AppRoutes.createNewPassword, arguments: {'email': email});
  }

  void _backToLogin() {
    if (Navigator.of(context).canPop()) {
      Get.back();
    } else {
      Get.offAllNamed(AppRoutes.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final illustration =
        (MediaQuery.sizeOf(context).height * 0.22).clamp(140.0, 200.0);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const AppTopBar(title: 'Reset password'),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.page, AppSpacing.sm, AppSpacing.page, AppSpacing.xxl),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: AppIllustration(
                    icon: Icons.lock_reset_rounded,
                    badgeIcon: Icons.mail_rounded,
                    size: illustration,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                FadeSlideIn(
                  child: Column(
                    children: [
                      Text(
                        'Forgot your password?',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        "No worries. Enter the email you signed up with and we'll send you a link to choose a new password.",
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                FadeSlideIn(
                  index: 1,
                  child: AppTextField(
                    controller: _emailController,
                    label: 'Email',
                    hint: 'you@example.com',
                    prefixIcon: Icons.mail_outline_rounded,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.send,
                    autofillHints: const [AutofillHints.email],
                    validator: Validators.email,
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                FadeSlideIn(
                  index: 2,
                  child: Obx(() {
                    final loading = _auth.isLoading.value;
                    return AppButton(
                      label: 'Send reset link',
                      icon: Icons.send_rounded,
                      loading: loading,
                      onPressed: _send,
                    );
                  }),
                ),
                const SizedBox(height: AppSpacing.lg),
                Center(
                  child: TextButton.icon(
                    onPressed: _backToLogin,
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    label: const Text('Back to sign in'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

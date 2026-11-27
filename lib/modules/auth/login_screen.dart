import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get/get.dart';

import '../../app/routes/app_routes.dart';
import '../../controllers/auth_controller.dart';
import '../../core/ui.dart';

/// Whether Sign in with Apple is offered on this platform.
bool get appleSignInAvailable =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS);

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();

  AuthController get _auth => AuthController.instance;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _submit() {
    if (_auth.isLoading.value) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    TextInput.finishAutofillContext();
    _auth.login(_emailController.text.trim(), _passwordController.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AuthHeader(
              icon: Icons.account_balance_wallet_rounded,
              orbitIcons: [
                Icons.receipt_long_rounded,
                Icons.groups_rounded,
                Icons.payments_rounded,
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.page,
                  AppSpacing.xxl, AppSpacing.page, AppSpacing.xxl),
              child: SafeArea(
                top: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FadeSlideIn(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Welcome back',
                              style: theme.textTheme.headlineMedium
                                  ?.copyWith(color: AppColors.textPrimary)),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'Sign in to see your balances and keep splitting.',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    FadeSlideIn(
                      index: 1,
                      child: AutofillGroup(
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              AppTextField(
                                controller: _emailController,
                                label: 'Email',
                                hint: 'you@example.com',
                                prefixIcon: Icons.mail_outline_rounded,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [
                                  AutofillHints.email,
                                  AutofillHints.username,
                                ],
                                validator: Validators.email,
                                onSubmitted: (_) =>
                                    _passwordFocus.requestFocus(),
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              AppTextField(
                                controller: _passwordController,
                                focusNode: _passwordFocus,
                                label: 'Password',
                                hint: 'Your password',
                                prefixIcon: Icons.lock_outline_rounded,
                                obscure: true,
                                textInputAction: TextInputAction.done,
                                autofillHints: const [AutofillHints.password],
                                validator: (v) => Validators.required(
                                    v, 'Password'),
                                onSubmitted: (_) => _submit(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Get.toNamed(AppRoutes.resetPassword),
                        child: const Text('Forgot password?'),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    FadeSlideIn(
                      index: 2,
                      child: Obx(() {
                        final loading = _auth.isLoading.value;
                        final social = _auth.socialLoading.value != null;
                        return AppButton(
                          label: 'Sign in',
                          icon: Icons.arrow_forward_rounded,
                          loading: loading && !social,
                          onPressed: loading ? null : _submit,
                        );
                      }),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    const AuthOrDivider(),
                    const SizedBox(height: AppSpacing.xl),
                    const FadeSlideIn(index: 3, child: SocialAuthButtons()),
                    const SizedBox(height: AppSpacing.xxl),
                    AuthFooterLink(
                      prompt: 'New to SplitShare?',
                      action: 'Create account',
                      onTap: () => Get.toNamed(AppRoutes.signup),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Quiet auth header on the page ground: optional back button, then the
/// SplitShare mark. The screen's title follows it in ink.
/// Shared by the auth screens. [icon] and [orbitIcons] are kept for API
/// compatibility and no longer drawn.
class AuthHeader extends StatelessWidget {
  final IconData icon;
  final List<IconData> orbitIcons;
  final bool showBack;

  const AuthHeader({
    super.key,
    required this.icon,
    this.orbitIcons = const [],
    this.showBack = false,
  });

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.page, AppSpacing.md, AppSpacing.page, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showBack && canPop) ...[
              AppIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                tooltip: 'Back',
                size: 40,
                onPressed: () => Get.back(),
              ),
              const SizedBox(height: AppSpacing.lg),
            ] else
              const SizedBox(height: AppSpacing.xxl),
            const AppLogo(size: 56, withShadow: false),
          ],
        ),
      ),
    );
  }
}

/// "or continue with" divider.
class AuthOrDivider extends StatelessWidget {
  const AuthOrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: AppColors.border, thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text('or continue with',
              style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(child: Divider(color: AppColors.border, thickness: 1)),
      ],
    );
  }
}

/// Google (+ Apple on iOS/macOS) sign-in buttons, bound to [AuthController].
class SocialAuthButtons extends StatelessWidget {
  const SocialAuthButtons({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthController.instance;
    return Obx(() {
      final busy = auth.isLoading.value;
      final social = auth.socialLoading.value;
      final google = _SocialButton(
        icon: FontAwesomeIcons.google,
        label: appleSignInAvailable ? 'Google' : 'Continue with Google',
        loading: social == 'google',
        onPressed: busy ? null : auth.signInWithGoogle,
      );
      if (!appleSignInAvailable) return google;
      return Row(
        children: [
          Expanded(child: google),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: _SocialButton(
              icon: FontAwesomeIcons.apple,
              label: 'Apple',
              loading: social == 'apple',
              onPressed: busy ? null : auth.signInWithApple,
            ),
          ),
        ],
      );
    });
  }
}

class _SocialButton extends StatelessWidget {
  final FaIconData icon;
  final String label;
  final bool loading;
  final VoidCallback? onPressed;

  const _SocialButton({
    required this.icon,
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Pressable(
        onTap: enabled ? onPressed : null,
        child: AnimatedOpacity(
          duration: AppMotion.fast,
          opacity: onPressed == null && !loading ? 0.5 : 1,
          child: Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.border),
            ),
            alignment: Alignment.center,
            child: AnimatedSwitcher(
              duration: AppMotion.fast,
              child: loading
                  ? SizedBox(
                      key: const ValueKey('loading'),
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: AppColors.primary),
                    )
                  : Row(
                      key: const ValueKey('label'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FaIcon(icon, size: 18, color: AppColors.textPrimary),
                        const SizedBox(width: AppSpacing.sm + 2),
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Prompt  Action" footer link row.
class AuthFooterLink extends StatelessWidget {
  final String prompt;
  final String action;
  final VoidCallback onTap;

  const AuthFooterLink({
    super.key,
    required this.prompt,
    required this.action,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(prompt, style: Theme.of(context).textTheme.bodyMedium),
        TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          ),
          child: Text(action,
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

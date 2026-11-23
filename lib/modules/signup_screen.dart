import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../app/routes/app_routes.dart';
import '../controllers/auth_controller.dart';
import '../core/ui.dart';
import 'login_screen.dart'
    show AuthFooterLink, AuthHeader, AuthOrDivider, SocialAuthButtons;

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();

  AuthController get _auth => AuthController.instance;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  void _submit() {
    if (_auth.isLoading.value) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    TextInput.finishAutofillContext();
    _auth.register(
      _nameController.text.trim(),
      _emailController.text.trim(),
      _passwordController.text,
    );
  }

  void _goToLogin() {
    if (Navigator.of(context).canPop()) {
      Get.back();
    } else {
      Get.offNamed(AppRoutes.login);
    }
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
              icon: Icons.person_add_alt_1_rounded,
              showBack: true,
              orbitIcons: [
                Icons.groups_rounded,
                Icons.call_split_rounded,
                Icons.favorite_rounded,
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
                          Text('Create your account',
                              style: theme.textTheme.headlineMedium),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'Start splitting bills with friends in under a minute.',
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
                                controller: _nameController,
                                label: 'Full name',
                                hint: 'e.g. Alex Morgan',
                                prefixIcon: Icons.person_outline_rounded,
                                keyboardType: TextInputType.name,
                                textCapitalization: TextCapitalization.words,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.name],
                                validator: Validators.name,
                                onSubmitted: (_) => _emailFocus.requestFocus(),
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              AppTextField(
                                controller: _emailController,
                                focusNode: _emailFocus,
                                label: 'Email',
                                hint: 'you@example.com',
                                prefixIcon: Icons.mail_outline_rounded,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.email],
                                validator: Validators.email,
                                onSubmitted: (_) =>
                                    _passwordFocus.requestFocus(),
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              AppTextField(
                                controller: _passwordController,
                                focusNode: _passwordFocus,
                                label: 'Password',
                                hint: 'At least 8 characters',
                                prefixIcon: Icons.lock_outline_rounded,
                                obscure: true,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [
                                  AutofillHints.newPassword
                                ],
                                validator: Validators.password,
                                onSubmitted: (_) =>
                                    _confirmFocus.requestFocus(),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              ValueListenableBuilder<TextEditingValue>(
                                valueListenable: _passwordController,
                                builder: (_, value, _) =>
                                    _StrengthMeter(password: value.text),
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              AppTextField(
                                controller: _confirmController,
                                focusNode: _confirmFocus,
                                label: 'Confirm password',
                                hint: 'Re-enter your password',
                                prefixIcon: Icons.lock_reset_rounded,
                                obscure: true,
                                textInputAction: TextInputAction.done,
                                autofillHints: const [
                                  AutofillHints.newPassword
                                ],
                                validator: (v) {
                                  if (v == null || v.isEmpty) {
                                    return 'Please confirm your password';
                                  }
                                  if (v != _passwordController.text) {
                                    return 'Passwords do not match';
                                  }
                                  return null;
                                },
                                onSubmitted: (_) => _submit(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    FadeSlideIn(
                      index: 2,
                      child: Obx(() {
                        final loading = _auth.isLoading.value;
                        final social = _auth.socialLoading.value != null;
                        return AppButton(
                          label: 'Create account',
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
                      prompt: 'Already have an account?',
                      action: 'Sign in',
                      onTap: _goToLogin,
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

/// Live weak / fair / strong indicator for the password field.
class _StrengthMeter extends StatelessWidget {
  final String password;

  const _StrengthMeter({required this.password});

  /// 0 = empty, 1 = weak, 2 = fair, 3 = strong.
  static int _score(String p) {
    if (p.isEmpty) return 0;
    var points = 0;
    if (p.length >= 8) points++;
    if (p.length >= 12) points++;
    if (RegExp(r'[a-z]').hasMatch(p) && RegExp(r'[A-Z]').hasMatch(p)) {
      points++;
    }
    if (RegExp(r'\d').hasMatch(p)) points++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(p)) points++;
    if (p.length < 8 || points <= 2) return 1;
    if (points <= 3) return 2;
    return 3;
  }

  @override
  Widget build(BuildContext context) {
    final score = _score(password);
    final (label, color) = switch (score) {
      1 => ('Weak', AppColors.negative),
      2 => ('Fair', AppColors.warning),
      3 => ('Strong', AppColors.positive),
      _ => ('', AppColors.border),
    };

    return AnimatedSize(
      duration: AppMotion.normal,
      curve: AppMotion.curve,
      alignment: Alignment.topCenter,
      child: score == 0
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Row(
                children: [
                  for (var i = 1; i <= 3; i++) ...[
                    Expanded(
                      child: AnimatedContainer(
                        duration: AppMotion.normal,
                        height: 5,
                        decoration: BoxDecoration(
                          color: i <= score ? color : AppColors.border,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs + 2),
                  ],
                  SizedBox(
                    width: 56,
                    child: Text(
                      label,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        color: color,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

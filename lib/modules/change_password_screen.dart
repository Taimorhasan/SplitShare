import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../app/routes/app_routes.dart';
import '../controllers/auth_controller.dart';
import '../controllers/shell_controller.dart';
import '../core/ui.dart';

/// Re-authenticates with the current password and sets a new one.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _newFocus = FocusNode();
  final _confirmFocus = FocusNode();

  AuthController get _auth => AuthController.instance;

  @override
  void initState() {
    super.initState();
    _newCtrl.addListener(_rebuild);
  }

  @override
  void dispose() {
    _newCtrl.removeListener(_rebuild);
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    _newFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  String get _providerName {
    final ids =
        FirebaseAuth.instance.currentUser?.providerData
            .map((p) => p.providerId)
            .toList() ??
        const <String>[];
    if (ids.contains('google.com')) return 'Google';
    if (ids.contains('apple.com')) return 'Apple';
    return 'your sign-in provider';
  }

  String? _validateNew(String? v) {
    final base = Validators.password(v);
    if (base != null) return base;
    if (v == _currentCtrl.text) {
      return 'Choose a password different from your current one';
    }
    return null;
  }

  String? _validateConfirm(String? v) {
    if (v == null || v.isEmpty) return 'Please confirm your new password';
    if (v != _newCtrl.text) return 'Passwords don\'t match';
    return null;
  }

  Future<void> _submit() async {
    if (_auth.isLoading.value) return;
    AppNav.unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    try {
      await _auth.changePassword(
        currentPassword: _currentCtrl.text,
        newPassword: _newCtrl.text,
      );
      if (!mounted) return;
      await AppDialogs.success(
        title: 'Password updated',
        message: 'Use your new password next time you sign in.',
      );
      if (!mounted) return;
      // Navigator.pop rather than Get.back(), which would only close a toast.
      Navigator.of(context).pop();
    } on Exception catch (e) {
      AppToast.error(
        e.toString().replaceFirst('Exception: ', ''),
        title: 'Couldn\'t change password',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppTopBar(title: 'Change password'),
      body: _auth.hasPasswordProvider ? _buildForm() : _buildUnavailable(),
    );
  }

  Widget _buildUnavailable() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.page),
        child: EmptyState(
          icon: Icons.verified_user_rounded,
          title: 'Managed by $_providerName',
          message:
              'You signed in with $_providerName, so there\'s no SplitShare '
              'password to change. Manage your password and security in your '
              '$_providerName account.',
          actionLabel: 'Go back',
          actionIcon: Icons.arrow_back_rounded,
          onAction: () => Navigator.of(context).maybePop(),
        ),
      ),
    );
  }

  Widget _buildForm() {
    final pw = _newCtrl.text;
    final checks = <(String, bool)>[
      ('At least 8 characters', pw.length >= 8),
      ('Contains a letter', RegExp(r'[A-Za-z]').hasMatch(pw)),
      ('Contains a number', RegExp(r'\d').hasMatch(pw)),
    ];

    return GestureDetector(
      onTap: AppNav.unfocus,
      behavior: HitTestBehavior.translucent,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          0,
          AppSpacing.page,
          AppSpacing.xxxl,
        ),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const FadeSlideIn(
                child: Center(
                  child: AppIllustration(
                    icon: Icons.lock_rounded,
                    badgeIcon: Icons.key_rounded,
                    size: 140,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              FadeSlideIn(
                index: 1,
                child: Text(
                  'Keep your account secure',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              FadeSlideIn(
                index: 1,
                child: Text(
                  'Enter your current password, then choose a new one.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              FadeSlideIn(
                index: 2,
                child: AppCard(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppTextField(
                          controller: _currentCtrl,
                          label: 'Current password',
                          hint: 'Enter your current password',
                          prefixIcon: Icons.lock_outline_rounded,
                          obscure: true,
                          validator: (v) => (v == null || v.isEmpty)
                              ? 'Enter your current password'
                              : null,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.password],
                          onSubmitted: (_) => _newFocus.requestFocus(),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () =>
                                Get.toNamed(AppRoutes.resetPassword),
                            child: const Text('Forgot your current password?'),
                          ),
                        ),
                        AppTextField(
                          controller: _newCtrl,
                          focusNode: _newFocus,
                          label: 'New password',
                          hint: 'Create a new password',
                          prefixIcon: Icons.key_outlined,
                          obscure: true,
                          validator: _validateNew,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.newPassword],
                          onSubmitted: (_) => _confirmFocus.requestFocus(),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _StrengthMeter(password: pw),
                        const SizedBox(height: AppSpacing.md),
                        for (final c in checks) _Requirement(c.$1, met: c.$2),
                        const SizedBox(height: AppSpacing.lg),
                        AppTextField(
                          controller: _confirmCtrl,
                          focusNode: _confirmFocus,
                          label: 'Confirm new password',
                          hint: 'Re-enter your new password',
                          prefixIcon: Icons.check_circle_outline_rounded,
                          obscure: true,
                          validator: _validateConfirm,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.newPassword],
                          onSubmitted: (_) => _submit(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              FadeSlideIn(
                index: 3,
                child: Obx(
                  () => AppButton(
                    label: 'Update password',
                    icon: Icons.lock_reset_rounded,
                    loading: _auth.isLoading.value,
                    onPressed: _submit,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Four-segment strength bar with a label.
class _StrengthMeter extends StatelessWidget {
  final String password;
  const _StrengthMeter({required this.password});

  int get _score {
    if (password.isEmpty) return 0;
    var s = 0;
    if (password.length >= 8) s++;
    if (password.length >= 12) s++;
    if (RegExp(r'[A-Za-z]').hasMatch(password) &&
        RegExp(r'\d').hasMatch(password)) {
      s++;
    }
    if (RegExp(r'[A-Z]').hasMatch(password) &&
        RegExp(r'[a-z]').hasMatch(password)) {
      s++;
    }
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(password)) s++;
    return s.clamp(1, 4);
  }

  @override
  Widget build(BuildContext context) {
    final score = _score;
    final (label, color) = switch (score) {
      0 => ('Enter a password', AppColors.textMuted),
      1 => ('Weak', AppColors.negative),
      2 => ('Fair', AppColors.warning),
      3 => ('Good', AppColors.info),
      _ => ('Strong', AppColors.positive),
    };
    return Row(
      children: [
        for (var i = 0; i < 4; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: AnimatedContainer(
              duration: AppMotion.normal,
              curve: AppMotion.curve,
              height: 6,
              decoration: BoxDecoration(
                color: i < score ? color : AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
          ),
        ],
        const SizedBox(width: AppSpacing.md),
        SizedBox(
          width: 96,
          child: AnimatedSwitcher(
            duration: AppMotion.fast,
            child: Text(
              label,
              key: ValueKey(label),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Requirement extends StatelessWidget {
  final String label;
  final bool met;
  const _Requirement(this.label, {required this.met});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          AnimatedContainer(
            duration: AppMotion.normal,
            curve: AppMotion.curve,
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: met ? AppColors.positive : AppColors.surfaceMuted,
              shape: BoxShape.circle,
            ),
            child: AnimatedScale(
              duration: AppMotion.normal,
              curve: Curves.easeOutBack,
              scale: met ? 1 : 0,
              child: Icon(
                Icons.check_rounded,
                size: 14,
                color: AppColors.onPrimary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: AnimatedDefaultTextStyle(
              duration: AppMotion.normal,
              style: TextStyle(
                fontSize: 13,
                fontWeight: met ? FontWeight.w600 : FontWeight.w500,
                color: met ? AppColors.textPrimary : AppColors.textSecondary,
              ),
              child: Text(label),
            ),
          ),
        ],
      ),
    );
  }
}

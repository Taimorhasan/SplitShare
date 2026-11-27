import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_colors.dart';
import '../app_theme.dart';

/// Labelled text input used for every form in the app.
///
/// Set [obscure] for passwords — a visibility toggle is added automatically.
class AppTextField extends StatefulWidget {
  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final IconData? prefixIcon;
  final Widget? suffix;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final bool readOnly;
  final int maxLines;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;
  final FocusNode? focusNode;
  final TextCapitalization textCapitalization;
  final String? helperText;
  final VoidCallback? onTap;
  final bool autofocus;

  const AppTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.prefixIcon,
    this.suffix,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.readOnly = false,
    this.maxLines = 1,
    this.maxLength,
    this.inputFormatters,
    this.autofillHints,
    this.focusNode,
    this.textCapitalization = TextCapitalization.none,
    this.helperText,
    this.onTap,
    this.autofocus = false,
  });

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late bool _hidden = widget.obscure;

  @override
  Widget build(BuildContext context) {
    Widget? suffix = widget.suffix;
    if (widget.obscure) {
      suffix = IconButton(
        tooltip: _hidden ? 'Show password' : 'Hide password',
        icon: Icon(
          _hidden ? Icons.visibility_off_rounded : Icons.visibility_rounded,
          size: 20,
        ),
        onPressed: () => setState(() => _hidden = !_hidden),
      );
    }

    final field = TextFormField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      obscureText: _hidden,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      validator: widget.validator,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onSubmitted,
      enabled: widget.enabled,
      readOnly: widget.readOnly,
      maxLines: widget.obscure ? 1 : widget.maxLines,
      maxLength: widget.maxLength,
      inputFormatters: widget.inputFormatters,
      autofillHints: widget.autofillHints,
      textCapitalization: widget.textCapitalization,
      onTap: widget.onTap,
      autofocus: widget.autofocus,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      style: TextStyle(
        fontSize: 15.5,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      ),
      decoration: InputDecoration(
        hintText: widget.hint,
        helperText: widget.helperText,
        helperMaxLines: 2,
        prefixIcon: widget.prefixIcon == null
            ? null
            : Icon(widget.prefixIcon, size: 20),
        suffixIcon: suffix,
        fillColor: widget.enabled && !widget.readOnly
            ? AppColors.surface
            : AppColors.surfaceMuted,
      ),
    );

    if (widget.label == null) return field;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: AppSpacing.sm),
          child: Text(
            widget.label!,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        field,
      ],
    );
  }
}

/// Pill-shaped search field.
class AppSearchField extends StatelessWidget {
  final TextEditingController? controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;

  const AppSearchField({
    super.key,
    this.controller,
    this.hint = 'Search',
    this.onChanged,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search_rounded, size: 22),
          suffixIcon: controller == null
              ? null
              : ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller!,
                  builder: (_, value, _) => value.text.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(
                          tooltip: 'Clear',
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () {
                            controller!.clear();
                            onChanged?.call('');
                            onClear?.call();
                          },
                        ),
                ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: BorderSide(color: AppColors.primary, width: 1.4),
          ),
          fillColor: Colors.transparent,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}

/// Common validators.
class Validators {
  Validators._();

  static String? required(String? v, [String field = 'This field']) =>
      (v == null || v.trim().isEmpty) ? '$field is required' : null;

  static String? email(String? v) {
    if (v == null || v.trim().isEmpty) return 'Email is required';
    final ok = RegExp(r'^[\w.+-]+@[\w-]+(\.[\w-]+)+$').hasMatch(v.trim());
    return ok ? null : 'Enter a valid email address';
  }

  static String? password(String? v) {
    if (v == null || v.isEmpty) return 'Password is required';
    if (v.length < 8) return 'Use at least 8 characters';
    if (!RegExp(r'[A-Za-z]').hasMatch(v) || !RegExp(r'\d').hasMatch(v)) {
      return 'Include at least one letter and one number';
    }
    return null;
  }

  static String? name(String? v) {
    if (v == null || v.trim().isEmpty) return 'Name is required';
    if (v.trim().length < 2) return 'Name is too short';
    return null;
  }

  static String? phone(String? v) {
    if (v == null || v.trim().isEmpty) return null; // optional
    final digits = v.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length < 7 || digits.length > 15) {
      return 'Enter a valid phone number';
    }
    return null;
  }

  static String? amount(String? v) {
    final value = double.tryParse((v ?? '').trim());
    if (value == null) return 'Enter an amount';
    if (value <= 0) return 'Amount must be greater than 0';
    if (value > 10000000) return 'Amount is too large';
    return null;
  }
}

/// Allows only positive decimals with up to 2 decimal places.
final amountInputFormatter =
    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'));

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_colors.dart';

/// Spacing scale (multiples of 4).
class AppSpacing {
  AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  /// Standard horizontal page padding.
  static const double page = 20;
}

/// Corner radii: soft and round, like the cards in the Chai & Pista design.
class AppRadius {
  AppRadius._();
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 26;
  static const double pill = 999;
}

/// No drop shadows on cards: separation comes from fill and a soft border.
/// Kept as an API so existing call-sites compile; [sheet] is the one real
/// elevation (bottom sheets / dialogs floating over the page).
class AppShadows {
  AppShadows._();

  static List<BoxShadow> get soft => const [];
  static List<BoxShadow> get medium => const [];
  static List<BoxShadow> glow(Color color) => const [];

  static List<BoxShadow> get sheet => [
        BoxShadow(
          color: Colors.black.withValues(alpha: AppColors.isDark ? 0.5 : 0.12),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];
}

/// Shared animation durations / curves.
class AppMotion {
  AppMotion._();
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 220);
  static const slow = Duration(milliseconds: 320);
  static const curve = Curves.easeOutCubic;
}

class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(false);
  static ThemeData get dark => _build(true);

  /// Builds the theme for one brightness from the same tokens.
  static ThemeData _build(bool dark) {
    final previous = AppColors.isDark;
    AppColors.setDark(dark);
    try {
      return _theme(dark);
    } finally {
      AppColors.setDark(previous);
    }
  }

  static ThemeData _theme(bool dark) {
    final brightness = dark ? Brightness.dark : Brightness.light;
    const tabular = [FontFeature.tabularFigures()];
    const fontFamily = 'Figtree';

    final scheme = ColorScheme(
      brightness: brightness,
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      primaryContainer: AppColors.primaryLight,
      onPrimaryContainer: AppColors.primary,
      secondary: AppColors.primary,
      onSecondary: AppColors.onPrimary,
      secondaryContainer: AppColors.primaryLight,
      onSecondaryContainer: AppColors.primary,
      tertiary: AppColors.positive,
      onTertiary: AppColors.onPrimary,
      error: AppColors.error,
      onError: AppColors.onPrimary,
      errorContainer: AppColors.negativeLight,
      onErrorContainer: AppColors.negative,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      surfaceContainerLowest: AppColors.background,
      surfaceContainerLow: AppColors.surface,
      surfaceContainer: AppColors.surfaceMuted,
      surfaceContainerHigh: AppColors.surfaceMuted,
      surfaceContainerHighest: AppColors.surfaceMuted,
      outline: AppColors.border,
      outlineVariant: AppColors.border,
      shadow: Colors.black,
      inverseSurface: AppColors.textPrimary,
      onInverseSurface: AppColors.surface,
    );

    TextStyle t(double size, FontWeight w, Color c, {double? height, double ls = 0}) =>
        TextStyle(
          fontSize: size,
          fontWeight: w,
          color: c,
          height: height,
          letterSpacing: ls,
          fontFamily: fontFamily,
          fontFeatures: tabular,
        );

    final textTheme = TextTheme(
      displaySmall: t(36, FontWeight.w800, AppColors.textPrimary, ls: -1.0),
      headlineMedium: t(26, FontWeight.w800, AppColors.textPrimary, ls: -0.5),
      headlineSmall: t(22, FontWeight.w800, AppColors.textPrimary, ls: -0.3),
      titleLarge: t(19, FontWeight.w800, AppColors.textPrimary, ls: -0.2),
      titleMedium: t(16, FontWeight.w600, AppColors.textPrimary),
      titleSmall: t(14, FontWeight.w600, AppColors.textPrimary),
      bodyLarge: t(16, FontWeight.w400, AppColors.textPrimary, height: 1.45),
      bodyMedium: t(14, FontWeight.w400, AppColors.textSecondary, height: 1.45),
      bodySmall: t(12.5, FontWeight.w400, AppColors.textSecondary),
      labelLarge: t(15, FontWeight.w600, AppColors.textPrimary),
      labelMedium: t(12.5, FontWeight.w600, AppColors.textSecondary),
      labelSmall: t(11.5, FontWeight.w600, AppColors.textMuted),
    );

    final field = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: BorderSide(color: AppColors.border),
    );

    final overlay = (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
        .copyWith(statusBarColor: Colors.transparent);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: fontFamily,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      textTheme: textTheme,
      splashFactory: InkRipple.splashFactory,
      dividerColor: AppColors.border,
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.primary,
        selectionColor: AppColors.primary.withValues(alpha: 0.25),
        selectionHandleColor: AppColors.primary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: AppColors.textPrimary,
        systemOverlayStyle: overlay,
        titleTextStyle: t(19, FontWeight.w800, AppColors.textPrimary, ls: -0.2),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: AppColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 15),
        labelStyle: TextStyle(color: AppColors.textSecondary),
        prefixIconColor: AppColors.textMuted,
        suffixIconColor: AppColors.textMuted,
        border: field,
        enabledBorder: field,
        focusedBorder: field.copyWith(
          borderSide: BorderSide(color: AppColors.primary, width: 1.6),
        ),
        errorBorder: field.copyWith(borderSide: BorderSide(color: AppColors.error)),
        focusedErrorBorder: field.copyWith(
          borderSide: BorderSide(color: AppColors.error, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          elevation: 0,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.primaryLight,
        side: BorderSide(color: AppColors.border),
        labelStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        checkmarkColor: AppColors.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.primary : null,
        ),
        checkColor: WidgetStatePropertyAll(AppColors.onPrimary),
        side: BorderSide(color: AppColors.textMuted, width: 1.5),
      ),
      dividerTheme: DividerThemeData(color: AppColors.border, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        iconColor: AppColors.textSecondary,
        textColor: AppColors.textPrimary,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: false, // AppDialogs.sheet draws its own handle
        dragHandleColor: AppColors.border,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(color: AppColors.textPrimary),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.onPrimary
              : AppColors.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.surfaceMuted,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.transparent : AppColors.border,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: AppColors.primary),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.textPrimary,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: AppColors.primary,
        dividerColor: AppColors.border,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}

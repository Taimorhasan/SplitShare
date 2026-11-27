import 'package:flutter/material.dart';

/// One palette per theme. Light = a cream page with pistachio and saffron;
/// dark = the same colours on roasted-chai brown.
class _Palette {
  final Color page; // scaffold ground
  final Color surface; // cards, sheets
  final Color surfaceMuted; // fields, chips, quiet fills
  final Color rule; // borders / dividers
  final Color text; // primary text
  final Color primary; // pistachio green: actions, links, selection
  final Color primarySoft; // pistachio tint behind primary elements
  final Color onPrimary; // text/icons on a primary fill
  final Color textSecondary;
  final Color textMuted;
  final Color credit; // "owes you"
  final Color creditSoft;
  final Color debit; // "you owe"
  final Color debitSoft;
  final Color warning;
  final Color warningSoft;
  final Color saffron; // the add button, the one warm accent
  final Color hero; // the balance card
  final Color onHero;
  final Color onHeroSoft;
  final Color nav; // floating nav pill
  final Color navIdle;
  final List<Color> pens; // per-person identity colours

  const _Palette({
    required this.page,
    required this.surface,
    required this.surfaceMuted,
    required this.rule,
    required this.text,
    required this.primary,
    required this.primarySoft,
    required this.onPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.credit,
    required this.creditSoft,
    required this.debit,
    required this.debitSoft,
    required this.warning,
    required this.warningSoft,
    required this.saffron,
    required this.hero,
    required this.onHero,
    required this.onHeroSoft,
    required this.nav,
    required this.navIdle,
    required this.pens,
  });
}

/// Colour tokens for SplitShare's "Chai & Pista" design: a warm cream page,
/// pistachio green for what comes back to you and for actions, pomegranate
/// for what you owe, saffron for the add button. Dark mode is the same set
/// on roasted-chai brown.
///
/// Every token is a getter that resolves against the active theme, so screens
/// keep writing `AppColors.textPrimary` and get the right colour in light and
/// dark. Don't use these inside `const` expressions.
class AppColors {
  AppColors._();

  static const _light = _Palette(
    page: Color(0xFFF6F1E7),
    surface: Color(0xFFFFFDF8),
    surfaceMuted: Color(0xFFEFE8DA),
    rule: Color(0xFFE5DCCB),
    text: Color(0xFF23201A),
    primary: Color(0xFF3C6B22),
    primarySoft: Color(0xFFE1EECF),
    onPrimary: Color(0xFFFFFDF8),
    textSecondary: Color(0xFF6E6857),
    textMuted: Color(0xFF8F887A),
    credit: Color(0xFF2F5F20),
    creditSoft: Color(0xFFE1EECF),
    debit: Color(0xFFB3263E),
    debitSoft: Color(0xFFF6DDE1),
    warning: Color(0xFF9A5F00),
    warningSoft: Color(0xFFF8E6C2),
    saffron: Color(0xFFE39B17),
    hero: Color(0xFFD5E8B5),
    onHero: Color(0xFF1F2A14),
    onHeroSoft: Color(0xFF46582C),
    nav: Color(0xFF23201A),
    navIdle: Color(0xFFCFC7B6),
    pens: [
      Color(0xFFB87400), // saffron
      Color(0xFF1F4870), // indigo
      Color(0xFF9C2238), // pomegranate
      Color(0xFF3C6B22), // pistachio
      Color(0xFF6A3A7E), // plum
      Color(0xFF1D6A6A), // teal
      Color(0xFFA4521A), // terracotta
      Color(0xFF5E6B1E), // olive
    ],
  );

  static const _dark = _Palette(
    page: Color(0xFF15130F),
    surface: Color(0xFF1F1C16),
    surfaceMuted: Color(0xFF29251D),
    rule: Color(0xFF332E25),
    text: Color(0xFFF1EBDD),
    primary: Color(0xFFA9D18E),
    primarySoft: Color(0xFF2C3B1E),
    onPrimary: Color(0xFF15130F),
    textSecondary: Color(0xFFA39C8A),
    textMuted: Color(0xFF7D7666),
    credit: Color(0xFFA9D18E),
    creditSoft: Color(0xFF26331A),
    debit: Color(0xFFFF8E9C),
    debitSoft: Color(0xFF3D1E24),
    warning: Color(0xFFF0B454),
    warningSoft: Color(0xFF3A2C12),
    saffron: Color(0xFFE39B17),
    hero: Color(0xFF2C3B1E),
    onHero: Color(0xFFD9EDB8),
    onHeroSoft: Color(0xFFB7CF94),
    nav: Color(0xFF29251D),
    navIdle: Color(0xFFA39C8A),
    pens: [
      Color(0xFFF4C66A),
      Color(0xFF9CC4EE),
      Color(0xFFFF9AA8),
      Color(0xFFA9D18E),
      Color(0xFFD2A8E6),
      Color(0xFF7FD1C8),
      Color(0xFFF0A070),
      Color(0xFFC9D27A),
    ],
  );

  static bool _isDark = false;
  static _Palette get _p => _isDark ? _dark : _light;

  /// Set by [ThemeController] whenever the effective theme changes.
  static void setDark(bool value) => _isDark = value;
  static bool get isDark => _isDark;

  // ---- Core roles -------------------------------------------------------
  static Color get background => _p.page;
  static Color get surface => _p.surface;
  static Color get surfaceMuted => _p.surfaceMuted;
  static Color get border => _p.rule;
  static Color get textPrimary => _p.text;
  static Color get textSecondary => _p.textSecondary;
  static Color get textMuted => _p.textMuted;

  /// Pistachio: primary actions, links, selected states.
  static Color get primary => _p.primary;
  static Color get primaryDark => _p.primary;
  static Color get primaryLight => _p.primarySoft;

  /// Text / icons on a primary-filled control.
  static Color get onPrimary => _p.onPrimary;

  static Color get secondary => _p.primary;

  /// Saffron: the add button and other single warm highlights.
  static Color get accent => _p.saffron;
  static Color get onAccent => const Color(0xFF23201A);

  // ---- Balance card + nav ------------------------------------------------
  static Color get hero => _p.hero;
  static Color get onHero => _p.onHero;
  static Color get onHeroSoft => _p.onHeroSoft;
  static Color get nav => _p.nav;
  static Color get navIdle => _p.navIdle;

  // ---- Money ------------------------------------------------------------
  static Color get positive => _p.credit; // owes you
  static Color get positiveLight => _p.creditSoft;
  static Color get negative => _p.debit; // you owe
  static Color get negativeLight => _p.debitSoft;

  /// Fine accent lines (kept for older call-sites).
  static Color get rule => _p.primary;

  // ---- States -----------------------------------------------------------
  static Color get success => _p.credit;
  static Color get error => _p.debit;
  static Color get info => _p.primary;
  static Color get infoLight => _p.primarySoft;
  static Color get warning => _p.warning;
  static Color get warningLight => _p.warningSoft;

  // ---- Fills ------------------------------------------------------------
  // No gradients: these resolve to flat fills so legacy call-sites render
  // as a solid block.
  static LinearGradient get brandGradient => _flat(_p.primary);
  static LinearGradient get heroGradient => _flat(_p.primary);
  static LinearGradient get positiveGradient => _flat(_p.credit);
  static LinearGradient get negativeGradient => _flat(_p.debit);

  static LinearGradient _flat(Color c) => LinearGradient(colors: [c, c]);

  /// Per-person identity colours.
  static List<Color> get palette => _p.pens;

  /// Stable identity colour for a string key (uid, name...).
  static Color forKey(String key) {
    final pens = _p.pens;
    if (key.isEmpty) return pens.first;
    var hash = 0;
    for (final unit in key.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return pens[hash % pens.length];
  }
}

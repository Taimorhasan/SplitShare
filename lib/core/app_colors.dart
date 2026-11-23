import 'package:flutter/material.dart';

/// Central colour tokens for SplitShare.
///
/// Every screen should pull colours from here (or from `Theme.of(context)`),
/// never from ad-hoc hex literals, so the whole app stays visually consistent.
class AppColors {
  AppColors._();

  // Brand
  static const primary = Color(0xFF4F46E5); // Indigo 600
  static const primaryDark = Color(0xFF3730A3);
  static const primaryLight = Color(0xFFEEF2FF);
  static const secondary = Color(0xFF7C3AED); // Violet 600
  static const accent = Color(0xFF06B6D4); // Cyan 500

  // Semantic money colours
  static const positive = Color(0xFF10B981); // you are owed
  static const positiveLight = Color(0xFFD1FAE5);
  static const negative = Color(0xFFF43F5E); // you owe
  static const negativeLight = Color(0xFFFFE4E6);
  static const warning = Color(0xFFF59E0B);
  static const warningLight = Color(0xFFFEF3C7);

  // Legacy aliases (kept so older call-sites keep compiling)
  static const success = positive;
  static const error = Color(0xFFE11D48);
  static const info = Color(0xFF3B82F6);
  static const infoLight = Color(0xFFDBEAFE);

  // Neutrals
  static const background = Color(0xFFF5F6FB);
  static const surface = Colors.white;
  static const surfaceMuted = Color(0xFFF1F3F9);
  static const border = Color(0xFFE4E7EF);
  static const textPrimary = Color(0xFF0F172A);
  static const textSecondary = Color(0xFF64748B);
  static const textMuted = Color(0xFF94A3B8);

  // Gradients
  static const brandGradient = LinearGradient(
    colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const heroGradient = LinearGradient(
    colors: [Color(0xFF4338CA), Color(0xFF6D28D9), Color(0xFF9333EA)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const positiveGradient = LinearGradient(
    colors: [Color(0xFF10B981), Color(0xFF059669)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const negativeGradient = LinearGradient(
    colors: [Color(0xFFFB7185), Color(0xFFE11D48)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// A rotating palette for avatars / group icons so items are distinguishable.
  static const List<Color> palette = [
    Color(0xFF4F46E5),
    Color(0xFF0EA5E9),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEC4899),
    Color(0xFF8B5CF6),
    Color(0xFF14B8A6),
    Color(0xFFF97316),
  ];

  /// Stable colour for a string key (uid, name...).
  static Color forKey(String key) {
    if (key.isEmpty) return palette.first;
    var hash = 0;
    for (final unit in key.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return palette[hash % palette.length];
  }
}

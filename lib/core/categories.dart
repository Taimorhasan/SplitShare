import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Visual metadata for a category / group type.
///
/// Colours are muted inks: one shade for the light
/// page and a lighter one for the night page.
class CategoryStyle {
  final String name;
  final IconData icon;
  final Color light;
  final Color dark;
  const CategoryStyle(this.name, this.icon, this.light, this.dark);

  Color get color => AppColors.isDark ? dark : light;
  Color get tint => color.withValues(alpha: AppColors.isDark ? 0.20 : 0.10);
}

/// Expense categories. Names are persisted in Firestore (`expenses.category`),
/// so existing names must never be renamed — only new ones added.
class ExpenseCategories {
  ExpenseCategories._();

  static const List<CategoryStyle> all = [
    CategoryStyle('Food', Icons.restaurant_rounded, Color(0xFFA4521A), Color(0xFFE3965E)),
    CategoryStyle('Groceries', Icons.local_grocery_store_rounded, Color(0xFF2E6B4F), Color(0xFF6FC49B)),
    CategoryStyle('Travel', Icons.flight_takeoff_rounded, Color(0xFF1D5E8C), Color(0xFF7FB6E0)),
    CategoryStyle('Transport', Icons.directions_car_rounded, Color(0xFF2F4A9E), Color(0xFF9CB0FF)),
    CategoryStyle('Bills', Icons.bolt_rounded, Color(0xFF8A5A00), Color(0xFFD9A54A)),
    CategoryStyle('Rent', Icons.home_rounded, Color(0xFF5B3A8E), Color(0xFFB394EA)),
    CategoryStyle('Shopping', Icons.shopping_bag_rounded, Color(0xFF8E2F5F), Color(0xFFE07FAA)),
    CategoryStyle('Entertainment', Icons.movie_rounded, Color(0xFFA12B2B), Color(0xFFF07A72)),
    CategoryStyle('Health', Icons.favorite_rounded, Color(0xFF00707A), Color(0xFF52C2CC)),
    CategoryStyle('Other', Icons.category_rounded, Color(0xFF55608A), Color(0xFFA3ACCB)),
  ];

  /// Style used for settle-up payments (the "owes you" ink).
  static const payment = CategoryStyle(
      'Payment', Icons.payments_rounded, Color(0xFF1E3FA3), Color(0xFF9CB0FF));

  static CategoryStyle of(String? name, {bool isPayment = false}) {
    if (isPayment) return payment;
    return all.firstWhere(
      (c) => c.name == name,
      orElse: () => all.last,
    );
  }
}

/// Group types. Persisted in `groups.icon`.
class GroupTypes {
  GroupTypes._();

  static const List<CategoryStyle> all = [
    CategoryStyle('Trip', Icons.flight_takeoff_rounded, Color(0xFF1D5E8C), Color(0xFF7FB6E0)),
    CategoryStyle('Home', Icons.home_rounded, Color(0xFF5B3A8E), Color(0xFFB394EA)),
    CategoryStyle('Couple', Icons.favorite_rounded, Color(0xFF8E2F5F), Color(0xFFE07FAA)),
    CategoryStyle('Food', Icons.restaurant_rounded, Color(0xFFA4521A), Color(0xFFE3965E)),
    CategoryStyle('Bills', Icons.receipt_long_rounded, Color(0xFF8A5A00), Color(0xFFD9A54A)),
    CategoryStyle('Work', Icons.work_rounded, Color(0xFF2F4A9E), Color(0xFF9CB0FF)),
    CategoryStyle('Event', Icons.celebration_rounded, Color(0xFFA12B2B), Color(0xFFF07A72)),
    CategoryStyle('Other', Icons.groups_rounded, Color(0xFF3C6B22), Color(0xFFA9D18E)),
  ];

  static CategoryStyle of(String? name) {
    if (name == 'home_outlined') return all[1]; // legacy default value
    return all.firstWhere((c) => c.name == name, orElse: () => all.last);
  }
}

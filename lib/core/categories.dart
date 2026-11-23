import 'package:flutter/material.dart';

/// Visual metadata for a category / group type.
class CategoryStyle {
  final String name;
  final IconData icon;
  final Color color;
  const CategoryStyle(this.name, this.icon, this.color);

  Color get tint => color.withValues(alpha: 0.12);
}

/// Expense categories. Names are persisted in Firestore (`expenses.category`),
/// so existing names must never be renamed — only new ones added.
class ExpenseCategories {
  ExpenseCategories._();

  static const List<CategoryStyle> all = [
    CategoryStyle('Food', Icons.restaurant_rounded, Color(0xFFF97316)),
    CategoryStyle('Groceries', Icons.local_grocery_store_rounded, Color(0xFF22C55E)),
    CategoryStyle('Travel', Icons.flight_takeoff_rounded, Color(0xFF0EA5E9)),
    CategoryStyle('Transport', Icons.directions_car_rounded, Color(0xFF3B82F6)),
    CategoryStyle('Bills', Icons.bolt_rounded, Color(0xFFF59E0B)),
    CategoryStyle('Rent', Icons.home_rounded, Color(0xFF8B5CF6)),
    CategoryStyle('Shopping', Icons.shopping_bag_rounded, Color(0xFFEC4899)),
    CategoryStyle('Entertainment', Icons.movie_rounded, Color(0xFFE11D48)),
    CategoryStyle('Health', Icons.favorite_rounded, Color(0xFF14B8A6)),
    CategoryStyle('Other', Icons.category_rounded, Color(0xFF64748B)),
  ];

  /// Style used for settle-up payments.
  static const payment =
      CategoryStyle('Payment', Icons.payments_rounded, Color(0xFF10B981));

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
    CategoryStyle('Trip', Icons.flight_takeoff_rounded, Color(0xFF0EA5E9)),
    CategoryStyle('Home', Icons.home_rounded, Color(0xFF8B5CF6)),
    CategoryStyle('Couple', Icons.favorite_rounded, Color(0xFFEC4899)),
    CategoryStyle('Food', Icons.restaurant_rounded, Color(0xFFF97316)),
    CategoryStyle('Bills', Icons.receipt_long_rounded, Color(0xFFF59E0B)),
    CategoryStyle('Work', Icons.work_rounded, Color(0xFF3B82F6)),
    CategoryStyle('Event', Icons.celebration_rounded, Color(0xFFE11D48)),
    CategoryStyle('Other', Icons.groups_rounded, Color(0xFF4F46E5)),
  ];

  static CategoryStyle of(String? name) {
    if (name == 'home_outlined') return all[1]; // legacy default value
    return all.firstWhere((c) => c.name == name, orElse: () => all.last);
  }
}

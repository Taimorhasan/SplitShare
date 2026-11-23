import 'package:cloud_firestore/cloud_firestore.dart';

/// Supported currencies: code -> (symbol, name).
class Currencies {
  Currencies._();

  static const Map<String, String> symbols = {
    'USD': '\$',
    'GBP': '£',
    'EUR': '€',
    'INR': '₹',
    'PKR': '₨',
    'JPY': '¥',
    'CAD': 'C\$',
    'AUD': 'A\$',
  };

  static const Map<String, String> names = {
    'USD': 'US Dollar',
    'GBP': 'British Pound',
    'EUR': 'Euro',
    'INR': 'Indian Rupee',
    'PKR': 'Pakistani Rupee',
    'JPY': 'Japanese Yen',
    'CAD': 'Canadian Dollar',
    'AUD': 'Australian Dollar',
  };

  static String symbolFor(String? code) => symbols[code ?? 'USD'] ?? '\$';
}

class Fmt {
  Fmt._();

  /// Formats [amount] with thousands separators and 2 decimals (0 for JPY).
  static String money(num amount, {String? currencyCode, bool signed = false}) {
    final code = currencyCode ?? 'USD';
    final symbol = Currencies.symbolFor(code);
    final decimals = code == 'JPY' ? 0 : 2;
    final value = amount.abs().toDouble();
    final fixed = value.toStringAsFixed(decimals);
    final parts = fixed.split('.');
    final intPart = parts[0].replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    final body = parts.length > 1 ? '$intPart.${parts[1]}' : intPart;
    final sign = amount < 0 ? '-' : (signed && amount > 0 ? '+' : '');
    return '$sign$symbol$body';
  }

  /// Formats a per-currency amount map, e.g. `$10.00 + €4.50`.
  /// The [preferred] currency is listed first. Zero amounts are skipped.
  static String multi(
    Map<String, double> byCurrency, {
    String preferred = 'USD',
    bool absolute = true,
  }) {
    final entries = byCurrency.entries
        .where((e) => e.value.abs() >= 0.005)
        .toList()
      ..sort((a, b) {
        if (a.key == preferred) return -1;
        if (b.key == preferred) return 1;
        return a.key.compareTo(b.key);
      });
    if (entries.isEmpty) return money(0, currencyCode: preferred);
    return entries
        .map((e) => money(absolute ? e.value.abs() : e.value, currencyCode: e.key))
        .join(' + ');
  }

  static DateTime? toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// e.g. `12 Mar 2026`.
  static String date(dynamic value) {
    final d = toDate(value);
    if (d == null) return '';
    return '${d.day} ${_months[d.month - 1]} ${d.year}';
  }

  /// e.g. `12 Mar`.
  static String shortDate(dynamic value) {
    final d = toDate(value);
    if (d == null) return '';
    return '${d.day} ${_months[d.month - 1]}';
  }

  /// Human relative time: `Just now`, `5 min ago`, `Yesterday`, `12 Mar`.
  static String relative(dynamic value) {
    final d = toDate(value);
    if (d == null) return 'Just now';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) {
      return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
    }
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return d.year == DateTime.now().year ? shortDate(d) : date(d);
  }

  /// Section label used to group lists by day: `Today`, `Yesterday`, `March 2026`...
  static String dayGroup(dynamic value) {
    final d = toDate(value);
    if (d == null) return 'Today';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return 'This week';
    const full = [
      'January', 'February', 'March', 'April', 'May', 'June', 'July',
      'August', 'September', 'October', 'November', 'December',
    ];
    return '${full[d.month - 1]} ${d.year}';
  }

  /// First name / short display.
  static String firstName(String? name) {
    final n = (name ?? '').trim();
    if (n.isEmpty) return 'there';
    return n.split(RegExp(r'\s+')).first;
  }

  static String initials(String? name) {
    final parts = (name ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

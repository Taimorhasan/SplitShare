import 'package:get/get.dart';

import 'expense_controller.dart';
import 'trip_controller.dart';

/// One source of truth for "how much do we owe each other", combining
/// friends & groups expenses with every Lain Dain trip, cancelled against
/// each other per currency. Positive = they owe me.
///
/// Reads Rx state, so calling these inside `Obx` rebuilds automatically when
/// expenses or trips change.
class Balances {
  Balances._();

  static ExpenseController get _ec => ExpenseController.to;
  static TripController? get _tc =>
      Get.isRegistered<TripController>() ? TripController.to : null;

  static Map<String, double> _clean(Map<String, double> m) =>
      m..removeWhere((_, v) => v.abs() < 0.005);

  /// Lain Dain only, with an app user.
  static Map<String, double> tripsWith(String uid) {
    final c = _tc?.myBalances()[uid];
    return c == null ? {} : Map<String, double>.from(c.byCurrency);
  }

  /// Trip-by-trip lines with an app user.
  static List<({String tripId, String title, double amount, String currency})>
  tripLinesWith(String uid) => _tc?.myBalances()[uid]?.trips ?? const [];

  /// Friends & groups only.
  static Map<String, double> expensesWith(String uid) => _ec.balanceWith(uid);

  /// Everything with one person.
  static Map<String, double> withPerson(String uid) {
    final m = <String, double>{...expensesWith(uid)};
    tripsWith(uid).forEach((cur, v) => m[cur] = (m[cur] ?? 0) + v);
    return _clean(m);
  }

  /// Both directions with one person, kept apart, per currency:
  /// [theyOwe] = what they owe me, [iOwe] = what I owe them (both >= 0).
  ///
  /// Invariant: `theyOwe[c] - iOwe[c] == withPerson(uid)[c]` for every
  /// currency (up to the 0.005 dust both sides drop).
  ///
  /// - Expenses (friends & groups): each open expense's signed entry for
  ///   [uid] from [ExpenseController.netForExpense] (positive = they owe me)
  ///   goes to theyOwe or iOwe. Open payments are not debts, so they pay
  ///   down the side they repay (positive payment = I paid them → reduces
  ///   iOwe; negative = they paid me → reduces theyOwe); any overpayment
  ///   spills to the other side so the net still matches [expensesWith].
  /// - Groups (trips): each shared pair's net after pay-backs, split by sign.
  static ({Map<String, double> theyOwe, Map<String, double> iOwe}) grossWith(
    String uid,
  ) {
    final theyOwe = <String, double>{};
    final iOwe = <String, double>{};
    void add(Map<String, double> m, String cur, double v) =>
        m[cur] = (m[cur] ?? 0) + v;

    final me = _ec.currentUid;
    if (me != null && uid.isNotEmpty && uid != me) {
      final payments = <String, double>{};
      for (final e in _ec.openExpenses) {
        final v = ExpenseController.netForExpense(e, me)[uid];
        if (v == null || v == 0) continue;
        final cur = (e['currencyCode'] ?? 'USD').toString();
        if (ExpenseController.isPayment(e)) {
          add(payments, cur, v);
        } else if (v > 0) {
          add(theyOwe, cur, v);
        } else {
          add(iOwe, cur, -v);
        }
      }
      payments.forEach((cur, p) {
        // p > 0 pays down what I owe; p < 0 pays down what they owe.
        final (paidDown, other) = p > 0 ? (iOwe, theyOwe) : (theyOwe, iOwe);
        final amount = p.abs();
        final open = paidDown[cur] ?? 0;
        final used = amount < open ? amount : open;
        paidDown[cur] = open - used;
        if (amount > used) add(other, cur, amount - used);
      });

      final tc = _tc;
      if (tc != null) {
        for (final trip in tc.trips) {
          final mine = trip.people.firstWhereOrNull((p) => p.uid == me);
          if (mine == null) continue;
          for (final v in trip.pairsFor(mine.id)) {
            if (trip.person(v.otherId)?.uid != uid) continue;
            if (v.net > 0) add(theyOwe, trip.currencyCode, v.net / 100);
            if (v.net < 0) add(iOwe, trip.currencyCode, -v.net / 100);
          }
        }
      }
    }
    return (theyOwe: _clean(theyOwe), iOwe: _clean(iOwe));
  }

  /// Everyone I have any open balance with: key → signed per-currency map.
  /// Keys are uids, or `name:<lower>` for Lain Dain people not on SplitShare.
  static Map<String, Map<String, double>> everyone() {
    final result = <String, Map<String, double>>{};
    _ec.balances.forEach((uid, m) => result[uid] = Map<String, double>.from(m));
    _tc?.myBalances().forEach((key, c) {
      final m = result.putIfAbsent(key, () => {});
      c.byCurrency.forEach((cur, v) => m[cur] = (m[cur] ?? 0) + v);
    });
    result.updateAll((_, m) => _clean(m));
    result.removeWhere((_, m) => m.isEmpty);
    return result;
  }

  /// Totals after cancelling per person: what I'm owed / what I owe.
  static ({Map<String, double> owed, Map<String, double> owe}) totals() {
    final owed = <String, double>{};
    final owe = <String, double>{};
    for (final m in everyone().values) {
      m.forEach((cur, v) {
        if (v > 0) {
          owed[cur] = (owed[cur] ?? 0) + v;
        } else {
          owe[cur] = (owe[cur] ?? 0) - v;
        }
      });
    }
    return (owed: owed, owe: owe);
  }

  /// Display info for a key from [everyone] (name / avatar).
  static ({String name, String avatarUrl, String? uid}) personInfo(String key) {
    final c = _tc?.myBalances()[key];
    if (key.startsWith('name:')) {
      return (
        name: c?.name ?? key.substring(5),
        avatarUrl: c?.avatarUrl ?? '',
        uid: null,
      );
    }
    final s = _ec.settleUpData[key];
    final name = (s?['name'] ?? c?.name ?? _ec.nameFor(key)).toString();
    final avatar = (s?['avatarUrl'] ?? c?.avatarUrl ?? '').toString();
    return (name: name, avatarUrl: avatar, uid: key);
  }
}

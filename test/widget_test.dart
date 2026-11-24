// Unit + widget tests that run without Firebase.
//
// They cover the money maths (the part most likely to cause real-world
// harm if wrong), formatting, validation and the core UI components.

import 'package:flutter/material.dart';
import 'package:splitshare/controllers/expense_controller.dart';
import 'package:splitshare/controllers/trip_controller.dart';
import 'package:splitshare/core/ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

Map<String, dynamic> expense({
  required String payer,
  required Map<String, double> splits,
  List<String> settledPairs = const [],
  bool isSettled = false,
}) =>
    {
      'paidBy': {'uid': payer, 'name': payer},
      'individualSplits': splits,
      'settledPairs': settledPairs,
      'isSettled': isSettled,
      'currencyCode': 'USD',
    };

void main() {
  group('ExpenseController.distribute', () {
    test('equal split sums exactly to the total (no lost cents)', () {
      final r = ExpenseController.distribute(100, ['a', 'b', 'c'], [1, 1, 1]);
      final sum = r.values.fold(0.0, (a, b) => a + b);
      expect((sum * 100).round(), 10000);
      expect(r.values.toSet(), containsAll(<double>[33.34, 33.33]));
    });

    test('weighted (percent) split respects weights', () {
      final r = ExpenseController.distribute(200, ['a', 'b'], [75, 25]);
      expect(r['a'], 150);
      expect(r['b'], 50);
    });

    test('zero-weight participants get nothing', () {
      final r = ExpenseController.distribute(10, ['a', 'b', 'c'], [1, 0, 1]);
      expect(r['b'], 0);
      expect(r['a']! + r['c']!, 10);
    });
  });

  group('ExpenseController.netForExpense', () {
    test('payer is owed every other share', () {
      final e = expense(payer: 'me', splits: {'me': 10, 'a': 10, 'b': 10});
      expect(ExpenseController.netForExpense(e, 'me'), {'a': 10, 'b': 10});
    });

    test('non-payer owes their own share to the payer only', () {
      final e = expense(payer: 'a', splits: {'me': 12.5, 'a': 12.5, 'b': 25});
      expect(ExpenseController.netForExpense(e, 'me'), {'a': -12.5});
    });

    test('not involved => nothing', () {
      final e = expense(payer: 'a', splits: {'a': 5, 'b': 5});
      expect(ExpenseController.netForExpense(e, 'me'), isEmpty);
    });

    test('settled pairs are excluded', () {
      final pair = ExpenseController.pairKey('me', 'a');
      final e = expense(
        payer: 'me',
        splits: {'me': 10, 'a': 10, 'b': 10},
        settledPairs: [pair],
      );
      expect(ExpenseController.netForExpense(e, 'me'), {'b': 10});
    });

    test('fully settled expense has no effect', () {
      final e = expense(payer: 'me', splits: {'me': 10, 'a': 10}, isSettled: true);
      expect(ExpenseController.netForExpense(e, 'me'), isEmpty);
    });

    test('a payment nets an existing debt to zero', () {
      // a paid 30 for dinner, my share 15 -> I owe a 15.
      final dinner = expense(payer: 'a', splits: {'me': 15, 'a': 15});
      // I pay a 15 -> stored as paid by me, a's split = 15.
      final payment = {
        ...expense(payer: 'me', splits: {'a': 15, 'me': 0}),
        'type': 'payment',
      };
      final total = <String, double>{};
      for (final e in [dinner, payment]) {
        ExpenseController.netForExpense(e, 'me').forEach((k, v) {
          total[k] = (total[k] ?? 0) + v;
        });
      }
      expect(total['a'], 0);
      expect(ExpenseController.isPayment(payment), isTrue);
    });

    test('pairKey is order independent', () {
      expect(ExpenseController.pairKey('x', 'y'), ExpenseController.pairKey('y', 'x'));
    });
  });

  group('TripMath', () {
    TripPerson p(String id) => TripPerson(id: id, name: id);
    TripPayment pay(String who, double amount) => TripPayment(
          id: '$who$amount',
          personId: who,
          cents: TripMath.toCents(amount),
          at: DateTime(2026),
        );

    // The user's real example: four friends pay different amounts.
    final people = [p('Ahad'), p('Ali'), p('Usman'), p('Taimoor')];
    final payments = [
      pay('Ahad', 8000),
      pay('Ali', 7500),
      pay('Usman', 890),
      pay('Taimoor', 500),
    ];

    test('equal shares and balances add up to zero', () {
      final s = TripMath.summarise(people, payments, const []);
      expect(s.map((x) => x.shareCents).fold<int>(0, (a, b) => a + b), 1689000);
      expect(s.map((x) => x.balanceCents).fold<int>(0, (a, b) => a + b), 0);
      final byName = {for (final x in s) x.person.id: x.balanceCents};
      expect(byName['Ahad'], 377750); // +3,777.50
      expect(byName['Ali'], 327750); // +3,277.50
      expect(byName['Usman'], -333250); // -3,332.50
      expect(byName['Taimoor'], -372250); // -3,722.50
    });

    test('settle plan uses at most n-1 transfers and clears every balance', () {
      final plan = TripMath.settlePlan(TripMath.summarise(people, payments, const []));
      expect(plan.length, lessThanOrEqualTo(3));
      final net = <String, int>{};
      for (final t in plan) {
        net[t.fromId] = (net[t.fromId] ?? 0) + t.cents;
        net[t.toId] = (net[t.toId] ?? 0) - t.cents;
      }
      expect(net['Taimoor'], 372250);
      expect(net['Usman'], 333250);
      expect(net['Ahad'], -377750);
      expect(net['Ali'], -327750);
    });

    test('marking transfers as paid settles the trip', () {
      final plan = TripMath.settlePlan(TripMath.summarise(people, payments, const []));
      final settlements = [
        for (final t in plan)
          TripSettlement(
            id: t.toString(),
            fromId: t.fromId,
            toId: t.toId,
            cents: t.cents,
            at: DateTime(2026),
          ),
      ];
      final after = TripMath.summarise(people, payments, settlements);
      expect(after.every((x) => x.balanceCents == 0), isTrue);
      expect(TripMath.settlePlan(after), isEmpty);
    });

    test('odd totals still split to the cent', () {
      final shares = TripMath.equalShares(1000, 3);
      expect(shares.fold<int>(0, (a, b) => a + b), 1000);
    });
  });

  group('Full-amount split', () {
    test('payer is owed everything', () {
      final e = expense(payer: 'me', splits: {'me': 0, 'a': 50});
      expect(ExpenseController.netForExpense(e, 'me'), {'a': 50});
      expect(ExpenseController.netForExpense(e, 'a'), {'me': -50});
    });
  });

  group('Fmt', () {
    test('money formats with symbol, separators and sign', () {
      expect(Fmt.money(1234.5, currencyCode: 'USD'), '\$1,234.50');
      expect(Fmt.money(-20, currencyCode: 'EUR'), '-€20.00');
      expect(Fmt.money(1500, currencyCode: 'JPY'), '¥1,500');
      expect(Fmt.money(5, currencyCode: 'GBP', signed: true), '+£5.00');
    });

    test('multi lists preferred currency first and skips zeros', () {
      final s = Fmt.multi({'EUR': 4, 'USD': 10, 'GBP': 0}, preferred: 'USD');
      expect(s, '\$10.00 + €4.00');
    });

    test('initials and first name', () {
      expect(Fmt.initials('Ada Lovelace'), 'AL');
      expect(Fmt.initials(''), '?');
      expect(Fmt.firstName('  Grace Hopper '), 'Grace');
    });

    test('relative time', () {
      expect(Fmt.relative(DateTime.now()), 'Just now');
      expect(
        Fmt.relative(DateTime.now().subtract(const Duration(days: 1, hours: 1))),
        'Yesterday',
      );
    });
  });

  group('Validators', () {
    test('email', () {
      expect(Validators.email('a@b.co'), isNull);
      expect(Validators.email('nope'), isNotNull);
      expect(Validators.email(''), isNotNull);
    });

    test('password needs 8 chars with a letter and a number', () {
      expect(Validators.password('abc12345'), isNull);
      expect(Validators.password('short1'), isNotNull);
      expect(Validators.password('allletters'), isNotNull);
    });

    test('amount', () {
      expect(Validators.amount('12.50'), isNull);
      expect(Validators.amount('0'), isNotNull);
      expect(Validators.amount('abc'), isNotNull);
    });

    test('phone is optional but validated when present', () {
      expect(Validators.phone(''), isNull);
      expect(Validators.phone('+44 7700 900123'), isNull);
      expect(Validators.phone('12'), isNotNull);
    });
  });

  group('Design system widgets', () {
    Widget wrap(Widget child) => GetMaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: Center(child: child)),
        );

    testWidgets('AppButton fires once and blocks taps while loading',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(wrap(AppButton(label: 'Save', onPressed: () => taps++)));
      await tester.tap(find.text('Save'));
      expect(taps, 1);

      await tester.pumpWidget(
        wrap(AppButton(label: 'Save', loading: true, onPressed: () => taps++)),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byType(AppButton));
      expect(taps, 1);
    });

    testWidgets('EmptyState shows its call to action', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(EmptyState(
        icon: Icons.group,
        title: 'No groups yet',
        message: 'Create one',
        actionLabel: 'Create group',
        onAction: () => tapped = true,
        illustrationSize: 80,
      )));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('No groups yet'), findsOneWidget);
      await tester.tap(find.text('Create group'));
      expect(tapped, isTrue);
    });

    testWidgets('BalanceLabel shows direction and colour', (tester) async {
      await tester.pumpWidget(wrap(const BalanceLabel(
        byCurrency: {'USD': -12.5},
        preferredCurrency: 'USD',
      )));
      expect(find.text('you owe'), findsOneWidget);
      expect(find.text('\$12.50'), findsOneWidget);

      await tester.pumpWidget(wrap(const BalanceLabel(
        byCurrency: {},
        preferredCurrency: 'USD',
      )));
      expect(find.text('settled up'), findsOneWidget);
    });

    testWidgets('AppAvatar falls back to initials', (tester) async {
      await tester.pumpWidget(wrap(const AppAvatar(name: 'Sam Lee')));
      expect(find.text('SL'), findsOneWidget);
    });
  });
}

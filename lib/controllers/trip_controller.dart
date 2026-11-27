import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../core/formatters.dart';
import 'profile_controller.dart';

/// A person in a Lain Dain trip. [uid] is set when they're a SplitShare user
/// (then they can open the trip too); otherwise they're just a name.
class TripPerson {
  final String id;
  final String name;
  final String? uid;
  final String avatarUrl;

  const TripPerson({
    required this.id,
    required this.name,
    this.uid,
    this.avatarUrl = '',
  });

  factory TripPerson.fromMap(Map<String, dynamic> m) => TripPerson(
        id: m['id'].toString(),
        name: (m['name'] ?? 'Someone').toString(),
        uid: (m['uid']?.toString().isEmpty ?? true) ? null : m['uid'].toString(),
        avatarUrl: (m['avatarUrl'] ?? '').toString(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        if (uid != null) 'uid': uid,
        'avatarUrl': avatarUrl,
      };
}

/// Money someone paid during the trip, shared equally between [splitAmong]
/// (empty = everyone on the trip).
class TripPayment {
  final String id;
  final String personId;
  final int cents;
  final String note;
  final DateTime at;
  final List<String> splitAmong;

  const TripPayment({
    required this.id,
    required this.personId,
    required this.cents,
    this.note = '',
    required this.at,
    this.splitAmong = const [],
  });

  factory TripPayment.fromMap(Map<String, dynamic> m) => TripPayment(
        id: m['id'].toString(),
        personId: m['personId'].toString(),
        cents: (m['cents'] as num?)?.toInt() ?? 0,
        note: (m['note'] ?? '').toString(),
        at: DateTime.fromMillisecondsSinceEpoch((m['at'] as num?)?.toInt() ?? 0),
        splitAmong: ((m['splitAmong'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'personId': personId,
        'cents': cents,
        'note': note,
        'at': at.millisecondsSinceEpoch,
        'splitAmong': splitAmong,
      };

  /// Who shares this payment, in trip order. Unknown ids are ignored and an
  /// empty selection means everyone.
  List<String> sharers(List<TripPerson> people) {
    final ids = people.map((p) => p.id).toList();
    if (splitAmong.isEmpty) return ids;
    final set = splitAmong.toSet();
    final result = ids.where(set.contains).toList();
    return result.isEmpty ? ids : result;
  }

  bool splitsWithEveryone(List<TripPerson> people) =>
      sharers(people).length == people.length;
}

/// A pay-back between two people ("Usman paid Ali 3,277.50").
/// Doesn't change what was spent; it settles what one owes the other.
class TripSettlement {
  final String id;
  final String fromId;
  final String toId;
  final int cents;
  final DateTime at;

  const TripSettlement({
    required this.id,
    required this.fromId,
    required this.toId,
    required this.cents,
    required this.at,
  });

  factory TripSettlement.fromMap(Map<String, dynamic> m) => TripSettlement(
        id: m['id'].toString(),
        fromId: m['fromId'].toString(),
        toId: m['toId'].toString(),
        cents: (m['cents'] as num?)?.toInt() ?? 0,
        at: DateTime.fromMillisecondsSinceEpoch((m['at'] as num?)?.toInt() ?? 0),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'fromId': fromId,
        'toId': toId,
        'cents': cents,
        'at': at.millisecondsSinceEpoch,
      };
}

/// "from pays to `cents`".
class TripTransfer {
  final String fromId;
  final String toId;
  final int cents;
  const TripTransfer(this.fromId, this.toId, this.cents);

  @override
  String toString() => '$fromId→$toId:$cents';
}

/// Per-person totals.
class TripPersonSummary {
  final TripPerson person;
  final int paidCents;
  final int shareCents;

  /// Positive = others owe them; negative = they owe. Includes pay-backs.
  final int balanceCents;

  const TripPersonSummary({
    required this.person,
    required this.paidCents,
    required this.shareCents,
    required this.balanceCents,
  });
}

/// What two people owe each other, before and after cancelling out.
class TripPair {
  final String aId;
  final String bId;

  /// What a owes b (b paid for things a shared).
  final int aOwesB;

  /// What b owes a.
  final int bOwesA;

  /// Pay-backs already made a→b and b→a.
  final int aPaidB;
  final int bPaidA;

  const TripPair({
    required this.aId,
    required this.bId,
    required this.aOwesB,
    required this.bOwesA,
    this.aPaidB = 0,
    this.bPaidA = 0,
  });

  /// Net after cancelling and pay-backs. Positive = a still owes b.
  int get net => (aOwesB - aPaidB) - (bOwesA - bPaidA);

  bool get hasHistory => aOwesB > 0 || bOwesA > 0 || aPaidB > 0 || bPaidA > 0;

  /// The remaining transfer, if any.
  TripTransfer? get transfer {
    final n = net;
    if (n > 0) return TripTransfer(aId, bId, n);
    if (n < 0) return TripTransfer(bId, aId, -n);
    return null;
  }

  /// This pair seen from [personId]'s side.
  TripPairView viewFor(String personId) => personId == aId
      ? TripPairView(
          otherId: bId,
          iOwe: aOwesB,
          theyOwe: bOwesA,
          iPaidBack: aPaidB,
          theyPaidBack: bPaidA,
        )
      : TripPairView(
          otherId: aId,
          iOwe: bOwesA,
          theyOwe: aOwesB,
          iPaidBack: bPaidA,
          theyPaidBack: aPaidB,
        );
}

/// A pair relationship from one person's point of view.
class TripPairView {
  final String otherId;
  final int iOwe;
  final int theyOwe;
  final int iPaidBack;
  final int theyPaidBack;

  const TripPairView({
    required this.otherId,
    required this.iOwe,
    required this.theyOwe,
    required this.iPaidBack,
    required this.theyPaidBack,
  });

  /// Positive = they still owe me; negative = I still owe them.
  int get net => (theyOwe - theyPaidBack) - (iOwe - iPaidBack);
}

/// Pure Lain Dain maths (unit-tested; no Firebase). All money in cents.
class TripMath {
  TripMath._();

  static int toCents(double amount) => (amount * 100).round();

  /// Splits [total] cents equally between [n] people so it sums exactly.
  static List<int> equalShares(int total, int n) {
    if (n <= 0) return const [];
    final base = total ~/ n;
    final rem = total % n;
    return List.generate(n, (i) => base + (i < rem ? 1 : 0));
  }

  /// Each sharer's cents for one payment.
  static Map<String, int> sharesOf(TripPayment pay, List<TripPerson> people) {
    final sharers = pay.sharers(people);
    final parts = equalShares(pay.cents, sharers.length);
    return {for (var i = 0; i < sharers.length; i++) sharers[i]: parts[i]};
  }

  static List<TripPersonSummary> summarise(
    List<TripPerson> people,
    List<TripPayment> payments,
    List<TripSettlement> settlements,
  ) {
    final paid = <String, int>{for (final p in people) p.id: 0};
    final share = <String, int>{for (final p in people) p.id: 0};
    for (final pay in payments) {
      if (!paid.containsKey(pay.personId)) continue;
      paid[pay.personId] = paid[pay.personId]! + pay.cents;
      sharesOf(pay, people).forEach((id, c) => share[id] = share[id]! + c);
    }
    final sentBack = <String, int>{};
    final gotBack = <String, int>{};
    for (final s in settlements) {
      sentBack[s.fromId] = (sentBack[s.fromId] ?? 0) + s.cents;
      gotBack[s.toId] = (gotBack[s.toId] ?? 0) + s.cents;
    }
    return [
      for (final p in people)
        TripPersonSummary(
          person: p,
          paidCents: paid[p.id]!,
          shareCents: share[p.id]!,
          balanceCents: paid[p.id]! -
              share[p.id]! +
              (sentBack[p.id] ?? 0) -
              (gotBack[p.id] ?? 0),
        ),
    ];
  }

  /// Every pair of people with what each owes the other and the result
  /// after cancelling: "Ali owes Ahad 2,000, Ahad owes Ali 2,120 → Ahad pays
  /// Ali 120".
  static List<TripPair> pairs(
    List<TripPerson> people,
    List<TripPayment> payments,
    List<TripSettlement> settlements,
  ) {
    final ids = people.map((p) => p.id).toList();
    final idSet = ids.toSet();
    final owes = <String, int>{}; // "x|y" = x owes y
    for (final pay in payments) {
      if (!idSet.contains(pay.personId)) continue;
      sharesOf(pay, people).forEach((id, c) {
        if (id == pay.personId || c == 0) return;
        final k = '$id|${pay.personId}';
        owes[k] = (owes[k] ?? 0) + c;
      });
    }
    final paidBack = <String, int>{}; // "x|y" = x paid y back
    for (final s in settlements) {
      final k = '${s.fromId}|${s.toId}';
      paidBack[k] = (paidBack[k] ?? 0) + s.cents;
    }
    final result = <TripPair>[];
    for (var i = 0; i < ids.length; i++) {
      for (var j = i + 1; j < ids.length; j++) {
        final a = ids[i], b = ids[j];
        final pair = TripPair(
          aId: a,
          bId: b,
          aOwesB: owes['$a|$b'] ?? 0,
          bOwesA: owes['$b|$a'] ?? 0,
          aPaidB: paidBack['$a|$b'] ?? 0,
          bPaidA: paidBack['$b|$a'] ?? 0,
        );
        if (pair.hasHistory) result.add(pair);
      }
    }
    return result;
  }

  /// Settle each pair directly — easiest to follow.
  static List<TripTransfer> pairwisePlan(List<TripPair> pairs) =>
      pairs.map((p) => p.transfer).whereType<TripTransfer>().toList()
        ..sort((a, b) => b.cents.compareTo(a.cents));

  /// Fewest transfers that bring everyone to zero (greedy: biggest debtor
  /// pays biggest creditor). At most n − 1 transfers.
  static List<TripTransfer> settlePlan(List<TripPersonSummary> summary) {
    final creditors = summary
        .where((s) => s.balanceCents > 0)
        .map((s) => [s.person.id, s.balanceCents])
        .toList();
    final debtors = summary
        .where((s) => s.balanceCents < 0)
        .map((s) => [s.person.id, -s.balanceCents])
        .toList();
    final transfers = <TripTransfer>[];
    while (creditors.isNotEmpty && debtors.isNotEmpty) {
      creditors.sort((a, b) => (b[1] as int).compareTo(a[1] as int));
      debtors.sort((a, b) => (b[1] as int).compareTo(a[1] as int));
      final c = creditors.first;
      final d = debtors.first;
      final amount = math.min(c[1] as int, d[1] as int);
      if (amount > 0) {
        transfers.add(TripTransfer(d[0] as String, c[0] as String, amount));
      }
      c[1] = (c[1] as int) - amount;
      d[1] = (d[1] as int) - amount;
      if (c[1] == 0) creditors.removeAt(0);
      if (d[1] == 0) debtors.removeAt(0);
    }
    return transfers;
  }
}

/// Parsed trip document (`trips/{id}`). Derived numbers are computed once
/// per snapshot so lists stay smooth.
class Trip {
  final String id;
  final String title;
  final String currencyCode;

  /// Group type name (see `GroupTypes` in core/categories.dart).
  final String icon;
  final String ownerUid;
  final List<TripPerson> people;
  final List<TripPayment> payments;
  final List<TripSettlement> settlements;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Trip({
    required this.id,
    required this.title,
    required this.currencyCode,
    this.icon = 'Trip',
    required this.ownerUid,
    required this.people,
    required this.payments,
    required this.settlements,
    this.createdAt,
    this.updatedAt,
  });

  factory Trip.fromDoc(String id, Map<String, dynamic> d) {
    List<Map<String, dynamic>> list(String key) => ((d[key] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
    return Trip(
      id: id,
      title: (d['title'] ?? 'Trip').toString(),
      currencyCode: (d['currencyCode'] ?? 'USD').toString(),
      icon: (d['icon'] ?? 'Trip').toString(),
      ownerUid: (d['ownerUid'] ?? '').toString(),
      people: list('people').map(TripPerson.fromMap).toList(),
      payments: list('payments').map(TripPayment.fromMap).toList()
        ..sort((a, b) => b.at.compareTo(a.at)),
      settlements: list('settlements').map(TripSettlement.fromMap).toList()
        ..sort((a, b) => b.at.compareTo(a.at)),
      createdAt: Fmt.toDate(d['createdAt']),
      updatedAt: Fmt.toDate(d['updatedAt']),
    );
  }

  late final int totalCents = payments.fold<int>(0, (a, b) => a + b.cents);

  late final List<TripPersonSummary> summary =
      TripMath.summarise(people, payments, settlements);

  late final List<TripPair> pairs = TripMath.pairs(people, payments, settlements);

  /// Who pays whom, pair by pair (default — easiest to follow).
  late final List<TripTransfer> plan = TripMath.pairwisePlan(pairs);

  /// Same end result in the fewest possible transfers.
  late final List<TripTransfer> simplifiedPlan = TripMath.settlePlan(summary);

  bool get isSettled => payments.isNotEmpty && plan.isEmpty;

  /// Pair relationships involving [personId], from their side.
  List<TripPairView> pairsFor(String personId) => [
        for (final p in pairs)
          if (p.aId == personId || p.bId == personId) p.viewFor(personId),
      ];

  TripPerson? person(String id) => people.firstWhereOrNull((p) => p.id == id);

  String nameOf(String personId) => person(personId)?.name ?? 'Someone';
}

/// What the signed-in user and one other person owe each other across all
/// Lain Dain trips. [key] is the other person's uid, or `name:<lowercase>`
/// for people who aren't on SplitShare.
class TripCounterparty {
  final String key;
  final String name;
  final String? uid;
  final String avatarUrl;

  /// Positive = they owe me; negative = I owe them. Per currency.
  final Map<String, double> byCurrency;

  /// Per-trip breakdown: trip id → (title, signed amount, currency).
  final List<({String tripId, String title, double amount, String currency})> trips;

  TripCounterparty({
    required this.key,
    required this.name,
    required this.uid,
    required this.avatarUrl,
  })  : byCurrency = {},
        trips = [];
}

class TripException implements Exception {
  final String message;
  TripException(this.message);
  @override
  String toString() => message;
}

/// Trips ("Lain Dain"): a standalone calculator for a day out / trip where
/// several people pay for things and you want to know who owes whom at the
/// end. People don't need SplitShare accounts; app users added from friends
/// can open the same trip.
///
/// Firestore: `trips/{id}` {title, currencyCode, ownerUid, memberUids[],
/// people[], payments[{…, splitAmong[]}], settlements[], createdAt, updatedAt}.
class TripController extends GetxController {
  static TripController get to => Get.find();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  String? _uid;

  final trips = <Trip>[].obs;
  final isLoading = true.obs;
  final hasError = false.obs;

  @override
  void onInit() {
    super.onInit();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) {
        _uid = null;
        _sub?.cancel();
        trips.clear();
        isLoading.value = false;
        return;
      }
      if (_uid == user.uid) return;
      _uid = user.uid;
      fetchTrips();
    });
  }

  @override
  void onClose() {
    _authSub?.cancel();
    _sub?.cancel();
    super.onClose();
  }

  CollectionReference<Map<String, dynamic>> get _col => _firestore.collection('trips');

  String _newId() => _col.doc().id;

  void fetchTrips() {
    final uid = _uid;
    if (uid == null) return;
    isLoading.value = trips.isEmpty;
    hasError.value = false;
    _sub?.cancel();
    _sub = _col.where('memberUids', arrayContains: uid).snapshots().listen((snap) {
      final list = snap.docs.map((d) => Trip.fromDoc(d.id, d.data())).toList()
        ..sort((a, b) {
          final at = a.updatedAt ?? a.createdAt;
          final bt = b.updatedAt ?? b.createdAt;
          if (at == null) return -1;
          if (bt == null) return 1;
          return bt.compareTo(at);
        });
      _latest = list;
      trips.value = list;
      isLoading.value = false;
    }, onError: (Object e) {
      debugPrint('Trips stream error: $e');
      hasError.value = true;
      isLoading.value = false;
    });
  }

  Stream<Trip?> tripStream(String id) => _col
      .doc(id)
      .snapshots()
      .map((d) => d.exists ? Trip.fromDoc(d.id, d.data()!) : null);

  /// Creates a trip with the current user as the first person.
  Future<String> createTrip({
    required String title,
    required String currencyCode,
    String icon = 'Trip',
  }) async {
    final uid = _uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw TripException('Please sign in again.');
    final name = title.trim();
    if (name.isEmpty) throw TripException('Give your group a name.');
    final profile = Get.isRegistered<ProfileController>() ? ProfileController.to : null;
    final me = TripPerson(
      id: _newId(),
      name: (profile?.name.value.isNotEmpty ?? false) ? profile!.name.value : 'You',
      uid: uid,
      avatarUrl: profile?.avatarUrl.value ?? '',
    );
    final ref = await _col.add({
      'title': name,
      'currencyCode': currencyCode,
      'icon': icon,
      'ownerUid': uid,
      'memberUids': [uid],
      'people': [me.toMap()],
      'payments': <Map<String, dynamic>>[],
      'settlements': <Map<String, dynamic>>[],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }).timeout(const Duration(seconds: 20));
    return ref.id;
  }

  /// Applies [change] to a fresh copy of the trip inside a transaction so
  /// edits from several phones never overwrite each other.
  Future<void> _mutate(String tripId, void Function(Map<String, dynamic> data) change) async {
    final ref = _col.doc(tripId);
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw TripException('This group no longer exists.');
      final data = Map<String, dynamic>.from(snap.data()!);
      for (final key in ['people', 'payments', 'settlements', 'memberUids']) {
        data[key] = List<dynamic>.from((data[key] as List?) ?? const []);
      }
      change(data);
      tx.update(ref, {
        'title': data['title'],
        'currencyCode': data['currencyCode'],
        'icon': data['icon'] ?? 'Trip',
        'people': data['people'],
        'payments': data['payments'],
        'settlements': data['settlements'],
        'memberUids': data['memberUids'],
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }).timeout(const Duration(seconds: 20));
  }

  Future<void> updateDetails(
    String tripId, {
    String? title,
    String? currencyCode,
    String? icon,
  }) =>
      _mutate(tripId, (d) {
        if (title != null) {
          if (title.trim().isEmpty) throw TripException('The name can\'t be empty.');
          d['title'] = title.trim();
        }
        if (currencyCode != null) d['currencyCode'] = currencyCode;
        if (icon != null) d['icon'] = icon;
      });

  /// Adds people. Entries: {name, uid?, avatarUrl?}. Duplicate app users and
  /// exact duplicate names are skipped.
  Future<int> addPeople(String tripId, List<Map<String, dynamic>> entries) async {
    var added = 0;
    await _mutate(tripId, (d) {
      added = 0;
      final people = (d['people'] as List).cast<Map>();
      final members = (d['memberUids'] as List).cast<String>();
      for (final e in entries) {
        final name = (e['name'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        final uid = e['uid']?.toString();
        final dup = people.any((p) =>
            (uid != null && p['uid'] == uid) ||
            (uid == null &&
                p['uid'] == null &&
                p['name'].toString().toLowerCase() == name.toLowerCase()));
        if (dup) continue;
        people.add(TripPerson(
          id: _newId(),
          name: name,
          uid: uid,
          avatarUrl: (e['avatarUrl'] ?? '').toString(),
        ).toMap());
        if (uid != null && !members.contains(uid)) members.add(uid);
        added++;
      }
      d['people'] = people;
      d['memberUids'] = members;
    });
    return added;
  }

  Future<void> renamePerson(String tripId, String personId, String name) =>
      _mutate(tripId, (d) {
        final n = name.trim();
        if (n.isEmpty) throw TripException('Enter a name.');
        d['people'] = (d['people'] as List)
            .map((p) => p is Map && p['id'] == personId ? {...p, 'name': n} : p)
            .toList();
      });

  /// Removes a person together with their payments and pay-backs, and takes
  /// them out of every split.
  Future<void> removePerson(String tripId, String personId) => _mutate(tripId, (d) {
        final people = (d['people'] as List).cast<Map>();
        if (people.length <= 1) throw TripException('A group needs at least one person.');
        final person = people.firstWhereOrNull((p) => p['id'] == personId);
        if (person == null) return;
        final uid = person['uid']?.toString();
        if (uid != null && uid == d['ownerUid']) {
          throw TripException('The group\'s creator can\'t be removed.');
        }
        d['people'] = people.where((p) => p['id'] != personId).toList();
        d['payments'] = (d['payments'] as List)
            .whereType<Map>()
            .where((p) => p['personId'] != personId)
            .map((p) {
          final among = (p['splitAmong'] as List?) ?? const [];
          return {...p, 'splitAmong': among.where((x) => x != personId).toList()};
        }).toList();
        d['settlements'] = (d['settlements'] as List)
            .where((s) => s is Map && s['fromId'] != personId && s['toId'] != personId)
            .toList();
        if (uid != null) {
          d['memberUids'] = (d['memberUids'] as List).where((m) => m != uid).toList();
        }
      });

  /// [splitAmong]: person ids who share the payment (empty = everyone).
  Future<void> addPayment(
    String tripId, {
    required String personId,
    required double amount,
    String note = '',
    List<String> splitAmong = const [],
  }) {
    final cents = TripMath.toCents(amount);
    if (cents <= 0) throw TripException('Enter an amount above zero.');
    return _mutate(tripId, (d) {
      (d['payments'] as List).add(TripPayment(
        id: _newId(),
        personId: personId,
        cents: cents,
        note: note.trim(),
        at: DateTime.now(),
        splitAmong: splitAmong,
      ).toMap());
    });
  }

  Future<void> updatePayment(
    String tripId,
    String paymentId, {
    required String personId,
    required double amount,
    String note = '',
    List<String> splitAmong = const [],
  }) {
    final cents = TripMath.toCents(amount);
    if (cents <= 0) throw TripException('Enter an amount above zero.');
    return _mutate(tripId, (d) {
      d['payments'] = (d['payments'] as List).map((p) {
        if (p is Map && p['id'] == paymentId) {
          return {
            ...p,
            'personId': personId,
            'cents': cents,
            'note': note.trim(),
            'splitAmong': splitAmong,
          };
        }
        return p;
      }).toList();
    });
  }

  Future<void> deletePayment(String tripId, String paymentId) => _mutate(tripId, (d) {
        d['payments'] =
            (d['payments'] as List).where((p) => p is Map && p['id'] != paymentId).toList();
      });

  /// Records that [t] was paid back.
  Future<void> markTransferPaid(String tripId, TripTransfer t) => _mutate(tripId, (d) {
        (d['settlements'] as List).add(TripSettlement(
          id: _newId(),
          fromId: t.fromId,
          toId: t.toId,
          cents: t.cents,
          at: DateTime.now(),
        ).toMap());
      });

  Future<void> undoSettlement(String tripId, String settlementId) => _mutate(tripId, (d) {
        d['settlements'] = (d['settlements'] as List)
            .where((s) => s is Map && s['id'] != settlementId)
            .toList();
      });

  Future<void> deleteTrip(String tripId) => _col.doc(tripId).delete();

  bool isOwner(Trip trip) => trip.ownerUid == _uid;

  // Cache for [myBalances], recomputed only when a new snapshot arrives.
  List<Trip>? _memoTrips;
  List<Trip> _latest = const [];
  String? _memoUid;
  Map<String, TripCounterparty>? _memo;

  /// Marks every open Lain Dain balance with app user [otherUid] as paid,
  /// across all trips (records a pay-back in each). Returns how many trips
  /// were updated.
  Future<int> settleAllWith(String otherUid) async {
    final uid = _uid;
    if (uid == null) return 0;
    var count = 0;
    for (final trip in trips.toList()) {
      final me = trip.people.firstWhereOrNull((p) => p.uid == uid);
      final other = trip.people.firstWhereOrNull((p) => p.uid == otherUid);
      if (me == null || other == null) continue;
      final pair = trip.pairs.firstWhereOrNull((p) =>
          (p.aId == me.id && p.bId == other.id) || (p.aId == other.id && p.bId == me.id));
      final t = pair?.transfer;
      if (t == null) continue;
      await markTransferPaid(trip.id, t);
      count++;
    }
    return count;
  }

  /// My open Lain Dain balance with each person, across every trip.
  Map<String, TripCounterparty> myBalances() {
    final uid = _uid;
    trips.length; // register Rx dependency for Obx callers
    if (uid != null && identical(_memoTrips, _latest) && _memoUid == uid) {
      return _memo!;
    }
    final result = <String, TripCounterparty>{};
    if (uid == null) return result;
    _memoTrips = _latest;
    _memoUid = uid;
    _memo = result;
    for (final trip in trips) {
      final me = trip.people.firstWhereOrNull((p) => p.uid == uid);
      if (me == null) continue;
      for (final v in trip.pairsFor(me.id)) {
        if (v.net == 0) continue;
        final other = trip.person(v.otherId);
        if (other == null) continue;
        final key = other.uid ?? 'name:${other.name.trim().toLowerCase()}';
        final c = result.putIfAbsent(
          key,
          () => TripCounterparty(
            key: key,
            name: other.name,
            uid: other.uid,
            avatarUrl: other.avatarUrl,
          ),
        );
        final amount = v.net / 100;
        c.byCurrency[trip.currencyCode] =
            (c.byCurrency[trip.currencyCode] ?? 0) + amount;
        c.trips.add((
          tripId: trip.id,
          title: trip.title,
          amount: amount,
          currency: trip.currencyCode,
        ));
      }
    }
    for (final c in result.values) {
      c.byCurrency.removeWhere((_, v) => v.abs() < 0.005);
    }
    result.removeWhere((_, c) => c.byCurrency.isEmpty);
    return result;
  }

  /// Plain-text summary for WhatsApp etc.
  static String shareText(Trip trip) {
    String money(int cents) => Fmt.money(cents / 100, currencyCode: trip.currencyCode);
    final b = StringBuffer()
      ..writeln('🧾 ${trip.title} — SplitShare group')
      ..writeln('Total spent: ${money(trip.totalCents)} · ${trip.people.length} people')
      ..writeln()
      ..writeln('Who paid what:');
    for (final s in trip.summary) {
      b.writeln('• ${s.person.name}: paid ${money(s.paidCents)}, '
          'share ${money(s.shareCents)}');
    }
    b.writeln();
    final plan = trip.plan;
    if (plan.isEmpty) {
      b.writeln('✅ Everyone is settled up.');
    } else {
      b.writeln('To settle up:');
      for (final t in plan) {
        b.writeln('➡️ ${trip.nameOf(t.fromId)} pays ${trip.nameOf(t.toId)} ${money(t.cents)}');
      }
    }
    return b.toString().trimRight();
  }
}

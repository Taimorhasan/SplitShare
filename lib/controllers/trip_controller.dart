import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../core/formatters.dart';
import 'profile_controller.dart';

/// A person in a trip. [uid] is set when they're a SplitShare user (then they
/// can open the trip too); otherwise they're just a name.
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

/// Money someone put in during the trip (counts towards the shared total).
class TripPayment {
  final String id;
  final String personId;
  final int cents;
  final String note;
  final DateTime at;

  const TripPayment({
    required this.id,
    required this.personId,
    required this.cents,
    this.note = '',
    required this.at,
  });

  factory TripPayment.fromMap(Map<String, dynamic> m) => TripPayment(
        id: m['id'].toString(),
        personId: m['personId'].toString(),
        cents: (m['cents'] as num?)?.toInt() ?? 0,
        note: (m['note'] ?? '').toString(),
        at: DateTime.fromMillisecondsSinceEpoch((m['at'] as num?)?.toInt() ?? 0),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'personId': personId,
        'cents': cents,
        'note': note,
        'at': at.millisecondsSinceEpoch,
      };
}

/// A pay-back between two people after the trip ("Usman paid Ali 3,277.50").
/// Doesn't change the trip total; moves balances towards zero.
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

  /// Positive = the group owes them; negative = they owe. Includes pay-backs.
  final int balanceCents;

  const TripPersonSummary({
    required this.person,
    required this.paidCents,
    required this.shareCents,
    required this.balanceCents,
  });
}

/// Pure trip maths (unit-tested; no Firebase).
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

  static List<TripPersonSummary> summarise(
    List<TripPerson> people,
    List<TripPayment> payments,
    List<TripSettlement> settlements,
  ) {
    final paid = <String, int>{for (final p in people) p.id: 0};
    for (final pay in payments) {
      if (paid.containsKey(pay.personId)) {
        paid[pay.personId] = paid[pay.personId]! + pay.cents;
      }
    }
    final total = paid.values.fold<int>(0, (a, b) => a + b);
    final shares = equalShares(total, people.length);

    final result = <TripPersonSummary>[];
    for (var i = 0; i < people.length; i++) {
      final p = people[i];
      var balance = paid[p.id]! - shares[i];
      for (final s in settlements) {
        if (s.fromId == p.id) balance += s.cents; // they paid someone back
        if (s.toId == p.id) balance -= s.cents; // they were paid back
      }
      result.add(TripPersonSummary(
        person: p,
        paidCents: paid[p.id]!,
        shareCents: shares[i],
        balanceCents: balance,
      ));
    }
    return result;
  }

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

/// Parsed trip document (`trips/{id}`).
class Trip {
  final String id;
  final String title;
  final String currencyCode;
  final String ownerUid;
  final List<TripPerson> people;
  final List<TripPayment> payments;
  final List<TripSettlement> settlements;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Trip({
    required this.id,
    required this.title,
    required this.currencyCode,
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

  int get totalCents => payments.fold<int>(0, (a, b) => a + b.cents);

  List<TripPersonSummary> get summary =>
      TripMath.summarise(people, payments, settlements);

  List<TripTransfer> get plan => TripMath.settlePlan(summary);

  bool get isSettled => payments.isNotEmpty && plan.isEmpty;

  TripPerson? person(String id) => people.firstWhereOrNull((p) => p.id == id);

  String nameOf(String personId) => person(personId)?.name ?? 'Someone';
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
/// people[], payments[], settlements[], createdAt, updatedAt}.
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
    isLoading.value = true;
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
  Future<String> createTrip({required String title, required String currencyCode}) async {
    final uid = _uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw TripException('Please sign in again.');
    final name = title.trim();
    if (name.isEmpty) throw TripException('Give your trip a name.');
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
      if (!snap.exists) throw TripException('This trip no longer exists.');
      final data = Map<String, dynamic>.from(snap.data()!);
      for (final key in ['people', 'payments', 'settlements', 'memberUids']) {
        data[key] = List<dynamic>.from((data[key] as List?) ?? const []);
      }
      change(data);
      data['updatedAt'] = FieldValue.serverTimestamp();
      tx.update(ref, {
        'title': data['title'],
        'currencyCode': data['currencyCode'],
        'people': data['people'],
        'payments': data['payments'],
        'settlements': data['settlements'],
        'memberUids': data['memberUids'],
        'updatedAt': data['updatedAt'],
      });
    }).timeout(const Duration(seconds: 20));
  }

  Future<void> updateDetails(String tripId, {String? title, String? currencyCode}) =>
      _mutate(tripId, (d) {
        if (title != null) {
          if (title.trim().isEmpty) throw TripException('The name can\'t be empty.');
          d['title'] = title.trim();
        }
        if (currencyCode != null) d['currencyCode'] = currencyCode;
      });

  /// Adds people. Entries: {name, uid?, avatarUrl?}. Duplicate app users and
  /// exact duplicate names are skipped.
  Future<int> addPeople(String tripId, List<Map<String, dynamic>> entries) async {
    var added = 0;
    await _mutate(tripId, (d) {
      final people = (d['people'] as List).cast<Map>();
      final members = (d['memberUids'] as List).cast<String>();
      for (final e in entries) {
        final name = (e['name'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        final uid = e['uid']?.toString();
        final dup = people.any((p) =>
            (uid != null && p['uid'] == uid) ||
            (uid == null && p['uid'] == null &&
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

  /// Removes a person together with their payments and pay-backs.
  Future<void> removePerson(String tripId, String personId) => _mutate(tripId, (d) {
        final people = (d['people'] as List).cast<Map>();
        if (people.length <= 1) throw TripException('A trip needs at least one person.');
        final person = people.firstWhereOrNull((p) => p['id'] == personId);
        if (person == null) return;
        final uid = person['uid']?.toString();
        if (uid != null && uid == d['ownerUid']) {
          throw TripException('The trip\'s creator can\'t be removed.');
        }
        d['people'] = people.where((p) => p['id'] != personId).toList();
        d['payments'] =
            (d['payments'] as List).where((p) => p is Map && p['personId'] != personId).toList();
        d['settlements'] = (d['settlements'] as List)
            .where((s) => s is Map && s['fromId'] != personId && s['toId'] != personId)
            .toList();
        if (uid != null) {
          d['memberUids'] = (d['memberUids'] as List).where((m) => m != uid).toList();
        }
      });

  Future<void> addPayment(
    String tripId, {
    required String personId,
    required double amount,
    String note = '',
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
      ).toMap());
    });
  }

  Future<void> updatePayment(
    String tripId,
    String paymentId, {
    required String personId,
    required double amount,
    String note = '',
  }) {
    final cents = TripMath.toCents(amount);
    if (cents <= 0) throw TripException('Enter an amount above zero.');
    return _mutate(tripId, (d) {
      d['payments'] = (d['payments'] as List).map((p) {
        if (p is Map && p['id'] == paymentId) {
          return {...p, 'personId': personId, 'cents': cents, 'note': note.trim()};
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

  /// Plain-text summary for WhatsApp etc.
  static String shareText(Trip trip) {
    String money(int cents) => Fmt.money(cents / 100, currencyCode: trip.currencyCode);
    final b = StringBuffer()
      ..writeln('🧾 ${trip.title} — SplitShare')
      ..writeln('Total spent: ${money(trip.totalCents)}'
          ' · ${trip.people.length} people'
          ' · ${money(trip.people.isEmpty ? 0 : trip.totalCents ~/ trip.people.length)} each')
      ..writeln()
      ..writeln('Who paid what:');
    for (final s in trip.summary) {
      b.writeln('• ${s.person.name}: paid ${money(s.paidCents)}');
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

import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../core/feedback.dart';
import '../core/formatters.dart';
import 'auth_controller.dart';
import 'friend_controller.dart';
import 'notification_controller.dart';
import 'profile_controller.dart';

class ExpenseValidationException implements Exception {
  final String message;
  ExpenseValidationException(this.message);
  @override
  String toString() => message;
}

/// Owns all expense data and balance maths.
///
/// Firestore model (`expenses/{id}`):
/// ```
/// amount, description, category, date, notes, currencyCode,
/// type: 'expense' | 'payment',
/// paidBy: {uid, name},
/// splitType: 'Equally' | 'Percent' | 'Exact',
/// individualSplits: {uid: amountOwed},   // includes the payer's own share
/// involvedUsers: [uid],                  // used for queries + security rules
/// participantNames: {uid: name},
/// isSettled, settledPairs: ['uidA_uidB'],
/// createdBy, createdAt, updatedAt, groupId?, receiptUrl?
/// ```
///
/// Balance rule: every participant with a positive split (other than the
/// payer) owes the payer that amount, unless their pair is in `settledPairs`.
/// A *payment* is stored as an expense paid by the sender with the receiver's
/// split equal to the amount, which nets the debt down automatically.
class ExpenseController extends GetxController {
  static ExpenseController get to => Get.find();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _openSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _activitySub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _monthSub;
  Worker? _friendsWorker;
  Timer? _publishDebounce;
  String? _activeUid;

  /// All *unsettled* expenses involving the user (no limit — balances must
  /// account for every open debt, however old).
  final Map<String, Map<String, dynamic>> _openCache = {};
  final Map<String, String> _nameCache = {};

  static const int _activityPageSize = 30;
  int _activityLimit = _activityPageSize;

  // ---------- Reactive state ----------

  /// Open (unsettled) expenses, newest first.
  final openExpenses = <Map<String, dynamic>>[].obs;

  /// Most recent activity (settled and unsettled), newest first. Paginated.
  final recentActivity = <Map<String, dynamic>>[].obs;
  final hasMoreActivity = true.obs;
  final isLoadingMore = false.obs;

  /// Net balance per person per currency. Positive = they owe you.
  final balances = <String, Map<String, double>>{}.obs;

  /// Totals per currency, after netting each person's balance.
  final owedToMeByCurrency = <String, double>{}.obs;
  final iOweByCurrency = <String, double>{}.obs;

  /// The user's own share of expenses created this month (category totals
  /// are in the user's default currency only).
  final monthSpendByCurrency = <String, double>{}.obs;
  final monthSpendByCategory = <String, double>{}.obs;

  final isLoading = true.obs;
  final hasError = false.obs;

  /// UI-ready list for Settle Up / Friends: uid -> {uid, name, byCurrency}.
  final settleUpData = <String, Map<String, dynamic>>{}.obs;

  String? get currentUid => _activeUid ?? AuthController.instance.user?.uid;

  @override
  void onInit() {
    super.onInit();
    _bindFriendNames();
    if (Get.isRegistered<ProfileController>()) {
      _currencyWorker = ever(Get.find<ProfileController>().currencyCode, (_) => _computeMonth());
    }
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) {
        _activeUid = null;
        _cancelStreams();
        _clear();
        isLoading.value = false;
        return;
      }
      if (_activeUid == user.uid) return;
      _activeUid = user.uid;
      _subscribe(user.uid);
    });
  }

  @override
  void onClose() {
    _authSubscription?.cancel();
    _cancelStreams();
    _friendsWorker?.dispose();
    _currencyWorker?.dispose();
    _publishDebounce?.cancel();
    super.onClose();
  }

  void _cancelStreams() {
    _openSub?.cancel();
    _activitySub?.cancel();
    _monthSub?.cancel();
    _openSub = null;
    _activitySub = null;
    _monthSub = null;
  }

  void _clear() {
    _openCache.clear();
    openExpenses.clear();
    recentActivity.clear();
    balances.clear();
    owedToMeByCurrency.clear();
    iOweByCurrency.clear();
    monthSpendByCurrency.clear();
    monthSpendByCategory.clear();
    _monthDocs = const [];
    settleUpData.clear();
    _activityLimit = _activityPageSize;
    hasMoreActivity.value = true;
  }

  /// Re-subscribe all streams (pull-to-refresh / retry).
  Future<void> refreshData() async {
    final uid = currentUid;
    if (uid == null) return;
    _subscribe(uid);
    // Give the first snapshot a moment so the refresh indicator is meaningful.
    await Future.delayed(const Duration(milliseconds: 500));
  }

  void _subscribe(String uid) {
    _cancelStreams();
    isLoading.value = true;
    hasError.value = false;

    _openSub = _firestore
        .collection('expenses')
        .where('involvedUsers', arrayContains: uid)
        .where('isSettled', isEqualTo: false)
        .snapshots()
        .listen(
      (snap) {
        for (final change in snap.docChanges) {
          if (change.type == DocumentChangeType.removed) {
            _openCache.remove(change.doc.id);
          } else {
            final data = change.doc.data();
            if (data != null) {
              _openCache[change.doc.id] = {...data, 'id': change.doc.id};
              _rememberNames(data);
            }
          }
        }
        isLoading.value = false;
        _schedulePublish();
      },
      onError: (Object e) {
        debugPrint('Open expenses stream error: $e');
        hasError.value = true;
        isLoading.value = false;
      },
    );

    _listenActivity(uid);
    _listenMonth(uid);
  }

  void _listenActivity(String uid) {
    _activitySub?.cancel();
    _activitySub = _firestore
        .collection('expenses')
        .where('involvedUsers', arrayContains: uid)
        .orderBy('createdAt', descending: true)
        .limit(_activityLimit)
        .snapshots()
        .listen(
      (snap) {
        final list = snap.docs.map((d) {
          final data = d.data();
          _rememberNames(data);
          return {...data, 'id': d.id};
        }).toList();
        recentActivity.value = list;
        hasMoreActivity.value = list.length >= _activityLimit;
        isLoadingMore.value = false;
      },
      onError: (Object e) {
        debugPrint('Activity stream error: $e');
        isLoadingMore.value = false;
      },
    );
  }

  void _listenMonth(String uid) {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);
    _monthSub?.cancel();
    _monthSub = _firestore
        .collection('expenses')
        .where('involvedUsers', arrayContains: uid)
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(
      (snap) {
        _monthDocs = snap.docs.map((d) => d.data()).toList();
        _computeMonth();
      },
      onError: (Object e) => debugPrint('Month stream error: $e'),
    );
  }

  List<Map<String, dynamic>> _monthDocs = const [];
  Worker? _currencyWorker;

  /// Month totals. Category breakdown only counts the user's default
  /// currency so the proportions are never mixing currencies.
  void _computeMonth() {
    final uid = currentUid;
    if (uid == null) return;
    final preferred = Get.isRegistered<ProfileController>()
        ? Get.find<ProfileController>().currencyCode.value
        : 'USD';
    final byCurrency = <String, double>{};
    final byCategory = <String, double>{};
    for (final e in _monthDocs) {
      if (isPayment(e)) continue;
      final share = _num(Map<String, dynamic>.from(e['individualSplits'] ?? {})[uid]);
      if (share <= 0) continue;
      final cur = (e['currencyCode'] ?? 'USD').toString();
      byCurrency[cur] = (byCurrency[cur] ?? 0) + share;
      if (cur != preferred) continue;
      final cat = (e['category'] ?? 'Other').toString();
      byCategory[cat] = (byCategory[cat] ?? 0) + share;
    }
    monthSpendByCurrency.value = byCurrency;
    monthSpendByCategory.value = byCategory;
  }

  /// Loads the next page of activity.
  void loadMoreActivity() {
    final uid = currentUid;
    if (uid == null || isLoadingMore.value || !hasMoreActivity.value) return;
    isLoadingMore.value = true;
    _activityLimit += _activityPageSize;
    _listenActivity(uid);
  }

  // ---------- Names ----------

  void _bindFriendNames() {
    if (!Get.isRegistered<FriendController>()) return;
    final fc = Get.find<FriendController>();
    void rebuild() {
      for (final f in fc.friends) {
        final uid = f['uid']?.toString();
        if (uid != null) _nameCache[uid] = (f['name'] ?? uid).toString();
      }
    }

    rebuild();
    _friendsWorker = ever(fc.friends, (_) {
      rebuild();
      _schedulePublish();
    });
  }

  void _rememberNames(Map<String, dynamic> e) {
    final names = e['participantNames'];
    if (names is Map) {
      names.forEach((k, v) {
        if (v != null && v.toString().isNotEmpty) {
          _nameCache.putIfAbsent(k.toString(), () => v.toString());
        }
      });
    }
    final paidBy = e['paidBy'];
    if (paidBy is Map && paidBy['uid'] != null && paidBy['name'] != null) {
      _nameCache.putIfAbsent(paidBy['uid'].toString(), () => paidBy['name'].toString());
    }
  }

  /// Best known display name for [uid] ("You" for the current user).
  String nameFor(String uid) {
    if (uid == currentUid) return 'You';
    return _nameCache[uid] ?? 'Unknown';
  }

  // ---------- Balance maths ----------

  static double _num(dynamic v) => v is num ? v.toDouble() : 0.0;

  static bool isPayment(Map<String, dynamic> e) => e['type'] == 'payment';

  static String pairKey(String a, String b) {
    final s = [a, b]..sort();
    return '${s[0]}_${s[1]}';
  }

  static bool _pairSettled(Map<String, dynamic> e, String a, String b) {
    if (e['isSettled'] == true) return true;
    final pairs = (e['settledPairs'] as List?)?.map((x) => x.toString()) ?? const [];
    return pairs.contains(pairKey(a, b));
  }

  static String payerOf(Map<String, dynamic> e) {
    final p = e['paidBy'];
    return p is Map ? (p['uid']?.toString() ?? '') : '';
  }

  /// Net effect of a single expense for [me], per counterparty.
  /// Positive = that person owes me.
  static Map<String, double> netForExpense(Map<String, dynamic> e, String me) {
    final result = <String, double>{};
    if (e['isSettled'] == true) return result;
    final payer = payerOf(e);
    if (payer.isEmpty) return result;
    final splits = Map<String, dynamic>.from(e['individualSplits'] ?? {});

    if (payer == me) {
      splits.forEach((uid, amount) {
        if (uid == me) return;
        final amt = _num(amount);
        if (amt <= 0 || _pairSettled(e, me, uid)) return;
        result[uid] = (result[uid] ?? 0) + amt;
      });
    } else if (splits.containsKey(me) && !_pairSettled(e, me, payer)) {
      final mine = _num(splits[me]);
      if (mine > 0) result[payer] = (result[payer] ?? 0) - mine;
    }
    return result;
  }

  /// The current user's net position on one expense (positive = owed to you).
  double myNetOn(Map<String, dynamic> e) {
    final me = currentUid;
    if (me == null) return 0;
    return netForExpense(e, me).values.fold(0.0, (a, b) => a + b);
  }

  void _schedulePublish() {
    _publishDebounce?.cancel();
    _publishDebounce = Timer(const Duration(milliseconds: 16), _publish);
  }

  void _publish() {
    final me = currentUid;
    if (me == null) return;

    final open = _openCache.values.toList()..sort(_byCreatedDesc);
    openExpenses.value = open;

    final net = <String, Map<String, double>>{};
    for (final e in open) {
      final cur = (e['currencyCode'] ?? 'USD').toString();
      netForExpense(e, me).forEach((uid, amt) {
        final m = net.putIfAbsent(uid, () => <String, double>{});
        m[cur] = (m[cur] ?? 0) + amt;
      });
    }
    // Drop rounding dust.
    for (final m in net.values) {
      m.removeWhere((_, v) => v.abs() < 0.005);
    }
    net.removeWhere((_, m) => m.isEmpty);
    balances.value = net;

    final owed = <String, double>{};
    final owe = <String, double>{};
    net.forEach((_, m) {
      m.forEach((cur, v) {
        if (v > 0) {
          owed[cur] = (owed[cur] ?? 0) + v;
        } else {
          owe[cur] = (owe[cur] ?? 0) - v;
        }
      });
    });
    owedToMeByCurrency.value = owed;
    iOweByCurrency.value = owe;

    settleUpData.value = {
      for (final entry in net.entries)
        entry.key: {
          'uid': entry.key,
          'name': nameFor(entry.key),
          'avatarUrl': _avatarFor(entry.key),
          'byCurrency': entry.value,
        },
    };
  }

  String _avatarFor(String uid) {
    if (!Get.isRegistered<FriendController>()) return '';
    final f = Get.find<FriendController>()
        .friends
        .firstWhereOrNull((f) => f['uid'] == uid);
    return (f?['avatarUrl'] ?? '').toString();
  }

  static int _byCreatedDesc(Map<String, dynamic> a, Map<String, dynamic> b) {
    final at = Fmt.toDate(a['createdAt']);
    final bt = Fmt.toDate(b['createdAt']);
    if (at == null && bt == null) return 0;
    if (at == null) return -1; // pending server timestamp = newest
    if (bt == null) return 1;
    return bt.compareTo(at);
  }

  /// Net balance with one person (per currency). Positive = they owe you.
  Map<String, double> balanceWith(String uid) =>
      Map<String, double>.from(balances[uid] ?? const {});

  /// The user's net position inside a group (per currency).
  Map<String, double> groupBalance(String groupId) {
    final me = currentUid;
    final result = <String, double>{};
    if (me == null) return result;
    for (final e in _openCache.values) {
      if (e['groupId'] != groupId) continue;
      final cur = (e['currencyCode'] ?? 'USD').toString();
      final n = netForExpense(e, me).values.fold(0.0, (a, b) => a + b);
      result[cur] = (result[cur] ?? 0) + n;
    }
    result.removeWhere((_, v) => v.abs() < 0.005);
    return result;
  }

  /// Per-member balances with the current user inside a group.
  Map<String, Map<String, double>> groupMemberBalances(String groupId) {
    final me = currentUid;
    final result = <String, Map<String, double>>{};
    if (me == null) return result;
    for (final e in _openCache.values) {
      if (e['groupId'] != groupId) continue;
      final cur = (e['currencyCode'] ?? 'USD').toString();
      netForExpense(e, me).forEach((uid, amt) {
        final m = result.putIfAbsent(uid, () => {});
        m[cur] = (m[cur] ?? 0) + amt;
      });
    }
    for (final m in result.values) {
      m.removeWhere((_, v) => v.abs() < 0.005);
    }
    result.removeWhere((_, m) => m.isEmpty);
    return result;
  }

  /// Back-compat helper used by older UI: single-currency summary.
  Map<String, dynamic> groupBalanceForUser(String groupId, String _) {
    final m = groupBalance(groupId);
    final total = m.values.fold(0.0, (a, b) => a + b);
    return {'balance': total.abs(), 'isPositive': total >= 0, 'byCurrency': m};
  }

  // ---------- Streams for detail screens ----------

  /// Live list of a group's expenses visible to the user.
  Stream<List<Map<String, dynamic>>> groupExpensesStream(String groupId) {
    final uid = currentUid;
    if (uid == null) return Stream.value(const []);
    return _firestore
        .collection('expenses')
        .where('involvedUsers', arrayContains: uid)
        .where('groupId', isEqualTo: groupId)
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots()
        .map((s) => s.docs.map((d) => {...d.data(), 'id': d.id}).toList());
  }

  /// Live list of expenses shared between the user and one friend.
  Stream<List<Map<String, dynamic>>> sharedWithStream(String friendUid) {
    final uid = currentUid;
    if (uid == null) return Stream.value(const []);
    return _firestore
        .collection('expenses')
        .where('involvedUsers', arrayContains: uid)
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots()
        .map((s) => s.docs
            .map((d) => {...d.data(), 'id': d.id})
            .where((e) =>
                (e['involvedUsers'] as List?)?.contains(friendUid) ?? false)
            .toList());
  }

  /// Live single expense (null if deleted / not accessible).
  Stream<Map<String, dynamic>?> expenseStream(String id) {
    return _firestore.collection('expenses').doc(id).snapshots().map(
          (d) => d.exists ? {...d.data()!, 'id': d.id} : null,
        );
  }

  // ---------- Create / edit / delete ----------

  /// Splits [amount] in cents so the parts always sum exactly to [amount].
  @visibleForTesting
  static Map<String, double> distribute(
    double amount,
    List<String> uids,
    List<double> weights,
  ) {
    final totalCents = (amount * 100).round();
    final weightSum = weights.fold(0.0, (a, b) => a + b);
    final cents = <int>[];
    for (final w in weights) {
      cents.add(weightSum == 0 ? 0 : (totalCents * w / weightSum).floor());
    }
    var remainder = totalCents - cents.fold<int>(0, (a, b) => a + b);
    var i = 0;
    while (remainder > 0 && uids.isNotEmpty) {
      if (weights[i % uids.length] > 0) {
        cents[i % uids.length]++;
        remainder--;
      }
      i++;
      if (i > uids.length * 4 && remainder > 0) {
        cents[0] += remainder; // safety net
        break;
      }
    }
    return {
      for (var k = 0; k < uids.length; k++) uids[k]: cents[k] / 100.0,
    };
  }

  /// Validates input and builds the Firestore payload.
  Map<String, dynamic> _buildExpense({
    required String amountText,
    required String description,
    required String category,
    required DateTime date,
    required Map<String, dynamic> paidByUser,
    required String splitType,
    required String notes,
    required List<Map<String, dynamic>> splitWith,
    required Map<String, double> splitValuesByUid,
    required String currencyCode,
    String? groupId,
  }) {
    final amount = double.tryParse(amountText.trim());
    if (amount == null || amount <= 0) {
      throw ExpenseValidationException('Please enter a valid amount');
    }
    if (amount > 10000000) {
      throw ExpenseValidationException('That amount is too large');
    }
    final desc = description.trim();
    if (desc.isEmpty) {
      throw ExpenseValidationException('Please enter a description');
    }
    final me = currentUid;
    if (me == null || me.isEmpty) {
      throw ExpenseValidationException('Please sign in before adding an expense');
    }
    final payerUid = paidByUser['uid']?.toString() ?? me;

    // Participants: me + everyone selected (+ payer).
    final names = <String, String>{};
    final myName = Get.isRegistered<ProfileController>()
        ? Get.find<ProfileController>().name.value
        : '';
    names[me] = myName.isNotEmpty ? myName : 'Someone';
    final participants = <String>[me];
    for (final p in splitWith) {
      final uid = p['uid']?.toString();
      if (uid == null || uid.isEmpty || participants.contains(uid)) continue;
      participants.add(uid);
      names[uid] = (p['name'] ?? nameFor(uid)).toString();
    }
    if (!participants.contains(payerUid)) {
      participants.add(payerUid);
    }
    if (payerUid != me) {
      final payerName = paidByUser['name']?.toString();
      names[payerUid] = (payerName == null || payerName == 'You')
          ? nameFor(payerUid)
          : payerName;
    }
    if (participants.length < 2) {
      throw ExpenseValidationException('Add at least one person to split with');
    }

    Map<String, double> splits;
    if (splitType == 'Percent') {
      final total = splitValuesByUid.values.fold(0.0, (a, b) => a + b);
      if ((total - 100).abs() > 0.01) {
        throw ExpenseValidationException(
            'Percentages must add up to 100% (currently ${total.toStringAsFixed(1)}%)');
      }
      if (splitValuesByUid.values.any((v) => v < 0)) {
        throw ExpenseValidationException('Percentages can\'t be negative');
      }
      final uids = participants;
      splits = distribute(
        amount,
        uids,
        uids.map((u) => splitValuesByUid[u] ?? 0).toList(),
      );
    } else if (splitType == 'Exact') {
      final total = splitValuesByUid.values.fold(0.0, (a, b) => a + b);
      if ((total - amount).abs() > 0.01) {
        throw ExpenseValidationException(
            'Split amounts must add up to ${Fmt.money(amount, currencyCode: currencyCode)} '
            '(currently ${Fmt.money(total, currencyCode: currencyCode)})');
      }
      if (splitValuesByUid.values.any((v) => v < 0)) {
        throw ExpenseValidationException('Amounts can\'t be negative');
      }
      splits = {
        for (final u in participants)
          u: double.parse((splitValuesByUid[u] ?? 0).toStringAsFixed(2)),
      };
    } else {
      // Equally between everyone selected (payer included only if selected,
      // or if the payer is me — "I paid and split with X" means both share).
      final sharers = participants
          .where((u) => u == me || splitWith.any((p) => p['uid'] == u))
          .toList();
      splits = distribute(amount, sharers, List.filled(sharers.length, 1.0));
      for (final u in participants) {
        splits.putIfAbsent(u, () => 0.0);
      }
    }

    if (!splits.entries.any((e) => e.key != payerUid && e.value > 0)) {
      throw ExpenseValidationException(
          'Nobody owes anything with this split — check who paid and who shares it');
    }

    final data = <String, dynamic>{
      'amount': amount,
      'description': desc,
      'category': category,
      'date': Timestamp.fromDate(date),
      'paidBy': {'uid': payerUid, 'name': names[payerUid] ?? 'Unknown'},
      'splitType': splitType,
      'notes': notes.trim(),
      'individualSplits': splits,
      'involvedUsers': participants,
      'participantNames': names,
      'currencyCode': currencyCode,
      'type': 'expense',
    };
    if (groupId != null && groupId.isNotEmpty) data['groupId'] = groupId;
    return data;
  }

  /// Creates a new expense. Throws [ExpenseValidationException] on bad input.
  Future<String> addExpenseFromInput({
    required String amountText,
    required String description,
    required String category,
    required DateTime date,
    required Map<String, dynamic> paidByUser,
    required String splitType,
    required String notes,
    required List<Map<String, dynamic>> splitWith,
    required Map<String, double> splitValuesByUid,
    required String currencyCode,
    String? groupId,
    File? receiptFile,
  }) async {
    final data = _buildExpense(
      amountText: amountText,
      description: description,
      category: category,
      date: date,
      paidByUser: paidByUser,
      splitType: splitType,
      notes: notes,
      splitWith: splitWith,
      splitValuesByUid: splitValuesByUid,
      currencyCode: currencyCode,
      groupId: groupId,
    );
    data.addAll({
      'isSettled': false,
      'settledPairs': <String>[],
      'createdBy': currentUid,
      'createdAt': FieldValue.serverTimestamp(),
    });

    final ref = await _firestore
        .collection('expenses')
        .add(data)
        .timeout(const Duration(seconds: 20));

    if (receiptFile != null) {
      final url = await _uploadReceipt(ref.id, receiptFile);
      if (url != null) await ref.update({'receiptUrl': url});
    }

    if (groupId != null && groupId.isNotEmpty) {
      unawaited(_firestore
          .collection('groups')
          .doc(groupId)
          .update({'lastActive': FieldValue.serverTimestamp()})
          .catchError((Object e) => debugPrint('lastActive update failed: $e')));
    }

    unawaited(_notifyParticipants(
      data,
      title: 'New expense',
      verb: 'added',
      expenseId: ref.id,
    ));
    return ref.id;
  }

  /// Edits an existing expense (creator only — enforced by security rules).
  Future<void> updateExpenseFromInput({
    required String expenseId,
    required String amountText,
    required String description,
    required String category,
    required DateTime date,
    required Map<String, dynamic> paidByUser,
    required String splitType,
    required String notes,
    required List<Map<String, dynamic>> splitWith,
    required Map<String, double> splitValuesByUid,
    required String currencyCode,
    String? groupId,
    File? receiptFile,
    bool removeReceipt = false,
  }) async {
    final data = _buildExpense(
      amountText: amountText,
      description: description,
      category: category,
      date: date,
      paidByUser: paidByUser,
      splitType: splitType,
      notes: notes,
      splitWith: splitWith,
      splitValuesByUid: splitValuesByUid,
      currencyCode: currencyCode,
      groupId: groupId,
    );
    data['updatedAt'] = FieldValue.serverTimestamp();
    // Editing resets settlement state for the changed split.
    data['settledPairs'] = <String>[];
    data['isSettled'] = false;
    if (groupId == null || groupId.isEmpty) data['groupId'] = FieldValue.delete();
    if (removeReceipt && receiptFile == null) data['receiptUrl'] = FieldValue.delete();

    final ref = _firestore.collection('expenses').doc(expenseId);
    await ref.update(data).timeout(const Duration(seconds: 20));

    if (receiptFile != null) {
      final url = await _uploadReceipt(expenseId, receiptFile);
      if (url != null) await ref.update({'receiptUrl': url});
    } else if (removeReceipt) {
      unawaited(FirebaseStorage.instance
          .ref('receipts/$expenseId.jpg')
          .delete()
          .catchError((Object e) => debugPrint('Receipt delete failed: $e')));
    }

    unawaited(_notifyParticipants(
      data,
      title: 'Expense updated',
      verb: 'updated',
      expenseId: expenseId,
    ));
  }

  /// Deletes an expense and its receipt (creator only).
  Future<void> deleteExpense(Map<String, dynamic> expense) async {
    final id = expense['id']?.toString();
    if (id == null) return;
    await _firestore.collection('expenses').doc(id).delete();
    _openCache.remove(id);
    _schedulePublish();
    if ((expense['receiptUrl'] ?? '').toString().isNotEmpty) {
      unawaited(FirebaseStorage.instance
          .ref('receipts/$id.jpg')
          .delete()
          .catchError((Object e) => debugPrint('Receipt delete failed: $e')));
    }
    unawaited(_notifyParticipants(
      expense,
      title: 'Expense deleted',
      verb: 'deleted',
      expenseId: null,
    ));
  }

  /// Whether the current user may edit/delete [expense].
  bool canModify(Map<String, dynamic> expense) {
    final me = currentUid;
    if (me == null) return false;
    final creator = expense['createdBy']?.toString() ?? payerOf(expense);
    return creator == me;
  }

  Future<String?> _uploadReceipt(String expenseId, File file) async {
    try {
      final ref = FirebaseStorage.instance.ref('receipts/$expenseId.jpg');
      await ref
          .putFile(file, SettableMetadata(contentType: 'image/jpeg'))
          .timeout(const Duration(seconds: 60));
      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('Receipt upload failed: $e');
      AppToast.warning(
        'The expense was saved, but the receipt photo could not be uploaded. '
        'You can add it again by editing the expense.',
        title: 'Receipt not uploaded',
      );
      return null;
    }
  }

  // ---------- Payments & settling ----------

  /// Records a (possibly partial) payment.
  ///
  /// If [iPaid] is true the current user sent [amount] to [friendUid];
  /// otherwise the friend paid the current user.
  Future<void> recordPayment({
    required String friendUid,
    required String friendName,
    required double amount,
    required String currencyCode,
    required bool iPaid,
    String note = '',
    String? groupId,
  }) async {
    final me = currentUid;
    if (me == null) throw ExpenseValidationException('Please sign in again');
    if (amount <= 0) throw ExpenseValidationException('Enter an amount above zero');

    final myName = _myName();
    final payer = iPaid ? me : friendUid;
    final receiver = iPaid ? friendUid : me;
    final names = {me: myName, friendUid: friendName};

    final data = <String, dynamic>{
      'type': 'payment',
      'amount': double.parse(amount.toStringAsFixed(2)),
      'description': iPaid
          ? '$myName paid $friendName'
          : '$friendName paid $myName',
      'category': 'Payment',
      'date': Timestamp.now(),
      'paidBy': {'uid': payer, 'name': names[payer]},
      'splitType': 'Exact',
      'notes': note.trim(),
      'individualSplits': {
        receiver: double.parse(amount.toStringAsFixed(2)),
        payer: 0.0,
      },
      'involvedUsers': [me, friendUid],
      'participantNames': names,
      'currencyCode': currencyCode,
      'isSettled': false,
      'settledPairs': <String>[],
      'createdBy': me,
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (groupId != null && groupId.isNotEmpty) data['groupId'] = groupId;

    await _firestore.collection('expenses').add(data).timeout(const Duration(seconds: 20));

    unawaited(NotificationController.createNotification(
      targetUid: friendUid,
      title: 'Payment recorded',
      message: iPaid
          ? '$myName recorded a payment of ${Fmt.money(amount, currencyCode: currencyCode)} to you.'
          : '$myName confirmed you paid ${Fmt.money(amount, currencyCode: currencyCode)}.',
      type: 'payment',
      iconName: 'payment',
      iconColor: 0xFF10B981,
      data: {'fromUid': me},
    ));
  }

  /// Fully settles everything between the user and [friendUid] (all currencies).
  ///
  /// Marks every open expense between the two as settled for that pair and
  /// writes a settled payment record per currency so it shows in history.
  Future<int> settleUpWithFriend(String friendUid) async {
    final me = currentUid;
    if (me == null) return 0;

    final before = balanceWith(friendUid);
    final pair = pairKey(me, friendUid);
    final batch = _firestore.batch();
    var count = 0;

    for (final e in _openCache.values) {
      final payer = payerOf(e);
      if (payer != me && payer != friendUid) continue;
      final splits = Map<String, dynamic>.from(e['individualSplits'] ?? {});
      final other = payer == me ? friendUid : me;
      if (_num(splits[other]) <= 0) continue;
      if (_pairSettled(e, me, friendUid)) continue;

      final pairs = (e['settledPairs'] as List?)?.map((x) => x.toString()).toList() ?? [];
      pairs.add(pair);

      // Fully settled when every debtor has settled with the payer.
      final debtors = splits.entries
          .where((s) => s.key != payer && _num(s.value) > 0)
          .map((s) => s.key);
      final allDone = debtors.every((d) => pairs.contains(pairKey(d, payer)));

      batch.update(_firestore.collection('expenses').doc(e['id'].toString()), {
        'settledPairs': pairs,
        if (allDone) 'isSettled': true,
      });
      count++;
    }

    if (count == 0) return 0;

    // History records (already settled, so they don't affect balances).
    final myName = _myName();
    final friendName = nameFor(friendUid);
    before.forEach((cur, net) {
      if (net.abs() < 0.005) return;
      final iPaid = net < 0; // I owed them
      final payer = iPaid ? me : friendUid;
      final receiver = iPaid ? friendUid : me;
      batch.set(_firestore.collection('expenses').doc(), {
        'type': 'payment',
        'amount': double.parse(net.abs().toStringAsFixed(2)),
        'description': iPaid
            ? '$myName settled up with $friendName'
            : '$friendName settled up with $myName',
        'category': 'Payment',
        'date': Timestamp.now(),
        'paidBy': {'uid': payer, 'name': payer == me ? myName : friendName},
        'splitType': 'Exact',
        'notes': '',
        'individualSplits': {receiver: double.parse(net.abs().toStringAsFixed(2)), payer: 0.0},
        'involvedUsers': [me, friendUid],
        'participantNames': {me: myName, friendUid: friendName},
        'currencyCode': cur,
        'isSettled': true,
        'settledPairs': [pair],
        'createdBy': me,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });

    await batch.commit().timeout(const Duration(seconds: 30));

    unawaited(NotificationController.createNotification(
      targetUid: friendUid,
      title: 'Settled up',
      message: '$myName marked all your shared expenses as settled.',
      type: 'payment',
      iconName: 'check_circle',
      iconColor: 0xFF10B981,
      data: {'fromUid': me},
    ));
    return count;
  }

  /// Sends a payment reminder notification to a friend who owes the user.
  Future<void> sendReminder(String friendUid) async {
    final me = currentUid;
    if (me == null) return;
    final owed = balanceWith(friendUid)..removeWhere((_, v) => v <= 0);
    if (owed.isEmpty) {
      throw ExpenseValidationException('${nameFor(friendUid)} doesn\'t owe you anything');
    }
    await NotificationController.createNotification(
      targetUid: friendUid,
      title: 'Payment reminder',
      message: '${_myName()} reminded you that you owe ${Fmt.multi(owed)}.',
      type: 'reminder',
      iconName: 'warning_amber_rounded',
      iconColor: 0xFFF59E0B,
      data: {'fromUid': me},
    );
  }

  String _myName() {
    var n = Get.isRegistered<ProfileController>()
        ? Get.find<ProfileController>().name.value
        : '';
    if (n.isEmpty) n = AuthController.instance.user?.displayName ?? 'Someone';
    return n;
  }

  Future<void> _notifyParticipants(
    Map<String, dynamic> e, {
    required String title,
    required String verb,
    required String? expenseId,
  }) async {
    final me = currentUid;
    if (me == null) return;
    final users = (e['involvedUsers'] as List?)?.map((x) => x.toString()) ?? const [];
    final amount = _num(e['amount']);
    final cur = (e['currencyCode'] ?? 'USD').toString();
    final desc = (e['description'] ?? 'an expense').toString();
    final myName = _myName();
    await Future.wait(users.where((u) => u != me).map((u) {
      return NotificationController.createNotification(
        targetUid: u,
        title: title,
        message: '$myName $verb "$desc" (${Fmt.money(amount, currencyCode: cur)}).',
        type: 'expense',
        iconName: 'receipt_long',
        iconColor: 0xFF4F46E5,
        data: {
          'fromUid': me,
          'expenseId': ?expenseId,
        },
      ).catchError((Object err) => debugPrint('Notify failed: $err'));
    }));
  }
}

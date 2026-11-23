import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'auth_controller.dart';
import 'expense_controller.dart';
import 'notification_controller.dart';
import 'profile_controller.dart';

class GroupException implements Exception {
  final String message;
  GroupException(this.message);
  @override
  String toString() => message;
}

/// Groups (`groups/{id}`): name, icon (group type), members[], memberDetails[],
/// createdBy, createdAt, lastActive, currencyCode.
class GroupController extends GetxController {
  static GroupController get to => Get.find();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _groupsSubscription;
  String? _activeUid;

  final groups = <Map<String, dynamic>>[].obs;
  final isLoading = true.obs;
  final hasError = false.obs;

  @override
  void onInit() {
    super.onInit();
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) {
        _activeUid = null;
        _groupsSubscription?.cancel();
        groups.clear();
        isLoading.value = false;
        return;
      }
      if (_activeUid == user.uid) return;
      _activeUid = user.uid;
      fetchGroups();
    });
  }

  @override
  void onClose() {
    _authSubscription?.cancel();
    _groupsSubscription?.cancel();
    super.onClose();
  }

  String? get _uid => _activeUid ?? AuthController.instance.user?.uid;

  void fetchGroups() {
    final uid = _uid;
    if (uid == null) {
      isLoading.value = false;
      return;
    }
    isLoading.value = true;
    hasError.value = false;
    _groupsSubscription?.cancel();
    _groupsSubscription = _firestore
        .collection('groups')
        .where('members', arrayContains: uid)
        .snapshots()
        .listen((snapshot) {
      final list = snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();
      list.sort((a, b) {
        final at = a['lastActive'] ?? a['createdAt'];
        final bt = b['lastActive'] ?? b['createdAt'];
        if (at is Timestamp && bt is Timestamp) return bt.compareTo(at);
        if (at == null) return -1;
        if (bt == null) return 1;
        return 0;
      });
      groups.value = list;
      isLoading.value = false;
    }, onError: (Object e) {
      debugPrint('Groups stream error: $e');
      hasError.value = true;
      isLoading.value = false;
    });
  }

  Map<String, dynamic>? groupById(String id) =>
      groups.firstWhereOrNull((g) => g['id'] == id);

  /// Live group document.
  Stream<Map<String, dynamic>?> groupStream(String id) => _firestore
      .collection('groups')
      .doc(id)
      .snapshots()
      .map((d) => d.exists ? {...d.data()!, 'id': d.id} : null);

  /// Member preview list for a group (from denormalised `memberDetails`).
  static List<Map<String, dynamic>> membersOf(Map<String, dynamic> group) {
    final details = group['memberDetails'];
    final uids = (group['members'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final byUid = <String, Map<String, dynamic>>{};
    if (details is List) {
      for (final d in details) {
        if (d is Map && d['uid'] != null) {
          byUid[d['uid'].toString()] = Map<String, dynamic>.from(d);
        }
      }
    }
    return uids
        .map((u) => byUid[u] ?? {'uid': u, 'name': 'Member', 'email': '', 'avatarUrl': ''})
        .toList();
  }

  /// Creates a group. Returns its id. Throws [GroupException] on failure.
  Future<String> createGroup(
    String name,
    List<String> memberUids,
    Map<String, dynamic> groupDetails, {
    double? initialAmount,
    String splitMethod = 'Equally',
  }) async {
    final uid = _uid;
    if (uid == null) throw GroupException('Please sign in again.');
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw GroupException('Give your group a name.');

    final members = {...memberUids, uid}.toList();
    final memberDetails = await _loadMemberDetails(members);
    final currency = groupDetails['currencyCode']?.toString() ?? 'USD';

    final docRef = await _firestore.collection('groups').add({
      'name': trimmed,
      'members': members,
      'memberDetails': memberDetails,
      'createdBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
      'lastActive': FieldValue.serverTimestamp(),
      'icon': groupDetails['icon'] ?? 'Other',
      'currencyCode': currency,
    }).timeout(const Duration(seconds: 20));

    if (initialAmount != null && initialAmount > 0 && members.length > 1) {
      await Get.find<ExpenseController>().addExpenseFromInput(
        amountText: initialAmount.toStringAsFixed(2),
        description: 'Initial group expense',
        category: 'Other',
        date: DateTime.now(),
        paidByUser: {'uid': uid, 'name': 'You'},
        splitType: 'Equally',
        notes: '',
        splitWith: memberDetails.where((m) => m['uid'] != uid).toList(),
        splitValuesByUid: const {},
        currencyCode: currency,
        groupId: docRef.id,
      );
    }

    _notifyAdded(members.where((m) => m != uid), trimmed, docRef.id);
    return docRef.id;
  }

  /// Renames / restyles a group.
  Future<void> updateGroup(
    String groupId, {
    String? name,
    String? icon,
    String? currencyCode,
  }) async {
    final updates = <String, dynamic>{};
    if (name != null) {
      if (name.trim().isEmpty) throw GroupException('Group name can\'t be empty.');
      updates['name'] = name.trim();
    }
    if (icon != null) updates['icon'] = icon;
    if (currencyCode != null) updates['currencyCode'] = currencyCode;
    if (updates.isEmpty) return;
    updates['lastActive'] = FieldValue.serverTimestamp();
    await _firestore.collection('groups').doc(groupId).update(updates);
  }

  /// Adds members to an existing group.
  Future<void> addMembers(String groupId, List<String> newUids) async {
    if (newUids.isEmpty) return;
    final doc = await _firestore.collection('groups').doc(groupId).get();
    if (!doc.exists) throw GroupException('This group no longer exists.');
    final data = doc.data()!;
    final current = (data['members'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final toAdd = newUids.where((u) => !current.contains(u)).toList();
    if (toAdd.isEmpty) return;
    final details = await _loadMemberDetails(toAdd);
    await doc.reference.update({
      'members': FieldValue.arrayUnion(toAdd),
      'memberDetails': FieldValue.arrayUnion(details),
      'lastActive': FieldValue.serverTimestamp(),
    });
    _notifyAdded(toAdd, (data['name'] ?? 'a group').toString(), groupId);
  }

  /// Leaves a group. Refuses while the user still has an open balance in it.
  Future<void> leaveGroup(String groupId) async {
    final uid = _uid;
    if (uid == null) return;
    final balance = Get.find<ExpenseController>().groupBalance(groupId);
    if (balance.isNotEmpty) {
      throw GroupException('Settle your balance in this group before leaving.');
    }
    final doc = await _firestore.collection('groups').doc(groupId).get();
    if (!doc.exists) return;
    final details = (doc.data()!['memberDetails'] as List?) ?? [];
    final mine = details.where((d) => d is Map && d['uid'] == uid).toList();
    await doc.reference.update({
      'members': FieldValue.arrayRemove([uid]),
      if (mine.isNotEmpty) 'memberDetails': FieldValue.arrayRemove(mine),
    });
  }

  /// Deletes a group (creator only). Expenses stay in members' history.
  Future<void> deleteGroup(String groupId) async {
    await _firestore.collection('groups').doc(groupId).delete();
  }

  bool isCreator(Map<String, dynamic> group) => group['createdBy'] == _uid;

  void _notifyAdded(Iterable<String> uids, String groupName, String groupId) {
    final me = Get.isRegistered<ProfileController>()
        ? Get.find<ProfileController>().name.value
        : 'Someone';
    for (final u in uids) {
      unawaited(NotificationController.createNotification(
        targetUid: u,
        title: 'Added to a group',
        message: '${me.isEmpty ? 'Someone' : me} added you to "$groupName".',
        type: 'group',
        iconName: 'group_add',
        iconColor: 0xFF0EA5E9,
        data: {'groupId': groupId},
      ));
    }
  }

  Future<List<Map<String, dynamic>>> _loadMemberDetails(List<String> uids) async {
    final details = <String, Map<String, dynamic>>{};
    for (var start = 0; start < uids.length; start += 30) {
      final end = start + 30 > uids.length ? uids.length : start + 30;
      final chunk = uids.sublist(start, end);
      final snapshot = await _firestore
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snapshot.docs) {
        final data = doc.data();
        details[doc.id] = {
          'uid': doc.id,
          'name': data['name'] ?? 'Unknown',
          'email': data['email'] ?? '',
          'avatarUrl': data['avatarUrl'] ?? '',
        };
      }
    }
    return uids
        .map((u) => details[u] ?? {'uid': u, 'name': 'Unknown', 'email': '', 'avatarUrl': ''})
        .toList();
  }
}

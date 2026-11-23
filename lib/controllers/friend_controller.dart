import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../core/feedback.dart';
import 'auth_controller.dart';
import 'notification_controller.dart';

/// Friends (`users/{uid}/friends`) and friend requests
/// (`users/{target}/friendRequests/{senderUid}`).
class FriendController extends GetxController {
  static FriendController get to => Get.find();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _friendsSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _requestsSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sentSubscription;
  String? _activeUid;

  final friends = <Map<String, dynamic>>[].obs;
  final friendRequests = <Map<String, dynamic>>[].obs;
  final searchResults = <Map<String, dynamic>>[].obs;
  final sentRequests = <String>[].obs;
  final isLoading = true.obs;
  final isSearching = false.obs;
  final hasError = false.obs;

  /// Request ids currently being processed (accept / ignore) — prevents
  /// double taps.
  final busyRequests = <String>{}.obs;

  @override
  void onInit() {
    super.onInit();
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) {
        _activeUid = null;
        _friendsSubscription?.cancel();
        _requestsSubscription?.cancel();
        _sentSubscription?.cancel();
        friends.clear();
        friendRequests.clear();
        searchResults.clear();
        sentRequests.clear();
        isLoading.value = false;
        return;
      }
      if (_activeUid == user.uid) return;
      _activeUid = user.uid;
      _bindToUser(user.uid);
    });
  }

  @override
  void onClose() {
    _authSubscription?.cancel();
    _friendsSubscription?.cancel();
    _requestsSubscription?.cancel();
    _sentSubscription?.cancel();
    super.onClose();
  }

  String? get _uid => _activeUid ?? AuthController.instance.user?.uid;

  void refreshFriends() {
    final uid = _uid;
    if (uid != null) _bindToUser(uid);
  }

  void _bindToUser(String uid) {
    isLoading.value = true;
    hasError.value = false;

    _friendsSubscription?.cancel();
    _friendsSubscription = _firestore
        .collection('users')
        .doc(uid)
        .collection('friends')
        .snapshots()
        .listen((snapshot) {
      final list = snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList()
        ..sort((a, b) => (a['name'] ?? '')
            .toString()
            .toLowerCase()
            .compareTo((b['name'] ?? '').toString().toLowerCase()));
      friends.value = list;
      isLoading.value = false;
    }, onError: (Object e) {
      debugPrint('Friends stream error: $e');
      hasError.value = true;
      isLoading.value = false;
    });

    _requestsSubscription?.cancel();
    _requestsSubscription = _firestore
        .collection('users')
        .doc(uid)
        .collection('friendRequests')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snapshot) {
      final requests = snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();
      requests.sort((a, b) {
        final aTime = a['sentAt'];
        final bTime = b['sentAt'];
        if (aTime is Timestamp && bTime is Timestamp) return bTime.compareTo(aTime);
        return 0;
      });
      friendRequests.value = requests;
    }, onError: (Object e) => debugPrint('Requests stream error: $e'));

    _bindSentRequests(uid);
  }

  /// Outgoing pending requests, so "Requested" survives app restarts.
  void _bindSentRequests(String uid) {
    _sentSubscription?.cancel();
    _sentSubscription = _firestore
        .collectionGroup('friendRequests')
        .where('fromUid', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snap) {
      sentRequests.value = snap.docs
          .map((d) => d.reference.parent.parent?.id)
          .whereType<String>()
          .toList();
    }, onError: (Object e) => debugPrint('Sent requests stream error: $e'));
  }

  /// Withdraws a request the user sent.
  Future<void> cancelFriendRequest(String targetUid) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _firestore
          .collection('users')
          .doc(targetUid)
          .collection('friendRequests')
          .doc(uid)
          .delete();
      sentRequests.remove(targetUid);
      AppToast.info('Friend request withdrawn.', title: 'Withdrawn');
    } catch (e) {
      AppToast.error(AppToast.friendly(e));
    }
  }

  bool isAlreadyFriend(String uid) => friends.any((f) => f['uid'] == uid);

  Map<String, dynamic>? friendByUid(String uid) =>
      friends.firstWhereOrNull((f) => f['uid'] == uid);

  List<Map<String, dynamic>> _filterSelfAndFriends(
    Iterable<Map<String, dynamic>> users,
  ) {
    final me = _uid;
    final friendUids = friends.map((f) => f['uid']).toSet();
    final seen = <String>{};
    return users.where((u) {
      final uid = u['uid']?.toString();
      if (uid == null || uid == me || friendUids.contains(uid)) return false;
      return seen.add(uid);
    }).toList();
  }

  /// Public subset of a user document — never expose more than needed.
  static Map<String, dynamic> _publicProfile(Map<String, dynamic> data, String id) => {
        'uid': data['uid'] ?? id,
        'name': data['name'] ?? 'User',
        'email': data['email'] ?? '',
        'avatarUrl': data['avatarUrl'] ?? '',
      };

  /// Search by email (exact) or name prefix.
  Future<void> searchUsers(String query) async {
    final uid = _uid;
    final trimmed = query.trim();
    if (uid == null || trimmed.length < 2) {
      searchResults.clear();
      return;
    }

    isSearching.value = true;
    try {
      final lower = trimmed.toLowerCase();
      QuerySnapshot<Map<String, dynamic>> snapshot;
      if (GetUtils.isEmail(lower)) {
        snapshot = await _firestore
            .collection('users')
            .where('email', whereIn: {trimmed, lower}.toList())
            .limit(10)
            .get();
      } else {
        snapshot = await _firestore
            .collection('users')
            .where('nameLowercase', isGreaterThanOrEqualTo: lower)
            .where('nameLowercase', isLessThanOrEqualTo: '$lower')
            .limit(15)
            .get();
      }
      searchResults.value = _filterSelfAndFriends(
        snapshot.docs.map((d) => _publicProfile(d.data(), d.id)),
      );
    } catch (e) {
      debugPrint('User search failed: $e');
      AppToast.error(AppToast.friendly(e), title: 'Search failed');
    } finally {
      isSearching.value = false;
    }
  }

  /// Suggestions: friends-of-friends are not readable under our rules, so we
  /// suggest people the user already shares expenses/groups with.
  Future<void> loadSuggestedUsers({Iterable<Map<String, dynamic>> fromPeople = const []}) async {
    searchResults.value = _filterSelfAndFriends(fromPeople);
  }

  /// Resolves a user by uid (used by QR scanning / invite codes).
  Future<Map<String, dynamic>?> getUser(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (!doc.exists) return null;
      return _publicProfile(doc.data()!, doc.id);
    } catch (e) {
      debugPrint('getUser failed: $e');
      return null;
    }
  }

  /// Finds SplitShare users whose email matches any of [emails].
  Future<List<Map<String, dynamic>>> findUsersByEmails(List<String> emails) async {
    final normalized = <String>{};
    for (final e in emails) {
      final t = e.trim();
      if (t.isEmpty || !GetUtils.isEmail(t)) continue;
      normalized.add(t);
      normalized.add(t.toLowerCase());
    }
    final list = normalized.toList();
    final results = <Map<String, dynamic>>[];
    for (var i = 0; i < list.length; i += 30) {
      final chunk = list.sublist(i, i + 30 > list.length ? list.length : i + 30);
      final snap = await _firestore
          .collection('users')
          .where('email', whereIn: chunk)
          .get();
      results.addAll(snap.docs.map((d) => _publicProfile(d.data(), d.id)));
    }
    return _filterSelfAndFriends(results);
  }

  Future<bool> sendFriendRequest(String targetUid) async {
    final uid = _uid;
    if (uid == null || uid == targetUid) return false;

    try {
      if (isAlreadyFriend(targetUid)) {
        AppToast.info('You\'re already friends with this person.');
        return false;
      }

      // If they already sent us a request, accept it instead.
      final incoming = friendRequests.firstWhereOrNull((r) => r['fromUid'] == targetUid);
      if (incoming != null) {
        await acceptFriendRequest(incoming);
        return true;
      }

      final requestRef = _firestore
          .collection('users')
          .doc(targetUid)
          .collection('friendRequests')
          .doc(uid);
      final existing = await requestRef.get();
      if (existing.exists) {
        if (!sentRequests.contains(targetUid)) sentRequests.add(targetUid);
        AppToast.info('Your request is already waiting for a reply.');
        return false;
      }

      final myDoc = await _firestore.collection('users').doc(uid).get();
      final myData = myDoc.data() ?? {};

      await requestRef.set({
        'fromUid': uid,
        'fromName': myData['name'] ?? 'User',
        'fromEmail': myData['email'] ?? '',
        'fromAvatarUrl': myData['avatarUrl'] ?? '',
        'status': 'pending',
        'sentAt': FieldValue.serverTimestamp(),
      });

      sentRequests.add(targetUid);

      unawaited(NotificationController.createNotification(
        targetUid: targetUid,
        title: 'Friend request',
        message: '${myData['name'] ?? 'Someone'} wants to add you as a friend.',
        type: 'friend_request',
        iconName: 'person_add',
        iconColor: 0xFF8B5CF6,
        data: {'fromUid': uid},
      ));

      AppToast.success('Friend request sent.');
      return true;
    } catch (e) {
      AppToast.error(AppToast.friendly(e), title: 'Couldn\'t send request');
      return false;
    }
  }

  Future<void> sendFriendRequestByEmail(String email) async {
    final trimmed = email.trim();
    if (!GetUtils.isEmail(trimmed)) {
      AppToast.warning('Enter a valid email address.');
      return;
    }
    final snap = await _firestore
        .collection('users')
        .where('email', whereIn: {trimmed, trimmed.toLowerCase()}.toList())
        .limit(1)
        .get();
    if (snap.docs.isEmpty) {
      AppToast.info('No SplitShare account uses that email yet. Invite them instead!',
          title: 'Not found');
      return;
    }
    await sendFriendRequest(snap.docs.first.id);
  }

  Future<void> acceptFriendRequest(Map<String, dynamic> request) async {
    final uid = _uid;
    if (uid == null) return;
    final fromUid = request['fromUid'] as String;
    final requestId = request['id'] as String;
    if (busyRequests.contains(requestId)) return;
    busyRequests.add(requestId);

    try {
      final fromUserDoc = await _firestore.collection('users').doc(fromUid).get();
      final myDoc = await _firestore.collection('users').doc(uid).get();
      if (!fromUserDoc.exists) {
        await ignoreFriendRequest(requestId, silent: true);
        AppToast.info('That account no longer exists.');
        return;
      }
      final fromData = fromUserDoc.data()!;
      final myData = myDoc.data() ?? {};

      final batch = _firestore.batch();
      batch.set(
        _firestore.collection('users').doc(uid).collection('friends').doc(fromUid),
        {
          'name': fromData['name'] ?? 'User',
          'email': fromData['email'] ?? '',
          'uid': fromUid,
          'avatarUrl': fromData['avatarUrl'] ?? '',
          'addedAt': FieldValue.serverTimestamp(),
        },
      );
      batch.set(
        _firestore.collection('users').doc(fromUid).collection('friends').doc(uid),
        {
          'name': myData['name'] ?? 'User',
          'email': myData['email'] ?? '',
          'uid': uid,
          'avatarUrl': myData['avatarUrl'] ?? '',
          'addedAt': FieldValue.serverTimestamp(),
        },
      );
      batch.delete(_firestore
          .collection('users')
          .doc(uid)
          .collection('friendRequests')
          .doc(requestId));
      await batch.commit();

      unawaited(NotificationController.createNotification(
        targetUid: fromUid,
        title: 'Friend added',
        message: '${myData['name'] ?? 'Someone'} accepted your friend request.',
        type: 'friend_accepted',
        iconName: 'check_circle',
        iconColor: 0xFF10B981,
        data: {'fromUid': uid},
      ));

      AppToast.success('You and ${fromData['name'] ?? 'your friend'} are now connected.',
          title: 'Friend added');
    } catch (e) {
      AppToast.error(AppToast.friendly(e), title: 'Couldn\'t accept request');
    } finally {
      busyRequests.remove(requestId);
    }
  }

  Future<void> ignoreFriendRequest(String requestId, {bool silent = false}) async {
    final uid = _uid;
    if (uid == null) return;
    if (busyRequests.contains(requestId)) return;
    busyRequests.add(requestId);
    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('friendRequests')
          .doc(requestId)
          .delete();
      if (!silent) AppToast.info('Request declined.', title: 'Declined');
    } catch (e) {
      AppToast.error(AppToast.friendly(e));
    } finally {
      busyRequests.remove(requestId);
    }
  }

  /// Removes the friendship on both sides. Shared expenses are kept.
  Future<bool> removeFriend(String friendUid) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      final batch = _firestore.batch();
      batch.delete(_firestore.collection('users').doc(uid).collection('friends').doc(friendUid));
      batch.delete(_firestore.collection('users').doc(friendUid).collection('friends').doc(uid));
      await batch.commit();
      sentRequests.remove(friendUid);
      return true;
    } catch (e) {
      AppToast.error(AppToast.friendly(e), title: 'Couldn\'t remove friend');
      return false;
    }
  }
}

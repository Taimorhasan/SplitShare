import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../core/formatters.dart';

/// In-app notifications stored at `users/{uid}/notifications`.
///
/// Listens from sign-in so unread badges are always accurate.
class NotificationController extends GetxController {
  static NotificationController get to => Get.find();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  String? _activeUid;

  static const int _limit = 100;

  final notifications = <Map<String, dynamic>>[].obs;
  final isLoading = true.obs;
  final hasError = false.obs;

  int get unreadCount => notifications.where((n) => n['isRead'] != true).length;

  @override
  void onInit() {
    super.onInit();
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) {
        _activeUid = null;
        _sub?.cancel();
        notifications.clear();
        isLoading.value = false;
        return;
      }
      if (_activeUid == user.uid) return;
      _activeUid = user.uid;
      fetchNotifications();
    });
  }

  @override
  void onClose() {
    _authSubscription?.cancel();
    _sub?.cancel();
    super.onClose();
  }

  /// Kept for backwards compatibility — listening now starts at sign-in.
  void ensureListening() {
    if (_sub == null && _activeUid != null) fetchNotifications();
  }

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _firestore.collection('users').doc(uid).collection('notifications');

  void fetchNotifications() {
    final uid = _activeUid;
    if (uid == null) {
      isLoading.value = false;
      return;
    }
    isLoading.value = true;
    hasError.value = false;
    _sub?.cancel();
    _sub = _col(uid)
        .orderBy('createdAt', descending: true)
        .limit(_limit)
        .snapshots()
        .listen((snap) {
      notifications.value =
          snap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
      isLoading.value = false;
    }, onError: (Object e) {
      debugPrint('Notification stream error: $e');
      hasError.value = true;
      isLoading.value = false;
    });
  }

  Future<void> markAsRead(String id) async {
    final uid = _activeUid;
    if (uid == null) return;
    await _col(uid).doc(id).update({'isRead': true});
  }

  Future<void> markAllAsRead() async {
    final uid = _activeUid;
    if (uid == null) return;
    final unread = notifications.where((n) => n['isRead'] != true).toList();
    if (unread.isEmpty) return;
    final batch = _firestore.batch();
    for (final n in unread) {
      batch.update(_col(uid).doc(n['id'].toString()), {'isRead': true});
    }
    await batch.commit();
  }

  Future<void> deleteNotification(String id) async {
    final uid = _activeUid;
    if (uid == null) return;
    await _col(uid).doc(id).delete();
  }

  Future<void> clearAll() async {
    final uid = _activeUid;
    if (uid == null) return;
    final batch = _firestore.batch();
    for (final n in notifications) {
      batch.delete(_col(uid).doc(n['id'].toString()));
    }
    await batch.commit();
  }

  /// Writes a notification into another user's inbox.
  ///
  /// Skipped silently when the recipient turned notifications off.
  /// Security rules require `fromUid` to equal the sender.
  static Future<void> createNotification({
    required String targetUid,
    required String title,
    required String message,
    required String type,
    String iconName = 'notifications',
    int iconColor = 0xFF4F46E5,
    Map<String, dynamic>? data,
  }) async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null || targetUid.isEmpty || targetUid == me) return;
    final fs = FirebaseFirestore.instance;
    try {
      final target = await fs.collection('users').doc(targetUid).get();
      if (target.data()?['notificationsEnabled'] == false) return;
      await fs.collection('users').doc(targetUid).collection('notifications').add({
        'title': title,
        'message': message,
        'type': type,
        'iconName': iconName,
        'iconColor': iconColor,
        'isRead': false,
        'fromUid': me,
        'data': data ?? {},
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('createNotification failed: $e');
    }
  }

  static IconData iconFromName(String? name) {
    switch (name) {
      case 'check_circle':
        return Icons.check_circle_rounded;
      case 'receipt_long':
        return Icons.receipt_long_rounded;
      case 'person_add':
        return Icons.person_add_rounded;
      case 'warning_amber_rounded':
        return Icons.notifications_active_rounded;
      case 'group_add':
        return Icons.group_add_rounded;
      case 'payment':
        return Icons.payments_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  static String formatTime(dynamic timestamp) => Fmt.relative(timestamp);
}

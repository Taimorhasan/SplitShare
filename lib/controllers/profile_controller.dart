import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';
import '../core/formatters.dart';
import '../core/image_store.dart';
import 'auth_controller.dart';

/// The signed-in user's profile.
///
/// Public fields live in `users/{uid}` (readable by signed-in users so
/// friends can find each other). Private fields (phone) live in
/// `users/{uid}/private/contact`, readable only by the owner.
class ProfileController extends GetxController {
  static ProfileController get to => Get.find();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _privateSubscription;
  String? _activeUid;

  final name = ''.obs;
  final email = ''.obs;
  final phone = ''.obs;
  final avatarUrl = ''.obs;
  final currencyCode = 'USD'.obs;
  final currencySymbol = '\$'.obs;
  final notificationsEnabled = true.obs;
  final memberSince = Rxn<DateTime>();
  final isLoaded = false.obs;
  final isSaving = false.obs;

  Map<String, String> get currencies => Currencies.symbols;

  @override
  void onInit() {
    super.onInit();
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) {
        _activeUid = null;
        _profileSubscription?.cancel();
        _privateSubscription?.cancel();
        name.value = '';
        email.value = '';
        phone.value = '';
        avatarUrl.value = '';
        isLoaded.value = false;
        return;
      }
      if (_activeUid == user.uid) return;
      _activeUid = user.uid;
      fetchUserProfile();
    });
  }

  @override
  void onClose() {
    _authSubscription?.cancel();
    _profileSubscription?.cancel();
    _privateSubscription?.cancel();
    super.onClose();
  }

  String? get _uid => _activeUid ?? AuthController.instance.user?.uid;

  void fetchUserProfile() {
    final uid = _uid;
    if (uid == null) return;
    final authUser = FirebaseAuth.instance.currentUser;

    _profileSubscription?.cancel();
    _profileSubscription = _firestore.collection('users').doc(uid).snapshots().listen(
      (snapshot) {
        if (snapshot.exists) {
          final data = snapshot.data()!;
          name.value = (data['name'] ?? '').toString();
          email.value = (data['email'] ?? authUser?.email ?? '').toString();
          avatarUrl.value = (data['avatarUrl'] ?? '').toString();
          currencyCode.value = (data['currencyCode'] ?? 'USD').toString();
          currencySymbol.value = Currencies.symbolFor(currencyCode.value);
          notificationsEnabled.value = data['notificationsEnabled'] ?? true;
          memberSince.value = Fmt.toDate(data['createdAt']);
          // Legacy: phone used to be public. Show it until migrated.
          final legacyPhone = (data['phone'] ?? '').toString();
          if (legacyPhone.isNotEmpty && phone.value.isEmpty) {
            phone.value = legacyPhone;
          }
        } else if (authUser != null) {
          // Profile doc missing (e.g. interrupted sign-up) — recreate it.
          unawaited(AuthController.instance.ensureUserDocument(authUser));
        }
        isLoaded.value = true;
      },
      onError: (Object e) => debugPrint('Profile stream error: $e'),
    );

    _privateSubscription?.cancel();
    _privateSubscription = _firestore
        .collection('users')
        .doc(uid)
        .collection('private')
        .doc('contact')
        .snapshots()
        .listen(
      (snap) {
        final p = snap.data()?['phone']?.toString();
        if (p != null) phone.value = p;
      },
      onError: (Object e) => debugPrint('Private profile stream error: $e'),
    );
  }

  /// Saves a profile photo (free Firestore image store) and returns its URL.
  Future<String> uploadAvatar(File file) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not signed in');
    return ImageStore.saveAvatar(uid, await file.readAsBytes());
  }

  /// Updates the profile and propagates name/avatar to friends' and groups'
  /// denormalised copies so everyone sees the change.
  Future<void> updateProfile({
    String? newName,
    String? newPhone,
    String? newAvatar,
    @Deprecated('Email changes are not supported here') String? newEmail,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    isSaving.value = true;
    try {
      final updates = <String, dynamic>{};
      if (newName != null && newName.trim() != name.value) {
        updates['name'] = newName.trim();
        updates['nameLowercase'] = newName.trim().toLowerCase();
      }
      if (newAvatar != null && newAvatar != avatarUrl.value) {
        updates['avatarUrl'] = newAvatar;
      }
      if (newPhone != null) {
        await _firestore
            .collection('users')
            .doc(uid)
            .collection('private')
            .doc('contact')
            .set({'phone': newPhone.trim()}, SetOptions(merge: true));
        updates['phone'] = FieldValue.delete(); // migrate off the public doc
        phone.value = newPhone.trim();
      }
      if (updates.isEmpty) return;

      await _firestore.collection('users').doc(uid).update(updates);

      if (updates.containsKey('name')) {
        await FirebaseAuth.instance.currentUser?.updateDisplayName(updates['name']);
      }
      if (updates.containsKey('name') || updates.containsKey('avatarUrl')) {
        unawaited(_propagate(
          uid,
          name: updates['name'] as String?,
          avatarUrl: updates['avatarUrl'] as String?,
        ));
      }
    } finally {
      isSaving.value = false;
    }
  }

  Future<void> _propagate(String uid, {String? name, String? avatarUrl}) async {
    try {
      final patch = <String, dynamic>{
        'name': ?name,
        'avatarUrl': ?avatarUrl,
      };
      // Friends' copies of me.
      final friends =
          await _firestore.collection('users').doc(uid).collection('friends').get();
      final batch = _firestore.batch();
      for (final f in friends.docs) {
        batch.update(
          _firestore.collection('users').doc(f.id).collection('friends').doc(uid),
          patch,
        );
      }
      // Group member previews.
      final groups = await _firestore
          .collection('groups')
          .where('members', arrayContains: uid)
          .get();
      for (final g in groups.docs) {
        final details = (g.data()['memberDetails'] as List?) ?? [];
        final updated = details.map((d) {
          if (d is Map && d['uid'] == uid) return {...d, ...patch};
          return d;
        }).toList();
        batch.update(g.reference, {'memberDetails': updated});
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Profile propagation failed: $e');
    }
  }

  Future<void> changeCurrency(String code) async {
    final uid = _uid;
    if (uid == null) return;
    final previous = currencyCode.value;
    currencyCode.value = code; // optimistic
    currencySymbol.value = Currencies.symbolFor(code);
    try {
      await _firestore.collection('users').doc(uid).update({'currencyCode': code});
    } catch (e) {
      currencyCode.value = previous;
      currencySymbol.value = Currencies.symbolFor(previous);
      rethrow;
    }
  }

  Future<void> toggleNotifications(bool value) async {
    final uid = _uid;
    if (uid == null) return;
    notificationsEnabled.value = value; // optimistic
    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .update({'notificationsEnabled': value});
    } catch (e) {
      notificationsEnabled.value = !value;
      rethrow;
    }
  }

  void logout() => AuthController.instance.logout();

  /// Exports the user's data as JSON through the system share sheet.
  Future<void> exportUserData() async {
    final uid = _uid;
    if (uid == null) return;

    final userDoc = await _firestore.collection('users').doc(uid).get();
    final privateDoc = await _firestore
        .collection('users')
        .doc(uid)
        .collection('private')
        .doc('contact')
        .get();
    final friendsSnap =
        await _firestore.collection('users').doc(uid).collection('friends').get();
    final groupsSnap = await _firestore
        .collection('groups')
        .where('members', arrayContains: uid)
        .get();
    final expensesSnap = await _firestore
        .collection('expenses')
        .where('involvedUsers', arrayContains: uid)
        .get();

    final export = _serialize({
      'exportedAt': DateTime.now().toIso8601String(),
      'profile': {...?userDoc.data(), ...?privateDoc.data()},
      'friends': friendsSnap.docs.map((d) => d.data()).toList(),
      'groups': groupsSnap.docs.map((d) => {'id': d.id, ...d.data()}).toList(),
      'expenses': expensesSnap.docs.map((d) => {'id': d.id, ...d.data()}).toList(),
    });

    final json = const JsonEncoder.withIndent('  ').convert(export);
    await SharePlus.instance.share(
      ShareParams(text: json, subject: 'My SplitShare data export'),
    );
  }

  dynamic _serialize(dynamic value) {
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), _serialize(v)));
    }
    if (value is List) return value.map(_serialize).toList();
    if (value is FieldValue) return null;
    return value;
  }

  /// Avatar provider for legacy widgets. Prefer `AppAvatar`.
  ImageProvider<Object>? getAvatarProvider() {
    final url = avatarUrl.value;
    if (url.startsWith('http')) return NetworkImage(url);
    return null;
  }
}

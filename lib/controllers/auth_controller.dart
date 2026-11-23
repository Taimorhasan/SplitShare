import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../app/routes/app_routes.dart';
import '../core/feedback.dart';

/// Authentication: email/password, Google, Apple, password reset/change.
///
/// Also watches the session: if the user is signed out while inside the app
/// (token revoked, account disabled, signed out on another flow) they are
/// returned to the login screen.
class AuthController extends GetxController {
  static AuthController get instance => Get.find();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);
  final Rxn<User> _firebaseUser = Rxn<User>();

  User? get user => _firebaseUser.value ?? _auth.currentUser;
  final isLoading = false.obs;

  /// Which social provider is in progress ('google' / 'apple'), for spinners.
  final socialLoading = RxnString();

  static const _publicRoutes = {
    AppRoutes.splash,
    AppRoutes.onboarding,
    AppRoutes.login,
    AppRoutes.signup,
    AppRoutes.resetPassword,
    AppRoutes.createNewPassword,
  };

  bool get hasPasswordProvider {
    final current = _auth.currentUser;
    if (current == null) return false;
    return current.providerData.any((p) => p.providerId == 'password');
  }

  @override
  void onInit() {
    super.onInit();
    _firebaseUser.value = _auth.currentUser;
    _firebaseUser.bindStream(_auth.userChanges());
    ever<User?>(_firebaseUser, (u) {
      if (u == null && !_publicRoutes.contains(Get.currentRoute)) {
        // Session ended while inside the app.
        Get.offAllNamed(AppRoutes.login);
      }
    });
  }

  void _goHome() => Get.offAllNamed(AppRoutes.home);

  // ---------- Email / password ----------

  Future<bool> login(String email, String password) async {
    if (isLoading.value) return false;
    try {
      isLoading.value = true;
      final cred = await _auth
          .signInWithEmailAndPassword(email: email.trim(), password: password)
          .timeout(const Duration(seconds: 25));
      if (cred.user != null) await ensureUserDocument(cred.user!);
      _goHome();
      return true;
    } on FirebaseAuthException catch (e) {
      _handleAuthError(e);
      return false;
    } catch (e) {
      AppToast.error(AppToast.friendly(e), title: 'Sign in failed');
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  Future<bool> register(String name, String email, String password) async {
    if (isLoading.value) return false;
    try {
      isLoading.value = true;
      final cred = await _auth
          .createUserWithEmailAndPassword(email: email.trim(), password: password)
          .timeout(const Duration(seconds: 25));
      final u = cred.user!;
      await u.updateDisplayName(name.trim());
      await _createUserDoc(u, name: name.trim(), email: email.trim(), photoUrl: '');
      _goHome();
      AppToast.success('Welcome to SplitShare, ${name.trim().split(' ').first}!',
          title: 'Account created');
      return true;
    } on FirebaseAuthException catch (e) {
      _handleAuthError(e);
      return false;
    } catch (e) {
      AppToast.error(AppToast.friendly(e), title: 'Sign up failed');
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  // ---------- Social ----------

  Future<void> signInWithGoogle() async {
    if (isLoading.value) return;
    try {
      isLoading.value = true;
      socialLoading.value = 'google';
      UserCredential cred;
      if (kIsWeb) {
        cred = await _auth.signInWithPopup(GoogleAuthProvider());
      } else {
        final googleUser = await _googleSignIn.signIn();
        if (googleUser == null) return; // cancelled
        final googleAuth = await googleUser.authentication;
        cred = await _auth.signInWithCredential(GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        ));
      }
      if (cred.user != null) await ensureUserDocument(cred.user!);
      _goHome();
    } on FirebaseAuthException catch (e) {
      _handleAuthError(e);
    } catch (e) {
      debugPrint('Google sign-in error: $e');
      AppToast.error('Google sign-in didn\'t complete. Please try again.',
          title: 'Google sign-in');
    } finally {
      isLoading.value = false;
      socialLoading.value = null;
    }
  }

  Future<void> signInWithApple() async {
    if (isLoading.value) return;
    try {
      isLoading.value = true;
      socialLoading.value = 'apple';
      UserCredential cred;
      String? givenName;
      final isApple = !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.macOS);

      if (isApple) {
        final rawNonce = _generateNonce();
        final nonce = sha256.convert(utf8.encode(rawNonce)).toString();
        final apple = await SignInWithApple.getAppleIDCredential(
          scopes: [
            AppleIDAuthorizationScopes.email,
            AppleIDAuthorizationScopes.fullName,
          ],
          nonce: nonce,
        );
        cred = await _auth.signInWithCredential(OAuthProvider('apple.com')
            .credential(idToken: apple.identityToken, rawNonce: rawNonce));
        if (apple.givenName != null) {
          givenName = '${apple.givenName} ${apple.familyName ?? ''}'.trim();
        }
      } else {
        final provider = AppleAuthProvider()
          ..addScope('email')
          ..addScope('name');
        cred = kIsWeb
            ? await _auth.signInWithPopup(provider)
            : await _auth.signInWithProvider(provider);
      }
      if (cred.user != null) {
        await ensureUserDocument(cred.user!, fallbackName: givenName);
      }
      _goHome();
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code != AuthorizationErrorCode.canceled) {
        AppToast.error('Apple sign-in didn\'t complete.', title: 'Apple sign-in');
      }
    } on FirebaseAuthException catch (e) {
      _handleAuthError(e);
    } catch (e) {
      debugPrint('Apple sign-in error: $e');
      AppToast.error('Apple sign-in didn\'t complete. Please try again.',
          title: 'Apple sign-in');
    } finally {
      isLoading.value = false;
      socialLoading.value = null;
    }
  }

  /// Creates `users/{uid}` if it doesn't exist yet.
  Future<void> ensureUserDocument(User u, {String? fallbackName}) async {
    final ref = _firestore.collection('users').doc(u.uid);
    final doc = await ref.get();
    if (doc.exists) return;
    final name = (u.displayName?.trim().isNotEmpty ?? false)
        ? u.displayName!.trim()
        : (fallbackName?.isNotEmpty ?? false)
            ? fallbackName!
            : (u.email?.split('@').first ?? 'SplitShare user');
    await _createUserDoc(u, name: name, email: u.email ?? '', photoUrl: u.photoURL ?? '');
  }

  Future<void> _createUserDoc(
    User u, {
    required String name,
    required String email,
    required String photoUrl,
  }) {
    return _firestore.collection('users').doc(u.uid).set({
      'name': name,
      'nameLowercase': name.toLowerCase(),
      'email': email.toLowerCase(),
      'uid': u.uid,
      'avatarUrl': photoUrl,
      'currencyCode': 'USD',
      'notificationsEnabled': true,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)]).join();
  }

  // ---------- Errors ----------

  static String messageFor(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'That email and password don\'t match. Please try again.';
      case 'email-already-in-use':
        return 'An account already exists for this email. Try signing in.';
      case 'weak-password':
        return 'Choose a stronger password (at least 8 characters).';
      case 'invalid-email':
        return 'That email address doesn\'t look right.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'network-request-failed':
        return 'No internet connection. Check your network and try again.';
      case 'requires-recent-login':
        return 'For security, please sign in again and retry.';
      case 'account-exists-with-different-credential':
        return 'This email is linked to a different sign-in method.';
      case 'popup-closed-by-user':
      case 'cancelled-popup-request':
      case 'web-context-canceled':
        return 'Sign-in was cancelled.';
      case 'operation-not-allowed':
        return 'This sign-in method isn\'t enabled for SplitShare yet.';
      default:
        return e.message ?? 'Something went wrong. Please try again.';
    }
  }

  void _handleAuthError(FirebaseAuthException e) {
    AppToast.error(messageFor(e), title: 'Authentication');
  }

  // ---------- Session / password ----------

  Future<void> logout() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    await _auth.signOut();
    Get.offAllNamed(AppRoutes.login);
  }

  Future<bool> sendPasswordResetEmail(String email) async {
    if (isLoading.value) return false;
    try {
      isLoading.value = true;
      await _auth.sendPasswordResetEmail(email: email.trim());
      return true;
    } on FirebaseAuthException catch (e) {
      // Don't reveal whether an account exists.
      if (e.code == 'user-not-found') return true;
      _handleAuthError(e);
      return false;
    } catch (e) {
      AppToast.error(AppToast.friendly(e));
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  /// Re-authenticates then changes the password. Throws on failure.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final current = _auth.currentUser;
    if (current == null || current.email == null) {
      throw Exception('You must be signed in to change your password.');
    }
    if (!hasPasswordProvider) {
      throw Exception('Password change isn\'t available for Google/Apple accounts.');
    }
    try {
      isLoading.value = true;
      await current.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: current.email!, password: currentPassword),
      );
      await current.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        throw Exception('Your current password is incorrect.');
      }
      throw Exception(messageFor(e));
    } finally {
      isLoading.value = false;
    }
  }
}

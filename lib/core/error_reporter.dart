import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

/// Free, built-in crash reporting.
///
/// Every uncaught Flutter / Dart error is written to the write-only
/// `errorReports` collection (message, stack trace, screen, platform) so the
/// developer can read it from the Firebase console. No personal data is sent.
/// Identical errors are only reported once per app session.
class ErrorReporter {
  ErrorReporter._();

  static final Set<String> _sent = {};
  static const _appVersion = '1.0.0';

  static void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      report(
        details.exceptionAsString(),
        details.stack,
        context: details.context?.toDescription() ?? details.library,
      );
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('Uncaught: $error');
      report(error.toString(), stack, context: 'async');
      return true; // handled: keep the app running
    };
  }

  static void report(String message, StackTrace? stack, {String? context}) {
    try {
      if (Firebase.apps.isEmpty) return;
      final key = message.length > 200 ? message.substring(0, 200) : message;
      if (!_sent.add(key)) return;
      final lines = (stack?.toString() ?? '')
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .take(40)
          .join('\n');
      FirebaseFirestore.instance.collection('errorReports').add({
        'message': message.length > 3000 ? message.substring(0, 3000) : message,
        'stack': lines.length > 6000 ? lines.substring(0, 6000) : lines,
        'context': (context ?? '').length > 500 ? context!.substring(0, 500) : (context ?? ''),
        'route': Get.currentRoute,
        'platform': defaultTargetPlatform.name,
        'debug': kDebugMode,
        'appVersion': _appVersion,
        'uid': FirebaseAuth.instance.currentUser?.uid ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      }).catchError((Object e) {
        debugPrint('Error report failed: $e');
        return FirebaseFirestore.instance.collection('errorReports').doc();
      });
    } catch (_) {
      // Never let reporting itself crash the app.
    }
  }
}

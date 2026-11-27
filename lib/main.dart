import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'app/routes/app_pages.dart';
import 'controllers/auth_controller.dart';
import 'controllers/expense_controller.dart';
import 'controllers/friend_controller.dart';
import 'controllers/group_controller.dart';
import 'controllers/notification_controller.dart';
import 'controllers/profile_controller.dart';
import 'controllers/shell_controller.dart';
import 'controllers/theme_controller.dart';
import 'controllers/trip_controller.dart';
import 'core/error_reporter.dart';
import 'core/ui.dart';
import 'firebase_options.dart';

/// Set if Firebase failed to start; the splash screen shows a retry state.
Object? firebaseInitError;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // In release builds a widget that fails to build would otherwise leave a
  // blank grey/white area. Show a small friendly message instead so the rest
  // of the screen keeps working.
  if (kReleaseMode) {
    ErrorWidget.builder = (details) => Material(
          color: Colors.transparent,
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded, color: AppColors.textMuted, size: 18),
                SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'This part couldn\'t be shown.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        );
  }
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // Keep a full offline copy of the user's data: screens fill instantly
    // from the local cache on launch, then update live from the server.
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
    if (_useEmulators) await _connectEmulators();
    ErrorReporter.install();
    registerControllers();
  } catch (e) {
    debugPrint('Firebase initialization failed: $e');
    firebaseInitError = e;
  }

  // Appearance is decided before the first frame (no flash of the wrong theme).
  Get.put(ThemeController(await ThemeController.loadSaved()), permanent: true);

  runApp(const SplitShareApp());
}

/// Local testing only: `flutter run --dart-define=USE_EMULATORS=true` talks to
/// the Firebase emulators (`firebase emulators:start`) instead of the live
/// project. Never enabled in normal builds.
const bool _useEmulators = bool.fromEnvironment('USE_EMULATORS');

Future<void> _connectEmulators() async {
  const host = 'localhost';
  await FirebaseAuth.instance.useAuthEmulator(host, 9099);
  FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
  debugPrint('Using Firebase emulators on $host');
}

/// Registers global controllers. Order matters: Friend before Expense
/// (Expense reads friend names), Auth first.
void registerControllers() {
  if (Get.isRegistered<AuthController>()) return;
  Get.put(AuthController(), permanent: true);
  Get.put(ProfileController(), permanent: true);
  Get.put(FriendController(), permanent: true);
  Get.put(ExpenseController(), permanent: true);
  Get.put(GroupController(), permanent: true);
  Get.put(NotificationController(), permanent: true);
  Get.put(ShellController(), permanent: true);
  Get.put(TripController(), permanent: true);
}

class SplitShareApp extends StatelessWidget {
  const SplitShareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'SplitShare',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeController.to.mode.value,
      initialRoute: AppPages.initial,
      getPages: AppPages.routes,
      defaultTransition: Transition.cupertino,
      // Swipe from the left edge to go back, on Android as well as iPhone.
      popGesture: true,
      transitionDuration: const Duration(milliseconds: 320),
      unknownRoute: GetPage(
        name: '/not-found',
        page: () => Scaffold(
          body: EmptyState(
            icon: Icons.explore_off_rounded,
            title: 'Page not found',
            message: 'The screen you were looking for doesn\'t exist.',
            actionLabel: 'Go home',
            onAction: () => Get.offAllNamed('/home'),
          ),
        ),
      ),
      builder: (context, child) {
        // Clamp extreme text scaling so layouts stay intact while still
        // honouring the user's accessibility preference.
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: mq.textScaler.clamp(minScaleFactor: 0.85, maxScaleFactor: 1.3),
          ),
          child: GestureDetector(
            onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
            behavior: HitTestBehavior.translucent,
            child: child!,
          ),
        );
      },
    );
  }
}

/// Backwards-compatible alias used by the widget test.
typedef MyApp = SplitShareApp;

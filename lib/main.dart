import 'package:firebase_core/firebase_core.dart';
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
import 'controllers/trip_controller.dart';
import 'core/ui.dart';
import 'firebase_options.dart';

/// Set if Firebase failed to start; the splash screen shows a retry state.
Object? firebaseInitError;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    registerControllers();
  } catch (e) {
    debugPrint('Firebase initialization failed: $e');
    firebaseInitError = e;
  }

  runApp(const SplitShareApp());
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
      themeMode: ThemeMode.light,
      initialRoute: AppPages.initial,
      getPages: AppPages.routes,
      defaultTransition: Transition.cupertino,
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

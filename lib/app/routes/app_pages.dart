import 'package:get/get.dart';
import '../../modules/activity_screen.dart';
import '../../modules/add_expense_screen.dart';
import '../../modules/add_friends_screen.dart';
import '../../modules/change_password_screen.dart';
import '../../modules/create_group_screen.dart';
import '../../modules/create_new_password_screen.dart';
import '../../modules/edit_profile_screen.dart';
import '../../modules/expense_detail_screen.dart';
import '../../modules/friend_detail_screen.dart';
import '../../modules/friend_requests_screen.dart';
import '../../modules/group_detail_screen.dart';
import '../../modules/help_screen.dart';
import '../../modules/login_screen.dart';
import '../../modules/main_layout.dart';
import '../../modules/notifications_screen.dart';
import '../../modules/onboarding_screen.dart';
import '../../modules/reset_password_screen.dart';
import '../../modules/scan_qr_screen.dart';
import '../../modules/settle_up_screen.dart';
import '../../modules/signup_screen.dart';
import '../../modules/splash_screen.dart';
import 'app_routes.dart';

/// Route table.
///
/// Screens that need input read it from `Get.arguments` (documented on each
/// screen class) so they can be opened by name from anywhere.
class AppPages {
  AppPages._();

  static const String initial = AppRoutes.splash;

  static final List<GetPage<dynamic>> routes = [
    // Public
    GetPage(name: AppRoutes.splash, page: () => const SplashScreen(),
        transition: Transition.fade),
    GetPage(name: AppRoutes.onboarding, page: () => const OnboardingScreen(),
        transition: Transition.fade),
    GetPage(name: AppRoutes.login, page: () => const LoginScreen(),
        transition: Transition.fade),
    GetPage(name: AppRoutes.signup, page: () => const SignupScreen()),
    GetPage(name: AppRoutes.resetPassword, page: () => const ResetPasswordScreen()),
    GetPage(name: AppRoutes.createNewPassword,
        page: () => const CreateNewPasswordScreen()),

    // Shell + tab aliases
    GetPage(name: AppRoutes.home, page: () => const MainLayout(),
        transition: Transition.fade),
    GetPage(name: AppRoutes.dashboard, page: () => const MainLayout(initialIndex: 0),
        transition: Transition.fade),
    GetPage(name: AppRoutes.groups, page: () => const MainLayout(initialIndex: 1),
        transition: Transition.fade),
    GetPage(name: AppRoutes.friends, page: () => const MainLayout(initialIndex: 2),
        transition: Transition.fade),
    GetPage(name: AppRoutes.profile, page: () => const MainLayout(initialIndex: 3),
        transition: Transition.fade),

    // Pushed screens
    GetPage(name: AppRoutes.addExpense, page: () => const AddExpenseScreen(),
        transition: Transition.downToUp),
    GetPage(name: AppRoutes.expenseDetail, page: () => const ExpenseDetailScreen()),
    GetPage(name: AppRoutes.activity, page: () => const ActivityScreen()),
    GetPage(name: AppRoutes.settleUp, page: () => const SettleUpScreen()),
    GetPage(name: AppRoutes.notifications, page: () => const NotificationsScreen()),
    GetPage(name: AppRoutes.createGroup, page: () => const CreateGroupScreen(),
        transition: Transition.downToUp),
    GetPage(name: AppRoutes.groupDetail, page: () => const GroupDetailScreen()),
    GetPage(name: AppRoutes.addFriends, page: () => const AddFriendsScreen()),
    GetPage(name: AppRoutes.friendDetail, page: () => const FriendDetailScreen()),
    GetPage(name: AppRoutes.friendRequests, page: () => const FriendRequestsScreen()),
    GetPage(name: AppRoutes.scanQr, page: () => const ScanQrScreen(),
        transition: Transition.downToUp),
    GetPage(name: AppRoutes.editProfile, page: () => const EditProfileScreen()),
    GetPage(name: AppRoutes.changePassword, page: () => const ChangePasswordScreen()),
    GetPage(name: AppRoutes.help, page: () => const HelpScreen()),
  ];
}

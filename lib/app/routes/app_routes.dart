/// Route names.
class AppRoutes {
  AppRoutes._();

  // Public
  static const String splash = '/splash';
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String signup = '/signup';
  static const String resetPassword = '/reset-password';
  static const String createNewPassword = '/reset-email-sent';

  // Shell (bottom navigation). Tab aliases open the shell on that tab.
  static const String home = '/home';
  static const String dashboard = '/dashboard';
  static const String groups = '/groups';
  static const String friends = '/friends';
  static const String profile = '/profile';

  // Pushed screens
  static const String addExpense = '/add-expense';
  static const String expenseDetail = '/expense';
  static const String activity = '/activity';
  static const String settleUp = '/settle-up';
  static const String notifications = '/notifications';
  static const String createGroup = '/create-group';
  static const String groupDetail = '/group-detail';
  static const String addFriends = '/add-friends';
  static const String friendDetail = '/friend';
  static const String friendRequests = '/friend-requests';
  static const String scanQr = '/scan';
  static const String editProfile = '/edit-profile';
  static const String changePassword = '/change-password';
  static const String help = '/help';
  static const String trips = '/trips';
  static const String tripDetail = '/trip';
}

/// Alias kept for backward compatibility.
typedef Routes = AppRoutes;

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import '../app/routes/app_routes.dart';

/// Tabs of the main shell.
enum AppTab { home, groups, friends, profile }

/// Holds the selected bottom-navigation tab.
///
/// The shell (bottom bar + IndexedStack) is built once; switching tabs only
/// swaps the visible content, so the bar never moves and tab state is kept.
class ShellController extends GetxController {
  static ShellController get to => Get.find();

  final index = 0.obs;

  AppTab get tab => AppTab.values[index.value];

  void select(AppTab tab) => index.value = tab.index;
}

/// App-wide navigation helpers.
class AppNav {
  AppNav._();

  /// Switches to a bottom-nav tab from anywhere: pops back to the shell
  /// (if a screen is pushed on top) and selects the tab.
  static void toTab(AppTab tab) {
    final shell = ShellController.to;
    shell.select(tab);
    if (Get.currentRoute != AppRoutes.home) {
      var foundShell = false;
      Get.until((route) {
        final name = route.settings.name;
        final isShell = name == AppRoutes.home ||
            name == AppRoutes.dashboard ||
            name == AppRoutes.groups ||
            name == AppRoutes.friends ||
            name == AppRoutes.profile;
        if (isShell) foundShell = true;
        return isShell || route.isFirst;
      });
      if (!foundShell) Get.offAllNamed(AppRoutes.home);
    }
  }

  static Future<T?>? to<T>(String route, {dynamic arguments}) =>
      Get.toNamed<T>(route, arguments: arguments);

  static void openExpense(String id) =>
      Get.toNamed(AppRoutes.expenseDetail, arguments: {'id': id});

  static void openGroup(Map<String, dynamic> group) =>
      Get.toNamed(AppRoutes.groupDetail, arguments: group);

  static void openFriend(String uid, {Map<String, dynamic>? data}) =>
      Get.toNamed(AppRoutes.friendDetail, arguments: {'uid': uid, ...?data});

  static void addExpense({Map<String, dynamic>? arguments}) =>
      Get.toNamed(AppRoutes.addExpense, arguments: arguments);

  /// Dismisses the keyboard.
  static void unfocus() => FocusManager.instance.primaryFocus?.unfocus();
}

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_colors.dart';

/// Light / dark / follow-system appearance, remembered on the device.
class ThemeController extends GetxController with WidgetsBindingObserver {
  static ThemeController get to => Get.find();

  static const _key = 'theme_mode';

  final mode = ThemeMode.system.obs;

  bool get isDark => AppColors.isDark;

  /// Reads the saved choice before the first frame so the app opens in the
  /// right colours (no flash of the wrong theme).
  static Future<ThemeMode> loadSaved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return switch (prefs.getString(_key)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    } catch (_) {
      return ThemeMode.system;
    }
  }

  ThemeController(ThemeMode initial) {
    mode.value = initial;
    AppColors.setDark(_effectiveDark(initial));
  }

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }

  static bool _effectiveDark(ThemeMode m) => switch (m) {
        ThemeMode.dark => true,
        ThemeMode.light => false,
        ThemeMode.system =>
          SchedulerBinding.instance.platformDispatcher.platformBrightness ==
              Brightness.dark,
      };

  Future<void> setMode(ThemeMode m) async {
    mode.value = m;
    _apply();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, m.name);
    } catch (_) {}
  }

  /// Phone switched between light and dark while the app is open.
  @override
  void didChangePlatformBrightness() {
    if (mode.value == ThemeMode.system) _apply();
  }

  void _apply() {
    final dark = _effectiveDark(mode.value);
    if (dark == AppColors.isDark) {
      Get.changeThemeMode(mode.value);
      return;
    }
    AppColors.setDark(dark);
    Get.changeThemeMode(mode.value);
    // Colour tokens are read during build, so repaint everything.
    Get.forceAppUpdate();
  }

  String get label => switch (mode.value) {
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
        ThemeMode.system => 'Same as phone',
      };
}

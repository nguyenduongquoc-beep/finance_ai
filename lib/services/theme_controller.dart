import 'package:flutter/material.dart';

/// ============================================================
/// THEME CONTROLLER (THỐNG NHẤT GIAO DIỆN MẶC ĐỊNH)
/// Ứng dụng sử dụng thống nhất một giao diện sáng mặc định xuyên suốt.
/// ============================================================
class ThemeController {
  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.light);

  static Future<void> loadSavedTheme() async {
    mode.value = ThemeMode.light;
  }

  static Future<void> toggle(bool _) async {
    mode.value = ThemeMode.light;
  }

  static bool get isDark => false;
}

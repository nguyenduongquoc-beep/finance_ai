import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';

/// ============================================================
/// LANGUAGE CONTROLLER (I18N)
/// Quản lý trạng thái đa ngôn ngữ (Tiếng Việt & English) toàn app.
/// Sử dụng ValueNotifier tương tự ThemeController, lưu vào
/// SharedPreferences để duy trì lựa chọn của người dùng.
/// ============================================================
class LanguageController {
  static const String _prefKey = 'app_language';

  /// Mặc định: Tiếng Việt
  static final ValueNotifier<Locale> currentLocale =
      ValueNotifier(const Locale('vi', 'VN'));

  static const List<Locale> supportedLocales = [
    Locale('vi', 'VN'),
    Locale('en', 'US'),
  ];

  /// Gọi trong main() trước runApp() để nạp ngôn ngữ đã lưu
  static Future<void> loadSavedLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedCode = prefs.getString(_prefKey) ?? 'vi';
      final locale = savedCode == 'en'
          ? const Locale('en', 'US')
          : const Locale('vi', 'VN');

      currentLocale.value = locale;
      await initializeDateFormatting(
          locale.languageCode == 'en' ? 'en_US' : 'vi_VN', null);
    } catch (_) {
      currentLocale.value = const Locale('vi', 'VN');
    }
  }

  /// Chuyển đổi ngôn ngữ ('vi' hoặc 'en')
  static Future<void> setLanguage(String languageCode) async {
    final code = languageCode.toLowerCase().trim();
    final newLocale =
        code == 'en' ? const Locale('en', 'US') : const Locale('vi', 'VN');

    if (currentLocale.value.languageCode == newLocale.languageCode) {
      return;
    }

    currentLocale.value = newLocale;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, newLocale.languageCode);
      await initializeDateFormatting(
          newLocale.languageCode == 'en' ? 'en_US' : 'vi_VN', null);
    } catch (_) {}
  }

  static bool get isVietnamese => currentLocale.value.languageCode == 'vi';
  static bool get isEnglish => currentLocale.value.languageCode == 'en';
  static String get currentLanguageCode => currentLocale.value.languageCode;
  static String get currentLanguageName =>
      isVietnamese ? 'Tiếng Việt' : 'English';
  static String get currentLanguageFlag => isVietnamese ? '🇻🇳' : '🇺🇸';
}

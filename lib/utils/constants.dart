import 'package:flutter/material.dart';

/// ============================================================
/// APP CONSTANTS & DESIGN SYSTEM TOKENS
/// Ngôn ngữ thiết kế: phẳng, trung tính, MỘT màu nhấn duy nhất.
/// Không gradient, không shadow; phân tách bằng viền hairline.
/// ============================================================
class AppColors {
  // Màu nhấn duy nhất (Petrol) — đủ tương phản trên cả nền sáng và tối.
  static const Color primary = Color(0xFF1F6F8B);
  static const Color primaryLight = Color(0xFF2B87A8);
  static const Color primaryAccent = Color(0xFF1F6F8B);
  static const Color secondary = Color(0xFF3E9BB9);

  // Semantic: dịu, ít bão hòa để số liệu dễ đọc lâu
  static const Color income = Color(0xFF2E8B57);
  static const Color incomeBackground = Color(0xFFEAF4EE);
  static const Color expense = Color(0xFFC0453A);
  static const Color expenseBackground = Color(0xFFF8ECEA);
  static const Color warning = Color(0xFFB7791F);
  static const Color warningBackground = Color(0xFFF8F1E3);
  static const Color info = Color(0xFF1F6F8B);
  static const Color infoBackground = Color(0xFFE6F0F4);

  // AI dùng chung màu nhấn, không còn bảng màu tím riêng.
  static const Color aiAccent = Color(0xFF1F6F8B);
  static const Color aiGradientStart = Color(0xFF1F6F8B);
  static const Color aiGradientEnd = Color(0xFF1F6F8B);
  static const Color aiBackgroundLight = Color(0xFFE6F0F4);

  // Thang trung tính ấm (tên giữ nguyên để tương thích)
  static const Color slate50 = Color(0xFFF6F6F4);
  static const Color slate100 = Color(0xFFEEEEEB);
  static const Color slate200 = Color(0xFFE2E2DE);
  static const Color slate300 = Color(0xFFCFCFCA);
  static const Color slate400 = Color(0xFF9A9B96);
  static const Color slate500 = Color(0xFF6D6E69);
  static const Color slate600 = Color(0xFF52534F);
  static const Color slate700 = Color(0xFF2B2E2C);
  static const Color slate800 = Color(0xFF1B1D1C);
  static const Color slate900 = Color(0xFF121413);

  // Dynamic Theme Colors via BuildContext (Theme.of(context))
  static Color getBackground(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? slate900 : slate50;
  }

  static Color getCard(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? slate800
        : Colors.white;
  }

  static Color getTextPrimary(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFEDEEEC)
        : const Color(0xFF1A1C1B);
  }

  static Color getTextSecondary(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF9DA19C)
        : slate500;
  }

  static Color getBorder(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? slate700 : slate200;
  }

  static Color getInputFill(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? slate700
        : slate100;
  }

  // Màn Auth & Fixed Light/Dark Themes
  static const Color fixedLightBackground = Color(0xFFF6F6F4);
  static const Color fixedLightCard = Colors.white;
  static const Color fixedLightTextPrimary = Color(0xFF1A1C1B);
  static const Color fixedLightTextSecondary = Color(0xFF6D6E69);

  static const Color darkBackground = Color(0xFF121413);
  static const Color darkSurface = Color(0xFF1B1D1C);
  static const Color darkCard = Color(0xFF1B1D1C);
  static const Color accentGreen = Color(0xFF2E8B57);
  static const Color glowGreen = Color(0xFF4FAE7B);
  static const Color darkTextPrimary = Color(0xFFEDEEEC);
  static const Color darkTextSecondary = Color(0xFF9DA19C);
  static const Color darkDivider = Color(0xFF2B2E2C);

  // Màn Báo cáo AI (Hero card)
  static const Color reportDark = Color(0xFF1B1D1C);
  static const Color reportDarkGreenText = Color(0xFF2E8B57);

  // Bo góc chuẩn toàn app
  static const double radiusCard = 12;
  static const double radiusControl = 10;
  static const double radiusChip = 8;
}

/// Extension tiện ích truy xuất màu & theme ngắn gọn trong BuildContext
extension ContextThemeExtension on BuildContext {
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get typography => Theme.of(this).textTheme;

  Color get appBackground => AppColors.getBackground(this);
  Color get appCard => AppColors.getCard(this);
  Color get appTextPrimary => AppColors.getTextPrimary(this);
  Color get appTextSecondary => AppColors.getTextSecondary(this);
  Color get appBorder => AppColors.getBorder(this);
  Color get appInputFill => AppColors.getInputFill(this);
}

class AppStrings {
  static const String appName = 'Finance AI';
}

/// Danh mục mặc định - Thu
class DefaultIncomeCategories {
  static const List<Map<String, dynamic>> categories = [
    {'name': 'Lương', 'icon': 'work', 'color': 0xFF10B981},
    {'name': 'Thưởng', 'icon': 'card_giftcard', 'color': 0xFFF59E0B},
    {'name': 'Bán hàng', 'icon': 'storefront', 'color': 0xFF3B82F6},
  ];
}

/// Danh mục mặc định - Chi
class DefaultExpenseCategories {
  static const List<Map<String, dynamic>> categories = [
    {'name': 'Ăn uống', 'icon': 'restaurant', 'color': 0xFFEF4444},
    {'name': 'Mua sắm', 'icon': 'shopping_bag', 'color': 0xFFF97316},
    {'name': 'Xăng xe', 'icon': 'local_gas_station', 'color': 0xFF84CC16},
    {'name': 'Học tập', 'icon': 'school', 'color': 0xFF3B82F6},
    {'name': 'Giải trí', 'icon': 'movie', 'color': 0xFF8B5CF6},
    {'name': 'Du lịch', 'icon': 'flight', 'color': 0xFF06B6D4},
    {'name': 'Y tế', 'icon': 'local_hospital', 'color': 0xFFEC4899},
  ];
}

/// Loại giao dịch
enum TransactionType { income, expense }

/// Loại ví
enum WalletType { cash, bank, eWallet, other }

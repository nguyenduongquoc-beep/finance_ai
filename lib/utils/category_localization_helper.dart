import 'package:flutter/widgets.dart';
import '../l10n/app_localizations.dart';

/// ============================================================
/// CATEGORY LOCALIZATION HELPER
/// Chuẩn hóa hiển thị đa ngôn ngữ cho danh mục hệ thống/mặc định
/// mà không làm thay đổi dữ liệu đã lưu trong Firestore và vẫn giữ
/// nguyên hoàn toàn tên danh mục tùy chỉnh do người dùng tạo.
/// ============================================================
class CategoryLocalizationHelper {
  CategoryLocalizationHelper._();

  static const Map<String, String> _canonicalKeyByNormalizedName = {
    // Mặc định Thu nhập (constants.dart) & biến thể tiếng Anh / icon template
    'lương': 'cat_sys_salary',
    'salary': 'cat_sys_salary',
    'thưởng': 'cat_sys_bonus',
    'bonus': 'cat_sys_bonus',
    'bán hàng': 'cat_sys_sales',
    'sales': 'cat_sys_sales',

    // Mặc định Chi tiêu (constants.dart) & biến thể tiếng Anh / icon template
    'ăn uống': 'cat_sys_food',
    'food': 'cat_sys_food',
    'food & dining': 'cat_sys_food',
    'dining': 'cat_sys_food',
    'mua sắm': 'cat_sys_shopping',
    'shopping': 'cat_sys_shopping',
    'xăng xe': 'cat_sys_fuel',
    'fuel': 'cat_sys_fuel',
    'học tập': 'cat_sys_education',
    'education': 'cat_sys_education',
    'giải trí': 'cat_sys_entertainment',
    'entertainment': 'cat_sys_entertainment',
    'du lịch': 'cat_sys_travel',
    'travel': 'cat_sys_travel',
    'y tế': 'cat_sys_healthcare',
    'healthcare': 'cat_sys_healthcare',

    // Các danh mục mẫu mở rộng trong category_icons.dart / Admin system_categories
    'nhà ở': 'cat_sys_housing',
    'housing': 'cat_sys_housing',
    'hóa đơn / tiện ích': 'cat_sys_bills_utils',
    'bills & utilities': 'cat_sys_bills_utils',
    'bills / utilities': 'cat_sys_bills_utils',
    'hóa đơn': 'cat_sys_bills',
    'bills': 'cat_sys_bills',
    'tiện ích': 'cat_sys_utilities',
    'utilities': 'cat_sys_utilities',
    'xăng xe / di chuyển': 'cat_sys_fuel_transport',
    'fuel & transport': 'cat_sys_fuel_transport',
    'di chuyển': 'cat_sys_transport',
    'đi lại': 'cat_sys_transport',
    'transport': 'cat_sys_transport',
    'transportation': 'cat_sys_transport',
    'học tập / giáo dục': 'cat_sys_edu_full',
    'giáo dục': 'cat_sys_education',
    'y tế / sức khỏe': 'cat_sys_health_full',
    'healthcare & wellness': 'cat_sys_health_full',
    'sức khỏe': 'cat_sys_health',
    'health': 'cat_sys_health',
    'thú cưng': 'cat_sys_pets',
    'pets': 'cat_sys_pets',
    'thể thao': 'cat_sys_sports',
    'sports': 'cat_sys_sports',
    'lương / công việc': 'cat_sys_salary_work',
    'salary & work': 'cat_sys_salary_work',
    'thưởng / quà tặng': 'cat_sys_bonus_gift',
    'bonus & gifts': 'cat_sys_bonus_gift',
    'bán hàng / kinh doanh': 'cat_sys_sales_biz',
    'sales & business': 'cat_sys_sales_biz',
    'đầu tư / lãi': 'cat_sys_investment',
    'investments & interest': 'cat_sys_investment',
    'đầu tư': 'cat_sys_invest_short',
    'investments': 'cat_sys_invest_short',
    'investment': 'cat_sys_invest_short',
    'khác': 'cat_sys_other',
    'other': 'cat_sys_other',
  };

  static const Map<String, List<String>> _searchSynonymsByKey = {
    'cat_sys_salary': ['Lương', 'Salary', 'Payroll', 'Income'],
    'cat_sys_bonus': ['Thưởng', 'Bonus', 'Reward'],
    'cat_sys_sales': ['Bán hàng', 'Sales'],
    'cat_sys_food': ['Ăn uống', 'Food', 'Food & Dining', 'Dining', 'Meal'],
    'cat_sys_shopping': ['Mua sắm', 'Shopping'],
    'cat_sys_fuel': ['Xăng xe', 'Fuel', 'Gas', 'Transport', 'Transportation'],
    'cat_sys_education': ['Học tập', 'Giáo dục', 'Education', 'Study'],
    'cat_sys_entertainment': ['Giải trí', 'Entertainment', 'Fun'],
    'cat_sys_travel': ['Du lịch', 'Travel', 'Trip'],
    'cat_sys_healthcare': [
      'Y tế',
      'Healthcare',
      'Health',
      'Medical',
      'Sức khỏe',
    ],
    'cat_sys_housing': ['Nhà ở', 'Housing', 'Home', 'Rent'],
    'cat_sys_bills_utils': [
      'Hóa đơn / Tiện ích',
      'Bills & Utilities',
      'Bills',
      'Utilities',
    ],
    'cat_sys_bills': ['Hóa đơn', 'Bills'],
    'cat_sys_utilities': ['Tiện ích', 'Utilities'],
    'cat_sys_fuel_transport': [
      'Xăng xe / Di chuyển',
      'Fuel & Transport',
      'Fuel',
      'Transport',
    ],
    'cat_sys_transport': ['Di chuyển', 'Đi lại', 'Transport', 'Transportation'],
    'cat_sys_edu_full': ['Học tập / Giáo dục', 'Education'],
    'cat_sys_health_full': ['Y tế / Sức khỏe', 'Healthcare & Wellness'],
    'cat_sys_health': ['Sức khỏe', 'Health'],
    'cat_sys_pets': ['Thú cưng', 'Pets'],
    'cat_sys_sports': ['Thể thao', 'Sports'],
    'cat_sys_salary_work': ['Lương / Công việc', 'Salary & Work'],
    'cat_sys_bonus_gift': ['Thưởng / Quà tặng', 'Bonus & Gifts'],
    'cat_sys_sales_biz': ['Bán hàng / Kinh doanh', 'Sales & Business'],
    'cat_sys_investment': ['Đầu tư / Lãi', 'Investments & Interest'],
    'cat_sys_invest_short': ['Đầu tư', 'Investments'],
    'cat_sys_other': ['Khác', 'Other'],
  };

  /// Trả về localization key nếu [rawName] khớp chính xác một danh mục hệ thống.
  static String? localizationKeyForName(String rawName) {
    final normalized = rawName.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    return _canonicalKeyByNormalizedName[normalized];
  }

  /// Kiểm tra xem [rawName] có phải danh mục hệ thống/mặc định đã biết không.
  static bool isSystemCategoryName(String rawName) {
    return localizationKeyForName(rawName) != null;
  }

  /// Trả về tên hiển thị theo ngôn ngữ hiện tại cho danh mục hệ thống,
  /// giữ nguyên nguyên văn nếu là danh mục do người dùng tự đặt.
  static String localizeName(String rawName) {
    final key = localizationKeyForName(rawName);
    if (key == null) return rawName;
    return AppLocalizations.tr(key);
  }

  /// Phiên bản dùng [BuildContext.tr] trong `build()` để Flutter tự rebuild
  /// ngay lập tức khi đổi ngôn ngữ.
  static String localizeNameWithContext(BuildContext context, String rawName) {
    final key = localizationKeyForName(rawName);
    if (key == null) return rawName;
    return context.tr(key);
  }

  /// Danh sách tất cả biến thể tên (gốc + đa ngôn ngữ + từ khóa đồng nghĩa chuẩn)
  /// phục vụ tìm kiếm hai chiều (VD: gõ "Food" vẫn tìm ra "Ăn uống").
  static List<String> allSearchVariants(String rawName) {
    final key = localizationKeyForName(rawName);
    if (key == null) return [rawName];
    final set = <String>{
      rawName,
      AppLocalizations.tr(key),
      ...(_searchSynonymsByKey[key] ?? const []),
    };
    return set.toList();
  }
}

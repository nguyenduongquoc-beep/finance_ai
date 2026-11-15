import 'package:flutter/material.dart';
import '../services/language_controller.dart';

/// ============================================================
/// APP LOCALIZATIONS (BỘ TỪ ĐIỂN ĐA NGÔN NGỮ TIẾNG VIỆT & ENGLISH)
/// ============================================================
class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// Tra cứu từ điển trực tiếp hoặc fallback theo locale hiện tại
  static String tr(String key, {Map<String, String>? params}) {
    final langCode = LanguageController.currentLanguageCode;
    final dict = langCode == 'en' ? _en : _vi;
    var value = dict[key] ?? _vi[key] ?? key;

    if (params != null && params.isNotEmpty) {
      params.forEach((paramKey, paramValue) {
        value = value.replaceAll('{$paramKey}', paramValue);
      });
    }

    return value;
  }

  /// Tra cứu bản dịch có Context
  String text(String key, {Map<String, String>? params}) {
    final dict = locale.languageCode == 'en' ? _en : _vi;
    var value = dict[key] ?? _vi[key] ?? key;

    if (params != null && params.isNotEmpty) {
      params.forEach((paramKey, paramValue) {
        value = value.replaceAll('{$paramKey}', paramValue);
      });
    }

    return value;
  }

  // ============================================================
  // TỪ ĐIỂN TIẾNG VIỆT (VIETNAMESE DICTIONARY)
  // ============================================================
  static const Map<String, String> _vi = {
    // --- CHUNG (COMMON) ---
    'app_name': 'Finance AI',
    'common_save': 'Lưu',
    'common_cancel': 'Hủy',
    'common_delete': 'Xóa',
    'common_edit': 'Sửa',
    'common_confirm': 'Xác nhận',
    'common_close': 'Đóng',
    'common_back': 'Quay lại',
    'common_search': 'Tìm kiếm',
    'common_filter': 'Bộ lọc',
    'common_all': 'Tất cả',
    'common_income': 'Thu nhập',
    'common_expense': 'Chi tiêu',
    'common_transfer': 'Chuyển khoản',
    'common_loading': 'Đang tải...',
    'common_success': 'Thành công',
    'common_error': 'Có lỗi xảy ra',
    'common_retry': 'Thử lại',
    'common_completed': 'Hoàn thành',
    'common_activated': 'Đã kích hoạt',
    'common_not_set': 'Chưa thiết lập',

    // --- NAVIGATION (THANH ĐIỀU HƯỚNG DƯỚI) ---
    'nav_home': 'Trang chủ',
    'nav_transactions': 'Giao dịch',
    'nav_add': 'Thêm',
    'nav_ai': 'Trợ lý AI',
    'nav_profile': 'Cá nhân',

    // --- MÀN HÌNH CHÍNH (HOME DASHBOARD) ---
    'home_total_balance': 'Tổng tài sản',
    'home_wallets_count': '{count} ví',
    'home_available_balance': 'Số dư khả dụng hiện tại',
    'home_monthly_income': 'Thu nhập tháng',
    'home_monthly_expense': 'Chi tiêu tháng',
    'home_quick_actions': 'Thao tác nhanh',
    'home_action_income': 'Thu nhập',
    'home_action_transfer': 'Chuyển tiền',
    'home_action_scan': 'Quét hóa đơn',
    'home_action_ai_report': 'Báo cáo AI',
    'home_monthly_overview': 'Tổng quan tháng {month}',
    'home_spending_trend': 'Xu hướng chi tiêu 6 tháng',
    'home_category_structure': 'Cơ cấu chi tiêu danh mục',
    'home_recent_transactions': 'Giao dịch gần đây',
    'home_view_all': 'Xem tất cả',
    'home_no_transactions': 'Chưa có giao dịch trong tháng này',
    'home_no_transactions_sub':
        'Ghi lại một khoản thu hoặc chi để bắt đầu theo dõi.',
    'home_add_transaction': 'Thêm giao dịch',
    'home_spent_percentage': 'Đã chi {percent}% thu nhập tháng này',
    'home_spent_exceeded': 'Chi tiêu đã vượt 100% thu nhập tháng này',

    // --- MÀN HÌNH CÁ NHÂN (PROFILE SCREEN) ---
    'profile_title': 'Cá nhân',
    'profile_edit_tooltip': 'Chỉnh sửa thông tin',
    'profile_financial_snapshot': 'TỔNG QUAN TÀI CHÍNH',
    'profile_actual_income': 'Thu thực tế: {amount}',
    'profile_monthly_declared': 'Khai báo: {amount}',
    'profile_actual_expense': 'Chi tiêu: {amount}',
    'profile_net_savings': 'Dư ròng: {amount}',
    'profile_no_income_declared': 'Chưa khai báo thu nhập',

    // Profile Sections
    'profile_sec_financial_mgmt': 'QUẢN LÝ TÀI CHÍNH',
    'profile_sec_ai_insights': 'PHÂN TÍCH & HỖ TRỢ AI',
    'profile_sec_account_security': 'TÀI KHOẢN & BẢO MẬT',
    'profile_sec_system_settings': 'TÙY CHỈNH HỆ THỐNG',
    'profile_sec_about': 'THÔNG TIN',

    // Profile Menu Items
    'profile_menu_wallets': 'Ví & tài khoản',
    'profile_menu_wallets_sub': 'Quản lý các nguồn tiền, tài khoản và số dư',
    'profile_menu_budgets': 'Ngân sách & hạn mức',
    'profile_menu_budgets_sub': 'Thiết lập và theo dõi hạn mức chi tiêu',
    'profile_menu_savings': 'Mục tiêu tiết kiệm',
    'profile_menu_savings_sub': 'Theo dõi tiến độ các mục tiêu tài chính',
    'profile_menu_categories': 'Danh mục phân loại',
    'profile_menu_categories_sub': 'Tùy chỉnh danh mục thu nhập và chi tiêu',
    'profile_menu_recurring': 'Giao dịch định kỳ & hóa đơn',
    'profile_menu_recurring_sub':
        'Quản lý các khoản chi lặp lại và hóa đơn đến hạn',

    'profile_menu_ai_insight': 'AI Financial Insight',
    'profile_menu_ai_insight_sub': 'Phân tích dòng tiền, chi tiêu & khuyến nghị',
    'profile_menu_ai_chat': 'Trợ lý AI Chat',
    'profile_menu_ai_chat_sub':
        'Trao đổi với trợ lý AI về tình hình tài chính',
    'profile_menu_ai_report': 'Báo cáo định kỳ AI',
    'profile_menu_ai_report_sub': 'Xem và xuất báo cáo tổng hợp chi tiết',
    'profile_menu_notifications': 'Thông báo & cảnh báo',
    'profile_menu_notifications_sub':
        'Cảnh báo ngân sách, giao dịch và lịch hẹn',

    'profile_menu_personal_info': 'Thông tin cá nhân',
    'profile_menu_personal_info_sub':
        'Họ tên, ảnh đại diện, thu nhập hàng tháng',
    'profile_menu_security': 'Bảo mật & Đổi mật khẩu',
    'profile_menu_security_sub': 'Quản lý mật khẩu và an toàn đăng nhập',
    'profile_menu_auth_method': 'Phương thức xác thực',

    'profile_menu_dark_mode': 'Giao diện tối',
    'profile_menu_dark_mode_on': 'Đang bật chế độ tối',
    'profile_menu_dark_mode_off': 'Đang bật chế độ sáng',
    'profile_menu_language': 'Ngôn ngữ hiển thị',
    'profile_menu_currency': 'Đơn vị tiền tệ',
    'profile_menu_currency_name': 'Việt Nam Đồng',
    'profile_menu_currency_sub': 'VNĐ (₫)',
    'profile_menu_currency_default': 'Mặc định đơn vị tiền tệ là VNĐ',

    'profile_menu_about': 'Về ứng dụng Finance AI',
    'profile_menu_about_sub': 'Thông tin nhóm phát triển và điều khoản',

    'profile_logout_btn': 'Đăng xuất tài khoản',
    'profile_logout_sub': 'Đăng xuất khỏi thiết bị này an toàn',
    'profile_logout_dialog_title': 'Đăng xuất tài khoản?',
    'profile_logout_dialog_sub':
        'Hẹn gặp lại bạn sớm! Bạn có thể đăng nhập lại bất cứ lúc nào để tiếp tục theo dõi thu chi.',
    'profile_logout_dialog_content':
        'Mọi dữ liệu tài chính & ngân sách của bạn vẫn được bảo toàn 100% trên đám mây.',
    'profile_logout_dialog_cancel': 'Hủy',
    'profile_logout_dialog_action': 'Đăng xuất',
    'profile_logout_failed': 'Đăng xuất không thành công, vui lòng thử lại',

    // Modal chọn ngôn ngữ (Language Selector Modal)
    'lang_picker_title': 'Ngôn ngữ hiển thị',
    'lang_picker_subtitle': 'Chọn ngôn ngữ giao diện của ứng dụng',
    'lang_vi': 'Tiếng Việt',
    'lang_vi_desc': 'Giao diện Tiếng Việt chuẩn xác',
    'lang_en': 'English',
    'lang_en_desc': 'Standard English interface',
    'lang_changed_toast': 'Đã đổi ngôn ngữ sang Tiếng Việt',

    // --- GIAO DỊCH (TRANSACTIONS) ---
    'tx_add_title': 'Thêm giao dịch',
    'tx_edit_title': 'Sửa giao dịch',
    'tx_type_selector': 'Phân loại giao dịch',
    'tx_type_expense': 'Chi tiền',
    'tx_type_income': 'Thu tiền',
    'tx_type_transfer': 'Chuyển tiền',
    'tx_amount_label': 'Số tiền giao dịch',
    'tx_category_label': 'Danh mục giao dịch',
    'tx_wallet_label': 'Ví nguồn',
    'tx_dest_wallet_label': 'Ví đích',
    'tx_date_label': 'Thời gian',
    'tx_note_label': 'Ghi chú',
    'tx_note_hint': 'Nhập nội dung ghi chú (không bắt buộc)...',
    'tx_save_template': 'Lưu thành mẫu giao dịch',
    'tx_save_button': 'Lưu giao dịch',
    'tx_update_button': 'Cập nhật giao dịch',
    'tx_history_title': 'Lịch sử giao dịch',

    // --- GIAO DỊCH ĐỊNH KỲ (RECURRING) ---
    'recurring_title': 'Giao dịch định kỳ',
    'recurring_hero_title': 'Tổng chi cố định dự kiến / kỳ',
    'recurring_active_count': '{count} lịch bật',
    'recurring_due_count': '{count} cần xử lý',
    'recurring_expected_income': 'Dự thu: {amount}',
    'recurring_active_summary': 'Đang bật: {active}/{total} lịch',
    'recurring_freq_daily': 'Hàng ngày',
    'recurring_freq_weekly': 'Hàng tuần',
    'recurring_freq_monthly': 'Hàng tháng',
    'recurring_freq_yearly': 'Hàng năm',
    'recurring_btn_add': 'Thêm lịch định kỳ',
    'recurring_btn_skip': 'Bỏ qua',
    'recurring_btn_process': 'Ghi nhận',

    // --- VÍ (WALLETS) ---
    'wallet_title': 'Quản lý ví',
    'wallet_total_assets': 'TỔNG TÀI SẢN',
    'wallet_in_use': '{count} ví đang dùng',
    'wallet_total_balance_sub': 'Tổng số dư các ví hoạt động',
    'wallet_add_button': 'Thêm ví mới',
    'wallet_type_cash': 'Tiền mặt',
    'wallet_type_bank': 'Tài khoản ngân hàng',
    'wallet_type_ewallet': 'Ví điện tử',
    'wallet_type_other': 'Khác',

    // --- DANH MỤC (CATEGORIES) ---
    'category_title': 'Quản lý danh mục',
    'category_income_tab': 'Danh mục Thu',
    'category_expense_tab': 'Danh mục Chi',
    'category_add_btn': 'Thêm danh mục mới',

    // --- BÁO CÁO AI (AI REPORT) ---
    'ai_report_title': 'Báo cáo chi tiêu AI',
    'ai_report_month_header': 'BÁO CÁO THÁNG {month}/{year}',
    'ai_report_total_expense': 'Tổng chi tiêu tháng này',
    'ai_report_net_savings': 'Tiết kiệm ròng',
    'ai_report_vs_last_month': 'So với tháng trước',
    'ai_report_no_prev_month': 'Chưa có kỳ trước',
    'ai_report_increase': 'Tăng {percent}%',
    'ai_report_decrease': 'Giảm {percent}%',
    'ai_report_export_pdf': 'Xuất báo cáo PDF',
  };

  // ============================================================
  // TỪ ĐIỂN TIẾNG ANH (ENGLISH DICTIONARY)
  // ============================================================
  static const Map<String, String> _en = {
    // --- COMMON ---
    'app_name': 'Finance AI',
    'common_save': 'Save',
    'common_cancel': 'Cancel',
    'common_delete': 'Delete',
    'common_edit': 'Edit',
    'common_confirm': 'Confirm',
    'common_close': 'Close',
    'common_back': 'Back',
    'common_search': 'Search',
    'common_filter': 'Filter',
    'common_all': 'All',
    'common_income': 'Income',
    'common_expense': 'Expense',
    'common_transfer': 'Transfer',
    'common_loading': 'Loading...',
    'common_success': 'Success',
    'common_error': 'An error occurred',
    'common_retry': 'Retry',
    'common_completed': 'Completed',
    'common_activated': 'Activated',
    'common_not_set': 'Not set',

    // --- NAVIGATION ---
    'nav_home': 'Home',
    'nav_transactions': 'Transactions',
    'nav_add': 'Add',
    'nav_ai': 'AI Assistant',
    'nav_profile': 'Profile',

    // --- HOME DASHBOARD ---
    'home_total_balance': 'Total Balance',
    'home_wallets_count': '{count} wallets',
    'home_available_balance': 'Current available balance',
    'home_monthly_income': 'Monthly income',
    'home_monthly_expense': 'Monthly expense',
    'home_quick_actions': 'Quick Actions',
    'home_action_income': 'Income',
    'home_action_transfer': 'Transfer',
    'home_action_scan': 'Scan Receipt',
    'home_action_ai_report': 'AI Report',
    'home_monthly_overview': 'Overview for {month}',
    'home_spending_trend': '6-Month Spending Trend',
    'home_category_structure': 'Category Spending Breakdown',
    'home_recent_transactions': 'Recent Transactions',
    'home_view_all': 'View All',
    'home_no_transactions': 'No transactions this month',
    'home_no_transactions_sub':
        'Record an income or expense to begin tracking.',
    'home_add_transaction': 'Add Transaction',
    'home_spent_percentage': 'Spent {percent}% of income this month',
    'home_spent_exceeded': 'Spending exceeded 100% of income this month',

    // --- PROFILE SCREEN ---
    'profile_title': 'Profile',
    'profile_edit_tooltip': 'Edit profile',
    'profile_financial_snapshot': 'FINANCIAL SNAPSHOT',
    'profile_actual_income': 'Actual Income: {amount}',
    'profile_monthly_declared': 'Declared: {amount}',
    'profile_actual_expense': 'Expense: {amount}',
    'profile_net_savings': 'Net Savings: {amount}',
    'profile_no_income_declared': 'No declared income yet',

    // Profile Sections
    'profile_sec_financial_mgmt': 'FINANCIAL MANAGEMENT',
    'profile_sec_ai_insights': 'AI INSIGHTS & TOOLS',
    'profile_sec_account_security': 'ACCOUNT & SECURITY',
    'profile_sec_system_settings': 'SYSTEM PREFERENCES',
    'profile_sec_about': 'INFORMATION',

    // Profile Menu Items
    'profile_menu_wallets': 'Wallets & Accounts',
    'profile_menu_wallets_sub': 'Manage payment sources, accounts and balances',
    'profile_menu_budgets': 'Budgets & Limits',
    'profile_menu_budgets_sub': 'Set and monitor spending limits',
    'profile_menu_savings': 'Saving Goals',
    'profile_menu_savings_sub': 'Track financial goals and progress',
    'profile_menu_categories': 'Categories',
    'profile_menu_categories_sub': 'Customize income and expense categories',
    'profile_menu_recurring': 'Recurring & Bills',
    'profile_menu_recurring_sub': 'Manage scheduled expenses and upcoming bills',

    'profile_menu_ai_insight': 'AI Financial Insight',
    'profile_menu_ai_insight_sub': 'Cashflow analysis, spending & suggestions',
    'profile_menu_ai_chat': 'AI Chat Assistant',
    'profile_menu_ai_chat_sub': 'Discuss your financial health with AI',
    'profile_menu_ai_report': 'AI Periodic Report',
    'profile_menu_ai_report_sub': 'View and export detailed financial reports',
    'profile_menu_notifications': 'Notifications & Alerts',
    'profile_menu_notifications_sub': 'Budget alerts, reminders and schedules',

    'profile_menu_personal_info': 'Personal Information',
    'profile_menu_personal_info_sub': 'Full name, avatar and monthly income',
    'profile_menu_security': 'Security & Password',
    'profile_menu_security_sub': 'Manage password and login protection',
    'profile_menu_auth_method': 'Authentication Method',

    'profile_menu_dark_mode': 'Dark Mode',
    'profile_menu_dark_mode_on': 'Dark mode enabled',
    'profile_menu_dark_mode_off': 'Light mode enabled',
    'profile_menu_language': 'Display Language',
    'profile_menu_currency': 'Currency',
    'profile_menu_currency_name': 'Vietnamese Dong',
    'profile_menu_currency_sub': 'VNĐ (₫)',
    'profile_menu_currency_default': 'Default currency is VNĐ',

    'profile_menu_about': 'About Finance AI',
    'profile_menu_about_sub': 'Developer team info and terms of service',

    'profile_logout_btn': 'Log Out Account',
    'profile_logout_sub': 'Safely log out from this device',
    'profile_logout_dialog_title': 'Confirm Logout',
    'profile_logout_dialog_sub': 'Your active session will end',
    'profile_logout_dialog_content':
        'Your transaction history, wallets and AI analyses are securely synced with the cloud. You can sign back in anytime.',
    'profile_logout_dialog_cancel': 'Cancel',
    'profile_logout_dialog_action': 'Log Out',
    'profile_logout_failed': 'Logout was unsuccessful, please try again',

    // Language Picker Modal
    'lang_picker_title': 'Display Language',
    'lang_picker_subtitle': 'Choose your preferred app interface language',
    'lang_vi': 'Tiếng Việt',
    'lang_vi_desc': 'Giao diện Tiếng Việt chuẩn xác',
    'lang_en': 'English',
    'lang_en_desc': 'Standard English interface',
    'lang_changed_toast': 'Language changed to English',

    // --- TRANSACTIONS ---
    'tx_add_title': 'Add Transaction',
    'tx_edit_title': 'Edit Transaction',
    'tx_type_selector': 'Transaction Type',
    'tx_type_expense': 'Expense',
    'tx_type_income': 'Income',
    'tx_type_transfer': 'Transfer',
    'tx_amount_label': 'Transaction Amount',
    'tx_category_label': 'Transaction Category',
    'tx_wallet_label': 'Source Wallet',
    'tx_dest_wallet_label': 'Destination Wallet',
    'tx_date_label': 'Date & Time',
    'tx_note_label': 'Note',
    'tx_note_hint': 'Enter note description (optional)...',
    'tx_save_template': 'Save as Template',
    'tx_save_button': 'Save Transaction',
    'tx_update_button': 'Update Transaction',
    'tx_history_title': 'Transaction History',

    // --- RECURRING TRANSACTIONS ---
    'recurring_title': 'Recurring Transactions',
    'recurring_hero_title': 'Expected Recurring Expense / Cycle',
    'recurring_active_count': '{count} active',
    'recurring_due_count': '{count} due to process',
    'recurring_expected_income': 'Expected Income: {amount}',
    'recurring_active_summary': 'Active: {active}/{total} schedules',
    'recurring_freq_daily': 'Daily',
    'recurring_freq_weekly': 'Weekly',
    'recurring_freq_monthly': 'Monthly',
    'recurring_freq_yearly': 'Yearly',
    'recurring_btn_add': 'Add Recurring Schedule',
    'recurring_btn_skip': 'Skip',
    'recurring_btn_process': 'Record',

    // --- WALLETS ---
    'wallet_title': 'Wallet Management',
    'wallet_total_assets': 'TOTAL BALANCE',
    'wallet_in_use': '{count} active wallets',
    'wallet_total_balance_sub': 'Total balance across active wallets',
    'wallet_add_button': 'Add New Wallet',
    'wallet_type_cash': 'Cash',
    'wallet_type_bank': 'Bank Account',
    'wallet_type_ewallet': 'E-Wallet',
    'wallet_type_other': 'Other',

    // --- CATEGORIES ---
    'category_title': 'Category Management',
    'category_income_tab': 'Income Categories',
    'category_expense_tab': 'Expense Categories',
    'category_add_btn': 'Add New Category',

    // --- AI REPORT ---
    'ai_report_title': 'AI Spending Report',
    'ai_report_month_header': 'REPORT FOR {month}/{year}',
    'ai_report_total_expense': 'Total Monthly Expense',
    'ai_report_net_savings': 'Net Savings',
    'ai_report_vs_last_month': 'Compared to Last Month',
    'ai_report_no_prev_month': 'No prior period',
    'ai_report_increase': '+{percent}% higher',
    'ai_report_decrease': '-{percent}% lower',
    'ai_report_export_pdf': 'Export PDF Report',
  };
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return ['vi', 'en'].contains(locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

/// Extension tiện ích gọi nhanh `context.tr('key', params: {...})`
extension LocalizationContextExtension on BuildContext {
  String tr(String key, {Map<String, String>? params}) {
    final localizations = AppLocalizations.of(this);
    if (localizations != null) {
      return localizations.text(key, params: params);
    }
    return AppLocalizations.tr(key, params: params);
  }
}

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/user_model.dart';
import '../models/support_ticket_model.dart';
import '../models/transaction_model.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/language_controller.dart';
import '../services/support_service.dart';
import '../l10n/app_localizations.dart';
import '../utils/constants.dart';
import '../utils/formatters.dart';
import 'auth/login_screen.dart';
import 'management/wallet_management_screen.dart';
import 'management/category_management_screen.dart';
import 'management/budget_management_screen.dart';
import 'management/saving_goal_screen.dart';
import 'management/recurring_transaction_screen.dart';
import 'ai/ai_insight_screen.dart';
import 'ai/ai_chat_screen.dart';
import 'ai/ai_report_screen.dart';
import 'notification_screen.dart';
import 'personal_info_screen.dart';
import 'account_security_screen.dart';
import 'about_app_screen.dart';
import 'support/support_center_screen.dart';
import '../widgets/stream_error_widget.dart';
import '../widgets/app_snackbar.dart';

/// Màn hình Cá nhân — Tối ưu hóa UI/UX Fintech chuyên nghiệp
/// Kết hợp Hồ sơ người dùng, Financial Snapshot thực tế và Cổng điều hướng quản lý tài chính.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _firestoreService = FirestoreService();
  final _authService = AuthService();
  final _supportService = SupportService();
  late final Stream<List<SupportTicket>> _unreadSupportTicketsStream;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _unreadSupportTicketsStream = _supportService.streamUnreadUserTickets(uid);
  }

  ImageProvider? _avatarImage(String? path) {
    if (path != null && path.isNotEmpty) {
      final file = File(path);
      if (file.existsSync()) return FileImage(file);
    }
    final photoUrl = FirebaseAuth.instance.currentUser?.photoURL;
    if (photoUrl != null && photoUrl.isNotEmpty) {
      return NetworkImage(photoUrl);
    }
    return null;
  }

  /// Quy trình đăng xuất an toàn: Hộp thoại xác nhận hiện đại, đóng khi chạm ra ngoài (tương đương Hủy),
  /// ngăn double submit, làm sạch ngăn xếp điều hướng và bảo toàn dữ liệu Firebase.
  Future<void> _handleLogout() async {
    final email = _authService.currentUser?.email;
    final shouldLogout = await showLogoutConfirmationDialog(
      context,
      userEmail: email,
    );

    if (shouldLogout == true && mounted) {
      try {
        // Thực hiện signOut qua AuthService (GoogleSignIn + FirebaseAuth)
        // Không xóa bất kỳ dữ liệu nào trong Firestore
        await _authService.signOut();

        if (mounted) {
          // Xóa toàn bộ stack và đưa về LoginScreen để không thể Back lại
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
          );
        }
      } catch (e) {
        if (mounted) {
          AppSnackbar.show(
            context,
            context.tr('profile_logout_failed'),
            isError: true,
          );
        }
      }
    }
  }

  /// Hộp thoại chọn ngôn ngữ hiển thị (Tiếng Việt & English)
  void _showLanguagePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.appCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        final currentCode = LanguageController.currentLanguageCode;

        Widget buildOption({
          required String code,
          required String flag,
          required String title,
          required String subtitle,
        }) {
          final isSelected = currentCode == code;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () async {
                await LanguageController.setLanguage(code);
                try {
                  final uid = _authService.currentUser?.uid ?? '';
                  if (uid.isNotEmpty) {
                    unawaited(
                      _firestoreService.resyncLocalNotifications(
                        uid,
                        force: true,
                      ),
                    );
                  }
                } catch (_) {}
                if (sheetContext.mounted) {
                  Navigator.of(sheetContext).pop();
                }
                if (context.mounted) {
                  AppSnackbar.show(
                    context,
                    code == 'en'
                        ? context.tr('profile_lang_changed_en')
                        : context.tr('profile_lang_changed_vi'),
                  );
                }
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary.withValues(alpha: 0.1)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primary.withValues(alpha: 0.35)
                        : context.appBorder.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      flag,
                      style: const TextStyle(fontSize: 26),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: isSelected
                                  ? AppColors.primary
                                  : context.appTextPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 12,
                              color: context.appTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isSelected)
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.appBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color:
                            const Color(0xFF26A69A).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.language_rounded,
                        color: Color(0xFF26A69A),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr('lang_picker_title'),
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: context.appTextPrimary,
                            ),
                          ),
                          Text(
                            context.tr('lang_picker_subtitle'),
                            style: TextStyle(
                              fontSize: 12,
                              color: context.appTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                buildOption(
                  code: 'vi',
                  flag: '🇻🇳',
                  title: context.tr('lang_vi'),
                  subtitle: context.tr('lang_vi_desc'),
                ),
                buildOption(
                  code: 'en',
                  flag: '🇺🇸',
                  title: context.tr('lang_en'),
                  subtitle: context.tr('lang_en_desc'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        title: Text(
          context.tr('profile_title'),
          style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.manage_accounts_outlined),
            tooltip: context.tr('profile_edit_tooltip'),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PersonalInfoScreen()),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<AppUser?>(
        stream: _firestoreService.streamUserProfile(uid),
        builder: (context, userSnap) {
          if (userSnap.hasError) {
            return StreamErrorWidget(error: userSnap.error.toString());
          }
          final user = userSnap.data;

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // 1. Profile Header (Gọn gàng & Hiện đại, nhấn vào để xem chi tiết tài khoản)
              _buildProfileHeader(user),
              const SizedBox(height: 14),

              // 2. Financial Snapshot (Tình hình tài chính tháng này từ dữ liệu thực tế)
              _buildFinancialSnapshot(
                uid,
                now,
                startOfMonth,
                endOfMonth,
              ),
              const SizedBox(height: 18),

              // 3. QUẢN LÝ TÀI CHÍNH (Hierarchy rõ ràng, có mô tả chức năng)
              _buildSectionTitle(context.tr('profile_sec_financial_mgmt')),
              _buildGroupContainer([
                _buildMenuItem(
                  icon: Icons.account_balance_wallet_outlined,
                  iconColor: AppColors.primaryLight,
                  iconBgColor: AppColors.primaryLight.withAlpha(25),
                  title: context.tr('profile_menu_wallets'),
                  subtitle: context.tr('profile_menu_wallets_sub'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const WalletManagementScreen()),
                    );
                  },
                ),
                _buildMenuItem(
                  icon: Icons.pie_chart_outline_rounded,
                  iconColor: const Color(0xFFE57373),
                  iconBgColor: const Color(0xFFE57373).withAlpha(25),
                  title: context.tr('profile_menu_budgets'),
                  subtitle: context.tr('profile_menu_budgets_sub'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const BudgetManagementScreen()),
                    );
                  },
                ),
                _buildMenuItem(
                  icon: Icons.flag_outlined,
                  iconColor: const Color(0xFF4DB6AC),
                  iconBgColor: const Color(0xFF4DB6AC).withAlpha(25),
                  title: context.tr('profile_menu_savings'),
                  subtitle: context.tr('profile_menu_savings_sub'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const SavingGoalScreen()),
                    );
                  },
                ),
                _buildMenuItem(
                  icon: Icons.category_outlined,
                  iconColor: const Color(0xFFFFB74D),
                  iconBgColor: const Color(0xFFFFB74D).withAlpha(25),
                  title: context.tr('profile_menu_categories'),
                  subtitle: context.tr('profile_menu_categories_sub'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const CategoryManagementScreen()),
                    );
                  },
                ),
                _buildMenuItem(
                  icon: Icons.repeat_rounded,
                  iconColor: const Color(0xFF64B5F6),
                  iconBgColor: const Color(0xFF64B5F6).withAlpha(25),
                  title: context.tr('profile_menu_recurring'),
                  subtitle: context.tr('profile_menu_recurring_sub'),
                  showDivider: false,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const RecurringTransactionScreen()),
                    );
                  },
                ),
              ]),
              const SizedBox(height: 18),

              // 4. PHÂN TÍCH & HỖ TRỢ AI
              _buildSectionTitle(context.tr('profile_sec_ai_insights')),
              _buildGroupContainer([
                _buildMenuItem(
                  icon: Icons.insights_rounded,
                  iconColor: const Color(0xFF9575CD),
                  iconBgColor: const Color(0xFF9575CD).withAlpha(25),
                  title: context.tr('profile_menu_ai_insight'),
                  subtitle: context.tr('profile_menu_ai_insight_sub'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const AiInsightScreen()),
                    );
                  },
                ),
                _buildMenuItem(
                  icon: Icons.chat_bubble_outline_rounded,
                  iconColor: AppColors.primary,
                  iconBgColor: AppColors.primary.withAlpha(25),
                  title: context.tr('profile_menu_ai_chat'),
                  subtitle: context.tr('profile_menu_ai_chat_sub'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AiChatScreen()),
                    );
                  },
                ),
                _buildMenuItem(
                  icon: Icons.assessment_outlined,
                  iconColor: const Color(0xFF4FC3F7),
                  iconBgColor: const Color(0xFF4FC3F7).withAlpha(25),
                  title: context.tr('profile_menu_ai_report'),
                  subtitle: context.tr('profile_menu_ai_report_sub'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AiReportScreen()),
                    );
                  },
                ),
                _buildMenuItem(
                  icon: Icons.notifications_none_rounded,
                  iconColor: const Color(0xFFFF8A65),
                  iconBgColor: const Color(0xFFFF8A65).withAlpha(25),
                  title: context.tr('profile_menu_notifications'),
                  subtitle: context.tr('profile_menu_notifications_sub'),
                  showDivider: false,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const NotificationScreen()),
                    );
                  },
                ),
              ]),
              const SizedBox(height: 18),

              // 5. TÀI KHOẢN & BẢO MẬT (Phân tách rõ ràng giữa hồ sơ và bảo mật)
              _buildSectionTitle(context.tr('profile_sec_account_security')),
              _buildGroupContainer([
                _buildMenuItem(
                  icon: Icons.person_outline_rounded,
                  iconColor: AppColors.primaryLight,
                  iconBgColor: AppColors.primaryLight.withAlpha(25),
                  title: context.tr('profile_menu_personal_info'),
                  subtitle: context.tr('profile_menu_personal_info_sub'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const PersonalInfoScreen()),
                    );
                  },
                ),
                _buildMenuItem(
                  icon: Icons.lock_outline_rounded,
                  iconColor: const Color(0xFF78909C),
                  iconBgColor: const Color(0xFF78909C).withAlpha(25),
                  title: context.tr('profile_menu_security'),
                  subtitle: context.tr('profile_menu_security_sub'),
                  showDivider: false,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const AccountSecurityScreen()),
                    );
                  },
                ),
              ]),
              const SizedBox(height: 18),

              // 6. CÀI ĐẶT & HỆ THỐNG
              _buildSectionTitle(context.tr('profile_sec_system_settings')),
              _buildGroupContainer([
                _buildMenuItem(
                  icon: Icons.language_rounded,
                  iconColor: const Color(0xFF26A69A),
                  iconBgColor: const Color(0xFF26A69A).withAlpha(25),
                  title: context.tr('profile_menu_language'),
                  subtitle: LanguageController.currentLanguageName,
                  trailingText: LanguageController.isVietnamese ? 'VN' : 'EN',
                  onTap: () => _showLanguagePicker(context),
                ),
                _buildMenuItem(
                  icon: Icons.payments_outlined,
                  iconColor: const Color(0xFFFFA726),
                  iconBgColor: const Color(0xFFFFA726).withAlpha(25),
                  title: context.tr('profile_menu_currency'),
                  subtitle: context.tr('profile_menu_currency_name'),
                  trailingText: context.tr('profile_menu_currency_sub'),
                  showDivider: false,
                  onTap: () {
                    AppSnackbar.show(
                      context,
                      context.tr('profile_menu_currency_default'),
                    );
                  },
                ),
              ]),
              const SizedBox(height: 18),

              // 7. HỖ TRỢ & THÔNG TIN ỨNG DỤNG
              _buildSectionTitle(context.tr('profile_sec_about')),
              _buildGroupContainer([
                StreamBuilder<List<SupportTicket>>(
                  stream: _unreadSupportTicketsStream,
                  builder: (context, supportSnap) {
                    final unreadSupportCount = supportSnap.data?.length ?? 0;
                    return _buildMenuItem(
                      icon: Icons.support_agent_rounded,
                      iconColor: AppColors.primary,
                      iconBgColor: AppColors.primary.withAlpha(25),
                      title: context.tr('profile_menu_support'),
                      subtitle: context.tr('profile_menu_support_sub'),
                      trailingText: unreadSupportCount > 0
                          ? '$unreadSupportCount · ${context.tr('support_unread_badge')}'
                          : null,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SupportCenterScreen(),
                          ),
                        );
                      },
                    );
                  },
                ),
                _buildMenuItem(
                  icon: Icons.info_outline_rounded,
                  iconColor: const Color(0xFF7E57C2),
                  iconBgColor: const Color(0xFF7E57C2).withAlpha(25),
                  title: context.tr('profile_menu_about'),
                  subtitle: context.tr('profile_menu_about_sub'),
                  trailingText: 'v1.0.0',
                  showDivider: false,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AboutAppScreen()),
                    );
                  },
                ),
              ]),
              const SizedBox(height: 22),

              // 8. ĐĂNG XUẤT (Thiết kế hiện đại, đồng bộ với các thẻ tính năng)
              Container(
                decoration: BoxDecoration(
                  color: context.appCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.expense.withAlpha(55)),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.expense.withAlpha(10),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: const ValueKey('profile_logout_button'),
                    borderRadius: BorderRadius.circular(16),
                    onTap: _handleLogout,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppColors.expense.withAlpha(22),
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: const Icon(
                              Icons.logout_rounded,
                              color: AppColors.expense,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.tr('profile_logout_btn'),
                                  style: const TextStyle(
                                    color: AppColors.expense,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  context.tr('profile_logout_sub'),
                                  style: TextStyle(
                                    color: context.appTextSecondary,
                                    fontSize: 11.5,
                                    height: 1.25,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: AppColors.expense.withAlpha(16),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.chevron_right_rounded,
                              color: AppColors.expense,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),
              Center(
                child: Text(
                  'Finance AI • ${context.tr('app_name')}',
                  style:
                      TextStyle(color: context.appTextSecondary, fontSize: 11),
                ),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  /// 1. Profile Header
  Widget _buildProfileHeader(AppUser? user) {
    final avatar = _avatarImage(user?.avatar);
    final initial =
        (user?.name.isNotEmpty == true) ? user!.name[0].toUpperCase() : 'U';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.appBorder),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PersonalInfoScreen()),
          );
        },
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 30,
              backgroundColor: AppColors.primaryLight.withAlpha(30),
              backgroundImage: avatar,
              child: avatar == null
                  ? Text(
                      initial,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryLight,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 14),

            // Tên & Email
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user?.name.isNotEmpty == true
                        ? user!.name
                        : context.tr('common_user'),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: context.appTextPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    user?.email.isNotEmpty == true
                        ? user!.email
                        : (_authService.currentUser?.email ?? ''),
                    style: TextStyle(
                      fontSize: 12,
                      color: context.appTextSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withAlpha(18),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _authService.authProviderLabel,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryLight,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Biểu tượng điều hướng xem thông tin tài khoản
            Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: context.appTextSecondary,
            ),
          ],
        ),
      ),
    );
  }

  /// 2. Financial Snapshot (Dữ liệu thực tế của tháng hiện tại)
  Widget _buildFinancialSnapshot(
    String uid,
    DateTime now,
    DateTime startOfMonth,
    DateTime endOfMonth,
  ) {
    return StreamBuilder<List<AppTransaction>>(
      stream: _firestoreService.streamTransactions(
        uid,
        from: startOfMonth,
        to: endOfMonth,
      ),
      builder: (context, snapshot) {
        final transactions = snapshot.data ?? [];

        double income = 0;
        double expense = 0;

        for (final t in transactions) {
          if (t.type == 'income') {
            income += t.amount;
          } else if (t.type == 'expense') {
            expense += t.amount;
          }
        }

        final remaining = income - expense;
        final savingsRate = income > 0 && remaining > 0
            ? ((remaining / income) * 100).clamp(0, 100).round()
            : 0;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.appCard,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: context.appBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header of Snapshot
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withAlpha(20),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.insights_rounded,
                            size: 16,
                            color: AppColors.primaryLight,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            context.tr(
                              'profile_month_status',
                              params: {
                                'month': '${now.month}',
                                'year': '${now.year}',
                              },
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                              color: context.appTextSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Savings rate badge
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 145),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: remaining >= 0
                            ? AppColors.incomeBackground
                            : AppColors.expenseBackground,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          context.tr(
                            'profile_savings_rate',
                            params: {'pct': '$savingsRate'},
                          ),
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: remaining >= 0
                                ? AppColors.income
                                : AppColors.expense,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Columns of financial data
              Row(
                children: [
                  // Thu nhập thực tế
                  Expanded(
                    child: _buildSnapshotColumn(
                      label: context.tr('common_income'),
                      amountStr: '+${AppFormatters.compactCurrency(income)}',
                      color: AppColors.income,
                    ),
                  ),
                  Container(width: 1, height: 32, color: context.appBorder),
                  // Chi tiêu thực tế
                  Expanded(
                    child: _buildSnapshotColumn(
                      label: context.tr('common_expense'),
                      amountStr: '-${AppFormatters.compactCurrency(expense)}',
                      color: AppColors.expense,
                    ),
                  ),
                  Container(width: 1, height: 32, color: context.appBorder),
                  // Dòng tiền ròng
                  Expanded(
                    child: _buildSnapshotColumn(
                      label: context.tr('profile_cash_flow'),
                      amountStr:
                          '${remaining >= 0 ? '+' : ''}${AppFormatters.compactCurrency(remaining)}',
                      color:
                          remaining >= 0 ? AppColors.income : AppColors.expense,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Mini progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: income > 0 ? (expense / income).clamp(0.0, 1.0) : 0.0,
                  minHeight: 5,
                  backgroundColor: AppColors.income.withAlpha(40),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppColors.expense),
                ),
              ),
              const SizedBox(height: 10),
              // Quick link to AI Insight
              InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AiInsightScreen()),
                  );
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          context.tr('profile_view_ai_analysis'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryLight,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        size: 14,
                        color: AppColors.primaryLight,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSnapshotColumn({
    required String label,
    required String amountStr,
    required Color color,
  }) {
    return Column(
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            color: context.appTextSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            amountStr,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  /// Tiêu đề phân mục
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: context.appTextSecondary,
        ),
      ),
    );
  }

  /// Khung gom nhóm các thiết lập (Grouped Container)
  Widget _buildGroupContainer(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: context.appCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.appBorder),
      ),
      child: Column(
        children: children,
      ),
    );
  }

  /// Item menu chuẩn Fintech: Icon bo tròn + Title + Subtitle + Trailing
  Widget _buildMenuItem({
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required String title,
    required String subtitle,
    String? trailingText,
    Widget? trailing,
    VoidCallback? onTap,
    bool showDivider = true,
  }) {
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  // Icon container
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: iconBgColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: iconColor, size: 20),
                  ),
                  const SizedBox(width: 12),

                  // Title + Subtitle
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: context.appTextPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 11,
                            color: context.appTextSecondary,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Trailing
                  if (trailing != null)
                    trailing
                  else if (trailingText != null) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        trailingText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: context.appTextSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: context.appTextSecondary,
                    ),
                  ] else
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: context.appTextSecondary,
                    ),
                ],
              ),
            ),
          ),
        ),
        if (showDivider) const Divider(height: 1, indent: 64, endIndent: 16),
      ],
    );
  }
}

/// Hiển thị hộp thoại xác nhận đăng xuất phong cách Fintech hiện đại.
/// - Cho phép chạm ra ngoài vùng hộp thoại (`barrierDismissible: true`) hoặc bấm nút `X` / `Hủy` để đóng (tương đương hủy bỏ).
/// - Hai nút hành động cân đối nằm ngang, có thẻ cam kết an toàn dữ liệu đám mây để giao diện thân thiện, bớt khô khan.
Future<bool?> showLogoutConfirmationDialog(
  BuildContext context, {
  String? userEmail,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withAlpha(135),
    builder: (ctx) {
      bool isLoggingOut = false;
      return StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final isDark = dialogContext.isDarkMode;
          return Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                decoration: BoxDecoration(
                  color: dialogContext.appCard,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: dialogContext.appBorder,
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(isDark ? 90 : 35),
                      blurRadius: 28,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Hàng nút đóng nhanh góc phải trên cùng
                    Align(
                      alignment: Alignment.topRight,
                      child: Material(
                        color: dialogContext.appInputFill,
                        shape: const CircleBorder(),
                        child: InkWell(
                          key: const ValueKey('logout_dialog_close'),
                          customBorder: const CircleBorder(),
                          onTap: isLoggingOut
                              ? null
                              : () => Navigator.of(ctx).pop(false),
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: dialogContext.appTextSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Biểu tượng trung tâm nhiều lớp hiện đại kèm huy hiệu đám mây
                    Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                AppColors.expense.withAlpha(32),
                                AppColors.expense.withAlpha(12),
                              ],
                            ),
                            border: Border.all(
                              color: AppColors.expense.withAlpha(55),
                              width: 1.2,
                            ),
                          ),
                          child: Center(
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: AppColors.expense.withAlpha(28),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.logout_rounded,
                                color: AppColors.expense,
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: dialogContext.appCard,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: dialogContext.appBorder,
                                width: 1,
                              ),
                            ),
                            child: const Icon(
                              Icons.cloud_done_rounded,
                              size: 14,
                              color: AppColors.income,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Tiêu đề thân thiện
                    Text(
                      dialogContext.tr('profile_logout_dialog_title'),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: dialogContext.appTextPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (userEmail != null && userEmail.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: dialogContext.appInputFill,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: dialogContext.appBorder),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.person_outline_rounded,
                              size: 13,
                              color: dialogContext.appTextSecondary,
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                userEmail.trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: dialogContext.appTextSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),

                    // Nội dung mô tả nhẹ nhàng, tự nhiên
                    Text(
                      dialogContext.tr('profile_logout_dialog_sub'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: dialogContext.appTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Hộp cam kết đồng bộ đám mây tạo điểm nhấn thị giác
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.income.withAlpha(isDark ? 22 : 15),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.income.withAlpha(60),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: AppColors.income.withAlpha(30),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.verified_user_outlined,
                              size: 16,
                              color: AppColors.income,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              dialogContext.tr('profile_logout_dialog_content'),
                              style: TextStyle(
                                fontSize: 11.5,
                                height: 1.35,
                                fontWeight: FontWeight.w600,
                                color: dialogContext.appTextPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Hàng 2 nút hành động cân xứng 50/50
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            key: const ValueKey('logout_dialog_cancel'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 46),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12),
                              backgroundColor: dialogContext.appInputFill,
                              foregroundColor: dialogContext.appTextPrimary,
                              side: BorderSide(color: dialogContext.appBorder),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(13),
                              ),
                            ),
                            onPressed: isLoggingOut
                                ? null
                                : () => Navigator.of(ctx).pop(false),
                            child: Text(
                              dialogContext.tr('profile_logout_dialog_cancel'),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: dialogContext.appTextPrimary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            key: const ValueKey('logout_dialog_confirm'),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(0, 46),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12),
                              backgroundColor: AppColors.expense,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(13),
                              ),
                            ),
                            onPressed: isLoggingOut
                                ? null
                                : () {
                                    setDialogState(() => isLoggingOut = true);
                                    Navigator.of(ctx).pop(true);
                                  },
                            child: isLoggingOut
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.logout_rounded, size: 16),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          dialogContext.tr('profile_logout_dialog_action'),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

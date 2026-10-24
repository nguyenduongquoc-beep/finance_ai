import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/user_model.dart';
import '../models/transaction_model.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/theme_controller.dart';
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

  /// Quy trình đăng xuất an toàn: Redesign hộp thoại xác nhận, xử lý loading,
  /// ngăn double submit, làm sạch ngăn xếp điều hướng và bảo toàn dữ liệu Firebase.
  Future<void> _handleLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        bool isLoggingOut = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: context.appCard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: context.appBorder),
              ),
              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              title: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.expense.withAlpha(25),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.logout_rounded,
                      color: AppColors.expense,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Đăng xuất?',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: context.appTextPrimary,
                    ),
                  ),
                ],
              ),
              content: Text(
                'Bạn sẽ cần đăng nhập lại để tiếp tục sử dụng ứng dụng. '
                'Toàn bộ dữ liệu tài chính của bạn vẫn được lưu trữ an toàn trên đám mây.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: context.appTextSecondary,
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      isLoggingOut ? null : () => Navigator.pop(ctx, false),
                  child: Text(
                    'Hủy',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.appTextSecondary,
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.expense,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: isLoggingOut
                      ? null
                      : () async {
                          setDialogState(() => isLoggingOut = true);
                          Navigator.pop(ctx, true);
                        },
                  child: isLoggingOut
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'Đăng xuất',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ],
            );
          },
        );
      },
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
            'Đăng xuất không thành công, vui lòng thử lại',
            isError: true,
          );
        }
      }
    }
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
          'Cá nhân',
          style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.manage_accounts_outlined),
            tooltip: 'Chỉnh sửa thông tin',
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
              // 1. Profile Header (Gọn gàng & Hiện đại, nhấn vào để sửa hồ sơ)
              _buildProfileHeader(user),
              const SizedBox(height: 14),

              // 2. Financial Snapshot (Tình hình tài chính tháng này từ dữ liệu thực tế)
              _buildFinancialSnapshot(
                uid,
                now,
                startOfMonth,
                endOfMonth,
                user?.monthlyIncome ?? 0,
              ),
              const SizedBox(height: 18),

              // 3. QUẢN LÝ TÀI CHÍNH (Hierarchy rõ ràng, có mô tả chức năng)
              _buildSectionTitle('QUẢN LÝ TÀI CHÍNH'),
              _buildGroupContainer([
                _buildMenuItem(
                  icon: Icons.account_balance_wallet_outlined,
                  iconColor: AppColors.primaryLight,
                  iconBgColor: AppColors.primaryLight.withAlpha(25),
                  title: 'Ví & tài khoản',
                  subtitle: 'Quản lý các nguồn tiền, tài khoản và số dư',
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
                  title: 'Ngân sách & hạn mức',
                  subtitle: 'Thiết lập và theo dõi hạn mức chi tiêu',
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
                  title: 'Mục tiêu tiết kiệm',
                  subtitle: 'Theo dõi tiến độ các mục tiêu tài chính',
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
                  title: 'Danh mục phân loại',
                  subtitle: 'Tùy chỉnh danh mục thu nhập và chi tiêu',
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
                  title: 'Giao dịch định kỳ & hóa đơn',
                  subtitle: 'Quản lý các khoản chi lặp lại và hóa đơn đến hạn',
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
              _buildSectionTitle('PHÂN TÍCH & HỖ TRỢ AI'),
              _buildGroupContainer([
                _buildMenuItem(
                  icon: Icons.insights_rounded,
                  iconColor: const Color(0xFF9575CD),
                  iconBgColor: const Color(0xFF9575CD).withAlpha(25),
                  title: 'AI Financial Insight',
                  subtitle: 'Phân tích dòng tiền, chi tiêu & khuyến nghị',
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
                  title: 'Trợ lý AI Chat',
                  subtitle: 'Trao đổi với trợ lý AI về tình hình tài chính',
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
                  title: 'Báo cáo định kỳ AI',
                  subtitle: 'Xem và xuất báo cáo tổng hợp chi tiết',
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
                  title: 'Thông báo & cảnh báo',
                  subtitle: 'Cảnh báo ngân sách, giao dịch và lịch hẹn',
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
              _buildSectionTitle('TÀI KHOẢN & BẢO MẬT'),
              _buildGroupContainer([
                _buildMenuItem(
                  icon: Icons.person_outline_rounded,
                  iconColor: AppColors.primaryLight,
                  iconBgColor: AppColors.primaryLight.withAlpha(25),
                  title: 'Thông tin cá nhân',
                  subtitle: 'Họ tên, ảnh đại diện, thu nhập hàng tháng',
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
                  title: 'Bảo mật & Đổi mật khẩu',
                  subtitle: 'Quản lý mật khẩu và an toàn đăng nhập',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const AccountSecurityScreen()),
                    );
                  },
                ),
                _buildMenuItem(
                  icon: Icons.verified_user_outlined,
                  iconColor: AppColors.income,
                  iconBgColor: AppColors.income.withAlpha(25),
                  title: 'Phương thức xác thực',
                  subtitle: _authService.authProviderLabel,
                  trailing: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.incomeBackground,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Đã kích hoạt',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.income,
                      ),
                    ),
                  ),
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
              _buildSectionTitle('TÙY CHỈNH HỆ THỐNG'),
              _buildGroupContainer([
                // Giao diện sáng / tối
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight.withAlpha(25),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          context.isDarkMode
                              ? Icons.dark_mode_rounded
                              : Icons.wb_sunny_rounded,
                          color: AppColors.primaryLight,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Giao diện tối',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: context.appTextPrimary,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              context.isDarkMode
                                  ? 'Đang bật chế độ tối'
                                  : 'Đang bật chế độ sáng',
                              style: TextStyle(
                                fontSize: 12,
                                color: context.appTextSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch.adaptive(
                        value: context.isDarkMode,
                        activeTrackColor: AppColors.primary,
                        onChanged: ThemeController.toggle,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, indent: 64, endIndent: 16),
                _buildMenuItem(
                  icon: Icons.language_rounded,
                  iconColor: const Color(0xFF26A69A),
                  iconBgColor: const Color(0xFF26A69A).withAlpha(25),
                  title: 'Ngôn ngữ hiển thị',
                  subtitle: 'Tiếng Việt',
                  trailingText: 'VN',
                  onTap: () {
                    AppSnackbar.show(
                        context, 'Hệ thống đang hoạt động với Tiếng Việt');
                  },
                ),
                _buildMenuItem(
                  icon: Icons.payments_outlined,
                  iconColor: const Color(0xFFFFA726),
                  iconBgColor: const Color(0xFFFFA726).withAlpha(25),
                  title: 'Đơn vị tiền tệ',
                  subtitle: 'Việt Nam Đồng',
                  trailingText: 'VNĐ (₫)',
                  showDivider: false,
                  onTap: () {
                    AppSnackbar.show(context, 'Mặc định đơn vị tiền tệ là VNĐ');
                  },
                ),
              ]),
              const SizedBox(height: 18),

              // 7. THÔNG TIN ỨNG DỤNG
              _buildSectionTitle('THÔNG TIN'),
              _buildGroupContainer([
                _buildMenuItem(
                  icon: Icons.info_outline_rounded,
                  iconColor: const Color(0xFF7E57C2),
                  iconBgColor: const Color(0xFF7E57C2).withAlpha(25),
                  title: 'Về ứng dụng Finance AI',
                  subtitle: 'Thông tin nhóm phát triển và điều khoản',
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

              // 8. ĐĂNG XUẤT (Tách biệt, màu cảnh báo nhẹ)
              Container(
                decoration: BoxDecoration(
                  color: AppColors.expenseBackground,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.expense.withAlpha(50)),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: _handleLogout,
                    child: const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.logout_rounded,
                              color: AppColors.expense, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Đăng xuất tài khoản',
                            style: TextStyle(
                              color: AppColors.expense,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
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
                  'Finance AI • Quản lý tài chính thông minh',
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
                    user?.name.isNotEmpty == true ? user!.name : 'Người dùng',
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

            // Nút Chỉnh sửa hồ sơ
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                side: BorderSide(color: context.appBorder),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PersonalInfoScreen()),
                );
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.edit_outlined,
                      size: 14, color: context.appTextPrimary),
                  const SizedBox(width: 4),
                  Text(
                    'Sửa',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.appTextPrimary,
                    ),
                  ),
                ],
              ),
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
    double monthlyIncome,
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
                  Row(
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
                      Text(
                        'TÌNH HÌNH THÁNG ${now.month}/${now.year}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: context.appTextSecondary,
                        ),
                      ),
                    ],
                  ),
                  // Savings rate badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: remaining >= 0
                          ? AppColors.incomeBackground
                          : AppColors.expenseBackground,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Tiết kiệm: $savingsRate%',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: remaining >= 0
                            ? AppColors.income
                            : AppColors.expense,
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
                      label: 'Thu nhập',
                      amountStr: '+${AppFormatters.compactCurrency(income)}',
                      color: AppColors.income,
                    ),
                  ),
                  Container(width: 1, height: 32, color: context.appBorder),
                  // Chi tiêu thực tế
                  Expanded(
                    child: _buildSnapshotColumn(
                      label: 'Chi tiêu',
                      amountStr: '-${AppFormatters.compactCurrency(expense)}',
                      color: AppColors.expense,
                    ),
                  ),
                  Container(width: 1, height: 32, color: context.appBorder),
                  // Dòng tiền ròng
                  Expanded(
                    child: _buildSnapshotColumn(
                      label: 'Dòng tiền',
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
              // Expected monthly income vs actual income (if provided)
              if (monthlyIncome > 0) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: context.appBackground,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: context.appBorder),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.flag_outlined,
                              size: 14, color: context.appTextSecondary),
                          const SizedBox(width: 6),
                          Text(
                            'Thu nhập khai báo: ${AppFormatters.compactCurrency(monthlyIncome)}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: context.appTextSecondary,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        income >= monthlyIncome ? 'Đạt mục tiêu' : 'Chưa đủ',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: income >= monthlyIncome
                              ? AppColors.income
                              : AppColors.warning,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              // Quick link to AI Insight
              InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AiInsightScreen()),
                  );
                },
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Xem phân tích chi tiết \u0026 giải pháp với AI',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryLight,
                        ),
                      ),
                      Icon(
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
                    Text(
                      trailingText,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: context.appTextSecondary,
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

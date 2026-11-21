import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../models/admin_audit_log_model.dart';
import '../../models/monthly_financial_plan.dart';
import '../../models/user_model.dart';
import '../../utils/constants.dart';
import '../services/admin_web_service.dart';
import '../widgets/admin_governance_widgets.dart';

/// Màn hình Dashboard Tổng quan (Admin Overview) trên Admin Web Portal.
/// Hiển thị các chỉ số tổng hợp và biểu đồ tăng trưởng thực tế từ Firestore.
class AdminOverviewView extends StatelessWidget {
  final AdminWebService adminService;
  final ValueChanged<int>? onNavigateTab;

  const AdminOverviewView({
    super.key,
    required this.adminService,
    this.onNavigateTab,
  });

  @override
  Widget build(BuildContext context) {
    final firestore = adminService.firestoreService;

    return StreamBuilder<List<AppUser>>(
      stream: firestore.streamAllUsersForAdmin(),
      builder: (context, userSnap) {
        if (userSnap.connectionState == ConnectionState.waiting &&
            !userSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (userSnap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: AdminErrorStateCard(error: userSnap.error!),
          );
        }
        final users = userSnap.data ?? const <AppUser>[];

        return StreamBuilder<List<SystemCategoryTemplate>>(
          stream: firestore.streamSystemCategoryTemplates(),
          builder: (context, catSnap) {
            final categories =
                catSnap.data ?? const <SystemCategoryTemplate>[];

            return StreamBuilder<List<AdminAuditLog>>(
              stream: firestore.streamAdminAuditLogs(limit: 25),
              builder: (context, logSnap) {
                final logs = logSnap.data ?? const <AdminAuditLog>[];
                final metrics = adminService.computeDashboardMetrics(
                  users: users,
                  categories: categories,
                  logs: logs,
                );

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. 4 Thẻ KPI Tổng quan Vận hành
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth >= 820;
                          final cardWidth = isWide
                              ? (constraints.maxWidth - 36) / 4
                              : (constraints.maxWidth >= 480
                                  ? (constraints.maxWidth - 12) / 2
                                  : constraints.maxWidth);

                          return Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              SizedBox(
                                width: cardWidth,
                                child: _buildKpiCard(
                                  key: const ValueKey('kpi_total_users'),
                                  title: 'Tổng số tài khoản',
                                  value: '${metrics.totalUsers}',
                                  subtitle:
                                      '${metrics.adminUsers} Quản trị viên · ${metrics.totalUsers - metrics.adminUsers} Người dùng',
                                  icon: Icons.people_alt_rounded,
                                  accentColor: AppColors.primary,
                                ),
                              ),
                              SizedBox(
                                width: cardWidth,
                                child: _buildKpiCard(
                                  key: const ValueKey('kpi_active_users'),
                                  title: 'Tài khoản hoạt động',
                                  value: '${metrics.activeUsers}',
                                  subtitle: 'Đang có quyền truy cập bình thường',
                                  icon: Icons.verified_user_rounded,
                                  accentColor: AppColors.income,
                                ),
                              ),
                              SizedBox(
                                width: cardWidth,
                                child: _buildKpiCard(
                                  key: const ValueKey('kpi_locked_users'),
                                  title: 'Tài khoản bị khóa',
                                  value: '${metrics.lockedUsers}',
                                  subtitle: 'Đã vô hiệu hóa quyền đăng nhập',
                                  icon: Icons.lock_person_rounded,
                                  accentColor: AppColors.expense,
                                ),
                              ),
                              SizedBox(
                                width: cardWidth,
                                child: _buildKpiCard(
                                  key: const ValueKey('kpi_system_categories'),
                                  title: 'Danh mục hệ thống',
                                  value: '${metrics.totalSystemCategories}',
                                  subtitle:
                                      '${metrics.activeSystemCategories} hiển thị · ${metrics.hiddenSystemCategories} đang ẩn',
                                  icon: Icons.category_rounded,
                                  accentColor: const Color(0xFF0284C7),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 20),

                      // 2. Biểu đồ tăng trưởng người dùng theo thời gian
                      _buildUserGrowthChartCard(metrics.monthlyGrowth),
                      const SizedBox(height: 20),

                      // 3. Hai bảng dữ liệu thực tế: Tài khoản đăng ký gần đây & Nhật ký quản trị gần đây
                      LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth >= 900) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: _buildRecentUsersCard(
                                    metrics.recentUsers,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  flex: 6,
                                  child: _buildRecentAuditLogsCard(
                                    metrics.recentLogs,
                                  ),
                                ),
                              ],
                            );
                          }
                          return Column(
                            children: [
                              _buildRecentUsersCard(metrics.recentUsers),
                              const SizedBox(height: 16),
                              _buildRecentAuditLogsCard(metrics.recentLogs),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildKpiCard({
    required Key key,
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.slate600,
                  ),
                ),
              ),
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accentColor, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: AppColors.slate900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              color: AppColors.slate500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildUserGrowthChartCard(List<AdminGrowthBucket> buckets) {
    final maxNew = buckets.fold<int>(
      0,
      (prev, b) => b.newUsersCount > prev ? b.newUsersCount : prev,
    );
    final maxY = (maxNew < 4 ? 4 : maxNew + 1).toDouble();

    return Container(
      key: const ValueKey('admin_user_growth_chart_card'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Biểu đồ tăng trưởng người dùng theo thời gian',
                      style: GoogleFonts.inter(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.slate900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Thống kê số lượng tài khoản đăng ký mới trong 6 tháng gần nhất (từ dữ liệu users.createdAt)',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppColors.slate500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.infoBackground,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '6 tháng gần nhất',
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 210,
            child: BarChart(
              BarChartData(
                maxY: maxY,
                alignment: BarChartAlignment.spaceAround,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 1,
                  getDrawingHorizontalLine: (_) => const FlLine(
                    color: AppColors.slate200,
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: 1,
                      getTitlesWidget: (val, _) {
                        if (val % 1 != 0) return const SizedBox.shrink();
                        return Text(
                          val.toInt().toString(),
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppColors.slate500,
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (val, _) {
                        final idx = val.toInt();
                        if (idx < 0 || idx >= buckets.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            buckets[idx].monthKey,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.slate600,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: List.generate(buckets.length, (index) {
                  final b = buckets[index];
                  return BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: b.newUsersCount.toDouble(),
                        width: 28,
                        color: AppColors.primary,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(6),
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentUsersCard(List<AppUser> recentUsers) {
    return Container(
      key: const ValueKey('admin_recent_users_card'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Tài khoản đăng ký gần đây',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.slate900,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onNavigateTab != null)
                TextButton(
                  onPressed: () => onNavigateTab!(1),
                  child: const Text('Xem tất cả'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (recentUsers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Chưa có tài khoản nào trên hệ thống.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppColors.slate500,
                  ),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: recentUsers.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 16, color: AppColors.slate200),
              itemBuilder: (context, index) {
                final u = recentUsers[index];
                return Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: u.isLocked
                          ? AppColors.expenseBackground
                          : AppColors.infoBackground,
                      child: Icon(
                        u.isLocked
                            ? Icons.lock_outline_rounded
                            : Icons.person_outline_rounded,
                        size: 18,
                        color:
                            u.isLocked ? AppColors.expense : AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            u.name.isNotEmpty ? u.name : 'Người dùng',
                            style: GoogleFonts.inter(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.slate900,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            u.email,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppColors.slate500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: u.isLocked
                                ? AppColors.expenseBackground
                                : AppColors.incomeBackground,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            u.isLocked ? 'Đã khóa' : 'Hoạt động',
                            style: GoogleFonts.inter(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: u.isLocked
                                  ? AppColors.expense
                                  : AppColors.income,
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          DateFormat('dd/MM/yyyy').format(u.createdAt),
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppColors.slate500,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildRecentAuditLogsCard(List<AdminAuditLog> recentLogs) {
    return Container(
      key: const ValueKey('admin_recent_logs_card'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Nhật ký quản trị gần đây',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.slate900,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onNavigateTab != null)
                TextButton(
                  onPressed: () => onNavigateTab!(4),
                  child: const Text('Xem toàn bộ log'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (recentLogs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Chưa có thao tác quản trị nào được ghi nhận.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppColors.slate500,
                  ),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: recentLogs.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 16, color: AppColors.slate200),
              itemBuilder: (context, index) {
                final log = recentLogs[index];
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.infoBackground,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.history_edu_rounded,
                        size: 17,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            log.actionDisplayLabel,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.slate900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            log.details.isNotEmpty
                                ? log.details
                                : 'Đối tượng: ${log.targetLabel}',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppColors.slate600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Admin: ${log.adminEmail.isNotEmpty ? log.adminEmail : log.adminId} · ${DateFormat('dd/MM/yyyy HH:mm').format(log.createdAt)}',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AppColors.slate400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

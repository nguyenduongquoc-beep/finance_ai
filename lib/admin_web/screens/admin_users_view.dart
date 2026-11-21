import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../models/user_model.dart';
import '../../utils/constants.dart';
import '../../widgets/app_snackbar.dart';
import '../services/admin_web_service.dart';
import '../widgets/admin_governance_widgets.dart';

/// Màn hình Quản lý Tài khoản Người dùng trên Admin Web Portal (Mục 3.2).
/// Chức năng:
/// - Xem danh sách tài khoản, tìm kiếm theo tên/email, lọc theo trạng thái.
/// - Xem thông tin tài khoản cần thiết (UID, tên, email, ngày đăng ký, trạng thái, vai trò).
/// - Khóa / Mở khóa tài khoản (đồng bộ Cloud Function Firebase Auth + Firestore + Audit Log).
/// - Bảo mật: Không hiển thị hay truy cập dữ liệu tài chính cá nhân của người dùng.
class AdminUsersManagementView extends StatefulWidget {
  final AdminWebService adminService;
  final String currentAdminUid;
  final String currentAdminEmail;
  final Map<String, dynamic>? tokenClaimsOverride;

  const AdminUsersManagementView({
    super.key,
    required this.adminService,
    required this.currentAdminUid,
    required this.currentAdminEmail,
    this.tokenClaimsOverride,
  });

  @override
  State<AdminUsersManagementView> createState() =>
      _AdminUsersManagementViewState();
}

class _AdminUsersManagementViewState extends State<AdminUsersManagementView> {
  String _searchQuery = '';
  String _statusFilter = 'all'; // 'all' | 'active' | 'locked'

  Future<void> _showUserDetailsDialog(AppUser user) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              user.isLocked
                  ? Icons.lock_outline_rounded
                  : Icons.account_circle_outlined,
              color: user.isLocked ? AppColors.expense : AppColors.primary,
            ),
            const SizedBox(width: 10),
            const Expanded(child: Text('Thông tin Tài khoản')),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow('UID:', user.uid),
              _buildInfoRow(
                'Họ và tên:',
                user.name.isNotEmpty ? user.name : 'Người dùng',
              ),
              _buildInfoRow('Email:', user.email),
              _buildInfoRow(
                'Nghề nghiệp:',
                (user.occupation != null && user.occupation!.isNotEmpty)
                    ? user.occupation!
                    : 'Chưa cập nhật',
              ),
              _buildInfoRow(
                'Vai trò hệ thống:',
                user.isAdmin ? 'Quản trị viên (Admin)' : 'Người dùng (User)',
              ),
              _buildInfoRow(
                'Trạng thái:',
                user.isLocked ? 'Đã bị khóa (Locked)' : 'Đang hoạt động (Active)',
              ),
              _buildInfoRow(
                'Ngày đăng ký:',
                DateFormat('dd/MM/yyyy HH:mm').format(user.createdAt),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.infoBackground,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Dữ liệu ví, giao dịch, ngân sách, mục tiêu tiết kiệm và lịch sử trò chuyện AI của người dùng được bảo vệ riêng tư và không hiển thị tại cổng quản trị.',
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    color: AppColors.slate700,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.slate500,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.slate900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAndToggleLock(AppUser user) async {
    final willLock = !user.isLocked;
    final reasonCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          willLock ? 'Xác nhận Khóa tài khoản' : 'Xác nhận Mở khóa tài khoản',
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                willLock
                    ? 'Bạn có chắc chắn muốn KHÓA tài khoản "${user.email}" (UID: ${user.uid})?\n\n'
                        '• Hệ thống sẽ cập nhật trạng thái Firestore và vô hiệu hóa trên Firebase Authentication.\n'
                        '• Tài khoản này sẽ bị đăng xuất ngay lập tức khỏi thiết bị đang mở và không thể đăng nhập mới.'
                    : 'Bạn có chắc chắn muốn MỞ KHÓA tài khoản "${user.email}" (UID: ${user.uid})?\n\n'
                        '• Quyền đăng nhập và sử dụng ứng dụng sẽ được khôi phục ngay lập tức.',
                style: GoogleFonts.inter(fontSize: 13, height: 1.45),
              ),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey('admin_lock_reason_input'),
                controller: reasonCtrl,
                decoration: InputDecoration(
                  labelText: willLock
                      ? 'Lý do khóa tài khoản (ghi vào Nhật ký quản trị)'
                      : 'Ghi chú mở khóa (tùy chọn)',
                  hintText: willLock
                      ? 'VD: Phát hiện hoạt động bất thường / Vi phạm điều khoản'
                      : 'VD: Đã xác minh thông tin chủ tài khoản',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            key: const ValueKey('admin_confirm_lock_btn'),
            style: FilledButton.styleFrom(
              backgroundColor:
                  willLock ? AppColors.expense : AppColors.income,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(willLock ? 'Xác nhận Khóa' : 'Xác nhận Mở khóa'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await widget.adminService.setUserAccountStatus(
        adminUid: widget.currentAdminUid,
        adminEmail: widget.currentAdminEmail,
        targetUser: user,
        lockAccount: willLock,
        reason: reasonCtrl.text.trim(),
        tokenClaimsOverride: widget.tokenClaimsOverride,
      );

      if (!mounted) return;
      AppSnackbar.show(
        context,
        willLock
            ? 'Đã khóa tài khoản ${user.email} và ghi nhật ký quản trị.'
            : 'Đã mở khóa tài khoản ${user.email} thành công.',
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.show(
        context,
        'Không thể cập nhật trạng thái tài khoản: ${formatAdminErrorMessage(e)}',
        isError: true,
      );
    }
  }

  Future<void> _confirmAndDeleteUser(AppUser user) async {
    final reasonCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: AppColors.expense,
              size: 24,
            ),
            SizedBox(width: 8),
            Expanded(child: Text('Xác nhận XÓA VĨNH VIỄN Tài khoản')),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CẢNH BÁO NGUY HIỂM: Bạn đang chuẩn bị xóa vĩnh viễn tài khoản "${user.email}" (UID: ${user.uid}).\n\n'
                '• Tài khoản sẽ bị xóa hoàn toàn khỏi Firebase Authentication.\n'
                '• Toàn bộ hồ sơ người dùng trong Firestore và các dữ liệu tài chính liên quan (ví, giao dịch, ngân sách, mục tiêu) sẽ được dọn dẹp sạch sẽ.\n'
                '• Hành động này KHÔNG THỂ HOÀN TÁC!',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  height: 1.45,
                  color: AppColors.expense,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey('admin_delete_reason_input'),
                controller: reasonCtrl,
                decoration: const InputDecoration(
                  labelText: 'Lý do xóa tài khoản (ghi vào Nhật ký quản trị)',
                  hintText: 'VD: Yêu cầu xóa dữ liệu cá nhân theo GDPR / Vi phạm',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton.icon(
            key: const ValueKey('admin_confirm_delete_btn'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.expense,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.delete_forever_rounded, size: 16),
            label: const Text('Xác nhận Xóa Vĩnh Viễn'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await widget.adminService.deleteUserAccount(
        adminUid: widget.currentAdminUid,
        adminEmail: widget.currentAdminEmail,
        targetUser: user,
        reason: reasonCtrl.text.trim(),
        tokenClaimsOverride: widget.tokenClaimsOverride,
      );

      if (!mounted) return;
      AppSnackbar.show(
        context,
        'Đã xóa vĩnh viễn tài khoản ${user.email} (Auth + Firestore).',
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.show(
        context,
        'Không thể xóa tài khoản: ${formatAdminErrorMessage(e)}',
        isError: true,
      );
    }
  }

  Future<void> _confirmAndToggleRole(AppUser user) async {
    final nextRole = user.isAdmin ? 'user' : 'admin';
    final confirm = await showAdminConfirmDialog(
      context: context,
      title: user.isAdmin
          ? 'Thu hồi quyền Quản trị viên?'
          : 'Cấp quyền Quản trị viên (Admin)?',
      message: user.isAdmin
          ? 'Tài khoản ${user.email} sẽ chuyển về vai trò User thông thường (cập nhật qua Cloud Function & Custom Claims).'
          : 'Tài khoản ${user.email} sẽ được cấp toàn quyền truy cập Cổng Quản trị AI & Tri thức.',
      confirmLabel: user.isAdmin ? 'Thu hồi quyền Admin' : 'Cấp quyền Admin',
      confirmColor: user.isAdmin ? AppColors.warning : AppColors.primary,
      confirmButtonKey: ValueKey('confirm_role_${user.uid}'),
    );
    if (confirm == null || !confirm.confirmed || !mounted) return;

    try {
      await widget.adminService.setUserAccountRole(
        adminUid: widget.currentAdminUid,
        adminEmail: widget.currentAdminEmail,
        targetUser: user,
        nextRole: nextRole,
        tokenClaimsOverride: widget.tokenClaimsOverride,
      );
      if (!mounted) return;
      AppSnackbar.show(
        context,
        nextRole == 'admin'
            ? 'Đã cấp quyền Admin cho ${user.email}.'
            : 'Đã thu hồi quyền Admin của ${user.email}.',
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.show(
        context,
        formatAdminErrorMessage(e),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final firestore = widget.adminService.firestoreService;

    return StreamBuilder<List<AppUser>>(
      stream: firestore.streamAllUsersForAdmin(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: AdminErrorStateCard(error: snapshot.error!),
          );
        }

        final allUsers = snapshot.data ?? const <AppUser>[];
        final activeCount = allUsers.where((u) => !u.isLocked).length;
        final lockedCount = allUsers.where((u) => u.isLocked).length;

        final filteredUsers = allUsers.where((u) {
          if (_statusFilter == 'active' && u.isLocked) return false;
          if (_statusFilter == 'locked' && !u.isLocked) return false;
          if (_searchQuery.isNotEmpty) {
            final q = _searchQuery.toLowerCase();
            final matchName = u.name.toLowerCase().contains(q);
            final matchEmail = u.email.toLowerCase().contains(q);
            final matchUid = u.uid.toLowerCase().contains(q);
            return matchName || matchEmail || matchUid;
          }
          return true;
        }).toList();

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thanh tóm tắt số lượng + Tìm kiếm & Lọc trạng thái
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.slate200),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _buildSummaryChip(
                          label: 'Tổng tài khoản: ${allUsers.length}',
                          color: AppColors.primary,
                          selected: _statusFilter == 'all',
                          onTap: () => setState(() => _statusFilter = 'all'),
                        ),
                        const SizedBox(width: 8),
                        _buildSummaryChip(
                          label: 'Hoạt động: $activeCount',
                          color: AppColors.income,
                          selected: _statusFilter == 'active',
                          onTap: () => setState(() => _statusFilter = 'active'),
                        ),
                        const SizedBox(width: 8),
                        _buildSummaryChip(
                          label: 'Đã khóa: $lockedCount',
                          color: AppColors.expense,
                          selected: _statusFilter == 'locked',
                          onTap: () => setState(() => _statusFilter = 'locked'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      key: const ValueKey('admin_user_search_input'),
                      onChanged: (v) =>
                          setState(() => _searchQuery = v.trim()),
                      decoration: const InputDecoration(
                        hintText:
                            'Tìm kiếm người dùng theo tên, địa chỉ email hoặc UID...',
                        prefixIcon: Icon(Icons.search_rounded),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Danh sách tài khoản
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.slate200),
                  ),
                  child: filteredUsers.isEmpty
                      ? Center(
                          child: Text(
                            'Không tìm thấy tài khoản người dùng phù hợp.',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: AppColors.slate500,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: filteredUsers.length,
                          separatorBuilder: (_, __) => const Divider(
                            height: 16,
                            color: AppColors.slate200,
                          ),
                          itemBuilder: (context, index) {
                            final u = filteredUsers[index];
                            final isSelf = u.uid == widget.currentAdminUid;

                            final infoBlock = Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 21,
                                  backgroundColor: u.isLocked
                                      ? AppColors.expenseBackground
                                      : AppColors.infoBackground,
                                  child: Icon(
                                    u.isLocked
                                        ? Icons.lock_outline_rounded
                                        : (u.isAdmin
                                            ? Icons
                                                .admin_panel_settings_rounded
                                            : Icons.person_outline_rounded),
                                    color: u.isLocked
                                        ? AppColors.expense
                                        : AppColors.primary,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          Text(
                                            u.name.isNotEmpty
                                                ? u.name
                                                : 'Người dùng',
                                            style: GoogleFonts.inter(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.slate900,
                                            ),
                                          ),
                                          _buildBadge(
                                            u.isAdmin ? 'ADMIN' : 'USER',
                                            u.isAdmin
                                                ? AppColors.primary
                                                : AppColors.slate600,
                                          ),
                                          _buildBadge(
                                            u.isLocked
                                                ? 'ĐÃ KHÓA'
                                                : 'HOẠT ĐỘNG',
                                            u.isLocked
                                                ? AppColors.expense
                                                : AppColors.income,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '${u.email} · UID: ${u.uid}',
                                        style: GoogleFonts.inter(
                                          fontSize: 12.5,
                                          color: AppColors.slate600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Ngày đăng ký: ${DateFormat('dd/MM/yyyy HH:mm').format(u.createdAt)}',
                                        style: GoogleFonts.inter(
                                          fontSize: 11.5,
                                          color: AppColors.slate500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );

                            final actionsWidgets = <Widget>[
                              OutlinedButton.icon(
                                key: ValueKey('view_user_${u.uid}'),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 38),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                ),
                                onPressed: () => _showUserDetailsDialog(u),
                                icon: const Icon(
                                  Icons.info_outline_rounded,
                                  size: 16,
                                ),
                                label: const Text('Chi tiết'),
                              ),
                              if (!isSelf) ...[
                                OutlinedButton.icon(
                                  key: ValueKey('toggle_role_${u.uid}'),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(0, 38),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                  ),
                                  onPressed: () => _confirmAndToggleRole(u),
                                  icon: Icon(
                                    u.isAdmin
                                        ? Icons.person_remove_outlined
                                        : Icons.admin_panel_settings_outlined,
                                    size: 16,
                                  ),
                                  label: Text(
                                    u.isAdmin ? 'Hạ quyền User' : 'Cấp Admin',
                                  ),
                                ),
                                FilledButton.icon(
                                  key: ValueKey('toggle_lock_${u.uid}'),
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(0, 38),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    backgroundColor: u.isLocked
                                        ? AppColors.income
                                        : AppColors.expense,
                                  ),
                                  onPressed: () => _confirmAndToggleLock(u),
                                  icon: Icon(
                                    u.isLocked
                                        ? Icons.lock_open_rounded
                                        : Icons.lock_outline_rounded,
                                    size: 16,
                                  ),
                                  label: Text(
                                    u.isLocked ? 'Mở khóa' : 'Khóa',
                                  ),
                                ),
                                OutlinedButton.icon(
                                  key: ValueKey('delete_user_${u.uid}'),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(0, 38),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    foregroundColor: AppColors.expense,
                                    side: const BorderSide(
                                      color: AppColors.expense,
                                    ),
                                  ),
                                  onPressed: () => _confirmAndDeleteUser(u),
                                  icon: const Icon(
                                    Icons.delete_forever_rounded,
                                    size: 16,
                                  ),
                                  label: const Text('Xóa'),
                                ),
                              ],
                              if (isSelf)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.slate100,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Tài khoản của bạn',
                                    style: GoogleFonts.inter(
                                      fontSize: 11.5,
                                      fontStyle: FontStyle.italic,
                                      color: AppColors.slate500,
                                    ),
                                  ),
                                ),
                            ];

                            return LayoutBuilder(
                              builder: (context, constraints) {
                                final isWideRow = constraints.maxWidth >= 820;
                                if (isWideRow) {
                                  return Row(
                                    children: [
                                      Expanded(child: infoBlock),
                                      const SizedBox(width: 12),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: actionsWidgets,
                                      ),
                                    ],
                                  );
                                }
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    infoBlock,
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: actionsWidgets,
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummaryChip({
    required String label,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.14) : AppColors.slate100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? color : AppColors.slate200,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: selected ? color : AppColors.slate700,
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

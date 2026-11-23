import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../models/admin_audit_log_model.dart';
import '../../models/support_ticket_model.dart';
import '../../models/user_model.dart';
import '../../utils/constants.dart';
import '../../widgets/app_snackbar.dart';
import '../services/admin_web_service.dart';
import '../widgets/admin_governance_widgets.dart';

/// 5 nhóm lý do chuẩn hóa khi Quản trị viên khóa tài khoản người dùng.
enum AdminLockReasonPreset {
  termsViolation('terms_violation', 'Vi phạm điều khoản sử dụng'),
  supportAbuse('support_abuse', 'Gửi tin nhắn rác / Lạm dụng hệ thống hỗ trợ'),
  suspiciousAccess('suspicious_access', 'Nghi vấn truy cập bất thường'),
  userRequested('user_requested', 'Khóa tạm thời theo yêu cầu chủ tài khoản'),
  other('other', 'Lý do khác');

  final String code;
  final String label;
  const AdminLockReasonPreset(this.code, this.label);
}

enum _UserRegistrationRange {
  all('all', 'Mọi thời gian'),
  last7Days('7d', '7 ngày qua'),
  last30Days('30d', '30 ngày qua');

  final String code;
  final String label;
  const _UserRegistrationRange(this.code, this.label);
}

enum _UserSortOption {
  newestRegistered('newest', 'Mới đăng ký nhất'),
  lastActive('last_active', 'Hoạt động gần nhất');

  final String code;
  final String label;
  const _UserSortOption(this.code, this.label);
}

/// Màn hình Quản lý Tài khoản Người dùng trên Admin Web Portal (100% thuần Firebase Spark).
/// - Đọc/ghi trực tiếp qua Cloud Firestore + `WriteBatch` được bảo vệ bởi `firestore.rules`.
/// - Zero-Knowledge tuyệt đối: chỉ đọc siêu dữ liệu vận hành phi tài chính trên `users/{uid}`.
/// - 3 nghiệp vụ cốt lõi:
///   1. Hồ sơ Vận hành Chi tiết 3 khối phi tài chính (định danh, vé hỗ trợ liên kết, lịch sử quản trị).
///   2. Khóa / Mở khóa User thường có lý do chuẩn hóa (bảo vệ chính mình & mọi tài khoản Admin khác).
///   3. Tìm kiếm, lọc trạng thái/thời gian đăng ký, sắp xếp và phân trang theo lô tiết kiệm lượt đọc Spark.
class AdminUsersManagementView extends StatefulWidget {
  final AdminWebService adminService;
  final String currentAdminUid;
  final String currentAdminEmail;
  final Map<String, dynamic>? tokenClaimsOverride;
  final ValueChanged<String>? onOpenSupportTicket;

  const AdminUsersManagementView({
    super.key,
    required this.adminService,
    required this.currentAdminUid,
    required this.currentAdminEmail,
    this.tokenClaimsOverride,
    this.onOpenSupportTicket,
  });

  @override
  State<AdminUsersManagementView> createState() =>
      _AdminUsersManagementViewState();
}

class _AdminUsersManagementViewState extends State<AdminUsersManagementView> {
  static const int _pageSize = 25;

  final _searchCtrl = TextEditingController();
  late Stream<List<AppUser>> _usersStream;

  int _limit = _pageSize;
  String _searchQuery = '';
  String _statusFilter = 'all'; // 'all' | 'active' | 'locked'
  _UserRegistrationRange _registrationRange = _UserRegistrationRange.all;
  _UserSortOption _sortOption = _UserSortOption.newestRegistered;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _usersStream = _buildUsersStream();
  }

  @override
  void didUpdateWidget(covariant AdminUsersManagementView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.adminService != widget.adminService ||
        oldWidget.currentAdminUid != widget.currentAdminUid) {
      _limit = _pageSize;
      _usersStream = _buildUsersStream();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Stream<List<AppUser>> _buildUsersStream() {
    return widget.adminService.streamUsersDirectoryForAdmin(limit: _limit);
  }

  void _refreshUsers() {
    setState(() {
      _usersStream = _buildUsersStream();
    });
  }

  void _loadMoreUsers() {
    setState(() {
      _limit += _pageSize;
      _usersStream = _buildUsersStream();
    });
  }

  Future<void> _showUserDetailsDialog(AppUser user) async {
    final selectedTicketId = await showDialog<String>(
      context: context,
      builder: (ctx) => _UserOperationalDetailDialog(
        user: user,
        adminService: widget.adminService,
      ),
    );
    if (!mounted || selectedTicketId == null || selectedTicketId.isEmpty) return;
    widget.onOpenSupportTicket?.call(selectedTicketId);
  }

  Future<void> _confirmAndToggleLock(AppUser user) async {
    if (_isSubmitting) return;
    if (user.uid == widget.currentAdminUid || user.isAdmin) return;

    final willLock = !user.isLocked;
    final String? finalReason;
    if (willLock) {
      finalReason = await showDialog<String>(
        context: context,
        builder: (_) => _LockAccountDialog(targetUser: user),
      );
    } else {
      finalReason = await showDialog<String>(
        context: context,
        builder: (_) => _UnlockAccountDialog(targetUser: user),
      );
    }

    if (finalReason == null || !mounted) return;

    setState(() => _isSubmitting = true);
    try {
      await widget.adminService.setUserAccountStatus(
        adminUid: widget.currentAdminUid,
        adminEmail: widget.currentAdminEmail,
        targetUser: user,
        lockAccount: willLock,
        reason: finalReason,
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
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  List<AppUser> _applyFiltersAndSort(List<AppUser> allUsers) {
    final now = DateTime.now();
    final q = _searchQuery.trim().toLowerCase();

    final filtered = allUsers.where((u) {
      if (_statusFilter == 'active' && u.isLocked) return false;
      if (_statusFilter == 'locked' && !u.isLocked) return false;

      if (_registrationRange == _UserRegistrationRange.last7Days) {
        if (now.difference(u.createdAt).inDays > 7) return false;
      } else if (_registrationRange == _UserRegistrationRange.last30Days) {
        if (now.difference(u.createdAt).inDays > 30) return false;
      }

      if (q.isNotEmpty) {
        final match = u.name.toLowerCase().contains(q) ||
            u.email.toLowerCase().contains(q) ||
            u.uid.toLowerCase().contains(q);
        if (!match) return false;
      }
      return true;
    }).toList();

    filtered.sort((a, b) {
      if (_sortOption == _UserSortOption.lastActive) {
        final aActive = a.lastActiveAt;
        final bActive = b.lastActiveAt;
        if (aActive == null && bActive == null) {
          return b.createdAt.compareTo(a.createdAt);
        }
        if (aActive == null) return 1;
        if (bActive == null) return -1;
        final cmp = bActive.compareTo(aActive);
        if (cmp != 0) return cmp;
      }
      return b.createdAt.compareTo(a.createdAt);
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AppUser>>(
      stream: _usersStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: AdminErrorStateCard(
              error: snapshot.error!,
              onRetry: _refreshUsers,
            ),
          );
        }

        final allUsers = snapshot.data ?? const <AppUser>[];
        final activeCount = allUsers.where((u) => !u.isLocked).length;
        final lockedCount = allUsers.where((u) => u.isLocked).length;
        final filteredUsers = _applyFiltersAndSort(allUsers);
        final hasMore = allUsers.length >= _limit;

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Khối 1: Bộ lọc trạng thái, thời gian đăng ký, sắp xếp & tìm kiếm
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.slate200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _buildSummaryChip(
                          key: const ValueKey('admin_users_status_all'),
                          label: 'Tất cả (${allUsers.length})',
                          color: AppColors.primary,
                          selected: _statusFilter == 'all',
                          onTap: () => setState(() => _statusFilter = 'all'),
                        ),
                        _buildSummaryChip(
                          key: const ValueKey('admin_users_status_active'),
                          label: 'Hoạt động ($activeCount)',
                          color: AppColors.income,
                          selected: _statusFilter == 'active',
                          onTap: () => setState(() => _statusFilter = 'active'),
                        ),
                        _buildSummaryChip(
                          key: const ValueKey('admin_users_status_locked'),
                          label: 'Đã khóa ($lockedCount)',
                          color: AppColors.expense,
                          selected: _statusFilter == 'locked',
                          onTap: () => setState(() => _statusFilter = 'locked'),
                        ),
                        OutlinedButton.icon(
                          key: const ValueKey('admin_users_refresh_btn'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 34),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                          ),
                          onPressed: _refreshUsers,
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: const Text('Làm mới'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Đăng ký:',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.slate500,
                          ),
                        ),
                        for (final range in _UserRegistrationRange.values)
                          ChoiceChip(
                            key: ValueKey('admin_users_reg_${range.code}'),
                            label: Text(
                              range.label,
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                fontWeight: _registrationRange == range
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: _registrationRange == range
                                    ? AppColors.primary
                                    : AppColors.slate700,
                              ),
                            ),
                            selected: _registrationRange == range,
                            onSelected: (_) =>
                                setState(() => _registrationRange = range),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            selectedColor: AppColors.infoBackground,
                            backgroundColor: AppColors.slate50,
                            side: BorderSide(
                              color: _registrationRange == range
                                  ? AppColors.primary
                                  : AppColors.slate200,
                            ),
                          ),
                        const SizedBox(width: 8),
                        Text(
                          'Sắp xếp:',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.slate500,
                          ),
                        ),
                        for (final sortOpt in _UserSortOption.values)
                          ChoiceChip(
                            key: ValueKey('admin_users_sort_${sortOpt.code}'),
                            label: Text(
                              sortOpt.label,
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                fontWeight: _sortOption == sortOpt
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: _sortOption == sortOpt
                                    ? AppColors.primary
                                    : AppColors.slate700,
                              ),
                            ),
                            selected: _sortOption == sortOpt,
                            onSelected: (_) =>
                                setState(() => _sortOption = sortOpt),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            selectedColor: AppColors.infoBackground,
                            backgroundColor: AppColors.slate50,
                            side: BorderSide(
                              color: _sortOption == sortOpt
                                  ? AppColors.primary
                                  : AppColors.slate200,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('admin_user_search_input'),
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() => _searchQuery = v.trim()),
                      decoration: InputDecoration(
                        hintText:
                            'Tìm kiếm người dùng theo tên, địa chỉ email hoặc UID...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        isDense: true,
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Khối 2: Danh sách tài khoản
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
                          itemCount: filteredUsers.length + (hasMore ? 1 : 0),
                          separatorBuilder: (_, __) => const Divider(
                            height: 16,
                            color: AppColors.slate200,
                          ),
                          itemBuilder: (context, index) {
                            if (index == filteredUsers.length) {
                              return Center(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: OutlinedButton.icon(
                                    key: const ValueKey(
                                      'admin_users_load_more_btn',
                                    ),
                                    onPressed: _loadMoreUsers,
                                    icon: const Icon(
                                      Icons.expand_more_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('Tải thêm người dùng'),
                                  ),
                                ),
                              );
                            }

                            final u = filteredUsers[index];
                            return _buildUserRow(u);
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

  Widget _buildUserRow(AppUser u) {
    final isSelf = u.uid == widget.currentAdminUid;
    final isProtectedAdmin = isSelf || u.isAdmin;

    final createdStr = DateFormat('dd/MM/yyyy HH:mm').format(u.createdAt.toLocal());
    final lastActiveStr = u.lastActiveAt != null
        ? DateFormat('dd/MM/yyyy HH:mm').format(u.lastActiveAt!.toLocal())
        : 'Chưa ghi nhận';

    final infoBlock = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 21,
          backgroundColor:
              u.isLocked ? AppColors.expenseBackground : AppColors.infoBackground,
          child: Icon(
            u.isLocked
                ? Icons.lock_outline_rounded
                : (u.isAdmin
                    ? Icons.admin_panel_settings_rounded
                    : Icons.person_outline_rounded),
            color: u.isLocked ? AppColors.expense : AppColors.primary,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    u.name.isNotEmpty ? u.name : 'Người dùng',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.slate900,
                    ),
                  ),
                  _buildBadge(
                    u.isAdmin ? 'ADMIN' : 'USER',
                    u.isAdmin ? AppColors.primary : AppColors.slate600,
                  ),
                  _buildBadge(
                    u.isLocked ? 'ĐÃ KHÓA' : 'HOẠT ĐỘNG',
                    u.isLocked ? AppColors.expense : AppColors.income,
                  ),
                  if (u.authProvider != null && u.authProvider!.isNotEmpty)
                    _buildBadge(u.authProviderLabelVi, AppColors.slate600),
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
                'Đăng ký: $createdStr · Hoạt động gần nhất: $lastActiveStr',
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  color: AppColors.slate500,
                ),
              ),
              if (u.isLocked &&
                  u.lockReason != null &&
                  u.lockReason!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Lý do khóa: ${u.lockReason!}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.expense,
                  ),
                ),
              ],
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        onPressed: () => _showUserDetailsDialog(u),
        icon: const Icon(Icons.info_outline_rounded, size: 16),
        label: const Text('Chi tiết'),
      ),
      if (!isProtectedAdmin)
        FilledButton.icon(
          key: ValueKey('toggle_lock_${u.uid}'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 38),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            backgroundColor: u.isLocked ? AppColors.income : AppColors.expense,
          ),
          onPressed: _isSubmitting ? null : () => _confirmAndToggleLock(u),
          icon: Icon(
            u.isLocked ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
            size: 16,
          ),
          label: Text(u.isLocked ? 'Mở khóa' : 'Khóa'),
        ),
      if (isProtectedAdmin)
        Container(
          key: ValueKey('admin_readonly_badge_${u.uid}'),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.slate100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.slate200),
          ),
          child: Text(
            isSelf ? 'Tài khoản của bạn (Admin)' : 'Admin (Chỉ đọc)',
            style: GoogleFonts.inter(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.slate600,
            ),
          ),
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideRow = constraints.maxWidth >= 780;
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
  }

  Widget _buildSummaryChip({
    required Key key,
    required String label,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
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
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// Dialog Hồ sơ Vận hành Chi tiết 3 khối phi tài chính:
/// - Khối 1: Định danh & Truy cập (kèm nút sao chép UID/Email + thông tin khóa nếu có).
/// - Khối 2: Yêu cầu Hỗ trợ của người dùng (tối đa 10 vé gần nhất, bấm mở thẳng sang Tab Hỗ trợ).
/// - Khối 3: Lịch sử Tác động Quản trị (tối đa 10 bản ghi `admin_logs` gần nhất).
class _UserOperationalDetailDialog extends StatefulWidget {
  final AppUser user;
  final AdminWebService adminService;

  const _UserOperationalDetailDialog({
    required this.user,
    required this.adminService,
  });

  @override
  State<_UserOperationalDetailDialog> createState() =>
      _UserOperationalDetailDialogState();
}

class _UserOperationalDetailDialogState
    extends State<_UserOperationalDetailDialog> {
  late Future<List<SupportTicket>> _ticketsFuture;
  late Future<List<AdminAuditLog>> _logsFuture;

  @override
  void initState() {
    super.initState();
    _ticketsFuture =
        widget.adminService.fetchUserSupportTickets(widget.user.uid, limit: 10);
    _logsFuture =
        widget.adminService.fetchUserAdminLogs(widget.user.uid, limit: 10);
  }

  Future<void> _copyToClipboard(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    AppSnackbar.show(context, 'Đã sao chép $label.');
  }

  String _stageLabel(SupportTicketStatus status) {
    switch (status) {
      case SupportTicketStatus.newTicket:
        return 'Mới';
      case SupportTicketStatus.inProgress:
      case SupportTicketStatus.replied:
      case SupportTicketStatus.waitingForUser:
        return 'Đang xử lý';
      case SupportTicketStatus.resolved:
      case SupportTicketStatus.closed:
        return 'Đã giải quyết';
    }
  }

  Color _stageColor(SupportTicketStatus status) {
    switch (status) {
      case SupportTicketStatus.newTicket:
        return const Color(0xFF0284C7);
      case SupportTicketStatus.inProgress:
      case SupportTicketStatus.replied:
      case SupportTicketStatus.waitingForUser:
        return AppColors.primary;
      case SupportTicketStatus.resolved:
      case SupportTicketStatus.closed:
        return AppColors.income;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final fmt = DateFormat('dd/MM/yyyy HH:mm');

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 740),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: user.isLocked
                        ? AppColors.expenseBackground
                        : AppColors.infoBackground,
                    child: Icon(
                      user.isLocked
                          ? Icons.lock_outline_rounded
                          : Icons.account_circle_outlined,
                      color:
                          user.isLocked ? AppColors.expense : AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hồ sơ Vận hành Tài khoản',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.slate900,
                          ),
                        ),
                        Text(
                          user.email,
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            color: AppColors.slate500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Đóng',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.slate200),

            // Body cuộn mượt 3 khối
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // KHỐI 1: Thông tin định danh & Truy cập
                    _buildSectionTitle(
                      '1. Thông tin định danh & Truy cập',
                      Icons.badge_outlined,
                    ),
                    const SizedBox(height: 10),
                    Container(
                      key: const ValueKey('user_detail_identity_block'),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.slate50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.slate200),
                      ),
                      child: Column(
                        children: [
                          _buildCopyableRow(
                            'UID',
                            user.uid,
                            copyKey: const ValueKey('copy_user_uid_btn'),
                            onCopy: () => _copyToClipboard('UID', user.uid),
                          ),
                          _buildInfoRow(
                            'Họ và tên',
                            user.name.isNotEmpty ? user.name : 'Người dùng',
                          ),
                          _buildCopyableRow(
                            'Email',
                            user.email,
                            copyKey: const ValueKey('copy_user_email_btn'),
                            onCopy: () => _copyToClipboard('Email', user.email),
                          ),
                          _buildInfoRow(
                            'Nghề nghiệp',
                            (user.occupation != null &&
                                    user.occupation!.trim().isNotEmpty)
                                ? user.occupation!.trim()
                                : 'Chưa cập nhật',
                          ),
                          _buildInfoRow(
                            'Vai trò hệ thống',
                            user.isAdmin
                                ? 'Quản trị viên (Admin)'
                                : 'Người dùng (User)',
                          ),
                          _buildInfoRow(
                            'Trạng thái',
                            user.isLocked
                                ? 'Đã bị khóa (Locked)'
                                : 'Đang hoạt động (Active)',
                          ),
                          _buildInfoRow(
                            'Phương thức đăng nhập',
                            user.authProviderLabelVi,
                          ),
                          _buildInfoRow(
                            'Ngày đăng ký',
                            fmt.format(user.createdAt.toLocal()),
                          ),
                          _buildInfoRow(
                            'Hoạt động gần nhất',
                            user.lastActiveAt != null
                                ? fmt.format(user.lastActiveAt!.toLocal())
                                : 'Chưa ghi nhận',
                          ),
                        ],
                      ),
                    ),
                    if (user.isLocked) ...[
                      const SizedBox(height: 10),
                      Container(
                        key: const ValueKey('user_detail_lock_block'),
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.expenseBackground,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppColors.expense.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Thông tin khóa tài khoản hiện tại',
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.expense,
                              ),
                            ),
                            const SizedBox(height: 6),
                            _buildInfoRow(
                              'Lý do khóa',
                              (user.lockReason != null &&
                                      user.lockReason!.isNotEmpty)
                                  ? user.lockReason!
                                  : 'Chưa ghi nhận lý do cụ thể',
                            ),
                            _buildInfoRow(
                              'Thời điểm khóa',
                              user.lockedAt != null
                                  ? fmt.format(user.lockedAt!.toLocal())
                                  : 'Chưa ghi nhận',
                            ),
                            _buildInfoRow(
                              'Người thực hiện',
                              (user.lockedBy != null &&
                                      user.lockedBy!.isNotEmpty)
                                  ? user.lockedBy!
                                  : 'Quản trị viên',
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.infoBackground,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.privacy_tip_outlined,
                            size: 16,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Nguyên tắc Zero-Knowledge: Ví tiền, giao dịch, thu nhập dự kiến, ngân sách, mục tiêu tiết kiệm và lịch sử AI Chat của người dùng được tách biệt hoàn toàn khỏi cổng Quản trị.',
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

                    const SizedBox(height: 20),

                    // KHỐI 2: Yêu cầu Hỗ trợ của người dùng
                    _buildSectionTitle(
                      '2. Yêu cầu Hỗ trợ của người dùng (10 vé gần nhất)',
                      Icons.support_agent_rounded,
                    ),
                    const SizedBox(height: 8),
                    FutureBuilder<List<SupportTicket>>(
                      future: _ticketsFuture,
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.all(12),
                            child: Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          );
                        }
                        if (snap.hasError) {
                          return _buildEmptyBox(
                            'Không thể tải danh sách yêu cầu hỗ trợ.',
                          );
                        }
                        final tickets = snap.data ?? const <SupportTicket>[];
                        if (tickets.isEmpty) {
                          return _buildEmptyBox(
                            'Người dùng chưa gửi yêu cầu hỗ trợ nào.',
                          );
                        }
                        return Container(
                          key: const ValueKey('user_detail_tickets_block'),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.slate200),
                          ),
                          child: Column(
                            children: [
                              for (int i = 0; i < tickets.length; i++) ...[
                                if (i > 0)
                                  const Divider(
                                    height: 1,
                                    color: AppColors.slate100,
                                  ),
                                InkWell(
                                  key: ValueKey(
                                    'user_detail_ticket_${tickets[i].ticketId}',
                                  ),
                                  onTap: () => Navigator.of(context)
                                      .pop(tickets[i].ticketId),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${tickets[i].ticketCode} · ${tickets[i].title}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: GoogleFonts.inter(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.slate900,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'Cập nhật: ${fmt.format(tickets[i].updatedAt.toLocal())}',
                                                style: GoogleFonts.inter(
                                                  fontSize: 11,
                                                  color: AppColors.slate500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _stageColor(
                                              tickets[i].status,
                                            ).withValues(alpha: 0.12),
                                            borderRadius:
                                                BorderRadius.circular(999),
                                          ),
                                          child: Text(
                                            _stageLabel(tickets[i].status),
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: _stageColor(
                                                tickets[i].status,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        const Icon(
                                          Icons.open_in_new_rounded,
                                          size: 15,
                                          color: AppColors.primary,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 20),

                    // KHỐI 3: Lịch sử Tác động Quản trị
                    _buildSectionTitle(
                      '3. Lịch sử Tác động Quản trị (10 bản ghi gần nhất)',
                      Icons.history_edu_rounded,
                    ),
                    const SizedBox(height: 8),
                    FutureBuilder<List<AdminAuditLog>>(
                      future: _logsFuture,
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.all(12),
                            child: Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          );
                        }
                        if (snap.hasError) {
                          return _buildEmptyBox(
                            'Không thể tải lịch sử tác động quản trị.',
                          );
                        }
                        final logs = snap.data ?? const <AdminAuditLog>[];
                        if (logs.isEmpty) {
                          return _buildEmptyBox(
                            'Chưa có tác động quản trị nào ghi nhận trên tài khoản này.',
                          );
                        }
                        return Container(
                          key: const ValueKey('user_detail_logs_block'),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.slate200),
                          ),
                          child: Column(
                            children: [
                              for (int i = 0; i < logs.length; i++) ...[
                                if (i > 0)
                                  const Divider(
                                    height: 1,
                                    color: AppColors.slate100,
                                  ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              logs[i].actionDisplayLabel,
                                              style: GoogleFonts.inter(
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w700,
                                                color: logs[i].action ==
                                                        'LOCK_USER'
                                                    ? AppColors.expense
                                                    : AppColors.primary,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            fmt.format(
                                              logs[i].createdAt.toLocal(),
                                            ),
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              color: AppColors.slate500,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (logs[i].details.isNotEmpty) ...[
                                        const SizedBox(height: 3),
                                        Text(
                                          logs[i].details,
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            color: AppColors.slate700,
                                            height: 1.35,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 2),
                                      Text(
                                        'Thực hiện bởi: ${logs[i].adminEmail.isNotEmpty ? logs[i].adminEmail : logs[i].adminId}',
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          color: AppColors.slate500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            const Divider(height: 1, color: AppColors.slate200),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Đóng'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 17, color: AppColors.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.slate900,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyBox(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.slate50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.slate200),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.slate500),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              '$label:',
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
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.slate900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCopyableRow(
    String label,
    String value, {
    required Key copyKey,
    required VoidCallback onCopy,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              '$label:',
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
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.slate900,
              ),
            ),
          ),
          IconButton(
            key: copyKey,
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            tooltip: 'Sao chép $label',
            onPressed: onCopy,
            icon: const Icon(Icons.copy_rounded, color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}

/// Hộp thoại Khóa tài khoản với 5 nhóm lý do chuẩn hóa & ô ghi chú (bắt buộc khi chọn Lý do khác).
class _LockAccountDialog extends StatefulWidget {
  final AppUser targetUser;

  const _LockAccountDialog({required this.targetUser});

  @override
  State<_LockAccountDialog> createState() => _LockAccountDialogState();
}

class _LockAccountDialogState extends State<_LockAccountDialog> {
  final _noteCtrl = TextEditingController();
  AdminLockReasonPreset _selectedPreset = AdminLockReasonPreset.termsViolation;
  String? _validationError;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final detail = _noteCtrl.text.trim();
    if (_selectedPreset == AdminLockReasonPreset.other && detail.isEmpty) {
      setState(() {
        _validationError =
            'Vui lòng nhập ghi chú chi tiết khi chọn "Lý do khác".';
      });
      return;
    }

    final combinedReason = _selectedPreset == AdminLockReasonPreset.other
        ? detail
        : (detail.isEmpty
            ? _selectedPreset.label
            : '${_selectedPreset.label} — $detail');

    Navigator.of(context).pop(combinedReason);
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.targetUser;
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.lock_outline_rounded, color: AppColors.expense, size: 22),
          SizedBox(width: 8),
          Expanded(child: Text('Xác nhận Khóa tài khoản')),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tài khoản "${user.email}" (UID: ${user.uid}) sẽ bị chặn truy cập realtime trên Mobile ngay sau khi xác nhận.',
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  color: AppColors.slate600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Chọn nhóm lý do khóa:',
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.slate800,
                ),
              ),
              const SizedBox(height: 6),
              for (final preset in AdminLockReasonPreset.values)
                InkWell(
                  key: ValueKey('lock_reason_preset_${preset.code}'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() {
                    _selectedPreset = preset;
                    _validationError = null;
                  }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _selectedPreset == preset
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_off_rounded,
                          size: 19,
                          color: _selectedPreset == preset
                              ? AppColors.expense
                              : AppColors.slate400,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            preset.label,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: _selectedPreset == preset
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: AppColors.slate800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('admin_lock_reason_input'),
                controller: _noteCtrl,
                maxLines: 3,
                maxLength: 300,
                onChanged: (_) {
                  if (_validationError != null) {
                    setState(() => _validationError = null);
                  }
                },
                decoration: InputDecoration(
                  labelText: _selectedPreset == AdminLockReasonPreset.other
                      ? 'Ghi chú chi tiết (bắt buộc)'
                      : 'Ghi chú bổ sung (tùy chọn)',
                  hintText:
                      'Nhập thông tin cụ thể hiển thị cho người dùng và lưu vào Nhật ký quản trị...',
                  errorText: _validationError,
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          key: const ValueKey('admin_confirm_lock_btn'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.expense),
          onPressed: _submit,
          child: const Text('Xác nhận Khóa'),
        ),
      ],
    );
  }
}

/// Hộp thoại Mở khóa tài khoản (có ghi chú tùy chọn, hiển thị lý do khóa trước đó).
class _UnlockAccountDialog extends StatefulWidget {
  final AppUser targetUser;

  const _UnlockAccountDialog({required this.targetUser});

  @override
  State<_UnlockAccountDialog> createState() => _UnlockAccountDialogState();
}

class _UnlockAccountDialogState extends State<_UnlockAccountDialog> {
  final _noteCtrl = TextEditingController();

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.targetUser;
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.lock_open_rounded, color: AppColors.income, size: 22),
          SizedBox(width: 8),
          Expanded(child: Text('Xác nhận Mở khóa tài khoản')),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Khôi phục quyền truy cập cho tài khoản "${user.email}".',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppColors.slate700,
              ),
            ),
            if (user.lockReason != null && user.lockReason!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.slate50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.slate200),
                ),
                child: Text(
                  'Lý do khóa trước đó: ${user.lockReason!}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.slate600,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('admin_unlock_note_input'),
              controller: _noteCtrl,
              maxLines: 2,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: 'Ghi chú mở khóa (tùy chọn)',
                hintText: 'VD: Đã xác minh thông tin chủ tài khoản',
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          key: const ValueKey('admin_confirm_lock_btn'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.income),
          onPressed: () => Navigator.of(context).pop(_noteCtrl.text.trim()),
          child: const Text('Xác nhận Mở khóa'),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../models/admin_audit_log_model.dart';
import '../../models/monthly_financial_plan.dart';
import '../../utils/constants.dart';
import '../../widgets/app_snackbar.dart';
import '../services/admin_web_service.dart';
import '../widgets/admin_governance_widgets.dart';

/// Màn hình Quản lý Thông báo Hệ thống (`system_announcements`) trên Admin Web Portal (Mục 3.4).
/// Chức năng:
/// - Tạo mới, chỉnh sửa tiêu đề & nội dung thông báo (khớp giới hạn backend 150/1000 ký tự).
/// - Kích hoạt hoặc ngừng hiển thị (`isActive`) thông báo.
/// - Xóa thông báo có hộp thoại xác nhận, chống bấm đúp và xử lý lỗi an toàn.
/// - Đồng bộ realtime sang ứng dụng User (`NotificationScreen`).
class AdminAnnouncementsView extends StatefulWidget {
  final AdminWebService adminService;
  final String currentAdminUid;
  final String currentAdminEmail;
  final Map<String, dynamic>? tokenClaimsOverride;

  const AdminAnnouncementsView({
    super.key,
    required this.adminService,
    required this.currentAdminUid,
    required this.currentAdminEmail,
    this.tokenClaimsOverride,
  });

  @override
  State<AdminAnnouncementsView> createState() => _AdminAnnouncementsViewState();
}

class _AdminAnnouncementsViewState extends State<AdminAnnouncementsView> {
  static const int _kMaxTitleLength = 150;
  static const int _kMaxContentLength = 1000;

  late Stream<List<SystemAnnouncement>> _announcementsStream;
  final Set<String> _busyAnnouncementIds = <String>{};

  @override
  void initState() {
    super.initState();
    _announcementsStream = widget.adminService.firestoreService
        .streamSystemAnnouncements(activeOnly: false);
  }

  @override
  void didUpdateWidget(covariant AdminAnnouncementsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.adminService != widget.adminService) {
      _announcementsStream = widget.adminService.firestoreService
          .streamSystemAnnouncements(activeOnly: false);
    }
  }

  void _retryStream() {
    setState(() {
      _announcementsStream = widget.adminService.firestoreService
          .streamSystemAnnouncements(activeOnly: false);
    });
  }

  Future<void> _openAnnouncementDialog({SystemAnnouncement? existing}) async {
    final savedTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => _AnnouncementFormDialog(
        existing: existing,
        maxTitleLength: _kMaxTitleLength,
        maxContentLength: _kMaxContentLength,
        onSave: (announcement, isNew) => widget.adminService.saveAnnouncement(
          adminUid: widget.currentAdminUid,
          adminEmail: widget.currentAdminEmail,
          announcement: announcement,
          isNew: isNew,
          tokenClaimsOverride: widget.tokenClaimsOverride,
        ),
      ),
    );

    if (savedTitle == null || !mounted) return;
    AppSnackbar.show(
      context,
      existing == null
          ? 'Đã đăng thông báo hệ thống "$savedTitle".'
          : 'Đã cập nhật thông báo "$savedTitle".',
    );
  }

  Future<void> _handleToggleActive(
    SystemAnnouncement announcement,
    bool nextActive,
  ) async {
    if (_busyAnnouncementIds.contains(announcement.id)) return;
    setState(() => _busyAnnouncementIds.add(announcement.id));
    try {
      await widget.adminService.toggleAnnouncementActive(
        adminUid: widget.currentAdminUid,
        adminEmail: widget.currentAdminEmail,
        announcement: announcement,
        isActive: nextActive,
        tokenClaimsOverride: widget.tokenClaimsOverride,
      );
      if (!mounted) return;
      AppSnackbar.show(
        context,
        nextActive
            ? 'Đã kích hoạt hiển thị thông báo "${announcement.title}".'
            : 'Đã tạm ẩn thông báo "${announcement.title}".',
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.show(
        context,
        'Không thể cập nhật trạng thái thông báo: ${formatAdminErrorMessage(e)}',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _busyAnnouncementIds.remove(announcement.id));
      }
    }
  }

  Future<void> _confirmAndDeleteAnnouncement(
    SystemAnnouncement announcement,
  ) async {
    if (_busyAnnouncementIds.contains(announcement.id)) return;

    final confirm = await showAdminConfirmDialog(
      context: context,
      title: 'Xác nhận xóa thông báo hệ thống',
      message:
          'Bạn có chắc chắn muốn xóa vĩnh viễn thông báo "${announcement.title}"?\n\n'
          '• Thông báo sẽ biến mất ngay lập tức khỏi ứng dụng người dùng và không thể khôi phục.',
      confirmLabel: 'Xóa thông báo',
      confirmColor: AppColors.expense,
      confirmButtonKey: ValueKey('confirm_delete_ann_${announcement.id}'),
    );
    if (confirm == null || !confirm.confirmed || !mounted) return;

    setState(() => _busyAnnouncementIds.add(announcement.id));
    try {
      await widget.adminService.deleteAnnouncement(
        adminUid: widget.currentAdminUid,
        adminEmail: widget.currentAdminEmail,
        announcement: announcement,
        tokenClaimsOverride: widget.tokenClaimsOverride,
      );
      if (!mounted) return;
      AppSnackbar.show(
        context,
        'Đã xóa thông báo "${announcement.title}".',
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.show(
        context,
        'Không thể xóa thông báo: ${formatAdminErrorMessage(e)}',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _busyAnnouncementIds.remove(announcement.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<SystemAnnouncement>>(
      stream: _announcementsStream,
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
              onRetry: _retryStream,
            ),
          );
        }

        final items = snapshot.data ?? const <SystemAnnouncement>[];

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.slate200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Thông báo Hệ thống (${items.length})',
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.slate900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Các thông báo đang kích hoạt sẽ hiển thị trực tiếp theo thời gian thực trên ứng dụng của tất cả người dùng.',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppColors.slate500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      key: const ValueKey('admin_create_announcement_btn'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 42),
                      ),
                      onPressed: () => _openAnnouncementDialog(),
                      icon: const Icon(Icons.add_alert_rounded, size: 18),
                      label: const Text('Tạo Thông báo Mới'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.slate200),
                  ),
                  child: items.isEmpty
                      ? Center(
                          child: Text(
                            'Chưa có thông báo hệ thống nào.',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: AppColors.slate500,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const Divider(
                            height: 16,
                            color: AppColors.slate200,
                          ),
                          itemBuilder: (context, index) {
                            final a = items[index];
                            return Opacity(
                              opacity: a.isActive ? 1.0 : 0.6,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: a.isActive
                                          ? AppColors.infoBackground
                                          : AppColors.slate100,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      Icons.campaign_rounded,
                                      color: a.isActive
                                          ? AppColors.primary
                                          : AppColors.slate500,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                a.title,
                                                style: GoogleFonts.inter(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppColors.slate900,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 7,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: a.isActive
                                                    ? AppColors.incomeBackground
                                                    : AppColors.slate100,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                a.isActive
                                                    ? 'ĐANG HIỂN THỊ'
                                                    : 'ĐÃ TẠM ẨN',
                                                style: GoogleFonts.inter(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                  color: a.isActive
                                                      ? AppColors.income
                                                      : AppColors.slate500,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          a.content,
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            color: AppColors.slate700,
                                            height: 1.4,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Đăng lúc: ${DateFormat('dd/MM/yyyy HH:mm').format(a.createdAt)}',
                                          style: GoogleFonts.inter(
                                            fontSize: 11.5,
                                            color: AppColors.slate500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    key: ValueKey('edit_ann_${a.id}'),
                                    tooltip: 'Chỉnh sửa thông báo',
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 20,
                                    ),
                                    onPressed:
                                        _busyAnnouncementIds.contains(a.id)
                                            ? null
                                            : () => _openAnnouncementDialog(
                                                existing: a),
                                  ),
                                  Switch(
                                    key: ValueKey('toggle_ann_${a.id}'),
                                    value: a.isActive,
                                    onChanged:
                                        _busyAnnouncementIds.contains(a.id)
                                            ? null
                                            : (val) =>
                                                _handleToggleActive(a, val),
                                  ),
                                  IconButton(
                                    key: ValueKey('delete_ann_${a.id}'),
                                    tooltip: 'Xóa thông báo',
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      color: AppColors.expense,
                                      size: 20,
                                    ),
                                    onPressed:
                                        _busyAnnouncementIds.contains(a.id)
                                            ? null
                                            : () =>
                                                _confirmAndDeleteAnnouncement(
                                                    a),
                                  ),
                                ],
                              ),
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
}

/// Dialog tạo / chỉnh sửa Thông báo Hệ thống: tự quản lý và giải phóng `TextEditingController`,
/// giới hạn độ dài khớp Backend (150/1000 ký tự), chống bấm đúp và bắt lỗi an toàn.
class _AnnouncementFormDialog extends StatefulWidget {
  final SystemAnnouncement? existing;
  final int maxTitleLength;
  final int maxContentLength;
  final Future<String> Function(SystemAnnouncement announcement, bool isNew)
      onSave;

  const _AnnouncementFormDialog({
    required this.existing,
    required this.maxTitleLength,
    required this.maxContentLength,
    required this.onSave,
  });

  @override
  State<_AnnouncementFormDialog> createState() =>
      _AnnouncementFormDialogState();
}

class _AnnouncementFormDialogState extends State<_AnnouncementFormDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _contentCtrl;
  late bool _isActive;
  bool _isSaving = false;
  String? _validationError;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.existing?.title ?? '');
    _contentCtrl = TextEditingController(text: widget.existing?.content ?? '');
    _isActive = widget.existing?.isActive ?? true;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSaving) return;
    final title = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();
    if (title.isEmpty || content.isEmpty) {
      setState(() {
        _validationError = 'Vui lòng nhập đầy đủ tiêu đề và nội dung thông báo.';
      });
      return;
    }
    if (title.length > widget.maxTitleLength) {
      setState(() {
        _validationError =
            'Tiêu đề không được vượt quá ${widget.maxTitleLength} ký tự.';
      });
      return;
    }
    if (content.length > widget.maxContentLength) {
      setState(() {
        _validationError =
            'Nội dung không được vượt quá ${widget.maxContentLength} ký tự.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _validationError = null;
    });

    final ann = SystemAnnouncement(
      id: widget.existing?.id ?? '',
      title: title,
      content: content,
      isActive: _isActive,
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    try {
      await widget.onSave(ann, _isNew);
      if (mounted) {
        Navigator.of(context).pop(title);
      }
    } catch (e) {
      if (!mounted) return;
      final msg = formatAdminErrorMessage(e);
      setState(() {
        _isSaving = false;
        _validationError = msg;
      });
      AppSnackbar.show(context, msg, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _isNew ? 'Tạo Thông báo Hệ thống' : 'Chỉnh sửa Thông báo Hệ thống',
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const ValueKey('admin_ann_title_input'),
                controller: _titleCtrl,
                enabled: !_isSaving,
                maxLength: widget.maxTitleLength,
                decoration: const InputDecoration(
                  labelText: 'Tiêu đề thông báo',
                  hintText: 'VD: Bảo trì nâng cấp dịch vụ AI định kỳ',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('admin_ann_content_input'),
                controller: _contentCtrl,
                enabled: !_isSaving,
                maxLines: 4,
                maxLength: widget.maxContentLength,
                decoration: const InputDecoration(
                  labelText: 'Nội dung chi tiết',
                  hintText: 'Nhập nội dung gửi tới toàn bộ người dùng...',
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                key: const ValueKey('admin_ann_active_switch'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Kích hoạt hiển thị ngay trên User App'),
                value: _isActive,
                onChanged:
                    _isSaving ? null : (v) => setState(() => _isActive = v),
              ),
              if (_validationError != null) ...[
                const SizedBox(height: 6),
                Text(
                  _validationError!,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.expense,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          key: const ValueKey('admin_ann_save_btn'),
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(_isNew ? 'Đăng thông báo' : 'Lưu thay đổi'),
        ),
      ],
    );
  }
}

/// Màn hình Nhật ký Quản trị (`admin_logs`) trên Admin Web Portal (Mục 3.5).
/// Nguyên tắc bảo mật:
/// - Chỉ hiển thị các thao tác đã thực hiện thành công.
/// - Admin chỉ có quyền ĐỌC (Read-Only), tuyệt đối không có chức năng sửa hoặc xóa log.
class AdminAuditLogsView extends StatefulWidget {
  final AdminWebService adminService;

  const AdminAuditLogsView({
    super.key,
    required this.adminService,
  });

  @override
  State<AdminAuditLogsView> createState() => _AdminAuditLogsViewState();
}

class _AdminAuditLogsViewState extends State<AdminAuditLogsView> {
  String _searchQuery = '';
  String _targetTypeFilter =
      'all'; // 'all' | 'user' | 'system_category' | 'system_announcement'
  late Stream<List<AdminAuditLog>> _auditLogsStream;

  @override
  void initState() {
    super.initState();
    _auditLogsStream =
        widget.adminService.firestoreService.streamAdminAuditLogs(limit: 100);
  }

  @override
  void didUpdateWidget(covariant AdminAuditLogsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.adminService != widget.adminService) {
      _auditLogsStream = widget.adminService.firestoreService
          .streamAdminAuditLogs(limit: 100);
    }
  }

  void _retryStream() {
    setState(() {
      _auditLogsStream =
          widget.adminService.firestoreService.streamAdminAuditLogs(limit: 100);
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AdminAuditLog>>(
      stream: _auditLogsStream,
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
              onRetry: _retryStream,
            ),
          );
        }

        final allLogs = snapshot.data ?? const <AdminAuditLog>[];
        final filtered = allLogs.where((log) {
          if (_targetTypeFilter != 'all' &&
              log.targetType != _targetTypeFilter) {
            return false;
          }
          if (_searchQuery.isNotEmpty) {
            final q = _searchQuery.toLowerCase();
            return log.actionDisplayLabel.toLowerCase().contains(q) ||
                log.adminEmail.toLowerCase().contains(q) ||
                log.adminId.toLowerCase().contains(q) ||
                log.targetLabel.toLowerCase().contains(q) ||
                log.details.toLowerCase().contains(q);
          }
          return true;
        }).toList();

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                    Row(
                      children: [
                        const Icon(
                          Icons.shield_outlined,
                          size: 18,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Nhật ký Quản trị Bất biến (Immutable Audit Logs) — Chỉ đọc, không cho phép chỉnh sửa hoặc xóa bản ghi.',
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.slate700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildTypeChip('Tất cả (${allLogs.length})', 'all'),
                        _buildTypeChip('Tài khoản User', 'user'),
                        _buildTypeChip('Danh mục hệ thống', 'system_category'),
                        _buildTypeChip(
                          'Thông báo hệ thống',
                          'system_announcement',
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('admin_audit_search_input'),
                      onChanged: (v) =>
                          setState(() => _searchQuery = v.trim()),
                      decoration: const InputDecoration(
                        hintText:
                            'Tìm theo hành động, email Admin, đối tượng tác động...',
                        prefixIcon: Icon(Icons.search_rounded),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.slate200),
                  ),
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            'Không có bản ghi nhật ký quản trị nào phù hợp.',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: AppColors.slate500,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const Divider(
                            height: 16,
                            color: AppColors.slate200,
                          ),
                          itemBuilder: (context, index) {
                            final log = filtered[index];
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: log.isSuccess
                                        ? AppColors.incomeBackground
                                        : AppColors.expenseBackground,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    log.isSuccess
                                        ? Icons.verified_outlined
                                        : Icons.error_outline_rounded,
                                    color: log.isSuccess
                                        ? AppColors.income
                                        : AppColors.expense,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 4,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          Text(
                                            log.actionDisplayLabel,
                                            style: GoogleFonts.inter(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.slate900,
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: log.isSuccess
                                                  ? AppColors.incomeBackground
                                                  : AppColors.expenseBackground,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              log.isSuccess
                                                  ? 'THÀNH CÔNG'
                                                  : 'THẤT BẠI',
                                              style: GoogleFonts.inter(
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w700,
                                                color: log.isSuccess
                                                    ? AppColors.income
                                                    : AppColors.expense,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        log.details.isNotEmpty
                                            ? log.details
                                            : 'Đối tượng: ${log.targetLabel} (${log.targetId})',
                                        style: GoogleFonts.inter(
                                          fontSize: 12.5,
                                          color: AppColors.slate700,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        'Thực hiện bởi: ${log.adminEmail.isNotEmpty ? log.adminEmail : log.adminId} (UID: ${log.adminId}) · Đối tượng: ${log.targetLabel}',
                                        style: GoogleFonts.inter(
                                          fontSize: 11.5,
                                          color: AppColors.slate500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  DateFormat('dd/MM/yyyy\nHH:mm:ss')
                                      .format(log.createdAt),
                                  textAlign: TextAlign.right,
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: AppColors.slate500,
                                  ),
                                ),
                              ],
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

  Widget _buildTypeChip(String label, String value) {
    final selected = _targetTypeFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _targetTypeFilter = value),
    );
  }
}

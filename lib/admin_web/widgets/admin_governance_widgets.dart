import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/ai_runtime_config_model.dart';
import '../../utils/constants.dart';
import '../services/admin_http_helper.dart';
import '../services/admin_web_service.dart';

bool isAdminPermissionDeniedError(Object error) {
  if (error is AdminPermissionException) return true;
  if (error is AdminCloudCallException && error.isAuthOrPermissionError) {
    return true;
  }
  if (error is FirebaseException) {
    return error.code == 'permission-denied' || error.code == 'unauthenticated';
  }
  final lower = error.toString().toLowerCase();
  return lower.contains('permission-denied') ||
      lower.contains('truy cập bị từ chối') ||
      lower.contains('không có quyền');
}

String formatAdminErrorMessage(Object error) {
  if (error is AdminCloudCallException) {
    if (error.validationErrors.isEmpty) return error.message;
    return '${error.message}\n• ${error.validationErrors.join('\n• ')}';
  }
  if (error is AdminPermissionException) return error.message;
  if (error is FirebaseException) {
    if (error.code == 'permission-denied') {
      return 'Permission Denied: Tài khoản hiện tại không có quyền đọc/ghi dữ liệu quản trị này trên Firestore.';
    }
    return error.message ?? 'Lỗi Firestore (${error.code}).';
  }
  return error.toString().replaceFirst('Exception: ', '');
}

void showAdminSnackBar(
  BuildContext context,
  String message, {
  bool isError = false,
}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: isError ? AppColors.expense : AppColors.income,
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: isError ? 5 : 3),
    ),
  );
}

class AdminConfirmResult {
  final bool confirmed;
  final String note;

  const AdminConfirmResult({
    required this.confirmed,
    required this.note,
  });
}

Future<AdminConfirmResult?> showAdminConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = 'Xác nhận',
  String cancelLabel = 'Hủy',
  Color confirmColor = AppColors.primary,
  bool showNoteField = false,
  String noteLabel = 'Ghi chú thay đổi (Change Note)',
  String noteHint = 'Mô tả ngắn lý do thay đổi để lưu Audit Log...',
  String initialNote = '',
  bool noteRequired = false,
  Key? confirmButtonKey,
  Key? noteFieldKey,
}) {
  return showDialog<AdminConfirmResult>(
    context: context,
    builder: (ctx) => _AdminConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      confirmColor: confirmColor,
      showNoteField: showNoteField,
      noteLabel: noteLabel,
      noteHint: noteHint,
      initialNote: initialNote,
      noteRequired: noteRequired,
      confirmButtonKey: confirmButtonKey,
      noteFieldKey: noteFieldKey,
    ),
  );
}

class _AdminConfirmDialog extends StatefulWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final Color confirmColor;
  final bool showNoteField;
  final String noteLabel;
  final String noteHint;
  final String initialNote;
  final bool noteRequired;
  final Key? confirmButtonKey;
  final Key? noteFieldKey;

  const _AdminConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.confirmColor,
    required this.showNoteField,
    required this.noteLabel,
    required this.noteHint,
    required this.initialNote,
    required this.noteRequired,
    this.confirmButtonKey,
    this.noteFieldKey,
  });

  @override
  State<_AdminConfirmDialog> createState() => _AdminConfirmDialogState();
}

class _AdminConfirmDialogState extends State<_AdminConfirmDialog> {
  late final TextEditingController _noteController;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController(text: widget.initialNote);
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.title,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.message,
              style: const TextStyle(
                fontSize: 13.5,
                color: AppColors.slate700,
                height: 1.45,
              ),
            ),
            if (widget.showNoteField) ...[
              const SizedBox(height: 14),
              TextField(
                key: widget.noteFieldKey,
                controller: _noteController,
                maxLines: 2,
                maxLength: 200,
                decoration: InputDecoration(
                  labelText: widget.noteLabel,
                  hintText: widget.noteHint,
                  errorText: _validationError,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(widget.cancelLabel),
        ),
        ElevatedButton(
          key: widget.confirmButtonKey,
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.confirmColor,
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            final text = _noteController.text.trim();
            if (widget.showNoteField && widget.noteRequired && text.isEmpty) {
              setState(() {
                _validationError = 'Vui lòng nhập lý do/ghi chú bắt buộc.';
              });
              return;
            }
            Navigator.of(context).pop(
              AdminConfirmResult(confirmed: true, note: text),
            );
          },
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class AdminStatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final Color backgroundColor;
  final IconData? icon;

  const AdminStatusBadge({
    super.key,
    required this.label,
    required this.color,
    required this.backgroundColor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class AdminSectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const AdminSectionCard({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.slate200),
      ),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.slate800,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.slate500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 12),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class AdminLoadingCard extends StatelessWidget {
  final String message;

  const AdminLoadingCard({
    super.key,
    this.message = 'Đang tải dữ liệu quản trị...',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.slate200),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(fontSize: 13, color: AppColors.slate500),
          ),
        ],
      ),
    );
  }
}

class AdminEmptyStateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  const AdminEmptyStateCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.slate200),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: AppColors.slate400),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: AppColors.slate700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 12.5, color: AppColors.slate500),
            textAlign: TextAlign.center,
          ),
          if (action != null) ...[
            const SizedBox(height: 14),
            action!,
          ],
        ],
      ),
    );
  }
}

class AdminErrorStateCard extends StatelessWidget {
  final Object error;
  final VoidCallback? onRetry;

  const AdminErrorStateCard({
    super.key,
    required this.error,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final isPerm = isAdminPermissionDeniedError(error);
    return Container(
      key: isPerm ? const ValueKey('admin_permission_denied_card') : null,
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isPerm ? AppColors.warningBackground : AppColors.expenseBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: (isPerm ? AppColors.warning : AppColors.expense)
              .withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isPerm ? Icons.gpp_maybe_outlined : Icons.error_outline_rounded,
            color: isPerm ? AppColors.warning : AppColors.expense,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPerm
                      ? 'Không đủ quyền truy cập dữ liệu'
                      : 'Đã xảy ra lỗi tải dữ liệu',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isPerm ? AppColors.warning : AppColors.expense,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  formatAdminErrorMessage(error),
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.slate700,
                  ),
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Thử lại'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Thanh trạng thái & hành động chuẩn cho quy trình Draft -> Sandbox Verify -> Publish.
class AdminDraftPublishBar extends StatelessWidget {
  final String configTitle;
  final int? publishedVersion;
  final DateTime? publishedAt;
  final String? publishedByEmail;
  final DraftConfigEnvelope? draftEnvelope;
  final String localPayloadHash;
  final bool hasUnsavedLocalChanges;
  final List<String> localValidationErrors;
  final bool isBusy;
  final VoidCallback onSaveDraft;
  final VoidCallback onVerifySandbox;
  final VoidCallback onPublish;
  final VoidCallback? onResetToPublished;
  final VoidCallback? onResetToDefaults;

  const AdminDraftPublishBar({
    super.key,
    required this.configTitle,
    required this.publishedVersion,
    this.publishedAt,
    this.publishedByEmail,
    required this.draftEnvelope,
    required this.localPayloadHash,
    required this.hasUnsavedLocalChanges,
    required this.localValidationErrors,
    required this.isBusy,
    required this.onSaveDraft,
    required this.onVerifySandbox,
    required this.onPublish,
    this.onResetToPublished,
    this.onResetToDefaults,
  });

  @override
  Widget build(BuildContext context) {
    final envelope = draftEnvelope;
    final hasSavedDraft = envelope != null;
    final isVerifiedValid =
        !hasUnsavedLocalChanges && (envelope?.isSandboxVerificationValid ?? false);
    final hashChangedAfterVerify = hasSavedDraft &&
        envelope.verifiedSandboxHash != null &&
        envelope.verifiedSandboxHash!.isNotEmpty &&
        envelope.verifiedSandboxHash != envelope.draftHash;

    final String sandboxStatusText;
    final Color sandboxColor;
    final Color sandboxBg;
    final IconData sandboxIcon;

    if (!hasSavedDraft) {
      sandboxStatusText = 'Chưa có Draft trên Server';
      sandboxColor = AppColors.slate600;
      sandboxBg = AppColors.slate100;
      sandboxIcon = Icons.edit_note_rounded;
    } else if (hasUnsavedLocalChanges) {
      sandboxStatusText = 'Có thay đổi chưa lưu — Lưu Draft để xác minh';
      sandboxColor = AppColors.warning;
      sandboxBg = AppColors.warningBackground;
      sandboxIcon = Icons.pending_actions_rounded;
    } else if (isVerifiedValid) {
      sandboxStatusText = 'Sandbox Verified (HMAC khớp Hash)';
      sandboxColor = AppColors.income;
      sandboxBg = AppColors.incomeBackground;
      sandboxIcon = Icons.verified_rounded;
    } else if (hashChangedAfterVerify) {
      sandboxStatusText = 'Hash đã thay đổi — Cần xác minh lại Sandbox';
      sandboxColor = AppColors.expense;
      sandboxBg = AppColors.expenseBackground;
      sandboxIcon = Icons.sync_problem_rounded;
    } else {
      sandboxStatusText = 'Draft chưa xác minh Sandbox';
      sandboxColor = AppColors.warning;
      sandboxBg = AppColors.warningBackground;
      sandboxIcon = Icons.science_outlined;
    }

    final shortLocalHash = localPayloadHash.length > 12
        ? '${localPayloadHash.substring(0, 12)}...'
        : localPayloadHash;
    final fmt = DateFormat('dd/MM/yyyy HH:mm');

    return Container(
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
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                configTitle,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.slate800,
                ),
              ),
              AdminStatusBadge(
                label: publishedVersion != null
                    ? 'Published v$publishedVersion'
                    : 'Published: Mặc định v1',
                color: AppColors.info,
                backgroundColor: AppColors.infoBackground,
                icon: Icons.public_rounded,
              ),
              AdminStatusBadge(
                label: sandboxStatusText,
                color: sandboxColor,
                backgroundColor: sandboxBg,
                icon: sandboxIcon,
              ),
              if (hasUnsavedLocalChanges)
                const AdminStatusBadge(
                  label: 'Chưa lưu Draft',
                  color: AppColors.warning,
                  backgroundColor: AppColors.warningBackground,
                  icon: Icons.edit_rounded,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              Text(
                'Hash cục bộ: $shortLocalHash',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.slate500,
                  fontFamily: 'monospace',
                ),
              ),
              if (publishedAt != null)
                Text(
                  'Xuất bản lúc: ${fmt.format(publishedAt!.toLocal())}${publishedByEmail != null && publishedByEmail!.isNotEmpty ? ' ($publishedByEmail)' : ''}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.slate500,
                  ),
                ),
              if (envelope?.updatedAt != null)
                Text(
                  'Cập nhật Draft: ${fmt.format(envelope!.updatedAt!.toLocal())}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.slate500,
                  ),
                ),
            ],
          ),
          if (localValidationErrors.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.expenseBackground,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.expense.withValues(alpha: 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Lỗi hợp lệ cấu hình (Chặn lưu Draft):',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.expense,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final err in localValidationErrors)
                    Text(
                      '• $err',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.expense,
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              if (onResetToDefaults != null)
                OutlinedButton.icon(
                  onPressed: isBusy ? null : onResetToDefaults,
                  icon: const Icon(Icons.restart_alt_rounded, size: 17),
                  label: const Text('Nạp mặc định'),
                ),
              if (onResetToPublished != null)
                OutlinedButton.icon(
                  onPressed: isBusy ? null : onResetToPublished,
                  icon: const Icon(Icons.undo_rounded, size: 17),
                  label: const Text('Tải bản Published'),
                ),
              OutlinedButton.icon(
                key: const ValueKey('admin_save_draft_btn'),
                onPressed:
                    (isBusy || localValidationErrors.isNotEmpty) ? null : onSaveDraft,
                icon: const Icon(Icons.save_outlined, size: 17),
                label: const Text('Lưu Draft'),
              ),
              ElevatedButton.icon(
                key: const ValueKey('admin_verify_sandbox_btn'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.info,
                  foregroundColor: Colors.white,
                ),
                onPressed: (isBusy || !hasSavedDraft || hasUnsavedLocalChanges)
                    ? null
                    : onVerifySandbox,
                icon: const Icon(Icons.verified_user_outlined, size: 17),
                label: const Text('Xác minh HMAC Sandbox'),
              ),
              ElevatedButton.icon(
                key: const ValueKey('admin_publish_config_btn'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.income,
                  foregroundColor: Colors.white,
                ),
                onPressed: (isBusy || !isVerifiedValid) ? null : onPublish,
                icon: const Icon(Icons.rocket_launch_outlined, size: 17),
                label: const Text('Publish lên Production'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bảng Lịch sử phiên bản & Khôi phục (Rollback tạo version mới, không ghi đè snapshot cũ).
class AdminVersionHistoryCard extends StatelessWidget {
  final String configType;
  final int? currentPublishedVersion;
  final AdminWebService adminWebService;
  final bool isBusy;
  final void Function(ConfigVersionSnapshot version) onRollbackRequested;
  final void Function(ConfigVersionSnapshot version)? onLoadSnapshotIntoDraft;

  const AdminVersionHistoryCard({
    super.key,
    required this.configType,
    required this.currentPublishedVersion,
    required this.adminWebService,
    required this.isBusy,
    required this.onRollbackRequested,
    this.onLoadSnapshotIntoDraft,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    return AdminSectionCard(
      title: 'Lịch sử phiên bản & Khôi phục (Rollback)',
      subtitle:
          'Mỗi lần Publish hoặc Rollback tạo một bản chụp bất biến mới trong config_versions.',
      child: StreamBuilder<List<ConfigVersionSnapshot>>(
        stream: adminWebService.streamConfigVersions(configType),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const AdminLoadingCard(
              message: 'Đang tải lịch sử phiên bản...',
            );
          }
          if (snapshot.hasError) {
            return AdminErrorStateCard(error: snapshot.error!);
          }
          final versions = snapshot.data ?? const [];
          if (versions.isEmpty) {
            return const AdminEmptyStateCard(
              icon: Icons.history_rounded,
              title: 'Chưa có lịch sử phiên bản nào được xuất bản',
              subtitle:
                  'Sau khi xác minh Sandbox và Publish lần đầu, lịch sử phiên bản sẽ hiển thị tại đây.',
            );
          }

          return Column(
            children: [
              for (int i = 0; i < versions.length; i++) ...[
                if (i > 0) const Divider(height: 16, color: AppColors.slate200),
                _VersionRow(
                  version: versions[i],
                  isCurrentPublished:
                      currentPublishedVersion == versions[i].versionNumber,
                  formattedTime: fmt.format(versions[i].publishedAt.toLocal()),
                  isBusy: isBusy,
                  onRollback: () => onRollbackRequested(versions[i]),
                  onLoadToEditor: onLoadSnapshotIntoDraft == null
                      ? null
                      : () => onLoadSnapshotIntoDraft!(versions[i]),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _VersionRow extends StatelessWidget {
  final ConfigVersionSnapshot version;
  final bool isCurrentPublished;
  final String formattedTime;
  final bool isBusy;
  final VoidCallback onRollback;
  final VoidCallback? onLoadToEditor;

  const _VersionRow({
    required this.version,
    required this.isCurrentPublished,
    required this.formattedTime,
    required this.isBusy,
    required this.onRollback,
    this.onLoadToEditor,
  });

  @override
  Widget build(BuildContext context) {
    final shortHash = version.payloadHash.length > 10
        ? version.payloadHash.substring(0, 10)
        : version.payloadHash;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isCurrentPublished
                          ? AppColors.incomeBackground
                          : AppColors.slate100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'v${version.versionNumber}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: isCurrentPublished
                            ? AppColors.income
                            : AppColors.slate700,
                      ),
                    ),
                  ),
                  if (isCurrentPublished)
                    const AdminStatusBadge(
                      label: 'Đang chạy Production',
                      color: AppColors.income,
                      backgroundColor: AppColors.incomeBackground,
                    ),
                  if (version.rollbackFromVersion != null)
                    AdminStatusBadge(
                      label: 'Rollback từ v${version.rollbackFromVersion}',
                      color: AppColors.warning,
                      backgroundColor: AppColors.warningBackground,
                    ),
                  Text(
                    'Hash: $shortHash...',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.slate500,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                version.changeNote.isNotEmpty
                    ? version.changeNote
                    : 'Không có ghi chú thay đổi',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.slate800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Bởi ${version.publishedByEmail.isNotEmpty ? version.publishedByEmail : version.publishedBy} • $formattedTime',
                style: const TextStyle(fontSize: 11.5, color: AppColors.slate500),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            if (onLoadToEditor != null)
              TextButton(
                onPressed: isBusy ? null : onLoadToEditor,
                child: const Text('Nạp vào Draft'),
              ),
            OutlinedButton.icon(
              key: ValueKey('admin_rollback_v_${version.versionNumber}'),
              onPressed: (isBusy || isCurrentPublished) ? null : onRollback,
              icon: const Icon(Icons.history_toggle_off_rounded, size: 16),
              label: const Text('Rollback'),
            ),
          ],
        ),
      ],
    );
  }
}

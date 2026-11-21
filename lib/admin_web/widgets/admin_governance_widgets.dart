import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
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

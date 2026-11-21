import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../utils/constants.dart';
import 'app_button.dart';

class StreamErrorWidget extends StatelessWidget {
  final String error;
  final VoidCallback? onRetry;

  const StreamErrorWidget({
    super.key,
    required this.error,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = error.toLowerCase();
    final isPermissionDenied = normalized.contains('permission-denied') ||
        normalized.contains('missing or insufficient permissions');
    final isIndexBuilding = normalized.contains('failed-precondition') &&
        normalized.contains('index');

    final icon = isPermissionDenied
        ? Icons.lock_outline_rounded
        : (isIndexBuilding
            ? Icons.sync_problem_rounded
            : Icons.wifi_off_rounded);
    final title = isPermissionDenied
        ? context.tr('stream_err_permission_title')
        : (isIndexBuilding
            ? context.tr('stream_err_index_title')
            : context.tr('stream_err_title'));
    final subtitle = isPermissionDenied
        ? context.tr('stream_err_permission_hint')
        : (isIndexBuilding ? context.tr('stream_err_index_hint') : error);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isIndexBuilding
                    ? AppColors.warningBackground
                    : AppColors.expenseBackground,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isIndexBuilding ? AppColors.warning : AppColors.expense,
                size: 36,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: context.appTextPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 13,
                color: context.appTextSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: 140,
                child: AppButton(
                  text: context.tr('common_retry'),
                  icon: Icons.refresh_rounded,
                  onPressed: onRetry,
                  height: 42,
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}

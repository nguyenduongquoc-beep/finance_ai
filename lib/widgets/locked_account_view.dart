import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../models/user_model.dart';
import '../utils/constants.dart';

/// Tạo thông báo lỗi chi tiết (hỗ trợ Vi/En) khi người dùng đăng nhập vào tài khoản đang bị khóa.
String formatLockedAccountLoginError(AppUser profile) {
  final reason = (profile.lockReason != null &&
          profile.lockReason!.trim().isNotEmpty)
      ? profile.lockReason!.trim()
      : AppLocalizations.tr('nav_locked_default_reason');

  final base = AppLocalizations.tr(
    'auth_err_locked_with_reason',
    params: {'reason': reason},
  );

  if (profile.lockedAt == null) return base;

  final timeText =
      DateFormat('dd/MM/yyyy HH:mm').format(profile.lockedAt!.toLocal());
  final suffix = AppLocalizations.tr(
    'auth_err_locked_time_suffix',
    params: {'time': timeText},
  );
  return '$base$suffix';
}

/// Màn hình chặn truy cập phía Mobile khi tài khoản bị Quản trị viên khóa.
/// Hiển thị rõ lý do khóa (`lockReason`), thời điểm khóa (`lockedAt`) với fallback an toàn,
/// hỗ trợ đầy đủ tiếng Việt & tiếng Anh, kèm nút Đăng xuất.
class LockedAccountView extends StatelessWidget {
  final AppUser user;
  final Future<void> Function() onSignOut;

  const LockedAccountView({
    super.key,
    required this.user,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final displayReason = (user.lockReason != null &&
            user.lockReason!.trim().isNotEmpty)
        ? user.lockReason!.trim()
        : context.tr('nav_locked_default_reason');
    final formattedLockedAt = user.lockedAt != null
        ? DateFormat('dd/MM/yyyy HH:mm').format(user.lockedAt!.toLocal())
        : null;

    return Scaffold(
      backgroundColor: context.appBackground,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.expenseBackground,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.expense.withValues(alpha: 0.25),
                      ),
                    ),
                    child: const Icon(
                      Icons.lock_person_rounded,
                      size: 38,
                      color: AppColors.expense,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    context.tr('nav_locked_title'),
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: context.appTextPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr(
                      'nav_locked_body',
                      params: {'email': user.email},
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.45,
                      color: context.appTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    key: const ValueKey('mobile_locked_details_card'),
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: context.appCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.expense.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.info_outline_rounded,
                              size: 18,
                              color: AppColors.expense,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    context.tr('nav_locked_reason_label'),
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: context.appTextSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    displayReason,
                                    key: const ValueKey(
                                      'mobile_locked_reason_text',
                                    ),
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      color: context.appTextPrimary,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (formattedLockedAt != null) ...[
                          const Divider(height: 18),
                          Row(
                            children: [
                              Icon(
                                Icons.schedule_rounded,
                                size: 16,
                                color: context.appTextSecondary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${context.tr('nav_locked_time_label')}: ',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: context.appTextSecondary,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  formattedLockedAt,
                                  key: const ValueKey(
                                    'mobile_locked_time_text',
                                  ),
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: context.appTextPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const ValueKey('mobile_locked_logout_btn'),
                      onPressed: onSignOut,
                      icon: const Icon(Icons.logout_rounded),
                      label: Text(context.tr('nav_locked_logout')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

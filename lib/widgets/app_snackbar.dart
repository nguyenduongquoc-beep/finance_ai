import 'package:flutter/material.dart';
import '../utils/constants.dart';

/// Helper hiển thị SnackBar chuẩn Fintech — đặt gọn ở cạnh dưới vùng nội dung,
/// tự động tránh FloatingActionButton / BottomNavigationBar và chống xếp chồng.
class AppSnackbar {
  static void show(
    BuildContext context,
    String message, {
    bool isError = false,
    bool isWarning = false,
    bool isInfo = false,
    Duration? duration,
  }) {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color bg;
    final Color iconColor;
    final IconData iconData;
    final Duration effectiveDuration;

    if (isError) {
      bg = AppColors.expense;
      iconColor = Colors.white;
      iconData = Icons.error_outline_rounded;
      effectiveDuration = duration ?? const Duration(milliseconds: 3500);
    } else if (isWarning) {
      bg = const Color(0xFFD97706);
      iconColor = Colors.white;
      iconData = Icons.warning_amber_rounded;
      effectiveDuration = duration ?? const Duration(milliseconds: 2800);
    } else if (isInfo) {
      bg = AppColors.primary;
      iconColor = Colors.white;
      iconData = Icons.info_outline_rounded;
      effectiveDuration = duration ?? const Duration(milliseconds: 2200);
    } else {
      bg = isDark ? const Color(0xFF1E293B) : const Color(0xFF0F172A);
      iconColor = AppColors.income;
      iconData = Icons.check_circle_rounded;
      effectiveDuration = duration ?? const Duration(milliseconds: 2200);
    }

    // Xóa ngay SnackBar hiện tại và hàng đợi để không bị xếp chồng khi thao tác liên tiếp
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(iconData, color: iconColor, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: bg,
        elevation: 4,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: effectiveDuration,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../utils/constants.dart';

/// Bộ chọn tháng dùng cho các màn hình Ngân sách.
/// Hiển thị tháng ở giữa (một dòng, không ngắt chữ) kèm dòng chú thích tương đối
/// ("Tháng hiện tại", "Tháng trước"...). Mũi tên chuyển tháng là tùy chọn.
class BudgetMonthSelector extends StatelessWidget {
  final DateTime month;
  final VoidCallback onTap;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const BudgetMonthSelector({
    super.key,
    required this.month,
    required this.onTap,
    this.onPrevious,
    this.onNext,
  });

  String _caption() {
    final now = DateTime.now();
    final diff = (month.year - now.year) * 12 + (month.month - now.month);
    if (diff == 0) return 'Tháng hiện tại';
    if (diff == -1) return 'Tháng trước';
    if (diff == 1) return 'Tháng sau';
    return diff < 0 ? '${-diff} tháng trước' : '$diff tháng nữa';
  }

  @override
  Widget build(BuildContext context) {
    final isCurrent = _caption() == 'Tháng hiện tại';

    Widget arrow(IconData icon, VoidCallback? onPressed, String tooltip) {
      if (onPressed == null) return const SizedBox(width: 8);
      return IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon, color: context.appTextPrimary),
      );
    }

    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: context.appCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.appBorder),
      ),
      child: Row(
        children: [
          arrow(Icons.chevron_left_rounded, onPrevious, 'Tháng trước'),
          Expanded(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_month_rounded,
                            size: 18, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Tháng ${month.month}, ${month.year}',
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: context.appTextPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(Icons.expand_more_rounded,
                            size: 20, color: context.appTextSecondary),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _caption(),
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500,
                        color: isCurrent ? AppColors.primary : context.appTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          arrow(Icons.chevron_right_rounded, onNext, 'Tháng sau'),
        ],
      ),
    );
  }
}

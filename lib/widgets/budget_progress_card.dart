import 'package:flutter/material.dart';
import 'package:percent_indicator/percent_indicator.dart';
import '../l10n/app_localizations.dart';
import '../models/budget_model.dart';
import '../models/category_model.dart';
import '../utils/category_localization_helper.dart';
import '../utils/constants.dart';
import '../utils/formatters.dart';
import 'app_card.dart';

/// Widget hiển thị hạn mức chi tiêu chi tiết theo danh mục chuẩn Fintech
class BudgetProgressCard extends StatelessWidget {
  final Budget budget;
  final double spentAmount;
  final Category? category;
  final VoidCallback? onTap;

  const BudgetProgressCard({
    super.key,
    required this.budget,
    required this.spentAmount,
    this.category,
    this.onTap,
  });

  IconData _getCategoryIcon(String? iconName) {
    switch (iconName) {
      case 'work':
        return Icons.work_outline_rounded;
      case 'card_giftcard':
        return Icons.card_giftcard_rounded;
      case 'storefront':
        return Icons.storefront_rounded;
      case 'restaurant':
        return Icons.restaurant_rounded;
      case 'shopping_bag':
        return Icons.shopping_bag_outlined;
      case 'local_gas_station':
        return Icons.local_gas_station_rounded;
      case 'school':
        return Icons.school_outlined;
      case 'movie':
        return Icons.movie_outlined;
      case 'flight':
        return Icons.flight_takeoff_rounded;
      case 'local_hospital':
        return Icons.local_hospital_outlined;
      default:
        return Icons.receipt_long_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOver = budget.isOverBudget(spentAmount);
    final isNear = budget.isNearLimit(spentAmount);
    final percent = budget.percentUsed(spentAmount);
    final remaining = budget.remaining(spentAmount);

    final Color statusColor = isOver
        ? AppColors.expense
        : isNear
            ? AppColors.warning
            : AppColors.income;

    final String statusLabel = isOver
        ? context.tr('budget_card_over')
        : isNear
            ? context.tr('budget_card_near')
            : context.tr('budget_card_safe');

    final Color cardBorderColor = isOver
        ? AppColors.expense.withAlpha(100)
        : isNear
            ? AppColors.warning.withAlpha(100)
            : context.appBorder;

    final Color catColor = category != null ? Color(category!.color) : AppColors.slate500;

    return AppCard(
      onTap: onTap,
      borderColor: cardBorderColor,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: catColor.withAlpha(context.isDarkMode ? 50 : 30),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(_getCategoryIcon(category?.icon), color: catColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            category != null
                                ? CategoryLocalizationHelper
                                    .localizeNameWithContext(
                                        context, category!.name)
                                : context.tr('budget_card_default_category'),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: category != null
                                  ? context.appTextPrimary
                                  : context.appTextSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (category == null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.expenseBackground,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              context.tr('budget_card_deleted'),
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.expense,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      context.tr(
                        'budget_card_limit',
                        params: {
                          'amount': AppFormatters.compactCurrency(
                            budget.limit,
                            unit: '₫',
                          ),
                        },
                      ),
                      style: TextStyle(fontSize: 12, color: context.appTextSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 135),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withAlpha(context.isDarkMode ? 45 : 26),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      statusLabel,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    AppFormatters.compactCurrency(spentAmount, unit: '₫'),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: context.appTextPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${(percent * 100).round()}%',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearPercentIndicator(
            lineHeight: 8,
            percent: percent.clamp(0.0, 1.0),
            backgroundColor: context.appInputFill,
            progressColor: statusColor,
            barRadius: const Radius.circular(4),
            padding: EdgeInsets.zero,
            animation: true,
            animationDuration: 600,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                isOver
                    ? Icons.warning_amber_rounded
                    : isNear
                        ? Icons.error_outline_rounded
                        : Icons.check_circle_outline_rounded,
                size: 15,
                color: statusColor,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  isOver
                      ? context.tr(
                          'budget_card_over_by',
                          params: {
                            'amount': AppFormatters.compactCurrency(
                              spentAmount - budget.limit,
                              unit: '₫',
                            ),
                          },
                        )
                      : context.tr(
                          'budget_card_remaining',
                          params: {
                            'amount': AppFormatters.compactCurrency(
                              remaining,
                              unit: '₫',
                            ),
                          },
                        ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isOver ? AppColors.expense : context.appTextSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

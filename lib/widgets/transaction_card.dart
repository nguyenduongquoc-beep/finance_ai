import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/category_model.dart';
import '../models/saving_goal_model.dart';
import '../models/transaction_model.dart';
import '../models/wallet_model.dart';
import '../utils/category_localization_helper.dart';
import '../utils/constants.dart';
import '../utils/formatters.dart';
import '../utils/transaction_note_localization_helper.dart';
import 'app_card.dart';

/// Widget hiển thị một dòng giao dịch trong danh sách chuẩn Fintech
class TransactionCard extends StatelessWidget {
  final AppTransaction transaction;
  final Category? category;
  final Wallet? wallet;
  final SavingGoal? goal;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry margin;

  const TransactionCard({
    super.key,
    required this.transaction,
    this.category,
    this.wallet,
    this.goal,
    this.onTap,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
    final isGoalDeposit = transaction.type == 'goal_deposit';
    final isGoalWithdraw = transaction.type == 'goal_withdraw';
    final isTransfer = transaction.type == 'transfer' || isGoalDeposit || isGoalWithdraw;
    final isIncome = transaction.type == 'income';
    final amountColor = isTransfer
        ? context.appTextPrimary
        : (isIncome ? AppColors.income : AppColors.expense);

    final localizedNote = TransactionNoteLocalizationHelper.localizeNoteWithContext(
      context,
      transaction,
      wallet: wallet,
      goal: goal,
    );
    final hasNote = localizedNote.trim().isNotEmpty;
    final categoryLabel = isGoalDeposit
        ? context.tr('tx_card_goal_deposit')
        : isGoalWithdraw
            ? context.tr('tx_card_goal_withdraw')
            : isTransfer
                ? context.tr('common_transfer')
                : (category != null
                    ? CategoryLocalizationHelper.localizeNameWithContext(
                        context, category!.name)
                    : context.tr('tx_card_unknown_category'));
    final titleText = hasNote ? localizedNote : categoryLabel;
    final subtitleText = hasNote ? categoryLabel : null;

    final iconColor = isTransfer
        ? context.appTextSecondary
        : (isIncome ? AppColors.income : AppColors.expense);

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      margin: margin,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: context.isDarkMode ? AppColors.slate700 : AppColors.slate100,
              borderRadius: BorderRadius.circular(AppColors.radiusControl),
            ),
            child: Icon(
              (isGoalDeposit || isGoalWithdraw)
                  ? Icons.savings_outlined
                  : (isTransfer ? Icons.swap_horiz_rounded : _getCategoryIcon(category?.icon)),
              color: iconColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  titleText,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: context.appTextPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitleText ?? AppFormatters.date(transaction.date),
                  style: TextStyle(
                    fontSize: 12,
                    color: context.appTextSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                isTransfer
                    ? AppFormatters.compactCurrency(transaction.amount, unit: '₫')
                    : '${isIncome ? '+' : '-'}${AppFormatters.compactCurrency(transaction.amount, unit: '₫')}',
                style: TextStyle(
                  color: amountColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

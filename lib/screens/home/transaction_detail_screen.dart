import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../l10n/app_localizations.dart';
import '../../models/saving_goal_model.dart';
import '../../models/transaction_model.dart';
import '../../models/wallet_model.dart';
import '../../services/firestore_service.dart';
import '../../utils/category_localization_helper.dart';
import '../../utils/constants.dart';
import '../../utils/formatters.dart';
import '../../utils/transaction_note_localization_helper.dart';
import '../../utils/wallet_localization_helper.dart';
import 'dart:io';
import 'add_transaction_screen.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_snackbar.dart';

/// 12. Chi tiết giao dịch - cho phép Sửa / Xóa / Xem ảnh đính kèm
class TransactionDetailScreen extends StatelessWidget {
  final AppTransaction transaction;

  const TransactionDetailScreen({super.key, required this.transaction});

  IconData getCategoryIcon(String? iconName, String type) {
    if (iconName == null) {
      return type == 'income' ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded;
    }
    switch (iconName) {
      case 'restaurant':
        return Icons.restaurant;
      case 'shopping_bag':
        return Icons.shopping_bag;
      case 'local_gas_station':
        return Icons.local_gas_station;
      case 'school':
        return Icons.school;
      case 'movie':
        return Icons.movie;
      case 'flight':
        return Icons.flight;
      case 'local_hospital':
        return Icons.local_hospital;
      case 'work':
        return Icons.work;
      case 'card_giftcard':
        return Icons.card_giftcard;
      case 'storefront':
        return Icons.storefront;
      default:
        return Icons.category;
    }
  }

  String getFormattedDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final txDate = DateTime(date.year, date.month, date.day);
    final dateStr = DateFormat('dd/MM/yyyy').format(date);
    if (txDate == today) {
      return AppLocalizations.tr('tx_detail_today', params: {'date': dateStr});
    } else if (txDate == yesterday) {
      return AppLocalizations.tr('tx_detail_yesterday',
          params: {'date': dateStr});
    } else {
      return dateStr;
    }
  }

  Future<Map<String, dynamic>> _loadDetails() async {
    final hasWallet = transaction.walletId.isNotEmpty;
    final hasCategory = transaction.categoryId.isNotEmpty;
    final isTransfer = transaction.type == 'transfer' &&
        transaction.toWalletId != null &&
        transaction.toWalletId!.isNotEmpty;
    final isGoalTx = (transaction.type == 'goal_deposit' ||
            transaction.type == 'goal_withdraw') &&
        transaction.goalId != null &&
        transaction.goalId!.isNotEmpty;

    DocumentSnapshot? walletDoc;
    DocumentSnapshot? categoryDoc;
    DocumentSnapshot? toWalletDoc;
    DocumentSnapshot? goalDoc;

    try {
      final results = await Future.wait([
        hasWallet
            ? FirebaseFirestore.instance
                .collection('wallets')
                .doc(transaction.walletId)
                .get()
            : Future.value(null),
        hasCategory
            ? FirebaseFirestore.instance
                .collection('categories')
                .doc(transaction.categoryId)
                .get()
            : Future.value(null),
        isTransfer
            ? FirebaseFirestore.instance
                .collection('wallets')
                .doc(transaction.toWalletId!)
                .get()
            : Future.value(null),
        isGoalTx
            ? FirebaseFirestore.instance
                .collection('savingGoals')
                .doc(transaction.goalId!)
                .get()
            : Future.value(null),
      ]);

      walletDoc = results[0];
      categoryDoc = results[1];
      toWalletDoc = results[2];
      goalDoc = results[3];
    } catch (e) {
      debugPrint('❌ Error loading transaction details: $e');
    }

    final walletObj = (walletDoc != null && walletDoc.exists)
        ? Wallet.fromMap(
            walletDoc.data() as Map<String, dynamic>, walletDoc.id)
        : null;
    final toWalletObj = (toWalletDoc != null && toWalletDoc.exists)
        ? Wallet.fromMap(
            toWalletDoc.data() as Map<String, dynamic>, toWalletDoc.id)
        : null;
    final goalObj = (goalDoc != null && goalDoc.exists)
        ? SavingGoal.fromMap(
            goalDoc.data() as Map<String, dynamic>, goalDoc.id)
        : null;

    String? goalName = goalObj?.name;

    if ((goalName == null || goalName.isEmpty) && transaction.note != null) {
      final note = transaction.note!;
      if (note.contains(': ')) {
        goalName = note.split(': ').last;
      }
    }

    final unknownLabel = AppLocalizations.tr('tx_detail_unknown');
    return {
      'walletObj': walletObj,
      'toWalletObj': toWalletObj,
      'goalObj': goalObj,
      'walletName': walletObj?.walletName ?? unknownLabel,
      'categoryName': (categoryDoc != null && categoryDoc.exists)
          ? ((categoryDoc.data() as Map<String, dynamic>?)?['name'] ??
              unknownLabel)
          : unknownLabel,
      'categoryColor': (categoryDoc != null && categoryDoc.exists)
          ? ((categoryDoc.data() as Map<String, dynamic>?)?['color'] as int?)
          : null,
      'categoryIcon': (categoryDoc != null && categoryDoc.exists)
          ? ((categoryDoc.data() as Map<String, dynamic>?)?['icon'] as String?)
          : null,
      'toWalletName': toWalletObj?.walletName,
      'goalName': goalName ?? unknownLabel,
    };
  }

  @override
  Widget build(BuildContext context) {
    final firestoreService = FirestoreService();
    final isGoalDeposit = transaction.type == 'goal_deposit';
    final isGoalWithdraw = transaction.type == 'goal_withdraw';
    final isGoalTx = isGoalDeposit || isGoalWithdraw;
    final isTransfer = transaction.type == 'transfer' || isGoalTx;
    final isIncome = transaction.type == 'income';
    final color = isTransfer
        ? AppColors.info
        : (isIncome ? AppColors.income : AppColors.expense);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(context.tr('tx_detail_title')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _loadDetails(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final details = snapshot.data ?? {};
          final unknown = context.tr('tx_detail_unknown');
          final walletObj = details['walletObj'] as Wallet?;
          final toWalletObj = details['toWalletObj'] as Wallet?;
          final goalObj = details['goalObj'] as SavingGoal?;
          final walletName = walletObj != null
              ? WalletLocalizationHelper.localizeWalletWithContext(
                  context, walletObj)
              : (details['walletName'] as String? ?? unknown);
          final rawCategoryName = details['categoryName'] ?? unknown;
          final categoryName = rawCategoryName == unknown
              ? unknown
              : CategoryLocalizationHelper.localizeNameWithContext(
                  context, rawCategoryName);
          final categoryIcon = details['categoryIcon'];
          final toWalletName = toWalletObj != null
              ? WalletLocalizationHelper.localizeWalletWithContext(
                  context, toWalletObj)
              : details['toWalletName'];
          final goalName = details['goalName'];
          final localizedNote =
              TransactionNoteLocalizationHelper.localizeNoteWithContext(
            context,
            transaction,
            wallet: walletObj,
            goal: goalObj,
          );

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isGoalTx
                              ? Icons.savings_rounded
                              : (transaction.type == 'transfer'
                                  ? Icons.swap_horiz_rounded
                                  : getCategoryIcon(
                                      categoryIcon, transaction.type)),
                          color: color,
                          size: 34,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        isGoalDeposit
                            ? context.tr('tx_detail_amount_deposit')
                            : (isGoalWithdraw
                                ? context.tr('tx_detail_amount_withdraw')
                                : (transaction.type == 'transfer'
                                    ? context.tr('tx_detail_amount_transfer')
                                    : (isIncome
                                        ? context.tr('tx_detail_amount_income')
                                        : context.tr(
                                            'tx_detail_amount_expense')))),
                        style: TextStyle(
                          color: context.appTextSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Builder(
                        builder: (context) {
                          final isHuge = transaction.amount.abs() >= 1e9;
                          final amountStr = isTransfer
                              ? (isHuge
                                  ? AppFormatters.compactCurrency(
                                      transaction.amount,
                                      unit: context.tr('common_vnd_label'))
                                  : AppFormatters.currency(transaction.amount))
                              : '${isIncome ? '+' : '-'}${isHuge ? AppFormatters.compactCurrency(transaction.amount, unit: context.tr('common_vnd_label')) : AppFormatters.currency(transaction.amount)}';
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  amountStr,
                                  style: TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w600,
                                    color: color,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                              ),
                              if (isHuge) ...[
                                const SizedBox(height: 4),
                                Text(
                                  context.tr(
                                    'tx_detail_exact',
                                    params: {
                                      'amount': AppFormatters.currency(
                                          transaction.amount),
                                    },
                                  ),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: context.appTextSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isGoalDeposit
                              ? context.tr('tx_detail_badge_deposit')
                              : (isGoalWithdraw
                                  ? context.tr('tx_detail_badge_withdraw')
                                  : (transaction.type == 'transfer'
                                      ? context.tr('tx_detail_badge_transfer')
                                      : (isIncome
                                          ? context.tr('common_income')
                                          : context.tr('common_expense')))),
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isGoalTx) ...[
                        _buildDetailRow(
                            context, context.tr('tx_detail_wallet'), walletName),
                        Divider(
                            height: 24,
                            thickness: 0.5,
                            color: context.appBorder),
                        _buildDetailRow(
                            context,
                            context.tr('tx_detail_goal'),
                            goalName ?? context.tr('tx_detail_unknown')),
                        Divider(
                            height: 24,
                            thickness: 0.5,
                            color: context.appBorder),
                      ] else if (transaction.type == 'transfer') ...[
                        _buildDetailRow(context,
                            context.tr('tx_detail_from_wallet'), walletName),
                        Divider(
                            height: 24,
                            thickness: 0.5,
                            color: context.appBorder),
                        _buildDetailRow(
                            context,
                            context.tr('tx_detail_to_wallet'),
                            toWalletName ?? context.tr('tx_detail_unknown')),
                        Divider(
                            height: 24,
                            thickness: 0.5,
                            color: context.appBorder),
                      ] else ...[
                        _buildDetailRow(context,
                            context.tr('tx_detail_category'), categoryName),
                        Divider(
                            height: 24,
                            thickness: 0.5,
                            color: context.appBorder),
                        _buildDetailRow(
                            context,
                            context.tr('tx_detail_payment_wallet'),
                            walletName),
                        Divider(
                            height: 24,
                            thickness: 0.5,
                            color: context.appBorder),
                      ],
                      _buildDetailRow(context, context.tr('tx_detail_time'),
                          getFormattedDate(transaction.date)),
                      if (localizedNote.isNotEmpty) ...[
                        Divider(
                            height: 24,
                            thickness: 0.5,
                            color: context.appBorder),
                        Text(
                          context.tr('tx_detail_note'),
                          style: TextStyle(
                            color: context.appTextSecondary,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          localizedNote,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: context.appTextPrimary,
                            fontSize: 15,
                          ),
                        ),
                      ],
                      if (transaction.location != null &&
                          transaction.location!.isNotEmpty) ...[
                        Divider(
                            height: 24,
                            thickness: 0.5,
                            color: context.appBorder),
                        Text(
                          context.tr('tx_detail_location'),
                          style: TextStyle(
                            color: context.appTextSecondary,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          transaction.location!,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: context.appTextPrimary,
                            fontSize: 15,
                          ),
                        ),
                      ],
                      if (transaction.image != null &&
                          transaction.image!.isNotEmpty) ...[
                        Divider(
                            height: 24,
                            thickness: 0.5,
                            color: context.appBorder),
                        Text(
                          context.tr('tx_detail_receipt'),
                          style: TextStyle(
                            color: context.appTextSecondary,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => FullscreenImageScreen(
                                    imagePath: transaction.image!),
                              ),
                            );
                          },
                          child: Container(
                            constraints: const BoxConstraints(
                              maxHeight: 250,
                            ),
                            width: double.infinity,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(
                                File(transaction.image!),
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) =>
                                    Container(
                                  height: 180,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: context.appInputFill,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Center(
                                    child: Icon(
                                      Icons.broken_image_outlined,
                                      color: context.appTextSecondary,
                                      size: 40,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: AppOutlinedButton(
                  text: context.tr('common_delete'),
                  icon: Icons.delete_outline_rounded,
                  textColor: AppColors.expense,
                  borderColor: AppColors.expense.withValues(alpha: 0.5),
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(context.tr('tx_detail_delete_title')),
                        content: Text(
                          isGoalTx
                              ? context.tr('tx_detail_delete_goal_msg')
                              : context.tr('tx_detail_delete_msg'),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text(context.tr('common_cancel')),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: Text(
                              context.tr('common_delete'),
                              style: const TextStyle(color: AppColors.expense),
                            ),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      try {
                        await firestoreService.deleteTransaction(transaction);
                        if (context.mounted) Navigator.of(context).pop();
                      } catch (e) {
                        if (context.mounted) {
                          final errorMsg =
                              e.toString().replaceFirst('Exception: ', '');
                          AppSnackbar.show(context, errorMsg, isError: true);
                        }
                      }
                    }
                  },
                ),
              ),
              if (!isGoalTx) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    text: context.tr('common_edit'),
                    icon: Icons.edit_outlined,
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AddTransactionScreen(
                              transactionToEdit: transaction),
                        ),
                      );
                      if (result == true) {
                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }
                      }
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: TextStyle(
              color: context.appTextSecondary,
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: context.appTextPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class FullscreenImageScreen extends StatelessWidget {
  final String imagePath;
  const FullscreenImageScreen({super.key, required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(context.tr('tx_detail_receipt'),
            style: const TextStyle(color: Colors.white)),
      ),
      body: Center(
        child: InteractiveViewer(
          panEnabled: true,
          boundaryMargin: const EdgeInsets.all(20),
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.file(
            File(imagePath),
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => const Center(
              child: Icon(Icons.broken_image_outlined,
                  color: Colors.white54, size: 64),
            ),
          ),
        ),
      ),
    );
  }
}

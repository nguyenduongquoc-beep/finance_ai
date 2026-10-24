import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../models/transaction_model.dart';
import '../../services/firestore_service.dart';
import '../../utils/constants.dart';
import '../../utils/formatters.dart';
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
      return type == 'income' ? Icons.arrow_downward : Icons.arrow_upward;
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
      return 'Hôm nay, $dateStr';
    } else if (txDate == yesterday) {
      return 'Hôm qua, $dateStr';
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

    String? goalName = (goalDoc != null && goalDoc.exists)
        ? ((goalDoc.data() as Map<String, dynamic>?)?['name'] as String?)
        : null;

    if ((goalName == null || goalName.isEmpty) && transaction.note != null) {
      final note = transaction.note!;
      if (note.contains(': ')) {
        goalName = note.split(': ').last;
      }
    }

    return {
      'walletName': (walletDoc != null && walletDoc.exists)
          ? ((walletDoc.data() as Map<String, dynamic>?)?['walletName'] ??
              'Không rõ')
          : 'Không rõ',
      'categoryName': (categoryDoc != null && categoryDoc.exists)
          ? ((categoryDoc.data() as Map<String, dynamic>?)?['name'] ??
              'Không rõ')
          : 'Không rõ',
      'categoryColor': (categoryDoc != null && categoryDoc.exists)
          ? ((categoryDoc.data() as Map<String, dynamic>?)?['color'] as int?)
          : null,
      'categoryIcon': (categoryDoc != null && categoryDoc.exists)
          ? ((categoryDoc.data() as Map<String, dynamic>?)?['icon'] as String?)
          : null,
      'toWalletName': (toWalletDoc != null && toWalletDoc.exists)
          ? ((toWalletDoc.data() as Map<String, dynamic>?)?['walletName'] ??
              'Không rõ')
          : null,
      'goalName': goalName ?? 'Không rõ',
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
        title: const Text('Chi tiết giao dịch'),
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
          final walletName = details['walletName'] ?? 'Không rõ';
          final categoryName = details['categoryName'] ?? 'Không rõ';
          final categoryIcon = details['categoryIcon'];
          final toWalletName = details['toWalletName'];
          final goalName = details['goalName'];

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
                            ? 'Số tiền đã nạp'
                            : (isGoalWithdraw
                                ? 'Số tiền đã rút'
                                : (transaction.type == 'transfer'
                                    ? 'Số tiền đã chuyển'
                                    : (isIncome
                                        ? 'Số tiền đã thu'
                                        : 'Số tiền đã chi'))),
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
                                      unit: 'VNĐ')
                                  : AppFormatters.currency(transaction.amount))
                              : '${isIncome ? '+' : '-'}${isHuge ? AppFormatters.compactCurrency(transaction.amount, unit: 'VNĐ') : AppFormatters.currency(transaction.amount)}';
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
                                  'Chính xác: ${AppFormatters.currency(transaction.amount)}',
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
                              ? 'Nạp tiết kiệm'
                              : (isGoalWithdraw
                                  ? 'Rút tiết kiệm'
                                  : (transaction.type == 'transfer'
                                      ? 'Chuyển tiền'
                                      : (isIncome ? 'Thu nhập' : 'Chi tiêu'))),
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
                        _buildDetailRow(context, 'Ví', walletName),
                        Divider(
                            height: 24,
                            thickness: 0.5,
                            color: context.appBorder),
                        _buildDetailRow(context, 'Mục tiêu tiết kiệm',
                            goalName ?? 'Không rõ'),
                        Divider(
                            height: 24,
                            thickness: 0.5,
                            color: context.appBorder),
                      ] else if (transaction.type == 'transfer') ...[
                        _buildDetailRow(context, 'Từ ví', walletName),
                        Divider(
                            height: 24,
                            thickness: 0.5,
                            color: context.appBorder),
                        _buildDetailRow(
                            context, 'Đến ví', toWalletName ?? 'Không rõ'),
                        Divider(
                            height: 24,
                            thickness: 0.5,
                            color: context.appBorder),
                      ] else ...[
                        _buildDetailRow(context, 'Danh mục', categoryName),
                        Divider(
                            height: 24,
                            thickness: 0.5,
                            color: context.appBorder),
                        _buildDetailRow(context, 'Ví thanh toán', walletName),
                        Divider(
                            height: 24,
                            thickness: 0.5,
                            color: context.appBorder),
                      ],
                      _buildDetailRow(context, 'Thời gian',
                          getFormattedDate(transaction.date)),
                      if (transaction.note != null &&
                          transaction.note!.isNotEmpty) ...[
                        Divider(
                            height: 24,
                            thickness: 0.5,
                            color: context.appBorder),
                        Text(
                          'Ghi chú',
                          style: TextStyle(
                            color: context.appTextSecondary,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          transaction.note!,
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
                          'Địa điểm',
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
                          'Ảnh hóa đơn',
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
                  text: 'Xóa',
                  icon: Icons.delete_outline_rounded,
                  textColor: AppColors.expense,
                  borderColor: AppColors.expense.withValues(alpha: 0.5),
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Xóa giao dịch?'),
                        content: Text(
                          isGoalTx
                              ? 'Xóa giao dịch này sẽ hoàn tác cả số dư ví lẫn tiến độ mục tiêu tiết kiệm liên quan.'
                              : 'Hành động này không thể hoàn tác.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Hủy'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text(
                              'Xóa',
                              style: TextStyle(color: AppColors.expense),
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
                    text: 'Sửa',
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
      children: [
        Text(
          label,
          style: TextStyle(
            color: context.appTextSecondary,
            fontSize: 14,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: context.appTextPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
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
        title: const Text('Ảnh hóa đơn', style: TextStyle(color: Colors.white)),
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

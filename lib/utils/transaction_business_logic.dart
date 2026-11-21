import 'dart:math' as math;
import '../l10n/app_localizations.dart';
import '../models/transaction_model.dart';
import '../models/wallet_model.dart';
import '../models/saving_goal_model.dart';

/// Kết quả tính toán ảnh hưởng của giao dịch lên các ví và mục tiêu tiết kiệm
class TransactionEffects {
  final double? newSourceBalance;
  final double? newTargetBalance;
  final double? newGoalSavedAmount;
  final Map<String, GoalWalletSource>? newGoalWalletSources;
  final List<GoalDepositRecord>? newGoalDeposits;

  const TransactionEffects({
    this.newSourceBalance,
    this.newTargetBalance,
    this.newGoalSavedAmount,
    this.newGoalWalletSources,
    this.newGoalDeposits,
  });
}

/// Lớp xử lý nghiệp vụ tài chính thuần Dart (Pure Logic)
/// Giúp đảm bảo tính nhất quán số dư, không cho số dư âm, chặn nạp tiền vượt mục tiêu,
/// quản lý chặt chẽ nguồn ví nạp/rút mục tiêu tiết kiệm,
/// và hỗ trợ unit test độc lập không phụ thuộc Firestore.
class TransactionBusinessLogic {
  /// Validate số tiền giao dịch hợp lệ (> 0, hữu hạn, không NaN)
  static void validateAmount(double amount) {
    if (amount <= 0 || amount.isNaN || !amount.isFinite) {
      throw Exception(AppLocalizations.tr('svc_tbl_invalid_amount'));
    }
  }

  /// Kiểm tra và tính toán ảnh hưởng khi tạo giao dịch mới
  static TransactionEffects processCreateTransaction({
    required AppTransaction tx,
    required Wallet wallet,
    Wallet? toWallet,
    SavingGoal? goal,
    String? transactionId,
  }) {
    validateAmount(tx.amount);

    if (!wallet.isActive) {
      throw Exception(AppLocalizations.tr('svc_tbl_wallet_inactive'));
    }

    switch (tx.type) {
      case 'income':
        return TransactionEffects(
          newSourceBalance: wallet.balance + tx.amount,
        );

      case 'expense':
        if (tx.amount > wallet.balance) {
          throw Exception(AppLocalizations.tr('svc_tbl_insufficient_bal'));
        }
        return TransactionEffects(
          newSourceBalance: wallet.balance - tx.amount,
        );

      case 'transfer':
        if (toWallet == null) {
          throw Exception(AppLocalizations.tr('svc_tbl_dst_missing'));
        }
        if (!toWallet.isActive) {
          throw Exception(AppLocalizations.tr('svc_tbl_dst_inactive'));
        }
        if (tx.walletId == tx.toWalletId) {
          throw Exception(AppLocalizations.tr('svc_tbl_same_wallet'));
        }
        if (tx.amount > wallet.balance) {
          throw Exception(AppLocalizations.tr('svc_tbl_insufficient_bal'));
        }
        return TransactionEffects(
          newSourceBalance: wallet.balance - tx.amount,
          newTargetBalance: toWallet.balance + tx.amount,
        );

      case 'goal_deposit':
        if (goal == null) {
          throw Exception(AppLocalizations.tr('svc_tbl_goal_missing'));
        }
        if (tx.amount > wallet.balance) {
          throw Exception(AppLocalizations.tr('svc_tbl_insufficient_bal'));
        }
        final remaining = goal.targetAmount - goal.savedAmount;
        if (tx.amount > remaining) {
          throw Exception(
              AppLocalizations.tr('svc_tbl_goal_dep_excess'));
        }

        final updatedSources =
            Map<String, GoalWalletSource>.from(goal.walletSources);
        final existingSource = updatedSources[tx.walletId];
        updatedSources[tx.walletId] = GoalWalletSource(
          walletId: tx.walletId,
          walletName: wallet.walletName,
          totalDeposited: (existingSource?.totalDeposited ?? 0.0) + tx.amount,
          withdrawableAmount:
              (existingSource?.withdrawableAmount ?? 0.0) + tx.amount,
          lastDepositedAt: tx.date,
        );

        final updatedDeposits = List<GoalDepositRecord>.from(goal.deposits);
        final resolvedId =
            (transactionId != null && transactionId.trim().isNotEmpty)
                ? transactionId.trim()
                : tx.transactionId;
        updatedDeposits.add(
          GoalDepositRecord(
            depositId: resolvedId,
            walletId: tx.walletId,
            walletName: wallet.walletName,
            depositedAmount: tx.amount,
            remainingAmount: tx.amount,
            createdAt: tx.date,
          ),
        );

        return TransactionEffects(
          newSourceBalance: wallet.balance - tx.amount,
          newGoalSavedAmount: goal.savedAmount + tx.amount,
          newGoalWalletSources: updatedSources,
          newGoalDeposits: updatedDeposits,
        );

      case 'goal_withdraw':
        if (goal == null) {
          throw Exception(AppLocalizations.tr('svc_tbl_goal_missing'));
        }
        if (tx.amount > goal.savedAmount) {
          throw Exception(
              AppLocalizations.tr('svc_tbl_goal_wdr_excess'));
        }

        Map<String, GoalWalletSource>? updatedSources;
        List<GoalDepositRecord>? updatedDeposits;

        if (goal.hasTrackedSources) {
          final source = goal.walletSources[tx.walletId];
          if (source == null || source.totalDeposited <= 0) {
            throw Exception(
              AppLocalizations.tr('svc_tbl_goal_wdr_never', params: {'wallet': wallet.walletName}),
            );
          }
          if (source.withdrawableAmount <= 0) {
            throw Exception(
              AppLocalizations.tr('svc_tbl_goal_wdr_depleted', params: {'wallet': wallet.walletName}),
            );
          }
          if (tx.amount > source.withdrawableAmount) {
            throw Exception(
              AppLocalizations.tr('svc_tbl_goal_wdr_over', params: {'wallet': wallet.walletName}),
            );
          }

          updatedSources =
              Map<String, GoalWalletSource>.from(goal.walletSources);
          updatedSources[tx.walletId] = source.copyWith(
            walletName: wallet.walletName.isNotEmpty
                ? wallet.walletName
                : source.walletName,
            withdrawableAmount: (source.withdrawableAmount - tx.amount)
                .clamp(0.0, double.infinity),
          );

          updatedDeposits = _deductFromDepositRecords(
            goal.deposits,
            walletId: tx.walletId,
            amountToDeduct: tx.amount,
          );
        }

        return TransactionEffects(
          newSourceBalance: wallet.balance + tx.amount,
          newGoalSavedAmount: goal.savedAmount - tx.amount,
          newGoalWalletSources: updatedSources,
          newGoalDeposits: updatedDeposits,
        );

      default:
        throw Exception(AppLocalizations.tr('svc_tbl_invalid_type'));
    }
  }

  /// Kiểm tra và tính toán ảnh hưởng khi xóa giao dịch
  /// (Không chặn nếu ví bị ẩn isActive == false để hỗ trợ đối soát lịch sử)
  static TransactionEffects processDeleteTransaction({
    required AppTransaction tx,
    Wallet? wallet,
    Wallet? toWallet,
    SavingGoal? goal,
  }) {
    validateAmount(tx.amount);

    switch (tx.type) {
      case 'income':
        final currentBal = wallet?.balance ?? 0;
        if (wallet != null && currentBal < tx.amount) {
          throw Exception(
              AppLocalizations.tr('svc_tbl_undo_inc'));
        }
        return TransactionEffects(
          newSourceBalance: currentBal - tx.amount,
        );

      case 'expense':
        final currentBal = wallet?.balance ?? 0;
        return TransactionEffects(
          newSourceBalance: currentBal + tx.amount,
        );

      case 'transfer':
        final currentSource = wallet?.balance ?? 0;
        final currentTarget = toWallet?.balance ?? 0;
        if (toWallet != null && currentTarget < tx.amount) {
          throw Exception(
              AppLocalizations.tr('svc_tbl_undo_trf'));
        }
        return TransactionEffects(
          newSourceBalance: currentSource + tx.amount,
          newTargetBalance: currentTarget - tx.amount,
        );

      case 'goal_deposit':
        final currentBal = wallet?.balance ?? 0;
        final currentSaved = goal?.savedAmount ?? 0;

        Map<String, GoalWalletSource>? updatedSources;
        List<GoalDepositRecord>? updatedDeposits;

        if (goal != null && goal.hasTrackedSources) {
          final source = goal.walletSources[tx.walletId];
          final availableWithdrawable = source?.withdrawableAmount ?? 0.0;
          if (tx.amount > availableWithdrawable || tx.amount > currentSaved) {
            throw Exception(
              AppLocalizations.tr('svc_tbl_del_goal_dep'),
            );
          }

          updatedSources =
              Map<String, GoalWalletSource>.from(goal.walletSources);
          if (source != null) {
            final newTotal = (source.totalDeposited - tx.amount)
                .clamp(0.0, double.infinity);
            final newWithdrawable = (source.withdrawableAmount - tx.amount)
                .clamp(0.0, double.infinity);
            if (newTotal <= 0 && newWithdrawable <= 0) {
              updatedSources.remove(tx.walletId);
            } else {
              updatedSources[tx.walletId] = source.copyWith(
                totalDeposited: newTotal,
                withdrawableAmount: newWithdrawable,
              );
            }
          }

          updatedDeposits = List<GoalDepositRecord>.from(goal.deposits);
          final exactIdx = updatedDeposits.indexWhere(
            (d) =>
                d.depositId == tx.transactionId &&
                d.walletId == tx.walletId &&
                d.remainingAmount >= tx.amount,
          );
          if (exactIdx != -1) {
            final rec = updatedDeposits[exactIdx];
            if (rec.depositedAmount <= tx.amount) {
              updatedDeposits.removeAt(exactIdx);
            } else {
              updatedDeposits[exactIdx] = rec.copyWith(
                depositedAmount: rec.depositedAmount - tx.amount,
                remainingAmount: rec.remainingAmount - tx.amount,
              );
            }
          } else {
            updatedDeposits = _deductFromDepositRecords(
              updatedDeposits,
              walletId: tx.walletId,
              amountToDeduct: tx.amount,
              alsoReduceDeposited: true,
            );
          }
        }

        return TransactionEffects(
          newSourceBalance: currentBal + tx.amount,
          newGoalSavedAmount:
              (currentSaved - tx.amount).clamp(0, double.infinity),
          newGoalWalletSources: updatedSources,
          newGoalDeposits: updatedDeposits,
        );

      case 'goal_withdraw':
        final currentBal = wallet?.balance ?? 0;
        if (wallet != null && currentBal < tx.amount) {
          throw Exception(
              AppLocalizations.tr('svc_tbl_undo_goal_wdr'));
        }
        final currentSaved = goal?.savedAmount ?? 0;
        final targetAmount = goal?.targetAmount ?? double.infinity;

        Map<String, GoalWalletSource>? updatedSources;
        List<GoalDepositRecord>? updatedDeposits;

        if (goal != null && goal.hasTrackedSources) {
          updatedSources =
              Map<String, GoalWalletSource>.from(goal.walletSources);
          final source = updatedSources[tx.walletId];
          final walletName =
              wallet?.walletName ?? source?.walletName ?? AppLocalizations.tr('svc_tbl_pay_wallet');
          final newWithdrawable =
              (source?.withdrawableAmount ?? 0.0) + tx.amount;
          final newTotalDeposited = math.max(
            source?.totalDeposited ?? 0.0,
            newWithdrawable,
          );
          updatedSources[tx.walletId] = GoalWalletSource(
            walletId: tx.walletId,
            walletName: walletName,
            totalDeposited: newTotalDeposited,
            withdrawableAmount: newWithdrawable,
            lastDepositedAt: source?.lastDepositedAt ?? tx.date,
          );

          updatedDeposits = _restoreToDepositRecords(
            goal.deposits,
            walletId: tx.walletId,
            walletName: walletName,
            amountToRestore: tx.amount,
            fallbackDate: tx.date,
          );
        }

        return TransactionEffects(
          newSourceBalance: currentBal - tx.amount,
          newGoalSavedAmount: (currentSaved + tx.amount).clamp(0, targetAmount),
          newGoalWalletSources: updatedSources,
          newGoalDeposits: updatedDeposits,
        );

      default:
        throw Exception(AppLocalizations.tr('svc_tbl_invalid_type'));
    }
  }

  /// Áp dụng kết quả TransactionEffects lên đối tượng SavingGoal (hữu ích cho chuỗi thao tác & test)
  static SavingGoal applyEffectsToGoal(
    SavingGoal goal,
    TransactionEffects effects,
  ) {
    return goal.copyWith(
      savedAmount: effects.newGoalSavedAmount ?? goal.savedAmount,
      walletSources: effects.newGoalWalletSources ?? goal.walletSources,
      deposits: effects.newGoalDeposits ?? goal.deposits,
      sourcesSynced: true,
    );
  }

  /// Khôi phục thông tin nguồn ví (`walletSources` và `deposits`) từ lịch sử giao dịch
  /// `goal_deposit` và `goal_withdraw` đã được xác thực trong cơ sở dữ liệu.
  /// Không tự ý suy đoán ví nguồn nếu không có lịch sử giao dịch.
  static SavingGoal reconstructGoalSources({
    required SavingGoal goal,
    required List<AppTransaction> goalTransactions,
    required Map<String, String> walletNamesById,
  }) {
    final relevantTxs = goalTransactions
        .where(
          (tx) =>
              tx.goalId == goal.goalId &&
              (tx.type == 'goal_deposit' || tx.type == 'goal_withdraw') &&
              tx.amount > 0,
        )
        .toList();

    // Sắp xếp theo thời gian tăng dần; nếu cùng thời điểm thì xử lý nạp trước rút sau
    relevantTxs.sort((a, b) {
      final cmp = a.date.compareTo(b.date);
      if (cmp != 0) return cmp;
      if (a.type == b.type) return 0;
      return a.type == 'goal_deposit' ? -1 : 1;
    });

    final sources = <String, GoalWalletSource>{};
    var deposits = <GoalDepositRecord>[];

    for (final tx in relevantTxs) {
      final walletName = walletNamesById[tx.walletId] ?? AppLocalizations.tr('svc_tbl_linked_wallet');
      if (tx.type == 'goal_deposit') {
        final existing = sources[tx.walletId];
        sources[tx.walletId] = GoalWalletSource(
          walletId: tx.walletId,
          walletName: walletName,
          totalDeposited: (existing?.totalDeposited ?? 0.0) + tx.amount,
          withdrawableAmount: (existing?.withdrawableAmount ?? 0.0) + tx.amount,
          lastDepositedAt: tx.date,
        );
        deposits.add(
          GoalDepositRecord(
            depositId: tx.transactionId,
            walletId: tx.walletId,
            walletName: walletName,
            depositedAmount: tx.amount,
            remainingAmount: tx.amount,
            createdAt: tx.date,
          ),
        );
      } else if (tx.type == 'goal_withdraw') {
        var remainingToDeduct = tx.amount;
        final existing = sources[tx.walletId];
        if (existing != null && existing.withdrawableAmount > 0) {
          final deductFromSame =
              math.min(existing.withdrawableAmount, remainingToDeduct);
          sources[tx.walletId] = existing.copyWith(
            withdrawableAmount:
                (existing.withdrawableAmount - deductFromSame)
                    .clamp(0.0, double.infinity),
          );
          deposits = _deductFromDepositRecords(
            deposits,
            walletId: tx.walletId,
            amountToDeduct: deductFromSame,
          );
          remainingToDeduct -= deductFromSame;
        }

        // Trường hợp dữ liệu lịch sử cũ từng rút sang ví khác, trừ dần FIFO trên các nguồn còn lại
        if (remainingToDeduct > 0) {
          for (var i = 0; i < deposits.length && remainingToDeduct > 0; i++) {
            final rec = deposits[i];
            if (rec.remainingAmount <= 0) continue;
            final cut = math.min(rec.remainingAmount, remainingToDeduct);
            deposits[i] = rec.copyWith(
              remainingAmount:
                  (rec.remainingAmount - cut).clamp(0.0, rec.depositedAmount),
            );
            final src = sources[rec.walletId];
            if (src != null) {
              sources[rec.walletId] = src.copyWith(
                withdrawableAmount:
                    (src.withdrawableAmount - cut).clamp(0.0, double.infinity),
              );
            }
            remainingToDeduct -= cut;
          }
        }
      }
    }

    // Đảm bảo tổng có thể rút không vượt quá savedAmount thực tế hiện tại của mục tiêu
    final totalWithdrawable = sources.values
        .fold<double>(0.0, (sum, item) => sum + item.withdrawableAmount);
    if (totalWithdrawable > goal.savedAmount) {
      var excess = totalWithdrawable - goal.savedAmount;
      for (var i = 0; i < deposits.length && excess > 0; i++) {
        final rec = deposits[i];
        if (rec.remainingAmount <= 0) continue;
        final cut = math.min(rec.remainingAmount, excess);
        deposits[i] = rec.copyWith(
          remainingAmount:
              (rec.remainingAmount - cut).clamp(0.0, rec.depositedAmount),
        );
        final src = sources[rec.walletId];
        if (src != null) {
          sources[rec.walletId] = src.copyWith(
            withdrawableAmount:
                (src.withdrawableAmount - cut).clamp(0.0, double.infinity),
          );
        }
        excess -= cut;
      }
    }

    return goal.copyWith(
      walletSources: sources,
      deposits: deposits,
      sourcesSynced: true,
    );
  }

  static List<GoalDepositRecord> _deductFromDepositRecords(
    List<GoalDepositRecord> records, {
    required String walletId,
    required double amountToDeduct,
    bool alsoReduceDeposited = false,
  }) {
    final result = List<GoalDepositRecord>.from(records);
    var remaining = amountToDeduct;
    for (var i = 0; i < result.length && remaining > 0; i++) {
      final rec = result[i];
      if (rec.walletId != walletId || rec.remainingAmount <= 0) continue;
      final deduct = math.min(rec.remainingAmount, remaining);
      final newRemaining =
          (rec.remainingAmount - deduct).clamp(0.0, rec.depositedAmount);
      final newDeposited = alsoReduceDeposited
          ? (rec.depositedAmount - deduct).clamp(0.0, double.infinity)
          : rec.depositedAmount;
      result[i] = rec.copyWith(
        depositedAmount: newDeposited,
        remainingAmount: newRemaining.clamp(0.0, newDeposited),
      );
      remaining -= deduct;
    }
    if (alsoReduceDeposited) {
      result.removeWhere((r) => r.depositedAmount <= 0);
    }
    return result;
  }

  static List<GoalDepositRecord> _restoreToDepositRecords(
    List<GoalDepositRecord> records, {
    required String walletId,
    required String walletName,
    required double amountToRestore,
    required DateTime fallbackDate,
  }) {
    final result = List<GoalDepositRecord>.from(records);
    var remaining = amountToRestore;
    for (var i = result.length - 1; i >= 0 && remaining > 0; i--) {
      final rec = result[i];
      if (rec.walletId != walletId) continue;
      final capacity =
          (rec.depositedAmount - rec.remainingAmount).clamp(0.0, double.infinity);
      if (capacity <= 0) continue;
      final addBack = math.min(capacity, remaining);
      result[i] = rec.copyWith(
        remainingAmount: rec.remainingAmount + addBack,
      );
      remaining -= addBack;
    }
    if (remaining > 0) {
      result.add(
        GoalDepositRecord(
          depositId: 'restored_${fallbackDate.millisecondsSinceEpoch}',
          walletId: walletId,
          walletName: walletName,
          depositedAmount: remaining,
          remainingAmount: remaining,
          createdAt: fallbackDate,
        ),
      );
    }
    return result;
  }


  /// Kiểm tra và tính toán ảnh hưởng khi sửa giao dịch an toàn
  /// Khóa sửa goal_deposit và goal_withdraw
  static Map<String, double> processUpdateTransaction({
    required AppTransaction oldTx,
    required AppTransaction newTx,
    required Wallet oldWallet,
    required Wallet newWallet,
    Wallet? oldToWallet,
    Wallet? newToWallet,
  }) {
    if (oldTx.type == 'goal_deposit' ||
        oldTx.type == 'goal_withdraw' ||
        newTx.type == 'goal_deposit' ||
        newTx.type == 'goal_withdraw') {
      throw Exception(
          AppLocalizations.tr('svc_tbl_edit_goal_blocked'));
    }

    validateAmount(newTx.amount);

    // Kiểm tra ví chuyển tiền
    if (newTx.type == 'transfer') {
      if (newTx.toWalletId == null || newTx.toWalletId!.isEmpty) {
        throw Exception(AppLocalizations.tr('svc_tbl_trf_need_dst'));
      }
      if (newTx.walletId == newTx.toWalletId) {
        throw Exception(AppLocalizations.tr('svc_tbl_same_wallet'));
      }
    }

    // Kiểm tra ví mới isActive nếu đổi ví
    if (newTx.walletId != oldTx.walletId && !newWallet.isActive) {
      throw Exception(AppLocalizations.tr('svc_tbl_wallet_inactive'));
    }
    if (newTx.type == 'transfer') {
      if (newToWallet == null) {
        throw Exception(AppLocalizations.tr('svc_tbl_dst_missing'));
      }
      final isNewToWallet =
          oldTx.type != 'transfer' || newTx.toWalletId != oldTx.toWalletId;
      if (isNewToWallet && !newToWallet.isActive) {
        throw Exception(AppLocalizations.tr('svc_tbl_dst_inactive'));
      }
    }

    // Tính toán số dư mới cho các ví liên quan
    final balanceMap = <String, double>{};

    // Khởi tạo số dư hiện tại từ đối tượng ví
    balanceMap[oldWallet.walletId] = oldWallet.balance;
    balanceMap[newWallet.walletId] = newWallet.balance;
    if (oldToWallet != null) {
      balanceMap[oldToWallet.walletId] = oldToWallet.balance;
    }
    if (newToWallet != null) {
      balanceMap[newToWallet.walletId] = newToWallet.balance;
    }

    // 1. Hoàn tác oldTx
    switch (oldTx.type) {
      case 'expense':
        balanceMap[oldTx.walletId] =
            (balanceMap[oldTx.walletId] ?? 0) + oldTx.amount;
        break;
      case 'income':
        balanceMap[oldTx.walletId] =
            (balanceMap[oldTx.walletId] ?? 0) - oldTx.amount;
        break;
      case 'transfer':
        balanceMap[oldTx.walletId] =
            (balanceMap[oldTx.walletId] ?? 0) + oldTx.amount;
        if (oldTx.toWalletId != null) {
          balanceMap[oldTx.toWalletId!] =
              (balanceMap[oldTx.toWalletId!] ?? 0) - oldTx.amount;
        }
        break;
    }

    // 2. Áp dụng newTx
    switch (newTx.type) {
      case 'expense':
        balanceMap[newTx.walletId] =
            (balanceMap[newTx.walletId] ?? 0) - newTx.amount;
        break;
      case 'income':
        balanceMap[newTx.walletId] =
            (balanceMap[newTx.walletId] ?? 0) + newTx.amount;
        break;
      case 'transfer':
        balanceMap[newTx.walletId] =
            (balanceMap[newTx.walletId] ?? 0) - newTx.amount;
        if (newTx.toWalletId != null) {
          balanceMap[newTx.toWalletId!] =
              (balanceMap[newTx.toWalletId!] ?? 0) + newTx.amount;
        }
        break;
    }

    // 3. Kiểm tra không ví nào bị âm số dư
    balanceMap.forEach((walletId, balance) {
      if (balance < 0) {
        throw Exception(AppLocalizations.tr('svc_tbl_insufficient_bal'));
      }
    });

    return balanceMap;
  }
}

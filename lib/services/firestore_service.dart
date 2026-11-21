import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:intl/intl.dart';
import '../models/user_model.dart';
import '../models/wallet_model.dart';
import '../models/category_model.dart';
import '../models/transaction_model.dart';
import '../models/budget_model.dart';
import '../models/saving_goal_model.dart';
import '../models/notification_model.dart';
import '../models/recurring_transaction_model.dart';
import '../models/recurring_transaction_occurrence_model.dart';
import '../models/monthly_financial_plan.dart';
import '../models/admin_audit_log_model.dart';
import '../utils/formatters.dart';
import 'financial_context_revision_tracker.dart';
import 'local_notification_service.dart';
import 'recurring_transaction_service.dart';
import 'storage_service.dart';
import '../utils/category_localization_helper.dart';
import '../utils/transaction_business_logic.dart';
import '../utils/wallet_localization_helper.dart';
import '../l10n/app_localizations.dart';
import 'language_controller.dart';

/// Exception chuyên biệt khi ví không đủ số dư để xác nhận giao dịch chi
class InsufficientBalanceException implements Exception {
  final String message;
  final String walletName;
  final double currentBalance;
  final double requiredAmount;
  final double shortfall;

  InsufficientBalanceException({
    required this.message,
    required this.walletName,
    required this.currentBalance,
    required this.requiredAmount,
    required this.shortfall,
  });

  @override
  String toString() => message;
}

/// Exception khi truy vấn theo cửa sổ thời gian thiếu Composite Index trên Firestore.
/// Tuyệt đối không cắt cụt dữ liệu âm thầm bằng .limit(400) mà thông báo tường minh.
class FirestoreIndexRequiredException implements Exception {
  final String message;
  final String collection;

  const FirestoreIndexRequiredException({
    required this.message,
    required this.collection,
  });

  @override
  String toString() => message;
}

/// Exception khi phát hiện Ngân sách trên Firestore đã bị thay đổi trong lúc người dùng
/// đang xem trước Kế hoạch (Optimistic Concurrency Conflict).
class PlanBudgetConflictException implements Exception {
  final String message;
  final List<String> conflictingCategoryIds;
  final Map<String, double?> latestBudgetsByCategory;

  const PlanBudgetConflictException({
    required this.message,
    required this.conflictingCategoryIds,
    required this.latestBudgetsByCategory,
  });

  @override
  String toString() => message;
}

/// ============================================================
/// FIRESTORE SERVICE
/// CRUD cho tất cả collections: users, wallets, categories,
/// transactions, budgets, savingGoals, notifications
/// ============================================================
class FirestoreService {
  final FirebaseFirestore? _customDb;
  FirebaseFirestore get _db => _customDb ?? FirebaseFirestore.instance;
  FirebaseFirestore get firestoreInstance => _db;

  FirestoreService({FirebaseFirestore? firestore}) : _customDb = firestore;

  // ---------------- USERS ----------------
  Future<void> createUserProfile(AppUser user) {
    return _db.collection('users').doc(user.uid).set(user.toMap());
  }

  Future<AppUser?> getUserProfile(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return AppUser.fromMap(doc.data()!, doc.id);
  }

  Stream<AppUser?> streamUserProfile(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((doc) => doc.exists ? AppUser.fromMap(doc.data()!, doc.id) : null);
  }

  Future<void> updateUserProfile(String uid, Map<String, dynamic> data) async {
    await _db.collection('users').doc(uid).update(data);
    FinancialContextRevisionTracker.notifyDataMutated();
  }

  // ---------------- WALLETS ----------------
  Future<String> createWallet(Wallet wallet) async {
    final ref = await _db.collection('wallets').add(wallet.toMap());
    return ref.id;
  }

  Stream<List<Wallet>> streamWallets(String userId) {
    return _db
        .collection('wallets')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snap) {
      final list =
          snap.docs.map((d) => Wallet.fromMap(d.data(), d.id)).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  Future<void> updateWallet(String walletId, Map<String, dynamic> data) {
    return _db.collection('wallets').doc(walletId).update(data);
  }

  Future<void> deleteWallet(String walletId) {
    return _db.collection('wallets').doc(walletId).delete();
  }

  /// Ẩn hoặc khôi phục hiển thị 1 ví — dùng thay cho xóa cứng khi ví đã có
  /// giao dịch, để giữ nguyên lịch sử giao dịch cũ (xem RULES.md nguyên tắc Wallet).
  Future<void> setWalletActive(String walletId, bool isActive) {
    return _db.collection('wallets').doc(walletId).update({
      'isActive': isActive,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  Future<bool> checkWalletInUse(String userId, String walletId) async {
    final txQuery = await _db
        .collection('transactions')
        .where('userId', isEqualTo: userId)
        .where('walletId', isEqualTo: walletId)
        .limit(1)
        .get();
    return txQuery.docs.isNotEmpty;
  }

  Future<void> reassignAndDeleteWallet(
      String userId, String oldWalletId, String newWalletId) async {
    final oldWalletDoc = await _db.collection('wallets').doc(oldWalletId).get();
    if (!oldWalletDoc.exists) {
      throw Exception(AppLocalizations.tr('svc_fs_src_not_found'));
    }
    final oldBalance = (oldWalletDoc.data()!['balance'] as num).toDouble();
    final newWalletDoc = await _db.collection('wallets').doc(newWalletId).get();
    final newWalletName =
        newWalletDoc.data()?['walletName']?.toString() ?? AppLocalizations.tr('svc_tbl_pay_wallet');

    // Giao dịch mà ví này là ví thực hiện (walletId)
    final txQuery = await _db
        .collection('transactions')
        .where('userId', isEqualTo: userId)
        .where('walletId', isEqualTo: oldWalletId)
        .get();

    // Giao dịch chuyển tiền mà ví này là ví ĐÍCH (toWalletId)
    final transferToQuery = await _db
        .collection('transactions')
        .where('userId', isEqualTo: userId)
        .where('toWalletId', isEqualTo: oldWalletId)
        .get();

    // Cập nhật nguồn ví trong các mục tiêu tiết kiệm nếu có liên kết với ví cũ
    final goalsQuery = await _db
        .collection('savingGoals')
        .where('userId', isEqualTo: userId)
        .get();

    final batch = _db.batch();
    for (var doc in txQuery.docs) {
      batch.update(doc.reference, {'walletId': newWalletId});
    }
    for (var doc in transferToQuery.docs) {
      batch.update(doc.reference, {'toWalletId': newWalletId});
    }
    for (final goalDoc in goalsQuery.docs) {
      try {
        final goal = SavingGoal.fromMap(goalDoc.data(), goalDoc.id);
        final hasOldInSources = goal.walletSources.containsKey(oldWalletId);
        final hasOldInDeposits =
            goal.deposits.any((d) => d.walletId == oldWalletId);
        if (!hasOldInSources && !hasOldInDeposits) continue;

        final updatedSources =
            Map<String, GoalWalletSource>.from(goal.walletSources);
        final oldSource = updatedSources.remove(oldWalletId);
        if (oldSource != null) {
          final existingNew = updatedSources[newWalletId];
          updatedSources[newWalletId] = GoalWalletSource(
            walletId: newWalletId,
            walletName: newWalletName,
            totalDeposited: (existingNew?.totalDeposited ?? 0.0) +
                oldSource.totalDeposited,
            withdrawableAmount: (existingNew?.withdrawableAmount ?? 0.0) +
                oldSource.withdrawableAmount,
            lastDepositedAt:
                oldSource.lastDepositedAt ?? existingNew?.lastDepositedAt,
          );
        }

        final updatedDeposits = goal.deposits
            .map(
              (d) => d.walletId == oldWalletId
                  ? d.copyWith(
                      walletId: newWalletId,
                      walletName: newWalletName,
                    )
                  : d,
            )
            .toList();

        batch.update(goalDoc.reference, {
          'walletSources': {
            for (final entry in updatedSources.entries)
              entry.key: entry.value.toMap(),
          },
          'deposits': updatedDeposits.map((d) => d.toMap()).toList(),
        });
      } catch (_) {}
    }

    // QUAN TRỌNG: chuyển toàn bộ số dư ví cũ sang ví mới TRƯỚC khi xóa,
    // để tiền không biến mất khỏi tổng tài sản.
    if (oldBalance != 0) {
      batch.update(_db.collection('wallets').doc(newWalletId), {
        'balance': FieldValue.increment(oldBalance),
      });
    }

    batch.delete(_db.collection('wallets').doc(oldWalletId));
    await batch.commit();
  }

  /// Cập nhật số dư ví (dùng khi thêm/sửa/xóa giao dịch)
  Future<void> adjustWalletBalance(String walletId, double delta) {
    return _db.collection('wallets').doc(walletId).update({
      'balance': FieldValue.increment(delta),
    });
  }

  // ---------------- CATEGORIES ----------------
  Future<String> createCategory(Category category) async {
    final ref = await _db.collection('categories').add(category.toMap());
    FinancialContextRevisionTracker.notifyDataMutated();
    return ref.id;
  }

  Stream<List<Category>> streamCategories(String userId, {String? type}) {
    Query<Map<String, dynamic>> query =
        _db.collection('categories').where('userId', isEqualTo: userId);
    if (type != null) {
      query = query.where('type', isEqualTo: type);
    }
    return query.snapshots().map((snap) {
      final list =
          snap.docs.map((d) => Category.fromMap(d.data(), d.id)).toList();
      list.sort((a, b) => a.name.compareTo(b.name));
      return list;
    });
  }

  Future<void> updateCategory(String categoryId, Map<String, dynamic> data) async {
    data['updatedAt'] = DateTime.now().toIso8601String();
    await _db.collection('categories').doc(categoryId).update(data);
    FinancialContextRevisionTracker.notifyDataMutated();
  }

  Future<void> deleteCategory(String categoryId) async {
    await _db.collection('categories').doc(categoryId).delete();
    FinancialContextRevisionTracker.notifyDataMutated();
  }

  Future<bool> checkCategoryInUse(String userId, String categoryId) async {
    final txQuery = await _db
        .collection('transactions')
        .where('userId', isEqualTo: userId)
        .where('categoryId', isEqualTo: categoryId)
        .limit(1)
        .get();
    if (txQuery.docs.isNotEmpty) return true;
    final budgetQuery = await _db
        .collection('budgets')
        .where('userId', isEqualTo: userId)
        .where('categoryId', isEqualTo: categoryId)
        .limit(1)
        .get();
    return budgetQuery.docs.isNotEmpty;
  }

  Future<void> reassignAndDeleteCategory(
      String userId, String oldCategoryId, String newCategoryId) async {
    final txQuery = await _db
        .collection('transactions')
        .where('userId', isEqualTo: userId)
        .where('categoryId', isEqualTo: oldCategoryId)
        .get();
    final budgetQuery = await _db
        .collection('budgets')
        .where('userId', isEqualTo: userId)
        .where('categoryId', isEqualTo: oldCategoryId)
        .get();

    final batch = _db.batch();
    for (var doc in txQuery.docs) {
      batch.update(doc.reference, {'categoryId': newCategoryId});
    }
    for (var doc in budgetQuery.docs) {
      batch.update(doc.reference, {'categoryId': newCategoryId});
    }
    batch.delete(_db.collection('categories').doc(oldCategoryId));
    await batch.commit();
  }

  // ---------------- TRANSACTIONS ----------------
  Future<String> createTransaction(AppTransaction tx) async {
    TransactionBusinessLogic.validateAmount(tx.amount);

    final txRef = _db.collection('transactions').doc();
    final walletRef = _db.collection('wallets').doc(tx.walletId);
    DocumentReference? toWalletRef;

    if (tx.type == 'transfer') {
      if (tx.toWalletId == null || tx.toWalletId!.isEmpty) {
        throw Exception(AppLocalizations.tr('svc_tbl_trf_need_dst'));
      }
      if (tx.toWalletId == tx.walletId) {
        throw Exception(AppLocalizations.tr('svc_tbl_same_wallet'));
      }
      toWalletRef = _db.collection('wallets').doc(tx.toWalletId);
    }

    DocumentReference? goalRef;
    if (tx.type == 'goal_deposit' || tx.type == 'goal_withdraw') {
      if (tx.goalId == null || tx.goalId!.isEmpty) {
        throw Exception(AppLocalizations.tr('svc_fs_goal_need_id'));
      }
      goalRef = _db.collection('savingGoals').doc(tx.goalId);
      try {
        final preGoalSnap = await goalRef.get();
        if (preGoalSnap.exists && preGoalSnap.data() != null) {
          final preGoal = SavingGoal.fromMap(
            preGoalSnap.data() as Map<String, dynamic>,
            preGoalSnap.id,
          );
          if (preGoal.needsSourceSync) {
            await syncGoalWalletSourcesIfNeeded(preGoal);
          }
        }
      } catch (_) {}
    }

    DocumentReference? budgetRef;
    final monthStr = DateFormat('MM/yyyy').format(tx.date);
    if (tx.type == 'expense') {
      final budgetQuery = await _db
          .collection('budgets')
          .where('userId', isEqualTo: tx.userId)
          .where('categoryId', isEqualTo: tx.categoryId)
          .where('month', isEqualTo: monthStr)
          .limit(1)
          .get();
      if (budgetQuery.docs.isNotEmpty) {
        budgetRef = budgetQuery.docs.first.reference;
      }
    }

    await _db.runTransaction((transaction) async {
      final walletSnap = await transaction.get(walletRef);
      if (!walletSnap.exists) throw Exception(AppLocalizations.tr('svc_fs_wallet_not_found'));
      final wallet = Wallet.fromMap(
          walletSnap.data() as Map<String, dynamic>, walletSnap.id);

      Wallet? toWallet;
      if (toWalletRef != null) {
        final toWalletSnap = await transaction.get(toWalletRef);
        if (!toWalletSnap.exists) throw Exception(AppLocalizations.tr('svc_tbl_dst_missing'));
        toWallet = Wallet.fromMap(
            toWalletSnap.data() as Map<String, dynamic>, toWalletSnap.id);
      }

      SavingGoal? goal;
      if (goalRef != null) {
        final goalSnap = await transaction.get(goalRef);
        if (!goalSnap.exists) {
          throw Exception(AppLocalizations.tr('svc_tbl_goal_missing'));
        }
        goal = SavingGoal.fromMap(
            goalSnap.data() as Map<String, dynamic>, goalSnap.id);
      }

      final effects = TransactionBusinessLogic.processCreateTransaction(
        tx: tx,
        wallet: wallet,
        toWallet: toWallet,
        goal: goal,
        transactionId: txRef.id,
      );

      transaction.set(txRef, tx.toMap());

      if (effects.newSourceBalance != null) {
        transaction.update(walletRef, {'balance': effects.newSourceBalance});
      }
      if (effects.newTargetBalance != null && toWalletRef != null) {
        transaction.update(toWalletRef, {'balance': effects.newTargetBalance});
      }
      if (effects.newGoalSavedAmount != null && goalRef != null) {
        final goalUpdates = <String, dynamic>{
          'savedAmount': effects.newGoalSavedAmount,
          'sourcesSynced': true,
        };
        if (effects.newGoalWalletSources != null) {
          goalUpdates['walletSources'] = {
            for (final entry in effects.newGoalWalletSources!.entries)
              entry.key: entry.value.toMap(),
          };
        }
        if (effects.newGoalDeposits != null) {
          goalUpdates['deposits'] =
              effects.newGoalDeposits!.map((d) => d.toMap()).toList();
        }
        transaction.update(goalRef, goalUpdates);
      }
    });

    if (tx.type == 'expense' && budgetRef != null) {
      try {
        final updatedBudget = await budgetRef.get();
        final data = updatedBudget.data() as Map<String, dynamic>?;
        if (data != null) {
          final limit = (data['limit'] as num).toDouble();
          final newSpent = await getCategorySpentThisMonth(
              tx.userId, tx.categoryId,
              month: tx.date);
          final oldSpent = newSpent - tx.amount;
          if (limit > 0 && newSpent >= limit * 0.8 && oldSpent < limit * 0.8) {
            await createNotification(AppNotification(
              notificationId: '',
              userId: tx.userId,
              title: AppLocalizations.tr('svc_fs_bud_warn_title'),
              content:
                  AppLocalizations.tr('svc_fs_bud_warn_add', params: {'month': monthStr}),
              status: 'unread',
              type: 'budget',
              createdAt: DateTime.now(),
              titleKey: 'svc_fs_bud_warn_title',
              contentKey: 'svc_fs_bud_warn_add',
              contentParams: {'month': monthStr},
            ));
          }
        }
      } catch (_) {}
    }

    FinancialContextRevisionTracker.notifyDataMutated();
    return txRef.id;
  }

  Stream<List<AppTransaction>> streamTransactions(
    String userId, {
    DateTime? from,
    DateTime? to,
  }) {
    Query<Map<String, dynamic>> query =
        _db.collection('transactions').where('userId', isEqualTo: userId);

    if (from != null) {
      query =
          query.where('date', isGreaterThanOrEqualTo: from.toIso8601String());
    }
    if (to != null) {
      query = query.where('date', isLessThanOrEqualTo: to.toIso8601String());
    }

    // Sort by date descending (Requires Composite Index in Firestore)
    query = query.orderBy('date', descending: true);

    return query.snapshots().map((snap) {
      return snap.docs
          .map((d) => AppTransaction.fromMap(d.data(), d.id))
          .toList();
    });
  }

  /// Lấy danh sách giao dịch của user trong khoảng thời gian (dùng cho Smart Transaction Assistant)
  Future<List<AppTransaction>> getUserTransactions(
    String userId, {
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      Query<Map<String, dynamic>> query =
          _db.collection('transactions').where('userId', isEqualTo: userId);

      if (from != null) {
        query = query.where(
          'date',
          isGreaterThanOrEqualTo: from.toIso8601String(),
        );
      }
      if (to != null) {
        query = query.where('date', isLessThanOrEqualTo: to.toIso8601String());
      }
      if (from != null || to != null) {
        // Bắt buộc chỉ định orderBy('date', descending: true) để khớp Composite Index (userId ASC, date DESC)
        query = query.orderBy('date', descending: true);
      }

      final snap = await query.get();
      final list = snap.docs
          .map((d) => AppTransaction.fromMap(d.data(), d.id))
          .toList();
      list.sort((a, b) => b.date.compareTo(a.date));
      return list;
    } catch (e) {
      debugPrint(
        '[getUserTransactions] Fallback sang single-field query do lỗi index/truy vấn: $e',
      );
      final all = await getTransactionsSafely(userId);
      return all.where((tx) {
        if (from != null && tx.date.isBefore(from)) return false;
        if (to != null && tx.date.isAfter(to)) return false;
        return true;
      }).toList();
    }
  }


  Future<void> updateTransaction(String txId, Map<String, dynamic> data) {
    return _db.collection('transactions').doc(txId).update(data);
  }

  /// Cập nhật giao dịch an toàn, xử lý atomic cả số dư ví và ngân sách
  Future<void> updateTransactionSafely(
    AppTransaction oldTx,
    AppTransaction newTx, {
    DateTime? currentReferenceDate,
  }) async {
    if (oldTx.type == 'goal_deposit' ||
        oldTx.type == 'goal_withdraw' ||
        newTx.type == 'goal_deposit' ||
        newTx.type == 'goal_withdraw') {
      throw Exception(
          AppLocalizations.tr('svc_tbl_edit_goal_blocked'));
    }

    TransactionBusinessLogic.validateAmount(newTx.amount);

    final monthStrNew = DateFormat('MM/yyyy').format(newTx.date);
    final monthStrOld = DateFormat('MM/yyyy').format(oldTx.date);

    DocumentReference? newBudgetRef;
    if (newTx.type == 'expense') {
      final q = await _db
          .collection('budgets')
          .where('userId', isEqualTo: newTx.userId)
          .where('categoryId', isEqualTo: newTx.categoryId)
          .where('month', isEqualTo: monthStrNew)
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) newBudgetRef = q.docs.first.reference;
    }

    final txRef = _db.collection('transactions').doc(newTx.transactionId);
    final oldWalletRef = _db.collection('wallets').doc(oldTx.walletId);
    final newWalletRef = _db.collection('wallets').doc(newTx.walletId);
    final oldToWalletRef =
        (oldTx.type == 'transfer' && oldTx.toWalletId != null)
            ? _db.collection('wallets').doc(oldTx.toWalletId!)
            : null;
    final newToWalletRef =
        (newTx.type == 'transfer' && newTx.toWalletId != null)
            ? _db.collection('wallets').doc(newTx.toWalletId!)
            : null;

    await _db.runTransaction((txn) async {
      final oldWalletSnap = await txn.get(oldWalletRef);
      if (!oldWalletSnap.exists) throw Exception(AppLocalizations.tr('svc_fs_src_not_found_dot'));
      final oldWallet = Wallet.fromMap(
          oldWalletSnap.data() as Map<String, dynamic>, oldWalletSnap.id);

      final newWalletSnap = (newTx.walletId == oldTx.walletId)
          ? oldWalletSnap
          : await txn.get(newWalletRef);
      if (!newWalletSnap.exists) throw Exception(AppLocalizations.tr('svc_fs_new_src_not_found'));
      final newWallet = Wallet.fromMap(
          newWalletSnap.data() as Map<String, dynamic>, newWalletSnap.id);

      Wallet? oldToWallet;
      if (oldToWalletRef != null) {
        final oldToSnap = await txn.get(oldToWalletRef);
        if (oldToSnap.exists) {
          oldToWallet = Wallet.fromMap(
              oldToSnap.data() as Map<String, dynamic>, oldToSnap.id);
        }
      }

      Wallet? newToWallet;
      if (newToWalletRef != null) {
        final newToSnap = (oldTx.type == 'transfer' &&
                newTx.toWalletId == oldTx.toWalletId &&
                oldToWallet != null)
            ? await txn.get(oldToWalletRef!)
            : await txn.get(newToWalletRef);
        if (!newToSnap.exists) throw Exception(AppLocalizations.tr('svc_tbl_dst_missing'));
        newToWallet = Wallet.fromMap(
            newToSnap.data() as Map<String, dynamic>, newToSnap.id);
      }

      final balanceMap = TransactionBusinessLogic.processUpdateTransaction(
        oldTx: oldTx,
        newTx: newTx,
        oldWallet: oldWallet,
        newWallet: newWallet,
        oldToWallet: oldToWallet,
        newToWallet: newToWallet,
      );

      // Cập nhật tất cả các ví đã tính toán vào transaction
      balanceMap.forEach((walletId, newBalance) {
        txn.update(
            _db.collection('wallets').doc(walletId), {'balance': newBalance});
      });

      txn.update(txRef, newTx.toMap());
    });

    if (newTx.type == 'expense' && newBudgetRef != null) {
      try {
        final budgetDoc = await newBudgetRef.get();
        final data = budgetDoc.data() as Map<String, dynamic>?;
        if (data != null) {
          final limit = (data['limit'] as num).toDouble();
          final newSpent = await getCategorySpentThisMonth(
              newTx.userId, newTx.categoryId,
              month: newTx.date);
          final delta = newTx.categoryId == oldTx.categoryId
              ? (newTx.amount - oldTx.amount)
              : newTx.amount;
          final oldSpent = newSpent - delta;
          if (limit > 0 && newSpent >= limit * 0.8 && oldSpent < limit * 0.8) {
            await createNotification(AppNotification(
              notificationId: '',
              userId: newTx.userId,
              title: AppLocalizations.tr('svc_fs_bud_warn_title'),
              content:
                  AppLocalizations.tr('svc_fs_bud_warn_edit', params: {'month': monthStrNew}),
              status: 'unread',
              type: 'budget',
              createdAt: DateTime.now(),
              titleKey: 'svc_fs_bud_warn_title',
              contentKey: 'svc_fs_bud_warn_edit',
              contentParams: {'month': monthStrNew},
            ));
          }
        }
      } catch (_) {}
    }

    if (oldTx.type == 'expense' && oldTx.userId.isNotEmpty) {
      try {
        await _syncFutureMonthlyPlansAfterSourceExpenseChange(
          userId: oldTx.userId,
          sourceMonth: monthStrOld,
          affectedCategoryIds: {oldTx.categoryId},
          currentReferenceDate: currentReferenceDate,
        );
      } catch (e) {
        debugPrint('[updateTransactionSafely] Lỗi đồng bộ kế hoạch tương lai: $e');
      }
    }

    FinancialContextRevisionTracker.notifyDataMutated();
  }

  Future<void> deleteTransaction(
    AppTransaction tx, {
    DateTime? currentReferenceDate,
  }) async {
    final txRef = _db.collection('transactions').doc(tx.transactionId);
    final walletRef = _db.collection('wallets').doc(tx.walletId);
    final toWalletRef = (tx.type == 'transfer' &&
            tx.toWalletId != null &&
            tx.toWalletId!.isNotEmpty)
        ? _db.collection('wallets').doc(tx.toWalletId!)
        : null;
    final goalRef =
        ((tx.type == 'goal_deposit' || tx.type == 'goal_withdraw') &&
                tx.goalId != null &&
                tx.goalId!.isNotEmpty)
            ? _db.collection('savingGoals').doc(tx.goalId!)
            : null;

    if (goalRef != null) {
      try {
        final preGoalSnap = await goalRef.get();
        if (preGoalSnap.exists && preGoalSnap.data() != null) {
          final preGoal = SavingGoal.fromMap(
            preGoalSnap.data() as Map<String, dynamic>,
            preGoalSnap.id,
          );
          if (preGoal.needsSourceSync) {
            await syncGoalWalletSourcesIfNeeded(preGoal);
          }
        }
      } catch (_) {}
    }

    bool wasDeleted = false;
    AppTransaction deletedTx = tx;

    await _db.runTransaction((transaction) async {
      final txSnap = await transaction.get(txRef);
      if (!txSnap.exists) return; // Giao dịch đã bị xóa trước đó
      if (txSnap.data() != null) {
        deletedTx = AppTransaction.fromMap(
          txSnap.data() as Map<String, dynamic>,
          txSnap.id,
        );
      }

      final walletSnap = await transaction.get(walletRef);
      Wallet? wallet;
      if (walletSnap.exists) {
        wallet = Wallet.fromMap(
            walletSnap.data() as Map<String, dynamic>, walletSnap.id);
      }

      Wallet? toWallet;
      if (toWalletRef != null) {
        final toWalletSnap = await transaction.get(toWalletRef);
        if (toWalletSnap.exists) {
          toWallet = Wallet.fromMap(
              toWalletSnap.data() as Map<String, dynamic>, toWalletSnap.id);
        }
      }

      SavingGoal? goal;
      if (goalRef != null) {
        final goalSnap = await transaction.get(goalRef);
        if (goalSnap.exists) {
          goal = SavingGoal.fromMap(
              goalSnap.data() as Map<String, dynamic>, goalSnap.id);
        }
      }

      final effects = TransactionBusinessLogic.processDeleteTransaction(
        tx: tx,
        wallet: wallet,
        toWallet: toWallet,
        goal: goal,
      );

      if (walletSnap.exists && effects.newSourceBalance != null) {
        transaction.update(walletRef, {'balance': effects.newSourceBalance});
      }
      if (toWalletRef != null && effects.newTargetBalance != null) {
        final toSnap = await transaction.get(toWalletRef);
        if (toSnap.exists) {
          transaction
              .update(toWalletRef, {'balance': effects.newTargetBalance});
        }
      }
      if (goalRef != null && effects.newGoalSavedAmount != null) {
        final gSnap = await transaction.get(goalRef);
        if (gSnap.exists) {
          final goalUpdates = <String, dynamic>{
            'savedAmount': effects.newGoalSavedAmount,
          };
          if (effects.newGoalWalletSources != null) {
            goalUpdates['walletSources'] = {
              for (final entry in effects.newGoalWalletSources!.entries)
                entry.key: entry.value.toMap(),
            };
          }
          if (effects.newGoalDeposits != null) {
            goalUpdates['deposits'] =
                effects.newGoalDeposits!.map((d) => d.toMap()).toList();
          }
          transaction.update(goalRef, goalUpdates);
        }
      }

      wasDeleted = true;
      transaction.delete(txRef);
    });

    if (tx.image != null && tx.image!.isNotEmpty) {
      try {
        await StorageService().deleteImageByUrl(tx.image!);
      } catch (_) {}
    }

    if (wasDeleted &&
        deletedTx.type == 'expense' &&
        deletedTx.userId.isNotEmpty) {
      try {
        await _syncFutureMonthlyPlansAfterSourceExpenseChange(
          userId: deletedTx.userId,
          sourceMonth: DateFormat('MM/yyyy').format(deletedTx.date),
          affectedCategoryIds: {deletedTx.categoryId},
          currentReferenceDate: currentReferenceDate,
        );
      } catch (e) {
        debugPrint('[deleteTransaction] Lỗi đồng bộ kế hoạch & hạn mức tương lai: $e');
      }
    }

    FinancialContextRevisionTracker.notifyDataMutated();
  }

  // ---------------- BUDGETS ----------------
  Future<String> createBudget(Budget budget) async {
    final ref = await _db.collection('budgets').add(budget.toMap());
    FinancialContextRevisionTracker.notifyDataMutated();
    return ref.id;
  }

  Stream<List<Budget>> streamBudgets(String userId, {String? month}) {
    Query<Map<String, dynamic>> query =
        _db.collection('budgets').where('userId', isEqualTo: userId);
    if (month != null) {
      query = query.where('month', isEqualTo: month);
    }
    return query.snapshots().map((snap) {
      final list =
          snap.docs.map((d) => Budget.fromMap(d.data(), d.id)).toList();
      list.sort((a, b) => b.month
          .compareTo(a.month)); // Sort text MM/yyyy, not perfect but okay
      return list;
    });
  }

  Future<void> updateBudget(String budgetId, Map<String, dynamic> data) async {
    await _db.collection('budgets').doc(budgetId).update(data);
    FinancialContextRevisionTracker.notifyDataMutated();
  }

  Future<void> deleteBudget(String budgetId) async {
    await _db.collection('budgets').doc(budgetId).delete();
    FinancialContextRevisionTracker.notifyDataMutated();
  }

  /// Tính tổng chi tiêu (expense) của 1 category trong 1 tháng cụ thể —
  /// tính ĐỘNG từ transactions, không đọc field spent (đã bỏ khỏi Budget).
  Future<double> getCategorySpentThisMonth(
    String userId,
    String categoryId, {
    DateTime? month,
  }) async {
    final target = month ?? DateTime.now();
    final monthStart = DateTime(target.year, target.month, 1);
    final monthEnd = DateTime(target.year, target.month + 1, 1)
        .subtract(const Duration(seconds: 1));
    try {
      final txQuery = await _db
          .collection('transactions')
          .where('userId', isEqualTo: userId)
          .where('date', isGreaterThanOrEqualTo: monthStart.toIso8601String())
          .where('date', isLessThanOrEqualTo: monthEnd.toIso8601String())
          .orderBy('date', descending: true)
          .get();
      double total = 0;
      for (final doc in txQuery.docs) {
        final data = doc.data();
        if (data['type'] == 'expense' && data['categoryId'] == categoryId) {
          total += (data['amount'] as num).toDouble();
        }
      }
      return total;
    } catch (_) {
      final allTx = await getTransactionsSafely(userId);
      double total = 0;
      for (final tx in allTx) {
        if (tx.type == 'expense' &&
            tx.categoryId == categoryId &&
            !tx.date.isBefore(monthStart) &&
            !tx.date.isAfter(monthEnd)) {
          total += tx.amount;
        }
      }
      return total;
    }
  }

  // ---------------- SAVING GOALS ----------------
  Future<String> createSavingGoal(SavingGoal goal) async {
    final ref = await _db.collection('savingGoals').add(goal.toMap());
    FinancialContextRevisionTracker.notifyDataMutated();
    return ref.id;
  }

  Stream<List<SavingGoal>> streamSavingGoals(String userId) {
    if (userId.isEmpty) {
      return Stream.value([]);
    }
    return _db
        .collection('savingGoals')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snap) {
      final list = <SavingGoal>[];
      for (final doc in snap.docs) {
        try {
          list.add(SavingGoal.fromMap(doc.data(), doc.id));
        } catch (e) {
          debugPrint('❌ Lỗi parse SavingGoal doc ${doc.id}: $e');
        }
      }
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  Future<void> updateSavingGoal(String goalId, Map<String, dynamic> data) async {
    await _db.collection('savingGoals').doc(goalId).update(data);
    FinancialContextRevisionTracker.notifyDataMutated();
  }

  Future<void> deleteSavingGoal(String goalId) async {
    await _db.collection('savingGoals').doc(goalId).delete();
    FinancialContextRevisionTracker.notifyDataMutated();
  }

  /// Đồng bộ nguồn ví (`walletSources` và `deposits`) từ lịch sử giao dịch thực tế
  /// cho các mục tiêu tiết kiệm cũ chưa lưu trường `walletSources`.
  Future<SavingGoal> syncGoalWalletSourcesIfNeeded(SavingGoal goal) async {
    if (!goal.needsSourceSync || goal.userId.isEmpty) {
      return goal;
    }
    try {
      final walletsSnap = await _db
          .collection('wallets')
          .where('userId', isEqualTo: goal.userId)
          .get();
      final walletNamesById = <String, String>{};
      for (final doc in walletsSnap.docs) {
        final data = doc.data();
        walletNamesById[doc.id] =
            data['walletName']?.toString() ?? AppLocalizations.tr('svc_tbl_pay_wallet');
      }

      final allTx = await getTransactionsSafely(goal.userId);
      final goalTransactions = allTx
          .where(
            (t) =>
                t.goalId == goal.goalId &&
                (t.type == 'goal_deposit' || t.type == 'goal_withdraw'),
          )
          .toList();

      final syncedGoal = TransactionBusinessLogic.reconstructGoalSources(
        goal: goal,
        goalTransactions: goalTransactions,
        walletNamesById: walletNamesById,
      );

      await _db.collection('savingGoals').doc(goal.goalId).update({
        'walletSources': {
          for (final entry in syncedGoal.walletSources.entries)
            entry.key: entry.value.toMap(),
        },
        'deposits': syncedGoal.deposits.map((d) => d.toMap()).toList(),
        'sourcesSynced': true,
      });

      return syncedGoal;
    } catch (e) {
      debugPrint(
        '⚠️ Không thể đồng bộ nguồn ví cho mục tiêu ${goal.goalId}: $e',
      );
      return goal;
    }
  }

  // ---------------- NOTIFICATIONS ----------------
  Future<void> createNotification(AppNotification notification) {
    return _db.collection('notifications').add(notification.toMap());
  }

  Stream<List<AppNotification>> streamNotifications(String userId) {
    return _db
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => AppNotification.fromMap(d.data(), d.id))
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  // ---------------- HELPERS ----------------
  /// Lấy số dư hiện tại của ví
  Future<double> getWalletBalance(String walletId) async {
    final doc = await _db.collection('wallets').doc(walletId).get();
    if (!doc.exists) return 0;
    final data = doc.data()!;
    return (data['balance'] as num).toDouble();
  }

  /// Lấy budget cho danh mục trong tháng hiện tại (hoặc tháng chỉ định)
  Future<Budget?> getCategoryBudget(String userId, String categoryId,
      {String? month}) async {
    final now = DateTime.now();
    final monthStr = month ?? DateFormat('MM/yyyy').format(now);
    final query = await _db
        .collection('budgets')
        .where('userId', isEqualTo: userId)
        .where('categoryId', isEqualTo: categoryId)
        .where('month', isEqualTo: monthStr)
        .limit(1)
        .get();
    if (query.docs.isEmpty) return null;
    final doc = query.docs.first;
    return Budget.fromMap(doc.data(), doc.id);
  }

  Future<void> markNotificationRead(String notificationId) {
    return _db
        .collection('notifications')
        .doc(notificationId)
        .update({'status': 'read'});
  }

  Future<void> markAllNotificationsRead(String userId) async {
    final query = await _db
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .get();
    final batch = _db.batch();
    for (final doc in query.docs) {
      final data = doc.data();
      if (data['status'] != 'read') {
        batch.update(doc.reference, {'status': 'read'});
      }
    }
    await batch.commit();
  }

  Future<void> clearAllNotifications(String userId) async {
    final query = await _db
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .get();
    final batch = _db.batch();
    for (final doc in query.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  Future<void> createRecurringNotificationIfNotExists({
    required String userId,
    required String title,
    required String content,
    required String type,
    required String scheduleId,
    required String occurrenceKey,
    bool showLocalPush = true,
    String? titleKey,
    Map<String, String>? titleParams,
    String? contentKey,
    Map<String, String>? contentParams,
  }) async {
    try {
      // Dùng single-field query theo userId để tránh lỗi thiếu composite index trên Firestore
      final userNotificationsSnap = await _db
          .collection('notifications')
          .where('userId', isEqualTo: userId)
          .get();

      final alreadyExists = userNotificationsSnap.docs.any((doc) {
        final data = doc.data();
        return data['scheduleId'] == scheduleId &&
            data['occurrenceKey'] == occurrenceKey &&
            data['type'] == type;
      });

      if (!alreadyExists) {
        await createNotification(AppNotification(
          notificationId: '',
          userId: userId,
          title: title,
          content: content,
          status: 'unread',
          type: type,
          createdAt: DateTime.now(),
          scheduleId: scheduleId,
          occurrenceKey: occurrenceKey,
          titleKey: titleKey,
          titleParams: titleParams,
          contentKey: contentKey,
          contentParams: contentParams,
        ));

        if (showLocalPush) {
          final pushId = LocalNotificationService.generateNotificationId(
            scheduleId,
            '$occurrenceKey:$type',
            isOnDueDate: type != 'recurring_reminder',
          );
          await LocalNotificationService().showImmediateNotification(
            notificationId: pushId,
            title: title,
            body: content,
            scheduleId: scheduleId,
          );
        }
      }
    } catch (e) {
      debugPrint('[createRecurringNotificationIfNotExists] error: $e');
    }
  }

  /// Đánh dấu các thông báo nhắc hạn/đến hạn của kỳ đã xử lý thành đã đọc và hủy thông báo thanh trạng thái
  Future<void> resolveRecurringNotificationsForOccurrence({
    required String userId,
    required String scheduleId,
    required String occurrenceKey,
    String? resolutionNote,
    String? resolutionContentKey,
    Map<String, String>? resolutionContentParams,
  }) async {
    try {
      await LocalNotificationService()
          .cancelNotificationForOccurrence(scheduleId, occurrenceKey);

      final snap = await _db
          .collection('notifications')
          .where('userId', isEqualTo: userId)
          .get();

      final batch = _db.batch();
      int count = 0;
      for (final doc in snap.docs) {
        final data = doc.data();
        if (data['scheduleId'] == scheduleId &&
            data['occurrenceKey'] == occurrenceKey &&
            (data['type'] == 'recurring_due' ||
                data['type'] == 'recurring_reminder' ||
                data['type'] == 'recurring_failed')) {
          final updates = <String, dynamic>{'status': 'read'};
          if (resolutionNote != null && resolutionNote.isNotEmpty) {
            updates['content'] = resolutionNote;
            if (resolutionContentKey != null &&
                resolutionContentKey.isNotEmpty) {
              updates['contentKey'] = resolutionContentKey;
              if (resolutionContentParams != null &&
                  resolutionContentParams.isNotEmpty) {
                updates['contentParams'] = resolutionContentParams;
              } else {
                updates['contentParams'] = FieldValue.delete();
              }
            } else {
              updates['contentKey'] = FieldValue.delete();
              updates['contentParams'] = FieldValue.delete();
            }
          }
          batch.update(doc.reference, updates);
          count++;
        }
      }
      if (count > 0) {
        await batch.commit();
      }
    } catch (e) {
      debugPrint('[resolveRecurringNotificationsForOccurrence] error: $e');
    }
  }

  /// Đánh dấu các thông báo đang chờ của một lịch khi lịch bị tạm dừng hoặc xóa
  Future<void> resolvePendingNotificationsForSchedule({
    required String userId,
    required String scheduleId,
  }) async {
    try {
      await LocalNotificationService().cancelRemindersForSchedule(scheduleId);
      final snap = await _db
          .collection('notifications')
          .where('userId', isEqualTo: userId)
          .get();

      final batch = _db.batch();
      int count = 0;
      for (final doc in snap.docs) {
        final data = doc.data();
        if (data['scheduleId'] == scheduleId &&
            data['status'] == 'unread' &&
            (data['type'] == 'recurring_due' ||
                data['type'] == 'recurring_reminder')) {
          batch.update(doc.reference, {'status': 'read'});
          count++;
        }
      }
      if (count > 0) {
        await batch.commit();
      }
    } catch (e) {
      debugPrint('[resolvePendingNotificationsForSchedule] error: $e');
    }
  }

  /// Đồng bộ lại toàn bộ OS local notifications từ trạng thái mới nhất trong Firestore
  Future<void> resyncLocalNotifications(
    String userId, {
    bool force = false,
  }) async {
    if (userId.isEmpty || !LocalNotificationService().isInitialized) return;
    try {
      final schedulesSnap = await _db
          .collection('recurringTransactions')
          .where('userId', isEqualTo: userId)
          .get();
      final walletsSnap = await _db
          .collection('wallets')
          .where('userId', isEqualTo: userId)
          .get();

      final schedules = schedulesSnap.docs
          .map((d) => RecurringTransactionSchedule.fromMap(d.data(), d.id))
          .toList();
      final walletNamesMap = <String, String>{
        for (final w in walletsSnap.docs)
          w.id: WalletLocalizationHelper.localizeWallet(
            Wallet.fromMap(w.data(), w.id),
          ),
      };

      await LocalNotificationService().syncAllReminders(
        schedules: schedules,
        walletNamesMap: walletNamesMap,
        force: force,
      );
    } catch (e) {
      debugPrint('[resyncLocalNotifications] error: $e');
    }
  }

  /// Đồng bộ thông báo trong app và thanh trạng thái cho các kỳ đến hạn hoặc sắp đến hạn cần xử lý
  Future<void> syncRecurringNotifications(String userId) async {
    if (userId.isEmpty) return;
    try {
      // Đảm bảo các lịch manualConfirmation quá hạn 3 ngày được tự động chuyển kỳ
      // trước khi tạo hoặc giữ lại thông báo nhắc hạn cũ.
      await processDueRecurringTransactions(userId);

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final schedulesSnap = await _db
          .collection('recurringTransactions')
          .where('userId', isEqualTo: userId)
          .get();

      final schedules = schedulesSnap.docs
          .map((d) => RecurringTransactionSchedule.fromMap(d.data(), d.id))
          .where((s) => s.isActive)
          .toList();

      final walletsSnap = await _db
          .collection('wallets')
          .where('userId', isEqualTo: userId)
          .get();
      final walletNamesMap = <String, String>{
        for (final w in walletsSnap.docs)
          w.id: WalletLocalizationHelper.localizeWallet(
            Wallet.fromMap(w.data(), w.id),
          ),
      };

      for (final s in schedules) {
        final occurrenceKey =
            RecurringTransactionService.getOccurrenceKey(s.nextDueDate);
        if (s.lastProcessedKey == occurrenceKey) continue;

        final rawNote = s.note?.trim() ?? '';
        final rawNameToken = rawNote.isNotEmpty
            ? rawNote
            : (s.type == 'income'
                ? 'Thu nhập định kỳ'
                : 'Khoản chi định kỳ');
        final displayName = rawNote.isNotEmpty
            ? CategoryLocalizationHelper.localizeName(rawNote)
            : (s.type == 'income'
                ? AppLocalizations.tr('svc_fs_rec_in_default')
                : AppLocalizations.tr('svc_fs_rec_out_default'));
        final isIncome = s.type == 'income';
        final dirWord = isIncome
            ? AppLocalizations.tr('svc_fs_rec_in_word')
            : AppLocalizations.tr('svc_fs_rec_out_word');
        final amountFormatted =
            '${AppFormatters.number(s.amount)} ${LanguageController.isEnglish ? 'VND' : 'VNĐ'}';
        final dueDateOnly = DateTime(
          s.nextDueDate.year,
          s.nextDueDate.month,
          s.nextDueDate.day,
        );

        // 1. Quá hạn (chỉ nằm trong cửa sổ hiệu lực hoặc auto bị kẹt)
        if (dueDateOnly.isBefore(today)) {
          final diffDays =
              RecurringTransactionService.calendarDaysBetween(dueDateOnly, today);
          final isManual =
              s.postingMode == RecurringTransactionSchedule.postingModeManual;
          if (isManual &&
              diffDays >=
                  RecurringTransactionService.manualConfirmationGraceDays) {
            continue;
          }
          final dueDateStr = DateFormat('dd/MM/yyyy').format(s.nextDueDate);
          await createRecurringNotificationIfNotExists(
            userId: userId,
            title: AppLocalizations.tr('svc_fs_rec_overdue_title',
                params: {'name': displayName}),
            content: AppLocalizations.tr('svc_fs_rec_overdue_body', params: {
              'dir': dirWord,
              'amount': amountFormatted,
              'days': '$diffDays',
              'date': dueDateStr,
            }),
            type: 'recurring_due',
            scheduleId: s.scheduleId,
            occurrenceKey: occurrenceKey,
            titleKey: 'svc_fs_rec_overdue_title',
            titleParams: {'name': rawNameToken},
            contentKey: 'svc_fs_rec_overdue_body',
            contentParams: {
              'dir': isIncome ? 'income' : 'expense',
              'amount': amountFormatted,
              'days': '$diffDays',
              'date': dueDateStr,
            },
          );
        }
        // 2. Đến hạn hôm nay
        else if (dueDateOnly == today) {
          final isManual =
              s.postingMode == RecurringTransactionSchedule.postingModeManual;
          final bodyKey =
              isManual ? 'svc_fs_rec_today_manual' : 'svc_fs_rec_today_auto';
          await createRecurringNotificationIfNotExists(
            userId: userId,
            title: AppLocalizations.tr('svc_fs_rec_today_title',
                params: {'name': displayName}),
            content: AppLocalizations.tr(bodyKey, params: {
              'dir': dirWord,
              'amount': amountFormatted,
            }),
            type: 'recurring_due',
            scheduleId: s.scheduleId,
            occurrenceKey: occurrenceKey,
            titleKey: 'svc_fs_rec_today_title',
            titleParams: {'name': rawNameToken},
            contentKey: bodyKey,
            contentParams: {
              'dir': isIncome ? 'income' : 'expense',
              'amount': amountFormatted,
            },
          );
        }
        // 3. Sắp đến hạn (theo reminderDaysBefore)
        else if (s.reminderDaysBefore > 0) {
          final reminderDate = DateTime(
            dueDateOnly.year,
            dueDateOnly.month,
            dueDateOnly.day - s.reminderDaysBefore,
          );
          if (!today.isBefore(reminderDate) && today.isBefore(dueDateOnly)) {
            final daysLeft = RecurringTransactionService.calendarDaysBetween(
              today,
              dueDateOnly,
            );
            final dueDateStr = DateFormat('dd/MM/yyyy').format(s.nextDueDate);
            await createRecurringNotificationIfNotExists(
              userId: userId,
              title: AppLocalizations.tr('svc_fs_rec_soon_title',
                  params: {'name': displayName}),
              content: AppLocalizations.tr('svc_fs_rec_soon_body', params: {
                'days': '$daysLeft',
                'dir': dirWord,
                'amount': amountFormatted,
                'date': dueDateStr,
              }),
              type: 'recurring_reminder',
              scheduleId: s.scheduleId,
              occurrenceKey: occurrenceKey,
              titleKey: 'svc_fs_rec_soon_title',
              titleParams: {'name': rawNameToken},
              contentKey: 'svc_fs_rec_soon_body',
              contentParams: {
                'days': '$daysLeft',
                'dir': isIncome ? 'income' : 'expense',
                'amount': amountFormatted,
                'date': dueDateStr,
              },
            );
          }
        }
      }

      if (LocalNotificationService().isInitialized) {
        await LocalNotificationService().syncAllReminders(
          schedules: schedules,
          walletNamesMap: walletNamesMap,
        );
      }
    } catch (e) {
      debugPrint('[syncRecurringNotifications] error: $e');
    }
  }

  // ---------------- RECURRING TRANSACTIONS ----------------
  Future<String> createRecurringTransaction(
      RecurringTransactionSchedule schedule) async {
    RecurringTransactionSchedule.validateAmount(schedule.amount);

    final walletDoc =
        await _db.collection('wallets').doc(schedule.walletId).get();
    if (!walletDoc.exists) {
      throw Exception(AppLocalizations.tr('svc_fs_rec_val_wallet'));
    }
    final wallet = Wallet.fromMap(walletDoc.data()!, walletDoc.id);
    if (!wallet.isActive) {
      throw Exception(AppLocalizations.tr('svc_fs_rec_val_wallet_hidden'));
    }

    if (schedule.categoryId.isNotEmpty) {
      final catDoc =
          await _db.collection('categories').doc(schedule.categoryId).get();
      if (!catDoc.exists) {
        throw Exception(AppLocalizations.tr('svc_fs_rec_val_cat'));
      }
    }

    final ref =
        await _db.collection('recurringTransactions').add(schedule.toMap());
    await resyncLocalNotifications(schedule.userId, force: true);
    return ref.id;
  }

  Stream<List<RecurringTransactionSchedule>> streamRecurringTransactions(
      String userId) {
    return _db
        .collection('recurringTransactions')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => RecurringTransactionSchedule.fromMap(d.data(), d.id))
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  Future<void> updateRecurringTransaction(
      String scheduleId, Map<String, dynamic> data) async {
    data.remove('userId'); // Bảo vệ userId không bị thay đổi
    data['updatedAt'] = DateTime.now().toIso8601String();
    await _db.collection('recurringTransactions').doc(scheduleId).update(data);
    try {
      final snap =
          await _db.collection('recurringTransactions').doc(scheduleId).get();
      final userId = (snap.data()?['userId'] ?? '').toString();
      if (userId.isNotEmpty) {
        await resyncLocalNotifications(userId, force: true);
      }
    } catch (_) {}
  }

  Future<void> setRecurringTransactionActive(String scheduleId, bool isActive) async {
    final scheduleRef = _db.collection('recurringTransactions').doc(scheduleId);
    final scheduleSnap = await scheduleRef.get();
    if (!scheduleSnap.exists) return;

    final sData = scheduleSnap.data()!;
    final schedule = RecurringTransactionSchedule.fromMap(sData, scheduleId);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final updateData = <String, dynamic>{
      'isActive': isActive,
      'updatedAt': now.toIso8601String(),
    };

    // Khi kích hoạt lại (isActive == true) mà ngày đến hạn nextDueDate đã nằm trong quá khứ (trước hôm nay),
    // đồng bộ nextDueDate sang kỳ kế tiếp hợp lệ để không tạo hàng loạt giao dịch quá hạn ngoài ý muốn!
    final dueDateOnly = DateTime(
      schedule.nextDueDate.year,
      schedule.nextDueDate.month,
      schedule.nextDueDate.day,
    );
    if (isActive && dueDateOnly.isBefore(today)) {
      final recService = RecurringTransactionService();
      var synchronizedNextDue = schedule.nextDueDate;
      while (DateTime(
        synchronizedNextDue.year,
        synchronizedNextDue.month,
        synchronizedNextDue.day,
      ).isBefore(today)) {
        synchronizedNextDue = recService.nextOccurrenceAfter(
          synchronizedNextDue,
          schedule.frequency,
          schedule.startDate,
        );
      }
      updateData['nextDueDate'] = synchronizedNextDue.toIso8601String();
    }

    await scheduleRef.update(updateData);

    if (!isActive) {
      await resolvePendingNotificationsForSchedule(
        userId: schedule.userId,
        scheduleId: scheduleId,
      );
    }
    await resyncLocalNotifications(schedule.userId, force: true);
  }

  Future<void> deleteRecurringTransaction(String scheduleId) async {
    String deletedUserId = '';
    try {
      final snap = await _db.collection('recurringTransactions').doc(scheduleId).get();
      if (snap.exists && snap.data() != null) {
        final userId = (snap.data()!['userId'] ?? '').toString();
        deletedUserId = userId;
        if (userId.isNotEmpty) {
          await resolvePendingNotificationsForSchedule(
            userId: userId,
            scheduleId: scheduleId,
          );
        }
      }
    } catch (_) {}
    // Chỉ xóa schedule, không xóa lịch sử giao dịch đã tạo trước đó
    await _db.collection('recurringTransactions').doc(scheduleId).delete();
    if (deletedUserId.isNotEmpty) {
      await resyncLocalNotifications(deletedUserId, force: true);
    }
  }

  Future<Map<String, dynamic>> processDueRecurringTransactions(
    String userId, {
    DateTime? referenceDate,
  }) async {
    final now = referenceDate ?? DateTime.now();
    final recService = RecurringTransactionService();

    debugPrint(
        '[DebugRecurring] collection: recurringTransactions, op: read, scheduleId: all');

    final querySnap = await _db
        .collection('recurringTransactions')
        .where('userId', isEqualTo: userId)
        .where('isActive', isEqualTo: true)
        .get();

    final allActiveSchedules = querySnap.docs
        .map((d) => RecurringTransactionSchedule.fromMap(d.data(), d.id))
        .toList();

    final schedules = allActiveSchedules
        .where((s) => s.postingMode == RecurringTransactionSchedule.postingModeAuto)
        .toList();

    final manualSchedules = allActiveSchedules
        .where(
            (s) => s.postingMode == RecurringTransactionSchedule.postingModeManual)
        .toList();

    int processedCount = 0;
    int skippedCount = 0;
    int autoSkippedManualCount = 0;
    final List<String> failedSchedules = [];

    // 1. Tự động bỏ qua kỳ quá hạn > 3 ngày (grace period) cho lịch cần xác nhận (manualConfirmation).
    // Tuyệt đối KHÔNG áp dụng cho lịch autoPost.
    for (final manualSchedule in manualSchedules) {
      if (manualSchedule.userId.isEmpty || manualSchedule.userId != userId) {
        continue;
      }

      final graceEval = recService.evaluateManualGracePeriod(
        schedule: manualSchedule,
        referenceDate: now,
      );
      if (!graceEval.wasAutoSkipped) continue;

      final scheduleRef = _db
          .collection('recurringTransactions')
          .doc(manualSchedule.scheduleId);

      List<DateTime> committedSkippedDates = [];

      try {
        Future<void> executeAutoSkipTxn({required bool withOccurrence}) async {
          await _db.runTransaction((txn) async {
            final freshSnap = await txn.get(scheduleRef);
            if (!freshSnap.exists || freshSnap.data() == null) return;
            final freshSchedule = RecurringTransactionSchedule.fromMap(
              freshSnap.data()!,
              freshSnap.id,
            );
            if (!freshSchedule.isActive ||
                freshSchedule.postingMode !=
                    RecurringTransactionSchedule.postingModeManual) {
              return;
            }

            final freshEval = recService.evaluateManualGracePeriod(
              schedule: freshSchedule,
              referenceDate: now,
            );
            if (!freshEval.wasAutoSkipped) return;

            final occEntries = <Map<String, dynamic>>[];
            if (withOccurrence) {
              // Đọc tất cả occurrence docs trước khi ghi (Firestore transaction rule)
              for (final skippedDate in freshEval.skippedDates) {
                final occKey =
                    RecurringTransactionService.getOccurrenceKey(skippedDate);
                final occDocId = '${freshSchedule.scheduleId}_$occKey';
                final occRef = _db
                    .collection('recurringTransactionOccurrences')
                    .doc(occDocId);
                final occSnap = await txn.get(occRef);
                occEntries.add({
                  'date': skippedDate,
                  'key': occKey,
                  'ref': occRef,
                  'exists': occSnap.exists,
                });
              }
            }

            final actionAt = DateTime.now();
            if (withOccurrence) {
              for (final entry in occEntries) {
                if (entry['exists'] == true) continue;
                txn.set(entry['ref'] as DocumentReference, {
                  'userId': userId,
                  'scheduleId': freshSchedule.scheduleId,
                  'occurrenceKey': entry['key'] as String,
                  'scheduledDate':
                      (entry['date'] as DateTime).toIso8601String(),
                  'action': 'skipped',
                  'actionAt': actionAt.toIso8601String(),
                  'skipReason': 'auto_grace_expired',
                });
              }
            }

            final lastSkippedKey = RecurringTransactionService.getOccurrenceKey(
              freshEval.skippedDates.last,
            );
            txn.update(scheduleRef, {
              'nextDueDate': freshEval.newNextDueDate.toIso8601String(),
              'lastProcessedKey': lastSkippedKey,
              'updatedAt': actionAt.toIso8601String(),
            });

            committedSkippedDates = freshEval.skippedDates;
          });
        }

        try {
          await executeAutoSkipTxn(withOccurrence: true);
        } catch (e) {
          if (_isPermissionDeniedError(e)) {
            await executeAutoSkipTxn(withOccurrence: false);
          } else {
            rethrow;
          }
        }

        if (committedSkippedDates.isNotEmpty) {
          autoSkippedManualCount += committedSkippedDates.length;
          for (final skippedDate in committedSkippedDates) {
            final skippedKey =
                RecurringTransactionService.getOccurrenceKey(skippedDate);
            await resolveRecurringNotificationsForOccurrence(
              userId: userId,
              scheduleId: manualSchedule.scheduleId,
              occurrenceKey: skippedKey,
              resolutionNote:
                  AppLocalizations.tr('svc_fs_rec_autoskip_note'),
              resolutionContentKey: 'svc_fs_rec_autoskip_note',
            );
          }
        }
      } catch (e) {
        debugPrint(
            '[processDueRecurringTransactions] Auto-skip manual grace error for ${manualSchedule.scheduleId}: $e');
      }
    }

    for (final schedule in schedules) {
      if (schedule.userId.isEmpty || schedule.userId != userId) {
        failedSchedules.add(
            AppLocalizations.tr('svc_fs_rec_missing_uid', params: {'id': schedule.scheduleId}));
        continue;
      }

      final dueDates = recService.dueOccurrences(
        schedule: schedule,
        referenceDate: now,
      );

      if (dueDates.isEmpty) continue;

      bool stopSchedule = false;

      for (final occurrenceDate in dueDates) {
        if (stopSchedule) break;

        final occurrenceKey =
            RecurringTransactionService.getOccurrenceKey(occurrenceDate);
        final deterministicTxId =
            RecurringTransactionService.buildTransactionId(
                schedule.scheduleId, occurrenceDate);
        final occurrenceDocId = '${schedule.scheduleId}_$occurrenceKey';

        final txRef = _db.collection('transactions').doc(deterministicTxId);
        final walletRef = _db.collection('wallets').doc(schedule.walletId);
        final scheduleRef =
            _db.collection('recurringTransactions').doc(schedule.scheduleId);
        final occurrenceRef = _db
            .collection('recurringTransactionOccurrences')
            .doc(occurrenceDocId);

        bool transactionAlreadyExists = false;
        bool insufficientBalance = false;
        bool walletUnavailable = false;
        bool invalidUserData = false;

        debugPrint(
            '[DebugRecurring] collection: transactions, op: read, scheduleId: ${schedule.scheduleId}');
        debugPrint(
            '[DebugRecurring] collection: wallets, op: read, scheduleId: ${schedule.scheduleId}');

        Future<void> executeProcessTxn({required bool withOccurrence}) async {
          await _db.runTransaction((txn) async {
            if (withOccurrence) {
              final occSnap = await txn.get(occurrenceRef);
              if (occSnap.exists) {
                transactionAlreadyExists = true;
                return;
              }
            }

            final txSnap = await txn.get(txRef);
            if (txSnap.exists) {
              transactionAlreadyExists = true;
              return;
            }

            final walletSnap = await txn.get(walletRef);
            if (!walletSnap.exists) {
              walletUnavailable = true;
              return;
            }

            final walletData = walletSnap.data() as Map<String, dynamic>;
            final wallet = Wallet.fromMap(walletData, walletSnap.id);

            if (wallet.userId.isEmpty || wallet.userId != userId) {
              invalidUserData = true;
              return;
            }

            if (!wallet.isActive) {
              walletUnavailable = true;
              return;
            }

            if (schedule.type == 'expense' && wallet.balance < schedule.amount) {
              insufficientBalance = true;
              return;
            }

            final appTx = AppTransaction(
              transactionId: deterministicTxId,
              userId: userId,
              walletId: schedule.walletId,
              categoryId: schedule.categoryId,
              amount: schedule.amount,
              type: schedule.type,
              note: schedule.note != null && schedule.note!.isNotEmpty
                  ? schedule.note
                  : AppLocalizations.tr('svc_fs_rec_tx_default'),
              date: occurrenceDate,
              recurringScheduleId: schedule.scheduleId,
              recurringOccurrenceKey: occurrenceKey,
            );

            debugPrint(
                '[DebugRecurring] collection: transactions, op: create, scheduleId: ${schedule.scheduleId}');
            txn.set(txRef, appTx.toMap());

            final delta =
                schedule.type == 'income' ? schedule.amount : -schedule.amount;

            debugPrint(
                '[DebugRecurring] collection: wallets, op: update, scheduleId: ${schedule.scheduleId}');
            txn.update(walletRef, {
              'balance': FieldValue.increment(delta),
            });

            final nextDueDate = recService.nextOccurrenceAfter(
              occurrenceDate,
              schedule.frequency,
              schedule.startDate,
            );

            debugPrint(
                '[DebugRecurring] collection: recurringTransactions, op: update, scheduleId: ${schedule.scheduleId}');
            txn.update(scheduleRef, {
              'nextDueDate': nextDueDate.toIso8601String(),
              'lastProcessedKey': occurrenceKey,
              'updatedAt': DateTime.now().toIso8601String(),
            });

            if (withOccurrence) {
              txn.set(occurrenceRef, {
                'userId': userId,
                'scheduleId': schedule.scheduleId,
                'occurrenceKey': occurrenceKey,
                'scheduledDate': occurrenceDate.toIso8601String(),
                'action': 'confirmed',
                'actionAt': DateTime.now().toIso8601String(),
                'transactionId': deterministicTxId,
              });
            }
          });
        }

        try {
          await executeProcessTxn(withOccurrence: true);
        } catch (e) {
          if (_isPermissionDeniedError(e)) {
            debugPrint(
                '[Recurring] Warning: occurrenceRef threw permission-denied. Retrying without occurrence collection: $e');
            await executeProcessTxn(withOccurrence: false);
          } else {
            rethrow;
          }
        }

        final rawNote = schedule.note?.trim() ?? '';
        final rawNameToken = rawNote.isNotEmpty
            ? rawNote
            : (schedule.type == 'income'
                ? 'Thu nhập định kỳ'
                : 'Khoản chi định kỳ');
        final displayName = rawNote.isNotEmpty
            ? CategoryLocalizationHelper.localizeName(rawNote)
            : (schedule.type == 'income'
                ? AppLocalizations.tr('svc_fs_rec_in_default')
                : AppLocalizations.tr('svc_fs_rec_out_default'));

        if (transactionAlreadyExists) {
          skippedCount++;
        } else if (invalidUserData) {
          failedSchedules.add(
              AppLocalizations.tr('svc_fs_rec_w_missing_uid', params: {'name': displayName}));
          stopSchedule = true;
        } else if (walletUnavailable) {
          failedSchedules.add(
              AppLocalizations.tr('svc_fs_rec_w_unavailable', params: {'name': displayName}));
          stopSchedule = true;
        } else if (insufficientBalance) {
          failedSchedules.add(
              AppLocalizations.tr('svc_fs_rec_w_insufficient_fail', params: {
                  'name': displayName,
                  'amount': '${schedule.amount.round()}',
                }));
          stopSchedule = true;
          final failAmountStr = AppFormatters.currency(schedule.amount);
          await createRecurringNotificationIfNotExists(
            userId: userId,
            title:
                AppLocalizations.tr('svc_fs_rec_fail_title', params: {'name': displayName}),
            content:
                AppLocalizations.tr('svc_fs_rec_fail_body', params: {
                  'amount': failAmountStr,
                  'key': occurrenceKey,
                }),
            type: 'recurring_failed',
            scheduleId: schedule.scheduleId,
            occurrenceKey: occurrenceKey,
            titleKey: 'svc_fs_rec_fail_title',
            titleParams: {'name': rawNameToken},
            contentKey: 'svc_fs_rec_fail_body',
            contentParams: {
              'amount': failAmountStr,
              'key': occurrenceKey,
            },
          );
        } else {
          processedCount++;
          await resolveRecurringNotificationsForOccurrence(
            userId: userId,
            scheduleId: schedule.scheduleId,
            occurrenceKey: occurrenceKey,
          );
          final okAmountStr = AppFormatters.currency(schedule.amount);
          await createRecurringNotificationIfNotExists(
            userId: userId,
            title: AppLocalizations.tr('svc_fs_rec_ok_title', params: {'name': displayName}),
            content:
                AppLocalizations.tr('svc_fs_rec_ok_body', params: {
                  'dir': schedule.type == 'income'
                      ? AppLocalizations.tr('svc_fs_rec_in_full_word')
                      : AppLocalizations.tr('svc_fs_rec_out_full_word'),
                  'amount': okAmountStr,
                  'key': occurrenceKey,
                }),
            type: 'recurring_success',
            scheduleId: schedule.scheduleId,
            occurrenceKey: occurrenceKey,
            titleKey: 'svc_fs_rec_ok_title',
            titleParams: {'name': rawNameToken},
            contentKey: 'svc_fs_rec_ok_body',
            contentParams: {
              'dir': schedule.type == 'income' ? 'income' : 'expense',
              'amount': okAmountStr,
              'key': occurrenceKey,
            },
          );
        }
      }
    }

    if (processedCount > 0 || autoSkippedManualCount > 0) {
      await resyncLocalNotifications(userId, force: true);
    }

    return {
      'processedCount': processedCount,
      'skippedCount': skippedCount,
      'autoSkippedManualCount': autoSkippedManualCount,
      'failedSchedules': failedSchedules,
    };
  }

  /// Xác nhận giao dịch định kỳ thủ công (manualConfirmation mode)
  Future<void> confirmRecurringOccurrence({
    required String userId,
    required RecurringTransactionSchedule schedule,
    required DateTime occurrenceDate,
  }) async {
    final recService = RecurringTransactionService();
    final occurrenceKey =
        RecurringTransactionService.getOccurrenceKey(occurrenceDate);
    final deterministicTxId =
        RecurringTransactionService.buildTransactionId(
            schedule.scheduleId, occurrenceDate);

    final occurrenceDocId = '${schedule.scheduleId}_$occurrenceKey';
    final occurrenceRef =
        _db.collection('recurringTransactionOccurrences').doc(occurrenceDocId);
    final txRef = _db.collection('transactions').doc(deterministicTxId);
    final walletRef = _db.collection('wallets').doc(schedule.walletId);
    final scheduleRef =
        _db.collection('recurringTransactions').doc(schedule.scheduleId);

    Future<void> executeConfirmTxn({required bool withOccurrence}) async {
      await _db.runTransaction((txn) async {
        if (withOccurrence) {
          final occSnap = await txn.get(occurrenceRef);
          if (occSnap.exists) {
            throw Exception(AppLocalizations.tr('svc_fs_rec_already_confirmed'));
          }
        }
        final txSnap = await txn.get(txRef);
        if (txSnap.exists) {
          throw Exception(AppLocalizations.tr('svc_fs_rec_tx_exists'));
        }

        final scheduleSnap = await txn.get(scheduleRef);
        if (scheduleSnap.exists) {
          final sData = scheduleSnap.data();
          if (sData != null && sData['lastProcessedKey'] == occurrenceKey) {
            throw Exception(AppLocalizations.tr('svc_fs_rec_already_confirmed'));
          }
        }

        final walletSnap = await txn.get(walletRef);
        if (!walletSnap.exists) {
          throw Exception(AppLocalizations.tr('svc_fs_rec_exec_w_missing'));
        }
        final walletData = walletSnap.data() as Map<String, dynamic>;
        final wallet = Wallet.fromMap(walletData, walletSnap.id);

        if (wallet.userId.isEmpty || wallet.userId != userId) {
          throw Exception(AppLocalizations.tr('svc_fs_rec_exec_w_uid'));
        }
        if (!wallet.isActive) {
          throw Exception(AppLocalizations.tr('svc_fs_rec_exec_w_inactive'));
        }
        if (schedule.type == 'expense' && wallet.balance < schedule.amount) {
          throw InsufficientBalanceException(
            message:
                AppLocalizations.tr('svc_fs_rec_exec_w_insuff', params: {
                  'wallet': wallet.walletName,
                  'bal': AppFormatters.currency(wallet.balance),
                  'req': AppFormatters.currency(schedule.amount),
                }),
            walletName: wallet.walletName,
            currentBalance: wallet.balance,
            requiredAmount: schedule.amount,
            shortfall: schedule.amount - wallet.balance,
          );
        }

        final appTx = AppTransaction(
          transactionId: deterministicTxId,
          userId: userId,
          walletId: schedule.walletId,
          categoryId: schedule.categoryId,
          amount: schedule.amount,
          type: schedule.type,
          note: schedule.note != null && schedule.note!.trim().isNotEmpty
              ? schedule.note!.trim()
              : AppLocalizations.tr('svc_fs_rec_tx_default'),
          date: occurrenceDate,
          recurringScheduleId: schedule.scheduleId,
          recurringOccurrenceKey: occurrenceKey,
        );

        txn.set(txRef, appTx.toMap());

        final delta =
            schedule.type == 'income' ? schedule.amount : -schedule.amount;
        txn.update(walletRef, {
          'balance': FieldValue.increment(delta),
        });

        final nextDueDate = recService.nextOccurrenceAfter(
          occurrenceDate,
          schedule.frequency,
          schedule.startDate,
        );

        txn.update(scheduleRef, {
          'nextDueDate': nextDueDate.toIso8601String(),
          'lastProcessedKey': occurrenceKey,
          'updatedAt': DateTime.now().toIso8601String(),
        });

        if (withOccurrence) {
          txn.set(occurrenceRef, {
            'userId': userId,
            'scheduleId': schedule.scheduleId,
            'occurrenceKey': occurrenceKey,
            'scheduledDate': occurrenceDate.toIso8601String(),
            'action': 'confirmed',
            'actionAt': DateTime.now().toIso8601String(),
            'transactionId': deterministicTxId,
          });
        }
      });
    }

    try {
      await executeConfirmTxn(withOccurrence: true);
    } catch (e) {
      if (_isPermissionDeniedError(e)) {
        await executeConfirmTxn(withOccurrence: false);
      } else {
        rethrow;
      }
    }

    final confirmedAmountStr = AppFormatters.currency(schedule.amount);
    final confirmedTimeStr = DateFormat('HH:mm dd/MM/yyyy').format(DateTime.now());
    await resolveRecurringNotificationsForOccurrence(
      userId: userId,
      scheduleId: schedule.scheduleId,
      occurrenceKey: occurrenceKey,
      resolutionNote:
          AppLocalizations.tr('svc_fs_rec_confirmed_note', params: {
            'amount': confirmedAmountStr,
            'time': confirmedTimeStr,
          }),
      resolutionContentKey: 'svc_fs_rec_confirmed_note',
      resolutionContentParams: {
        'amount': confirmedAmountStr,
        'time': confirmedTimeStr,
      },
    );
    await resyncLocalNotifications(userId, force: true);
  }

  /// Bỏ qua kỳ giao dịch định kỳ thủ công
  Future<void> skipRecurringOccurrence({
    required String userId,
    required RecurringTransactionSchedule schedule,
    required DateTime occurrenceDate,
  }) async {
    final recService = RecurringTransactionService();
    final occurrenceKey =
        RecurringTransactionService.getOccurrenceKey(occurrenceDate);
    final occurrenceDocId = '${schedule.scheduleId}_$occurrenceKey';
    final occurrenceRef =
        _db.collection('recurringTransactionOccurrences').doc(occurrenceDocId);
    final scheduleRef =
        _db.collection('recurringTransactions').doc(schedule.scheduleId);

    Future<void> executeSkipTxn({required bool withOccurrence}) async {
      await _db.runTransaction((txn) async {
        if (withOccurrence) {
          final occSnap = await txn.get(occurrenceRef);
          if (occSnap.exists) {
            throw Exception(AppLocalizations.tr('svc_fs_rec_already_processed'));
          }
        }

        final scheduleSnap = await txn.get(scheduleRef);
        if (scheduleSnap.exists) {
          final sData = scheduleSnap.data();
          if (sData != null && sData['lastProcessedKey'] == occurrenceKey) {
            throw Exception(AppLocalizations.tr('svc_fs_rec_already_processed'));
          }
        }

        final nextDueDate = recService.nextOccurrenceAfter(
          occurrenceDate,
          schedule.frequency,
          schedule.startDate,
        );

        txn.update(scheduleRef, {
          'nextDueDate': nextDueDate.toIso8601String(),
          'lastProcessedKey': occurrenceKey,
          'updatedAt': DateTime.now().toIso8601String(),
        });

        if (withOccurrence) {
          txn.set(occurrenceRef, {
            'userId': userId,
            'scheduleId': schedule.scheduleId,
            'occurrenceKey': occurrenceKey,
            'scheduledDate': occurrenceDate.toIso8601String(),
            'action': 'skipped',
            'actionAt': DateTime.now().toIso8601String(),
          });
        }
      });
    }

    try {
      await executeSkipTxn(withOccurrence: true);
    } catch (e) {
      if (_isPermissionDeniedError(e)) {
        await executeSkipTxn(withOccurrence: false);
      } else {
        rethrow;
      }
    }

    final skippedDateStr = DateFormat('dd/MM/yyyy').format(occurrenceDate);
    await resolveRecurringNotificationsForOccurrence(
      userId: userId,
      scheduleId: schedule.scheduleId,
      occurrenceKey: occurrenceKey,
      resolutionNote:
          AppLocalizations.tr('svc_fs_rec_skipped_note', params: {
            'date': skippedDateStr,
          }),
      resolutionContentKey: 'svc_fs_rec_skipped_note',
      resolutionContentParams: {'date': skippedDateStr},
    );
    await resyncLocalNotifications(userId, force: true);
  }

  /// Dời ngày giao dịch định kỳ thủ công
  Future<void> deferRecurringOccurrence({
    required String userId,
    required RecurringTransactionSchedule schedule,
    required DateTime occurrenceDate,
    required DateTime newDueDate,
  }) async {
    final occurrenceKey =
        RecurringTransactionService.getOccurrenceKey(occurrenceDate);
    final occurrenceDocId = '${schedule.scheduleId}_$occurrenceKey';
    final occurrenceRef =
        _db.collection('recurringTransactionOccurrences').doc(occurrenceDocId);
    final scheduleRef =
        _db.collection('recurringTransactions').doc(schedule.scheduleId);

    Future<void> executeDeferTxn({required bool withOccurrence}) async {
      await _db.runTransaction((txn) async {
        if (withOccurrence) {
          final occSnap = await txn.get(occurrenceRef);
          if (occSnap.exists) {
            throw Exception(AppLocalizations.tr('svc_fs_rec_already_processed'));
          }
        }

        final scheduleSnap = await txn.get(scheduleRef);
        if (scheduleSnap.exists) {
          final sData = scheduleSnap.data();
          if (sData != null && sData['lastProcessedKey'] == occurrenceKey) {
            throw Exception(AppLocalizations.tr('svc_fs_rec_already_processed'));
          }
        }

        txn.update(scheduleRef, {
          'nextDueDate': newDueDate.toIso8601String(),
          'lastProcessedKey': occurrenceKey,
          'updatedAt': DateTime.now().toIso8601String(),
        });

        if (withOccurrence) {
          txn.set(occurrenceRef, {
            'userId': userId,
            'scheduleId': schedule.scheduleId,
            'occurrenceKey': occurrenceKey,
            'scheduledDate': occurrenceDate.toIso8601String(),
            'action': 'deferred',
            'actionAt': DateTime.now().toIso8601String(),
            'deferredTo': newDueDate.toIso8601String(),
          });
        }
      });
    }

    try {
      await executeDeferTxn(withOccurrence: true);
    } catch (e) {
      if (_isPermissionDeniedError(e)) {
        await executeDeferTxn(withOccurrence: false);
      } else {
        rethrow;
      }
    }

    final deferredDateStr = DateFormat('dd/MM/yyyy').format(newDueDate);
    await resolveRecurringNotificationsForOccurrence(
      userId: userId,
      scheduleId: schedule.scheduleId,
      occurrenceKey: occurrenceKey,
      resolutionNote:
          AppLocalizations.tr('svc_fs_rec_deferred_note', params: {
            'date': deferredDateStr,
          }),
      resolutionContentKey: 'svc_fs_rec_deferred_note',
      resolutionContentParams: {'date': deferredDateStr},
    );
    await resyncLocalNotifications(userId, force: true);
  }

  Stream<List<RecurringTransactionOccurrence>> streamRecurringOccurrences(
      String userId) {
    return _db
        .collection('recurringTransactionOccurrences')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => RecurringTransactionOccurrence.fromMap(d.data(), d.id))
            .toList())
        .transform(
      StreamTransformer<List<RecurringTransactionOccurrence>,
          List<RecurringTransactionOccurrence>>.fromHandlers(
        handleData: (data, sink) => sink.add(data),
        handleError: (error, stackTrace, sink) {
          debugPrint('[streamRecurringOccurrences] fallback empty list: $error');
          sink.add(<RecurringTransactionOccurrence>[]);
        },
      ),
    );
  }

  bool _isPermissionDeniedError(Object e) {
    if (e is FirebaseException && e.code == 'permission-denied') return true;
    final msg = e.toString().toLowerCase();
    return msg.contains('permission-denied') || msg.contains('permission denied');
  }

  // ---------------- SAFE FINANCIAL QUERIES (FOR AI & ASSISTANT) ----------------
  /// Lấy toàn bộ transactions của user bằng single-field index (an toàn tuyệt đối không phụ thuộc composite index)
  Future<List<AppTransaction>> getTransactionsSafely(String userId) async {
    try {
      final snap = await _db
          .collection('transactions')
          .where('userId', isEqualTo: userId)
          .get();
      final list = snap.docs
          .map((d) => AppTransaction.fromMap(d.data(), d.id))
          .toList();
      list.sort((a, b) => b.date.compareTo(a.date));
      return list;
    } catch (e) {
      debugPrint('Error getting transactions safely: $e');
      return [];
    }
  }

  /// Lấy toàn bộ wallets của user an toàn
  Future<List<Wallet>> getWalletsSafely(String userId) async {
    try {
      final snap = await _db
          .collection('wallets')
          .where('userId', isEqualTo: userId)
          .get();
      return snap.docs.map((d) => Wallet.fromMap(d.data(), d.id)).toList();
    } catch (e) {
      debugPrint('Error getting wallets safely: $e');
      return [];
    }
  }

  /// Lấy toàn bộ categories của user an toàn
  Future<List<Category>> getCategoriesSafely(String userId) async {
    try {
      final snap = await _db
          .collection('categories')
          .where('userId', isEqualTo: userId)
          .get();
      return snap.docs.map((d) => Category.fromMap(d.data(), d.id)).toList();
    } catch (e) {
      debugPrint('Error getting categories safely: $e');
      return [];
    }
  }

  /// Lấy toàn bộ budgets của user an toàn
  Future<List<Budget>> getBudgetsSafely(String userId, {String? month}) async {
    try {
      Query<Map<String, dynamic>> query =
          _db.collection('budgets').where('userId', isEqualTo: userId);
      if (month != null) {
        query = query.where('month', isEqualTo: month);
      }
      final snap = await query.get();
      return snap.docs.map((d) => Budget.fromMap(d.data(), d.id)).toList();
    } catch (e) {
      debugPrint('Error getting budgets safely: $e');
      return [];
    }
  }

  /// Lấy toàn bộ savingGoals của user an toàn
  Future<List<SavingGoal>> getSavingGoalsSafely(String userId) async {
    try {
      final snap = await _db
          .collection('savingGoals')
          .where('userId', isEqualTo: userId)
          .get();
      return snap.docs.map((d) => SavingGoal.fromMap(d.data(), d.id)).toList();
    } catch (e) {
      debugPrint('Error getting saving goals safely: $e');
      return [];
    }
  }

  // ---------------- CHAT SESSIONS & CONVERSATION HISTORY ----------------
  /// Lưu hoặc cập nhật một phiên trò chuyện AI
  Future<void> saveChatSession({
    required String userId,
    required String sessionId,
    required String title,
    required List<Map<String, dynamic>> messages,
  }) async {
    try {
      final ref = _db
          .collection('users')
          .doc(userId)
          .collection('chat_sessions')
          .doc(sessionId);

      await ref.set({
        'sessionId': sessionId,
        'userId': userId,
        'title': title,
        'updatedAt': DateTime.now().toIso8601String(),
        'createdAt': FieldValue.serverTimestamp(),
        'messages': messages,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error saving chat session: $e');
    }
  }

  /// Lấy danh sách các phiên trò chuyện của user
  Future<List<Map<String, dynamic>>> getUserChatSessions(String userId) async {
    try {
      final snap = await _db
          .collection('users')
          .doc(userId)
          .collection('chat_sessions')
          .orderBy('updatedAt', descending: true)
          .limit(30)
          .get();

      return snap.docs.map((d) {
        final data = d.data();
        data['sessionId'] = d.id;
        return data;
      }).toList();
    } catch (e) {
      debugPrint('Error getting user chat sessions: $e');
      return [];
    }
  }

  /// Lấy chi tiết một phiên trò chuyện
  Future<Map<String, dynamic>?> getChatSession(String userId, String sessionId) async {
    try {
      final doc = await _db
          .collection('users')
          .doc(userId)
          .collection('chat_sessions')
          .doc(sessionId)
          .get();

      if (!doc.exists) return null;
      final data = doc.data()!;
      data['sessionId'] = doc.id;
      return data;
    } catch (e) {
      debugPrint('Error getting chat session: $e');
      return null;
    }
  }

  /// Xóa một phiên trò chuyện
  Future<void> deleteChatSession(String userId, String sessionId) async {
    try {
      await _db
          .collection('users')
          .doc(userId)
          .collection('chat_sessions')
          .doc(sessionId)
          .delete();
    } catch (e) {
      debugPrint('Error deleting chat session: $e');
    }
  }

  // ---------------- BOUNDED WINDOW QUERIES (PERFORMANCE & INTEGRITY) ----------------
  /// Truy vấn giao dịch trong cửa sổ thời gian xác định [from..to] có phân trang (cursor pagination).
  /// - Tránh tải toàn bộ lịch sử nhiều năm về RAM.
  /// - Tuyệt đối KHÔNG dùng fallback `.limit(400)` gây mất dữ liệu âm thầm.
  /// - Nếu môi trường chưa tạo Composite Index, ném `FirestoreIndexRequiredException` tường minh.
  Future<List<AppTransaction>> getTransactionsByDateWindow(
    String userId, {
    required DateTime from,
    required DateTime to,
    int pageSize = 500,
  }) async {
    final List<AppTransaction> results = [];
    DocumentSnapshot<Map<String, dynamic>>? lastDoc;
    final int safePageSize = pageSize.clamp(50, 1000);

    try {
      while (true) {
        Query<Map<String, dynamic>> query = _db
            .collection('transactions')
            .where('userId', isEqualTo: userId)
            .where('date', isGreaterThanOrEqualTo: from.toIso8601String())
            .where('date', isLessThanOrEqualTo: to.toIso8601String())
            .orderBy('date', descending: true)
            .limit(safePageSize);

        if (lastDoc != null) {
          query = query.startAfterDocument(lastDoc);
        }

        final snap = await query.get();
        if (snap.docs.isEmpty) break;

        for (final doc in snap.docs) {
          results.add(AppTransaction.fromMap(doc.data(), doc.id));
        }

        if (snap.docs.length < safePageSize) {
          break;
        }
        lastDoc = snap.docs.last;
      }
      return results;
    } on FirebaseException catch (e) {
      if (e.code == 'failed-precondition') {
        throw FirestoreIndexRequiredException(
          collection: 'transactions',
          message: AppLocalizations.tr('svc_fs_query_index_err'),
        );
      }
      rethrow;
    }
  }

  // ---------------- MONTHLY FINANCIAL PLANS (CLOSED-LOOP AI PLANNER) ----------------
  static final Set<String> _processedSubmissionTokens = <String>{};
  static final Set<String> _inFlightSubmissionTokens = <String>{};
  static bool _topLevelMonthlyPlansBlocked = false;

  String _buildPlanDocId(String userId, String targetMonth) =>
      '${userId}_${targetMonth.replaceAll('/', '-')}';

  String _buildMonthMapKey(String targetMonth) =>
      targetMonth.replaceAll('/', '-');

  MonthlyFinancialPlan? _extractPlanFromUserMap(
    Map<String, dynamic>? userData,
    String userId,
    String targetMonth,
  ) {
    if (userData == null) return null;
    final plansRaw = userData['monthlyPlans'];
    if (plansRaw is! Map) return null;
    final monthKey = _buildMonthMapKey(targetMonth);
    final entry = plansRaw[monthKey] ?? plansRaw[targetMonth];
    if (entry is! Map) return null;
    final docId = _buildPlanDocId(userId, targetMonth);
    return MonthlyFinancialPlan.fromMap(
      Map<String, dynamic>.from(entry),
      docId,
    );
  }

  MonthlyFinancialPlan _activatePlanIfCurrentMonth(MonthlyFinancialPlan plan) {
    final nowMonthKey = DateFormat('MM/yyyy').format(DateTime.now());
    if (plan.status == PlanLifecycleStatus.approved &&
        plan.targetMonth == nowMonthKey) {
      return plan.copyWith(status: PlanLifecycleStatus.active);
    }
    return plan;
  }

  Future<MonthlyFinancialPlan?> getMonthlyPlan(
    String userId,
    String targetMonth,
  ) async {
    if (userId.isEmpty) return null;
    final docId = _buildPlanDocId(userId, targetMonth);
    MonthlyFinancialPlan? plan;

    final bool shouldTryTopLevel =
        _customDb != null || !_topLevelMonthlyPlansBlocked;

    if (shouldTryTopLevel) {
      try {
        final doc = await _db.collection('monthly_plans').doc(docId).get();
        if (doc.exists && doc.data() != null) {
          plan = MonthlyFinancialPlan.fromMap(doc.data()!, doc.id);
        }
      } catch (e) {
        if (_isPermissionDeniedError(e)) {
          if (_customDb == null) {
            _topLevelMonthlyPlansBlocked = true;
          }
          debugPrint(
            '[getMonthlyPlan] Collection monthly_plans chưa mở quyền trên Cloud Rules -> tự động chuyển sang fallback users/{uid}.monthlyPlans.',
          );
        } else {
          debugPrint('[getMonthlyPlan] Lỗi đọc monthly_plans: $e');
        }
      }
    }

    if (plan == null) {
      try {
        final userDoc = await _db.collection('users').doc(userId).get();
        if (userDoc.exists && userDoc.data() != null) {
          plan = _extractPlanFromUserMap(userDoc.data(), userId, targetMonth);
        }
      } catch (e) {
        debugPrint('[getMonthlyPlan] Lỗi đọc fallback users/{uid}: $e');
      }
    }

    if (plan == null) return null;
    return _activatePlanIfCurrentMonth(plan);
  }

  Stream<MonthlyFinancialPlan?> streamMonthlyPlan(
    String userId,
    String targetMonth,
  ) {
    if (userId.isEmpty) return Stream.value(null);
    final docId = _buildPlanDocId(userId, targetMonth);
    final bool shouldTryTopLevel =
        _customDb != null || !_topLevelMonthlyPlansBlocked;

    if (!shouldTryTopLevel) {
      return _db.collection('users').doc(userId).snapshots().map((userDoc) {
        final p = _extractPlanFromUserMap(userDoc.data(), userId, targetMonth);
        return p != null ? _activatePlanIfCurrentMonth(p) : null;
      }).transform(
        StreamTransformer<MonthlyFinancialPlan?,
            MonthlyFinancialPlan?>.fromHandlers(
          handleData: (data, sink) => sink.add(data),
          handleError: (error, stackTrace, sink) => sink.add(null),
        ),
      );
    }

    return _db
        .collection('monthly_plans')
        .doc(docId)
        .snapshots()
        .map((doc) => doc.exists && doc.data() != null
            ? _activatePlanIfCurrentMonth(
                MonthlyFinancialPlan.fromMap(doc.data()!, doc.id),
              )
            : null)
        .transform(
      StreamTransformer<MonthlyFinancialPlan?,
          MonthlyFinancialPlan?>.fromHandlers(
        handleData: (data, sink) => sink.add(data),
        handleError: (error, stackTrace, sink) {
          if (_isPermissionDeniedError(error) && _customDb == null) {
            _topLevelMonthlyPlansBlocked = true;
          }
          sink.add(null);
        },
      ),
    );
  }

  /// Lưu và áp dụng Kế hoạch Tài chính Tháng trong một Firestore Transaction:
  /// 1. Chống bấm xác nhận lặp (Idempotency / In-flight lock qua `submissionToken`).
  /// 2. Đọc lại toàn bộ `budgets` của `targetMonth` ngay trong Transaction.
  /// 3. Kiểm tra xung đột đồng thời với `expectedExistingBudgets` lúc mở bảng Xem trước.
  /// 4. Chỉ ghi các danh mục được người dùng tích chọn (`selectedCategoryIds`), không tự ý ghi đè mục bỏ chọn.
  /// 5. Lưu `originalSnapshot` bất biến ở lần phê duyệt đầu tiên.
  Future<MonthlyFinancialPlan> commitMonthlyPlanTransactionally({
    required MonthlyFinancialPlan planToCommit,
    required Set<String> selectedCategoryIds,
    required Map<String, double?> expectedExistingBudgets,
    required String submissionToken,
    DateTime? currentReferenceDate,
  }) async {
    if (_inFlightSubmissionTokens.contains(submissionToken) ||
        _processedSubmissionTokens.contains(submissionToken)) {
      final existing =
          await getMonthlyPlan(planToCommit.userId, planToCommit.targetMonth);
      if (existing != null) return existing;
    }

    _inFlightSubmissionTokens.add(submissionToken);
    try {
      final now = currentReferenceDate ?? DateTime.now();
      final currentMonthStr = DateFormat('MM/yyyy').format(now);
      final PlanLifecycleStatus resolvedStatus =
          planToCommit.targetMonth == currentMonthStr
              ? PlanLifecycleStatus.active
              : PlanLifecycleStatus.approved;

      final planDocId =
          _buildPlanDocId(planToCommit.userId, planToCommit.targetMonth);
      final monthKey = _buildMonthMapKey(planToCommit.targetMonth);
      final planRef = _db.collection('monthly_plans').doc(planDocId);
      final userRef = _db.collection('users').doc(planToCommit.userId);

      // Truy vấn danh sách document ngân sách hiện tại của tháng mục tiêu
      final existingBudgetQuery = await _db
          .collection('budgets')
          .where('userId', isEqualTo: planToCommit.userId)
          .where('month', isEqualTo: planToCommit.targetMonth)
          .get();

      Future<MonthlyFinancialPlan> executeCommitTxn({
        required bool useTopLevelPlanCollection,
      }) async {
        return await _db.runTransaction<MonthlyFinancialPlan>(
          (txn) async {
            MonthlyFinancialPlan? oldPlan;
            if (useTopLevelPlanCollection) {
              final existingPlanSnap = await txn.get(planRef);
              if (existingPlanSnap.exists && existingPlanSnap.data() != null) {
                oldPlan = MonthlyFinancialPlan.fromMap(
                  existingPlanSnap.data()!,
                  existingPlanSnap.id,
                );
              }
            } else {
              final userSnap = await txn.get(userRef);
              if (userSnap.exists && userSnap.data() != null) {
                oldPlan = _extractPlanFromUserMap(
                  userSnap.data(),
                  planToCommit.userId,
                  planToCommit.targetMonth,
                );
              }
            }

            // Đọc lại từng budget doc bên trong Transaction để đảm bảo tính cô lập
            final Map<String, DocumentSnapshot<Map<String, dynamic>>>
                latestBudgetDocsByCat = {};
            final Map<String, double?> latestLimitsByCat = {};

            for (final qDoc in existingBudgetQuery.docs) {
              final freshSnap = await txn.get(qDoc.reference);
              if (freshSnap.exists && freshSnap.data() != null) {
                final b = Budget.fromMap(freshSnap.data()!, freshSnap.id);
                latestBudgetDocsByCat[b.categoryId] = freshSnap;
                latestLimitsByCat[b.categoryId] = b.limit;
              }
            }

            // Kiểm tra xung đột (Optimistic Concurrency Check) cho các danh mục được chọn áp dụng
            final List<String> conflicts = [];
            for (final catId in selectedCategoryIds) {
              final expectedLimit = expectedExistingBudgets[catId];
              final actualLimit = latestLimitsByCat[catId];
              final bool bothNull = expectedLimit == null && actualLimit == null;
              final bool bothEqual = expectedLimit != null &&
                  actualLimit != null &&
                  (expectedLimit - actualLimit).abs() < 0.01;
              if (!bothNull && !bothEqual) {
                conflicts.add(catId);
              }
            }

            if (conflicts.isNotEmpty) {
              throw PlanBudgetConflictException(
                message:
                    AppLocalizations.tr('svc_fs_plan_conflict', params: {'count': '${conflicts.length}'}),
                conflictingCategoryIds: conflicts,
                latestBudgetsByCategory: latestLimitsByCat,
              );
            }

            // Bảo toàn originalSnapshot nếu kế hoạch của tháng này đã từng được phê duyệt trước đó
            PlanSnapshotData originalSnapshotToKeep =
                planToCommit.originalSnapshot;
            int nextRevision = 1;
            List<PlanAdjustmentLog> historyToKeep =
                planToCommit.adjustmentHistory;
            final Set<String> mergedSelectedIds = {...selectedCategoryIds};

            if (oldPlan != null) {
              if (oldPlan.status != PlanLifecycleStatus.draft) {
                originalSnapshotToKeep = oldPlan.originalSnapshot;
              }
              nextRevision = oldPlan.revision + 1;
              historyToKeep = oldPlan.adjustmentHistory;
              for (final prevId in oldPlan.selectedCategoryIds) {
                if (latestBudgetDocsByCat.containsKey(prevId)) {
                  mergedSelectedIds.add(prevId);
                }
              }
            }

            final finalizedPlan = planToCommit.copyWith(
              planId: planDocId,
              status: resolvedStatus,
              selectedCategoryIds: mergedSelectedIds.toList(),
              originalSnapshot: originalSnapshotToKeep,
              adjustmentHistory: historyToKeep,
              revision: nextRevision,
              updatedAt: now,
            );

            if (useTopLevelPlanCollection) {
              txn.set(planRef, finalizedPlan.toMap());
            } else {
              txn.set(
                userRef,
                {
                  'monthlyPlans': {
                    monthKey: finalizedPlan.toMap(),
                  },
                },
                SetOptions(merge: true),
              );
            }

            // Chỉ tạo mới hoặc cập nhật Budget cho những danh mục người dùng ĐÃ TÍCH CHỌN
            for (final alloc in finalizedPlan.currentAllocations) {
              if (!selectedCategoryIds.contains(alloc.categoryId)) {
                continue;
              }
              final existingDoc = latestBudgetDocsByCat[alloc.categoryId];
              if (existingDoc != null) {
                final existingBudgetObj = Budget.fromMap(
                  existingDoc.data()!,
                  existingDoc.id,
                );
                final bool alreadyOwnedByThisPlan =
                    existingBudgetObj.sourcePlanId == planDocId;
                txn.update(existingDoc.reference, {
                  'limit': alloc.recommendedLimit,
                  'sourcePlanId': planDocId,
                  'isManual': false,
                  if (!alreadyOwnedByThisPlan)
                    'prePlanLimit': existingBudgetObj.limit,
                });
              } else {
                final newBudgetRef = _db.collection('budgets').doc();
                final newBudget = Budget(
                  budgetId: newBudgetRef.id,
                  userId: finalizedPlan.userId,
                  categoryId: alloc.categoryId,
                  limit: alloc.recommendedLimit,
                  month: finalizedPlan.targetMonth,
                  sourcePlanId: planDocId,
                  prePlanLimit: null,
                  isManual: false,
                );
                txn.set(newBudgetRef, newBudget.toMap());
              }
            }

            return finalizedPlan;
          },
        );
      }

      MonthlyFinancialPlan committedPlan;
      final bool shouldTryTopLevel =
          _customDb != null || !_topLevelMonthlyPlansBlocked;

      if (shouldTryTopLevel) {
        try {
          committedPlan =
              await executeCommitTxn(useTopLevelPlanCollection: true);
        } catch (e) {
          if (_isPermissionDeniedError(e)) {
            if (_customDb == null) {
              _topLevelMonthlyPlansBlocked = true;
            }
            committedPlan =
                await executeCommitTxn(useTopLevelPlanCollection: false);
          } else {
            rethrow;
          }
        }
      } else {
        committedPlan =
            await executeCommitTxn(useTopLevelPlanCollection: false);
      }

      _processedSubmissionTokens.add(submissionToken);
      FinancialContextRevisionTracker.notifyDataMutated();
      return committedPlan;
    } finally {
      _inFlightSubmissionTokens.remove(submissionToken);
    }
  }

  /// Điều chỉnh kế hoạch giữa tháng khi phát sinh chi phí ngoài dự kiến (Rebalance).
  /// - Giữ nguyên tuyệt đối `originalSnapshot` (bản kế hoạch gốc).
  /// - Nối thêm `PlanAdjustmentLog` vào `adjustmentHistory` và tăng `revision`.
  /// - TUYỆT ĐỐI KHÔNG chỉnh sửa document `SavingGoal` gốc khi người dùng điều chỉnh `targetSavingAmount` của tháng.
  Future<MonthlyFinancialPlan> rebalanceMonthlyPlanTransactionally({
    required String userId,
    required String targetMonth,
    required List<PlannedCategoryAllocation> updatedAllocations,
    required double updatedTargetSaving,
    required double updatedReferenceIncome,
    required String reason,
    required String strategy,
    required String summary,
    Set<String>? categoryIdsToSyncBudget,
  }) async {
    final planDocId = _buildPlanDocId(userId, targetMonth);
    final monthKey = _buildMonthMapKey(targetMonth);
    final planRef = _db.collection('monthly_plans').doc(planDocId);
    final userRef = _db.collection('users').doc(userId);

    final existingBudgetQuery = await _db
        .collection('budgets')
        .where('userId', isEqualTo: userId)
        .where('month', isEqualTo: targetMonth)
        .get();

    Future<MonthlyFinancialPlan> executeRebalanceTxn({
      required bool useTopLevelPlanCollection,
    }) async {
      return await _db.runTransaction<MonthlyFinancialPlan>(
        (txn) async {
          MonthlyFinancialPlan? currentPlan;
          if (useTopLevelPlanCollection) {
            final planSnap = await txn.get(planRef);
            if (planSnap.exists && planSnap.data() != null) {
              currentPlan =
                  MonthlyFinancialPlan.fromMap(planSnap.data()!, planSnap.id);
            }
          } else {
            final userSnap = await txn.get(userRef);
            if (userSnap.exists && userSnap.data() != null) {
              currentPlan = _extractPlanFromUserMap(
                userSnap.data(),
                userId,
                targetMonth,
              );
            }
          }

          if (currentPlan == null) {
            throw Exception(
                AppLocalizations.tr('svc_fs_plan_not_found', params: {'month': targetMonth}));
          }

          final Map<String, DocumentSnapshot<Map<String, dynamic>>>
              budgetDocsByCat = {};
          for (final qDoc in existingBudgetQuery.docs) {
            final bSnap = await txn.get(qDoc.reference);
            if (bSnap.exists && bSnap.data() != null) {
              final b = Budget.fromMap(bSnap.data()!, bSnap.id);
              budgetDocsByCat[b.categoryId] = bSnap;
            }
          }

          final double newEssentialCap = updatedAllocations
              .where((a) => a.isEssential)
              .fold<double>(0, (s, a) => s + a.recommendedLimit);
          final double newFlexibleCap = updatedAllocations
              .where((a) => !a.isEssential)
              .fold<double>(0, (s, a) => s + a.recommendedLimit);

          final now = DateTime.now();
          final newLog = PlanAdjustmentLog(
            adjustedAt: now,
            reason: reason,
            strategy: strategy,
            previousTargetSaving: currentPlan.targetSavingAmount,
            newTargetSaving: updatedTargetSaving,
            summary: summary,
          );

          final nextPlan = currentPlan.copyWith(
            referenceIncome: updatedReferenceIncome,
            essentialExpenseCap: newEssentialCap,
            flexibleExpenseCap: newFlexibleCap,
            targetSavingAmount: updatedTargetSaving,
            currentAllocations: updatedAllocations,
            // Giữ nguyên originalSnapshot gốc 100%
            originalSnapshot: currentPlan.originalSnapshot,
            adjustmentHistory: [...currentPlan.adjustmentHistory, newLog],
            revision: currentPlan.revision + 1,
            updatedAt: now,
          );

          if (useTopLevelPlanCollection) {
            txn.set(planRef, nextPlan.toMap());
          } else {
            txn.set(
              userRef,
              {
                'monthlyPlans': {
                  monthKey: nextPlan.toMap(),
                },
              },
              SetOptions(merge: true),
            );
          }

          // Đồng bộ lại các Budget của các danh mục được điều chỉnh
          final idsToSync = categoryIdsToSyncBudget ??
              updatedAllocations.map((e) => e.categoryId).toSet();
          for (final alloc in updatedAllocations) {
            if (!idsToSync.contains(alloc.categoryId)) continue;
            final bDoc = budgetDocsByCat[alloc.categoryId];
            if (bDoc != null) {
              txn.update(bDoc.reference, {'limit': alloc.recommendedLimit});
            }
          }

          return nextPlan;
        },
      );
    }

    MonthlyFinancialPlan updatedPlan;
    final bool shouldTryTopLevel =
        _customDb != null || !_topLevelMonthlyPlansBlocked;

    if (shouldTryTopLevel) {
      try {
        updatedPlan =
            await executeRebalanceTxn(useTopLevelPlanCollection: true);
      } catch (e) {
        if (_isPermissionDeniedError(e)) {
          if (_customDb == null) {
            _topLevelMonthlyPlansBlocked = true;
          }
          updatedPlan =
              await executeRebalanceTxn(useTopLevelPlanCollection: false);
        } else {
          rethrow;
        }
      }
    } else {
      updatedPlan =
          await executeRebalanceTxn(useTopLevelPlanCollection: false);
    }

    FinancialContextRevisionTracker.notifyDataMutated();
    return updatedPlan;
  }

  DateTime? _tryParseMonthYear(String mmYyyy) {
    final parts = mmYyyy.split('/');
    if (parts.length != 2) return null;
    final int? month = int.tryParse(parts[0].trim());
    final int? year = int.tryParse(parts[1].trim());
    if (month == null || year == null || month < 1 || month > 12) return null;
    return DateTime(year, month, 1);
  }

  double _computeUpdatedPlanSavingTarget({
    required MonthlyFinancialPlan basePlan,
    required double essentialCap,
    required double flexibleCap,
    required bool isEssentialDeficit,
  }) {
    if (basePlan.referenceIncome <= 0 ||
        basePlan.incomeMode == IncomeStabilityMode.noIncomeBasis ||
        isEssentialDeficit) {
      return 0.0;
    }
    final double maxAchievable = math.max(
      0.0,
      basePlan.referenceIncome - essentialCap - flexibleCap,
    );
    final double origMaxAchievable = math.max(
      0.0,
      basePlan.referenceIncome -
          basePlan.essentialExpenseCap -
          basePlan.flexibleExpenseCap,
    );
    if (basePlan.desiredGoalSavingAmount > 0 &&
        (basePlan.targetSavingAmount - origMaxAchievable).abs() > 10.0 &&
        basePlan.desiredGoalSavingAmount < maxAchievable) {
      return basePlan.desiredGoalSavingAmount;
    }
    return maxAchievable;
  }

  /// Đồng bộ lại các Kế hoạch Tháng tương lai (`status == approved` / `draft`,
  /// `targetMonth` sau `sourceMonth` và sau tháng hiện tại) cùng các Hạn mức (Budget)
  /// do kế hoạch đó tạo ra khi giao dịch chi tiêu ở `sourceMonth` bị xóa hoặc giảm.
  Future<void> _syncFutureMonthlyPlansAfterSourceExpenseChange({
    required String userId,
    required String sourceMonth,
    required Set<String> affectedCategoryIds,
    DateTime? currentReferenceDate,
  }) async {
    if (userId.isEmpty || affectedCategoryIds.isEmpty) return;
    final DateTime? sourceMonthDate = _tryParseMonthYear(sourceMonth);
    if (sourceMonthDate == null) return;

    final DateTime nowRef = currentReferenceDate ?? DateTime.now();
    final DateTime currentMonthDate = DateTime(nowRef.year, nowRef.month, 1);

    final bool shouldTryTopLevel =
        _customDb != null || !_topLevelMonthlyPlansBlocked;

    final Map<String, MonthlyFinancialPlan> candidatePlans = {};
    final Set<String> topLevelDocIds = {};
    final Set<String> userMapPlanIds = {};
    Map<String, dynamic>? userMonthlyPlansMap;
    final userRef = _db.collection('users').doc(userId);

    bool isSyncableFuturePlan(MonthlyFinancialPlan p) {
      if (p.sourceMonth != sourceMonth) return false;
      if (p.status != PlanLifecycleStatus.approved &&
          p.status != PlanLifecycleStatus.draft) {
        return false;
      }
      final targetDate = _tryParseMonthYear(p.targetMonth);
      if (targetDate == null) return false;
      return targetDate.isAfter(sourceMonthDate) &&
          targetDate.isAfter(currentMonthDate);
    }

    if (shouldTryTopLevel) {
      try {
        final planSnap = await _db
            .collection('monthly_plans')
            .where('userId', isEqualTo: userId)
            .get();
        for (final doc in planSnap.docs) {
          final p = MonthlyFinancialPlan.fromMap(doc.data(), doc.id);
          if (isSyncableFuturePlan(p)) {
            candidatePlans[p.planId] = p;
            topLevelDocIds.add(doc.id);
          }
        }
      } catch (e) {
        if (_isPermissionDeniedError(e) && _customDb == null) {
          _topLevelMonthlyPlansBlocked = true;
        }
      }
    }

    try {
      final userSnap = await userRef.get();
      final userData = userSnap.data();
      final rawPlans = userData?['monthlyPlans'];
      if (rawPlans is Map) {
        userMonthlyPlansMap = Map<String, dynamic>.from(rawPlans);
        for (final entry in userMonthlyPlansMap.entries) {
          if (entry.value is! Map) continue;
          final rawMap = Map<String, dynamic>.from(entry.value as Map);
          final targetM = (rawMap['targetMonth'] ?? '').toString();
          final docId = targetM.isNotEmpty
              ? _buildPlanDocId(userId, targetM)
              : '${userId}_${entry.key}';
          final p = MonthlyFinancialPlan.fromMap(rawMap, docId);
          if (isSyncableFuturePlan(p)) {
            candidatePlans.putIfAbsent(p.planId, () => p);
            userMapPlanIds.add(p.planId);
          }
        }
      }
    } catch (e) {
      debugPrint('[_syncFutureMonthlyPlans] Lỗi đọc fallback users/{uid}: $e');
    }

    if (candidatePlans.isEmpty) return;

    // Tính lại tổng thực chi từng danh mục còn lại ở sourceMonth
    final monthStart = DateTime(sourceMonthDate.year, sourceMonthDate.month, 1);
    final monthEnd = DateTime(
      sourceMonthDate.year,
      sourceMonthDate.month + 1,
      0,
      23,
      59,
      59,
      999,
    );

    List<AppTransaction> sourceMonthTx;
    try {
      sourceMonthTx = await getTransactionsByDateWindow(
        userId,
        from: monthStart,
        to: monthEnd,
      );
    } catch (_) {
      sourceMonthTx = await getTransactionsSafely(userId);
    }

    final Map<String, double> remainingSpentByCat = {};
    for (final tx in sourceMonthTx) {
      if (tx.type == 'expense' &&
          DateFormat('MM/yyyy').format(tx.date) == sourceMonth) {
        remainingSpentByCat[tx.categoryId] =
            (remainingSpentByCat[tx.categoryId] ?? 0) + tx.amount;
      }
    }

    for (final plan in candidatePlans.values) {
      final budgetQuery = await _db
          .collection('budgets')
          .where('userId', isEqualTo: userId)
          .where('month', isEqualTo: plan.targetMonth)
          .get();

      final Map<String, QueryDocumentSnapshot<Map<String, dynamic>>>
          budgetDocByCat = {};
      final Set<String> budgetOwnedCatIds = {};

      for (final bDoc in budgetQuery.docs) {
        final b = Budget.fromMap(bDoc.data(), bDoc.id);
        budgetDocByCat[b.categoryId] = bDoc;
        if (b.sourcePlanId == plan.planId) {
          budgetOwnedCatIds.add(b.categoryId);
        }
      }

      final Map<String, PlannedCategoryAllocation> originalByCat = {
        for (final a in plan.originalSnapshot.allocations) a.categoryId: a,
      };
      final Set<String> effectiveSelectedIds = {
        ...plan.selectedCategoryIds,
        ...budgetOwnedCatIds,
      };
      final Set<String> updatedSelectedIds = {...effectiveSelectedIds};

      final List<PlannedCategoryAllocation> updatedAllocations = [];
      final List<PlannedCategoryAllocation> updatedOriginalAllocations = [];
      bool planChanged = false;
      bool budgetMutations = false;

      final WriteBatch batch = _db.batch();

      for (final alloc in plan.currentAllocations) {
        final origAlloc = originalByCat[alloc.categoryId];

        if (!affectedCategoryIds.contains(alloc.categoryId)) {
          updatedAllocations.add(alloc);
          if (origAlloc != null) {
            updatedOriginalAllocations.add(origAlloc);
          }
          continue;
        }

        final double remainingSpent =
            remainingSpentByCat[alloc.categoryId] ?? 0.0;

        if (remainingSpent >= alloc.sourceMonthSpent - 0.01) {
          updatedAllocations.add(alloc);
          if (origAlloc != null) {
            updatedOriginalAllocations.add(origAlloc);
          }
          continue;
        }

        final budgetSnap = budgetDocByCat[alloc.categoryId];
        final Budget? budgetObj = budgetSnap != null
            ? Budget.fromMap(budgetSnap.data(), budgetSnap.id)
            : null;
        final bool budgetManagedByPlan = budgetObj != null &&
            (budgetObj.sourcePlanId == plan.planId ||
                (budgetObj.sourcePlanId == null &&
                    !budgetObj.isManual &&
                    origAlloc != null &&
                    origAlloc.existingBudget == null &&
                    (budgetObj.limit - alloc.recommendedLimit).abs() < 0.01 &&
                    (effectiveSelectedIds.isEmpty ||
                        effectiveSelectedIds.contains(alloc.categoryId))));

        if (remainingSpent <= 0) {
          if (budgetSnap != null && budgetManagedByPlan) {
            if (budgetObj.prePlanLimit != null && budgetObj.prePlanLimit! > 0) {
              final double restoredLimit = budgetObj.prePlanLimit!;
              batch.update(budgetSnap.reference, {
                'limit': restoredLimit,
                'sourcePlanId': null,
                'prePlanLimit': null,
                'isManual': true,
              });
              budgetMutations = true;
              updatedAllocations.add(alloc.copyWith(
                sourceMonthSpent: 0,
                regularBaselineSpent: 0,
                recommendedLimit: restoredLimit,
              ));
              if (origAlloc != null) {
                updatedOriginalAllocations.add(origAlloc.copyWith(
                  sourceMonthSpent: 0,
                  regularBaselineSpent: 0,
                  recommendedLimit: restoredLimit,
                ));
              }
              planChanged = true;
            } else {
              batch.delete(budgetSnap.reference);
              budgetMutations = true;
              updatedSelectedIds.remove(alloc.categoryId);
              planChanged = true;
            }
          } else if (budgetSnap == null) {
            updatedSelectedIds.remove(alloc.categoryId);
            planChanged = true;
          } else {
            // Ngân sách đang được người dùng giữ/chỉnh sửa thủ công -> không xóa ngân sách,
            // chỉ đồng bộ sourceMonthSpent thực tế về 0.
            updatedAllocations.add(alloc.copyWith(
              sourceMonthSpent: 0,
              regularBaselineSpent: 0,
              recommendedLimit: budgetObj!.limit,
            ));
            if (origAlloc != null) {
              updatedOriginalAllocations.add(origAlloc.copyWith(
                sourceMonthSpent: 0,
                regularBaselineSpent: 0,
              ));
            }
            planChanged = true;
          }
          continue;
        }

        // Trường hợp còn lại: 0 < remainingSpent < alloc.sourceMonthSpent
        double newLimit;
        if ((alloc.recommendedLimit - alloc.sourceMonthSpent).abs() < 1.0) {
          newLimit = remainingSpent;
        } else if (alloc.sourceMonthSpent > 0) {
          final double scaled = remainingSpent *
              (alloc.recommendedLimit / alloc.sourceMonthSpent);
          newLimit = scaled < 10000
              ? scaled.roundToDouble()
              : ((scaled / 10000).round() * 10000).toDouble();
          if (newLimit <= 0) newLimit = remainingSpent;
        } else {
          newLimit = remainingSpent;
        }

        if (budgetSnap != null && budgetManagedByPlan) {
          batch.update(budgetSnap.reference, {'limit': newLimit});
          budgetMutations = true;
        }

        updatedAllocations.add(alloc.copyWith(
          sourceMonthSpent: remainingSpent,
          regularBaselineSpent: remainingSpent,
          recommendedLimit: newLimit,
        ));
        if (origAlloc != null) {
          updatedOriginalAllocations.add(origAlloc.copyWith(
            sourceMonthSpent: remainingSpent,
            regularBaselineSpent: remainingSpent,
            recommendedLimit: newLimit,
          ));
        }
        planChanged = true;
      }

      if (!planChanged && !budgetMutations) continue;

      final bool hadExplicitSelection = effectiveSelectedIds.isNotEmpty;
      final bool shouldDeletePlan = updatedAllocations.isEmpty ||
          (hadExplicitSelection && updatedSelectedIds.isEmpty);

      final monthKey = _buildMonthMapKey(plan.targetMonth);

      if (shouldDeletePlan) {
        if (topLevelDocIds.contains(plan.planId)) {
          batch.delete(_db.collection('monthly_plans').doc(plan.planId));
        }
        if (userMapPlanIds.contains(plan.planId) &&
            userMonthlyPlansMap != null) {
          userMonthlyPlansMap.remove(monthKey);
          userMonthlyPlansMap.remove(plan.targetMonth);
          batch.update(userRef, {
            'monthlyPlans': Map<String, dynamic>.from(userMonthlyPlansMap),
          });
        }
      } else {
        final double newEssCap = updatedAllocations
            .where((a) => a.isEssential)
            .fold<double>(0, (s, a) => s + a.recommendedLimit);
        final double newFlexCap = updatedAllocations
            .where((a) => !a.isEssential)
            .fold<double>(0, (s, a) => s + a.recommendedLimit);
        final bool newEssDeficit =
            plan.referenceIncome > 0 && newEssCap >= plan.referenceIncome;
        final double newSaving = _computeUpdatedPlanSavingTarget(
          basePlan: plan,
          essentialCap: newEssCap,
          flexibleCap: newFlexCap,
          isEssentialDeficit: newEssDeficit,
        );
        final bool newGoalFeasible =
            plan.desiredGoalSavingAmount <= newSaving + 1000.0;
        final double newInfeasibleGap = newGoalFeasible
            ? 0.0
            : math.max(0.0, plan.desiredGoalSavingAmount - newSaving);

        final double origEssCap = updatedOriginalAllocations
            .where((a) => a.isEssential)
            .fold<double>(0, (s, a) => s + a.recommendedLimit);
        final double origFlexCap = updatedOriginalAllocations
            .where((a) => !a.isEssential)
            .fold<double>(0, (s, a) => s + a.recommendedLimit);
        final bool origEssDeficit =
            plan.referenceIncome > 0 && origEssCap >= plan.referenceIncome;
        final double origSaving = _computeUpdatedPlanSavingTarget(
          basePlan: plan,
          essentialCap: origEssCap,
          flexibleCap: origFlexCap,
          isEssentialDeficit: origEssDeficit,
        );

        final updatedOriginalSnapshot = plan.originalSnapshot.copyWith(
          essentialExpenseTotal: origEssCap,
          flexibleExpenseTotal: origFlexCap,
          targetSavingAmount: origSaving,
          allocations: updatedOriginalAllocations,
        );

        final nextPlan = plan.copyWith(
          essentialExpenseCap: newEssCap,
          flexibleExpenseCap: newFlexCap,
          targetSavingAmount: newSaving,
          isEssentialDeficit: newEssDeficit,
          isSavingGoalFeasible: newGoalFeasible,
          infeasibleSavingGap: newInfeasibleGap,
          currentAllocations: updatedAllocations,
          selectedCategoryIds: updatedSelectedIds.toList(),
          originalSnapshot: updatedOriginalSnapshot,
          updatedAt: DateTime.now(),
        );

        if (topLevelDocIds.contains(plan.planId)) {
          batch.set(
            _db.collection('monthly_plans').doc(plan.planId),
            nextPlan.toMap(),
          );
        }
        if (userMapPlanIds.contains(plan.planId) &&
            userMonthlyPlansMap != null) {
          userMonthlyPlansMap[monthKey] = nextPlan.toMap();
          batch.update(userRef, {
            'monthlyPlans': Map<String, dynamic>.from(userMonthlyPlansMap),
          });
        }
      }

      await batch.commit();
    }
  }

  // ---------------- ADMIN OPERATIONS (USERS, SYSTEM CATEGORIES, ANNOUNCEMENTS, AUDIT LOGS) ----------------
  Stream<List<AppUser>> streamAllUsersForAdmin() {
    return _db.collection('users').snapshots().map((snap) {
      final list =
          snap.docs.map((d) => AppUser.fromMap(d.data(), d.id)).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  Future<void> updateUserStatusOrRoleByAdmin({
    required String targetUid,
    String? status,
    String? role,
  }) async {
    final Map<String, dynamic> updates = {};
    if (status != null) updates['status'] = status;
    if (role != null) updates['role'] = role;
    if (updates.isEmpty) return;

    await _db.collection('users').doc(targetUid).update(updates);
  }

  Stream<List<SystemCategoryTemplate>> streamSystemCategoryTemplates() {
    return _db
        .collection('system_categories')
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => SystemCategoryTemplate.fromMap(d.data(), d.id))
            .toList())
        .transform(
      StreamTransformer<List<SystemCategoryTemplate>,
          List<SystemCategoryTemplate>>.fromHandlers(
        handleData: (data, sink) => sink.add(data),
        handleError: (error, stackTrace, sink) {
          debugPrint('[streamSystemCategoryTemplates] fallback empty: $error');
          sink.add(<SystemCategoryTemplate>[]);
        },
      ),
    );
  }

  Future<List<SystemCategoryTemplate>> getSystemCategoryTemplates() async {
    try {
      final snap = await _db.collection('system_categories').get();
      return snap.docs
          .map((d) => SystemCategoryTemplate.fromMap(d.data(), d.id))
          .where((t) => t.isActive)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Truy vấn danh mục hệ thống cho màn hình khởi tạo User mới (CategorySetupScreen).
  /// Phân biệt tường minh giữa:
  /// - Truy cập Firestore thành công (kể cả khi collection rỗng hoặc toàn bộ danh mục bị ẩn do Admin cấu hình).
  /// - Không thể truy cập nguồn dữ liệu từ Firestore (ném lỗi kết nối/quyền) để chỉ fallback về constants.dart khi lỗi truy cập.
  Future<SystemCategoriesSetupResult> fetchSystemCategoriesForSetup() async {
    try {
      final snap = await _db.collection('system_categories').get();
      final allTemplates = snap.docs
          .map((d) => SystemCategoryTemplate.fromMap(d.data(), d.id))
          .toList();
      final activeTemplates =
          allTemplates.where((t) => t.isActive).toList();
      return SystemCategoriesSetupResult(
        activeTemplates: activeTemplates,
        totalDocsInCollection: allTemplates.length,
        isFirestoreAccessible: true,
      );
    } catch (e) {
      debugPrint('[fetchSystemCategoriesForSetup] Firestore unreachable: $e');
      return const SystemCategoriesSetupResult(
        activeTemplates: [],
        totalDocsInCollection: 0,
        isFirestoreAccessible: false,
      );
    }
  }

  Future<String> saveSystemCategoryTemplate(
    SystemCategoryTemplate template,
  ) async {
    String docId = template.id;
    final payload = template
        .copyWith(
          createdAt: template.createdAt ?? DateTime.now(),
          updatedAt: DateTime.now(),
        )
        .toMap();

    if (docId.isEmpty) {
      final ref = await _db.collection('system_categories').add(payload);
      docId = ref.id;
    } else {
      await _db
          .collection('system_categories')
          .doc(docId)
          .set(payload, SetOptions(merge: true));
    }
    return docId;
  }

  /// Ẩn hoặc hiện danh mục hệ thống thông qua trường `isActive`
  /// (Không xóa cứng để bảo toàn tham chiếu và dữ liệu lịch sử).
  Future<void> setSystemCategoryActive(
    String id,
    bool isActive,
  ) async {
    await _db.collection('system_categories').doc(id).update({
      'isActive': isActive,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  Future<void> deleteSystemCategoryTemplate(String id) async {
    await _db.collection('system_categories').doc(id).delete();
  }

  Stream<List<SystemAnnouncement>> streamSystemAnnouncements({
    bool activeOnly = false,
  }) {
    return _db
        .collection('system_announcements')
        .snapshots()
        .map((snap) {
      var list = snap.docs
          .map((d) => SystemAnnouncement.fromMap(d.data(), d.id))
          .toList();
      if (activeOnly) {
        list = list.where((a) => a.isActive).toList();
      }
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    }).transform(
      StreamTransformer<List<SystemAnnouncement>,
          List<SystemAnnouncement>>.fromHandlers(
        handleData: (data, sink) => sink.add(data),
        handleError: (error, stackTrace, sink) {
          debugPrint('[streamSystemAnnouncements] fallback empty: $error');
          sink.add(<SystemAnnouncement>[]);
        },
      ),
    );
  }

  Future<String> saveSystemAnnouncement(
    SystemAnnouncement announcement,
  ) async {
    String docId = announcement.id;
    final payload = announcement
        .copyWith(updatedAt: DateTime.now())
        .toMap();

    if (docId.isEmpty) {
      final ref = await _db.collection('system_announcements').add(payload);
      docId = ref.id;
    } else {
      await _db
          .collection('system_announcements')
          .doc(docId)
          .set(payload, SetOptions(merge: true));
    }
    return docId;
  }

  Future<void> setSystemAnnouncementActive(
    String id,
    bool isActive,
  ) async {
    await _db.collection('system_announcements').doc(id).update({
      'isActive': isActive,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  Future<void> deleteSystemAnnouncement(String id) async {
    await _db.collection('system_announcements').doc(id).delete();
  }

  // ---------------- ADMIN AUDIT LOGS (READ ONLY TRÊN CLIENT - SERVER GHI) ----------------
  Stream<List<AdminAuditLog>> streamAdminAuditLogs({int limit = 100}) {
    return _db
        .collection('admin_logs')
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => AdminAuditLog.fromMap(d.data(), d.id))
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (list.length > limit) {
        return list.sublist(0, limit);
      }
      return list;
    }).transform(
      StreamTransformer<List<AdminAuditLog>,
          List<AdminAuditLog>>.fromHandlers(
        handleData: (data, sink) => sink.add(data),
        handleError: (error, stackTrace, sink) {
          debugPrint('[streamAdminAuditLogs] fallback empty: $error');
          sink.add(<AdminAuditLog>[]);
        },
      ),
    );
  }
}

/// Kết quả truy vấn danh mục mẫu hệ thống phục vụ khởi tạo cho User mới.
class SystemCategoriesSetupResult {
  final List<SystemCategoryTemplate> activeTemplates;
  final int totalDocsInCollection;
  final bool isFirestoreAccessible;

  const SystemCategoriesSetupResult({
    required this.activeTemplates,
    required this.totalDocsInCollection,
    required this.isFirestoreAccessible,
  });
}

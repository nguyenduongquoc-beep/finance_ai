import 'dart:async';
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
import '../models/ai_runtime_config_model.dart';
import '../utils/formatters.dart';
import 'ai_config_sync_service.dart';
import 'financial_context_revision_tracker.dart';
import 'local_notification_service.dart';
import 'recurring_transaction_service.dart';
import 'storage_service.dart';
import '../utils/transaction_business_logic.dart';

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

  Future<void> updateUserProfile(String uid, Map<String, dynamic> data) {
    return _db.collection('users').doc(uid).update(data);
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
      throw Exception('Ví nguồn không tồn tại');
    }
    final oldBalance = (oldWalletDoc.data()!['balance'] as num).toDouble();
    final newWalletDoc = await _db.collection('wallets').doc(newWalletId).get();
    final newWalletName =
        newWalletDoc.data()?['walletName']?.toString() ?? 'Ví thanh toán';

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
        throw Exception('Giao dịch chuyển tiền cần chỉ định ví đích.');
      }
      if (tx.toWalletId == tx.walletId) {
        throw Exception('Ví nguồn và ví đích không được trùng nhau.');
      }
      toWalletRef = _db.collection('wallets').doc(tx.toWalletId);
    }

    DocumentReference? goalRef;
    if (tx.type == 'goal_deposit' || tx.type == 'goal_withdraw') {
      if (tx.goalId == null || tx.goalId!.isEmpty) {
        throw Exception('Giao dịch mục tiêu tiết kiệm cần chỉ định mục tiêu.');
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
      if (!walletSnap.exists) throw Exception('Ví không tồn tại.');
      final wallet = Wallet.fromMap(
          walletSnap.data() as Map<String, dynamic>, walletSnap.id);

      Wallet? toWallet;
      if (toWalletRef != null) {
        final toWalletSnap = await transaction.get(toWalletRef);
        if (!toWalletSnap.exists) throw Exception('Ví đích không tồn tại.');
        toWallet = Wallet.fromMap(
            toWalletSnap.data() as Map<String, dynamic>, toWalletSnap.id);
      }

      SavingGoal? goal;
      if (goalRef != null) {
        final goalSnap = await transaction.get(goalRef);
        if (!goalSnap.exists) {
          throw Exception('Mục tiêu tiết kiệm không tồn tại.');
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
              title: 'Cảnh báo ngân sách',
              content:
                  'Bạn đã tiêu vượt 80% ngân sách tháng $monthStr cho danh mục này.',
              status: 'unread',
              type: 'budget',
              createdAt: DateTime.now(),
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
    AppTransaction newTx,
  ) async {
    if (oldTx.type == 'goal_deposit' ||
        oldTx.type == 'goal_withdraw' ||
        newTx.type == 'goal_deposit' ||
        newTx.type == 'goal_withdraw') {
      throw Exception(
          'Giao dịch nạp/rút mục tiêu không thể sửa. Vui lòng xóa và tạo lại giao dịch.');
    }

    TransactionBusinessLogic.validateAmount(newTx.amount);

    final monthStrNew = DateFormat('MM/yyyy').format(newTx.date);

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
      if (!oldWalletSnap.exists) throw Exception('Ví nguồn không tồn tại.');
      final oldWallet = Wallet.fromMap(
          oldWalletSnap.data() as Map<String, dynamic>, oldWalletSnap.id);

      final newWalletSnap = (newTx.walletId == oldTx.walletId)
          ? oldWalletSnap
          : await txn.get(newWalletRef);
      if (!newWalletSnap.exists) throw Exception('Ví nguồn mới không tồn tại.');
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
        if (!newToSnap.exists) throw Exception('Ví đích không tồn tại.');
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
              title: 'Cảnh báo ngân sách',
              content:
                  'Giao dịch vừa sửa đã làm bạn tiêu vượt 80% ngân sách tháng $monthStrNew cho danh mục này.',
              status: 'unread',
              type: 'budget',
              createdAt: DateTime.now(),
            ));
          }
        }
      } catch (_) {}
    }
  }

  Future<void> deleteTransaction(AppTransaction tx) async {
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

    await _db.runTransaction((transaction) async {
      final txSnap = await transaction.get(txRef);
      if (!txSnap.exists) return; // Giao dịch đã bị xóa trước đó

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

      transaction.delete(txRef);
    });

    if (tx.image != null && tx.image!.isNotEmpty) {
      try {
        await StorageService().deleteImageByUrl(tx.image!);
      } catch (_) {}
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
            data['walletName']?.toString() ?? 'Ví thanh toán';
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

  /// Đồng bộ thông báo trong app và thanh trạng thái cho các kỳ đến hạn hoặc sắp đến hạn cần xử lý
  Future<void> syncRecurringNotifications(String userId) async {
    if (userId.isEmpty) return;
    try {
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

      for (final s in schedules) {
        final occurrenceKey =
            RecurringTransactionService.getOccurrenceKey(s.nextDueDate);
        if (s.lastProcessedKey == occurrenceKey) continue;

        final displayName = s.note != null && s.note!.trim().isNotEmpty
            ? s.note!.trim()
            : (s.type == 'income' ? 'Thu nhập định kỳ' : 'Khoản chi định kỳ');
        final isIncome = s.type == 'income';
        final amountFormatted = '${AppFormatters.number(s.amount)} VNĐ';
        final dueDateOnly = DateTime(
          s.nextDueDate.year,
          s.nextDueDate.month,
          s.nextDueDate.day,
        );

        // 1. Quá hạn
        if (dueDateOnly.isBefore(today)) {
          final diffDays = today.difference(dueDateOnly).inDays;
          await createRecurringNotificationIfNotExists(
            userId: userId,
            title: 'Khoản $displayName đang quá hạn',
            content:
                'Khoản ${isIncome ? 'thu' : 'chi'} $amountFormatted đã quá hạn $diffDays ngày (từ ${DateFormat('dd/MM/yyyy').format(s.nextDueDate)}). Chạm để xử lý ngay.',
            type: 'recurring_due',
            scheduleId: s.scheduleId,
            occurrenceKey: occurrenceKey,
          );
        }
        // 2. Đến hạn hôm nay
        else if (dueDateOnly == today) {
          final isManual =
              s.postingMode == RecurringTransactionSchedule.postingModeManual;
          await createRecurringNotificationIfNotExists(
            userId: userId,
            title: 'Khoản $displayName đến hạn hôm nay',
            content: isManual
                ? 'Khoản ${isIncome ? 'thu' : 'chi'} $amountFormatted cần bạn xác nhận để ghi nhận vào sổ.'
                : 'Khoản ${isIncome ? 'thu' : 'chi'} $amountFormatted sẽ được tự động hạch toán.',
            type: 'recurring_due',
            scheduleId: s.scheduleId,
            occurrenceKey: occurrenceKey,
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
            final daysLeft = dueDateOnly.difference(today).inDays;
            await createRecurringNotificationIfNotExists(
              userId: userId,
              title: 'Khoản $displayName sắp đến hạn',
              content:
                  'Còn $daysLeft ngày nữa đến hạn khoản ${isIncome ? 'thu' : 'chi'} $amountFormatted (${DateFormat('dd/MM/yyyy').format(s.nextDueDate)}).',
              type: 'recurring_reminder',
              scheduleId: s.scheduleId,
              occurrenceKey: occurrenceKey,
            );
          }
        }
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
      throw Exception('Ví được chọn không tồn tại.');
    }
    final wallet = Wallet.fromMap(walletDoc.data()!, walletDoc.id);
    if (!wallet.isActive) {
      throw Exception('Không thể tạo lịch giao dịch với ví đã bị ẩn.');
    }

    if (schedule.categoryId.isNotEmpty) {
      final catDoc =
          await _db.collection('categories').doc(schedule.categoryId).get();
      if (!catDoc.exists) {
        throw Exception('Danh mục được chọn không tồn tại.');
      }
    }

    final ref =
        await _db.collection('recurringTransactions').add(schedule.toMap());
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
      String scheduleId, Map<String, dynamic> data) {
    data.remove('userId'); // Bảo vệ userId không bị thay đổi
    data['updatedAt'] = DateTime.now().toIso8601String();
    return _db.collection('recurringTransactions').doc(scheduleId).update(data);
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
  }

  Future<void> deleteRecurringTransaction(String scheduleId) async {
    try {
      final snap = await _db.collection('recurringTransactions').doc(scheduleId).get();
      if (snap.exists && snap.data() != null) {
        final userId = (snap.data()!['userId'] ?? '').toString();
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

    final schedules = querySnap.docs
        .map((d) => RecurringTransactionSchedule.fromMap(d.data(), d.id))
        .where((s) => s.postingMode == RecurringTransactionSchedule.postingModeAuto)
        .toList();

    int processedCount = 0;
    int skippedCount = 0;
    final List<String> failedSchedules = [];

    for (final schedule in schedules) {
      if (schedule.userId.isEmpty || schedule.userId != userId) {
        failedSchedules.add(
            'Lịch định kỳ "${schedule.scheduleId}" thiếu userId hợp lệ.');
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
                  : 'Giao dịch định kỳ',
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

        final displayName =
            schedule.note != null && schedule.note!.trim().isNotEmpty
                ? schedule.note!.trim()
                : (schedule.type == 'income'
                    ? 'Thu nhập định kỳ'
                    : 'Khoản chi định kỳ');

        if (transactionAlreadyExists) {
          skippedCount++;
        } else if (invalidUserData) {
          failedSchedules.add(
              'Ví cho khoản "$displayName" thiếu userId hợp lệ.');
          stopSchedule = true;
        } else if (walletUnavailable) {
          failedSchedules.add(
              'Ví cho khoản "$displayName" không khả dụng.');
          stopSchedule = true;
        } else if (insufficientBalance) {
          failedSchedules.add(
              'Ví không đủ số dư để thanh toán khoản "$displayName" (${schedule.amount.round()}đ).');
          stopSchedule = true;
          await createRecurringNotificationIfNotExists(
            userId: userId,
            title:
                'Không thể ghi nhận "$displayName" vì ví không đủ số dư',
            content:
                'Ví không đủ số dư để tự động thanh toán ${AppFormatters.currency(schedule.amount)} cho kỳ $occurrenceKey. Vui lòng nạp thêm tiền hoặc đổi ví khác.',
            type: 'recurring_failed',
            scheduleId: schedule.scheduleId,
            occurrenceKey: occurrenceKey,
          );
        } else {
          processedCount++;
          await resolveRecurringNotificationsForOccurrence(
            userId: userId,
            scheduleId: schedule.scheduleId,
            occurrenceKey: occurrenceKey,
          );
          await createRecurringNotificationIfNotExists(
            userId: userId,
            title: 'Đã tự động hạch toán "$displayName"',
            content:
                'Đã ghi nhận giao dịch ${schedule.type == 'income' ? 'thu nhập' : 'chi tiêu'} ${AppFormatters.currency(schedule.amount)} cho kỳ $occurrenceKey.',
            type: 'recurring_success',
            scheduleId: schedule.scheduleId,
            occurrenceKey: occurrenceKey,
          );
        }
      }
    }

    return {
      'processedCount': processedCount,
      'skippedCount': skippedCount,
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
            throw Exception('Kỳ giao dịch này đã được xác nhận hoặc xử lý trước đó.');
          }
        }
        final txSnap = await txn.get(txRef);
        if (txSnap.exists) {
          throw Exception('Giao dịch của kỳ này đã tồn tại.');
        }

        final scheduleSnap = await txn.get(scheduleRef);
        if (scheduleSnap.exists) {
          final sData = scheduleSnap.data();
          if (sData != null && sData['lastProcessedKey'] == occurrenceKey) {
            throw Exception('Kỳ giao dịch này đã được xác nhận hoặc xử lý trước đó.');
          }
        }

        final walletSnap = await txn.get(walletRef);
        if (!walletSnap.exists) {
          throw Exception('Ví thực hiện không tồn tại.');
        }
        final walletData = walletSnap.data() as Map<String, dynamic>;
        final wallet = Wallet.fromMap(walletData, walletSnap.id);

        if (wallet.userId.isEmpty || wallet.userId != userId) {
          throw Exception('Ví thực hiện thiếu userId hợp lệ.');
        }
        if (!wallet.isActive) {
          throw Exception('Ví thực hiện đã bị ẩn hoặc không hoạt động.');
        }
        if (schedule.type == 'expense' && wallet.balance < schedule.amount) {
          throw InsufficientBalanceException(
            message:
                'Ví "${wallet.walletName}" không đủ số dư (${AppFormatters.currency(wallet.balance)}) để thanh toán ${AppFormatters.currency(schedule.amount)}.',
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
              : 'Giao dịch định kỳ',
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

    await resolveRecurringNotificationsForOccurrence(
      userId: userId,
      scheduleId: schedule.scheduleId,
      occurrenceKey: occurrenceKey,
      resolutionNote:
          'Đã xác nhận thanh toán ${AppFormatters.currency(schedule.amount)} vào lúc ${DateFormat('HH:mm dd/MM/yyyy').format(DateTime.now())}.',
    );
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
            throw Exception('Kỳ giao dịch này đã được xử lý trước đó.');
          }
        }

        final scheduleSnap = await txn.get(scheduleRef);
        if (scheduleSnap.exists) {
          final sData = scheduleSnap.data();
          if (sData != null && sData['lastProcessedKey'] == occurrenceKey) {
            throw Exception('Kỳ giao dịch này đã được xử lý trước đó.');
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

    await resolveRecurringNotificationsForOccurrence(
      userId: userId,
      scheduleId: schedule.scheduleId,
      occurrenceKey: occurrenceKey,
      resolutionNote:
          'Đã bỏ qua kỳ giao dịch ${DateFormat('dd/MM/yyyy').format(occurrenceDate)}.',
    );
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
            throw Exception('Kỳ giao dịch này đã được xử lý trước đó.');
          }
        }

        final scheduleSnap = await txn.get(scheduleRef);
        if (scheduleSnap.exists) {
          final sData = scheduleSnap.data();
          if (sData != null && sData['lastProcessedKey'] == occurrenceKey) {
            throw Exception('Kỳ giao dịch này đã được xử lý trước đó.');
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

    await resolveRecurringNotificationsForOccurrence(
      userId: userId,
      scheduleId: schedule.scheduleId,
      occurrenceKey: occurrenceKey,
      resolutionNote:
          'Đã dời kỳ thanh toán sang ngày ${DateFormat('dd/MM/yyyy').format(newDueDate)}.',
    );
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
        throw const FirestoreIndexRequiredException(
          collection: 'transactions',
          message:
              'Truy vấn giao dịch theo khoảng thời gian cần Composite Index (userId ASC, date DESC) trên Firestore. Vui lòng đồng bộ firestore.indexes.json.',
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
                    'Ngân sách của ${conflicts.length} danh mục vừa có thay đổi mới trước khi xác nhận. Vui lòng kiểm tra lại số liệu mới nhất.',
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

            if (oldPlan != null) {
              if (oldPlan.status != PlanLifecycleStatus.draft) {
                originalSnapshotToKeep = oldPlan.originalSnapshot;
              }
              nextRevision = oldPlan.revision + 1;
              historyToKeep = oldPlan.adjustmentHistory;
            }

            final finalizedPlan = planToCommit.copyWith(
              planId: planDocId,
              status: resolvedStatus,
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
                txn.update(existingDoc.reference, {
                  'limit': alloc.recommendedLimit,
                });
              } else {
                final newBudgetRef = _db.collection('budgets').doc();
                final newBudget = Budget(
                  budgetId: newBudgetRef.id,
                  userId: finalizedPlan.userId,
                  categoryId: alloc.categoryId,
                  limit: alloc.recommendedLimit,
                  month: finalizedPlan.targetMonth,
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
                'Không tìm thấy kế hoạch tháng $targetMonth để điều chỉnh.');
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

  // ---------------- ADMIN AI & KNOWLEDGE GOVERNANCE ----------------

  /// Theo dõi bản cấu hình đã xuất bản (`published_configs/{configType}`).
  /// Trả về `null` nếu tài liệu chưa tồn tại trên Firestore.
  Stream<Map<String, dynamic>?> streamPublishedConfigMap(String configType) {
    return _db
        .collection(AiConfigSyncService.kPublishedConfigsCollection)
        .doc(configType)
        .snapshots()
        .map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return Map<String, dynamic>.from(snap.data()!);
    });
  }

  /// Kết hợp realtime `draft_configs/{configType}` và `_sandbox_verifications/{configType}`
  /// thành một [DraftConfigEnvelope] để kiểm tra trạng thái Hash/HMAC.
  Stream<DraftConfigEnvelope?> streamDraftConfigEnvelope(String configType) {
    late final StreamController<DraftConfigEnvelope?> controller;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? draftSub;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? verifySub;

    Map<String, dynamic>? latestDraft;
    bool hasDraftEmission = false;
    Map<String, dynamic>? latestVerification;

    void emitCombined() {
      if (!hasDraftEmission || controller.isClosed) return;
      if (latestDraft == null) {
        controller.add(null);
        return;
      }
      controller.add(
        DraftConfigEnvelope.fromMap(
          latestDraft!,
          configType: configType,
          verificationDoc: latestVerification,
        ),
      );
    }

    controller = StreamController<DraftConfigEnvelope?>(
      onListen: () {
        draftSub = _db
            .collection(AiConfigSyncService.kDraftConfigsCollection)
            .doc(configType)
            .snapshots()
            .listen(
          (snap) {
            latestDraft = (snap.exists && snap.data() != null)
                ? Map<String, dynamic>.from(snap.data()!)
                : null;
            hasDraftEmission = true;
            emitCombined();
          },
          onError: (Object err, StackTrace st) {
            if (!controller.isClosed) {
              controller.addError(err, st);
            }
          },
        );

        verifySub = _db
            .collection('_sandbox_verifications')
            .doc(configType)
            .snapshots()
            .listen(
          (snap) {
            latestVerification = (snap.exists && snap.data() != null)
                ? Map<String, dynamic>.from(snap.data()!)
                : null;
            emitCombined();
          },
          onError: (Object err, StackTrace st) {
            // Không chặn toàn bộ Draft nếu _sandbox_verifications lỗi quyền tạm thời,
            // nhưng chỉ ghi log; riêng lỗi permission-denied trên draft_configs vẫn nổi lên.
            debugPrint('[streamDraftConfigEnvelope] verify sub error: $err');
          },
        );
      },
      onCancel: () async {
        await draftSub?.cancel();
        await verifySub?.cancel();
      },
    );

    return controller.stream;
  }

  /// Lưu bản nháp cấu hình (`draft_configs/{configType}`) tuân thủ nghiêm ngặt Rules `hasAll`/`hasOnly`.
  Future<void> saveDraftConfigDoc({
    required String configType,
    required Map<String, dynamic> draftPayload,
    required String draftHash,
    required String updatedBy,
    String? changeNote,
  }) async {
    final cleanNote = changeNote?.trim();
    await _db
        .collection(AiConfigSyncService.kDraftConfigsCollection)
        .doc(configType)
        .set({
      'configType': configType,
      'draftPayload': draftPayload,
      'draftHash': draftHash,
      'updatedAt': DateTime.now().toIso8601String(),
      'updatedBy': updatedBy,
      if (cleanNote != null && cleanNote.isNotEmpty) 'changeNote': cleanNote,
    });
  }

  /// Theo dõi lịch sử phiên bản cấu hình (`config_versions`) theo từng loại.
  Stream<List<ConfigVersionSnapshot>> streamConfigVersions(String configType) {
    return _db
        .collection(AiConfigSyncService.kConfigVersionsCollection)
        .where('configType', isEqualTo: configType)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => ConfigVersionSnapshot.fromMap(d.data(), docId: d.id))
          .toList();
      list.sort((a, b) => b.versionNumber.compareTo(a.versionNumber));
      return list;
    });
  }

  /// Đọc danh sách tài liệu nháp Kho tri thức Tài chính (`financial_knowledge_drafts`).
  Stream<List<Map<String, dynamic>>> streamKnowledgeDraftDocs() {
    return _db
        .collection(AiConfigSyncService.kDraftKnowledgeCollection)
        .snapshots()
        .map((snap) {
      return snap.docs.map((d) {
        final data = Map<String, dynamic>.from(d.data());
        data['articleId'] ??= d.id;
        return data;
      }).toList();
    });
  }

  /// Đọc danh sách tài liệu đã xuất bản Kho tri thức Tài chính (`financial_knowledge_published`).
  Stream<List<Map<String, dynamic>>> streamKnowledgePublishedDocs() {
    return _db
        .collection(AiConfigSyncService.kPublishedKnowledgeCollection)
        .snapshots()
        .map((snap) {
      return snap.docs.map((d) {
        final data = Map<String, dynamic>.from(d.data());
        data['articleId'] ??= d.id;
        return data;
      }).toList();
    });
  }

  /// Lưu bản nháp bài viết Tri thức Tài chính (`financial_knowledge_drafts/{articleId}`).
  /// Sử dụng merge để giữ nguyên metadata `lastPublishedVersion`/`lastPublishedAt` từ Server.
  Future<void> saveKnowledgeDraftDoc({
    required FinancialKnowledgeArticle article,
    required String updatedBy,
  }) async {
    final docData = <String, dynamic>{
      'articleId': article.articleId.trim(),
      'title': article.title.trim(),
      'topic': article.topic.trim(),
      'triggerCondition': article.triggerCondition.code,
      'priority': article.priority.clamp(1, 10),
      'summaryForUser': article.summaryForUser.trim(),
      'aiGroundingSnippet': article.aiGroundingSnippet.trim(),
      'suggestedPrompts': article.suggestedPrompts,
      'isActive': article.isActive,
      'updatedAt': DateTime.now().toIso8601String(),
      'updatedBy': updatedBy,
    };
    await _db
        .collection(AiConfigSyncService.kDraftKnowledgeCollection)
        .doc(article.articleId.trim())
        .set(docData, SetOptions(merge: true));
  }

  /// Theo dõi danh sách phản hồi chất lượng AI (`ai_feedback_reports`).
  Stream<List<AiFeedbackReport>> streamAiFeedbackReports({int limit = 200}) {
    return _db
        .collection(AiConfigSyncService.kFeedbackReportsCollection)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => AiFeedbackReport.fromMap(d.data(), docId: d.id))
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (list.length > limit) {
        return list.sublist(0, limit);
      }
      return list;
    });
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

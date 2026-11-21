import 'package:flutter/foundation.dart' hide Category;
import '../models/budget_model.dart';
import '../models/category_model.dart';
import '../models/monthly_financial_plan.dart';
import '../models/saving_goal_model.dart';
import '../models/transaction_model.dart';
import '../models/wallet_model.dart';

/// ============================================================
/// FINANCIAL CONTEXT REVISION TRACKER
/// Theo dõi chữ ký thay đổi trên toàn bộ 5 nhóm dữ liệu tài chính:
/// transactions, budgets, categories, savingGoals, monthly_plans (và wallets)
/// nhằm tránh lỗi cache cũ (stale context) trong AI Chatbot và AI Insight.
/// ============================================================
class FinancialContextRevisionTracker {
  /// Bộ đếm phiên bản đột biến cục bộ (tăng mỗi khi FirestoreService thực hiện
  /// bất kỳ thao tác ghi create/update/delete nào).
  static int _localMutationVersion = 0;

  /// Notifier phát sự kiện mỗi khi dữ liệu tài chính thay đổi để UI (VD: AiInsightScreen)
  /// tự động làm mới mà không cần thoát app hoặc bấm refresh thủ công.
  static final ValueNotifier<int> versionNotifier = ValueNotifier<int>(0);

  static int get localMutationVersion => _localMutationVersion;

  static void notifyDataMutated() {
    _localMutationVersion++;
    versionNotifier.value = _localMutationVersion;
  }

  /// Tính chữ ký tổng hợp (Deterministic Revision Signature) cho toàn bộ dữ liệu
  /// tài chính trong cửa sổ phân tích.
  /// Bất kỳ sự thay đổi nào về số tiền, loại giao dịch, tên/nhóm Thiết yếu-Linh hoạt
  /// của danh mục, hạn mức ngân sách, tiến độ mục tiêu tiết kiệm hay phiên bản kế hoạch
  /// đều tạo ra chữ ký mới.
  static String computeRevisionSignature({
    required List<AppTransaction> transactions,
    required List<Budget> budgets,
    required List<Category> categories,
    required List<SavingGoal> savingGoals,
    List<Wallet> wallets = const [],
    MonthlyFinancialPlan? activePlan,
  }) {
    // 1. Chữ ký giao dịch (sắp xếp theo transactionId để không phụ thuộc thứ tự list)
    final sortedTx = List<AppTransaction>.from(transactions)
      ..sort((a, b) => a.transactionId.compareTo(b.transactionId));
    int txDigest = sortedTx.length;
    for (final tx in sortedTx) {
      txDigest = Object.hash(
        txDigest,
        tx.transactionId,
        tx.type,
        tx.amount.round(),
        tx.categoryId,
        tx.walletId,
        tx.goalId ?? '',
        tx.date.millisecondsSinceEpoch,
      );
    }

    // 2. Chữ ký ngân sách (bao gồm cả trường hợp đổi hạn mức 2 danh mục bù trừ nhau)
    final sortedBudgets = List<Budget>.from(budgets)
      ..sort((a, b) => a.budgetId.compareTo(b.budgetId));
    int budgetDigest = sortedBudgets.length;
    for (final b in sortedBudgets) {
      budgetDigest = Object.hash(
        budgetDigest,
        b.budgetId,
        b.categoryId,
        b.month,
        b.limit.round(),
      );
    }

    // 3. Chữ ký danh mục (bao gồm cả cờ isEssential Thiết yếu/Linh hoạt)
    final sortedCats = List<Category>.from(categories)
      ..sort((a, b) => a.categoryId.compareTo(b.categoryId));
    int catDigest = sortedCats.length;
    for (final c in sortedCats) {
      catDigest = Object.hash(
        catDigest,
        c.categoryId,
        c.name,
        c.type,
        c.isEssential,
      );
    }

    // 4. Chữ ký mục tiêu tiết kiệm
    final sortedGoals = List<SavingGoal>.from(savingGoals)
      ..sort((a, b) => a.goalId.compareTo(b.goalId));
    int goalDigest = sortedGoals.length;
    for (final g in sortedGoals) {
      goalDigest = Object.hash(
        goalDigest,
        g.goalId,
        g.name,
        g.targetAmount.round(),
        g.savedAmount.round(),
        g.months,
      );
    }

    // 5. Chữ ký ví
    final sortedWallets = List<Wallet>.from(wallets)
      ..sort((a, b) => a.walletId.compareTo(b.walletId));
    int walletDigest = sortedWallets.length;
    for (final w in sortedWallets) {
      walletDigest = Object.hash(
        walletDigest,
        w.walletId,
        w.balance.round(),
        w.isActive,
      );
    }

    // 6. Chữ ký kế hoạch tài chính tháng
    final int planDigest = activePlan == null
        ? 0
        : Object.hash(
            activePlan.planId,
            activePlan.status.name,
            activePlan.revision,
            activePlan.targetSavingAmount.round(),
            activePlan.essentialExpenseCap.round(),
            activePlan.flexibleExpenseCap.round(),
            activePlan.updatedAt.millisecondsSinceEpoch,
          );

    return 'v$_localMutationVersion|tx:$txDigest|bg:$budgetDigest|cat:$catDigest|sg:$goalDigest|wl:$walletDigest|pl:$planDigest';
  }
}

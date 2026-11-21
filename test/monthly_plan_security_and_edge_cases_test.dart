import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_ai_app/models/ai_runtime_config_model.dart';
import 'package:finance_ai_app/models/budget_model.dart';
import 'package:finance_ai_app/models/category_model.dart';
import 'package:finance_ai_app/models/monthly_financial_plan.dart';
import 'package:finance_ai_app/models/saving_goal_model.dart';
import 'package:finance_ai_app/models/transaction_model.dart';
import 'package:finance_ai_app/models/wallet_model.dart';
import 'package:finance_ai_app/services/ai_prompt_builder.dart';
import 'package:finance_ai_app/services/ai_service.dart';
import 'package:finance_ai_app/services/financial_analytics_service.dart';
import 'package:finance_ai_app/services/financial_context_revision_tracker.dart';
import 'package:finance_ai_app/services/financial_forecast_service.dart';
import 'package:finance_ai_app/services/firestore_service.dart';
import 'package:finance_ai_app/services/language_controller.dart';

void main() {
  late FinancialAnalyticsService analytics;
  late FakeFirebaseFirestore fakeFirestore;
  late FirestoreService firestoreService;

  setUp(() {
    analytics = FinancialAnalyticsService();
    fakeFirestore = FakeFirebaseFirestore();
    firestoreService = FirestoreService(firestore: fakeFirestore);
  });

  AppTransaction makeTx({
    required String id,
    required String type,
    required double amount,
    required String categoryId,
    required DateTime date,
    String userId = 'u1',
  }) {
    return AppTransaction(
      transactionId: id,
      userId: userId,
      walletId: 'w1',
      type: type,
      amount: amount,
      categoryId: categoryId,
      note: 'test',
      date: date,
    );
  }

  group('1. Thuật toán Tài chính & Bất biến Cân bằng Ngân sách', () {
    test(
      'TC-01: Chưa có dữ liệu thu nhập nhưng đã tạo ngân sách -> KHÔNG lấy tổng ngân sách làm thu nhập',
      () {
        final budgets = [
          Budget(
            budgetId: 'b1',
            userId: 'u1',
            categoryId: 'c1',
            limit: 5000000,
            month: '05/2026',
          ),
          Budget(
            budgetId: 'b2',
            userId: 'u1',
            categoryId: 'c2',
            limit: 3000000,
            month: '05/2026',
          ),
        ];

        final incomeRes = analytics.determineReferenceIncome(
          currentMonthTx: const [],
          historicalMonthsTx: const [],
          currentBudgets: budgets,
          declaredExpectedIncome: null,
        );

        expect(incomeRes.mode, IncomeStabilityMode.noIncomeBasis);
        expect(incomeRes.referenceIncome, 0.0);
        expect(incomeRes.currentTotalBudget, 8000000.0);
        expect(incomeRes.hasIncomeBasis, isFalse);

        final plan = analytics.buildSequentialMonthlyPlan(
          userId: 'u1',
          sourceMonth: '05/2026',
          targetMonth: '06/2026',
          sourceMonthTx: const [],
          historicalMonthsTx: const [],
          categories: [
            Category(
              categoryId: 'c1',
              userId: 'u1',
              name: 'Ăn uống',
              type: 'expense',
              icon: 'restaurant',
              color: 0xFF000000,
              isEssential: true,
            ),
          ],
          existingTargetBudgets: budgets,
          savingGoals: const [],
          wallets: const [],
        );

        expect(plan.incomeMode, IncomeStabilityMode.noIncomeBasis);
        expect(plan.referenceIncome, 0.0);
        expect(plan.targetSavingAmount, 0.0);
      },
    );

    test(
      'TC-04: Chi phí thiết yếu vượt thu nhập tham chiếu -> KHÔNG cắt giảm thiết yếu, báo isEssentialDeficit = true',
      () {
        final categories = [
          Category(
            categoryId: 'c_rent',
            userId: 'u1',
            name: 'Tiền nhà',
            type: 'expense',
            icon: 'home',
            color: 0xFF000000,
            isEssential: true,
          ),
          Category(
            categoryId: 'c_food',
            userId: 'u1',
            name: 'Ăn uống',
            type: 'expense',
            icon: 'restaurant',
            color: 0xFF000000,
            isEssential: true,
          ),
        ];

        final currentTx = [
          makeTx(
            id: 't_inc',
            type: 'income',
            amount: 10000000,
            categoryId: 'c_inc',
            date: DateTime(2026, 5, 5),
          ),
          makeTx(
            id: 't_rent',
            type: 'expense',
            amount: 7000000,
            categoryId: 'c_rent',
            date: DateTime(2026, 5, 6),
          ),
          makeTx(
            id: 't_food',
            type: 'expense',
            amount: 5000000,
            categoryId: 'c_food',
            date: DateTime(2026, 5, 10),
          ),
        ];

        final plan = analytics.buildSequentialMonthlyPlan(
          userId: 'u1',
          sourceMonth: '05/2026',
          targetMonth: '06/2026',
          sourceMonthTx: currentTx,
          historicalMonthsTx: const [],
          categories: categories,
          existingTargetBudgets: const [],
          savingGoals: [
            SavingGoal(
              goalId: 'g1',
              userId: 'u1',
              name: 'Mua xe',
              targetAmount: 30000000,
              savedAmount: 0,
              months: 6,
              createdAt: DateTime(2026, 5, 1),
            ),
          ],
          wallets: const [],
          referenceToday: DateTime(2026, 5, 25),
        );

        expect(plan.isEssentialDeficit, isTrue);
        expect(plan.targetSavingAmount, 0.0);
        // Không danh mục thiết yếu nào bị cắt giảm
        for (final alloc in plan.currentAllocations.where((a) => a.isEssential)) {
          expect(alloc.recommendedLimit, greaterThanOrEqualTo(alloc.sourceMonthSpent));
        }
      },
    );

    test(
      'TC-05: Danh mục linh hoạt chạm mức sàn & mục tiêu tiết kiệm vượt khả năng -> Bất biến E_ess + E_flex + S_planned <= I_ref vẫn giữ nguyên',
      () {
        final categories = [
          Category(
            categoryId: 'c_ess',
            userId: 'u1',
            name: 'Ăn uống',
            type: 'expense',
            icon: 'restaurant',
            color: 0xFF000000,
            isEssential: true,
          ),
          Category(
            categoryId: 'c_flex',
            userId: 'u1',
            name: 'Giải trí',
            type: 'expense',
            icon: 'movie',
            color: 0xFF000000,
            isEssential: false,
          ),
        ];

        final currentTx = [
          makeTx(
            id: 't_inc',
            type: 'income',
            amount: 15000000,
            categoryId: 'c_inc',
            date: DateTime(2026, 5, 1),
          ),
          makeTx(
            id: 't_ess',
            type: 'expense',
            amount: 9000000,
            categoryId: 'c_ess',
            date: DateTime(2026, 5, 10),
          ),
          makeTx(
            id: 't_flex',
            type: 'expense',
            amount: 4000000,
            categoryId: 'c_flex',
            date: DateTime(2026, 5, 15),
          ),
        ];

        // Mục tiêu tiết kiệm đòi hỏi rất cao: 10.000.000đ/tháng trong khi dư địa sau thiết yếu chỉ còn 6.000.000đ
        final goals = [
          SavingGoal(
            goalId: 'g_huge',
            userId: 'u1',
            name: 'Quỹ lớn',
            targetAmount: 20000000,
            savedAmount: 0,
            months: 2,
            createdAt: DateTime(2026, 5, 1),
          ),
        ];

        final plan = analytics.buildSequentialMonthlyPlan(
          userId: 'u1',
          sourceMonth: '05/2026',
          targetMonth: '06/2026',
          sourceMonthTx: currentTx,
          historicalMonthsTx: const [],
          categories: categories,
          existingTargetBudgets: const [],
          savingGoals: goals,
          wallets: const [],
          referenceToday: DateTime(2026, 5, 25),
        );

        // Kiểm tra bất biến cứng: Tổng chi dự kiến + Tiết kiệm khả thi <= Thu nhập tham chiếu
        expect(plan.satisfiesBudgetBalanceInvariant, isTrue);
        final totalAllocatedAndSaved = plan.essentialExpenseCap +
            plan.flexibleExpenseCap +
            plan.targetSavingAmount;
        expect(
          totalAllocatedAndSaved,
          lessThanOrEqualTo(plan.referenceIncome + 1.0),
        );
        expect(plan.isSavingGoalFeasible, isFalse);
        expect(plan.infeasibleSavingGap, greaterThan(0));
        expect(plan.recommendedGoalMonths, isNotNull);
        expect(plan.recommendedGoalMonths!, greaterThan(0));
      },
    );
  });

  group('2. Ma trận 5 Cấp độ Đủ Dữ liệu (DataSufficiencyTier)', () {
    test(
      'TC-02: Người dùng chỉ chi tiêu trong 1 danh mục duy nhất nhưng có >= 5 giao dịch ở >= 3 ngày -> Vẫn đạt Tier 2 (currentMonthAnalysis)',
      () {
        final txList = [
          makeTx(
              id: '1',
              type: 'expense',
              amount: 50000,
              categoryId: 'c_food',
              date: DateTime(2026, 5, 1)),
          makeTx(
              id: '2',
              type: 'expense',
              amount: 60000,
              categoryId: 'c_food',
              date: DateTime(2026, 5, 2)),
          makeTx(
              id: '3',
              type: 'expense',
              amount: 70000,
              categoryId: 'c_food',
              date: DateTime(2026, 5, 3)),
          makeTx(
              id: '4',
              type: 'expense',
              amount: 80000,
              categoryId: 'c_food',
              date: DateTime(2026, 5, 3)),
          makeTx(
              id: '5',
              type: 'expense',
              amount: 90000,
              categoryId: 'c_food',
              date: DateTime(2026, 5, 4)),
        ];

        final suff = analytics.assessDataSufficiency(
          currentMonthTx: txList,
          historicalMonthsTx: const [],
          currentBudgets: const [],
          referenceToday: DateTime(2026, 5, 20),
        );

        expect(suff.tier, DataSufficiencyTier.currentMonthAnalysis);
        expect(suff.expenseCategoriesCovered, 1);
        expect(suff.canForecastEndOfMonth, isTrue);
        expect(suff.canCompareMonthOverMonth, isFalse);
        expect(suff.canAnalyzeMultiMonthTrend, isFalse);
      },
    );

    test(
      'TC-03: Phân biệt chính xác Tier 0 (xét cả ví/mục tiêu), Tier 3 (1 tháng lịch sử) và Tier 4 (>= 2 tháng lịch sử)',
      () {
        // Tier 0 khi rỗng hoàn toàn
        final tier0 = analytics.assessDataSufficiency(
          currentMonthTx: const [],
          historicalMonthsTx: const [],
          currentBudgets: const [],
          wallets: const [],
          savingGoals: const [],
        );
        expect(tier0.tier, DataSufficiencyTier.empty);

        // Nếu có mục tiêu tiết kiệm hoặc số dư ví > 0 -> Không bị rơi vào Tier 0
        final tier1FromWallet = analytics.assessDataSufficiency(
          currentMonthTx: const [],
          historicalMonthsTx: const [],
          currentBudgets: const [],
          wallets: [
            Wallet(
              walletId: 'w1',
              userId: 'u1',
              walletName: 'Ví chính',
              balance: 5000000,
              type: 'cash',
              createdAt: DateTime(2026, 5, 1),
            ),
          ],
        );
        expect(tier1FromWallet.tier, DataSufficiencyTier.preliminary);

        List<AppTransaction> buildQualifiedMonth(int month) {
          return List.generate(
            6,
            (i) => makeTx(
              id: 'm_${month}_$i',
              type: 'expense',
              amount: 100000,
              categoryId: 'c_food',
              date: DateTime(2026, month, i + 1),
            ),
          );
        }

        // Tier 3: Chỉ có 1 tháng lịch sử đủ chuẩn
        final tier3 = analytics.assessDataSufficiency(
          currentMonthTx: buildQualifiedMonth(5),
          historicalMonthsTx: [buildQualifiedMonth(4), const [], const []],
          currentBudgets: const [],
          referenceToday: DateTime(2026, 5, 20),
        );
        expect(tier3.tier, DataSufficiencyTier.monthOverMonthComparison);
        expect(tier3.canCompareMonthOverMonth, isTrue);
        expect(tier3.canAnalyzeMultiMonthTrend, isFalse);

        // Tier 4: Có >= 2 tháng lịch sử đủ chuẩn
        final tier4 = analytics.assessDataSufficiency(
          currentMonthTx: buildQualifiedMonth(5),
          historicalMonthsTx: [
            buildQualifiedMonth(4),
            buildQualifiedMonth(3),
            const []
          ],
          currentBudgets: const [],
          referenceToday: DateTime(2026, 5, 20),
        );
        expect(tier4.tier, DataSufficiencyTier.multiMonthTrend);
        expect(tier4.canCompareMonthOverMonth, isTrue);
        expect(tier4.canAnalyzeMultiMonthTrend, isTrue);
      },
    );
  });

  group('3. Giao dịch Firestore, Kiểm tra Xung đột, Idempotency & Tái cân bằng', () {
    MonthlyFinancialPlan createSampleDraftPlan() {
      const allocs = [
        PlannedCategoryAllocation(
          categoryId: 'c1',
          categoryName: 'Ăn uống',
          isEssential: true,
          sourceMonthSpent: 4000000,
          regularBaselineSpent: 4000000,
          historicalMedian: 4000000,
          existingBudget: 4000000,
          floorLimit: 4000000,
          recommendedLimit: 4000000,
          deltaFromCurrent: 0,
          calculationBasis: 'Thiết yếu',
          aiActionTip: 'Giữ nguyên chi phí thiết yếu',
        ),
        PlannedCategoryAllocation(
          categoryId: 'c2',
          categoryName: 'Giải trí',
          isEssential: false,
          sourceMonthSpent: 2500000,
          regularBaselineSpent: 2500000,
          historicalMedian: 2000000,
          existingBudget: 2500000,
          floorLimit: 1000000,
          recommendedLimit: 1800000,
          deltaFromCurrent: -700000,
          calculationBasis: 'Cắt giảm linh hoạt',
          aiActionTip: 'Chia hạn mức tuần',
        ),
      ];
      return MonthlyFinancialPlan(
        planId: 'u1_06-2026',
        userId: 'u1',
        targetMonth: '06/2026',
        sourceMonth: '05/2026',
        status: PlanLifecycleStatus.draft,
        dataTierUsed: DataSufficiencyTier.monthOverMonthComparison,
        incomeMode: IncomeStabilityMode.stable,
        referenceIncome: 10000000,
        essentialExpenseCap: 4000000,
        flexibleExpenseCap: 1800000,
        targetSavingAmount: 4200000,
        desiredGoalSavingAmount: 4000000,
        isSavingGoalFeasible: true,
        isEssentialDeficit: false,
        infeasibleSavingGap: 0,
        recommendedGoalMonths: null,
        currentAllocations: allocs,
        originalSnapshot: PlanSnapshotData(
          referenceIncome: 10000000,
          essentialExpenseTotal: 4000000,
          flexibleExpenseTotal: 1800000,
          targetSavingAmount: 4200000,
          allocations: allocs,
          capturedAt: DateTime(2026, 5, 28),
        ),
        adjustmentHistory: const [],
        aiExecutiveSummary: 'Kế hoạch mẫu',
        behavioralInsights: const ['Ổn định'],
        revision: 1,
        createdAt: DateTime(2026, 5, 28),
        updatedAt: DateTime(2026, 5, 28),
      );
    }

    test(
      'TC-06: Ngân sách bị thay đổi ở màn hình khác trước khi xác nhận -> Ném PlanBudgetConflictException và không ghi đè',
      () async {
        // Giả lập trên Firestore ngân sách Giải trí (c2) đã bị đổi thành 3.200.000đ ở tab khác
        await fakeFirestore.collection('budgets').doc('b_ent').set({
          'userId': 'u1',
          'categoryId': 'c2',
          'limit': 3200000.0,
          'month': '06/2026',
        });

        final draft = createSampleDraftPlan();

        await expectLater(
          () => firestoreService.commitMonthlyPlanTransactionally(
            planToCommit: draft,
            selectedCategoryIds: {'c1', 'c2'},
            // Lúc mở sheet xem trước, giá trị cũ của c2 là 2.500.000đ
            expectedExistingBudgets: {
              'c1': null,
              'c2': 2500000.0,
            },
            submissionToken: 'tok_conflict_1',
          ),
          throwsA(isA<PlanBudgetConflictException>()),
        );

        // Đảm bảo ngân sách 3.200.000đ trên Firestore KHÔNG bị ghi đè
        final doc =
            await fakeFirestore.collection('budgets').doc('b_ent').get();
        expect(doc.data()?['limit'], 3200000.0);
      },
    );

    test(
      'TC-07: Người dùng bấm xác nhận nhiều lần liên tiếp -> Idempotency submissionToken ngăn ghi trùng',
      () async {
        final draft = createSampleDraftPlan();

        final firstCommit =
            await firestoreService.commitMonthlyPlanTransactionally(
          planToCommit: draft,
          selectedCategoryIds: {'c1', 'c2'},
          expectedExistingBudgets: {'c1': null, 'c2': null},
          submissionToken: 'tok_idempotent_99',
          currentReferenceDate: DateTime(2026, 6, 1),
        );

        final secondCommit =
            await firestoreService.commitMonthlyPlanTransactionally(
          planToCommit: draft,
          selectedCategoryIds: {'c1', 'c2'},
          expectedExistingBudgets: {'c1': null, 'c2': null},
          submissionToken: 'tok_idempotent_99',
          currentReferenceDate: DateTime(2026, 6, 1),
        );

        expect(firstCommit.status, PlanLifecycleStatus.active);
        expect(secondCommit.revision, firstCommit.revision);

        final budgetsSnap = await fakeFirestore
            .collection('budgets')
            .where('userId', isEqualTo: 'u1')
            .where('month', isEqualTo: '06/2026')
            .get();
        // Chỉ tạo đúng 2 ngân sách cho 2 danh mục, không bị nhân đôi
        expect(budgetsSnap.docs.length, 2);
      },
    );

    test(
      'TC-09: Tái cân bằng kế hoạch nhiều lần trong tháng -> Giữ nguyên originalSnapshot, lưu adjustmentHistory, tăng revision, KHÔNG sửa SavingGoal gốc',
      () async {
        // Tạo 1 SavingGoal dài hạn trên Firestore
        await fakeFirestore.collection('savingGoals').doc('goal_house').set({
          'userId': 'u1',
          'name': 'Mua nhà',
          'targetAmount': 500000000.0,
          'savedAmount': 50000000.0,
          'months': 36,
          'createdAt': DateTime(2026, 1, 1).toIso8601String(),
        });

        final draft = createSampleDraftPlan();
        final committed =
            await firestoreService.commitMonthlyPlanTransactionally(
          planToCommit: draft,
          selectedCategoryIds: {'c1', 'c2'},
          expectedExistingBudgets: {'c1': null, 'c2': null},
          submissionToken: 'tok_init_1',
          currentReferenceDate: DateTime(2026, 6, 1),
        );

        // Lần tái cân bằng 1: Tăng Ăn uống lên 4.500.000đ, giảm tiết kiệm tháng xuống 3.700.000đ
        final reb1Allocs = committed.currentAllocations
            .map((a) => a.categoryId == 'c1'
                ? a.copyWith(recommendedLimit: 4500000)
                : a)
            .toList();
        final reb1 = await firestoreService.rebalanceMonthlyPlanTransactionally(
          userId: 'u1',
          targetMonth: '06/2026',
          updatedAllocations: reb1Allocs,
          updatedTargetSaving: 3700000,
          updatedReferenceIncome: 10000000,
          reason: 'Phát sinh đám cưới và tiếp khách',
          strategy: 'reallocate_categories',
          summary: 'Tăng Ăn uống lên 4.5tr',
        );

        // Lần tái cân bằng 2: Tăng Giải trí lên 2.000.000đ, giảm tiết kiệm tháng xuống 3.500.000đ
        final reb2Allocs = reb1.currentAllocations
            .map((a) => a.categoryId == 'c2'
                ? a.copyWith(recommendedLimit: 2000000)
                : a)
            .toList();
        final reb2 = await firestoreService.rebalanceMonthlyPlanTransactionally(
          userId: 'u1',
          targetMonth: '06/2026',
          updatedAllocations: reb2Allocs,
          updatedTargetSaving: 3500000,
          updatedReferenceIncome: 10000000,
          reason: 'Chi phí sinh nhật',
          strategy: 'reallocate_categories',
          summary: 'Tăng Giải trí lên 2tr',
        );

        expect(reb2.revision, committed.revision + 2);
        expect(reb2.adjustmentHistory.length, 2);
        // Bản kế hoạch gốc ban đầu (originalSnapshot) vẫn giữ nguyên 4.200.000đ tiết kiệm
        expect(reb2.originalSnapshot.targetSavingAmount, 4200000.0);
        expect(reb2.targetSavingAmount, 3500000.0);

        // Kiểm tra tài liệu SavingGoal gốc KHÔNG bị thay đổi
        final goalDoc = await fakeFirestore
            .collection('savingGoals')
            .doc('goal_house')
            .get();
        expect(goalDoc.data()?['targetAmount'], 500000000.0);
        expect(goalDoc.data()?['savedAmount'], 50000000.0);
      },
    );
  });

  group('4. Đánh giá Thực thi Kép Không Tính Trùng & Các Thành phần Khác', () {
    test(
      'TC-08: Ghi nhận tiền tiết kiệm không bị tính trùng giữa goal_deposit và dòng tiền dư cuối tháng',
      () {
        const allocs = [
          PlannedCategoryAllocation(
            categoryId: 'c1',
            categoryName: 'Ăn uống',
            isEssential: true,
            sourceMonthSpent: 4000000,
            regularBaselineSpent: 4000000,
            historicalMedian: 4000000,
            existingBudget: 4000000,
            floorLimit: 4000000,
            recommendedLimit: 4000000,
            deltaFromCurrent: 0,
            calculationBasis: 'Thiết yếu',
            aiActionTip: 'Giữ nguyên',
          ),
        ];

        final activePlan = MonthlyFinancialPlan(
          planId: 'u1_05-2026',
          userId: 'u1',
          targetMonth: '05/2026',
          sourceMonth: '04/2026',
          status: PlanLifecycleStatus.active,
          dataTierUsed: DataSufficiencyTier.monthOverMonthComparison,
          incomeMode: IncomeStabilityMode.stable,
          referenceIncome: 10000000,
          essentialExpenseCap: 4000000,
          flexibleExpenseCap: 0,
          targetSavingAmount: 6000000,
          desiredGoalSavingAmount: 6000000,
          isSavingGoalFeasible: true,
          isEssentialDeficit: false,
          infeasibleSavingGap: 0,
          recommendedGoalMonths: null,
          currentAllocations: allocs,
          originalSnapshot: PlanSnapshotData(
            referenceIncome: 10000000,
            essentialExpenseTotal: 4000000,
            flexibleExpenseTotal: 0,
            targetSavingAmount: 6000000,
            allocations: allocs,
            capturedAt: DateTime(2026, 5, 1),
          ),
          adjustmentHistory: const [],
          aiExecutiveSummary: 'Kế hoạch tháng 5',
          revision: 1,
          createdAt: DateTime(2026, 5, 1),
          updatedAt: DateTime(2026, 5, 1),
        );

        // Tháng 5: Thu 10tr, Chi Ăn uống 4tr (Dư dòng tiền ròng = 6tr).
        // Người dùng nạp 2.5tr vào Mục tiêu Tiết kiệm (goal_deposit).
        // Tổng tiết kiệm thực tế vẫn phải là 6tr (gồm 2.5tr trong mục tiêu + 3.5tr còn trong ví), KHÔNG phải 8.5tr!
        final txList = [
          makeTx(
            id: 't1',
            type: 'income',
            amount: 10000000,
            categoryId: 'c_inc',
            date: DateTime(2026, 5, 5),
          ),
          makeTx(
            id: 't2',
            type: 'expense',
            amount: 4000000,
            categoryId: 'c1',
            date: DateTime(2026, 5, 10),
          ),
          makeTx(
            id: 't3',
            type: 'goal_deposit',
            amount: 2500000,
            categoryId: '',
            date: DateTime(2026, 5, 15),
          ),
        ];

        final tracker = analytics.evaluatePlanExecution(
          plan: activePlan,
          targetMonthTx: txList,
          referenceToday: DateTime(2026, 5, 20),
        );

        expect(tracker.totalNetCashflowSurplus, 6000000.0);
        expect(tracker.netGoalContributions, 2500000.0);
        expect(tracker.unallocatedWalletSurplus, 3500000.0);
        expect(tracker.effectiveMonthlySaved, 6000000.0);
        // Không tính trùng: netGoalContributions + unallocatedWalletSurplus == totalNetCashflowSurplus
        expect(
          tracker.netGoalContributions + tracker.unallocatedWalletSurplus,
          tracker.totalNetCashflowSurplus,
        );
        expect(tracker.savingAdherenceScore, closeTo(100.0, 0.1));
      },
    );

    test(
      'TC-10: Gemini trả dữ liệu sai định dạng JSON -> parseAndValidateStructuredInsight trả về null và buildDeterministicFallbackInsight hoạt động an toàn',
      () {
        const allocs = [
          PlannedCategoryAllocation(
            categoryId: 'c1',
            categoryName: 'Ăn uống',
            isEssential: true,
            sourceMonthSpent: 3000000,
            regularBaselineSpent: 3000000,
            historicalMedian: 3000000,
            existingBudget: 3000000,
            floorLimit: 3000000,
            recommendedLimit: 3000000,
            deltaFromCurrent: 0,
            calculationBasis: 'Thiết yếu',
            aiActionTip: 'Giữ nguyên',
          ),
        ];
        final plan = MonthlyFinancialPlan(
          planId: 'u1_06-2026',
          userId: 'u1',
          targetMonth: '06/2026',
          sourceMonth: '05/2026',
          status: PlanLifecycleStatus.draft,
          dataTierUsed: DataSufficiencyTier.currentMonthAnalysis,
          incomeMode: IncomeStabilityMode.stable,
          referenceIncome: 12000000,
          essentialExpenseCap: 3000000,
          flexibleExpenseCap: 0,
          targetSavingAmount: 9000000,
          desiredGoalSavingAmount: 5000000,
          isSavingGoalFeasible: true,
          isEssentialDeficit: false,
          infeasibleSavingGap: 0,
          recommendedGoalMonths: null,
          currentAllocations: allocs,
          originalSnapshot: PlanSnapshotData(
            referenceIncome: 12000000,
            essentialExpenseTotal: 3000000,
            flexibleExpenseTotal: 0,
            targetSavingAmount: 9000000,
            allocations: allocs,
            capturedAt: DateTime(2026, 5, 20),
          ),
          adjustmentHistory: const [],
          aiExecutiveSummary: 'Tóm tắt thuật toán nội bộ an toàn.',
          behavioralInsights: const ['Chi tiêu thiết yếu ổn định.'],
          revision: 1,
          createdAt: DateTime(2026, 5, 20),
          updatedAt: DateTime(2026, 5, 20),
        );

        final parsedInvalid = AiService.parseAndValidateStructuredInsight(
          rawText: 'Đây không phải là JSON hợp lệ {{{ broken',
          draftPlan: plan,
        );
        expect(parsedInvalid, isNull);

        final fallback = AiService.buildDeterministicFallbackInsight(plan);
        expect(fallback.isFromFallback, isTrue);
        expect(fallback.executiveSummary, isNotEmpty);
        expect(fallback.behavioralInsights, isNotEmpty);
      },
    );

    test(
      'TC-11: FinancialContextRevisionTracker phát hiện thay đổi khi đổi phân loại Thiết yếu/Linh hoạt hoặc Kế hoạch tháng',
      () {
        final catEssential = Category(
          categoryId: 'c1',
          userId: 'u1',
          name: 'Ăn ngoài',
          type: 'expense',
          icon: 'restaurant',
          color: 0xFF000000,
          isEssential: true,
        );
        final catFlexible = catEssential.copyWith(isEssential: false);

        final sig1 = FinancialContextRevisionTracker.computeRevisionSignature(
          transactions: const [],
          budgets: const [],
          categories: [catEssential],
          savingGoals: const [],
        );
        final sig2 = FinancialContextRevisionTracker.computeRevisionSignature(
          transactions: const [],
          budgets: const [],
          categories: [catFlexible],
          savingGoals: const [],
        );

        expect(sig1, isNot(equals(sig2)));

        final vBefore = FinancialContextRevisionTracker.localMutationVersion;
        FinancialContextRevisionTracker.notifyDataMutated();
        expect(
          FinancialContextRevisionTracker.localMutationVersion,
          greaterThan(vBefore),
        );
      },
    );

    test(
      'TC-12: getTransactionsByDateWindow lọc đúng cửa sổ thời gian và phân trang cursor chính xác',
      () async {
        // Tạo 5 giao dịch trong tháng 5/2026 và 2 giao dịch ngoài cửa sổ (tháng 1/2026)
        for (int i = 1; i <= 5; i++) {
          final tx = makeTx(
            id: 'tx_may_$i',
            type: 'expense',
            amount: 100000.0 * i,
            categoryId: 'c_food',
            date: DateTime(2026, 5, i + 1),
          );
          await fakeFirestore
              .collection('transactions')
              .doc(tx.transactionId)
              .set(tx.toMap());
        }
        for (int i = 1; i <= 2; i++) {
          final oldTx = makeTx(
            id: 'tx_jan_$i',
            type: 'expense',
            amount: 50000.0,
            categoryId: 'c_food',
            date: DateTime(2026, 1, i + 1),
          );
          await fakeFirestore
              .collection('transactions')
              .doc(oldTx.transactionId)
              .set(oldTx.toMap());
        }

        final windowResult = await firestoreService.getTransactionsByDateWindow(
          'u1',
          from: DateTime(2026, 5, 1),
          to: DateTime(2026, 5, 31, 23, 59, 59),
          pageSize: 50,
        );

        expect(windowResult.length, 5);
        expect(
          windowResult.every((t) => t.date.month == 5 && t.date.year == 2026),
          isTrue,
        );
      },
    );
  });

  group('5. Đồng bộ Kế hoạch Tương lai & Hạn mức khi Xóa/Sửa Giao dịch + Mốc Tháng Cố vấn AI', () {
    Future<void> seedWalletAndUser({
      String userId = 'u1',
      double balance = 10000000,
    }) async {
      await fakeFirestore.collection('wallets').doc('w1').set({
        'userId': userId,
        'walletName': 'Ví chính',
        'balance': balance,
        'type': 'cash',
        'isActive': true,
        'createdAt': DateTime(2026, 5, 1).toIso8601String(),
      });
    }

    test(
      'TC-13: Xóa giao dịch chi tiêu duy nhất ở tháng nguồn sau khi Xem trước & Áp dụng -> Xóa luôn Ngân sách tương lai và Kế hoạch đã phê duyệt',
      () async {
        await seedWalletAndUser();
        final categories = [
          Category(
            categoryId: 'c_food',
            userId: 'u1',
            name: 'Ăn uống',
            type: 'expense',
            icon: 'restaurant',
            color: 0xFFFF9800,
            isEssential: false,
          ),
        ];

        final incTx = makeTx(
          id: 'tx_inc',
          type: 'income',
          amount: 10000000,
          categoryId: 'c_inc',
          date: DateTime(2026, 5, 5),
        );
        final expTx = makeTx(
          id: 'tx_food',
          type: 'expense',
          amount: 2000000,
          categoryId: 'c_food',
          date: DateTime(2026, 5, 10),
        );

        await fakeFirestore
            .collection('transactions')
            .doc(incTx.transactionId)
            .set(incTx.toMap());
        await fakeFirestore
            .collection('transactions')
            .doc(expTx.transactionId)
            .set(expTx.toMap());

        final draftPlan = analytics.buildSequentialMonthlyPlan(
          userId: 'u1',
          sourceMonth: '05/2026',
          targetMonth: '06/2026',
          sourceMonthTx: [incTx, expTx],
          historicalMonthsTx: const [],
          categories: categories,
          existingTargetBudgets: const [],
          savingGoals: const [],
          referenceToday: DateTime(2026, 5, 20),
        );

        await firestoreService.commitMonthlyPlanTransactionally(
          planToCommit: draftPlan,
          selectedCategoryIds: {'c_food'},
          expectedExistingBudgets: {'c_food': null},
          submissionToken: 'tok_tc13',
          currentReferenceDate: DateTime(2026, 5, 20),
        );

        // Xác nhận trước khi xóa: có cả Budget 06/2026 và Plan 06/2026
        expect(
          (await firestoreService.getBudgetsSafely('u1', month: '06/2026'))
              .length,
          1,
        );
        expect(
          await firestoreService.getMonthlyPlan('u1', '06/2026'),
          isNotNull,
        );

        // Người dùng xóa giao dịch chi tiêu Ăn uống ở tháng 05/2026
        final int versionBefore =
            FinancialContextRevisionTracker.localMutationVersion;
        await firestoreService.deleteTransaction(
          expTx,
          currentReferenceDate: DateTime(2026, 5, 21),
        );

        // Budget tương lai (06/2026) và Kế hoạch tháng 06/2026 đều bị xóa theo
        final budgetsAfter =
            await firestoreService.getBudgetsSafely('u1', month: '06/2026');
        final planAfter =
            await firestoreService.getMonthlyPlan('u1', '06/2026');

        expect(budgetsAfter, isEmpty);
        expect(planAfter, isNull);
        expect(
          FinancialContextRevisionTracker.localMutationVersion,
          greaterThan(versionBefore),
        );
      },
    );

    test(
      'TC-14: Có 2 danh mục đã áp dụng (Ăn uống 2tr, Học tập 1tr) -> Xóa giao dịch Ăn uống chỉ xóa Ăn uống và giữ Học tập cùng Cân bằng đúng',
      () async {
        await seedWalletAndUser();
        final categories = [
          Category(
            categoryId: 'c_study',
            userId: 'u1',
            name: 'Học tập',
            type: 'expense',
            icon: 'school',
            color: 0xFF2196F3,
            isEssential: true,
          ),
          Category(
            categoryId: 'c_food',
            userId: 'u1',
            name: 'Ăn uống',
            type: 'expense',
            icon: 'restaurant',
            color: 0xFFFF9800,
            isEssential: false,
          ),
        ];

        final incTx = makeTx(
          id: 'tx_inc',
          type: 'income',
          amount: 10000000,
          categoryId: 'c_inc',
          date: DateTime(2026, 5, 2),
        );
        final studyTx = makeTx(
          id: 'tx_study',
          type: 'expense',
          amount: 1000000,
          categoryId: 'c_study',
          date: DateTime(2026, 5, 6),
        );
        final foodTx = makeTx(
          id: 'tx_food',
          type: 'expense',
          amount: 2000000,
          categoryId: 'c_food',
          date: DateTime(2026, 5, 8),
        );

        for (final tx in [incTx, studyTx, foodTx]) {
          await fakeFirestore
              .collection('transactions')
              .doc(tx.transactionId)
              .set(tx.toMap());
        }

        final draftPlan = analytics.buildSequentialMonthlyPlan(
          userId: 'u1',
          sourceMonth: '05/2026',
          targetMonth: '06/2026',
          sourceMonthTx: [incTx, studyTx, foodTx],
          historicalMonthsTx: const [],
          categories: categories,
          existingTargetBudgets: const [],
          savingGoals: const [],
          referenceToday: DateTime(2026, 5, 20),
        );

        await firestoreService.commitMonthlyPlanTransactionally(
          planToCommit: draftPlan,
          selectedCategoryIds: {'c_study', 'c_food'},
          expectedExistingBudgets: {'c_study': null, 'c_food': null},
          submissionToken: 'tok_tc14',
          currentReferenceDate: DateTime(2026, 5, 20),
        );

        // Xóa giao dịch Ăn uống (2tr)
        await firestoreService.deleteTransaction(
          foodTx,
          currentReferenceDate: DateTime(2026, 5, 21),
        );

        final budgetsAfter =
            await firestoreService.getBudgetsSafely('u1', month: '06/2026');
        final planAfter =
            await firestoreService.getMonthlyPlan('u1', '06/2026');

        expect(budgetsAfter.length, 1);
        expect(budgetsAfter.first.categoryId, 'c_study');
        expect(budgetsAfter.first.limit, 1000000.0);

        expect(planAfter, isNotNull);
        expect(planAfter!.currentAllocations.length, 1);
        expect(planAfter.currentAllocations.first.categoryId, 'c_study');
        expect(planAfter.essentialExpenseCap, 1000000.0);
        expect(planAfter.flexibleExpenseCap, 0.0);
      },
    );

    test(
      'TC-15: Xóa bớt 1 giao dịch hoặc sửa giảm số tiền trong cùng danh mục -> Tự động giảm hạn mức Hạn mức và Kế hoạch tương lai tương ứng',
      () async {
        await seedWalletAndUser();
        final categories = [
          Category(
            categoryId: 'c_food',
            userId: 'u1',
            name: 'Ăn uống',
            type: 'expense',
            icon: 'restaurant',
            color: 0xFFFF9800,
            isEssential: true,
          ),
        ];

        final incTx = makeTx(
          id: 'tx_inc',
          type: 'income',
          amount: 10000000,
          categoryId: 'c_inc',
          date: DateTime(2026, 5, 2),
        );
        final food1 = makeTx(
          id: 'tx_food_1',
          type: 'expense',
          amount: 2000000,
          categoryId: 'c_food',
          date: DateTime(2026, 5, 6),
        );
        final food2 = makeTx(
          id: 'tx_food_2',
          type: 'expense',
          amount: 1000000,
          categoryId: 'c_food',
          date: DateTime(2026, 5, 8),
        );

        for (final tx in [incTx, food1, food2]) {
          await fakeFirestore
              .collection('transactions')
              .doc(tx.transactionId)
              .set(tx.toMap());
        }

        final draftPlan = analytics.buildSequentialMonthlyPlan(
          userId: 'u1',
          sourceMonth: '05/2026',
          targetMonth: '06/2026',
          sourceMonthTx: [incTx, food1, food2],
          historicalMonthsTx: const [],
          categories: categories,
          existingTargetBudgets: const [],
          savingGoals: const [],
          referenceToday: DateTime(2026, 5, 20),
        );

        await firestoreService.commitMonthlyPlanTransactionally(
          planToCommit: draftPlan,
          selectedCategoryIds: {'c_food'},
          expectedExistingBudgets: {'c_food': null},
          submissionToken: 'tok_tc15',
          currentReferenceDate: DateTime(2026, 5, 20),
        );

        // Xóa tx 2tr, còn lại tx 1tr
        await firestoreService.deleteTransaction(
          food1,
          currentReferenceDate: DateTime(2026, 5, 21),
        );

        var budgetsAfter =
            await firestoreService.getBudgetsSafely('u1', month: '06/2026');
        var planAfter = await firestoreService.getMonthlyPlan('u1', '06/2026');
        expect(budgetsAfter.single.limit, 1000000.0);
        expect(planAfter!.essentialExpenseCap, 1000000.0);
        expect(planAfter.currentAllocations.single.sourceMonthSpent, 1000000.0);

        // Sửa giảm tx còn lại từ 1tr -> 500k
        final food2Updated = makeTx(
          id: 'tx_food_2',
          type: 'expense',
          amount: 500000,
          categoryId: 'c_food',
          date: DateTime(2026, 5, 8),
        );
        await firestoreService.updateTransactionSafely(
          food2,
          food2Updated,
          currentReferenceDate: DateTime(2026, 5, 22),
        );

        budgetsAfter =
            await firestoreService.getBudgetsSafely('u1', month: '06/2026');
        planAfter = await firestoreService.getMonthlyPlan('u1', '06/2026');
        expect(budgetsAfter.single.limit, 500000.0);
        expect(planAfter!.essentialExpenseCap, 500000.0);
      },
    );

    test(
      'TC-16: Bảo toàn ngân sách thủ công có sẵn (prePlanLimit) & không xóa kế hoạch đã active khi bước sang tháng đích',
      () async {
        await seedWalletAndUser();
        final categories = [
          Category(
            categoryId: 'c_food',
            userId: 'u1',
            name: 'Ăn uống',
            type: 'expense',
            icon: 'restaurant',
            color: 0xFFFF9800,
            isEssential: true,
          ),
        ];

        // Ngân sách thủ công có sẵn ở tháng 06/2026 là 1.500.000đ
        await fakeFirestore.collection('budgets').doc('b_manual').set({
          'userId': 'u1',
          'categoryId': 'c_food',
          'limit': 1500000.0,
          'month': '06/2026',
          'isManual': true,
        });

        final incTx = makeTx(
          id: 'tx_inc',
          type: 'income',
          amount: 10000000,
          categoryId: 'c_inc',
          date: DateTime(2026, 5, 2),
        );
        final foodTx = makeTx(
          id: 'tx_food',
          type: 'expense',
          amount: 2000000,
          categoryId: 'c_food',
          date: DateTime(2026, 5, 6),
        );
        await fakeFirestore
            .collection('transactions')
            .doc(incTx.transactionId)
            .set(incTx.toMap());
        await fakeFirestore
            .collection('transactions')
            .doc(foodTx.transactionId)
            .set(foodTx.toMap());

        final existingJuneBudgets =
            await firestoreService.getBudgetsSafely('u1', month: '06/2026');
        final draftPlan = analytics.buildSequentialMonthlyPlan(
          userId: 'u1',
          sourceMonth: '05/2026',
          targetMonth: '06/2026',
          sourceMonthTx: [incTx, foodTx],
          historicalMonthsTx: const [],
          categories: categories,
          existingTargetBudgets: existingJuneBudgets,
          savingGoals: const [],
          referenceToday: DateTime(2026, 5, 20),
        );

        await firestoreService.commitMonthlyPlanTransactionally(
          planToCommit: draftPlan,
          selectedCategoryIds: {'c_food'},
          expectedExistingBudgets: {'c_food': 1500000.0},
          submissionToken: 'tok_tc16a',
          currentReferenceDate: DateTime(2026, 5, 20),
        );

        expect(
          (await firestoreService.getBudgetsSafely('u1', month: '06/2026'))
              .single
              .limit,
          2000000.0,
        );

        // Xóa tx 2tr ở tháng 05 -> Ngân sách tháng 06/2026 khôi phục về 1.500.000đ thủ công ban đầu
        await firestoreService.deleteTransaction(
          foodTx,
          currentReferenceDate: DateTime(2026, 5, 21),
        );
        final restored =
            (await firestoreService.getBudgetsSafely('u1', month: '06/2026'))
                .single;
        expect(restored.limit, 1500000.0);
        expect(restored.isManual, isTrue);

        // Kiểm tra thêm: Nếu đã bước sang tháng 06/2026 (kế hoạch đã active), xóa giao dịch tháng 05 không xóa kế hoạch tháng 06
        final activeFoodTx = makeTx(
          id: 'tx_food_active',
          type: 'expense',
          amount: 2000000,
          categoryId: 'c_food',
          date: DateTime(2026, 5, 7),
        );
        await fakeFirestore
            .collection('transactions')
            .doc(activeFoodTx.transactionId)
            .set(activeFoodTx.toMap());
        await fakeFirestore.collection('budgets').doc('b_manual').delete();

        final draftForActive = analytics.buildSequentialMonthlyPlan(
          userId: 'u1',
          sourceMonth: '05/2026',
          targetMonth: '06/2026',
          sourceMonthTx: [incTx, activeFoodTx],
          historicalMonthsTx: const [],
          categories: categories,
          existingTargetBudgets: const [],
          savingGoals: const [],
          referenceToday: DateTime(2026, 5, 25),
        );
        await firestoreService.commitMonthlyPlanTransactionally(
          planToCommit: draftForActive,
          selectedCategoryIds: {'c_food'},
          expectedExistingBudgets: {'c_food': null},
          submissionToken: 'tok_tc16b',
          currentReferenceDate: DateTime(2026, 5, 25),
        );

        // Giả lập thời điểm hiện tại đã sang 05/06/2026
        await firestoreService.deleteTransaction(
          activeFoodTx,
          currentReferenceDate: DateTime(2026, 6, 5),
        );
        expect(
          (await firestoreService.getBudgetsSafely('u1', month: '06/2026'))
              .length,
          1,
        );
        expect(
          await firestoreService.getMonthlyPlan('u1', '06/2026'),
          isNotNull,
        );
      },
    );

    test(
      'TC-17: AiPromptBuilder.buildStructuredPlanPrompt tách bạch rõ tháng hiện tại (Health Score/Thực chi) và tháng kế hoạch (Hạn mức) cả VI và EN',
      () {
        final originalLocale = LanguageController.currentLocale.value;
        try {
          final categories = [
            Category(
              categoryId: 'c_food',
              userId: 'u1',
              name: 'Ăn uống',
              type: 'expense',
              icon: 'restaurant',
              color: 0xFFFF9800,
              isEssential: false,
            ),
          ];
          final txList = [
            makeTx(
              id: 't_inc',
              type: 'income',
              amount: 10000000,
              categoryId: 'c_inc',
              date: DateTime(2026, 11, 5),
            ),
            makeTx(
              id: 't_food',
              type: 'expense',
              amount: 2000000,
              categoryId: 'c_food',
              date: DateTime(2026, 11, 10),
            ),
          ];
          final draftPlan = analytics.buildSequentialMonthlyPlan(
            userId: 'u1',
            sourceMonth: '11/2026',
            targetMonth: '12/2026',
            sourceMonthTx: txList,
            historicalMonthsTx: const [],
            categories: categories,
            existingTargetBudgets: const [],
            savingGoals: const [],
            referenceToday: DateTime(2026, 11, 16),
          );
          final summary = FinancialForecastService().generateSummary(
            activeWallets: const [],
            currentMonthBudgets: const [],
            categories: categories,
            currentMonthTx: txList,
            preceding3MonthsTx: const [],
            monthlyIncome: 10000000,
            issues: const [],
            refDate: DateTime(2026, 11, 16),
          );

          // Tiếng Việt
          LanguageController.currentLocale.value = const Locale('vi', 'VN');
          final viPrompt = AiPromptBuilder.buildStructuredPlanPrompt(
            summary: summary,
            draftPlan: draftPlan,
          );
          expect(viPrompt, contains('Điểm sức khỏe tài chính tháng 11/2026'));
          expect(viPrompt, contains('Thực chi tháng 11/2026'));
          expect(viPrompt, contains('Hạn mức kế hoạch tháng 12/2026'));
          expect(
            viPrompt,
            contains('Tuyệt đối KHÔNG gọi điểm sức khỏe tài chính'),
          );

          // English
          LanguageController.currentLocale.value = const Locale('en', 'US');
          final enPrompt = AiPromptBuilder.buildStructuredPlanPrompt(
            summary: summary,
            draftPlan: draftPlan,
          );
          expect(enPrompt, contains('Financial health score for 11/2026'));
          expect(enPrompt, contains('Actual spent in 11/2026'));
          expect(enPrompt, contains('Planned limit for 12/2026'));
          expect(
            enPrompt,
            contains('NEVER attribute 11/2026\'s health score'),
          );
        } finally {
          LanguageController.currentLocale.value = originalLocale;
        }
      },
    );

    test(
      'TC-18: Bỏ tích Học tập và chỉ phê duyệt Ăn uống -> Khi xóa Ăn uống, toàn bộ Budget & Plan đã phê duyệt đều được dọn sạch',
      () async {
        await seedWalletAndUser();
        final categories = [
          Category(
            categoryId: 'c_study',
            userId: 'u1',
            name: 'Học tập',
            type: 'expense',
            icon: 'school',
            color: 0xFF2196F3,
            isEssential: true,
          ),
          Category(
            categoryId: 'c_food',
            userId: 'u1',
            name: 'Ăn uống',
            type: 'expense',
            icon: 'restaurant',
            color: 0xFFFF9800,
            isEssential: false,
          ),
        ];

        final incTx = makeTx(
          id: 'tx_inc',
          type: 'income',
          amount: 10000000,
          categoryId: 'c_inc',
          date: DateTime(2026, 5, 2),
        );
        final studyTx = makeTx(
          id: 'tx_study',
          type: 'expense',
          amount: 1000000,
          categoryId: 'c_study',
          date: DateTime(2026, 5, 6),
        );
        final foodTx = makeTx(
          id: 'tx_food',
          type: 'expense',
          amount: 2000000,
          categoryId: 'c_food',
          date: DateTime(2026, 5, 8),
        );
        for (final tx in [incTx, studyTx, foodTx]) {
          await fakeFirestore
              .collection('transactions')
              .doc(tx.transactionId)
              .set(tx.toMap());
        }

        final draftPlan = analytics.buildSequentialMonthlyPlan(
          userId: 'u1',
          sourceMonth: '05/2026',
          targetMonth: '06/2026',
          sourceMonthTx: [incTx, studyTx, foodTx],
          historicalMonthsTx: const [],
          categories: categories,
          existingTargetBudgets: const [],
          savingGoals: const [],
          referenceToday: DateTime(2026, 5, 20),
        );

        // Chỉ tích chọn c_food, bỏ tích c_study
        await firestoreService.commitMonthlyPlanTransactionally(
          planToCommit: draftPlan,
          selectedCategoryIds: {'c_food'},
          expectedExistingBudgets: {'c_food': null},
          submissionToken: 'tok_tc18',
          currentReferenceDate: DateTime(2026, 5, 20),
        );

        expect(
          (await firestoreService.getBudgetsSafely('u1', month: '06/2026'))
              .length,
          1,
        );

        // Xóa tx Ăn uống
        await firestoreService.deleteTransaction(
          foodTx,
          currentReferenceDate: DateTime(2026, 5, 21),
        );

        // Vì mục duy nhất được người dùng phê duyệt (c_food) đã bị xóa -> Không còn Budget lẫn Plan đã phê duyệt
        expect(
          await firestoreService.getBudgetsSafely('u1', month: '06/2026'),
          isEmpty,
        );
        expect(
          await firestoreService.getMonthlyPlan('u1', '06/2026'),
          isNull,
        );
      },
    );

    test(
      'TC-19: FinancialContextRevisionTracker.versionNotifier phát sự kiện đồng bộ khi xóa hoặc sửa giao dịch',
      () {
        int notifiedValue = -1;
        void listener() {
          notifiedValue = FinancialContextRevisionTracker.versionNotifier.value;
        }

        FinancialContextRevisionTracker.versionNotifier.addListener(listener);
        try {
          FinancialContextRevisionTracker.notifyDataMutated();
          expect(
            notifiedValue,
            FinancialContextRevisionTracker.localMutationVersion,
          );
        } finally {
          FinancialContextRevisionTracker.versionNotifier
              .removeListener(listener);
        }
      },
    );

    test(
      'TC-20: Kịch bản ví khởi tạo 5tr + thu 12tr (lương 10tr + thưởng 2tr) + khai báo thu nhập 10tr -> Phân tách đúng dòng tiền 12tr, thu nhập tham chiếu 10tr và định dạng dấu chấm',
      () {
        final originalLocale = LanguageController.currentLocale.value;
        try {
          LanguageController.currentLocale.value = const Locale('vi', 'VN');
          final wallets = [
            Wallet(
              walletId: 'w_cash',
              userId: 'u1',
              walletName: 'Tiền mặt',
              balance: 17000000, // 5tr ban đầu + 12tr thu nhập trong tháng 11
              type: 'cash',
              createdAt: DateTime(2026, 11, 1),
            ),
          ];
          final categories = [
            Category(
              categoryId: 'c_sal',
              userId: 'u1',
              name: 'Lương',
              type: 'income',
              icon: 'payments',
              color: 0xFF10B981,
            ),
            Category(
              categoryId: 'c_bonus',
              userId: 'u1',
              name: 'Thưởng',
              type: 'income',
              icon: 'card_giftcard',
              color: 0xFF10B981,
            ),
          ];
          final txList = [
            makeTx(
              id: 't1',
              type: 'income',
              amount: 10000000,
              categoryId: 'c_sal',
              date: DateTime(2026, 11, 17),
            ),
            makeTx(
              id: 't2',
              type: 'income',
              amount: 1000000,
              categoryId: 'c_bonus',
              date: DateTime(2026, 11, 17),
            ),
            makeTx(
              id: 't3',
              type: 'income',
              amount: 1000000,
              categoryId: 'c_bonus',
              date: DateTime(2026, 11, 17),
            ),
          ];

          final draftPlan = analytics.buildSequentialMonthlyPlan(
            userId: 'u1',
            sourceMonth: '11/2026',
            targetMonth: '12/2026',
            sourceMonthTx: txList,
            historicalMonthsTx: const [],
            categories: categories,
            existingTargetBudgets: const [],
            savingGoals: const [],
            wallets: wallets,
            declaredExpectedIncome: 10000000,
            referenceToday: DateTime(2026, 11, 17),
          );
          final issues = analytics.detectIssues(
            currentMonthTx: txList,
            lastMonthTx: const [],
            categories: categories,
            monthlyIncome: draftPlan.referenceIncome,
          );
          final summary = FinancialForecastService().generateSummary(
            activeWallets: wallets,
            currentMonthBudgets: const [],
            categories: categories,
            currentMonthTx: txList,
            preceding3MonthsTx: const [],
            monthlyIncome: draftPlan.referenceIncome,
            issues: issues,
            refDate: DateTime(2026, 11, 17),
          );

          // Dòng tiền ròng tháng 11 tính từ tổng thu thực tế (12tr) - chi (0)
          expect(summary.cashFlowAnalytics.totalIncome, 12000000.0);
          expect(summary.cashFlowAnalytics.netCashFlow, 12000000.0);
          expect(summary.monthEndForecast.currentTotalBalance, 17000000.0);

          // Kế hoạch tháng 12 dùng thu nhập tham chiếu 10tr đã khai báo, tiết kiệm mặc định 15% = 1.5tr
          expect(draftPlan.incomeMode, IncomeStabilityMode.declared);
          expect(draftPlan.referenceIncome, 10000000.0);
          expect(draftPlan.targetSavingAmount, 1500000.0);
          expect(draftPlan.dataTierUsed, DataSufficiencyTier.preliminary);

          final viPrompt = AiPromptBuilder.buildStructuredPlanPrompt(
            summary: summary,
            draftPlan: draftPlan,
          );
          expect(viPrompt, contains('12.000.000đ'));
          expect(viPrompt, contains('10.000.000đ'));
          expect(viPrompt, contains('1.500.000đ'));
          expect(viPrompt, contains('8.500.000đ'));
          expect(viPrompt, isNot(contains('12000000đ')));
          expect(viPrompt, isNot(contains('10000000đ')));
          expect(viPrompt, isNot(contains('1500000đ')));
          expect(viPrompt, contains('thu nhập dự kiến do người dùng khai báo'));
          expect(viPrompt, contains('chưa có danh mục chi tiêu'));

          // Kiểm tra fallback & hậu kiểm JSON cũng luôn giữ dấu chấm phân cách hàng nghìn
          final fallback = AiPromptBuilder.buildDeterministicFallbackInsight(
            draftPlan,
          );
          expect(fallback.savingStrategyNote, contains('1.500.000đ'));
          expect(fallback.savingStrategyNote, isNot(contains('1500000đ')));

          final parsedWithMissingDots = AiPromptBuilder.parseAndValidateStructuredInsight(
            rawText: '''
{
  "executiveSummary": "Tháng 11/2026 đạt 100/100 với tổng thu 12000000đ và thu nhập tham chiếu 10000000 VND.",
  "behavioralInsights": ["Đã thu 12000000 đ, thưởng 2000000₫ và tăng 1000 điểm thưởng chưa quy đổi."],
  "categoryActionTips": {"Ăn uống": "Giới hạn 1500000 đồng/tháng."},
  "savingStrategyNote": ""
}
''',
            draftPlan: draftPlan,
          );
          expect(parsedWithMissingDots, isNotNull);
          expect(
            parsedWithMissingDots!.executiveSummary,
            contains('12.000.000đ'),
          );
          expect(
            parsedWithMissingDots.executiveSummary,
            contains('10.000.000 VND'),
          );
          expect(parsedWithMissingDots.executiveSummary, contains('11/2026'));
          expect(parsedWithMissingDots.executiveSummary, contains('100/100'));
          expect(
            parsedWithMissingDots.behavioralInsights.first,
            contains('12.000.000 đ'),
          );
          expect(
            parsedWithMissingDots.behavioralInsights.first,
            contains('2.000.000₫'),
          );
          expect(
            parsedWithMissingDots.behavioralInsights.first,
            contains('1000 điểm'),
          );
          expect(
            parsedWithMissingDots.categoryActionTips['Ăn uống'],
            contains('1.500.000 đồng'),
          );
          expect(
            parsedWithMissingDots.savingStrategyNote,
            contains('1.500.000đ'),
          );
        } finally {
          LanguageController.currentLocale.value = originalLocale;
        }
      },
    );

    test(
      'TC-21: AiPromptBuilder.formatCurrencyNumbersInText bảo toàn số đã định dạng, % và ngày tháng',
      () {
        const input =
            'Tháng 11/2026 đạt 100/100 (100%): thu 12000000đ, đã chuẩn 1.500.000đ, phí nhỏ 500đ, giữ 1000000 VND và 2500000 đồng.';
        final output = AiPromptBuilder.formatCurrencyNumbersInText(input);
        expect(
          output,
          'Tháng 11/2026 đạt 100/100 (100%): thu 12.000.000đ, đã chuẩn 1.500.000đ, phí nhỏ 500đ, giữ 1.000.000 VND và 2.500.000 đồng.',
        );
      },
    );

    test(
      'TC-22: buildDeterministicFallbackInsight với summary tái hiện đúng cấu trúc và giọng văn chuẩn cố vấn',
      () {
        final originalLocale = LanguageController.currentLocale.value;
        LanguageController.currentLocale.value = const Locale('vi');
        try {
          final forecast = FinancialForecastService();
          final categories = [
            Category(
              categoryId: 'cat_salary',
              userId: 'u1',
              name: 'Lương',
              type: 'income',
              icon: 'work',
              color: 0xFF10B981,
            ),
            Category(
              categoryId: 'cat_bonus',
              userId: 'u1',
              name: 'Thưởng',
              type: 'income',
              icon: 'card_giftcard',
              color: 0xFF3B82F6,
            ),
            Category(
              categoryId: 'cat_fuel',
              userId: 'u1',
              name: 'Xăng xe',
              type: 'expense',
              icon: 'local_gas_station',
              color: 0xFFF59E0B,
              isEssential: true,
            ),
            Category(
              categoryId: 'cat_food',
              userId: 'u1',
              name: 'Ăn uống',
              type: 'expense',
              icon: 'restaurant',
              color: 0xFFEF4444,
              isEssential: false,
            ),
          ];
          final wallets = [
            Wallet(
              walletId: 'w_cash',
              userId: 'u1',
              walletName: 'Tiền mặt',
              type: 'cash',
              balance: 15500000,
              createdAt: DateTime(2026, 11, 1),
            ),
          ];
          final currentMonthTx = [
            makeTx(
              id: 't1',
              type: 'income',
              amount: 10000000,
              categoryId: 'cat_salary',
              date: DateTime(2026, 11, 5),
            ),
            makeTx(
              id: 't2',
              type: 'income',
              amount: 2000000,
              categoryId: 'cat_bonus',
              date: DateTime(2026, 11, 6),
            ),
            makeTx(
              id: 't3',
              type: 'expense',
              amount: 500000,
              categoryId: 'cat_fuel',
              date: DateTime(2026, 11, 10),
            ),
            makeTx(
              id: 't4',
              type: 'expense',
              amount: 1000000,
              categoryId: 'cat_food',
              date: DateTime(2026, 11, 12),
            ),
          ];

          final draftPlan = analytics.buildSequentialMonthlyPlan(
            userId: 'u1',
            sourceMonth: '11/2026',
            targetMonth: '12/2026',
            sourceMonthTx: currentMonthTx,
            historicalMonthsTx: const [],
            categories: categories,
            existingTargetBudgets: const [],
            savingGoals: const [],
            wallets: wallets,
            declaredExpectedIncome: 10000000,
            referenceToday: DateTime(2026, 11, 17),
          );

          final summary = forecast.generateSummary(
            activeWallets: wallets,
            currentMonthBudgets: const [],
            categories: categories,
            currentMonthTx: currentMonthTx,
            preceding3MonthsTx: const [],
            monthlyIncome: draftPlan.referenceIncome,
            issues: const [],
            savingGoals: const [],
            recurringSchedules: const [],
            refDate: DateTime(2026, 11, 17),
          );

          final fallback = AiService.buildDeterministicFallbackInsight(
            draftPlan,
            summary: summary,
          );

          expect(fallback.isFromFallback, isTrue);
          expect(fallback.executiveSummary, contains('11/2026'));
          expect(fallback.executiveSummary, contains('12.000.000đ'));
          expect(fallback.executiveSummary, contains('1.500.000đ'));
          expect(fallback.executiveSummary, contains('10.500.000đ'));
          expect(fallback.executiveSummary, contains('12/2026'));
          expect(fallback.executiveSummary, contains('10.000.000đ'));
          expect(fallback.executiveSummary, contains('500.000đ'));
          expect(fallback.executiveSummary, contains('1.000.000đ'));

          expect(fallback.behavioralInsights.length, 2);
          expect(fallback.behavioralInsights[0], contains('1.500.000đ'));
          expect(fallback.behavioralInsights[1], contains('Xăng xe'));
          expect(fallback.behavioralInsights[1], contains('500.000đ'));
          expect(fallback.behavioralInsights[1], contains('Ăn uống'));
          expect(fallback.behavioralInsights[1], contains('1.000.000đ'));

          expect(fallback.savingStrategyNote, contains('1.500.000đ'));
          expect(fallback.savingStrategyNote, contains('10.000.000đ'));
          expect(fallback.savingStrategyNote, isNot(startsWith('🎯')));
        } finally {
          LanguageController.currentLocale.value = originalLocale;
        }
      },
    );

    test(
      'TC-23: explainFinancialInsightsStructured tự động thử model tiếp theo khi model đầu trả JSON lỗi và làm sạch bullet/emoji trùng',
      () async {
        final originalLocale = LanguageController.currentLocale.value;
        LanguageController.currentLocale.value = const Locale('vi');
        try {
          final forecast = FinancialForecastService();
          final draftPlan = analytics.buildSequentialMonthlyPlan(
            userId: 'u1',
            sourceMonth: '11/2026',
            targetMonth: '12/2026',
            sourceMonthTx: [
              makeTx(
                id: 't1',
                type: 'income',
                amount: 10000000,
                categoryId: 'cat_salary',
                date: DateTime(2026, 11, 5),
              ),
            ],
            historicalMonthsTx: const [],
            categories: const [],
            existingTargetBudgets: const [],
            savingGoals: const [],
            wallets: [
              Wallet(
                walletId: 'w1',
                userId: 'u1',
                walletName: 'Ví',
                type: 'cash',
                balance: 10000000,
                createdAt: DateTime(2026, 11, 1),
              ),
            ],
            declaredExpectedIncome: 10000000,
            referenceToday: DateTime(2026, 11, 17),
          );
          final summary = forecast.generateSummary(
            activeWallets: [
              Wallet(
                walletId: 'w1',
                userId: 'u1',
                walletName: 'Ví',
                type: 'cash',
                balance: 10000000,
                createdAt: DateTime(2026, 11, 1),
              ),
            ],
            currentMonthBudgets: const [],
            categories: const [],
            currentMonthTx: const [],
            preceding3MonthsTx: const [],
            monthlyIncome: 10000000,
            issues: const [],
            savingGoals: const [],
            recurringSchedules: const [],
            refDate: DateTime(2026, 11, 17),
          );

          final attempted = <String>[];
          final aiService = AiService(
            runtimeConfigOverride: AiRuntimeConfig.defaults().copyWith(
              primaryModel: 'gemini-3.5-flash',
              fallbackModels: const ['gemini-3.5-flash-lite'],
            ),
            allowMissingApiKeyForTest: true,
            contentGeneratorOverride: (modelName, content, temp) async {
              attempted.add(modelName);
              if (modelName == 'gemini-3.5-flash') {
                return 'Xin lỗi, đây không phải JSON hợp lệ!';
              }
              return '''
{
  "executiveSummary": "Sức khỏe tài chính tháng 11/2026 đạt 100/100.\\nSang tháng 12/2026, tiết kiệm 1500000đ.",
  "behavioralInsights": [
    "• Trong tháng 11/2026 chưa ghi nhận khoản chi tiêu nào.",
    "- Cần duy trì kỷ luật ghi chép."
  ],
  "categoryActionTips": {},
  "savingStrategyNote": "🎯 Phân bổ ngay 1500000đ khi nhận lương."
}
''';
            },
          );

          final result = await aiService.explainFinancialInsightsStructured(
            summary: summary,
            draftPlan: draftPlan,
          );

          expect(
            attempted.take(2).toList(),
            equals(['gemini-3.5-flash', 'gemini-3.5-flash-lite']),
          );
          expect(result.isFromFallback, isFalse);
          expect(result.executiveSummary, isNot(contains('\n')));
          expect(result.executiveSummary, contains('1.500.000đ'));
          expect(result.behavioralInsights.first, isNot(startsWith('•')));
          expect(result.behavioralInsights.last, isNot(startsWith('-')));
          expect(result.savingStrategyNote, isNot(startsWith('🎯')));
          expect(result.savingStrategyNote, contains('1.500.000đ'));
        } finally {
          LanguageController.currentLocale.value = originalLocale;
        }
      },
    );
  });
}

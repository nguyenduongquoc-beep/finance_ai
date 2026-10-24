import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/budget_model.dart';
import '../../models/category_model.dart';
import '../../models/transaction_model.dart';
import '../../services/firestore_service.dart';
import '../../utils/constants.dart';
import '../../utils/formatters.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/budget_month_selector.dart';
import '../../widgets/budget_progress_card.dart';
import '../../widgets/stream_error_widget.dart';
import 'budget_setup_screen.dart';

/// Bộ lọc trạng thái ngân sách theo danh mục.
enum _BudgetFilter { all, over, near, safe }

/// Màn hình Ngân sách (Redesign Ticket 025 khớp 100% mockup Figma)
class BudgetManagementScreen extends StatefulWidget {
  const BudgetManagementScreen({super.key});

  @override
  State<BudgetManagementScreen> createState() => _BudgetManagementScreenState();
}

class _BudgetManagementScreenState extends State<BudgetManagementScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  DateTime _selectedMonth =
      DateTime(DateTime.now().year, DateTime.now().month, 1);
  _BudgetFilter _filter = _BudgetFilter.all;

  void _showMonthPicker() {
    int selectedM = _selectedMonth.month;
    int selectedY = _selectedMonth.year;
    final nowY = DateTime.now().year;
    final years = List.generate(5, (i) => nowY - 2 + i);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          return AlertDialog(
            title: const Text('Chọn tháng/năm'),
            content: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                DropdownButton<int>(
                  value: selectedM,
                  items: List.generate(12, (i) => i + 1)
                      .map((m) =>
                          DropdownMenuItem(value: m, child: Text('Tháng $m')))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setDlgState(() => selectedM = v);
                  },
                ),
                const SizedBox(width: 20),
                DropdownButton<int>(
                  value: selectedY,
                  items: years
                      .map((y) =>
                          DropdownMenuItem(value: y, child: Text('Năm $y')))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setDlgState(() => selectedY = v);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Hủy'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _selectedMonth = DateTime(selectedY, selectedM, 1);
                  });
                },
                child: const Text('Chọn',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _shiftMonth(int delta) {
    setState(() {
      _selectedMonth =
          DateTime(_selectedMonth.year, _selectedMonth.month + delta, 1);
    });
  }

  Future<void> _openSetup() async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => BudgetSetupScreen(initialMonth: _selectedMonth),
      ),
    );
    if (updated == true) setState(() {});
  }

  Widget _buildMonthSelector(BuildContext context) {
    return BudgetMonthSelector(
      month: _selectedMonth,
      onTap: _showMonthPicker,
      onPrevious: () => _shiftMonth(-1),
      onNext: () => _shiftMonth(1),
    );
  }

  Widget _buildFilterChips(
    BuildContext context, {
    required int total,
    required int over,
    required int near,
    required int safe,
  }) {
    Widget chip(_BudgetFilter f, String label, int count, Color color) {
      final selected = _filter == f;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          showCheckmark: false,
          selected: selected,
          selectedColor: color,
          label: Text('$label · $count'),
          labelStyle: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : context.appTextPrimary,
          ),
          onSelected: (_) => setState(() => _filter = f),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip(_BudgetFilter.all, 'Tất cả', total, AppColors.primary),
          if (over > 0)
            chip(_BudgetFilter.over, 'Vượt', over, AppColors.expense),
          if (near > 0)
            chip(_BudgetFilter.near, 'Sắp hết', near, AppColors.warning),
          if (safe > 0)
            chip(_BudgetFilter.safe, 'An toàn', safe, AppColors.income),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final monthKey = AppFormatters.month(_selectedMonth);
    final monthStart = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final monthEnd = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 1)
        .subtract(const Duration(seconds: 1));

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Ngân sách'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        elevation: 0,
      ),
      body: StreamBuilder<List<Category>>(
        stream: _firestoreService.streamCategories(uid, type: 'expense'),
        builder: (context, catSnap) {
          if (catSnap.hasError)
            return StreamErrorWidget(error: catSnap.error.toString());
          final categories = catSnap.data ?? [];

          return StreamBuilder<List<Budget>>(
            stream: _firestoreService.streamBudgets(uid, month: monthKey),
            builder: (context, budgetSnap) {
              if (budgetSnap.hasError) {
                return StreamErrorWidget(error: budgetSnap.error.toString());
              }
              final budgets = budgetSnap.data ?? [];

              return StreamBuilder<List<AppTransaction>>(
                stream: _firestoreService.streamTransactions(uid,
                    from: monthStart, to: monthEnd),
                builder: (context, txSnap) {
                  if (txSnap.hasError) {
                    return StreamErrorWidget(error: txSnap.error.toString());
                  }
                  if (!budgetSnap.hasData || !txSnap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final monthTx = txSnap.data ?? [];
                  final Map<String, double> spentByCategory = {};
                  for (final tx in monthTx.where((t) => t.type == 'expense')) {
                    spentByCategory[tx.categoryId] =
                        (spentByCategory[tx.categoryId] ?? 0) + tx.amount;
                  }

                  double totalLimit = 0;
                  double totalSpent = 0;
                  int overCount = 0;
                  int nearCount = 0;
                  int safeCount = 0;
                  for (final b in budgets) {
                    final spent = spentByCategory[b.categoryId] ?? 0;
                    totalLimit += b.limit;
                    totalSpent += spent;
                    if (b.isOverBudget(spent)) {
                      overCount++;
                    } else if (b.isNearLimit(spent)) {
                      nearCount++;
                    } else {
                      safeCount++;
                    }
                  }

                  // Sắp xếp: mức sử dụng cao nhất lên đầu để người dùng thấy rủi ro trước.
                  final sorted = [...budgets]..sort((a, b) => b
                      .percentUsed(spentByCategory[b.categoryId] ?? 0)
                      .compareTo(
                          a.percentUsed(spentByCategory[a.categoryId] ?? 0)));

                  var activeFilter = _filter;
                  if ((activeFilter == _BudgetFilter.over && overCount == 0) ||
                      (activeFilter == _BudgetFilter.near && nearCount == 0) ||
                      (activeFilter == _BudgetFilter.safe && safeCount == 0)) {
                    activeFilter = _BudgetFilter.all;
                  }

                  final visible = sorted.where((b) {
                    final spent = spentByCategory[b.categoryId] ?? 0;
                    switch (activeFilter) {
                      case _BudgetFilter.over:
                        return b.isOverBudget(spent);
                      case _BudgetFilter.near:
                        return b.isNearLimit(spent);
                      case _BudgetFilter.safe:
                        return !b.isOverBudget(spent) && !b.isNearLimit(spent);
                      case _BudgetFilter.all:
                        return true;
                    }
                  }).toList();

                  return Column(
                    children: [
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          children: [
                            _buildMonthSelector(context),
                            const SizedBox(height: 16),
                            if (budgets.isEmpty)
                              _EmptyBudgets(onSetup: _openSetup)
                            else ...[
                              _BudgetHero(
                                month: _selectedMonth,
                                totalSpent: totalSpent,
                                totalLimit: totalLimit,
                                overCount: overCount,
                                nearCount: nearCount,
                              ),
                              const SizedBox(height: 22),
                              Padding(
                                padding:
                                    const EdgeInsets.only(left: 2, bottom: 12),
                                child: Text(
                                  'Hạn mức theo danh mục',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: context.appTextPrimary,
                                  ),
                                ),
                              ),
                              _buildFilterChips(
                                context,
                                total: budgets.length,
                                over: overCount,
                                near: nearCount,
                                safe: safeCount,
                              ),
                              const SizedBox(height: 12),
                              for (final budget in visible)
                                BudgetProgressCard(
                                  budget: budget,
                                  spentAmount:
                                      spentByCategory[budget.categoryId] ?? 0,
                                  category: categories
                                      .where((c) =>
                                          c.categoryId == budget.categoryId)
                                      .firstOrNull,
                                  onTap: _openSetup,
                                ),
                            ],
                          ],
                        ),
                      ),
                      SafeArea(
                        top: false,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            border: Border(
                                top: BorderSide(color: context.appBorder)),
                          ),
                          child: AppButton(
                            text: 'Thiết lập ngân sách',
                            icon: Icons.tune_rounded,
                            onPressed: _openSetup,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// Thẻ tổng quan ngân sách tháng: đã chi / hạn mức, % sử dụng, còn lại, chi tiêu an toàn mỗi ngày.
class _BudgetHero extends StatelessWidget {
  final DateTime month;
  final double totalSpent;
  final double totalLimit;
  final int overCount;
  final int nearCount;

  const _BudgetHero({
    required this.month,
    required this.totalSpent,
    required this.totalLimit,
    required this.overCount,
    required this.nearCount,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = totalLimit <= 0 ? 0.0 : totalSpent / totalLimit;
    final isOver = totalSpent > totalLimit && totalLimit > 0;
    final isNear = !isOver && ratio >= 0.8;
    final remaining = totalLimit - totalSpent;

    final now = DateTime.now();
    final isCurrent = month.year == now.year && month.month == now.month;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final daysLeft = isCurrent ? daysInMonth - now.day + 1 : null;
    final perDay =
        (daysLeft != null && remaining > 0) ? remaining / daysLeft : null;

    final List<Color> gradient = isOver
        ? const [Color(0xFFD0584C), Color(0xFF7E2620)]
        : isNear
            ? const [Color(0xFFC58A2B), Color(0xFF7A4E10)]
            : const [Color(0xFF2A86A6), Color(0xFF14485B)];

    final String statusText = isOver
        ? 'Đã vượt ngân sách'
        : isNear
            ? 'Sắp chạm hạn mức'
            : 'Trong tầm kiểm soát';
    final IconData statusIcon = isOver
        ? Icons.warning_amber_rounded
        : isNear
            ? Icons.error_outline_rounded
            : Icons.verified_rounded;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -50,
            top: -60,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withAlpha(16),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Đã chi trong tháng',
                    style: TextStyle(
                      color: Colors.white.withAlpha(220),
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(36),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 13, color: Colors.white),
                        const SizedBox(width: 4),
                        Text(
                          statusText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        AppFormatters.compactCurrency(totalSpent),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 32,
                          color: Colors.white,
                          letterSpacing: -0.8,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      '/ ${AppFormatters.compactCurrency(totalLimit)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withAlpha(200),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: ratio.clamp(0.0, 1.0),
                  minHeight: 9,
                  backgroundColor: Colors.white.withAlpha(46),
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Đã dùng ${(ratio * 100).round()}% hạn mức',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withAlpha(215),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _heroStat(
                      isOver ? 'Đã vượt' : 'Còn lại',
                      AppFormatters.compactCurrency(remaining.abs(), unit: '₫'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _heroStat(
                      daysLeft != null
                          ? 'Chi mỗi ngày (còn $daysLeft ngày)'
                          : 'Số danh mục',
                      daysLeft != null
                          ? (perDay != null
                              ? AppFormatters.compactCurrency(perDay, unit: '₫')
                              : '—')
                          : '${overCount + nearCount} cần chú ý',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroStat(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(30),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.white.withAlpha(205),
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Trạng thái chưa thiết lập ngân sách cho tháng đang chọn.
class _EmptyBudgets extends StatelessWidget {
  final VoidCallback onSetup;

  const _EmptyBudgets({required this.onSetup});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: AppCard(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primary.withAlpha(24),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.savings_rounded,
                  size: 34, color: AppColors.primary),
            ),
            const SizedBox(height: 18),
            Text(
              'Chưa có ngân sách tháng này',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: context.appTextPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Đặt hạn mức cho từng danh mục chi tiêu để ứng dụng cảnh báo khi bạn sắp chi vượt.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, height: 1.4, color: context.appTextSecondary),
            ),
            const SizedBox(height: 22),
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: onSetup,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Thiết lập ngay'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

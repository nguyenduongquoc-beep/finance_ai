import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/budget_model.dart';
import '../../models/category_model.dart';
import '../../services/firestore_service.dart';
import '../../utils/constants.dart';
import '../../utils/formatters.dart';
import '../../utils/category_icons.dart';
import '../../widgets/app_button.dart';
import '../../widgets/budget_month_selector.dart';
import '../../widgets/app_snackbar.dart';

class _BudgetItemDraft {
  final String? budgetId; // null nếu là item mới chưa tạo trên Firestore
  final String categoryId;
  final String categoryName;
  final TextEditingController controller;

  _BudgetItemDraft({
    this.budgetId,
    required this.categoryId,
    required this.categoryName,
    required double limit,
  }) : controller = TextEditingController(
          text: limit > 0 ? AppFormatters.number(limit) : '',
        );
}

/// Màn hình Thiết lập ngân sách (Ticket 025)
class BudgetSetupScreen extends StatefulWidget {
  final DateTime initialMonth;

  const BudgetSetupScreen({
    super.key,
    required this.initialMonth,
  });

  @override
  State<BudgetSetupScreen> createState() => _BudgetSetupScreenState();
}

class _BudgetSetupScreenState extends State<BudgetSetupScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  late DateTime _selectedMonth;
  bool _isLoading = true;
  bool _isSaving = false;

  List<Category> _allExpenseCategories = [];
  final List<_BudgetItemDraft> _drafts = [];
  final Set<String> _deletedBudgetIds = {};

  @override
  void initState() {
    super.initState();
    _selectedMonth =
        DateTime(widget.initialMonth.year, widget.initialMonth.month, 1);
    _loadData();
  }

  @override
  void dispose() {
    for (final draft in _drafts) {
      draft.controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    try {
      // Clear draft cũ
      for (final draft in _drafts) {
        draft.controller.dispose();
      }
      _drafts.clear();
      _deletedBudgetIds.clear();

      final monthKey = AppFormatters.month(_selectedMonth);
      final catList =
          await _firestoreService.streamCategories(uid, type: 'expense').first;
      final budgetList =
          await _firestoreService.streamBudgets(uid, month: monthKey).first;

      _allExpenseCategories = catList;

      for (final b in budgetList) {
        final cat =
            catList.where((c) => c.categoryId == b.categoryId).firstOrNull;
        _drafts.add(_BudgetItemDraft(
          budgetId: b.budgetId,
          categoryId: b.categoryId,
          categoryName: cat?.name ?? 'Danh mục (Đã bị xóa)',
          limit: b.limit,
        ));
      }
    } catch (e) {
      debugPrint('❌ Lỗi khi tải dữ liệu thiết lập ngân sách: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

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
                  _loadData();
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

  void _addCategoryDialog() {
    final existingCatIds = _drafts.map((d) => d.categoryId).toSet();
    final availableCategories = _allExpenseCategories
        .where((c) => !existingCatIds.contains(c.categoryId))
        .toList();

    if (availableCategories.isEmpty) {
      AppSnackbar.show(
          context, 'Tất cả danh mục chi tiêu đã được thêm ngân sách.',
          isError: true);
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.appCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: availableCategories.length > 5 ? 0.65 : 0.5,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        builder: (ctx, scrollController) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.appBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Chọn danh mục chi tiêu',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: context.appTextPrimary,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                itemCount: availableCategories.length,
                itemBuilder: (_, i) {
                  final c = availableCategories[i];
                  final color = Color(c.color);
                  return ListTile(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    leading: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: color.withAlpha(30),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(categoryIconData(c.icon),
                          color: color, size: 21),
                    ),
                    title: Text(
                      c.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: context.appTextPrimary,
                      ),
                    ),
                    trailing: Icon(Icons.add_circle_outline_rounded,
                        color: context.appTextSecondary),
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() {
                        _drafts.add(_BudgetItemDraft(
                          categoryId: c.categoryId,
                          categoryName: c.name,
                          limit: 0,
                        ));
                      });
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyPreviousMonthBudgets() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final prevMonthDate =
        DateTime(_selectedMonth.year, _selectedMonth.month - 1, 1);
    final prevMonthKey = AppFormatters.month(prevMonthDate);

    try {
      final prevBudgets =
          await _firestoreService.streamBudgets(uid, month: prevMonthKey).first;
      if (prevBudgets.isEmpty) {
        if (mounted) {
          AppSnackbar.show(
              context, 'Tháng trước ($prevMonthKey) chưa có ngân sách nào.',
              isError: true);
        }
        return;
      }

      final existingCatIds = _drafts.map((d) => d.categoryId).toSet();
      int addedCount = 0;

      for (final pb in prevBudgets) {
        if (!existingCatIds.contains(pb.categoryId)) {
          final cat = _allExpenseCategories
              .where((c) => c.categoryId == pb.categoryId)
              .firstOrNull;
          _drafts.add(_BudgetItemDraft(
            categoryId: pb.categoryId,
            categoryName: cat?.name ?? 'Danh mục',
            limit: pb.limit,
          ));
          addedCount++;
        }
      }

      if (mounted) {
        if (addedCount > 0) {
          setState(() {});
          AppSnackbar.show(context,
              'Đã sao chép $addedCount danh mục từ tháng $prevMonthKey.');
        } else {
          AppSnackbar.show(context,
              'Tất cả danh mục từ tháng trước đã có trong danh sách hiện tại.');
        }
      }
    } catch (e) {
      debugPrint('❌ Lỗi khi sao chép ngân sách tháng trước: $e');
    }
  }

  Future<void> _saveBudgets() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final monthKey = AppFormatters.month(_selectedMonth);

    // Kiểm tra dữ liệu trước khi ghi để không báo "thành công" khi thực tế không lưu gì.
    if (_drafts.isEmpty && _deletedBudgetIds.isEmpty) {
      AppSnackbar.show(
        context,
        'Chưa có hạn mức nào để lưu. Hãy thêm danh mục và nhập hạn mức trước.',
        isError: true,
      );
      return;
    }

    for (final draft in _drafts) {
      final limit = AppFormatters.parseCurrencyInput(draft.controller.text);
      if (limit <= 0) {
        AppSnackbar.show(
          context,
          'Vui lòng nhập hạn mức lớn hơn 0 cho "${draft.categoryName}".',
          isError: true,
        );
        return;
      }
    }

    setState(() => _isSaving = true);
    try {
      final futures = <Future<void>>[];

      // 1. Xóa các budget bị xóa
      for (final id in _deletedBudgetIds) {
        futures.add(_firestoreService.deleteBudget(id));
      }

      // 2. Thêm mới / Cập nhật
      for (final draft in _drafts) {
        final limit = AppFormatters.parseCurrencyInput(draft.controller.text);
        if (draft.budgetId != null) {
          futures.add(_firestoreService
              .updateBudget(draft.budgetId!, {'limit': limit}));
        } else {
          futures.add(_firestoreService.createBudget(Budget(
            budgetId: '',
            userId: uid,
            categoryId: draft.categoryId,
            limit: limit,
            month: monthKey,
          )));
        }
      }

      await Future.wait(futures);

      if (mounted) {
        AppSnackbar.show(context, 'Lưu thiết lập ngân sách thành công!');
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('❌ Lỗi khi lưu ngân sách: $e');
      if (mounted) {
        AppSnackbar.show(context, 'Không thể lưu ngân sách. Vui lòng thử lại.',
            isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primary.withAlpha(24),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.tune_rounded,
                  size: 32, color: AppColors.primary),
            ),
            const SizedBox(height: 18),
            Text(
              'Chưa có hạn mức nào',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: context.appTextPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Thêm danh mục chi tiêu rồi đặt hạn mức cho tháng này, hoặc sao chép nhanh từ tháng trước.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, height: 1.45, color: context.appTextSecondary),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _isSaving ? null : _copyPreviousMonthBudgets,
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Sao chép từ tháng trước'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(color: context.appBorder),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDraftCard(BuildContext context, int index) {
    final draft = _drafts[index];
    final cat = _allExpenseCategories
        .where((c) => c.categoryId == draft.categoryId)
        .firstOrNull;
    final isDeleted = cat == null;
    final color = cat != null ? Color(cat.color) : AppColors.slate500;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 14),
      decoration: BoxDecoration(
        color: context.appCard,
        borderRadius: BorderRadius.circular(AppColors.radiusCard),
        border: Border.all(color: context.appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withAlpha(30),
                  borderRadius: BorderRadius.circular(13),
                ),
                child:
                    Icon(categoryIconData(cat?.icon), color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  draft.categoryName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: isDeleted
                        ? context.appTextSecondary
                        : context.appTextPrimary,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Xóa hạn mức',
                icon: const Icon(Icons.delete_outline_rounded,
                    color: AppColors.expense),
                onPressed: () {
                  setState(() {
                    if (draft.budgetId != null) {
                      _deletedBudgetIds.add(draft.budgetId!);
                    }
                    final removed = _drafts.removeAt(index);
                    // Controller được dispose cùng lúc để tránh rò rỉ bộ nhớ.
                    WidgetsBinding.instance.addPostFrameCallback(
                        (_) => removed.controller.dispose());
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextField(
              controller: draft.controller,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: context.appTextPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Nhập hạn mức',
                labelText: 'Hạn mức tháng',
                suffixText: 'VNĐ',
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                fillColor: context.appInputFill,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.appBorder),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalLimit = _drafts.fold<double>(
      0,
      (sum, d) => sum + AppFormatters.parseCurrencyInput(d.controller.text),
    );

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Thiết lập ngân sách'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            tooltip: 'Sao chép tháng trước',
            onPressed: _isSaving ? null : _copyPreviousMonthBudgets,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: BudgetMonthSelector(
                    month: _selectedMonth,
                    onTap: _showMonthPicker,
                  ),
                ),

                if (_drafts.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${_drafts.length} danh mục',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: context.appTextPrimary,
                          ),
                        ),
                        Flexible(
                          child: Text(
                            'Tổng hạn mức: ${AppFormatters.compactCurrency(totalLimit, unit: '₫')}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Danh sách thiết lập hạn mức
                Expanded(
                  child: _drafts.isEmpty
                      ? _buildEmptyState(context)
                      : ListView.builder(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: _drafts.length,
                          itemBuilder: (context, index) =>
                              _buildDraftCard(context, index),
                        ),
                ),

                // Bottom Bar
                SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    decoration: BoxDecoration(
                      color: context.appCard,
                      border: Border(
                          top:
                              BorderSide(color: context.appBorder, width: 0.5)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(50),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              side: BorderSide(color: context.appBorder),
                            ),
                            onPressed: _addCategoryDialog,
                            icon: const Icon(Icons.add,
                                size: 20, color: AppColors.primary),
                            label: const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'Thêm danh mục',
                                maxLines: 1,
                                style: TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppButton(
                            text: 'Lưu',
                            isLoading: _isSaving,
                            onPressed: _saveBudgets,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/category_model.dart';
import '../../models/transaction_model.dart';
import '../../services/firestore_service.dart';
import '../../utils/category_icons.dart';
import '../../utils/constants.dart';
import '../../utils/formatters.dart';
import '../../widgets/app_card.dart';
import '../../widgets/stream_error_widget.dart';
import '../../widgets/app_snackbar.dart';

/// 14. Quản lý danh mục — Phân loại thu chi, icon & màu trực quan, thống kê chi tiết theo tháng
class CategoryManagementScreen extends StatefulWidget {
  const CategoryManagementScreen({super.key});

  @override
  State<CategoryManagementScreen> createState() =>
      _CategoryManagementScreenState();
}

class _CategoryManagementScreenState extends State<CategoryManagementScreen> {
  final _firestoreService = FirestoreService();
  String _selectedType = 'expense'; // 'expense' | 'income'

  static const List<Color> _colorOptions = [
    Color(0xFFC0453A), // Red
    Color(0xFF2E8B57), // Green
    Color(0xFF1F6F8B), // Primary Blue
    Color(0xFFB7791F), // Orange/Amber
    Color(0xFF7A5FC9), // Purple
    Color(0xFF2B87A8), // Light Blue
    Color(0xFFD946EF), // Pink
    Color(0xFF0D9488), // Teal
    Color(0xFF854D0E), // Brown
    Color(0xFF475569), // Slate
  ];

  static const List<Map<String, dynamic>> _iconOptions = [
    {'name': 'restaurant', 'label': 'Ăn uống'},
    {'name': 'shopping_bag', 'label': 'Mua sắm'},
    {'name': 'local_gas_station', 'label': 'Di chuyển'},
    {'name': 'receipt_long', 'label': 'Hóa đơn'},
    {'name': 'work', 'label': 'Lương/Công việc'},
    {'name': 'card_giftcard', 'label': 'Thưởng/Quà'},
    {'name': 'storefront', 'label': 'Kinh doanh'},
    {'name': 'school', 'label': 'Giáo dục'},
    {'name': 'movie', 'label': 'Giải trí'},
    {'name': 'flight', 'label': 'Du lịch'},
    {'name': 'local_hospital', 'label': 'Y tế'},
    {'name': 'category', 'label': 'Khác'},
  ];

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Danh mục phân loại'),
        elevation: 0,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 3,
        onPressed: () => _showCategorySheet(context, uid),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Thêm danh mục',
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: StreamBuilder<List<Category>>(
        stream: _firestoreService.streamCategories(uid),
        builder: (context, catSnap) {
          if (catSnap.hasError)
            return StreamErrorWidget(error: catSnap.error.toString());
          final allCategories = catSnap.data ?? [];
          if (!catSnap.hasData)
            return const Center(
                child: CircularProgressIndicator(color: AppColors.primary));

          final expenseCategories =
              allCategories.where((c) => c.type == 'expense').toList();
          final incomeCategories =
              allCategories.where((c) => c.type == 'income').toList();
          final currentCategories =
              _selectedType == 'expense' ? expenseCategories : incomeCategories;

          return StreamBuilder<List<AppTransaction>>(
            stream: _firestoreService.streamTransactions(uid, from: monthStart),
            builder: (context, txSnap) {
              final monthTx = txSnap.data ?? [];
              final Map<String, double> totalsByCategory = {};
              double totalAmountInType = 0;

              for (final tx in monthTx.where((t) => t.type == _selectedType)) {
                totalsByCategory[tx.categoryId] =
                    (totalsByCategory[tx.categoryId] ?? 0) + tx.amount;
                totalAmountInType += tx.amount;
              }

              return Column(
                children: [
                  // 1. Hero Summary Card
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: _buildSummaryHero(
                      context: context,
                      type: _selectedType,
                      categoryCount: currentCategories.length,
                      totalAmount: totalAmountInType,
                    ),
                  ),

                  // 2. Segmented Pill Tab Bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: context.appInputFill,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildTabButton(
                              label: 'Chi tiêu',
                              count: expenseCategories.length,
                              isSelected: _selectedType == 'expense',
                              activeColor: AppColors.expense,
                              onTap: () =>
                                  setState(() => _selectedType = 'expense'),
                            ),
                          ),
                          Expanded(
                            child: _buildTabButton(
                              label: 'Thu nhập',
                              count: incomeCategories.length,
                              isSelected: _selectedType == 'income',
                              activeColor: AppColors.income,
                              onTap: () =>
                                  setState(() => _selectedType = 'income'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // 3. Category List
                  Expanded(
                    child: currentCategories.isEmpty
                        ? _buildEmptyState(context, _selectedType, uid)
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                            itemCount: currentCategories.length,
                            itemBuilder: (context, i) {
                              final c = currentCategories[i];
                              final amount =
                                  totalsByCategory[c.categoryId] ?? 0.0;
                              final share = totalAmountInType <= 0
                                  ? 0.0
                                  : (amount / totalAmountInType)
                                      .clamp(0.0, 1.0);

                              return _buildCategoryCard(
                                context: context,
                                category: c,
                                monthlyAmount: amount,
                                shareOfTotal: share,
                                allCategoriesInType: currentCategories,
                                uid: uid,
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildSummaryHero({
    required BuildContext context,
    required String type,
    required int categoryCount,
    required double totalAmount,
  }) {
    final isExpense = type == 'expense';
    final label =
        isExpense ? 'Tổng chi tiêu tháng này' : 'Tổng thu nhập tháng này';
    final themeColor =
        isExpense ? const Color(0xFFC0453A) : const Color(0xFF2E8B57);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.appCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.appBorder),
        boxShadow: [
          BoxShadow(
            color:
                Colors.black.withValues(alpha: context.isDarkMode ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: themeColor.withValues(
                  alpha: context.isDarkMode ? 0.25 : 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              isExpense
                  ? Icons.arrow_outward_rounded
                  : Icons.arrow_downward_rounded,
              color: themeColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: context.appTextSecondary,
                  ),
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    AppFormatters.compactCurrency(totalAmount, unit: '₫'),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: context.appTextPrimary,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: context.appInputFill,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$categoryCount danh mục',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.appTextSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required String label,
    required int count,
    required bool isSelected,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? context.appCard : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black
                        .withValues(alpha: context.isDarkMode ? 0.3 : 0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? context.appTextPrimary
                    : context.appTextSecondary,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected
                    ? activeColor.withValues(
                        alpha: context.isDarkMode ? 0.25 : 0.12)
                    : context.appBorder.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? activeColor : context.appTextSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryCard({
    required BuildContext context,
    required Category category,
    required double monthlyAmount,
    required double shareOfTotal,
    required List<Category> allCategoriesInType,
    required String uid,
  }) {
    final catColor = Color(category.color);

    return AppCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      onTap: () => _showCategorySheet(context, uid, category: category),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: catColor.withValues(
                      alpha: context.isDarkMode ? 0.25 : 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(categoryIconData(category.icon),
                    color: catColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: context.appTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      monthlyAmount > 0
                          ? 'Tháng này: ${AppFormatters.compactCurrency(monthlyAmount, unit: '₫')}'
                          : 'Chưa có giao dịch tháng này',
                      style: TextStyle(
                        fontSize: 12,
                        color: monthlyAmount > 0
                            ? context.appTextPrimary
                            : context.appTextSecondary,
                        fontWeight: monthlyAmount > 0
                            ? FontWeight.w500
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded,
                    color: context.appTextSecondary, size: 20),
                tooltip: 'Tùy chọn',
                onSelected: (action) {
                  if (action == 'edit') {
                    _showCategorySheet(context, uid, category: category);
                  } else if (action == 'delete') {
                    _handleDeleteCategory(
                        context, uid, category, allCategoriesInType);
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('Chỉnh sửa'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline_rounded,
                            size: 18, color: AppColors.expense),
                        SizedBox(width: 8),
                        Text('Xóa danh mục',
                            style: TextStyle(color: AppColors.expense)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (monthlyAmount > 0) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: shareOfTotal,
                        minHeight: 5,
                        backgroundColor: context.appInputFill,
                        valueColor: AlwaysStoppedAnimation<Color>(catColor),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${(shareOfTotal * 100).round()}%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: context.appTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, String type, String uid) {
    final label = type == 'expense' ? 'chi tiêu' : 'thu nhập';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: AppCard(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.category_rounded,
                    size: 36, color: AppColors.primary),
              ),
              const SizedBox(height: 16),
              Text(
                'Chưa có danh mục $label nào',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: context.appTextPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                'Tạo các danh mục để phân loại dòng tiền và theo dõi chi tiêu thông minh hơn.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13, height: 1.4, color: context.appTextSecondary),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => _showCategorySheet(context, uid),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Thêm danh mục'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleDeleteCategory(
    BuildContext context,
    String uid,
    Category c,
    List<Category> categories,
  ) async {
    try {
      final inUse =
          await _firestoreService.checkCategoryInUse(uid, c.categoryId);
      if (!inUse) {
        if (!context.mounted) return;
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Xóa danh mục?'),
            content: Text(
              'Bạn có chắc chắn muốn xóa danh mục "${c.name}"? Hành động này không thể hoàn tác.',
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Hủy')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Xóa',
                    style: TextStyle(color: AppColors.expense)),
              ),
            ],
          ),
        );
        if (confirm == true) {
          await _firestoreService.deleteCategory(c.categoryId);
          if (context.mounted) {
            AppSnackbar.show(context, 'Đã xóa danh mục "${c.name}".');
          }
        }
        return;
      }

      final otherCategories =
          categories.where((cat) => cat.categoryId != c.categoryId).toList();
      if (otherCategories.isEmpty) {
        if (context.mounted) {
          AppSnackbar.show(
            context,
            'Không thể xóa danh mục duy nhất đang chứa giao dịch/ngân sách.',
            isError: true,
          );
        }
        return;
      }

      String selectedCategoryId = otherCategories.first.categoryId;
      if (!context.mounted) return;
      final confirmReassign = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setDlgState) => AlertDialog(
              title: const Text('Danh mục đang được dùng'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Danh mục này đang có giao dịch hoặc ngân sách liên kết. '
                    'Vui lòng chọn danh mục thay thế để chuyển toàn bộ dữ liệu sang trước khi xóa:',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: selectedCategoryId,
                    decoration: const InputDecoration(
                      labelText: 'Chuyển sang danh mục',
                      border: OutlineInputBorder(),
                    ),
                    items: otherCategories.map((cat) {
                      return DropdownMenuItem(
                          value: cat.categoryId, child: Text(cat.name));
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) setDlgState(() => selectedCategoryId = v);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Hủy')),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Xóa & Chuyển',
                      style: TextStyle(color: AppColors.expense)),
                ),
              ],
            ),
          );
        },
      );

      if (confirmReassign == true) {
        await _firestoreService.reassignAndDeleteCategory(
            uid, c.categoryId, selectedCategoryId);
        if (context.mounted) {
          AppSnackbar.show(
              context, 'Đã chuyển dữ liệu và xóa danh mục "${c.name}".');
        }
      }
    } catch (e) {
      debugPrint('❌ Lỗi kiểm tra/xóa danh mục: $e');
      if (context.mounted) {
        AppSnackbar.show(
          context,
          'Không thể xóa danh mục. Vui lòng thử lại sau.',
          isError: true,
        );
      }
    }
  }

  void _showCategorySheet(BuildContext context, String uid,
      {Category? category}) {
    final nameController = TextEditingController(text: category?.name ?? '');
    String type = category?.type ?? _selectedType;
    String selectedIcon = category?.icon ?? 'category';
    Color selectedColor =
        category != null ? Color(category.color) : _colorOptions.first;
    bool isSaving = false;
    String? nameError;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.appCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          Future<void> submit() async {
            final newName = nameController.text.trim();
            if (newName.isEmpty) {
              setSheetState(() => nameError = 'Vui lòng nhập tên danh mục');
              return;
            }

            setSheetState(() => isSaving = true);
            try {
              final categoriesInType = await _firestoreService
                  .streamCategories(uid, type: type)
                  .first;
              final isDuplicate = categoriesInType.any((existing) =>
                  existing.categoryId != category?.categoryId &&
                  existing.name.trim().toLowerCase() == newName.toLowerCase());

              if (isDuplicate) {
                if (ctx.mounted) {
                  setSheetState(() {
                    isSaving = false;
                    nameError = 'Danh mục "$newName" đã tồn tại';
                  });
                }
                return;
              }

              if (category == null) {
                await _firestoreService.createCategory(Category(
                  categoryId: '',
                  userId: uid,
                  name: newName,
                  type: type,
                  icon: selectedIcon,
                  color: selectedColor.toARGB32(),
                ));
              } else {
                await _firestoreService.updateCategory(category.categoryId, {
                  'name': newName,
                  'type': type,
                  'icon': selectedIcon,
                  'color': selectedColor.toARGB32(),
                });
              }

              if (ctx.mounted) {
                Navigator.pop(ctx);
                AppSnackbar.show(
                  context,
                  category == null
                      ? 'Đã tạo danh mục "$newName"!'
                      : 'Đã cập nhật danh mục!',
                );
              }
            } catch (e) {
              debugPrint('❌ Lỗi khi lưu danh mục: $e');
              if (ctx.mounted) {
                setSheetState(() => isSaving = false);
                AppSnackbar.show(
                    ctx, 'Không thể lưu danh mục. Vui lòng thử lại.',
                    isError: true);
              }
            }
          }

          return Padding(
            padding:
                EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: context.appBorder,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  // Live Preview Header
                  Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: selectedColor.withValues(
                              alpha: context.isDarkMode ? 0.3 : 0.16),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(categoryIconData(selectedIcon),
                            color: selectedColor, size: 28),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              category == null
                                  ? 'Thêm danh mục mới'
                                  : 'Chỉnh sửa danh mục',
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                                color: context.appTextPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              type == 'expense'
                                  ? 'Phân loại cho khoản Chi tiêu'
                                  : 'Phân loại cho khoản Thu nhập',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: context.appTextSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Type selection if creating new
                  if (category == null) ...[
                    Text(
                      'Loại giao dịch',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: context.appTextSecondary),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            showCheckmark: false,
                            selected: type == 'expense',
                            selectedColor: AppColors.expense,
                            label: const Center(child: Text('Chi tiêu')),
                            labelStyle: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: type == 'expense'
                                  ? Colors.white
                                  : context.appTextPrimary,
                            ),
                            onSelected: (_) =>
                                setSheetState(() => type = 'expense'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ChoiceChip(
                            showCheckmark: false,
                            selected: type == 'income',
                            selectedColor: AppColors.income,
                            label: const Center(child: Text('Thu nhập')),
                            labelStyle: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: type == 'income'
                                  ? Colors.white
                                  : context.appTextPrimary,
                            ),
                            onSelected: (_) =>
                                setSheetState(() => type = 'income'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  // Name input
                  Text(
                    'Tên danh mục',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.appTextSecondary),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: nameController,
                    autofocus: category == null,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) {
                      if (nameError != null)
                        setSheetState(() => nameError = null);
                    },
                    decoration: InputDecoration(
                      hintText: 'VD: Cà phê, Học phí, Xăng xe...',
                      errorText: nameError,
                      prefixIcon:
                          const Icon(Icons.label_outline_rounded, size: 20),
                    ),
                  ),
                  const SizedBox(height: 18),
                  // Icon picker
                  Text(
                    'Biểu tượng',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.appTextSecondary),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 52,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _iconOptions.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (ctx, i) {
                        final iconItem = _iconOptions[i];
                        final iconKey = iconItem['name'] as String;
                        final isSelected = selectedIcon == iconKey;

                        return InkWell(
                          onTap: () =>
                              setSheetState(() => selectedIcon = iconKey),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? selectedColor.withValues(
                                      alpha: context.isDarkMode ? 0.35 : 0.18)
                                  : context.appInputFill,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? selectedColor
                                    : context.appBorder,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Icon(
                              categoryIconData(iconKey),
                              color: isSelected
                                  ? selectedColor
                                  : context.appTextSecondary,
                              size: 22,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 18),
                  // Color picker
                  Text(
                    'Màu sắc nhận diện',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.appTextSecondary),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _colorOptions.map((c) {
                      final isSelected = selectedColor == c;
                      return GestureDetector(
                        onTap: () => setSheetState(() => selectedColor = c),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected
                                  ? Colors.white
                                  : Colors.transparent,
                              width: 3,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: c.withValues(alpha: 0.5),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    )
                                  ]
                                : null,
                          ),
                          child: isSelected
                              ? const Icon(Icons.check_rounded,
                                  color: Colors.white, size: 20)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: OutlinedButton(
                            onPressed:
                                isSaving ? null : () => Navigator.pop(ctx),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: context.appTextPrimary,
                              side: BorderSide(color: context.appBorder),
                            ),
                            child: const Text('Hủy',
                                style: TextStyle(fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            onPressed: isSaving ? null : submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                            ),
                            child: isSaving
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                    ),
                                  )
                                : Text(
                                    category == null
                                        ? 'Tạo danh mục'
                                        : 'Lưu thay đổi',
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

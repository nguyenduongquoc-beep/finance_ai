import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../l10n/app_localizations.dart';
import '../../models/category_model.dart';
import '../../models/transaction_model.dart';
import '../../services/firestore_service.dart';
import '../../utils/category_icons.dart';
import '../../utils/category_localization_helper.dart';
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

  static const List<String> _iconKeys = [
    'restaurant',
    'shopping_bag',
    'local_gas_station',
    'receipt_long',
    'work',
    'card_giftcard',
    'storefront',
    'school',
    'movie',
    'flight',
    'local_hospital',
    'category',
  ];

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(context.tr('cat_mgmt_title')),
        elevation: 0,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 3,
        onPressed: () => _showCategorySheet(context, uid),
        icon: const Icon(Icons.add_rounded),
        label: Text(context.tr('bud_set_add_cat_btn'),
            style: const TextStyle(fontWeight: FontWeight.w600)),
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
                              label: context.tr('common_expense'),
                              count: expenseCategories.length,
                              isSelected: _selectedType == 'expense',
                              activeColor: AppColors.expense,
                              onTap: () =>
                                  setState(() => _selectedType = 'expense'),
                            ),
                          ),
                          Expanded(
                            child: _buildTabButton(
                              label: context.tr('common_income'),
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
    final label = isExpense
        ? context.tr('cat_mgmt_total_expense')
        : context.tr('cat_mgmt_total_income');
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
                  ? Icons.arrow_downward_rounded
                  : Icons.arrow_upward_rounded,
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
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 130),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: context.appInputFill,
                borderRadius: BorderRadius.circular(12),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  context.tr('bud_set_cat_count',
                      params: {'count': '$categoryCount'}),
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.appTextSecondary,
                  ),
                ),
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected
                          ? context.appTextPrimary
                          : context.appTextSecondary,
                    ),
                  ),
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
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            CategoryLocalizationHelper.localizeNameWithContext(
                                context, category.name),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: context.appTextPrimary,
                            ),
                          ),
                        ),
                        if (category.type == 'expense') ...[
                          const SizedBox(width: 8),
                          InkWell(
                            borderRadius: BorderRadius.circular(6),
                            onTap: () async {
                              final nextVal = !category.isEssential;
                              await _firestoreService.updateCategory(
                                category.categoryId,
                                {'isEssential': nextVal},
                              );
                              if (context.mounted) {
                                AppSnackbar.show(
                                  context,
                                  context.tr('cat_mgmt_moved_group', params: {
                                    'name': CategoryLocalizationHelper
                                        .localizeNameWithContext(
                                            context, category.name),
                                    'group': nextVal
                                        ? context.tr('cat_mgmt_essential')
                                        : context.tr('cat_mgmt_flexible'),
                                  }),
                                );
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: category.isEssential
                                    ? AppColors.primary.withValues(alpha: 0.14)
                                    : AppColors.warning.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                category.isEssential
                                    ? context.tr('cat_mgmt_essential')
                                    : context.tr('cat_mgmt_flexible'),
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: category.isEssential
                                      ? AppColors.primary
                                      : AppColors.warning,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      monthlyAmount > 0
                          ? context.tr('cat_mgmt_this_month_amt', params: {
                              'amount': AppFormatters.compactCurrency(
                                  monthlyAmount,
                                  unit: '₫')
                            })
                          : context.tr('cat_mgmt_no_tx_month'),
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
                tooltip: context.tr('cat_mgmt_options_tooltip'),
                onSelected: (action) {
                  if (action == 'edit') {
                    _showCategorySheet(context, uid, category: category);
                  } else if (action == 'delete') {
                    _handleDeleteCategory(
                        context, uid, category, allCategoriesInType);
                  }
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        const Icon(Icons.edit_outlined, size: 18),
                        const SizedBox(width: 8),
                        Text(ctx.tr('cat_mgmt_edit')),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        const Icon(Icons.delete_outline_rounded,
                            size: 18, color: AppColors.expense),
                        const SizedBox(width: 8),
                        Text(ctx.tr('cat_mgmt_delete_cat'),
                            style: const TextStyle(color: AppColors.expense)),
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
    final label = type == 'expense'
        ? context.tr('cat_mgmt_type_exp_lower')
        : context.tr('cat_mgmt_type_inc_lower');
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
                context.tr('cat_mgmt_empty_title', params: {'type': label}),
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: context.appTextPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                context.tr('cat_mgmt_empty_desc'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13, height: 1.4, color: context.appTextSecondary),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => _showCategorySheet(context, uid),
                icon: const Icon(Icons.add_rounded),
                label: Text(context.tr('bud_set_add_cat_btn')),
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
          builder: (ctx) {
            final displayCatName =
                CategoryLocalizationHelper.localizeNameWithContext(ctx, c.name);
            return AlertDialog(
              title: Text(ctx.tr('cat_mgmt_del_dialog_title')),
              content: Text(
                ctx.tr('cat_mgmt_del_dialog_msg',
                    params: {'name': displayCatName}),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(ctx.tr('common_cancel'))),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(ctx.tr('common_delete'),
                      style: const TextStyle(color: AppColors.expense)),
                ),
              ],
            );
          },
        );
        if (confirm == true) {
          await _firestoreService.deleteCategory(c.categoryId);
          if (context.mounted) {
            final displayCatName =
                CategoryLocalizationHelper.localizeNameWithContext(
                    context, c.name);
            AppSnackbar.show(
                context,
                context.tr('cat_mgmt_del_success',
                    params: {'name': displayCatName}));
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
            context.tr('cat_mgmt_del_only_err'),
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
              title: Text(ctx.tr('cat_mgmt_in_use_title')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ctx.tr('cat_mgmt_in_use_desc'),
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: selectedCategoryId,
                    decoration: InputDecoration(
                      labelText: ctx.tr('cat_mgmt_reassign_label'),
                      border: const OutlineInputBorder(),
                    ),
                    items: otherCategories.map((cat) {
                      return DropdownMenuItem(
                        value: cat.categoryId,
                        child: Text(
                          CategoryLocalizationHelper.localizeNameWithContext(
                              ctx, cat.name),
                        ),
                      );
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
                    child: Text(ctx.tr('common_cancel'))),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(ctx.tr('cat_mgmt_del_transfer_btn'),
                      style: const TextStyle(color: AppColors.expense)),
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
          final displayCatName =
              CategoryLocalizationHelper.localizeNameWithContext(
                  context, c.name);
          AppSnackbar.show(
              context,
              context.tr('cat_mgmt_del_transfer_ok',
                  params: {'name': displayCatName}));
        }
      }
    } catch (e) {
      debugPrint('❌ Lỗi kiểm tra/xóa danh mục: $e');
      if (context.mounted) {
        AppSnackbar.show(
          context,
          context.tr('cat_mgmt_del_error'),
          isError: true,
        );
      }
    }
  }

  void _showCategorySheet(BuildContext context, String uid,
      {Category? category}) {
    final isSystemCategory = category != null &&
        CategoryLocalizationHelper.isSystemCategoryName(category.name);
    final initialDisplayName = category != null
        ? CategoryLocalizationHelper.localizeNameWithContext(
            context, category.name)
        : '';
    final nameController = TextEditingController(text: initialDisplayName);
    String type = category?.type ?? _selectedType;
    String selectedIcon = category?.icon ?? 'category';
    Color selectedColor =
        category != null ? Color(category.color) : _colorOptions.first;
    bool isEssential = category?.isEssential ?? false;
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
              setSheetState(
                  () => nameError = ctx.tr('cat_mgmt_name_empty_err'));
              return;
            }

            setSheetState(() => isSaving = true);
            try {
              final categoriesInType = await _firestoreService
                  .streamCategories(uid, type: type)
                  .first;
              final isDuplicate = categoriesInType.any((existing) {
                if (existing.categoryId == category?.categoryId) return false;
                final target = newName.toLowerCase();
                final rawMatch = existing.name.trim().toLowerCase() == target;
                final localizedMatch =
                    CategoryLocalizationHelper.localizeNameWithContext(
                                ctx, existing.name)
                            .trim()
                            .toLowerCase() ==
                        target;
                return rawMatch || localizedMatch;
              });

              if (isDuplicate) {
                if (ctx.mounted) {
                  setSheetState(() {
                    isSaving = false;
                    nameError = ctx.tr('cat_mgmt_name_dup_err',
                        params: {'name': newName});
                  });
                }
                return;
              }

              // Nếu danh mục hệ thống giữ nguyên tên hiển thị khi sửa màu/icon/nhóm,
              // bảo toàn tên chuẩn gốc để vẫn tự dịch khi chuyển ngôn ngữ.
              final savedName = (isSystemCategory &&
                      newName.toLowerCase() == initialDisplayName.toLowerCase())
                  ? category.name
                  : newName;

              if (category == null) {
                await _firestoreService.createCategory(Category(
                  categoryId: '',
                  userId: uid,
                  name: newName,
                  type: type,
                  icon: selectedIcon,
                  color: selectedColor.toARGB32(),
                  isEssential: type == 'expense' ? isEssential : false,
                ));
              } else {
                await _firestoreService.updateCategory(category.categoryId, {
                  'name': savedName,
                  'type': type,
                  'icon': selectedIcon,
                  'color': selectedColor.toARGB32(),
                  'isEssential': type == 'expense' ? isEssential : false,
                });
              }

              if (ctx.mounted) {
                Navigator.pop(ctx);
                AppSnackbar.show(
                  context,
                  category == null
                      ? ctx.tr('cat_mgmt_created_ok', params: {'name': newName})
                      : ctx.tr('cat_mgmt_updated_ok'),
                );
              }
            } catch (e) {
              debugPrint('❌ Lỗi khi lưu danh mục: $e');
              if (ctx.mounted) {
                setSheetState(() => isSaving = false);
                AppSnackbar.show(ctx, ctx.tr('cat_mgmt_save_error'),
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
                                  ? ctx.tr('cat_mgmt_sheet_add')
                                  : ctx.tr('cat_mgmt_sheet_edit'),
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                                color: context.appTextPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              type == 'expense'
                                  ? ctx.tr('cat_mgmt_sub_exp')
                                  : ctx.tr('cat_mgmt_sub_inc'),
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
                      ctx.tr('cat_mgmt_tx_type'),
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
                            label:
                                Center(child: Text(ctx.tr('common_expense'))),
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
                            label: Center(child: Text(ctx.tr('common_income'))),
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
                    ctx.tr('cat_mgmt_name_label'),
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
                      hintText: ctx.tr('cat_mgmt_name_hint'),
                      errorText: nameError,
                      prefixIcon:
                          const Icon(Icons.label_outline_rounded, size: 20),
                    ),
                  ),
                  if (type == 'expense') ...[
                    const SizedBox(height: 16),
                    Text(
                      ctx.tr('cat_mgmt_cost_group'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.appTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            showCheckmark: false,
                            selected: isEssential,
                            selectedColor: AppColors.primary,
                            label: Center(
                                child: Text(ctx.tr('cat_mgmt_essential_full'))),
                            labelStyle: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: isEssential
                                  ? Colors.white
                                  : context.appTextPrimary,
                            ),
                            onSelected: (_) =>
                                setSheetState(() => isEssential = true),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ChoiceChip(
                            showCheckmark: false,
                            selected: !isEssential,
                            selectedColor: AppColors.warning,
                            label: Center(
                                child: Text(ctx.tr('cat_mgmt_flexible_full'))),
                            labelStyle: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: !isEssential
                                  ? Colors.white
                                  : context.appTextPrimary,
                            ),
                            onSelected: (_) =>
                                setSheetState(() => isEssential = false),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 18),
                  // Icon picker
                  Text(
                    ctx.tr('cat_mgmt_icon_label'),
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
                      itemCount: _iconKeys.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (ctx, i) {
                        final iconKey = _iconKeys[i];
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
                    ctx.tr('cat_mgmt_color_label'),
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
                            child: Text(ctx.tr('common_cancel'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
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
                                        ? ctx.tr('cat_mgmt_create_btn')
                                        : ctx.tr('cat_mgmt_save_changes'),
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

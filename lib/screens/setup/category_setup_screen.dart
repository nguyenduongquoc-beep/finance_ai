import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../l10n/app_localizations.dart';
import '../../models/category_model.dart';
import '../../models/wallet_model.dart';
import '../../services/firestore_service.dart';
import '../../utils/category_icons.dart';
import '../../utils/category_localization_helper.dart';
import '../../utils/constants.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/main_navigation.dart';

/// Chọn danh mục thu chi khởi tạo (Bước 2/2) — Hiện đại, thân thiện & logic
/// Kết nối trực tiếp với collection `system_categories` do Admin quản lý.
/// Chỉ fallback về constants.dart khi không thể truy cập nguồn dữ liệu từ Firestore.
/// Nhận `pendingWallets` từ Bước 1 và ghi đồng thời Ví + Danh mục nguyên tử khi bấm Hoàn tất.
class CategorySetupScreen extends StatefulWidget {
  final List<Wallet> pendingWallets;
  final FirestoreService? firestoreService;
  final String? userIdOverride;
  final VoidCallback? onSetupCompleted;

  const CategorySetupScreen({
    super.key,
    this.pendingWallets = const [],
    this.firestoreService,
    this.userIdOverride,
    this.onSetupCompleted,
  });

  @override
  State<CategorySetupScreen> createState() => _CategorySetupScreenState();
}

class _SetupCategoryItem {
  final String name;
  final String type; // 'expense' | 'income'
  final String icon;
  final int color;
  bool isEssential;
  bool selected;

  _SetupCategoryItem({
    required this.name,
    required this.type,
    required this.icon,
    required this.color,
    this.isEssential = false,
    this.selected = true,
  });
}

class _CategorySetupScreenState extends State<CategorySetupScreen> {
  late final FirestoreService _firestoreService;
  bool _isLoading = false;
  bool _isLoadingTemplates = true;
  bool _showExpenses = true;

  final List<_SetupCategoryItem> _expenseItems = [];
  final List<_SetupCategoryItem> _incomeItems = [];

  @override
  void initState() {
    super.initState();
    _firestoreService = widget.firestoreService ?? FirestoreService();
    _loadSystemCategories();
  }

  Future<void> _loadSystemCategories() async {
    final result = await _firestoreService.fetchSystemCategoriesForSetup();
    if (!mounted) return;

    setState(() {
      _expenseItems.clear();
      _incomeItems.clear();

      if (result.isFirestoreAccessible) {
        // Lấy danh mục đang hoạt động (isActive == true) từ Firestore.
        // Nếu collection rỗng hoặc Admin đã ẩn hết danh mục, giữ nguyên danh sách trống
        // (tuyệt đối không tự động khôi phục từ constants.dart).
        for (final t in result.activeTemplates) {
          final item = _SetupCategoryItem(
            name: t.name,
            type: t.type,
            icon: t.icon,
            color: t.color,
            isEssential: t.type == 'expense' ? t.isEssential : false,
            selected: true,
          );
          if (t.type == 'income') {
            _incomeItems.add(item);
          } else {
            _expenseItems.add(item);
          }
        }
      } else {
        // Chỉ fallback về constants.dart khi KHÔNG THỂ truy cập nguồn dữ liệu từ Firestore
        for (final c in DefaultExpenseCategories.categories) {
          _expenseItems.add(
            _SetupCategoryItem(
              name: c['name'] as String,
              type: 'expense',
              icon: c['icon'] as String,
              color: c['color'] as int,
              isEssential: c['isEssential'] == true,
              selected: true,
            ),
          );
        }
        for (final c in DefaultIncomeCategories.categories) {
          _incomeItems.add(
            _SetupCategoryItem(
              name: c['name'] as String,
              type: 'income',
              icon: c['icon'] as String,
              color: c['color'] as int,
              selected: true,
            ),
          );
        }
      }

      _isLoadingTemplates = false;
    });
  }

  int get _selectedExpenseCount =>
      _expenseItems.where((e) => e.selected).length;

  int get _selectedIncomeCount =>
      _incomeItems.where((e) => e.selected).length;

  int get _totalSelectedCount =>
      _selectedExpenseCount + _selectedIncomeCount;

  bool get _isCurrentTabAllSelected {
    final list = _showExpenses ? _expenseItems : _incomeItems;
    if (list.isEmpty) return false;
    return list.every((e) => e.selected);
  }

  void _toggleSelectAllCurrentTab() {
    final list = _showExpenses ? _expenseItems : _incomeItems;
    final targetState = !_isCurrentTabAllSelected;
    setState(() {
      for (final item in list) {
        item.selected = targetState;
      }
    });
  }

  void _showAddCustomCategorySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.appCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddCustomCategorySheet(
        initialType: _showExpenses ? 'expense' : 'income',
        onSubmit: ({required String name, required String selectedType}) {
          final targetList =
              selectedType == 'expense' ? _expenseItems : _incomeItems;
          final existingIndex = targetList.indexWhere(
            (item) => item.name.trim().toLowerCase() == name.toLowerCase(),
          );
          if (existingIndex != -1) {
            setState(() {
              targetList[existingIndex].selected = true;
              _showExpenses = selectedType == 'expense';
            });
            return;
          }

          final newItem = _SetupCategoryItem(
            name: name,
            type: selectedType,
            icon: selectedType == 'expense' ? 'shopping_bag' : 'work',
            color: selectedType == 'expense' ? 0xFFF59E0B : 0xFF10B981,
            selected: true,
          );

          setState(() {
            if (selectedType == 'expense') {
              _expenseItems.add(newItem);
              _showExpenses = true;
            } else {
              _incomeItems.add(newItem);
              _showExpenses = false;
            }
          });
        },
      ),
    );
  }

  Future<void> _handleFinish() async {
    if (_isLoading) return;
    if (_selectedExpenseCount == 0 || _selectedIncomeCount == 0) {
      AppSnackbar.show(
        context,
        context.tr('setup_cat_min_one'),
        isError: true,
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final uid =
          widget.userIdOverride ?? FirebaseAuth.instance.currentUser!.uid;

      final categoriesToSave = <Category>[
        for (final c in _incomeItems)
          if (c.selected)
            Category(
              categoryId: '',
              userId: uid,
              name: c.name,
              type: 'income',
              icon: c.icon,
              color: c.color,
            ),
        for (final c in _expenseItems)
          if (c.selected)
            Category(
              categoryId: '',
              userId: uid,
              name: c.name,
              type: 'expense',
              icon: c.icon,
              color: c.color,
              isEssential: c.isEssential,
            ),
      ];

      await _firestoreService.completeInitialSetup(
        userId: uid,
        wallets: widget.pendingWallets,
        categories: categoriesToSave,
      );

      if (!mounted) return;
      if (widget.onSetupCompleted != null) {
        widget.onSetupCompleted!();
      } else {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainNavigation()),
          (route) => false,
        );
      }
    } catch (e) {
      debugPrint('❌ Lỗi khi hoàn tất thiết lập tài khoản: $e');
      if (mounted) {
        AppSnackbar.show(context, context.tr('common_error'), isError: true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  IconData _getIconData(String name) => categoryIconData(name);

  @override
  Widget build(BuildContext context) {
    final currentList = _showExpenses ? _expenseItems : _incomeItems;

    return PopScope(
      canPop: !_isLoading,
      child: Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        backgroundColor: context.appBackground,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 18,
            color: context.appTextPrimary,
          ),
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
        ),
        title: _buildStepperHeader(currentStep: 2),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Hero Banner màu gốc dự án AppColors.primary
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppColors.primary,
                          Color(0xFF17576E),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withAlpha(45),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(28),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withAlpha(60),
                            ),
                          ),
                          child: const Icon(
                            Icons.grid_view_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      context.tr('setup_cat_title'),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 115),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withAlpha(28),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          context.tr(
                                            'setup_cat_selected_badge',
                                            params: {
                                              'count': '$_totalSelectedCount'
                                            },
                                          ),
                                          maxLines: 1,
                                          style: GoogleFonts.inter(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                context.tr('setup_cat_sub'),
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: Colors.white.withAlpha(220),
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Segmented Tab Bar (Chi tiêu hướng xuống / Thu nhập hướng lên đồng nhất)
                  Container(
                    width: double.infinity,
                    height: 48,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: context.appInputFill,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: context.appBorder, width: 1),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _showExpenses = true),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _showExpenses
                                    ? AppColors.primary
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.arrow_downward_rounded,
                                    size: 15,
                                    color: _showExpenses
                                        ? const Color(0xFFF87171)
                                        : AppColors.expense,
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        context.tr(
                                          'setup_cat_expense_tab',
                                          params: {
                                            'count': '$_selectedExpenseCount'
                                          },
                                        ),
                                        maxLines: 1,
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: _showExpenses
                                              ? Colors.white
                                              : context.appTextSecondary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _showExpenses = false),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: !_showExpenses
                                    ? AppColors.primary
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.arrow_upward_rounded,
                                    size: 15,
                                    color: !_showExpenses
                                        ? const Color(0xFF34D399)
                                        : AppColors.income,
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        context.tr(
                                          'setup_cat_income_tab',
                                          params: {
                                            'count': '$_selectedIncomeCount'
                                          },
                                        ),
                                        maxLines: 1,
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: !_showExpenses
                                              ? Colors.white
                                              : context.appTextSecondary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Thanh công cụ nhanh (Chọn tất cả / Thêm danh mục riêng)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            foregroundColor: context.appTextSecondary,
                          ),
                          onPressed: _toggleSelectAllCurrentTab,
                          icon: Icon(
                            _isCurrentTabAllSelected
                                ? Icons.check_box_rounded
                                : Icons.check_box_outline_blank_rounded,
                            size: 17,
                            color: _isCurrentTabAllSelected
                                ? const Color(0xFF10B981)
                                : context.appTextSecondary,
                          ),
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _isCurrentTabAllSelected
                                  ? context.tr('setup_cat_deselect_all')
                                  : context.tr('setup_cat_select_all'),
                              maxLines: 1,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            foregroundColor: AppColors.primaryLight,
                          ),
                          onPressed: _showAddCustomCategorySheet,
                          icon: const Icon(Icons.add_circle_outline_rounded,
                              size: 16),
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              context.tr('setup_cat_add_custom'),
                              maxLines: 1,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),

            // Grid danh mục
            Expanded(
              child: _isLoadingTemplates
                  ? const Center(child: CircularProgressIndicator())
                  : currentList.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.category_outlined,
                                  size: 40,
                                  color: context.appTextSecondary,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  context.tr('setup_cat_empty_title'),
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: context.appTextPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  context.tr('setup_cat_empty_sub'),
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: context.appTextSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 6),
                          itemCount: currentList.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 2.35,
                          ),
                          itemBuilder: (context, i) {
                            final item = currentList[i];
                            final isSelected = item.selected;
                            final color = Color(item.color);

                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  item.selected = !item.selected;
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: context.appCard,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isSelected
                                        ? AppColors.primaryLight
                                        : context.appBorder,
                                    width: isSelected ? 1.6 : 1.0,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: color.withAlpha(28),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        _getIconData(item.icon),
                                        color: color,
                                        size: 18,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            CategoryLocalizationHelper
                                                .localizeNameWithContext(
                                                    context, item.name),
                                            style: GoogleFonts.inter(
                                              fontWeight: isSelected
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                              fontSize: 13,
                                              color: isSelected
                                                  ? context.appTextPrimary
                                                  : context.appTextSecondary,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (item.type == 'expense')
                                            Text(
                                              item.isEssential
                                                  ? context.tr(
                                                      'setup_cat_essential')
                                                  : context.tr(
                                                      'setup_cat_flexible'),
                                              style: GoogleFonts.inter(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: item.isEssential
                                                    ? AppColors.primary
                                                    : context.appTextSecondary,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      isSelected
                                          ? Icons.check_circle_rounded
                                          : Icons.circle_outlined,
                                      color: isSelected
                                          ? AppColors.primary
                                          : context.appBorder,
                                      size: 19,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),

            // Thanh nút hoàn tất cố định dưới đáy
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
                color: context.appCard,
                border: Border(top: BorderSide(color: context.appBorder)),
              ),
              child: AppButton(
                text: context.tr('setup_cat_finish'),
                icon: Icons.check_circle_outline_rounded,
                isLoading: _isLoading,
                onPressed: _handleFinish,
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildStepperHeader({required int currentStep}) {
    final steps = [
      {'step': 1, 'label': context.tr('setup_step_wallets')},
      {'step': 2, 'label': context.tr('setup_step_categories')},
    ];

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(steps.length * 2 - 1, (index) {
          if (index.isOdd) {
            final prevStep = (index ~/ 2) + 1;
            final isPassed = currentStep > prevStep;
            return Container(
              width: 22,
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              color: isPassed ? const Color(0xFF10B981) : context.appBorder,
            );
          }

          final item = steps[index ~/ 2];
          final stepNum = item['step'] as int;
          final label = item['label'] as String;
          final isActive = stepNum == currentStep;
          final isDone = stepNum < currentStep;

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDone
                      ? const Color(0xFF10B981)
                      : isActive
                          ? AppColors.primary
                          : context.appInputFill,
                  border: Border.all(
                    color: isDone
                        ? const Color(0xFF10B981)
                        : isActive
                            ? AppColors.primaryLight
                            : context.appBorder,
                    width: 1.2,
                  ),
                ),
                child: isDone
                    ? const Icon(Icons.check_rounded,
                        size: 14, color: Colors.white)
                    : Text(
                        '$stepNum',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isActive
                              ? Colors.white
                              : context.appTextSecondary,
                        ),
                      ),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight:
                      isActive || isDone ? FontWeight.w700 : FontWeight.w500,
                  color: isActive
                      ? context.appTextPrimary
                      : isDone
                          ? const Color(0xFF10B981)
                          : context.appTextSecondary,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _AddCustomCategorySheet extends StatefulWidget {
  final String initialType;
  final void Function({required String name, required String selectedType})
      onSubmit;

  const _AddCustomCategorySheet({
    required this.initialType,
    required this.onSubmit,
  });

  @override
  State<_AddCustomCategorySheet> createState() =>
      _AddCustomCategorySheetState();
}

class _AddCustomCategorySheetState extends State<_AddCustomCategorySheet> {
  final _nameCtrl = TextEditingController();
  late String _selectedType;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.initialType;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  context.tr('setup_cat_add_custom'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: context.appTextPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: _nameCtrl,
            labelText: context.tr('setup_cat_name_label'),
            hintText: context.tr('setup_cat_name_hint'),
            prefixIcon: Icons.category_outlined,
          ),
          const SizedBox(height: 14),
          Text(
            context.tr('setup_cat_type_label'),
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.appTextSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedType = 'expense'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _selectedType == 'expense'
                          ? AppColors.primary.withAlpha(24)
                          : context.appBackground,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _selectedType == 'expense'
                            ? AppColors.primary
                            : context.appBorder,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.arrow_downward_rounded,
                          size: 16,
                          color: AppColors.expense,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              context.tr('setup_cat_expense'),
                              maxLines: 1,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _selectedType == 'expense'
                                    ? AppColors.primary
                                    : context.appTextSecondary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedType = 'income'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _selectedType == 'income'
                          ? AppColors.primary.withAlpha(24)
                          : context.appBackground,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _selectedType == 'income'
                            ? AppColors.primary
                            : context.appBorder,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.arrow_upward_rounded,
                          size: 16,
                          color: AppColors.income,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              context.tr('setup_cat_income'),
                              maxLines: 1,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _selectedType == 'income'
                                    ? AppColors.primary
                                    : context.appTextSecondary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          AppButton(
            text: context.tr('setup_cat_add_btn'),
            onPressed: () {
              final name = _nameCtrl.text.trim();
              if (name.isEmpty) return;
              widget.onSubmit(name: name, selectedType: _selectedType);
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}

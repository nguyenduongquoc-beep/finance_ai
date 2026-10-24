import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/category_model.dart';
import '../../services/firestore_service.dart';
import '../../utils/constants.dart';
import '../../widgets/app_button.dart';
import '../../widgets/main_navigation.dart';

/// Chọn danh mục mặc định (Bước 3/3)
class CategorySetupScreen extends StatefulWidget {
  const CategorySetupScreen({super.key});

  @override
  State<CategorySetupScreen> createState() => _CategorySetupScreenState();
}

class _CategorySetupScreenState extends State<CategorySetupScreen> {
  final _firestoreService = FirestoreService();
  bool _isLoading = false;
  bool _showExpenses = true;

  late final List<bool> _incomeSelected =
      List.filled(DefaultIncomeCategories.categories.length, true);
  late final List<bool> _expenseSelected =
      List.filled(DefaultExpenseCategories.categories.length, true);

  Future<void> _handleFinish() async {
    setState(() => _isLoading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;

      for (int i = 0; i < DefaultIncomeCategories.categories.length; i++) {
        if (!_incomeSelected[i]) continue;
        final c = DefaultIncomeCategories.categories[i];
        await _firestoreService.createCategory(Category(
          categoryId: '',
          userId: uid,
          name: c['name'],
          type: 'income',
          icon: c['icon'],
          color: c['color'],
        ));
      }

      for (int i = 0; i < DefaultExpenseCategories.categories.length; i++) {
        if (!_expenseSelected[i]) continue;
        final c = DefaultExpenseCategories.categories[i];
        await _firestoreService.createCategory(Category(
          categoryId: '',
          userId: uid,
          name: c['name'],
          type: 'expense',
          icon: c['icon'],
          color: c['color'],
        ));
      }

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainNavigation()),
        (route) => false,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  IconData _getIconData(String name) {
    switch (name) {
      case 'work':
        return Icons.work_outline_rounded;
      case 'card_giftcard':
        return Icons.card_giftcard_rounded;
      case 'storefront':
        return Icons.storefront_rounded;
      case 'restaurant':
        return Icons.restaurant_rounded;
      case 'shopping_bag':
        return Icons.shopping_bag_outlined;
      case 'local_gas_station':
        return Icons.local_gas_station_rounded;
      case 'school':
        return Icons.school_outlined;
      case 'movie':
        return Icons.movie_outlined;
      case 'flight':
        return Icons.flight_takeoff_rounded;
      case 'local_hospital':
        return Icons.local_hospital_outlined;
      default:
        return Icons.category_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = _showExpenses
        ? DefaultExpenseCategories.categories
        : DefaultIncomeCategories.categories;

    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        backgroundColor: context.appBackground,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight.withAlpha(25),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'BƯỚC 3/3',
                      style: GoogleFonts.inter(
                        color: AppColors.primaryLight,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Chọn danh mục',
                    style: GoogleFonts.inter(
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                      color: context.appTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Chọn các danh mục mặc định để tự động phân loại giao dịch của bạn.',
                    style: GoogleFonts.inter(
                      color: context.appTextSecondary,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Segmented Tab bar
                  Container(
                    width: double.infinity,
                    height: 48,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: context.appInputFill,
                      borderRadius: BorderRadius.circular(12),
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
                                    ? context.appCard
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'Chi tiêu',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: _showExpenses
                                      ? AppColors.expense
                                      : context.appTextSecondary,
                                ),
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
                                    ? context.appCard
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'Thu nhập',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: !_showExpenses
                                      ? AppColors.income
                                      : context.appTextSecondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),

            // Grid content
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: categories.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 2.2,
                ),
                itemBuilder: (context, i) {
                  final c = categories[i];
                  final isSelected =
                      _showExpenses ? _expenseSelected[i] : _incomeSelected[i];
                  final color = Color(c['color']);

                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        if (_showExpenses) {
                          _expenseSelected[i] = !_expenseSelected[i];
                        } else {
                          _incomeSelected[i] = !_incomeSelected[i];
                        }
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: context.appCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primaryLight
                              : context.appBorder,
                          width: isSelected ? 1.5 : 1.0,
                        ),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: color.withAlpha(30),
                            child: Icon(_getIconData(c['icon']),
                                color: color, size: 18),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              c['name'],
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: context.appTextPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(
                            isSelected
                                ? Icons.check_circle_rounded
                                : Icons.circle_outlined,
                            color: isSelected
                                ? AppColors.primaryLight
                                : context.appTextSecondary,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // Finish CTA button
            Padding(
              padding: const EdgeInsets.all(24),
              child: AppButton(
                text: 'Hoàn tất thiết lập',
                isLoading: _isLoading,
                onPressed: _handleFinish,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

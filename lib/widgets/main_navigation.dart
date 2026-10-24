import 'package:flutter/material.dart';
import '../utils/constants.dart';
import '../screens/home/home_dashboard_screen.dart';
import '../screens/home/transaction_list_screen.dart';
import '../screens/home/add_transaction_screen.dart';
import '../screens/ai/ai_chat_screen.dart';
import '../screens/profile_screen.dart';

/// Main Navigation 5 tab chuẩn Fintech
class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    HomeDashboardScreen(),
    TransactionListScreen(),
    SizedBox.shrink(),
    AiChatScreen(),
    ProfileScreen(),
  ];

  void _onTabTapped(int index) {
    if (index == 2) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AddTransactionScreen()),
      );
      return;
    }
    setState(() => _currentIndex = index);
  }

  Widget _buildNavItem(int index, IconData inactiveIcon, IconData activeIcon, String label) {
    final isSelected = _currentIndex == index;
    final color = isSelected
        ? AppColors.primary
        : context.appTextSecondary;

    return Expanded(
      child: InkWell(
        onTap: () => _onTabTapped(index),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSelected ? activeIcon : inactiveIcon,
              color: color,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddButton() {
    return Expanded(
      child: Center(
        child: InkWell(
          onTap: () => _onTabTapped(2),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.add_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    final hideBottomNav = isKeyboardOpen && _currentIndex == 3;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: IndexedStack(
        index: _currentIndex == 2 ? 0 : _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: hideBottomNav
          ? null
          : Container(
              decoration: BoxDecoration(
                color: context.appCard,
                border: Border(top: BorderSide(color: context.appBorder, width: 1)),
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  height: 64,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildNavItem(0, Icons.home_outlined, Icons.home_rounded, 'Trang chủ'),
                      _buildNavItem(1, Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'Giao dịch'),
                      _buildAddButton(),
                      _buildNavItem(3, Icons.auto_awesome_outlined, Icons.auto_awesome_rounded, 'Trợ lý AI'),
                      _buildNavItem(4, Icons.person_outline_rounded, Icons.person_rounded, 'Cá nhân'),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

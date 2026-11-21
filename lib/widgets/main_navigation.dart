import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/constants.dart';
import '../l10n/app_localizations.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/local_notification_service.dart';
import '../screens/auth/login_screen.dart';
import '../screens/home/home_dashboard_screen.dart';
import '../screens/home/transaction_list_screen.dart';
import '../screens/home/add_transaction_screen.dart';
import '../screens/ai/ai_insight_screen.dart';
import '../screens/profile_screen.dart';

/// Main Navigation 5 tab chuẩn Fintech
class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  final FirestoreService _firestoreService = FirestoreService();
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    LocalNotificationService.isAppReadyForDeepLink = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      LocalNotificationService().consumePendingPayloadIfAny();
    });
  }

  @override
  void dispose() {
    LocalNotificationService().resetNavigationReadiness();
    super.dispose();
  }

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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
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
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    final hideBottomNav = isKeyboardOpen && _currentIndex == 3;

    return StreamBuilder<AppUser?>(
      stream: uid.isNotEmpty ? _firestoreService.streamUserProfile(uid) : null,
      builder: (context, snapshot) {
        final appUser = snapshot.data;
        if (appUser != null && appUser.isLocked) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.lock_person_rounded,
                      size: 64,
                      color: AppColors.expense,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      context.tr('nav_locked_title'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.tr(
                        'nav_locked_body',
                        params: {'email': appUser.email},
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: context.appTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () async {
                        await _authService.signOut();
                        if (!context.mounted) return;
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                              builder: (_) => const LoginScreen()),
                          (route) => false,
                        );
                      },
                      icon: const Icon(Icons.logout_rounded),
                      label: Text(context.tr('nav_locked_logout')),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Scaffold(
          resizeToAvoidBottomInset: false,
          body: IndexedStack(
            index: _currentIndex == 2 ? 0 : _currentIndex,
            children: [
              const HomeDashboardScreen(),
              const TransactionListScreen(),
              const SizedBox.shrink(),
              AiInsightScreen(isActive: _currentIndex == 3),
              const ProfileScreen(),
            ],
          ),
          bottomNavigationBar: hideBottomNav
              ? null
              : Container(
                  decoration: BoxDecoration(
                    color: context.appCard,
                    border: Border(
                        top: BorderSide(color: context.appBorder, width: 1)),
                  ),
                  child: SafeArea(
                    top: false,
                    child: SizedBox(
                      height: 64,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildNavItem(0, Icons.home_outlined,
                              Icons.home_rounded, context.tr('nav_home')),
                          _buildNavItem(
                              1,
                              Icons.receipt_long_outlined,
                              Icons.receipt_long_rounded,
                              context.tr('nav_transactions')),
                          _buildAddButton(),
                          _buildNavItem(3, Icons.auto_awesome_outlined,
                              Icons.auto_awesome_rounded, context.tr('nav_ai')),
                          _buildNavItem(
                              4,
                              Icons.person_outline_rounded,
                              Icons.person_rounded,
                              context.tr('nav_profile')),
                        ],
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}

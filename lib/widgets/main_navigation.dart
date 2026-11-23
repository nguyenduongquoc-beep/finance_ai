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
import 'locked_account_view.dart';

/// Main Navigation 5 tab chuẩn Fintech
class MainNavigation extends StatefulWidget {
  final FirestoreService? firestoreService;
  final AuthService? authService;
  final String? userIdOverride;
  final Future<void> Function()? customSignOutHandler;

  const MainNavigation({
    super.key,
    this.firestoreService,
    this.authService,
    this.userIdOverride,
    this.customSignOutHandler,
  });

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  late final FirestoreService _firestoreService;
  late final AuthService _authService;
  late final String _uid;
  late final Stream<AppUser?>? _userProfileStream;

  @override
  void initState() {
    super.initState();
    _firestoreService = widget.firestoreService ?? FirestoreService();
    _authService = widget.authService ?? AuthService();
    _uid = widget.userIdOverride ?? FirebaseAuth.instance.currentUser?.uid ?? '';
    _userProfileStream =
        _uid.isNotEmpty ? _firestoreService.streamUserProfile(_uid) : null;

    LocalNotificationService.isAppReadyForDeepLink = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      LocalNotificationService().consumePendingPayloadIfAny();
      if (_uid.isNotEmpty && widget.userIdOverride == null) {
        _firestoreService.touchUserPresenceAndProvider(
          uid: _uid,
          authProvider: _authService.authProviderCode,
        );
      }
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
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    final hideBottomNav = isKeyboardOpen && _currentIndex == 3;

    return StreamBuilder<AppUser?>(
      stream: _userProfileStream,
      builder: (context, snapshot) {
        if (_userProfileStream != null &&
            snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final appUser = snapshot.data;
        if (appUser != null && appUser.isLocked) {
          return LockedAccountView(
            user: appUser,
            onSignOut: () async {
              if (widget.customSignOutHandler != null) {
                await widget.customSignOutHandler!();
              } else {
                await _authService.signOut();
              }
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
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

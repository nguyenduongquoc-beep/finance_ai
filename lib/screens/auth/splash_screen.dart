import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../services/local_notification_service.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/constants.dart';
import '../../widgets/main_navigation.dart';
import '../setup/wallet_setup_screen.dart';
import 'onboarding_screen.dart';

/// Splash Screen - Màn hình khởi động với thương hiệu Fintech cao cấp
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _fadeController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    LocalNotificationService.isAppReadyForDeepLink = false;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );

    _checkAuthState();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _checkAuthState() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const OnboardingScreen()),
      );
    } else {
      final firestore = FirestoreService();
      final profile = await firestore.getUserProfile(user.uid);
      if (profile != null && profile.isLocked) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainNavigation()),
        );
        return;
      }
      if (profile == null) {
        final fallbackName = (user.displayName?.trim().isNotEmpty == true)
            ? user.displayName!.trim()
            : AppLocalizations.tr('common_user');
        await firestore.createUserProfile(
          AppUser(
            uid: user.uid,
            name: fallbackName,
            email: user.email ?? '',
            createdAt: DateTime.now(),
          ),
        );
      }
      if (!mounted) return;
      final wallets = await firestore.streamWallets(user.uid).first;
      if (!mounted) return;
      if (wallets.isEmpty) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const WalletSetupScreen()),
        );
      } else {
        try {
          await firestore.processDueRecurringTransactions(user.uid);
          await firestore.syncRecurringNotifications(user.uid);
        } catch (_) {
          // Implemented silent fallback for offline/network errors
        }
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainNavigation()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.slate900,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          color: AppColors.slate900,
        ),
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Container(
                      width: 110,
                      height: 110,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.slate800,
                          border: Border.all(
                            color: AppColors.income.withAlpha(120),
                            width: 1.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.account_balance_wallet_rounded,
                          size: 52,
                          color: AppColors.income,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 28),
                Text(
                  AppStrings.appName,
                  style: GoogleFonts.inter(
                    color: AppColors.slate50,
                    fontSize: 32,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  context.tr('app_tagline'),
                  style: GoogleFonts.inter(
                    color: AppColors.slate400,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 48),
                const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    color: AppColors.income,
                    strokeWidth: 2.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

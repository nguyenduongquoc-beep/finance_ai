import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../l10n/app_localizations.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../utils/constants.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import 'wallet_setup_screen.dart';

/// Màn hình dự phòng khởi tạo hồ sơ cơ bản từ tài khoản xác thực
/// (Luồng chính đã tự động tạo hồ sơ ngay sau bước Đăng ký / Đăng nhập
/// và chuyển thẳng sang Thiết lập Ví tiền).
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _firestoreService = FirestoreService();
  bool _isLoading = false;

  Future<void> _handleContinue() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);
    try {
      final fallbackName = (user.displayName != null &&
              user.displayName!.trim().isNotEmpty)
          ? user.displayName!.trim()
          : (user.email?.split('@').first ?? AppLocalizations.tr('common_user'));
      final appUser = AppUser(
        uid: user.uid,
        name: fallbackName,
        email: user.email ?? '',
        monthlyIncome: 0,
        avatar: user.photoURL,
        createdAt: DateTime.now(),
      );
      await _firestoreService.createUserProfile(appUser);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const WalletSetupScreen()),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = (user?.displayName != null &&
            user!.displayName!.trim().isNotEmpty)
        ? user.displayName!.trim()
        : (user?.email?.split('@').first ?? context.tr('common_user'));
    final email = user?.email ?? '';

    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        backgroundColor: context.appBackground,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          context.tr('setup_profile_title'),
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: context.appTextPrimary,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AppCard(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 34,
                            backgroundColor: AppColors.primary.withAlpha(24),
                            child: Text(
                              displayName.isNotEmpty
                                  ? displayName[0].toUpperCase()
                                  : 'U',
                              style: GoogleFonts.inter(
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            displayName,
                            style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: context.appTextPrimary,
                            ),
                          ),
                          if (email.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              email,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: context.appTextSecondary,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Text(
                            context.tr('setup_profile_desc'),
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: context.appTextSecondary,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              AppButton(
                text: context.tr('setup_profile_continue'),
                icon: Icons.arrow_forward_rounded,
                isLoading: _isLoading,
                onPressed: _handleContinue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/constants.dart';
import '../widgets/app_card.dart';
import '../l10n/app_localizations.dart';
import 'support/support_center_screen.dart';

/// Thông tin về ứng dụng — màn tĩnh
class AboutAppScreen extends StatelessWidget {
  const AboutAppScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          context.tr('about_title'),
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            color: context.appTextPrimary,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          children: [
            const SizedBox(height: 12),

            // App Brand Logo & Title
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.account_balance_wallet_rounded,
                  color: Colors.white, size: 44),
            ),
            const SizedBox(height: 16),

            Text(
              AppStrings.appName,
              style: GoogleFonts.inter(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: context.appTextPrimary,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                context.tr('about_version'),
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Description
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('about_intro'),
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: context.appTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    context.tr('about_intro_desc'),
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: context.appTextSecondary,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Features
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('about_features'),
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: context.appTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _featureItem(context, Icons.account_balance_wallet_outlined,
                      context.tr('about_feat_wallet')),
                  _featureItem(context, Icons.bar_chart_rounded,
                      context.tr('about_feat_budget')),
                  _featureItem(context, Icons.auto_awesome_rounded,
                      context.tr('about_feat_ai')),
                  _featureItem(context, Icons.document_scanner_outlined,
                      context.tr('about_feat_ocr')),
                  _featureItem(context, Icons.savings_outlined,
                      context.tr('about_feat_goal')),
                  _featureItem(context, Icons.show_chart_rounded,
                      context.tr('about_feat_trend')),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Tech credits
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('about_tech'),
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: context.appTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _techItem(context, 'Flutter',
                      context.tr('about_tech_flutter')),
                  _techItem(context, 'Firebase',
                      'Backend: Authentication, Firestore, Cloud Messaging'),
                  _techItem(context, 'Gemini AI',
                      context.tr('about_tech_gemini')),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Contact & Support Center
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('about_contact'),
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: context.appTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.email_outlined,
                            size: 18, color: AppColors.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'support@financeai.app',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      key: const ValueKey('about_open_support_btn'),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SupportCenterScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.support_agent_rounded, size: 18),
                      label: Text(context.tr('about_open_support_cta')),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Copyright
            Text(
              '© 2026 Finance AI. All rights reserved.',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: context.appTextSecondary,
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _featureItem(BuildContext context, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: context.appTextSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _techItem(BuildContext context, String name, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 7, right: 10),
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: GoogleFonts.inter(
                    fontSize: 14, color: context.appTextSecondary, height: 1.4),
                children: [
                  TextSpan(
                      text: '$name — ',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: context.appTextPrimary)),
                  TextSpan(text: desc),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/constants.dart';
import 'login_screen.dart';

/// Onboarding - 3 trang giới thiệu tiện ích chuẩn Fintech
class OnboardingScreen extends StatefulWidget {
  static const String hasSeenOnboardingKey = 'has_seen_onboarding';

  final WidgetBuilder? loginRouteBuilder;

  const OnboardingScreen({
    super.key,
    this.loginRouteBuilder,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingPage {
  final String imagePath;
  final String title;
  final String description;
  _OnboardingPage(this.imagePath, this.title, this.description);
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _page = 0;

  final List<_OnboardingPage> _pages = [
    _OnboardingPage(
      'assets/images/onboarding_1.png',
      'onb_1_title',
      'onb_1_desc',
    ),
    _OnboardingPage(
      'assets/images/onboarding_2.png',
      'onb_2_title',
      'onb_2_desc',
    ),
    _OnboardingPage(
      'assets/images/onboarding_3.png',
      'onb_3_title',
      'onb_3_desc',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _goToLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(OnboardingScreen.hasSeenOnboardingKey, true);
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: widget.loginRouteBuilder ?? (_) => const LoginScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _pages.length - 1;

    return Scaffold(
      backgroundColor: AppColors.slate900,
      body: SafeArea(
        child: Column(
          children: [
            // Nút Bỏ qua
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 16, top: 8),
                child: TextButton(
                  onPressed: _goToLogin,
                  child: Text(
                    context.tr('onb_skip'),
                    style: GoogleFonts.inter(
                      color: AppColors.slate400,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),

            // Nội dung Slide
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) {
                  final page = _pages[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        const Spacer(),
                        Container(
                          height: 260,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            color: AppColors.slate800,
                            border:
                                Border.all(color: AppColors.slate700, width: 1),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Image.asset(
                              page.imagePath,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          context.tr(page.title),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            color: AppColors.slate50,
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          context.tr(page.description),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            color: AppColors.slate400,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                        const Spacer(flex: 2),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Indicator dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (i) {
                final isActive = _page == i;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: isActive ? 28 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isActive ? AppColors.income : AppColors.slate700,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            const SizedBox(height: 32),

            // Nút Tiếp tục / Bắt đầu
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.income,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    if (isLast) {
                      _goToLogin();
                    } else {
                      _controller.nextPage(
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeInOut,
                      );
                    }
                  },
                  child: Text(
                    isLast ? context.tr('onb_start') : context.tr('onb_next'),
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

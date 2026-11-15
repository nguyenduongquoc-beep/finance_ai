import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'admin_web/screens/admin_login_screen.dart';
import 'admin_web/screens/admin_web_shell_screen.dart';
import 'firebase_options.dart';
import 'l10n/app_localizations.dart';
import 'services/language_controller.dart';
import 'utils/constants.dart';

/// ============================================================================
/// ENTRYPOINT DÀNH RIÊNG CHO TRANG QUẢN TRỊ WEB (ADMIN WEB PORTAL)
/// Chạy thử nghiệm trên trình duyệt:
///   flutter run -d chrome -t lib/main_admin.dart
/// Build bản Web Production:
///   flutter build web -t lib/main_admin.dart
/// ============================================================================
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await initializeDateFormatting('vi_VN', null);
  await initializeDateFormatting('en_US', null);
  await LanguageController.loadSavedLanguage();
  runApp(const FinanceAiAdminWebApp());
}

class FinanceAiAdminWebApp extends StatelessWidget {
  const FinanceAiAdminWebApp({super.key});

  static ThemeData _buildAdminWebTheme() {
    const background = AppColors.slate100;
    const surface = Colors.white;
    const border = AppColors.slate200;
    const textPrimary = AppColors.fixedLightTextPrimary;
    const textSecondary = AppColors.fixedLightTextSecondary;
    const accent = AppColors.primary;

    final scheme = const ColorScheme.light().copyWith(
      primary: accent,
      onPrimary: Colors.white,
      secondary: accent,
      onSecondary: Colors.white,
      error: AppColors.expense,
      surface: background,
      onSurface: textPrimary,
      outline: AppColors.slate300,
      outlineVariant: border,
    );

    final baseText = GoogleFonts.interTextTheme(ThemeData.light().textTheme)
        .apply(bodyColor: textPrimary, displayColor: textPrimary);

    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppColors.radiusControl),
    );
    OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusControl),
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      textTheme: baseText,
      scaffoldBackgroundColor: background,
      dividerColor: border,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        hintStyle: GoogleFonts.inter(color: textSecondary, fontSize: 13.5),
        labelStyle: GoogleFonts.inter(color: textSecondary, fontSize: 13.5),
        border: inputBorder(border),
        enabledBorder: inputBorder(border),
        focusedBorder: inputBorder(accent, 1.5),
        errorBorder: inputBorder(AppColors.expense),
        focusedErrorBorder: inputBorder(AppColors.expense, 1.5),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          shape: controlShape,
          textStyle: GoogleFonts.inter(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: const BorderSide(color: border, width: 1),
          shape: controlShape,
          textStyle: GoogleFonts.inter(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasSession = FirebaseAuth.instance.currentUser != null;

    return MaterialApp(
      title: 'Finance AI — Cổng Quản trị Hệ thống (Admin Web)',
      debugShowCheckedModeBanner: false,
      theme: _buildAdminWebTheme(),
      supportedLocales: LanguageController.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: hasSession
          ? const AdminWebShellScreen()
          : const AdminLoginScreen(),
    );
  }
}

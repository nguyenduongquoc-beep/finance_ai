import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../l10n/app_localizations.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../utils/constants.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';
import '../setup/wallet_setup_screen.dart';

/// Register Screen - Nhập Họ tên, Email, Password, Confirm Password
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _authService = AuthService();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _agreeToTerms = false;
  String? _errorMessage;

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreeToTerms) {
      setState(() => _errorMessage = AppLocalizations.tr('auth_terms_required'));
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final name = _nameController.text.trim();
      final email = _emailController.text.trim();
      final credential = await _authService.registerWithEmail(
        email: email,
        password: _passwordController.text,
        name: name,
      );
      final uid = credential.user?.uid ?? '';
      if (uid.isNotEmpty) {
        await FirestoreService().createUserProfile(
          AppUser(
            uid: uid,
            name: name,
            email: email,
            createdAt: DateTime.now(),
          ),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const WalletSetupScreen()),
      );
    } catch (e) {
      setState(() =>
          _errorMessage = AppLocalizations.tr('auth_err_register_failed'));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        backgroundColor: context.appBackground,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: context.appTextPrimary, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('auth_create_title'),
                  style: GoogleFonts.inter(
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                    color: context.appTextPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  context.tr('auth_create_sub'),
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: context.appTextSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 28),

                // Name
                AppTextField(
                  controller: _nameController,
                  labelText: context.tr('auth_name_label'),
                  hintText: context.tr('auth_name_hint'),
                  prefixIcon: Icons.person_outline_rounded,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? context.tr('auth_name_required')
                      : null,
                ),
                const SizedBox(height: 16),

                // Email
                AppTextField(
                  controller: _emailController,
                  labelText: context.tr('auth_email_label'),
                  hintText: context.tr('auth_email_hint'),
                  prefixIcon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) => (v == null || !v.contains('@'))
                      ? context.tr('auth_email_invalid')
                      : null,
                ),
                const SizedBox(height: 16),

                // Password
                AppTextField(
                  controller: _passwordController,
                  labelText: context.tr('auth_password_label'),
                  hintText: '••••••••',
                  prefixIcon: Icons.lock_outline_rounded,
                  obscureText: _obscurePassword,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: context.appTextSecondary,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  validator: (v) => (v == null || v.length < 6)
                      ? context.tr('auth_password_min')
                      : null,
                ),
                const SizedBox(height: 16),

                // Confirm Password
                AppTextField(
                  controller: _confirmPasswordController,
                  labelText: context.tr('auth_confirm_pw_label'),
                  hintText: '••••••••',
                  prefixIcon: Icons.lock_outline_rounded,
                  obscureText: _obscureConfirmPassword,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirmPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: context.appTextSecondary,
                      size: 20,
                    ),
                    onPressed: () => setState(() =>
                        _obscureConfirmPassword = !_obscureConfirmPassword),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) {
                      return context.tr('auth_confirm_pw_required');
                    }
                    if (v != _passwordController.text) {
                      return context.tr('auth_pw_mismatch');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Terms Checkbox
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: _agreeToTerms,
                        activeColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        side: BorderSide(color: context.appBorder, width: 1.5),
                        onChanged: (v) =>
                            setState(() => _agreeToTerms = v ?? false),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        context.tr('auth_terms_agree'),
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: context.appTextSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Error Message
                if (_errorMessage != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.expenseBackground,
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: AppColors.expense.withAlpha(80)),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: GoogleFonts.inter(
                          color: AppColors.expense, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Register Button
                AppButton(
                  text: context.tr('auth_register_btn'),
                  backgroundColor: const Color(0xFF161F28),
                  textColor: Colors.white,
                  isLoading: _isLoading,
                  onPressed: _handleRegister,
                ),
                const SizedBox(height: 24),

                // Already Have Account
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text.rich(
                      TextSpan(
                        text: context.tr('auth_have_account'),
                        style: GoogleFonts.inter(
                          color: context.appTextSecondary,
                          fontSize: 14,
                        ),
                        children: [
                          TextSpan(
                            text: context.tr('auth_login_btn'),
                            style: GoogleFonts.inter(
                              color: AppColors.primaryLight,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

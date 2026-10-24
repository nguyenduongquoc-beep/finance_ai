import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
import '../../utils/constants.dart';
import '../../utils/formatters.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';
import 'wallet_setup_screen.dart';

/// Thiết lập hồ sơ (Bước 1/3)
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _incomeController = TextEditingController();
  final _occupationController = TextEditingController();
  final _goalController = TextEditingController();
  final _firestoreService = FirestoreService();
  final ImagePicker _picker = ImagePicker();

  File? _selectedAvatarFile;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final displayName = FirebaseAuth.instance.currentUser?.displayName;
    if (displayName != null) _nameController.text = displayName;
  }

  Future<void> _pickAvatar() async {
    try {
      final picked = await _picker.pickImage(
          source: ImageSource.gallery, imageQuality: 70);
      if (picked != null) {
        setState(() => _selectedAvatarFile = File(picked.path));
      }
    } catch (e) {
      debugPrint('Error picking avatar: $e');
    }
  }

  Future<void> _handleContinue() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final appUser = AppUser(
        uid: user.uid,
        name: _nameController.text.trim(),
        email: user.email ?? '',
        monthlyIncome: AppFormatters.parseCurrencyInput(_incomeController.text),
        occupation: _occupationController.text.trim(),
        savingGoal: _goalController.text.trim(),
        avatar: null,
        createdAt: DateTime.now(),
      );
      await _firestoreService.createUserProfile(appUser);

      if (_selectedAvatarFile != null) {
        try {
          final path = await StorageService()
              .uploadAvatar(user.uid, _selectedAvatarFile!);
          await _firestoreService.updateUserProfile(user.uid, {'avatar': path});
        } catch (avatarError) {
          debugPrint('Avatar upload failed: $avatarError');
        }
      }

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const WalletSetupScreen()),
      );
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
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Step Indicator Badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight.withAlpha(25),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'BƯỚC 1/3',
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
                  'Thiết lập hồ sơ',
                  style: GoogleFonts.inter(
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                    color: context.appTextPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Cho chúng tôi biết một số thông tin cơ bản để cá nhân hóa thói quen tài chính của bạn.',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: context.appTextSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),

                // Avatar Upload
                Center(
                  child: GestureDetector(
                    onTap: _pickAvatar,
                    child: Stack(
                      children: [
                        Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: context.appBorder, width: 2),
                            color: context.appInputFill,
                          ),
                          child: ClipOval(
                            child: _selectedAvatarFile != null
                                ? Image.file(_selectedAvatarFile!,
                                    fit: BoxFit.cover)
                                : Icon(
                                    Icons.person_rounded,
                                    size: 44,
                                    color: context.appTextSecondary,
                                  ),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.camera_alt_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // Name Input
                AppTextField(
                  controller: _nameController,
                  labelText: 'Họ tên hiển thị',
                  hintText: 'Nguyễn Văn A',
                  prefixIcon: Icons.badge_outlined,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Vui lòng nhập tên'
                      : null,
                ),
                const SizedBox(height: 16),

                // Occupation Input
                AppTextField(
                  controller: _occupationController,
                  labelText: 'Nghề nghiệp',
                  hintText: 'Lập trình viên, Nhân viên văn phòng...',
                  prefixIcon: Icons.work_outline_rounded,
                ),
                const SizedBox(height: 16),

                // Income Input
                AppTextField(
                  controller: _incomeController,
                  labelText: 'Thu nhập hàng tháng (VNĐ)',
                  hintText: '15000000',
                  prefixIcon: Icons.monetization_on_outlined,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),

                // Goal Input
                AppTextField(
                  controller: _goalController,
                  labelText: 'Mục tiêu tiết kiệm chính',
                  hintText: 'Mua xe máy, Đi du lịch, Quỹ dự phòng...',
                  prefixIcon: Icons.flag_outlined,
                ),
                const SizedBox(height: 32),

                // Continue Button
                AppButton(
                  text: 'Tiếp tục',
                  isLoading: _isLoading,
                  onPressed: _handleContinue,
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

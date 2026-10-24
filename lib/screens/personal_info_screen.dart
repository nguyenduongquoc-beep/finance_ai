import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/formatters.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/app_text_field.dart';
import 'account_security_screen.dart';

/// Màn hình Thông tin cá nhân — Tối ưu hóa UI/UX Fintech chuyên nghiệp
/// Phân tách rõ ràng giữa quản lý Hồ sơ người dùng và Thiết lập bảo mật.
/// Tích hợp thu nhập hàng tháng (monthlyIncome) với chỉ dẫn rõ ràng.
class PersonalInfoScreen extends StatefulWidget {
  const PersonalInfoScreen({super.key});

  @override
  State<PersonalInfoScreen> createState() => _PersonalInfoScreenState();
}

class _PersonalInfoScreenState extends State<PersonalInfoScreen> {
  final _firestoreService = FirestoreService();
  final _authService = AuthService();
  final _picker = ImagePicker();

  final _nameController = TextEditingController();
  final _incomeController = TextEditingController();
  final _occupationController = TextEditingController();

  AppUser? _user;
  String? _avatarPath;
  File? _newAvatarFile;
  bool _isLoading = true;
  bool _isSavingProfile = false;

  final List<String> _suggestedOccupations = [
    'Nhân viên văn phòng',
    'Kinh doanh / Freelancer',
    'Kỹ sư / CNTT',
    'Học sinh / Sinh viên',
    'Kế toán / Tài chính',
    'Khác',
  ];

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final user = await _firestoreService.getUserProfile(uid);
    if (!mounted) return;

    if (user != null) {
      setState(() {
        _user = user;
        _avatarPath = user.avatar;
        _nameController.text = user.name;
        _incomeController.text =
            user.monthlyIncome > 0 ? user.monthlyIncome.toInt().toString() : '';
        _occupationController.text = user.occupation ?? '';
        _isLoading = false;
      });
    } else {
      // Fallback lấy thông tin từ Firebase Auth nếu chưa có doc Firestore
      final authUser = FirebaseAuth.instance.currentUser;
      setState(() {
        _user = AppUser(
          uid: uid,
          name: authUser?.displayName ?? '',
          email: authUser?.email ?? '',
          createdAt: DateTime.now(),
        );
        _nameController.text = authUser?.displayName ?? '';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _incomeController.dispose();
    _occupationController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 75,
        maxWidth: 800,
      );
      if (picked != null) {
        setState(() => _newAvatarFile = File(picked.path));
      }
    } catch (e) {
      debugPrint('Error picking avatar: $e');
      if (mounted) {
        AppSnackbar.show(
          context,
          'Không thể mở thư viện ảnh, vui lòng thử lại',
          isError: true,
        );
      }
    }
  }

  ImageProvider? _avatarImage() {
    if (_newAvatarFile != null) return FileImage(_newAvatarFile!);
    if (_avatarPath != null && _avatarPath!.isNotEmpty) {
      final file = File(_avatarPath!);
      if (file.existsSync()) return FileImage(file);
    }
    final photoUrl = FirebaseAuth.instance.currentUser?.photoURL;
    if (photoUrl != null && photoUrl.isNotEmpty) {
      return NetworkImage(photoUrl);
    }
    return null;
  }

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      AppSnackbar.show(context, 'Vui lòng nhập họ tên hiển thị', isError: true);
      return;
    }

    final incomeText = _incomeController.text.trim();
    double monthlyIncome = 0;
    if (incomeText.isNotEmpty) {
      try {
        monthlyIncome = AppFormatters.parseCurrencyInput(incomeText);
        if (monthlyIncome < 0) {
          AppSnackbar.show(
            context,
            'Thu nhập hàng tháng không được là số âm',
            isError: true,
          );
          return;
        }
      } catch (_) {
        AppSnackbar.show(
          context,
          'Số tiền thu nhập không hợp lệ',
          isError: true,
        );
        return;
      }
    }

    setState(() => _isSavingProfile = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

      // Upload avatar nếu có chọn ảnh mới
      if (_newAvatarFile != null) {
        try {
          final path =
              await StorageService().uploadAvatar(uid, _newAvatarFile!);
          await _firestoreService.updateUserProfile(uid, {'avatar': path});
          setState(() {
            _avatarPath = path;
            _newAvatarFile = null;
          });
        } catch (e) {
          debugPrint('Avatar upload warning: $e');
        }
      }

      // Cập nhật display name trên Firebase Authentication để đồng bộ
      await FirebaseAuth.instance.currentUser?.updateDisplayName(name);

      // Cập nhật thông tin Firestore
      final updateData = {
        'name': name,
        'monthlyIncome': monthlyIncome,
        'occupation': _occupationController.text.trim(),
      };
      await _firestoreService.updateUserProfile(uid, updateData);

      // Cập nhật lại model trong bộ nhớ local
      setState(() {
        _user = _user?.copyWith(
          name: name,
          monthlyIncome: monthlyIncome,
          occupation: _occupationController.text.trim(),
        );
      });

      if (mounted) {
        AppSnackbar.show(context, 'Đã cập nhật thông tin thành công');
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.show(
          context,
          'Không thể lưu thông tin. Vui lòng kiểm tra kết nối mạng.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingProfile = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: context.appBackground,
        appBar: AppBar(title: const Text('Thông tin cá nhân')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final createdAt = _user?.createdAt ?? DateTime.now();
    final formattedDate = DateFormat('dd/MM/yyyy').format(createdAt);
    final authProviderLabel = _authService.authProviderLabel;

    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        title: const Text('Thông tin cá nhân'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Khu vực Avatar
            Center(
              child: GestureDetector(
                onTap: _pickAvatar,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 48,
                      backgroundColor: AppColors.primary.withAlpha(25),
                      backgroundImage: _avatarImage(),
                      child: _avatarImage() == null
                          ? Text(
                              (_nameController.text.isNotEmpty)
                                  ? _nameController.text[0].toUpperCase()
                                  : 'U',
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primaryLight,
                              ),
                            )
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: context.appCard, width: 2),
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
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Nhấn vào ảnh để đổi ảnh đại diện',
                style: TextStyle(
                  fontSize: 12,
                  color: context.appTextSecondary,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 2. Nhóm thông tin cơ bản
            _buildSectionHeader('THÔNG TIN CƠ BẢN'),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppTextField(
                    controller: _nameController,
                    labelText: 'Họ tên hiển thị',
                    prefixIcon: Icons.person_outline_rounded,
                    hintText: 'Nhập họ và tên',
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),

                  // Thu nhập hàng tháng
                  AppTextField(
                    controller: _incomeController,
                    labelText: 'Thu nhập hàng tháng (VNĐ)',
                    prefixIcon: Icons.payments_outlined,
                    hintText: 'Ví dụ: 15.000.000',
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 14, color: context.appTextSecondary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Thu nhập khai báo dùng để gợi ý hạn mức ngân sách và phân tích AI. '
                          'Dữ liệu này không làm thay đổi số dư ví thực tế.',
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.3,
                            color: context.appTextSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Nghề nghiệp
                  AppTextField(
                    controller: _occupationController,
                    labelText: 'Nghề nghiệp / Lĩnh vực',
                    prefixIcon: Icons.work_outline_rounded,
                    hintText: 'Chọn hoặc nhập nghề nghiệp',
                  ),
                  const SizedBox(height: 10),

                  // Gợi ý nghề nghiệp
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _suggestedOccupations.map((occupation) {
                      final isSelected =
                          _occupationController.text == occupation;
                      return ChoiceChip(
                        label: Text(
                          occupation,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: isSelected
                                ? AppColors.primary
                                : context.appTextSecondary,
                          ),
                        ),
                        selected: isSelected,
                        selectedColor: AppColors.primary.withAlpha(30),
                        backgroundColor: context.appBackground,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: isSelected
                                ? AppColors.primary
                                : context.appBorder,
                          ),
                        ),
                        onSelected: (selected) {
                          setState(() {
                            _occupationController.text =
                                selected ? occupation : '';
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 3. Thông tin tài khoản hệ thống (Chỉ đọc)
            _buildSectionHeader('TÀI KHOẢN HỆ THỐNG'),
            AppCard(
              child: Column(
                children: [
                  _buildReadOnlyRow(
                    icon: Icons.email_outlined,
                    label: 'Email tài khoản',
                    value: _user?.email ?? '',
                    badge: 'Không thể đổi',
                  ),
                  const Divider(height: 20),
                  _buildReadOnlyRow(
                    icon: Icons.verified_user_outlined,
                    label: 'Phương thức xác thực',
                    value: authProviderLabel,
                  ),
                  const Divider(height: 20),
                  _buildReadOnlyRow(
                    icon: Icons.calendar_today_outlined,
                    label: 'Ngày tham gia',
                    value: formattedDate,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 4. Lối tắt sang Bảo mật & Đổi mật khẩu
            _buildSecurityShortcut(),
            const SizedBox(height: 28),

            // 5. Nút Lưu thay đổi
            AppButton(
              text: 'Lưu thay đổi',
              isLoading: _isSavingProfile,
              onPressed: _saveProfile,
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: context.appTextSecondary,
        ),
      ),
    );
  }

  Widget _buildReadOnlyRow({
    required IconData icon,
    required String label,
    required String value,
    String? badge,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: context.appTextSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: context.appTextSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.appTextPrimary,
                ),
              ),
            ],
          ),
        ),
        if (badge != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: context.appBackground,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: context.appBorder),
            ),
            child: Text(
              badge,
              style: TextStyle(
                fontSize: 10,
                color: context.appTextSecondary,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSecurityShortcut() {
    return AppCard(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AccountSecurityScreen()),
        );
      },
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.primary.withAlpha(20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.lock_reset_rounded,
              color: AppColors.primaryLight,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bảo mật & Đổi mật khẩu',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.appTextPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Quản lý mật khẩu và phương thức đăng nhập',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.appTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: context.appTextSecondary,
          ),
        ],
      ),
    );
  }
}

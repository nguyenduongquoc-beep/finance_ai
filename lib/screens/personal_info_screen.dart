import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../utils/constants.dart';
import '../widgets/app_card.dart';
import 'account_security_screen.dart';
import '../l10n/app_localizations.dart';

/// Màn hình Thông tin cá nhân — Tinh gọn, chỉ hiển thị các thông tin định danh
/// và tài khoản có giá trị sử dụng thực tế trong hệ thống.
class PersonalInfoScreen extends StatefulWidget {
  const PersonalInfoScreen({super.key});

  @override
  State<PersonalInfoScreen> createState() => _PersonalInfoScreenState();
}

class _PersonalInfoScreenState extends State<PersonalInfoScreen> {
  final _firestoreService = FirestoreService();
  final _authService = AuthService();

  AppUser? _user;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final authUser = FirebaseAuth.instance.currentUser;
    final uid = authUser?.uid ?? '';
    AppUser? user;
    if (uid.isNotEmpty) {
      user = await _firestoreService.getUserProfile(uid);
    }
    if (!mounted) return;

    setState(() {
      _user = user ??
          AppUser(
            uid: uid,
            name: authUser?.displayName ?? '',
            email: authUser?.email ?? '',
            createdAt: DateTime.now(),
          );
      _isLoading = false;
    });
  }

  ImageProvider? _avatarImage() {
    final avatarPath = _user?.avatar;
    if (avatarPath != null && avatarPath.isNotEmpty) {
      final file = File(avatarPath);
      if (file.existsSync()) return FileImage(file);
    }
    final photoUrl = FirebaseAuth.instance.currentUser?.photoURL;
    if (photoUrl != null && photoUrl.isNotEmpty) {
      return NetworkImage(photoUrl);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: context.appBackground,
        appBar: AppBar(title: Text(context.tr('profile_menu_personal_info'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final displayName = (_user?.name.trim().isNotEmpty == true)
        ? _user!.name.trim()
        : context.tr('common_user');
    final email = (_user?.email.trim().isNotEmpty == true)
        ? _user!.email.trim()
        : (_authService.currentUser?.email ?? '');
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U';
    final createdAt = _user?.createdAt ?? DateTime.now();
    final formattedDate = DateFormat('dd/MM/yyyy').format(createdAt);
    final avatar = _avatarImage();

    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        title: Text(context.tr('profile_menu_personal_info')),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Thẻ đại diện & định danh tóm tắt
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 44,
                    backgroundColor: AppColors.primary.withAlpha(25),
                    backgroundImage: avatar,
                    child: avatar == null
                        ? Text(
                            initial,
                            style: const TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryLight,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    displayName,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: context.appTextPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (email.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      email,
                      style: TextStyle(
                        fontSize: 13,
                        color: context.appTextSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 2. Thông tin tài khoản (Chỉ đọc)
            _buildSectionHeader(context.tr('pers_sec_account')),
            AppCard(
              child: Column(
                children: [
                  _buildReadOnlyRow(
                    icon: Icons.person_outline_rounded,
                    label: context.tr('pers_full_name'),
                    value: displayName,
                  ),
                  const Divider(height: 20),
                  _buildReadOnlyRow(
                    icon: Icons.email_outlined,
                    label: context.tr('pers_email_address'),
                    value: email,
                  ),
                  const Divider(height: 20),
                  _buildReadOnlyRow(
                    icon: Icons.calendar_today_outlined,
                    label: context.tr('pers_joined_date'),
                    value: formattedDate,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 3. Lối tắt sang Bảo mật & Đổi mật khẩu
            _buildSectionHeader(context.tr('pers_sec_security')),
            _buildSecurityShortcut(),
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
        if (badge != null) ...[
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: context.appBackground,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: context.appBorder),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  badge,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 10,
                    color: context.appTextSecondary,
                  ),
                ),
              ),
            ),
          ),
        ],
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
                  context.tr('profile_menu_security'),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.appTextPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  context.tr('profile_menu_security_sub'),
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

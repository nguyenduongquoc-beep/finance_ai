import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../utils/constants.dart';
import '../services/admin_ai_sandbox_service.dart';
import '../services/admin_web_service.dart';
import 'admin_ai_feedback_view.dart';
import 'admin_ai_studio_view.dart';
import 'admin_login_screen.dart';
import 'admin_ocr_dictionary_view.dart';
import 'admin_overview_view.dart';
import 'admin_platform_ops_view.dart';
import 'admin_rules_knowledge_view.dart';

/// Khung giao diện chính của Cổng Quản trị Web (Admin Web Portal Shell).
/// Bao gồm:
/// - Lớp bảo vệ quyền Admin theo thời gian thực (Realtime Admin Route Guard).
/// - Thanh điều hướng bên trái (Sidebar) chuẩn Web Desktop / Drawer trên màn hình hẹp.
/// - Đúng 6 khu vực quản trị AI & Tri thức Tài chính:
///   0. AI & Ops Dashboard
///   1. AI Studio & Sandbox
///   2. Financial Rules & Knowledge
///   3. OCR Dictionary
///   4. AI Feedback
///   5. Platform Ops
class AdminWebShellScreen extends StatefulWidget {
  final AdminWebService? adminService;
  final AdminAiSandboxService sandboxService;
  final String? adminUidOverride;
  final Map<String, dynamic>? tokenClaimsOverride;
  final Future<void> Function()? customSignOutHandler;
  final int initialIndex;

  const AdminWebShellScreen({
    super.key,
    this.adminService,
    this.sandboxService = const AdminAiSandboxService(),
    this.adminUidOverride,
    this.tokenClaimsOverride,
    this.customSignOutHandler,
    this.initialIndex = 0,
  });

  @override
  State<AdminWebShellScreen> createState() => _AdminWebShellScreenState();
}

class _AdminWebShellScreenState extends State<AdminWebShellScreen> {
  late final AdminWebService _adminService;
  late int _selectedIndex;
  int _rulesKnowledgeSubTabIndex = 0;
  int _platformOpsSubTabIndex = 0;
  String? _ocrPrefillKeyword;
  bool _isCheckingInitialAuth = true;
  AdminAuthCheckResult? _initialAuthCheck;

  static const List<Map<String, dynamic>> _navItems = [
    {
      'title': 'AI & Ops Dashboard',
      'icon': Icons.dashboard_outlined,
      'activeIcon': Icons.dashboard_rounded,
    },
    {
      'title': 'AI Studio & Sandbox',
      'icon': Icons.psychology_outlined,
      'activeIcon': Icons.psychology_rounded,
    },
    {
      'title': 'Financial Rules & Knowledge',
      'icon': Icons.rule_folder_outlined,
      'activeIcon': Icons.rule_folder_rounded,
    },
    {
      'title': 'OCR Dictionary',
      'icon': Icons.spellcheck_outlined,
      'activeIcon': Icons.spellcheck_rounded,
    },
    {
      'title': 'AI Feedback',
      'icon': Icons.feedback_outlined,
      'activeIcon': Icons.feedback_rounded,
    },
    {
      'title': 'Platform Ops',
      'icon': Icons.admin_panel_settings_outlined,
      'activeIcon': Icons.admin_panel_settings_rounded,
    },
  ];

  @override
  void initState() {
    super.initState();
    _adminService = widget.adminService ?? AdminWebService();
    _selectedIndex = widget.initialIndex.clamp(0, _navItems.length - 1);
    _verifyInitialAccess();
  }

  String get _resolvedAdminUid =>
      widget.adminUidOverride ?? FirebaseAuth.instance.currentUser?.uid ?? '';

  Future<void> _verifyInitialAccess() async {
    final res = await _adminService.verifyAdminAccess(
      uidOverride: _resolvedAdminUid,
      tokenClaimsOverride: widget.tokenClaimsOverride,
    );
    if (!mounted) return;
    setState(() {
      _initialAuthCheck = res;
      _isCheckingInitialAuth = false;
    });
  }

  Future<void> _handleLogout() async {
    if (widget.customSignOutHandler != null) {
      await widget.customSignOutHandler!();
    } else {
      try {
        await AuthService().signOut();
      } catch (_) {}
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => AdminLoginScreen(
          adminService: _adminService,
          tokenClaimsOverride: widget.tokenClaimsOverride,
        ),
      ),
      (route) => false,
    );
  }

  Widget _buildUnauthorizedBlockScreen(String message) {
    return Scaffold(
      backgroundColor: AppColors.slate100,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Container(
            key: const ValueKey('admin_unauthorized_guard_view'),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.slate200),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.gpp_bad_rounded,
                  size: 56,
                  color: AppColors.expense,
                ),
                const SizedBox(height: 16),
                Text(
                  'Truy cập bị từ chối',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.slate900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    color: AppColors.slate600,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  key: const ValueKey('admin_guard_back_to_login_btn'),
                  onPressed: _handleLogout,
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text('Quay lại Đăng nhập Quản trị'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingInitialAuth) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final initialCheck = _initialAuthCheck;
    if (initialCheck == null || !initialCheck.isAuthorized) {
      return _buildUnauthorizedBlockScreen(
        initialCheck?.errorMessage ??
            'Tài khoản hiện tại không có quyền Quản trị viên (Admin).',
      );
    }

    final uid = _resolvedAdminUid;
    final hasClaim = widget.tokenClaimsOverride?['admin'] == true ||
        initialCheck.hasAdminCustomClaim;

    return StreamBuilder<AppUser?>(
      stream: uid.isNotEmpty
          ? _adminService.firestoreService.streamUserProfile(uid)
          : null,
      builder: (context, snapshot) {
        final liveUser = snapshot.data ?? initialCheck.userProfile;

        if (liveUser != null && liveUser.isLocked) {
          return _buildUnauthorizedBlockScreen(
            'Tài khoản quản trị viên này vừa bị khóa. Phiên làm việc đã bị thu hồi.',
          );
        }

        if (!hasClaim && (liveUser == null || !liveUser.isAdmin)) {
          return _buildUnauthorizedBlockScreen(
            'Tài khoản không có quyền Quản trị viên (Admin) để truy cập trang này.',
          );
        }

        final adminEmail = liveUser?.email ?? '';
        final adminName = (liveUser?.name.isNotEmpty == true)
            ? liveUser!.name
            : 'Quản trị viên';

        return LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 860;

            return Scaffold(
              backgroundColor: AppColors.slate100,
              drawer: isDesktop
                  ? null
                  : Drawer(
                      child: _buildSidebarContent(
                        adminName: adminName,
                        adminEmail: adminEmail,
                        closeDrawerOnTap: true,
                      ),
                    ),
              body: Row(
                children: [
                  if (isDesktop)
                    SizedBox(
                      width: 265,
                      child: _buildSidebarContent(
                        adminName: adminName,
                        adminEmail: adminEmail,
                        closeDrawerOnTap: false,
                      ),
                    ),
                  Expanded(
                    child: Column(
                      children: [
                        _buildTopBar(
                          isDesktop: isDesktop,
                          adminName: adminName,
                          adminEmail: adminEmail,
                        ),
                        Expanded(
                          child: _buildActiveView(
                            adminUid: uid,
                            adminEmail: adminEmail,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSidebarContent({
    required String adminName,
    required String adminEmail,
    required bool closeDrawerOnTap,
  }) {
    return Container(
      color: AppColors.slate900,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.admin_panel_settings_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Finance AI',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'Admin Web Portal',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            color: AppColors.slate400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: AppColors.slate700, height: 1),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _navItems.length,
                itemBuilder: (context, index) {
                  final item = _navItems[index];
                  final isSelected = _selectedIndex == index;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Material(
                      color: isSelected
                          ? AppColors.primary
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        key: ValueKey('admin_nav_tab_$index'),
                        borderRadius: BorderRadius.circular(10),
                        onTap: () {
                          setState(() => _selectedIndex = index);
                          if (closeDrawerOnTap && Navigator.canPop(context)) {
                            Navigator.pop(context);
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSelected
                                    ? item['activeIcon'] as IconData
                                    : item['icon'] as IconData,
                                size: 20,
                                color: isSelected
                                    ? Colors.white
                                    : AppColors.slate400,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  item['title'] as String,
                                  style: GoogleFonts.inter(
                                    fontSize: 13.5,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    color: isSelected
                                        ? Colors.white
                                        : AppColors.slate300,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.slate800,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.slate700),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.privacy_tip_outlined,
                          size: 16,
                          color: AppColors.secondary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Bảo mật Dữ liệu Riêng tư',
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Admin không truy cập ví, giao dịch, ngân sách, mục tiêu tiết kiệm hay nội dung chat AI của User.',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppColors.slate400,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar({
    required bool isDesktop,
    required String adminName,
    required String adminEmail,
  }) {
    final currentTitle = _navItems[_selectedIndex]['title'] as String;

    return Container(
      height: 64,
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 24 : 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.slate200)),
      ),
      child: Row(
        children: [
          if (!isDesktop) ...[
            Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu_rounded),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(
              currentTitle,
              style: GoogleFonts.inter(
                fontSize: isDesktop ? 18 : 16,
                fontWeight: FontWeight.w700,
                color: AppColors.slate900,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.infoBackground,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.verified_user_rounded,
                    size: 15,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      adminEmail.isNotEmpty
                          ? '$adminName ($adminEmail)'
                          : adminName,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            key: const ValueKey('admin_shell_logout_btn'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              foregroundColor: AppColors.expense,
            ),
            onPressed: _handleLogout,
            icon: const Icon(Icons.logout_rounded, size: 16),
            label: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveView({
    required String adminUid,
    required String adminEmail,
  }) {
    switch (_selectedIndex) {
      case 0:
        return AdminOverviewView(
          adminService: _adminService,
          onNavigateTab: (idx) => setState(() => _selectedIndex = idx),
          onOpenKnowledgeBase: () => setState(() {
            _rulesKnowledgeSubTabIndex = 1;
            _selectedIndex = 2;
          }),
          onOpenPlatformOpsSubTab: (subIdx) => setState(() {
            _platformOpsSubTabIndex = subIdx;
            _selectedIndex = 5;
          }),
        );
      case 1:
        return AdminAiStudioView(
          adminWebService: _adminService,
          currentAdminUid: adminUid,
          currentAdminEmail: adminEmail,
          sandboxService: widget.sandboxService,
          tokenClaimsOverride: widget.tokenClaimsOverride,
        );
      case 2:
        return AdminRulesKnowledgeView(
          adminWebService: _adminService,
          currentAdminUid: adminUid,
          currentAdminEmail: adminEmail,
          sandboxService: widget.sandboxService,
          tokenClaimsOverride: widget.tokenClaimsOverride,
          initialSubTabIndex: _rulesKnowledgeSubTabIndex,
        );
      case 3:
        return AdminOcrDictionaryView(
          adminWebService: _adminService,
          currentAdminUid: adminUid,
          currentAdminEmail: adminEmail,
          tokenClaimsOverride: widget.tokenClaimsOverride,
          initialCandidateKeyword: _ocrPrefillKeyword,
        );
      case 4:
        return AdminAiFeedbackView(
          adminWebService: _adminService,
          currentAdminUid: adminUid,
          currentAdminEmail: adminEmail,
          tokenClaimsOverride: widget.tokenClaimsOverride,
          onOpenOcrDictionary: (kw) => setState(() {
            _ocrPrefillKeyword = kw;
            _selectedIndex = 3;
          }),
          onOpenAiStudio: () => setState(() => _selectedIndex = 1),
          onOpenHeuristics: () => setState(() {
            _rulesKnowledgeSubTabIndex = 0;
            _selectedIndex = 2;
          }),
        );
      case 5:
        return AdminPlatformOpsView(
          adminService: _adminService,
          currentAdminUid: adminUid,
          currentAdminEmail: adminEmail,
          tokenClaimsOverride: widget.tokenClaimsOverride,
          initialSubTabIndex: _platformOpsSubTabIndex,
        );
      default:
        return AdminOverviewView(
          adminService: _adminService,
          onNavigateTab: (idx) => setState(() => _selectedIndex = idx),
        );
    }
  }
}

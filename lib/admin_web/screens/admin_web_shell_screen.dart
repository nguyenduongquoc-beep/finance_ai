import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/support_service.dart';
import '../../utils/constants.dart';
import '../services/admin_web_service.dart';
import 'admin_announcements_and_logs_view.dart';
import 'admin_categories_view.dart';
import 'admin_login_screen.dart';
import 'admin_overview_view.dart';
import 'admin_support_center_view.dart';
import 'admin_users_view.dart';

/// Khung giao diện chính của Cổng Quản trị Web (Admin Web Portal Shell).
/// Bao gồm:
/// - Lớp bảo vệ quyền Admin theo thời gian thực (Realtime Admin Route Guard).
/// - Thanh điều hướng bên trái (Sidebar) chuẩn Web Desktop / Drawer trên màn hình hẹp.
/// - 6 khu vực quản trị vận hành & hỗ trợ:
///   0. Dashboard Tổng quan
///   1. Quản lý Người dùng
///   2. Danh mục Hệ thống
///   3. Thông báo Hệ thống
///   4. Nhật ký Quản trị
///   5. Tư vấn & Hỗ trợ
class AdminWebShellScreen extends StatefulWidget {
  final AdminWebService? adminService;
  final SupportService? supportService;
  final String? adminUidOverride;
  final Map<String, dynamic>? tokenClaimsOverride;
  final Future<void> Function()? customSignOutHandler;
  final int initialIndex;

  const AdminWebShellScreen({
    super.key,
    this.adminService,
    this.supportService,
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
  late final SupportService _supportService;
  late final Stream<int> _supportUnreadCountStream;
  late final Stream<AppUser?>? _userProfileStream;
  late int _selectedIndex;
  String? _pendingSupportTicketId;
  bool _isSidebarCollapsed = false;
  bool _isCheckingInitialAuth = true;
  AdminAuthCheckResult? _initialAuthCheck;

  static const int _supportTabIndex = 5;
  static const double _sidebarExpandedWidth = 264.0;
  static const double _sidebarCollapsedWidth = 76.0;
  static const Duration _sidebarAnimDuration = Duration(milliseconds: 200);

  static const List<Map<String, dynamic>> _navItems = [
    {
      'title': 'Dashboard Tổng quan',
      'icon': Icons.dashboard_outlined,
      'activeIcon': Icons.dashboard_rounded,
    },
    {
      'title': 'Quản lý Người dùng',
      'icon': Icons.people_outline_rounded,
      'activeIcon': Icons.people_rounded,
    },
    {
      'title': 'Danh mục Hệ thống',
      'icon': Icons.category_outlined,
      'activeIcon': Icons.category_rounded,
    },
    {
      'title': 'Thông báo Hệ thống',
      'icon': Icons.campaign_outlined,
      'activeIcon': Icons.campaign_rounded,
    },
    {
      'title': 'Nhật ký Quản trị',
      'icon': Icons.history_edu_outlined,
      'activeIcon': Icons.history_edu_rounded,
    },
    {
      'title': 'Tư vấn & Hỗ trợ',
      'icon': Icons.support_agent_outlined,
      'activeIcon': Icons.support_agent_rounded,
    },
  ];

  @override
  void initState() {
    super.initState();
    _adminService = widget.adminService ?? AdminWebService();
    _supportService = widget.supportService ??
        SupportService(
          firestore: _adminService.firestoreService.firestoreInstance,
        );
    _supportUnreadCountStream = _supportService.streamAdminUnreadCount();
    final initialUid = _resolvedAdminUid;
    _userProfileStream = initialUid.isNotEmpty
        ? _adminService.firestoreService.streamUserProfile(initialUid)
        : null;
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

    return StreamBuilder<AppUser?>(
      stream: _userProfileStream,
      builder: (context, snapshot) {
        final hasLiveSnapshot =
            snapshot.connectionState == ConnectionState.active ||
                snapshot.connectionState == ConnectionState.done;
        final liveUser =
            hasLiveSnapshot ? snapshot.data : initialCheck.userProfile;

        if (liveUser != null && liveUser.isLocked) {
          return _buildUnauthorizedBlockScreen(
            'Tài khoản quản trị viên này vừa bị khóa. Phiên làm việc đã bị thu hồi.',
          );
        }

        if (liveUser == null || !liveUser.isAdmin) {
          return _buildUnauthorizedBlockScreen(
            'Tài khoản không có quyền Quản trị viên (Admin) để truy cập trang này.',
          );
        }

        final adminEmail = liveUser.email;
        final adminName = liveUser.name.isNotEmpty
            ? liveUser.name
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
                        isCollapsed: false,
                        allowCollapseToggle: false,
                      ),
                    ),
              body: Row(
                children: [
                  if (isDesktop)
                    AnimatedContainer(
                      key: const ValueKey('admin_sidebar_container'),
                      duration: _sidebarAnimDuration,
                      curve: Curves.fastOutSlowIn,
                      width: _isSidebarCollapsed
                          ? _sidebarCollapsedWidth
                          : _sidebarExpandedWidth,
                      child: ClipRect(
                        child: _buildSidebarContent(
                          adminName: adminName,
                          adminEmail: adminEmail,
                          closeDrawerOnTap: false,
                          isCollapsed: _isSidebarCollapsed,
                          allowCollapseToggle: true,
                        ),
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
                            adminName: adminName,
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

  Widget _buildSidebarBrandLogoIcon({bool showExpandCue = false}) {
    final logoBox = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(11),
      ),
      child: const Icon(
        Icons.account_balance_wallet_rounded,
        color: Colors.white,
        size: 22,
      ),
    );

    if (!showExpandCue) return logoBox;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        logoBox,
        Positioned(
          right: -6,
          bottom: -4,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: AppColors.slate800,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.slate600, width: 1.2),
            ),
            child: const Icon(
              Icons.chevron_right_rounded,
              key: ValueKey('admin_sidebar_chevron_expand'),
              size: 13,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSidebarContent({
    required String adminName,
    required String adminEmail,
    required bool closeDrawerOnTap,
    required bool isCollapsed,
    required bool allowCollapseToggle,
  }) {
    return Container(
      color: AppColors.slate900,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, sideConstraints) {
            // Neo cố định tọa độ trục dọc của Logo (x = 18px) và các Icon điều hướng (x = 28px)
            // trong suốt quá trình thu phóng 76px <-> 264px để hoàn toàn không bị giật hay nhảy vị trí.
            final showExpandedLabels =
                !isCollapsed && (!allowCollapseToggle || sideConstraints.maxWidth >= 145);
            final textAreaWidth =
                (sideConstraints.maxWidth - 78).clamp(0.0, 186.0);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 12,
                  ),
                  child: Tooltip(
                    message: allowCollapseToggle
                        ? (isCollapsed
                            ? 'Mở rộng thanh điều hướng'
                            : 'Thu gọn thanh điều hướng')
                        : 'Finance AI Admin Web Portal',
                    waitDuration: const Duration(milliseconds: 220),
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        key: const ValueKey('admin_sidebar_logo_toggle'),
                        borderRadius: BorderRadius.circular(12),
                        mouseCursor: allowCollapseToggle
                            ? SystemMouseCursors.click
                            : SystemMouseCursors.basic,
                        hoverColor: AppColors.slate800,
                        highlightColor:
                            AppColors.slate800.withValues(alpha: 0.85),
                        splashColor: AppColors.primary.withValues(alpha: 0.18),
                        onTap: allowCollapseToggle
                            ? () {
                                setState(() {
                                  _isSidebarCollapsed = !_isSidebarCollapsed;
                                });
                              }
                            : null,
                        child: SizedBox(
                          height: 48,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              children: [
                                _buildSidebarBrandLogoIcon(
                                  showExpandCue:
                                      allowCollapseToggle && !showExpandedLabels,
                                ),
                                if (showExpandedLabels &&
                                    textAreaWidth > 20) ...[
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: ClipRect(
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  'Finance AI',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: GoogleFonts.inter(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w700,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                Text(
                                                  'Admin Web Portal',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: GoogleFonts.inter(
                                                    fontSize: 11.5,
                                                    color: AppColors.slate400,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (allowCollapseToggle &&
                                              sideConstraints.maxWidth >=
                                                  210) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              width: 26,
                                              height: 26,
                                              decoration: BoxDecoration(
                                                color: AppColors.slate800,
                                                borderRadius:
                                                    BorderRadius.circular(7),
                                                border: Border.all(
                                                  color: AppColors.slate700,
                                                ),
                                              ),
                                              child: const Icon(
                                                Icons.chevron_left_rounded,
                                                key: ValueKey(
                                                  'admin_sidebar_chevron_collapse',
                                                ),
                                                size: 18,
                                                color: AppColors.slate300,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const Divider(color: AppColors.slate700, height: 1),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    itemCount: _navItems.length,
                    itemBuilder: (context, index) {
                      final item = _navItems[index];
                      final title = item['title'] as String;
                      final isSelected = _selectedIndex == index;
                      final iconData = isSelected
                          ? item['activeIcon'] as IconData
                          : item['icon'] as IconData;

                      Widget navButton = Material(
                        color: isSelected
                            ? AppColors.primary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          key: ValueKey('admin_nav_tab_$index'),
                          borderRadius: BorderRadius.circular(10),
                          hoverColor: isSelected
                              ? AppColors.primary.withValues(alpha: 0.9)
                              : AppColors.slate800,
                          onTap: () {
                            setState(() => _selectedIndex = index);
                            if (closeDrawerOnTap &&
                                Navigator.canPop(context)) {
                              Navigator.pop(context);
                            }
                          },
                          child: SizedBox(
                            height: 46,
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14),
                              child: Row(
                                children: [
                                  index == _supportTabIndex &&
                                          !showExpandedLabels
                                      ? StreamBuilder<int>(
                                          stream: _supportUnreadCountStream,
                                          builder: (context, snap) {
                                            final unread = snap.data ?? 0;
                                            return Stack(
                                              clipBehavior: Clip.none,
                                              children: [
                                                Icon(
                                                  iconData,
                                                  size: 20,
                                                  color: isSelected
                                                      ? Colors.white
                                                      : AppColors.slate400,
                                                ),
                                                if (unread > 0)
                                                  Positioned(
                                                    right: -8,
                                                    top: -6,
                                                    child: Container(
                                                      key: const ValueKey(
                                                        'admin_support_sidebar_badge',
                                                      ),
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 5,
                                                        vertical: 1.5,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color:
                                                            AppColors.expense,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(999),
                                                      ),
                                                      child: Text(
                                                        unread > 49
                                                            ? '49+'
                                                            : '$unread',
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 9.5,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            );
                                          },
                                        )
                                      : Icon(
                                          iconData,
                                          size: 20,
                                          color: isSelected
                                              ? Colors.white
                                              : AppColors.slate400,
                                        ),
                                  if (showExpandedLabels) ...[
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
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
                                    if (index == _supportTabIndex &&
                                        sideConstraints.maxWidth >= 210)
                                      StreamBuilder<int>(
                                        stream: _supportUnreadCountStream,
                                        builder: (context, snap) {
                                          final unread = snap.data ?? 0;
                                          if (unread <= 0) {
                                            return const SizedBox.shrink();
                                          }
                                          return Container(
                                            key: const ValueKey(
                                              'admin_support_sidebar_badge',
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 7,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.expense,
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              unread > 49 ? '49+' : '$unread',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      );

                      if (!showExpandedLabels) {
                        navButton = Tooltip(
                          message: title,
                          preferBelow: false,
                          waitDuration: const Duration(milliseconds: 120),
                          child: navButton,
                        );
                      }

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: navButton,
                      );
                    },
                  ),
                ),
                if (showExpandedLabels && sideConstraints.maxWidth >= 220)
                  Padding(
                    key: const ValueKey('admin_sidebar_privacy_card'),
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
            );
          },
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

  void _openSupportTicketFromUserDetail(String ticketId) {
    final cleanId = ticketId.trim();
    if (cleanId.isEmpty) return;
    setState(() {
      _pendingSupportTicketId = cleanId;
      _selectedIndex = _supportTabIndex;
    });
  }

  Widget _buildActiveView({
    required String adminUid,
    required String adminEmail,
    required String adminName,
  }) {
    switch (_selectedIndex) {
      case 0:
        return AdminOverviewView(
          adminService: _adminService,
          currentAdminUid: adminUid,
          tokenClaimsOverride: widget.tokenClaimsOverride,
          onNavigateTab: (idx) => setState(() => _selectedIndex = idx),
        );
      case 1:
        return AdminUsersManagementView(
          adminService: _adminService,
          currentAdminUid: adminUid,
          currentAdminEmail: adminEmail,
          tokenClaimsOverride: widget.tokenClaimsOverride,
          onOpenSupportTicket: _openSupportTicketFromUserDetail,
        );
      case 2:
        return AdminCategoriesManagementView(
          adminService: _adminService,
          currentAdminUid: adminUid,
          currentAdminEmail: adminEmail,
          tokenClaimsOverride: widget.tokenClaimsOverride,
        );
      case 3:
        return AdminAnnouncementsView(
          adminService: _adminService,
          currentAdminUid: adminUid,
          currentAdminEmail: adminEmail,
          tokenClaimsOverride: widget.tokenClaimsOverride,
        );
      case 4:
        return AdminAuditLogsView(
          adminService: _adminService,
        );
      case _supportTabIndex:
        return AdminSupportCenterView(
          supportService: _supportService,
          currentAdminUid: adminUid,
          currentAdminName: adminName,
          initialTicketId: _pendingSupportTicketId,
          onInitialTicketHandled: () {
            if (mounted && _pendingSupportTicketId != null) {
              setState(() => _pendingSupportTicketId = null);
            }
          },
        );
      default:
        return AdminOverviewView(
          adminService: _adminService,
          currentAdminUid: adminUid,
          tokenClaimsOverride: widget.tokenClaimsOverride,
          onNavigateTab: (idx) => setState(() => _selectedIndex = idx),
        );
    }
  }
}

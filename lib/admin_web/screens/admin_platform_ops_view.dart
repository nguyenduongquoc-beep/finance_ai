import 'package:flutter/material.dart';
import '../../utils/constants.dart';
import '../services/admin_web_service.dart';
import 'admin_announcements_and_logs_view.dart';
import 'admin_categories_view.dart';
import 'admin_users_view.dart';

/// Khu vực 6: Platform Ops (Vận hành nền tảng tối giản)
/// Gom 4 công cụ vận hành cơ bản vào một khu vực thống nhất:
/// - 0: Người dùng (users)
/// - 1: Danh mục Hệ thống (system_categories)
/// - 2: Thông báo Hệ thống (system_announcements)
/// - 3: Nhật ký Quản trị Bất biến (admin_logs)
class AdminPlatformOpsView extends StatefulWidget {
  final AdminWebService adminService;
  final String currentAdminUid;
  final String currentAdminEmail;
  final Map<String, dynamic>? tokenClaimsOverride;
  final int initialSubTabIndex;

  const AdminPlatformOpsView({
    super.key,
    required this.adminService,
    required this.currentAdminUid,
    required this.currentAdminEmail,
    this.tokenClaimsOverride,
    this.initialSubTabIndex = 0,
  });

  @override
  State<AdminPlatformOpsView> createState() => _AdminPlatformOpsViewState();
}

class _AdminPlatformOpsViewState extends State<AdminPlatformOpsView> {
  late int _subTabIndex;

  @override
  void initState() {
    super.initState();
    _subTabIndex = widget.initialSubTabIndex.clamp(0, 3);
  }

  @override
  void didUpdateWidget(covariant AdminPlatformOpsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialSubTabIndex != oldWidget.initialSubTabIndex) {
      _subTabIndex = widget.initialSubTabIndex.clamp(0, 3);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.slate200),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment<int>(
                    value: 0,
                    icon: Icon(Icons.manage_accounts_outlined, size: 17),
                    label: Text('Người dùng'),
                  ),
                  ButtonSegment<int>(
                    value: 1,
                    icon: Icon(Icons.category_outlined, size: 17),
                    label: Text('Danh mục Hệ thống'),
                  ),
                  ButtonSegment<int>(
                    value: 2,
                    icon: Icon(Icons.campaign_outlined, size: 17),
                    label: Text('Thông báo Hệ thống'),
                  ),
                  ButtonSegment<int>(
                    value: 3,
                    icon: Icon(Icons.history_edu_outlined, size: 17),
                    label: Text('Nhật ký Quản trị'),
                  ),
                ],
                selected: {_subTabIndex},
                onSelectionChanged: (s) {
                  setState(() => _subTabIndex = s.first);
                },
              ),
            ),
          ),
        ),
        Expanded(child: _buildSubView()),
      ],
    );
  }

  Widget _buildSubView() {
    switch (_subTabIndex) {
      case 0:
        return AdminUsersManagementView(
          adminService: widget.adminService,
          currentAdminUid: widget.currentAdminUid,
          currentAdminEmail: widget.currentAdminEmail,
          tokenClaimsOverride: widget.tokenClaimsOverride,
        );
      case 1:
        return AdminCategoriesManagementView(
          adminService: widget.adminService,
          currentAdminUid: widget.currentAdminUid,
          currentAdminEmail: widget.currentAdminEmail,
          tokenClaimsOverride: widget.tokenClaimsOverride,
        );
      case 2:
        return AdminAnnouncementsView(
          adminService: widget.adminService,
          currentAdminUid: widget.currentAdminUid,
          currentAdminEmail: widget.currentAdminEmail,
          tokenClaimsOverride: widget.tokenClaimsOverride,
        );
      case 3:
      default:
        return AdminAuditLogsView(
          adminService: widget.adminService,
        );
    }
  }
}

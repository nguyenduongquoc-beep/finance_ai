import 'package:flutter/material.dart';
import '../../admin_web/screens/admin_web_shell_screen.dart';
import '../../admin_web/services/admin_web_service.dart';

/// Màn hình cầu nối bảo toàn tương thích ngược, ủy quyền toàn bộ giao diện
/// và kiểm tra phân quyền sang [AdminWebShellScreen].
class AdminDashboardScreen extends StatelessWidget {
  final VoidCallback? onSwitchToUserView;
  final AdminWebService? adminService;
  final String? adminUidOverride;

  const AdminDashboardScreen({
    super.key,
    this.onSwitchToUserView,
    this.adminService,
    this.adminUidOverride,
  });

  @override
  Widget build(BuildContext context) {
    return AdminWebShellScreen(
      adminService: adminService,
      adminUidOverride: adminUidOverride,
    );
  }
}

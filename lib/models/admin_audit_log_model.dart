/// ============================================================
/// ADMIN AUDIT LOG MODEL
/// Firestore collection: admin_logs/{logId}
/// Nguyên tắc bảo mật: Nhật ký quản trị bất biến (Immutable Audit Log).
/// Admin chỉ được phép đọc và tạo mới sau khi thao tác thực tế thành công,
/// tuyệt đối không được phép chỉnh sửa hoặc xóa bản ghi nhật ký.
/// ============================================================
class AdminAuditLog {
  final String id;
  final String adminId;
  final String adminEmail;
  final String action;
  final String
      targetType; // 'user' | 'system_category' | 'system_announcement' | 'config' | 'knowledge' | 'ai_feedback' | 'sandbox'
  final String targetId;
  final String targetLabel;
  final String result; // 'success' | 'failed'
  final String details;
  final String source; // 'cloud_function' | 'admin_web'
  final DateTime createdAt;

  const AdminAuditLog({
    required this.id,
    required this.adminId,
    this.adminEmail = '',
    required this.action,
    required this.targetType,
    required this.targetId,
    this.targetLabel = '',
    this.result = 'success',
    this.details = '',
    this.source = 'admin_web',
    required this.createdAt,
  });

  bool get isSuccess => result == 'success';

  /// Nhãn tiếng Việt hiển thị trực quan trên bảng Nhật ký quản trị
  String get actionDisplayLabel {
    switch (action) {
      case 'LOCK_USER':
        return 'Khóa tài khoản người dùng';
      case 'UNLOCK_USER':
        return 'Mở khóa tài khoản người dùng';
      case 'SET_USER_ROLE':
        return 'Cập nhật phân quyền tài khoản';
      case 'CREATE_SYSTEM_CATEGORY':
        return 'Thêm danh mục hệ thống';
      case 'UPDATE_SYSTEM_CATEGORY':
        return 'Cập nhật danh mục hệ thống';
      case 'HIDE_SYSTEM_CATEGORY':
        return 'Ẩn danh mục hệ thống';
      case 'SHOW_SYSTEM_CATEGORY':
        return 'Hiển thị lại danh mục hệ thống';
      case 'SEED_SYSTEM_CATEGORIES':
        return 'Khởi tạo bộ danh mục hệ thống';
      case 'CREATE_ANNOUNCEMENT':
        return 'Tạo thông báo hệ thống';
      case 'UPDATE_ANNOUNCEMENT':
        return 'Cập nhật thông báo hệ thống';
      case 'ACTIVATE_ANNOUNCEMENT':
        return 'Kích hoạt thông báo hệ thống';
      case 'DEACTIVATE_ANNOUNCEMENT':
        return 'Ngừng hiển thị thông báo hệ thống';
      case 'DELETE_ANNOUNCEMENT':
        return 'Xóa thông báo hệ thống';
      case 'VERIFY_SANDBOX_DRAFT':
        return 'Xác minh bản nháp AI Sandbox';
      case 'PUBLISH_CONFIG':
        return 'Xuất bản cấu hình AI / Tri thức';
      case 'ROLLBACK_CONFIG':
        return 'Khôi phục phiên bản cấu hình';
      case 'RESOLVE_AI_FEEDBACK':
        return 'Xử lý phản hồi chất lượng AI';
      case 'PUBLISH_KNOWLEDGE':
        return 'Xuất bản Tri thức Tài chính';
      case 'RUN_SANDBOX':
        return 'Chạy thử nghiệm Gemini AI Sandbox';
      default:
        return action;
    }
  }

  factory AdminAuditLog.fromMap(Map<String, dynamic> map, String id) {
    DateTime parsedCreatedAt = DateTime.now();
    final rawCreated = map['createdAt'];
    if (rawCreated is DateTime) {
      parsedCreatedAt = rawCreated;
    } else if (rawCreated is String) {
      parsedCreatedAt = DateTime.tryParse(rawCreated) ?? DateTime.now();
    } else if (rawCreated != null) {
      try {
        parsedCreatedAt = (rawCreated as dynamic).toDate() as DateTime;
      } catch (_) {}
    }

    return AdminAuditLog(
      id: id,
      adminId: (map['adminId'] ?? '').toString(),
      adminEmail: (map['adminEmail'] ?? '').toString(),
      action: (map['action'] ?? '').toString(),
      targetType: (map['targetType'] ?? 'user').toString(),
      targetId: (map['targetId'] ?? '').toString(),
      targetLabel: (map['targetLabel'] ?? '').toString(),
      result: (map['result'] ?? 'success').toString(),
      details: (map['details'] ?? '').toString(),
      source: (map['source'] ?? 'admin_web').toString(),
      createdAt: parsedCreatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'adminId': adminId,
      'adminEmail': adminEmail,
      'action': action,
      'targetType': targetType,
      'targetId': targetId,
      'targetLabel': targetLabel,
      'result': result,
      'details': details,
      'source': source,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

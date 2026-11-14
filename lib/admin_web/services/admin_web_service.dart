import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../../models/admin_audit_log_model.dart';
import '../../models/ai_runtime_config_model.dart';
import '../../models/monthly_financial_plan.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../utils/constants.dart';
import 'admin_http_helper.dart';

/// Callback gọi Cloud Function (hỗ trợ Dependency Injection cho Unit/Integration Test)
typedef AdminCloudFunctionCaller = Future<Map<String, dynamic>?> Function(
  String functionName,
  Map<String, dynamic> payload,
);

/// Kết quả kiểm tra quyền truy cập Admin
class AdminAuthCheckResult {
  final bool isAuthorized;
  final bool isLocked;
  final bool hasAdminCustomClaim;
  final bool hasAdminFirestoreRole;
  final bool claimsSynced;
  final bool verifiedByServer;
  final AppUser? userProfile;
  final String? errorMessage;

  const AdminAuthCheckResult({
    required this.isAuthorized,
    this.isLocked = false,
    this.hasAdminCustomClaim = false,
    this.hasAdminFirestoreRole = false,
    this.claimsSynced = false,
    this.verifiedByServer = false,
    this.userProfile,
    this.errorMessage,
  });
}

/// Kết quả gọi thử nghiệm Gemini AI Sandbox từ phía Server Cloud Function
class AdminSandboxRunResult {
  final String modelUsed;
  final List<String> triedModels;
  final String responseText;
  final bool? jsonValid;
  final List<String> jsonValidationErrors;
  final int latencyMs;
  final String? logId;
  final String draftVerificationNote;

  const AdminSandboxRunResult({
    required this.modelUsed,
    required this.triedModels,
    required this.responseText,
    this.jsonValid,
    this.jsonValidationErrors = const [],
    this.latencyMs = 0,
    this.logId,
    this.draftVerificationNote = '',
  });

  factory AdminSandboxRunResult.fromMap(Map<String, dynamic> map) {
    return AdminSandboxRunResult(
      modelUsed: (map['modelUsed'] ?? '').toString(),
      triedModels: (map['triedModels'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      responseText: (map['responseText'] ?? '').toString(),
      jsonValid: map['jsonValid'] is bool ? map['jsonValid'] as bool : null,
      jsonValidationErrors: (map['jsonValidationErrors'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      latencyMs: (map['latencyMs'] as num?)?.toInt() ?? 0,
      logId: map['logId']?.toString(),
      draftVerificationNote:
          (map['draftVerificationNote'] ?? '').toString(),
    );
  }
}

/// Dữ liệu một cột trên biểu đồ tăng trưởng người dùng theo tháng
class AdminGrowthBucket {
  final String monthKey; // Định dạng MM/yyyy
  final String shortLabel; // Định dạng T01, T02...
  final int newUsersCount;
  final int cumulativeUsersCount;

  const AdminGrowthBucket({
    required this.monthKey,
    required this.shortLabel,
    required this.newUsersCount,
    required this.cumulativeUsersCount,
  });
}

/// Số liệu tổng quan thực tế trên Dashboard Admin (100% từ dữ liệu thật)
class AdminDashboardMetrics {
  final int totalUsers;
  final int activeUsers;
  final int lockedUsers;
  final int adminUsers;
  final int totalSystemCategories;
  final int activeSystemCategories;
  final int hiddenSystemCategories;
  final int essentialExpenseCategories;
  final int flexibleExpenseCategories;
  final int incomeCategories;
  final List<AdminGrowthBucket> monthlyGrowth;
  final List<AppUser> recentUsers;
  final List<AdminAuditLog> recentLogs;

  const AdminDashboardMetrics({
    required this.totalUsers,
    required this.activeUsers,
    required this.lockedUsers,
    required this.adminUsers,
    required this.totalSystemCategories,
    required this.activeSystemCategories,
    required this.hiddenSystemCategories,
    required this.essentialExpenseCategories,
    required this.flexibleExpenseCategories,
    required this.incomeCategories,
    required this.monthlyGrowth,
    required this.recentUsers,
    required this.recentLogs,
  });
}

/// Exception khi tài khoản không đủ quyền Admin hoặc thao tác quản trị bị từ chối
class AdminPermissionException implements Exception {
  final String message;
  const AdminPermissionException(this.message);

  @override
  String toString() => message;
}

/// Service nghiệp vụ dành riêng cho Cổng Quản trị Web (Admin Web Portal).
/// Mọi thao tác thay đổi dữ liệu và ghi `admin_logs` đều đi qua Backend Cloud Functions.
/// Bảo mật: Không chứa API Key Gemini và không đọc/ghi dữ liệu tài chính cá nhân của người dùng.
class AdminWebService {
  static const String defaultCloudFunctionsBaseUrl =
      'https://us-central1-finance-ai-app-6df28.cloudfunctions.net';

  final FirestoreService _firestoreService;
  final FirebaseAuth? _firebaseAuth;
  final http.Client? _httpClient;
  final AdminCloudFunctionCaller? _customCloudCaller;
  final String cloudFunctionsBaseUrl;

  AdminWebService({
    FirestoreService? firestoreService,
    FirebaseAuth? firebaseAuth,
    http.Client? httpClient,
    AdminCloudFunctionCaller? cloudCaller,
    this.cloudFunctionsBaseUrl = defaultCloudFunctionsBaseUrl,
  })  : _firestoreService = firestoreService ?? FirestoreService(),
        _firebaseAuth = firebaseAuth,
        _httpClient = httpClient,
        _customCloudCaller = cloudCaller;

  FirestoreService get firestoreService => _firestoreService;

  FirebaseAuth get _auth => _firebaseAuth ?? FirebaseAuth.instance;

  /// Xác minh quyền Admin của người dùng hiện tại.
  /// - Trong luồng thực tế (`tokenClaimsOverride == null`): LUÔN gọi `adminVerifySession`
  ///   trên Backend Cloud Function để kiểm tra Firebase ID Token + trạng thái `users/{uid}`
  ///   + tự động đồng bộ Custom Claim `{ admin: true }` nếu cần, sau đó làm mới Token tại Client.
  ///   Nếu Backend trả về 401/403 hoặc không thể xác minh -> từ chối truy cập ngay lập tức.
  Future<AdminAuthCheckResult> verifyAdminAccess({
    String? uidOverride,
    Map<String, dynamic>? tokenClaimsOverride,
    bool verifyWithBackend = false,
  }) async {
    final bool shouldVerifyWithBackend =
        verifyWithBackend || tokenClaimsOverride == null;

    if (!shouldVerifyWithBackend) {
      final String? uid = uidOverride ?? _auth.currentUser?.uid;
      if (uid == null || uid.isEmpty) {
        return const AdminAuthCheckResult(
          isAuthorized: false,
          errorMessage: 'Vui lòng đăng nhập bằng tài khoản Quản trị viên.',
        );
      }

      final hasCustomClaim = tokenClaimsOverride['admin'] == true;
      final profile = await _firestoreService.getUserProfile(uid);
      if (profile != null && profile.isLocked) {
        return AdminAuthCheckResult(
          isAuthorized: false,
          isLocked: true,
          hasAdminCustomClaim: hasCustomClaim,
          hasAdminFirestoreRole: profile.isAdmin,
          userProfile: profile,
          errorMessage:
              'Tài khoản quản trị viên này hiện đang bị khóa. Không thể truy cập hệ thống.',
        );
      }

      final hasFirestoreRole = profile?.isAdmin == true;
      final isAuthorized = hasCustomClaim || hasFirestoreRole;
      if (!isAuthorized) {
        return AdminAuthCheckResult(
          isAuthorized: false,
          hasAdminCustomClaim: hasCustomClaim,
          hasAdminFirestoreRole: hasFirestoreRole,
          userProfile: profile,
          errorMessage:
              'Truy cập bị từ chối: Tài khoản này là tài khoản Người dùng (User), không có quyền Quản trị viên (Admin).',
        );
      }

      return AdminAuthCheckResult(
        isAuthorized: true,
        hasAdminCustomClaim: hasCustomClaim,
        hasAdminFirestoreRole: hasFirestoreRole,
        userProfile: profile,
      );
    }

    // Luồng chuẩn Production/Web: Bắt buộc xác minh qua Server Cloud Function `adminVerifySession`
    final currentUser =
        (_customCloudCaller != null && _firebaseAuth == null)
            ? null
            : _auth.currentUser;
    if (_customCloudCaller == null && currentUser == null) {
      return const AdminAuthCheckResult(
        isAuthorized: false,
        errorMessage: 'Vui lòng đăng nhập bằng tài khoản Quản trị viên.',
      );
    }

    try {
      final serverSession = await _invokeAdminCloudFunction(
        'adminVerifySession',
        const <String, dynamic>{},
        method: 'GET',
      );

      final claimsSynced = serverSession['claimsSynced'] == true;
      if (claimsSynced && currentUser != null) {
        try {
          await currentUser.getIdTokenResult(true);
        } catch (_) {}
      }

      final uid = (serverSession['uid'] ?? currentUser?.uid ?? '').toString();
      AppUser? profile;
      if (uid.isNotEmpty) {
        try {
          profile = await _firestoreService.getUserProfile(uid);
        } catch (_) {}
      }
      profile ??= AppUser(
        uid: uid,
        name: (serverSession['name'] ?? '').toString(),
        email: (serverSession['email'] ?? currentUser?.email ?? '').toString(),
        role: (serverSession['role'] ?? 'admin').toString(),
        status: (serverSession['status'] ?? 'active').toString(),
        createdAt: DateTime.now(),
      );

      return AdminAuthCheckResult(
        isAuthorized: true,
        isLocked: false,
        hasAdminCustomClaim: serverSession['hasAdminClaim'] == true,
        hasAdminFirestoreRole: serverSession['hasFirestoreRole'] == true,
        claimsSynced: claimsSynced,
        verifiedByServer: true,
        userProfile: profile,
      );
    } on AdminCloudCallException catch (e) {
      final lower = e.message.toLowerCase();
      return AdminAuthCheckResult(
        isAuthorized: false,
        isLocked: lower.contains('khóa') || lower.contains('locked'),
        verifiedByServer: true,
        errorMessage: e.message,
      );
    } catch (e) {
      return AdminAuthCheckResult(
        isAuthorized: false,
        errorMessage: 'Không thể xác minh phiên Quản trị viên: $e',
      );
    }
  }

  /// Đảm bảo người gọi hiện tại có quyền Admin hợp lệ trước khi thực thi thao tác quản trị.
  Future<AppUser> _requireActiveAdmin(
    String adminUid, {
    Map<String, dynamic>? tokenClaimsOverride,
  }) async {
    final check = await verifyAdminAccess(
      uidOverride: adminUid,
      tokenClaimsOverride: tokenClaimsOverride,
    );
    if (!check.isAuthorized) {
      throw AdminPermissionException(
        check.errorMessage ??
            'Bạn không có quyền Quản trị viên để thực hiện thao tác này.',
      );
    }
    return check.userProfile ??
        AppUser(
          uid: adminUid,
          name: 'Admin',
          email: '',
          role: 'admin',
          status: 'active',
          createdAt: DateTime.now(),
        );
  }

  /// Gọi Cloud Function Admin endpoint bằng HTTP thực (`package:http`) hoặc caller inject trong test.
  /// Chuẩn hóa response và NÉM [AdminCloudCallException] cho mọi lỗi HTTP 4xx/5xx/mạng.
  Future<Map<String, dynamic>> _invokeAdminCloudFunction(
    String functionName,
    Map<String, dynamic> payload, {
    String method = 'POST',
    Duration timeout = const Duration(seconds: 25),
  }) async {
    if (_customCloudCaller != null) {
      final raw = await _customCloudCaller(functionName, payload);
      if (raw == null) {
        throw const AdminCloudCallException(
          statusCode: 0,
          kind: AdminCloudErrorKind.network,
          message: 'Cloud Function caller trả về null.',
        );
      }
      final statusCode = (raw['statusCode'] as num?)?.toInt() ??
          (raw['success'] == false ? 400 : 200);
      if (statusCode >= 400 || raw['success'] == false) {
        final validationErrors = (raw['validationErrors'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const <String>[];
        throw AdminCloudCallException(
          statusCode: statusCode,
          kind: classifyAdminHttpStatus(statusCode),
          message: (raw['error'] ?? 'Thao tác máy chủ thất bại.').toString(),
          validationErrors: validationErrors,
        );
      }
      return raw['data'] is Map
          ? Map<String, dynamic>.from(raw['data'] as Map)
          : raw;
    }

    final user = _auth.currentUser;
    if (user == null) {
      throw const AdminCloudCallException(
        statusCode: 401,
        kind: AdminCloudErrorKind.unauthenticated,
        message: 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
      );
    }
    final idToken = await user.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      throw const AdminCloudCallException(
        statusCode: 401,
        kind: AdminCloudErrorKind.unauthenticated,
        message: 'Không thể lấy Firebase ID Token hợp lệ.',
      );
    }

    final response = await sendAdminCloudRequest(
      method: method,
      url: '$cloudFunctionsBaseUrl/$functionName',
      idToken: idToken,
      body: method.toUpperCase() == 'GET' ? null : payload,
      client: _httpClient,
      timeout: timeout,
    );
    return response.requireSuccessData();
  }

  /// Lấy danh sách người dùng qua Backend `adminListUsers`
  Future<List<AppUser>> listUsersViaBackend({
    String? adminUid,
    Map<String, dynamic>? tokenClaimsOverride,
  }) async {
    if (adminUid != null && adminUid.isNotEmpty) {
      await _requireActiveAdmin(
        adminUid,
        tokenClaimsOverride: tokenClaimsOverride,
      );
    }
    final data = await _invokeAdminCloudFunction(
      'adminListUsers',
      const <String, dynamic>{},
      method: 'GET',
    );
    final rawUsers = data['users'] as List<dynamic>? ?? const [];
    return rawUsers
        .whereType<Map>()
        .map((m) {
          final map = Map<String, dynamic>.from(m);
          final uid = (map['uid'] ?? '').toString();
          return AppUser.fromMap(map, uid);
        })
        .toList();
  }

  /// Lấy thống kê Dashboard qua Backend `adminGetDashboardStats`
  Future<Map<String, dynamic>> fetchDashboardStatsViaBackend({
    String? adminUid,
    Map<String, dynamic>? tokenClaimsOverride,
  }) async {
    if (adminUid != null && adminUid.isNotEmpty) {
      await _requireActiveAdmin(
        adminUid,
        tokenClaimsOverride: tokenClaimsOverride,
      );
    }
    final data = await _invokeAdminCloudFunction(
      'adminGetDashboardStats',
      const <String, dynamic>{},
      method: 'GET',
    );
    return data['stats'] is Map
        ? Map<String, dynamic>.from(data['stats'] as Map)
        : data;
  }

  /// Khóa hoặc mở khóa tài khoản người dùng qua Cloud Function `adminSetUserStatus`
  /// (Backend tự cập nhật Auth, Firestore và ghi Audit Log nguyên tử; Client không tự ghi `admin_logs`).
  Future<void> setUserAccountStatus({
    required String adminUid,
    required String adminEmail,
    required AppUser targetUser,
    required bool lockAccount,
    String? reason,
    Map<String, dynamic>? tokenClaimsOverride,
  }) async {
    if (adminUid == targetUser.uid) {
      throw const AdminPermissionException(
        'Quản trị viên không thể tự khóa hoặc thay đổi trạng thái của chính mình.',
      );
    }

    await _requireActiveAdmin(
      adminUid,
      tokenClaimsOverride: tokenClaimsOverride,
    );
    final nextStatus = lockAccount ? 'locked' : 'active';

    await _invokeAdminCloudFunction(
      'adminSetUserStatus',
      {
        'targetUid': targetUser.uid,
        'status': nextStatus,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
  }

  /// Cấp hoặc thu hồi quyền Admin cho tài khoản qua Cloud Function `adminSetUserRole`
  Future<void> setUserAccountRole({
    required String adminUid,
    required String adminEmail,
    required AppUser targetUser,
    required String nextRole,
    Map<String, dynamic>? tokenClaimsOverride,
  }) async {
    if (adminUid == targetUser.uid && nextRole != 'admin') {
      throw const AdminPermissionException(
        'Quản trị viên không thể tự thu hồi quyền Admin của chính mình.',
      );
    }
    if (nextRole != 'user' && nextRole != 'admin') {
      throw const AdminPermissionException('Vai trò không hợp lệ.');
    }

    await _requireActiveAdmin(
      adminUid,
      tokenClaimsOverride: tokenClaimsOverride,
    );

    await _invokeAdminCloudFunction(
      'adminSetUserRole',
      {
        'targetUid': targetUser.uid,
        'role': nextRole,
      },
    );
  }

  /// Thêm mới hoặc chỉnh sửa danh mục mặc định hệ thống qua Cloud Function `adminManageSystemCategory`
  Future<String> saveSystemCategory({
    required String adminUid,
    required String adminEmail,
    required SystemCategoryTemplate template,
    required bool isNew,
    Map<String, dynamic>? tokenClaimsOverride,
  }) async {
    await _requireActiveAdmin(
      adminUid,
      tokenClaimsOverride: tokenClaimsOverride,
    );

    final res = await _invokeAdminCloudFunction(
      'adminManageSystemCategory',
      {
        'action': 'save',
        'isNew': isNew,
        'template': {
          'id': template.id,
          'name': template.name,
          'type': template.type,
          'icon': template.icon,
          'color': template.color,
          'isEssential': template.isEssential,
          'isActive': template.isActive,
          if (template.createdAt != null)
            'createdAt': template.createdAt!.toIso8601String(),
        },
      },
    );
    return (res['categoryId'] ?? template.id).toString();
  }

  /// Ẩn hoặc hiện danh mục hệ thống qua Cloud Function `adminManageSystemCategory`
  Future<void> toggleSystemCategoryActive({
    required String adminUid,
    required String adminEmail,
    required SystemCategoryTemplate template,
    required bool isActive,
    Map<String, dynamic>? tokenClaimsOverride,
  }) async {
    await _requireActiveAdmin(
      adminUid,
      tokenClaimsOverride: tokenClaimsOverride,
    );

    await _invokeAdminCloudFunction(
      'adminManageSystemCategory',
      {
        'action': 'toggle_active',
        'categoryId': template.id,
        'isActive': isActive,
        'categoryName': template.name,
      },
    );
  }

  /// Khởi tạo bộ danh mục mẫu chuẩn ban đầu qua Cloud Function `adminManageSystemCategory`
  Future<void> seedInitialSystemCategories({
    required String adminUid,
    required String adminEmail,
    Map<String, dynamic>? tokenClaimsOverride,
  }) async {
    await _requireActiveAdmin(
      adminUid,
      tokenClaimsOverride: tokenClaimsOverride,
    );

    final seedItems = <Map<String, dynamic>>[
      for (int i = 0; i < DefaultExpenseCategories.categories.length; i++)
        {
          'id': 'sys_exp_$i',
          'name': DefaultExpenseCategories.categories[i]['name'],
          'type': 'expense',
          'icon': DefaultExpenseCategories.categories[i]['icon'],
          'color': DefaultExpenseCategories.categories[i]['color'],
          'isEssential':
              (DefaultExpenseCategories.categories[i]['isEssential'] as bool?) ??
                  false,
        },
      for (int i = 0; i < DefaultIncomeCategories.categories.length; i++)
        {
          'id': 'sys_inc_$i',
          'name': DefaultIncomeCategories.categories[i]['name'],
          'type': 'income',
          'icon': DefaultIncomeCategories.categories[i]['icon'],
          'color': DefaultIncomeCategories.categories[i]['color'],
          'isEssential': false,
        },
    ];

    await _invokeAdminCloudFunction(
      'adminManageSystemCategory',
      {
        'action': 'seed_defaults',
        'seedItems': seedItems,
      },
    );
  }

  /// Tạo mới hoặc chỉnh sửa thông báo hệ thống qua Cloud Function `adminManageAnnouncement`
  Future<String> saveAnnouncement({
    required String adminUid,
    required String adminEmail,
    required SystemAnnouncement announcement,
    required bool isNew,
    Map<String, dynamic>? tokenClaimsOverride,
  }) async {
    await _requireActiveAdmin(
      adminUid,
      tokenClaimsOverride: tokenClaimsOverride,
    );

    final res = await _invokeAdminCloudFunction(
      'adminManageAnnouncement',
      {
        'action': 'save',
        'isNew': isNew,
        'announcement': {
          'id': announcement.id,
          'title': announcement.title,
          'content': announcement.content,
          'isActive': announcement.isActive,
          'createdBy': adminEmail.trim().isNotEmpty ? adminEmail : adminUid,
          'createdAt': announcement.createdAt.toIso8601String(),
          if (announcement.updatedAt != null)
            'updatedAt': announcement.updatedAt!.toIso8601String(),
        },
      },
    );
    return (res['announcementId'] ?? announcement.id).toString();
  }

  /// Kích hoạt hoặc ngừng hiển thị thông báo hệ thống qua Cloud Function `adminManageAnnouncement`
  Future<void> toggleAnnouncementActive({
    required String adminUid,
    required String adminEmail,
    required SystemAnnouncement announcement,
    required bool isActive,
    Map<String, dynamic>? tokenClaimsOverride,
  }) async {
    await _requireActiveAdmin(
      adminUid,
      tokenClaimsOverride: tokenClaimsOverride,
    );

    await _invokeAdminCloudFunction(
      'adminManageAnnouncement',
      {
        'action': 'toggle_active',
        'announcementId': announcement.id,
        'isActive': isActive,
        'title': announcement.title,
      },
    );
  }

  /// Xóa thông báo hệ thống qua Cloud Function `adminManageAnnouncement`
  Future<void> deleteAnnouncement({
    required String adminUid,
    required String adminEmail,
    required SystemAnnouncement announcement,
    Map<String, dynamic>? tokenClaimsOverride,
  }) async {
    await _requireActiveAdmin(
      adminUid,
      tokenClaimsOverride: tokenClaimsOverride,
    );

    await _invokeAdminCloudFunction(
      'adminManageAnnouncement',
      {
        'action': 'delete',
        'announcementId': announcement.id,
        'title': announcement.title,
      },
    );
  }

  /// Xác minh bản nháp cấu hình AI Sandbox phía Server (`adminVerifyDraftInSandbox`)
  Future<Map<String, dynamic>> verifyDraftInSandbox({
    required String adminUid,
    required String configType,
    Map<String, dynamic>? simulationSummary,
    Map<String, dynamic>? tokenClaimsOverride,
  }) async {
    await _requireActiveAdmin(
      adminUid,
      tokenClaimsOverride: tokenClaimsOverride,
    );
    return _invokeAdminCloudFunction(
      'adminVerifyDraftInSandbox',
      {
        'configType': configType,
        if (simulationSummary != null) 'simulationSummary': simulationSummary,
      },
    );
  }

  /// Xuất bản cấu hình động nguyên tử (`adminPublishConfig`)
  Future<Map<String, dynamic>> publishConfig({
    required String adminUid,
    required String configType,
    String? changeNote,
    Map<String, dynamic>? tokenClaimsOverride,
  }) async {
    await _requireActiveAdmin(
      adminUid,
      tokenClaimsOverride: tokenClaimsOverride,
    );
    return _invokeAdminCloudFunction(
      'adminPublishConfig',
      {
        'configType': configType,
        if (changeNote != null && changeNote.trim().isNotEmpty)
          'changeNote': changeNote.trim(),
      },
    );
  }

  /// Khôi phục phiên bản cấu hình cũ (`adminRollbackConfig` - tạo version mới)
  Future<Map<String, dynamic>> rollbackConfig({
    required String adminUid,
    required String configType,
    required int targetVersionNumber,
    String? reason,
    Map<String, dynamic>? tokenClaimsOverride,
  }) async {
    await _requireActiveAdmin(
      adminUid,
      tokenClaimsOverride: tokenClaimsOverride,
    );
    return _invokeAdminCloudFunction(
      'adminRollbackConfig',
      {
        'configType': configType,
        'targetVersionNumber': targetVersionNumber,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
  }

  /// Xuất bản hoặc bật/tắt bài viết Tri thức Tài chính (`adminPublishKnowledgeBase`)
  Future<Map<String, dynamic>> publishKnowledgeArticle({
    required String adminUid,
    required String articleId,
    String action = 'publish',
    bool? isActive,
    String? changeNote,
    Map<String, dynamic>? tokenClaimsOverride,
  }) async {
    await _requireActiveAdmin(
      adminUid,
      tokenClaimsOverride: tokenClaimsOverride,
    );
    return _invokeAdminCloudFunction(
      'adminPublishKnowledgeBase',
      {
        'articleId': articleId,
        'action': action,
        if (isActive != null) 'isActive': isActive,
        if (changeNote != null && changeNote.trim().isNotEmpty)
          'changeNote': changeNote.trim(),
      },
    );
  }

  /// Xử lý phản hồi chất lượng AI từ người dùng (`adminResolveAiFeedback`)
  Future<Map<String, dynamic>> resolveAiFeedback({
    required String adminUid,
    required String reportId,
    required String status, // 'resolved' | 'ignored'
    String? adminResolutionNote,
    String? appliedAction,
    Map<String, dynamic>? tokenClaimsOverride,
  }) async {
    await _requireActiveAdmin(
      adminUid,
      tokenClaimsOverride: tokenClaimsOverride,
    );
    return _invokeAdminCloudFunction(
      'adminResolveAiFeedback',
      {
        'reportId': reportId,
        'status': status,
        if (adminResolutionNote != null)
          'adminResolutionNote': adminResolutionNote,
        if (appliedAction != null) 'appliedAction': appliedAction,
      },
    );
  }

  /// Gọi thử nghiệm Gemini AI Sandbox qua Cloud Function `adminRunSandbox`.
  /// Tuyệt đối KHÔNG gửi API Key từ Web; Server đọc GEMINI_API_KEY từ Secret Manager.
  Future<AdminSandboxRunResult> runLiveGeminiSandbox({
    required String adminUid,
    required String prompt,
    String? systemInstruction,
    String mode = 'chat_prompt',
    String primaryModel = AiRuntimeConfig.kDefaultPrimaryModel,
    List<String> fallbackModels = AiRuntimeConfig.kDefaultFallbackModels,
    double temperature = 0.35,
    bool expectStructuredPlanJson = false,
    SyntheticPersona? persona,
    Map<String, dynamic>? tokenClaimsOverride,
  }) async {
    await _requireActiveAdmin(
      adminUid,
      tokenClaimsOverride: tokenClaimsOverride,
    );
    final res = await _invokeAdminCloudFunction(
      'adminRunSandbox',
      {
        'mode': mode,
        'prompt': prompt,
        if (systemInstruction != null && systemInstruction.isNotEmpty)
          'systemInstruction': systemInstruction,
        'primaryModel': primaryModel,
        'fallbackModels': fallbackModels,
        'temperature': temperature,
        'expectStructuredPlanJson': expectStructuredPlanJson,
        if (persona != null) 'persona': {'id': persona.id, 'label': persona.title},
      },
      timeout: const Duration(seconds: 32),
    );
    return AdminSandboxRunResult.fromMap(res);
  }

  /// Tính toán số liệu Dashboard thực tế 100% từ danh sách User, Danh mục hệ thống và Nhật ký quản trị.
  AdminDashboardMetrics computeDashboardMetrics({
    required List<AppUser> users,
    required List<SystemCategoryTemplate> categories,
    required List<AdminAuditLog> logs,
    DateTime? referenceNow,
  }) {
    final now = referenceNow ?? DateTime.now();

    int activeUsers = 0;
    int lockedUsers = 0;
    int adminUsers = 0;
    for (final u in users) {
      if (u.isLocked) {
        lockedUsers++;
      } else {
        activeUsers++;
      }
      if (u.isAdmin) {
        adminUsers++;
      }
    }

    int activeCategories = 0;
    int hiddenCategories = 0;
    int essentialExpense = 0;
    int flexibleExpense = 0;
    int incomeCategories = 0;

    for (final c in categories) {
      if (c.isActive) {
        activeCategories++;
      } else {
        hiddenCategories++;
      }
      if (c.type == 'income') {
        incomeCategories++;
      } else {
        if (c.isEssential) {
          essentialExpense++;
        } else {
          flexibleExpense++;
        }
      }
    }

    final List<AdminGrowthBucket> monthlyGrowth = [];
    for (int i = 5; i >= 0; i--) {
      final monthDate = DateTime(now.year, now.month - i, 1);
      final endOfMonth = DateTime(monthDate.year, monthDate.month + 1, 0, 23, 59, 59);
      final monthKey = DateFormat('MM/yyyy').format(monthDate);
      final shortLabel = 'T${monthDate.month.toString().padLeft(2, '0')}';

      int newInMonth = 0;
      int cumulativeUpToMonth = 0;
      for (final u in users) {
        if (u.createdAt.year == monthDate.year &&
            u.createdAt.month == monthDate.month) {
          newInMonth++;
        }
        if (!u.createdAt.isAfter(endOfMonth)) {
          cumulativeUpToMonth++;
        }
      }

      monthlyGrowth.add(
        AdminGrowthBucket(
          monthKey: monthKey,
          shortLabel: shortLabel,
          newUsersCount: newInMonth,
          cumulativeUsersCount: cumulativeUpToMonth,
        ),
      );
    }

    final sortedUsers = List<AppUser>.from(users)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final recentUsers = sortedUsers.take(6).toList();

    final sortedLogs = List<AdminAuditLog>.from(logs)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final recentLogs = sortedLogs.take(8).toList();

    return AdminDashboardMetrics(
      totalUsers: users.length,
      activeUsers: activeUsers,
      lockedUsers: lockedUsers,
      adminUsers: adminUsers,
      totalSystemCategories: categories.length,
      activeSystemCategories: activeCategories,
      hiddenSystemCategories: hiddenCategories,
      essentialExpenseCategories: essentialExpense,
      flexibleExpenseCategories: flexibleExpense,
      incomeCategories: incomeCategories,
      monthlyGrowth: monthlyGrowth,
      recentUsers: recentUsers,
      recentLogs: recentLogs,
    );
  }
}

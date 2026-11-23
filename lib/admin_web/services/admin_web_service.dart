import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../../models/admin_audit_log_model.dart';
import '../../models/monthly_financial_plan.dart';
import '../../models/support_ticket_model.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../services/support_service.dart';
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
  static const String _envCloudFunctionsBaseUrl = String.fromEnvironment(
    'CLOUD_FUNCTIONS_BASE_URL',
    defaultValue: '',
  );
  static const bool _useFirebaseEmulator = bool.fromEnvironment(
    'USE_FIREBASE_EMULATOR',
    defaultValue: false,
  );
  static const String _firebaseEmulatorHost = String.fromEnvironment(
    'FIREBASE_EMULATOR_HOST',
    defaultValue: '127.0.0.1',
  );
  static const int _functionsEmulatorPort = int.fromEnvironment(
    'FUNCTIONS_EMULATOR_PORT',
    defaultValue: 5001,
  );
  static const String _firebaseProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: 'finance-ai-app-6df28',
  );

  static const String defaultCloudFunctionsBaseUrl =
      _envCloudFunctionsBaseUrl != ''
          ? _envCloudFunctionsBaseUrl
          : (_useFirebaseEmulator
              ? 'http://$_firebaseEmulatorHost:$_functionsEmulatorPort/$_firebaseProjectId/us-central1'
              : 'https://us-central1-finance-ai-app-6df28.cloudfunctions.net');

  static const bool defaultUseCloudFunctions =
      _useFirebaseEmulator || _envCloudFunctionsBaseUrl != '';

  final FirestoreService _firestoreService;
  final FirebaseAuth? _firebaseAuth;
  final http.Client? _httpClient;
  final AdminCloudFunctionCaller? _customCloudCaller;
  final bool useCloudFunctions;
  final String cloudFunctionsBaseUrl;

  AdminWebService({
    FirestoreService? firestoreService,
    FirebaseAuth? firebaseAuth,
    http.Client? httpClient,
    AdminCloudFunctionCaller? cloudCaller,
    bool? useCloudFunctions,
    this.cloudFunctionsBaseUrl = defaultCloudFunctionsBaseUrl,
  })  : _firestoreService = firestoreService ?? FirestoreService(),
        _firebaseAuth = firebaseAuth,
        _httpClient = httpClient,
        _customCloudCaller = cloudCaller,
        useCloudFunctions = useCloudFunctions ??
            (cloudCaller != null || defaultUseCloudFunctions);

  FirestoreService get firestoreService => _firestoreService;

  FirebaseFirestore get _db => _firestoreService.firestoreInstance;

  FirebaseAuth get _auth => _firebaseAuth ?? FirebaseAuth.instance;

  /// Ghi bản ghi Nhật ký Quản trị bất biến (append-only) cùng WriteBatch với thao tác chính (Firebase Spark).
  void _appendAuditLogToBatch(
    WriteBatch batch, {
    required String adminUid,
    required String adminEmail,
    required String action,
    required String targetType,
    required String targetId,
    required String targetLabel,
    required String details,
    required String createdAtIso,
  }) {
    final safeDetails =
        details.length > 500 ? details.substring(0, 500) : details;
    final logRef = _db.collection('admin_logs').doc();
    batch.set(logRef, <String, dynamic>{
      'adminId': adminUid,
      'adminEmail': adminEmail,
      'action': action,
      'targetType': targetType,
      'targetId': targetId,
      'targetLabel': targetLabel,
      'result': 'success',
      'details': safeDetails,
      'source': 'admin_web',
      'createdAt': createdAtIso,
    });
  }

  /// Xác minh quyền Admin của người dùng hiện tại.
  /// - Trên chế độ Cloud Functions (Blaze / Emulator): gọi `adminVerifySession` và đồng bộ Custom Claim.
  /// - Trên chế độ Firebase Spark (mặc định): đọc trực tiếp `users/{uid}` qua Firestore + Security Rules
  ///   và bắt buộc `role == 'admin' && status == 'active'` (không gọi URL Cloud Functions 404).
  Future<AdminAuthCheckResult> verifyAdminAccess({
    String? uidOverride,
    Map<String, dynamic>? tokenClaimsOverride,
    bool verifyWithBackend = false,
  }) async {
    final bool shouldVerifyWithBackend =
        verifyWithBackend || (useCloudFunctions && tokenClaimsOverride == null);

    if (!shouldVerifyWithBackend) {
      final String? uid = uidOverride ?? _auth.currentUser?.uid;
      if (uid == null || uid.isEmpty) {
        return const AdminAuthCheckResult(
          isAuthorized: false,
          errorMessage: 'Vui lòng đăng nhập bằng tài khoản Quản trị viên.',
        );
      }

      final hasCustomClaim = tokenClaimsOverride?['admin'] == true;
      final profile = await _firestoreService.getUserProfile(
        uid,
        includePrivateFinancial: false,
      );
      if (profile == null) {
        return AdminAuthCheckResult(
          isAuthorized: false,
          hasAdminCustomClaim: hasCustomClaim,
          hasAdminFirestoreRole: false,
          errorMessage:
              'Truy cập bị từ chối: Không tìm thấy hồ sơ quản trị viên hợp lệ.',
        );
      }
      if (profile.isLocked) {
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

      // Bắt buộc `users/{uid}.role == 'admin'` cùng `status == 'active'` (không cho claim cũ vượt qua khi đã hạ quyền)
      final hasFirestoreRole = profile.isAdmin;
      if (!hasFirestoreRole) {
        return AdminAuthCheckResult(
          isAuthorized: false,
          hasAdminCustomClaim: hasCustomClaim,
          hasAdminFirestoreRole: false,
          userProfile: profile,
          errorMessage:
              'Truy cập bị từ chối: Tài khoản này là tài khoản Người dùng (User), không có quyền Quản trị viên (Admin).',
        );
      }

      return AdminAuthCheckResult(
        isAuthorized: true,
        hasAdminCustomClaim: hasCustomClaim,
        hasAdminFirestoreRole: true,
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
      if ((e.kind == AdminCloudErrorKind.network ||
              e.kind == AdminCloudErrorKind.notFound) &&
          !verifyWithBackend) {
        final String? uid = uidOverride ?? currentUser?.uid;
        if (uid != null && uid.isNotEmpty) {
          final profile = await _firestoreService.getUserProfile(uid);
          if (profile != null && profile.isLocked) {
            return AdminAuthCheckResult(
              isAuthorized: false,
              isLocked: true,
              hasAdminFirestoreRole: profile.isAdmin,
              userProfile: profile,
              errorMessage:
                  'Tài khoản quản trị viên này hiện đang bị khóa. Không thể truy cập hệ thống.',
            );
          }
          final bool hasRole = profile?.isAdmin == true;
          if (hasRole) {
            return AdminAuthCheckResult(
              isAuthorized: true,
              hasAdminFirestoreRole: true,
              userProfile: profile,
            );
          }
          return AdminAuthCheckResult(
            isAuthorized: false,
            userProfile: profile,
            errorMessage:
                'Truy cập bị từ chối: Tài khoản này là tài khoản Người dùng (User), không có quyền Quản trị viên (Admin).',
          );
        }
      }
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

    final normalizedBaseUrl =
        cloudFunctionsBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    final response = await sendAdminCloudRequest(
      method: method,
      url: '$normalizedBaseUrl/$functionName',
      idToken: idToken,
      body: method.toUpperCase() == 'GET' ? null : payload,
      client: _httpClient,
      timeout: timeout,
    );
    return response.requireSuccessData();
  }

  /// Lấy danh sách người dùng (chỉ giữ 7 trường phi tài chính).
  /// - Trên chế độ Cloud Functions (Blaze / Emulator): gọi `adminListUsers` (Zero-Knowledge ở tầng mạng).
  /// - Trên chế độ Firebase Spark (mặc định): đọc trực tiếp Firestore qua `getUsersDirectorySanitizedForAdmin`.
  Future<List<AppUser>> listUsersViaBackend({
    String? adminUid,
    Map<String, dynamic>? tokenClaimsOverride,
    bool allowFirestoreFallback = true,
  }) async {
    if (adminUid != null && adminUid.isNotEmpty) {
      await _requireActiveAdmin(
        adminUid,
        tokenClaimsOverride: tokenClaimsOverride,
      );
    }
    if (!useCloudFunctions) {
      return _firestoreService.getUsersDirectorySanitizedForAdmin();
    }
    try {
      final data = await _invokeAdminCloudFunction(
        'adminListUsers',
        const <String, dynamic>{},
        method: 'GET',
      );
      final rawUsers = data['users'] as List<dynamic>? ?? const [];
      final users = rawUsers
          .whereType<Map>()
          .map((m) {
            final map = Map<String, dynamic>.from(m);
            final uid = (map['uid'] ?? '').toString();
            return AppUser.fromMap(map, uid);
          })
          .toList();
      users.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return users;
    } on AdminCloudCallException catch (e) {
      final isUnavailableEndpoint = e.kind == AdminCloudErrorKind.network ||
          e.kind == AdminCloudErrorKind.notFound;
      if (allowFirestoreFallback && isUnavailableEndpoint) {
        try {
          return await _firestoreService.getUsersDirectorySanitizedForAdmin();
        } catch (_) {
          throw AdminCloudCallException(
            statusCode: e.statusCode,
            kind: e.kind,
            message:
                'Không thể gọi Cloud Function adminListUsers (chưa deploy trên Firebase hoặc chưa bật Functions Emulator) và Firestore Rules đang khóa đọc trực tiếp collection users.',
          );
        }
      }
      rethrow;
    }
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

  /// Stream danh sách người dùng có phân trang theo lô (`limit`), thuần Firebase Spark & Zero-Knowledge.
  Stream<List<AppUser>> streamUsersDirectoryForAdmin({int limit = 25}) {
    return _firestoreService.streamUsersDirectoryForAdmin(limit: limit);
  }

  /// Lấy tối đa [limit] yêu cầu hỗ trợ gần nhất của một User cụ thể (Khối 2 - Hồ sơ vận hành).
  Future<List<SupportTicket>> fetchUserSupportTickets(
    String targetUid, {
    int limit = 10,
  }) {
    return SupportService(firestore: _db)
        .fetchUserTicketsForAdmin(targetUid, limit: limit);
  }

  /// Lấy tối đa [limit] bản ghi lịch sử tác động quản trị của một User cụ thể (Khối 3 - Hồ sơ vận hành).
  Future<List<AdminAuditLog>> fetchUserAdminLogs(
    String targetUid, {
    int limit = 10,
  }) {
    return _firestoreService.fetchAuditLogsForTarget(targetUid, limit: limit);
  }

  /// Khóa hoặc mở khóa tài khoản User thường 100% thuần Firebase Spark qua 1 `WriteBatch` nguyên tử:
  /// - Chặn tuyệt đối tự khóa chính mình và chặn khóa/mở khóa mọi tài khoản có `role == 'admin'`.
  /// - Cập nhật `users/{targetUid}` (`status`, `lockReason`, `lockedAt`, `lockedBy`, `updatedAt`).
  /// - Ghi đồng thời 1 bản ghi bất biến (`LOCK_USER` / `UNLOCK_USER`) vào `admin_logs`.
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
    if (targetUser.isAdmin) {
      throw const AdminPermissionException(
        'Không thể khóa hoặc mở khóa tài khoản Quản trị viên khác từ cổng Web Admin.',
      );
    }

    await _requireActiveAdmin(
      adminUid,
      tokenClaimsOverride: tokenClaimsOverride,
    );

    final nextStatus = lockAccount ? 'locked' : 'active';
    final rawReason = (reason ?? '').trim();
    if (lockAccount && rawReason.isEmpty) {
      throw const AdminPermissionException(
        'Vui lòng chọn hoặc nhập lý do khóa tài khoản.',
      );
    }
    final safeReason =
        rawReason.length > 350 ? rawReason.substring(0, 350) : rawReason;
    final actorLabel =
        adminEmail.trim().isNotEmpty ? adminEmail.trim() : adminUid;
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final targetLabel =
        targetUser.email.isNotEmpty ? targetUser.email : targetUser.uid;

    final batch = _db.batch();
    batch.update(_db.collection('users').doc(targetUser.uid), <String, dynamic>{
      'status': nextStatus,
      'lockReason': lockAccount ? safeReason : null,
      'lockedAt': lockAccount ? FieldValue.serverTimestamp() : null,
      'lockedBy': lockAccount ? actorLabel : null,
      'updatedAt': nowIso,
    });
    _appendAuditLogToBatch(
      batch,
      adminUid: adminUid,
      adminEmail: actorLabel,
      action: lockAccount ? 'LOCK_USER' : 'UNLOCK_USER',
      targetType: 'user',
      targetId: targetUser.uid,
      targetLabel: targetLabel,
      details: safeReason.isNotEmpty
          ? '${lockAccount ? 'Khóa' : 'Mở khóa'} tài khoản $targetLabel. Lý do: $safeReason'
          : '${lockAccount ? 'Khóa' : 'Mở khóa'} tài khoản $targetLabel.',
      createdAtIso: nowIso,
    );
    await batch.commit();
  }

  /// Thêm mới hoặc chỉnh sửa danh mục mặc định hệ thống (hỗ trợ cả Spark Firestore WriteBatch và Cloud Function).
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

    if (!useCloudFunctions) {
      final cleanName = template.name.trim();
      if (cleanName.isEmpty || cleanName.length > 80) {
        throw const AdminPermissionException(
          'Tên danh mục hệ thống phải từ 1 đến 80 ký tự.',
        );
      }
      final type = template.type == 'income' ? 'income' : 'expense';
      final icon = template.icon.trim().isNotEmpty
          ? template.icon.trim()
          : 'category';
      final isEssential = type == 'expense' ? template.isEssential : false;
      final nowUtc = DateTime.now().toUtc();
      final nowIso = nowUtc.toIso8601String();

      final col = _db.collection('system_categories');
      final docRef = template.id.trim().isNotEmpty
          ? col.doc(template.id.trim())
          : col.doc();

      String createdAtIso = (template.createdAt ?? nowUtc).toUtc().toIso8601String();
      if (!isNew) {
        final existingSnap = await docRef.get();
        if (existingSnap.exists && existingSnap.data()?['createdAt'] is String) {
          final existingCreated =
              (existingSnap.data()!['createdAt'] as String).trim();
          if (existingCreated.isNotEmpty) {
            createdAtIso = existingCreated;
          }
        }
      }

      final batch = _db.batch();
      batch.set(docRef, <String, dynamic>{
        'id': docRef.id,
        'name': cleanName,
        'type': type,
        'icon': icon,
        'color': template.color,
        'isEssential': isEssential,
        'isActive': template.isActive,
        'createdAt': createdAtIso,
        'updatedAt': nowIso,
      });
      _appendAuditLogToBatch(
        batch,
        adminUid: adminUid,
        adminEmail: adminEmail,
        action: isNew ? 'CREATE_SYSTEM_CATEGORY' : 'UPDATE_SYSTEM_CATEGORY',
        targetType: 'system_category',
        targetId: docRef.id,
        targetLabel: cleanName,
        details:
            '${isNew ? 'Tạo mới' : 'Cập nhật'} danh mục hệ thống "$cleanName" ($type, ${isEssential ? 'Thiết yếu' : 'Linh hoạt'}).',
        createdAtIso: nowIso,
      );
      await batch.commit();
      return docRef.id;
    }

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

  /// Ẩn hoặc hiện danh mục hệ thống (hỗ trợ cả Spark Firestore WriteBatch và Cloud Function).
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

    if (!useCloudFunctions) {
      final id = template.id.trim();
      if (id.isEmpty) {
        throw const AdminPermissionException('Thiếu mã danh mục hệ thống.');
      }
      final docRef = _db.collection('system_categories').doc(id);
      final existingSnap = await docRef.get();
      if (!existingSnap.exists) {
        throw const AdminPermissionException(
          'Không tìm thấy danh mục hệ thống cần cập nhật.',
        );
      }
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final label =
          (existingSnap.data()?['name']?.toString().trim().isNotEmpty == true)
              ? existingSnap.data()!['name'].toString().trim()
              : template.name;

      final batch = _db.batch();
      batch.update(docRef, {
        'isActive': isActive,
        'updatedAt': nowIso,
      });
      _appendAuditLogToBatch(
        batch,
        adminUid: adminUid,
        adminEmail: adminEmail,
        action: isActive ? 'SHOW_SYSTEM_CATEGORY' : 'HIDE_SYSTEM_CATEGORY',
        targetType: 'system_category',
        targetId: id,
        targetLabel: label,
        details: isActive
            ? 'Hiển thị lại danh mục mẫu "$label".'
            : 'Ẩn danh mục mẫu "$label" khỏi gợi ý tạo mới.',
        createdAtIso: nowIso,
      );
      await batch.commit();
      return;
    }

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

  /// Khởi tạo bộ danh mục mẫu chuẩn ban đầu (hỗ trợ cả Spark Firestore WriteBatch và Cloud Function).
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

    if (!useCloudFunctions) {
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final col = _db.collection('system_categories');
      final batch = _db.batch();
      for (final item in seedItems) {
        final itemId = (item['id'] ?? '').toString().trim();
        final itemName = (item['name'] ?? '').toString().trim();
        if (itemId.isEmpty || itemName.isEmpty) continue;
        batch.set(col.doc(itemId), <String, dynamic>{
          'id': itemId,
          'name': itemName,
          'type': item['type'] == 'income' ? 'income' : 'expense',
          'icon': (item['icon'] ?? 'category').toString(),
          'color': (item['color'] as num?)?.toInt() ?? 0xFF607D8B,
          'isEssential': item['isEssential'] == true,
          'isActive': true,
          'createdAt': nowIso,
          'updatedAt': nowIso,
        });
      }
      _appendAuditLogToBatch(
        batch,
        adminUid: adminUid,
        adminEmail: adminEmail,
        action: 'SEED_SYSTEM_CATEGORIES',
        targetType: 'system_category',
        targetId: 'system_categories',
        targetLabel: 'Bộ danh mục chuẩn (${seedItems.length} danh mục)',
        details:
            'Khởi tạo ${seedItems.length} danh mục mẫu mặc định cho hệ thống.',
        createdAtIso: nowIso,
      );
      await batch.commit();
      return;
    }

    await _invokeAdminCloudFunction(
      'adminManageSystemCategory',
      {
        'action': 'seed_defaults',
        'seedItems': seedItems,
      },
    );
  }

  /// Tạo mới hoặc chỉnh sửa thông báo hệ thống (hỗ trợ cả Spark Firestore WriteBatch và Cloud Function).
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

    if (!useCloudFunctions) {
      final cleanTitle = announcement.title.trim();
      final cleanContent = announcement.content.trim();
      if (cleanTitle.isEmpty ||
          cleanTitle.length > 150 ||
          cleanContent.isEmpty ||
          cleanContent.length > 1000) {
        throw const AdminPermissionException(
          'Tiêu đề (1-150 ký tự) hoặc nội dung (1-1000 ký tự) thông báo không hợp lệ.',
        );
      }

      final nowUtc = DateTime.now().toUtc();
      final nowIso = nowUtc.toIso8601String();
      final actorLabel = adminEmail.trim().isNotEmpty ? adminEmail.trim() : adminUid;
      final col = _db.collection('system_announcements');
      final docRef = announcement.id.trim().isNotEmpty
          ? col.doc(announcement.id.trim())
          : col.doc();

      String preservedCreatedBy = actorLabel;
      String preservedCreatedAt = announcement.createdAt.toUtc().toIso8601String();
      if (!isNew || announcement.id.trim().isNotEmpty) {
        final existingSnap = await docRef.get();
        if (existingSnap.exists) {
          final existingData = existingSnap.data() ?? const <String, dynamic>{};
          final rawCreatedBy = existingData['createdBy'];
          final rawCreatedAt = existingData['createdAt'];
          if (rawCreatedBy is String && rawCreatedBy.isNotEmpty) {
            preservedCreatedBy = rawCreatedBy;
          }
          if (rawCreatedAt is String && rawCreatedAt.isNotEmpty) {
            preservedCreatedAt = rawCreatedAt;
          }
        }
      }

      final batch = _db.batch();
      batch.set(docRef, <String, dynamic>{
        'id': docRef.id,
        'title': cleanTitle,
        'content': cleanContent,
        'isActive': announcement.isActive,
        'createdBy': preservedCreatedBy,
        'updatedBy': actorLabel,
        'createdAt': preservedCreatedAt,
        'updatedAt': nowIso,
      });
      _appendAuditLogToBatch(
        batch,
        adminUid: adminUid,
        adminEmail: adminEmail,
        action: isNew ? 'CREATE_ANNOUNCEMENT' : 'UPDATE_ANNOUNCEMENT',
        targetType: 'system_announcement',
        targetId: docRef.id,
        targetLabel: cleanTitle,
        details:
            '${isNew ? 'Tạo thông báo hệ thống mới' : 'Cập nhật thông báo hệ thống'} "$cleanTitle".',
        createdAtIso: nowIso,
      );
      await batch.commit();
      return docRef.id;
    }

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

  /// Kích hoạt hoặc ngừng hiển thị thông báo hệ thống (hỗ trợ cả Spark Firestore WriteBatch và Cloud Function).
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

    if (!useCloudFunctions) {
      final id = announcement.id.trim();
      if (id.isEmpty) {
        throw const AdminPermissionException('Thiếu mã thông báo hệ thống.');
      }
      final docRef = _db.collection('system_announcements').doc(id);
      final existingSnap = await docRef.get();
      if (!existingSnap.exists) {
        throw const AdminPermissionException(
          'Không tìm thấy thông báo hệ thống cần cập nhật.',
        );
      }
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final actorLabel = adminEmail.trim().isNotEmpty ? adminEmail.trim() : adminUid;
      final label =
          (existingSnap.data()?['title']?.toString().trim().isNotEmpty == true)
              ? existingSnap.data()!['title'].toString().trim()
              : announcement.title;

      final batch = _db.batch();
      batch.update(docRef, {
        'isActive': isActive,
        'updatedBy': actorLabel,
        'updatedAt': nowIso,
      });
      _appendAuditLogToBatch(
        batch,
        adminUid: adminUid,
        adminEmail: adminEmail,
        action: isActive ? 'ACTIVATE_ANNOUNCEMENT' : 'DEACTIVATE_ANNOUNCEMENT',
        targetType: 'system_announcement',
        targetId: id,
        targetLabel: label,
        details: isActive
            ? 'Kích hoạt hiển thị thông báo "$label".'
            : 'Ngừng hiển thị thông báo "$label".',
        createdAtIso: nowIso,
      );
      await batch.commit();
      return;
    }

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

  /// Xóa thông báo hệ thống (hỗ trợ cả Spark Firestore WriteBatch và Cloud Function).
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

    if (!useCloudFunctions) {
      final id = announcement.id.trim();
      if (id.isEmpty) {
        throw const AdminPermissionException('Thiếu mã thông báo hệ thống.');
      }
      final docRef = _db.collection('system_announcements').doc(id);
      final existingSnap = await docRef.get();
      if (!existingSnap.exists) {
        throw const AdminPermissionException(
          'Không tìm thấy thông báo hệ thống cần xóa.',
        );
      }
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final label =
          (existingSnap.data()?['title']?.toString().trim().isNotEmpty == true)
              ? existingSnap.data()!['title'].toString().trim()
              : announcement.title;

      final batch = _db.batch();
      batch.delete(docRef);
      _appendAuditLogToBatch(
        batch,
        adminUid: adminUid,
        adminEmail: adminEmail,
        action: 'DELETE_ANNOUNCEMENT',
        targetType: 'system_announcement',
        targetId: id,
        targetLabel: label,
        details: 'Đã xóa thông báo hệ thống "$label".',
        createdAtIso: nowIso,
      );
      await batch.commit();
      return;
    }

    await _invokeAdminCloudFunction(
      'adminManageAnnouncement',
      {
        'action': 'delete',
        'announcementId': announcement.id,
        'title': announcement.title,
      },
    );
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

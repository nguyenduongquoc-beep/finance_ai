/// ============================================================
/// USER MODEL & PRIVATE FINANCIAL PROFILE
/// - `users/{uid}`: Chỉ chứa siêu dữ liệu vận hành phi tài chính (Zero-Knowledge với Admin).
/// - `users/{uid}/private/financial_profile`: Chứa thông tin tài chính riêng tư
///   (`monthlyIncome`, `savingGoal`), bị chặn hoàn toàn với Admin ở Firestore Rules.
/// ============================================================
DateTime? _parseOptionalUserDateTime(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  if (raw is String && raw.trim().isNotEmpty) {
    return DateTime.tryParse(raw.trim());
  }
  try {
    return (raw as dynamic).toDate() as DateTime;
  } catch (_) {
    return null;
  }
}

/// Hồ sơ tài chính riêng tư lưu tại `users/{uid}/private/financial_profile`
class PrivateFinancialProfile {
  final double monthlyIncome;
  final String? savingGoal;
  final DateTime? updatedAt;

  const PrivateFinancialProfile({
    this.monthlyIncome = 0,
    this.savingGoal,
    this.updatedAt,
  });

  factory PrivateFinancialProfile.fromMap(Map<String, dynamic> map) {
    return PrivateFinancialProfile(
      monthlyIncome: (map['monthlyIncome'] as num?)?.toDouble() ?? 0.0,
      savingGoal: map['savingGoal']?.toString(),
      updatedAt: _parseOptionalUserDateTime(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'monthlyIncome': monthlyIncome,
      'savingGoal': savingGoal,
      if (updatedAt != null) 'updatedAt': updatedAt!.toUtc().toIso8601String(),
    };
  }
}

class AppUser {
  final String uid;
  final String name;
  final String email;
  final String? avatar;

  /// Trường tài chính chỉ giữ trong bộ nhớ khi Mobile đọc từ
  /// `users/{uid}/private/financial_profile` (hoặc fallback tương thích dữ liệu cũ).
  /// KHÔNG xuất ra `toMap()` ghi lên root `users/{uid}`.
  final double monthlyIncome;
  final String? savingGoal;

  final String? occupation;
  final String role; // 'user' | 'admin'
  final String status; // 'active' | 'locked'
  final String? authProvider; // 'password' | 'google' | 'google+password'
  final DateTime createdAt;
  final DateTime? lastActiveAt;
  final String? lockReason;
  final DateTime? lockedAt;
  final String? lockedBy;
  final DateTime? updatedAt;

  AppUser({
    required this.uid,
    required this.name,
    required this.email,
    this.avatar,
    this.monthlyIncome = 0,
    this.savingGoal,
    this.occupation,
    this.role = 'user',
    this.status = 'active',
    this.authProvider,
    required this.createdAt,
    this.lastActiveAt,
    this.lockReason,
    this.lockedAt,
    this.lockedBy,
    this.updatedAt,
  });

  bool get isAdmin => role == 'admin';
  bool get isLocked => status == 'locked';

  /// Nhãn tiếng Việt hiển thị phương thức đăng nhập trên Admin Web
  String get authProviderLabelVi {
    final normalized = (authProvider ?? '').trim().toLowerCase();
    switch (normalized) {
      case 'google':
        return 'Google';
      case 'password':
      case 'email':
        return 'Email/Mật khẩu';
      case 'google+password':
        return 'Google & Email/Mật khẩu';
      default:
        return 'Chưa ghi nhận';
    }
  }

  /// Tạo [AppUser] từ dữ liệu root `users/{uid}` (và tùy chọn dữ liệu riêng tư
  /// từ `users/{uid}/private/financial_profile`).
  /// Khi [includeLegacyFinancialFallback] = true (mặc định cho Mobile): ưu tiên đọc từ
  /// [privateFinancialMap], nếu chưa có mới fallback sang trường cũ trên [map].
  /// Khi [includeLegacyFinancialFallback] = false (dành cho Admin Web): luôn giữ
  /// `monthlyIncome = 0` và `savingGoal = null` theo nguyên tắc Zero-Knowledge.
  factory AppUser.fromMap(
    Map<String, dynamic> map,
    String uid, {
    Map<String, dynamic>? privateFinancialMap,
    bool includeLegacyFinancialFallback = true,
  }) {
    final parsedCreatedAt =
        _parseOptionalUserDateTime(map['createdAt']) ?? DateTime.now();

    double resolvedMonthlyIncome = 0;
    String? resolvedSavingGoal;
    if (privateFinancialMap != null) {
      resolvedMonthlyIncome =
          (privateFinancialMap['monthlyIncome'] as num?)?.toDouble() ??
              (includeLegacyFinancialFallback
                  ? ((map['monthlyIncome'] as num?)?.toDouble() ?? 0.0)
                  : 0.0);
      resolvedSavingGoal = privateFinancialMap['savingGoal']?.toString() ??
          (includeLegacyFinancialFallback
              ? map['savingGoal']?.toString()
              : null);
    } else if (includeLegacyFinancialFallback) {
      resolvedMonthlyIncome = (map['monthlyIncome'] as num?)?.toDouble() ?? 0.0;
      resolvedSavingGoal = map['savingGoal']?.toString();
    }

    final rawLockReason = map['lockReason']?.toString().trim();
    final rawLockedBy = map['lockedBy']?.toString().trim();
    final rawAuthProvider = map['authProvider']?.toString().trim();

    return AppUser(
      uid: uid,
      name: (map['name'] ?? '').toString(),
      email: (map['email'] ?? '').toString(),
      avatar: map['avatar']?.toString(),
      monthlyIncome: resolvedMonthlyIncome,
      savingGoal: resolvedSavingGoal,
      occupation: map['occupation']?.toString(),
      role: (map['role'] ?? 'user').toString(),
      status: (map['status'] ?? 'active').toString(),
      authProvider:
          (rawAuthProvider != null && rawAuthProvider.isNotEmpty)
              ? rawAuthProvider
              : null,
      createdAt: parsedCreatedAt,
      lastActiveAt: _parseOptionalUserDateTime(map['lastActiveAt']),
      lockReason:
          (rawLockReason != null && rawLockReason.isNotEmpty)
              ? rawLockReason
              : null,
      lockedAt: _parseOptionalUserDateTime(map['lockedAt']),
      lockedBy:
          (rawLockedBy != null && rawLockedBy.isNotEmpty) ? rawLockedBy : null,
      updatedAt: _parseOptionalUserDateTime(map['updatedAt']),
    );
  }

  /// Xuất siêu dữ liệu vận hành PHI TÀI CHÍNH để lưu vào root `users/{uid}`.
  /// Tuyệt đối không ghi `monthlyIncome` hay `savingGoal` lên `users/{uid}` để đảm bảo Zero-Knowledge.
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'avatar': avatar,
      'occupation': occupation,
      'role': role,
      'status': status,
      if (authProvider != null && authProvider!.trim().isNotEmpty)
        'authProvider': authProvider!.trim(),
      'createdAt': createdAt.toIso8601String(),
      if (lastActiveAt != null)
        'lastActiveAt': lastActiveAt!.toUtc().toIso8601String(),
      if (lockReason != null && lockReason!.trim().isNotEmpty)
        'lockReason': lockReason!.trim(),
      if (lockedAt != null) 'lockedAt': lockedAt!.toUtc().toIso8601String(),
      if (lockedBy != null && lockedBy!.trim().isNotEmpty)
        'lockedBy': lockedBy!.trim(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toUtc().toIso8601String(),
    };
  }

  /// Xuất phần dữ liệu tài chính riêng tư để lưu riêng tại `users/{uid}/private/financial_profile`.
  Map<String, dynamic> toPrivateFinancialMap() {
    return {
      'monthlyIncome': monthlyIncome,
      'savingGoal': savingGoal,
    };
  }

  AppUser copyWith({
    String? name,
    String? avatar,
    double? monthlyIncome,
    String? savingGoal,
    String? occupation,
    String? role,
    String? status,
    String? authProvider,
    DateTime? lastActiveAt,
    String? lockReason,
    DateTime? lockedAt,
    String? lockedBy,
    DateTime? updatedAt,
  }) {
    return AppUser(
      uid: uid,
      name: name ?? this.name,
      email: email,
      avatar: avatar ?? this.avatar,
      monthlyIncome: monthlyIncome ?? this.monthlyIncome,
      savingGoal: savingGoal ?? this.savingGoal,
      occupation: occupation ?? this.occupation,
      role: role ?? this.role,
      status: status ?? this.status,
      authProvider: authProvider ?? this.authProvider,
      createdAt: createdAt,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      lockReason: lockReason ?? this.lockReason,
      lockedAt: lockedAt ?? this.lockedAt,
      lockedBy: lockedBy ?? this.lockedBy,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

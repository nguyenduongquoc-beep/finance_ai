/// ============================================================
/// USER MODEL
/// Firestore collection: users/{uid}
/// ============================================================
class AppUser {
  final String uid;
  final String name;
  final String email;
  final String? avatar;
  final double monthlyIncome;
  final String? savingGoal;
  final String? occupation;
  final String role; // 'user' | 'admin'
  final String status; // 'active' | 'locked'
  final DateTime createdAt;

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
    required this.createdAt,
  });

  bool get isAdmin => role == 'admin';
  bool get isLocked => status == 'locked';

  factory AppUser.fromMap(Map<String, dynamic> map, String uid) {
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

    return AppUser(
      uid: uid,
      name: (map['name'] ?? '').toString(),
      email: (map['email'] ?? '').toString(),
      avatar: map['avatar']?.toString(),
      monthlyIncome: (map['monthlyIncome'] ?? 0).toDouble(),
      savingGoal: map['savingGoal']?.toString(),
      occupation: map['occupation']?.toString(),
      role: (map['role'] ?? 'user').toString(),
      status: (map['status'] ?? 'active').toString(),
      createdAt: parsedCreatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'avatar': avatar,
      'monthlyIncome': monthlyIncome,
      'savingGoal': savingGoal,
      'occupation': occupation,
      'role': role,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
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
      createdAt: createdAt,
    );
  }
}

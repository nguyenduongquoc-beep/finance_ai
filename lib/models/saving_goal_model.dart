/// ============================================================
/// SAVING GOAL MODEL
/// Firestore collection: savingGoals/{goalId}
/// (Mở rộng từ mục tiêu tiết kiệm trong hồ sơ người dùng)
/// ============================================================
class SavingGoal {
  final String goalId;
  final String userId;
  final String name; // vd: "Laptop"
  final double targetAmount; // vd: 25.000.000
  final double savedAmount; // vd: 8.000.000
  final int months; // số tháng để đạt mục tiêu
  final DateTime createdAt;

  SavingGoal({
    required this.goalId,
    required this.userId,
    required this.name,
    required this.targetAmount,
    this.savedAmount = 0,
    required this.months,
    required this.createdAt,
  });

  double get percentComplete =>
      targetAmount == 0 ? 0 : (savedAmount / targetAmount).clamp(0, 1);

  double get monthlyRequired {
    if (months <= 0) return 0;
    final remaining = targetAmount - savedAmount;
    if (remaining <= 0) return 0;
    return remaining / months;
  }

  double get dailyRequired => monthlyRequired / 30;

  factory SavingGoal.fromMap(Map<String, dynamic> map, String id) {
    return SavingGoal(
      goalId: id,
      userId: map['userId']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      targetAmount: _parseDouble(map['targetAmount']),
      savedAmount: _parseDouble(map['savedAmount']),
      months: _parseInt(map['months'], defaultValue: 1),
      createdAt: _parseDate(map['createdAt']),
    );
  }

  static double _parseDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val) ?? 0.0;
    return 0.0;
  }

  static int _parseInt(dynamic val, {int defaultValue = 1}) {
    if (val == null) return defaultValue;
    if (val is int) return val;
    if (val is num) return val.toInt();
    if (val is String) return int.tryParse(val) ?? defaultValue;
    return defaultValue;
  }

  static DateTime _parseDate(dynamic val) {
    if (val == null) return DateTime.now();
    if (val is DateTime) return val;
    if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
    try {
      // Hỗ trợ Firestore Timestamp (có toDate())
      return (val as dynamic).toDate() as DateTime;
    } catch (_) {
      return DateTime.now();
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'name': name,
      'targetAmount': targetAmount,
      'savedAmount': savedAmount,
      'months': months,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

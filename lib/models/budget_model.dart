/// ============================================================
/// BUDGET MODEL
/// Firestore collection: budgets/{budgetId}
/// ============================================================
class Budget {
  final String budgetId;
  final String userId;
  final String categoryId;
  final double limit;
  final String month; // định dạng "MM/yyyy"
  final String? sourcePlanId; // ID của MonthlyFinancialPlan đã tạo/cập nhật hạn mức này
  final double? prePlanLimit; // Hạn mức thủ công trước khi kế hoạch cập nhật (null nếu do kế hoạch tạo mới)
  final bool isManual; // true khi người dùng tự tạo hoặc tự chỉnh tay ở màn Thiết lập ngân sách

  Budget({
    required this.budgetId,
    required this.userId,
    required this.categoryId,
    required this.limit,
    required this.month,
    this.sourcePlanId,
    this.prePlanLimit,
    this.isManual = false,
  });

  /// Tính % đã dùng — KHÔNG clamp giới hạn trên, cho phép vượt >100%
  /// (chỉ clamp 0 ở cận dưới để tránh số âm hiển thị sai).
  double percentUsed(double spentAmount) =>
      limit <= 0 ? 0 : (spentAmount / limit).clamp(0, double.infinity);

  bool isOverBudget(double spentAmount) => spentAmount > limit;

  /// Cảnh báo sắp vượt: 80–99%.
  bool isNearLimit(double spentAmount) {
    final p = percentUsed(spentAmount);
    return p >= 0.8 && !isOverBudget(spentAmount);
  }

  /// Số tiền còn lại (có thể âm nếu vượt limit)
  double remaining(double spentAmount) => limit - spentAmount;

  factory Budget.fromMap(Map<String, dynamic> map, String id) {
    return Budget(
      budgetId: id,
      userId: map['userId'] ?? '',
      categoryId: map['categoryId'] ?? '',
      limit: (map['limit'] ?? 0).toDouble(),
      month: map['month'] ?? '',
      sourcePlanId: map['sourcePlanId']?.toString(),
      prePlanLimit: map['prePlanLimit'] != null
          ? (map['prePlanLimit'] as num).toDouble()
          : null,
      isManual: map['isManual'] == true,
      // Lưu ý: field 'spent' cũ (nếu còn sót trong document cũ) KHÔNG đọc nữa,
      // không throw lỗi — Firestore vẫn có thể còn field thừa, bỏ qua an toàn.
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'categoryId': categoryId,
      'limit': limit,
      'month': month,
      if (sourcePlanId != null) 'sourcePlanId': sourcePlanId,
      if (prePlanLimit != null) 'prePlanLimit': prePlanLimit,
      if (isManual) 'isManual': true,
      // Không còn ghi field 'spent' — không còn là nguồn sự thật.
    };
  }
}

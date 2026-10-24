/// ============================================================
/// FINANCIAL ISSUE MODEL
/// Một "vấn đề tài chính" đã phát hiện bằng ngưỡng (Dart thuần).
/// Dùng cho FinancialAnalyticsService — không lưu Firestore,
/// tính lại from scratch mỗi lần mở AiInsightScreen.
/// ============================================================
enum IssueSeverity { warning, critical } // vàng / đỏ
enum IssueCategory {
  spike,
  budgetShare,
  lowSaving,
  negativeCashflow,
  incomeDrop,
  goalAtRisk,
}

class FinancialIssue {
  final String title; // VD: "Ăn uống tăng 32% so với tháng trước"
  final String description; // câu mô tả ngắn, không cần AI viết
  final IssueSeverity severity;
  final IssueCategory category; // phân loại vấn đề
  final double confidenceScore; // 0-100, tính bằng Dart (không phải AI)
  final String? categoryName; // null nếu vấn đề không gắn 1 danh mục cụ thể (VD tỷ lệ tiết kiệm)
  final double? currentValue; // giá trị hiện tại (số tiền hoặc %)
  final double? thresholdValue; // ngưỡng đã vi phạm

  // Cấu trúc 4 bước: Vấn đề → Nguyên nhân → Tác động → Đề xuất
  final String rootCause; // Nguyên nhân cốt lõi
  final String impact; // Tác động tới dòng tiền/tài chính
  final String recommendation; // Phương án hành động khắc phục

  FinancialIssue({
    required this.title,
    required this.description,
    required this.severity,
    required this.category,
    required this.confidenceScore,
    this.categoryName,
    this.currentValue,
    this.thresholdValue,
    this.rootCause = '',
    this.impact = '',
    this.recommendation = '',
  });

  String get effectiveRootCause =>
      rootCause.isNotEmpty ? rootCause : 'Biến động phát sinh trong kỳ so với dữ liệu lịch sử.';

  String get effectiveImpact =>
      impact.isNotEmpty ? impact : description;

  String get effectiveRecommendation =>
      recommendation.isNotEmpty ? recommendation : 'Cân đối và thiết lập hạn mức kiểm soát chặt chẽ.';
}

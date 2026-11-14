import 'dart:convert';
import '../models/ai_runtime_config_model.dart';
import '../models/category_model.dart';
import '../models/financial_forecast_result.dart';
import '../models/financial_issue.dart';
import '../models/monthly_financial_plan.dart';
import '../models/transaction_model.dart';
import 'ai_config_sync_service.dart';

/// ============================================================================
/// AI PROMPT BUILDER (PURE DART - ZERO API KEY / IO / ML KIT DEPENDENCY)
/// Tách biệt hoàn toàn phần xây dựng Prompt, Data Grounding, Knowledge Injection
/// và kiểm duyệt JSON khỏi `AiService` và `config/api_keys.dart`.
/// Có thể sử dụng an toàn trên cả Mobile App lẫn Admin Web AI Sandbox.
/// ============================================================================
class AiPromptBuilder {
  const AiPromptBuilder._();

  static String buildCategorySummary(
    List<AppTransaction> transactions,
    List<Category> categories,
  ) {
    final Map<String, double> totals = {};
    double totalSpent = 0;
    for (final tx in transactions.where((t) => t.type == 'expense')) {
      totals[tx.categoryId] = (totals[tx.categoryId] ?? 0) + tx.amount;
      totalSpent += tx.amount;
    }
    final buffer = StringBuffer();
    totals.forEach((catId, amount) {
      final cat = categories.firstWhere(
        (c) => c.categoryId == catId,
        orElse: () => Category(
          categoryId: catId,
          userId: '',
          name: 'Khác',
          type: 'expense',
          icon: 'category',
          color: 0xFF9E9E9E,
        ),
      );
      final percent = totalSpent == 0 ? 0 : (amount / totalSpent * 100).round();
      buffer.writeln('- ${cat.name}: ${amount.round()} đồng ($percent%)');
    });
    return buffer.toString();
  }

  static String buildSpendingHabitsPrompt({
    required List<AppTransaction> transactions,
    required List<Category> categories,
  }) {
    final summary = buildCategorySummary(transactions, categories);
    return '''
Bạn là trợ lý tài chính cá nhân. Dựa trên dữ liệu chi tiêu 30 ngày gần đây sau đây, hãy
phân tích thói quen chi tiêu của người dùng và đưa ra nhận xét ngắn gọn, thân thiện,
kèm 1-2 gợi ý cải thiện cụ thể. Trả lời bằng tiếng Việt, khoảng 3-4 câu.

Dữ liệu chi tiêu theo danh mục:
$summary
''';
  }

  static String buildMonthEndPrompt({
    required double spentSoFar,
    required int dayOfMonth,
    required int totalDaysInMonth,
  }) {
    final safeDay = dayOfMonth <= 0 ? 1 : dayOfMonth;
    final dailyAvg = spentSoFar / safeDay;
    final predicted = dailyAvg * totalDaysInMonth;
    return '''
Người dùng đã chi $spentSoFar đồng trong $dayOfMonth ngày đầu tháng (tháng có
$totalDaysInMonth ngày). Với tốc độ chi tiêu trung bình $dailyAvg đồng/ngày, ước tính
tổng chi tiêu cuối tháng sẽ khoảng $predicted đồng. Hãy viết một câu nhận xét ngắn
gọn bằng tiếng Việt cho người dùng về dự đoán này.
''';
  }

  static String buildSavingPlanPrompt({
    required String goalName,
    required double targetAmount,
    required int months,
    double savedAmount = 0,
    double? monthlyIncome,
    double? monthlyExpense,
    List<String>? flexibleCategorySummaries,
    AiRuntimeConfig? runtimeConfig,
  }) {
    final cfg = runtimeConfig ?? AiRuntimeConfig.defaults();
    final remaining = (targetAmount - savedAmount).clamp(0.0, double.infinity);
    final safeMonths = months <= 0 ? 1 : months;
    final monthlyRequired = remaining / safeMonths;
    final dailyRequired = monthlyRequired / 30;

    final contextBuffer = StringBuffer();
    if (monthlyIncome != null && monthlyIncome > 0) {
      final exp = monthlyExpense ?? 0.0;
      final net = monthlyIncome - exp;
      contextBuffer.writeln(
          '- Thu nhập tham chiếu hàng tháng: ${monthlyIncome.round()} đồng');
      contextBuffer.writeln(
          '- Tổng chi tiêu hàng tháng hiện tại: ${exp.round()} đồng');
      contextBuffer.writeln(
          '- Dòng tiền ròng (Thu - Chi): ${net.round()} đồng/tháng');
    } else if (monthlyExpense != null && monthlyExpense > 0) {
      contextBuffer.writeln(
          '- Chưa có dữ liệu thu nhập; tổng chi tiêu hiện tại: ${monthlyExpense.round()} đồng/tháng');
    }
    if (flexibleCategorySummaries != null &&
        flexibleCategorySummaries.isNotEmpty) {
      contextBuffer.writeln(
          '- Các danh mục chi tiêu linh hoạt có thể tối ưu: ${flexibleCategorySummaries.join(", ")}');
    }

    final advisoryRule = cfg.savingGoalAdvisoryRule.trim();
    final advisorySlot = advisoryRule.isNotEmpty
        ? '\nĐịnh hướng tư vấn bổ sung:\n$advisoryRule\n'
        : '';

    return '''
Bạn là Cố vấn Tài chính Cá nhân. Người dùng đang lập kế hoạch cho mục tiêu tiết kiệm:
- Tên mục tiêu: "$goalName"
- Tổng số tiền mục tiêu: ${targetAmount.round()} đồng (Đã tích lũy: ${savedAmount.round()} đồng, Còn thiếu: ${remaining.round()} đồng)
- Thời hạn còn lại: $safeMonths tháng
- Mức cần tiết kiệm mỗi tháng: ${monthlyRequired.round()} đồng/tháng (~${dailyRequired.round()} đồng/ngày)
${contextBuffer.isNotEmpty ? '\nNgữ cảnh tài chính thực tế của người dùng:\n$contextBuffer' : ''}$advisorySlot
Hãy đưa ra kế hoạch thực hiện ngắn gọn, cụ thể bằng tiếng Việt gồm 3 ý:
1. Đánh giá tính khả thi của mức tiết kiệm ${monthlyRequired.round()} đồng/tháng so với dòng tiền hiện tại (nếu vượt quá khả năng dòng tiền ròng, hãy đề xuất rõ số tháng nên giãn thêm).
2. Chỉ rõ nên ưu tiên cắt giảm từ danh mục chi tiêu linh hoạt nào bao nhiêu tiền/tháng (không cắt giảm chi phí thiết yếu).
3. Một hành động cụ thể dễ thực hiện ngay trong tuần này.
Tuyệt đối không tự bịa số liệu ngoài dữ liệu đã cung cấp.
''';
  }

  static String buildTrendPrompt({
    required List<double> amounts,
    DateTime? now,
  }) {
    final effectiveNow = now ?? DateTime.now();
    final monthLabels = List.generate(amounts.length, (i) {
      final month = DateTime(
        effectiveNow.year,
        effectiveNow.month - (amounts.length - 1 - i),
        1,
      );
      return 'Tháng ${month.month}/${month.year}';
    });
    final dataLines = List.generate(
      amounts.length,
      (i) => '- ${monthLabels[i]}: ${amounts[i].toStringAsFixed(0)} đồng',
    );
    return '''
Bạn là trợ lý tài chính cá nhân. Dựa trên dữ liệu chi tiêu trong 6 tháng gần nhất dưới đây, hãy phân tích xu hướng (tăng, giảm, ổn định) và đưa ra nhận xét ngắn gọn, thân thiện bằng tiếng Việt. Nếu có xu hướng tăng, hãy tính % thay đổi và cung cấp gợi ý quản lý. Dữ liệu:
${dataLines.join('\n')}
''';
  }

  static String buildSpendingCutsPrompt({
    required String categoryName,
    required double currentDailyAvg,
    required double targetDailyAvg,
  }) {
    final monthlySavings = (currentDailyAvg - targetDailyAvg) * 30;
    return '''
Người dùng đang chi trung bình $currentDailyAvg đồng/ngày cho "$categoryName".
Nếu giảm xuống còn $targetDailyAvg đồng/ngày, mỗi tháng sẽ tiết kiệm được khoảng
$monthlySavings đồng. Viết một gợi ý ngắn gọn, thực tế bằng tiếng Việt.
''';
  }

  static String buildReceiptExtractionPrompt({
    String? ocrText,
    AiRuntimeConfig? runtimeConfig,
  }) {
    final cfg = runtimeConfig ?? AiRuntimeConfig.defaults();
    final hasRawText = ocrText != null && ocrText.trim().isNotEmpty;
    final ocrReferenceBlock = hasRawText
        ? '''
Văn bản OCR thô trích xuất sơ bộ từ thiết bị (có thể bị mất dấu tiếng Việt, nhòe chữ hoặc tách dòng trong bảng, hãy đối chiếu trực tiếp với hình ảnh hóa đơn đính kèm):
---
$ocrText
---
'''
        : '';

    final extraOcrHints = cfg.ocrExtraHints.trim();
    final extraHintsSlot = extraOcrHints.isNotEmpty
        ? '\nLƯU Ý BỔ SUNG TỪ QUẢN TRỊ VIÊN TRI THỨC:\n$extraOcrHints\n'
        : '';

    return '''
Bạn là trợ lý tài chính thông minh chuyên phân tích hóa đơn/biên lai thanh toán tiếng Việt.
$ocrReferenceBlock
Hãy kết hợp hình ảnh hóa đơn và văn bản tham chiếu (nếu có) để phân tích theo cấu trúc thực tế của hóa đơn và trả về JSON với các nguyên tắc sau:

1. CHI TIẾT MẶT HÀNG (`items`):
- Mỗi phần tử trong mảng `items` gồm:
  + `description` (string): Tên mặt hàng hoặc dịch vụ đầy đủ nhất có thể. Nếu tên món trong bảng bị ngắt xuống dòng trong cùng một mục (ví dụ dòng trên là "Cà Phê Sữa Đá", dòng dưới là "Máy"), phải ghép lại đầy đủ thành "Cà Phê Sữa Đá Máy".
  + `quantity` (number hoặc null): Số lượng (SL). Chỉ trích xuất khi hóa đơn có cung cấp thông tin số lượng; tuyệt đối KHÔNG tự suy diễn hoặc tự gán là 1 khi hóa đơn không có (hãy để null).
  + `unitPrice` (number hoặc null): Đơn giá. Chỉ trích xuất khi hóa đơn có cung cấp đơn giá; KHÔNG tự suy diễn khi hóa đơn không có (hãy để null).
  + `amount` (number): Thành tiền của mặt hàng đó. Khi có đủ `quantity`, `unitPrice` và `amount`, hãy kiểm tra tính nhất quán (`quantity * unitPrice = amount`) để tránh đọc nhầm cột.
  + `isInferred` (boolean): `true` nếu tên mặt hàng bị mờ/nhòe/sai dấu và đã được bạn suy luận khôi phục dựa trên ngữ cảnh; `false` nếu đọc rõ ràng.

2. XỬ LÝ ẢNH MỜ & SUY LUẬN NGỮ CẢNH:
- Nếu chữ trên hóa đơn bị mờ, thiếu nét hoặc OCR thô nhận diện sai dấu (ví dụ "Cà Phê Sữa Đa Máy"), hãy kết hợp các ký tự còn đọc được + ngữ cảnh lĩnh vực (ăn uống, quán cà phê, siêu thị, dịch vụ...) + mối liên hệ trên hóa đơn để khôi phục từ đúng ("Cà Phê Sữa Đá Máy") và đặt `isInferred: true`.
- Nếu thông tin quá mờ không đủ căn cứ đáng tin cậy để khẳng định, hãy giữ nguyên phần chữ đọc được và đánh dấu `isInferred: true` để người dùng kiểm tra lại, tuyệt đối không bịa đặt tên món hoặc số liệu.

3. ĐỊA ĐIỂM KINH DOANH (`merchant`, `address`, `isLocationInferred`):
- `merchant` (string): Tên cửa hàng / đơn vị kinh doanh (bao gồm cả tên chi nhánh nếu có, ví dụ "Kang Tea & Coffee - Bạch Đằng").
- `address` (string hoặc null): Địa chỉ in trên hóa đơn (số nhà, tên đường, phường/xã, quận/huyện/thành phố, tỉnh). Nếu một phần địa chỉ bị mờ, hãy kết hợp phần đọc rõ với ngữ cảnh địa danh để khôi phục phần có căn cứ, hoặc giữ lại phần địa chỉ xác định được; tuyệt đối KHÔNG tự tạo địa chỉ hoàn chỉnh nếu ảnh không đủ căn cứ.
- `isLocationInferred` (boolean): `true` nếu tên cửa hàng hoặc địa chỉ có phần bị mờ phải suy luận/khôi phục; `false` nếu đọc rõ ràng.

4. CÁC TRƯỜNG KHÁC:
- `total` (number): Tổng số tiền thanh toán cuối cùng (đồng).
- `date` (string hoặc null): Ngày giao dịch theo định dạng ISO `yyyy-MM-dd`.
- `paymentMethod` (string hoặc null): Phương thức thanh toán hoặc tên ví/ngân hàng trên hóa đơn như "Tiền mặt", "MoMo", "ZaloPay", "ShopeePay", "VNPay", "MB Bank", "Vietcombank", "Techcombank", "BIDV", "VietinBank", "ACB", "Chuyển khoản", "Thẻ ngân hàng"... Nếu hóa đơn ghi "Thanh toán tiền mặt" hoặc có "Tiền nhận"/"Tiền khách đưa" và "Tiền thừa"/"Tiền trả lại" thì trả về "Tiền mặt". Nếu không rõ thì để null.
- `inferredFields` (mảng string): Liệt kê ngắn gọn các nội dung đã được AI suy luận/khôi phục do chữ mờ (ví dụ: ["Tên món: khôi phục 'Cà Phê Sữa Đá Máy' từ chữ mờ"]), hoặc mảng rỗng `[]` nếu tất cả đều đọc rõ.
$extraHintsSlot
Chỉ trả về JSON thuần túy gồm các trường: `merchant`, `total`, `date`, `address`, `paymentMethod`, `items`, `isLocationInferred`, `inferredFields`. Không bọc trong markdown code block, không giải thích thêm.''';
  }

  static String buildIssuesPrompt(List<FinancialIssue> issues) {
    final issuesText =
        issues.map((i) => '- ${i.title}: ${i.description}').join('\n');
    return '''
Bạn là trợ lý tài chính cá nhân. Hệ thống đã PHÁT HIỆN SẴN các vấn đề tài chính
sau đây (dựa trên phân tích số liệu, không cần bạn tính toán lại):

$issuesText

Với MỖI vấn đề, hãy viết ngắn gọn (1-2 câu):
1. Nguyên nhân có thể (dựa trên loại vấn đề)
2. Đề xuất phương án cải thiện CÓ SỐ LIỆU CỤ THỂ (VD "giảm xuống còn X đồng/tháng")

Trả lời bằng tiếng Việt, giọng thân thiện, đi thẳng vào từng vấn đề.
''';
  }

  static String buildSingleIssuePrompt(FinancialIssue issue) {
    return '''
Bạn là trợ lý tài chính cá nhân. Hệ thống đã phát hiện vấn đề sau (đã tính
sẵn bằng số liệu, không cần bạn tính toán lại):

${issue.title}: ${issue.description}

Viết TỐI ĐA 2-3 câu bằng tiếng Việt: 1 câu nêu nguyên nhân có thể, 1 câu đề
xuất phương án cải thiện CÓ SỐ LIỆU CỤ THỂ. Không lan man, không mở đầu bằng
lời chào.
''';
  }

  static String buildFinancialInsightsPrompt(FinancialInsightSummary summary) {
    final buffer = StringBuffer();
    buffer.writeln(
        '=== CHỈ SỐ SỨC KHỎE TÀI CHÍNH: ${summary.healthScore}/100 (${summary.healthRating}) ===');

    if (summary.strengths.isNotEmpty) {
      buffer.writeln('Điểm mạnh ghi nhận:');
      for (final s in summary.strengths) {
        buffer.writeln('- $s');
      }
    }

    if (summary.deductions.isNotEmpty) {
      buffer.writeln('Các điểm cần cải thiện (khoản trừ):');
      for (final d in summary.deductions) {
        buffer.writeln('- ${d.reason} (-${d.points} điểm)');
      }
    }

    buffer.writeln('\n=== PHÂN TÍCH THU NHẬP & DÒNG TIỀN ===');
    buffer.writeln(
        '- Tổng thu nhập tháng: ${summary.incomeAnalytics.currentMonthIncome.round()}đ');
    buffer.writeln(
        '- Tăng trưởng thu so tháng trước: ${(summary.incomeAnalytics.growthRate * 100).round()}% (Độ ổn định: ${summary.incomeAnalytics.stability})');
    if (summary.incomeAnalytics.sources.isNotEmpty) {
      final topSource = summary.incomeAnalytics.sources.first;
      buffer.writeln(
          '- Nguồn thu lớn nhất: ${topSource.categoryName} (${topSource.amount.round()}đ, ${(topSource.percentage * 100).round()}%)');
    }

    buffer.writeln(
        '- Tổng chi tiêu thực tế: ${summary.cashFlowAnalytics.totalExpense.round()}đ');
    buffer.writeln(
        '- Dòng tiền ròng (Số tiền còn lại): ${summary.cashFlowAnalytics.netCashFlow.round()}đ (${summary.cashFlowAnalytics.isPositive ? "DƯƠNG" : "ÂM"}, tỷ lệ tiết kiệm: ${summary.cashFlowAnalytics.savingsRate.round()}%)');
    buffer.writeln(
        '- Trạng thái duy trì dòng tiền: ${summary.cashFlowAnalytics.sustainabilityStatus}');

    if (summary.monthEndForecast.hasEnoughData) {
      buffer.writeln(
          '- Số dư dự kiến cuối tháng: ${summary.monthEndForecast.projectedEndBalance.round()}đ');
    }

    if (summary.savingsGoalAssessment != null &&
        summary.savingsGoalAssessment!.goals.isNotEmpty) {
      buffer.writeln('\n=== ĐÁNH GIÁ MỤC TIÊU TIẾT KIỆM ===');
      buffer.writeln(
          '- Tổng tiền cần tích lũy/tháng: ${summary.savingsGoalAssessment!.totalMonthlyRequired.round()}đ');
      buffer.writeln(
          '- Thặng dư khả dụng: ${summary.savingsGoalAssessment!.availableCashFlow.round()}đ');
      buffer.writeln(
          '- Chênh lệch ngân sách mục tiêu: ${summary.savingsGoalAssessment!.gapAmount > 0 ? "Thiếu ${summary.savingsGoalAssessment!.gapAmount.round()}đ/tháng" : "Đủ ngân sách"}');
      for (final g in summary.savingsGoalAssessment!.goals) {
        buffer.writeln(
            '  * Mục tiêu "${g.goalName}": Cần ${g.monthlyRequired.round()}đ/tháng (${(g.percentComplete * 100).round()}% hoàn thành) - ${g.statusText}');
      }
    }

    if (summary.issues.isNotEmpty) {
      buffer.writeln('\n=== CÁC VẤN ĐỀ TÀI CHÍNH PHÁT HIỆN ===');
      for (final i in summary.issues) {
        buffer.writeln(
            '- ${i.title} (Mức độ: ${i.severity == IssueSeverity.critical ? "Nghiêm trọng" : "Cảnh báo"})');
        buffer.writeln('  Nguyên nhân: ${i.effectiveRootCause}');
        buffer.writeln('  Tác động: ${i.effectiveImpact}');
        buffer.writeln('  Đề xuất: ${i.effectiveRecommendation}');
      }
    }

    if (summary.actionPlan.items.isNotEmpty) {
      buffer.writeln('\n=== KẾ HOẠCH HÀNH ĐỘNG ĐỀ XUẤT ===');
      buffer.writeln(
          'Mục tiêu: Tiết kiệm thêm ${summary.actionPlan.totalProjectedSavings.round()}đ/tháng');
      for (final item in summary.actionPlan.items) {
        buffer.writeln(
            '- ${item.actionTitle}: Giảm ${item.targetReduction.round()}đ (Hạn mức trần: ${item.suggestedBudget.round()}đ)');
      }
    }

    return '''
Bạn là Cố vấn Tài chính Cá nhân Thông minh (AI Financial Advisor).
Dưới đây là BÁO CÁO CHỈ SỐ TÀI CHÍNH ĐÃ ĐƯỢC THUẬT TOÁN DART TÍNH TOÁN XÁC ĐỊNH CHÍNH XÁC từ dữ liệu thực tế của người dùng:

${buffer.toString()}

Hãy đóng vai trò một Cố vấn Tài chính Chuyên nghiệp, phân tích và đưa ra tư vấn theo cấu trúc 4 phần rõ ràng (sử dụng định dạng Markdown đẹp, dễ đọc):

### 1. Đánh giá Tổng quan & Dòng tiền
Nhận xét sâu sắc, thực tế về sức khỏe tài chính, dòng tiền ròng và tỷ lệ tiết kiệm tháng này (2-3 câu).

### 2. Nguyên nhân & Điểm nghẽn Chi tiêu
Chỉ rõ nguyên nhân cốt lõi khiến dòng tiền hoặc ngân sách bị ảnh hưởng (dựa vào danh mục chi tiêu, vấn đề phát hiện bên trên).

### 3. Khả năng Đạt Mục tiêu Tiết kiệm
Đánh giá mức độ khả thi của các mục tiêu tài chính hiện có. Đưa ra hướng xử lý thực tế (nếu thiếu hụt thì nên dời ngày hay cắt giảm chi tiêu).

### 4. Chiến lược Hành động Tháng tới
Nhấn mạnh và hướng dẫn người dùng thực hiện theo các con số định mức trong Kế hoạch Hành động đã được tính toán ở trên.

NGUYÊN TẮC QUAN TRỌNG:
- Bám sát CHÍNH XÁC các con số đã được tính toán ở trên, TUYỆT ĐỐI KHÔNG tự bịa ra số tiền hoặc tỷ lệ mới.
- Tuyệt đối KHÔNG tư vấn đầu tư chứng khoán, tiền mã hóa, bất động sản hay vay vốn.
- Trả lời bằng tiếng Việt, giọng văn ấm áp, cố vấn khách quan, chuyên nghiệp và có tính khích lệ cao.
''';
  }

  static String buildStructuredPlanPrompt({
    required FinancialInsightSummary summary,
    required MonthlyFinancialPlan draftPlan,
    AiRuntimeConfig? runtimeConfig,
  }) {
    final cfg = runtimeConfig ?? AiRuntimeConfig.defaults();
    final tier = draftPlan.dataTierUsed;

    final allocText = draftPlan.currentAllocations
        .map((a) =>
            '- ${a.categoryName} (${a.isEssential ? "Thiết yếu" : "Linh hoạt"}): Thực chi ${a.sourceMonthSpent.round()}đ -> Hạn mức kế hoạch ${a.recommendedLimit.round()}đ (${a.calculationBasis})')
        .join('\n');

    final tierConstraintNote = switch (tier) {
      DataSufficiencyTier.preliminary =>
        'CẤP ĐỘ DỮ LIỆU: SƠ BỘ (PRELIMINARY). BẮT BUỘC nêu rõ dữ liệu trong tháng còn ít, chỉ nhận xét sơ bộ cơ cấu hiện tại, TUYỆT ĐỐI KHÔNG kết luận xu hướng hay dự báo cuối tháng.',
      DataSufficiencyTier.currentMonthAnalysis =>
        'CẤP ĐỘ DỮ LIỆU: ĐỦ TRONG THÁNG (CURRENT_MONTH_ONLY). Chỉ phân tích trong tháng và lập kế hoạch tháng tới, TUYỆT ĐỐI KHÔNG so sánh tăng/giảm với tháng trước.',
      DataSufficiencyTier.monthOverMonthComparison =>
        'CẤP ĐỘ DỮ LIỆU: SO SÁNH 2 THÁNG (MOM_COMPARISON). Được phép so sánh với tháng liền trước, nhưng KHÔNG gọi là xu hướng nhiều tháng.',
      DataSufficiencyTier.multiMonthTrend =>
        'CẤP ĐỘ DỮ LIỆU: ĐỦ XU HƯỚNG ĐA THÁNG (MULTI_MONTH_TREND). Được phép phân tích xu hướng và thói quen qua nhiều tháng.',
      DataSufficiencyTier.empty => '',
    };

    final incomeConstraintNote =
        draftPlan.incomeMode == IncomeStabilityMode.noIncomeBasis
            ? 'LƯU Ý THU NHẬP: Chưa có dữ liệu thu nhập. Tuyệt đối không tự suy đoán thu nhập và không tính tỷ lệ tiết kiệm trên thu nhập.'
            : 'Thu nhập tham chiếu (${draftPlan.incomeMode.name}): ${draftPlan.referenceIncome.round()}đ.';

    final planAdvisoryRule = cfg.monthlyPlanAdvisoryRule.trim();
    final planAdvisorySlot = planAdvisoryRule.isNotEmpty
        ? '\nĐỊNH HƯỚNG TƯ VẤN KẾ HOẠCH THÁNG:\n- $planAdvisoryRule\n'
        : '';

    return '''
Bạn là Cố vấn Lập kế hoạch Tài chính Cá nhân AI.
Dưới đây là các chỉ số tài chính và KẾ HOẠCH THÁNG ${draftPlan.targetMonth} ĐÃ ĐƯỢC THUẬT TOÁN DART TÍNH TOÁN CHÍNH XÁC:
- Điểm sức khỏe tài chính: ${summary.healthScore}/100
- $tierConstraintNote
- $incomeConstraintNote
- Tổng hạn mức Chi phí Thiết yếu: ${draftPlan.essentialExpenseCap.round()}đ
- Tổng hạn mức Chi phí Linh hoạt: ${draftPlan.flexibleExpenseCap.round()}đ
- Mục tiêu tiết kiệm khả thi trong tháng: ${draftPlan.targetSavingAmount.round()}đ (Khả thi với mục tiêu gốc: ${draftPlan.isSavingGoalFeasible ? "CÓ" : "KHÔNG, thiếu ${draftPlan.infeasibleSavingGap.round()}đ/tháng"})
- Chi tiết phân bổ từng danh mục:
$allocText$planAdvisorySlot
Hãy trả về DUY NHẤT một chuỗi JSON hợp lệ (không bọc trong markdown ```json) theo đúng cấu trúc sau:
{
  "executiveSummary": "Đánh giá tổng quan 2-3 câu bám sát đúng số liệu và cấp độ dữ liệu ở trên.",
  "behavioralInsights": [
    "Nhận định hành vi chi tiêu số 1 có dẫn chứng số liệu thực tế",
    "Nhận định hành vi chi tiêu số 2 (hoặc giới hạn phân tích nếu dữ liệu sơ bộ)"
  ],
  "categoryActionTips": {
    "Tên danh mục": "1 hành động cụ thể, thực tế để giữ chi tiêu trong hạn mức kế hoạch"
  },
  "savingStrategyNote": "Chiến lược thực hiện mục tiêu tiết kiệm tháng này"
}
NGUYÊN TẮC BẮT BUỘC:
- Giữ nguyên 100% các con số từ dữ liệu đầu vào, không tự tạo số tiền mới.
- Không đề xuất cắt giảm các danh mục Thiết yếu.
''';
  }

  /// Parse và kiểm duyệt JSON trả về từ Gemini; trả về null nếu JSON sai cấu trúc.
  static AiStructuredPlanInsight? parseAndValidateStructuredInsight({
    required String rawText,
    required MonthlyFinancialPlan draftPlan,
  }) {
    try {
      String cleaned = rawText.trim();
      final firstBrace = cleaned.indexOf('{');
      final lastBrace = cleaned.lastIndexOf('}');
      if (firstBrace == -1 || lastBrace == -1 || lastBrace <= firstBrace) {
        return null;
      }
      cleaned = cleaned.substring(firstBrace, lastBrace + 1);
      final decoded = jsonDecode(cleaned);
      if (decoded is! Map) return null;

      final map = Map<String, dynamic>.from(decoded);
      final execSummary = (map['executiveSummary'] ?? '').toString().trim();
      if (execSummary.isEmpty) return null;

      final rawInsights = (map['behavioralInsights'] as List<dynamic>?) ?? [];
      final insights = rawInsights
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();

      final Map<String, String> tips = {};
      if (map['categoryActionTips'] is Map) {
        final rawTips = Map<String, dynamic>.from(map['categoryActionTips']);
        for (final entry in rawTips.entries) {
          final val = entry.value.toString().trim();
          if (val.isNotEmpty) {
            tips[entry.key.trim()] = val;
          }
        }
      }

      final savingNote = (map['savingStrategyNote'] ?? '').toString().trim();

      return AiStructuredPlanInsight(
        executiveSummary: execSummary,
        behavioralInsights:
            insights.isNotEmpty ? insights : draftPlan.behavioralInsights,
        categoryActionTips: tips,
        savingStrategyNote: savingNote.isNotEmpty
            ? savingNote
            : (draftPlan.targetSavingAmount > 0
                ? 'Ưu tiên trích trước ${draftPlan.targetSavingAmount.round()}đ vào mục tiêu tiết kiệm ngay khi nhận thu nhập.'
                : 'Cập nhật thu nhập để thiết lập mức trích tiết kiệm hàng tháng.'),
        isFromFallback: false,
      );
    } catch (_) {
      return null;
    }
  }

  /// Bản diễn giải định lượng dự phòng (Deterministic Fallback) khi mất mạng hoặc JSON lỗi.
  static AiStructuredPlanInsight buildDeterministicFallbackInsight(
    MonthlyFinancialPlan draftPlan,
  ) {
    final Map<String, String> tips = {};
    for (final a in draftPlan.currentAllocations) {
      tips[a.categoryName] = a.aiActionTip;
    }
    return AiStructuredPlanInsight(
      executiveSummary: draftPlan.aiExecutiveSummary,
      behavioralInsights: draftPlan.behavioralInsights,
      categoryActionTips: tips,
      savingStrategyNote: draftPlan.targetSavingAmount > 0
          ? 'Trích riêng khoản tiết kiệm mục tiêu ${draftPlan.targetSavingAmount.round()}đ/tháng và theo dõi hạn mức các danh mục linh hoạt.'
          : 'Hãy bổ sung thông tin thu nhập hoặc điều chỉnh cơ cấu chi phí thiết yếu để tạo thặng dư tiết kiệm.',
      isFromFallback: true,
    );
  }

  static String buildTransactionAnomalyPrompt({
    required String categoryName,
    required double currentAmount,
    required double expectedAmount,
    required double ratio,
    required int historySampleSize,
    AiRuntimeConfig? runtimeConfig,
  }) {
    final cfg = runtimeConfig ?? AiRuntimeConfig.defaults();
    final ratioFormatted = ratio.toStringAsFixed(1).replaceAll('.0', '');
    final anomalyRule = cfg.anomalyAdvisoryRule.trim();
    final anomalyAdvisorySlot = anomalyRule.isNotEmpty
        ? '\nĐịnh hướng giọng điệu tư vấn:\n- $anomalyRule\n'
        : '';

    return '''
Bạn là trợ lý tài chính cá nhân. Hệ thống đã phát hiện một khoản chi bất thường dựa trên thuật toán Dart xác định:
- Danh mục: $categoryName
- Số tiền chi giao dịch này: ${currentAmount.round()} VNĐ
- Mức chi trung vị thông thường (90 ngày qua, $historySampleSize mẫu): ${expectedAmount.round()} VNĐ
- Tỷ lệ chênh lệch: khoảng $ratioFormatted lần mức thông thường.
$anomalyAdvisorySlot
Hãy viết giải thích ngắn gọn bằng tiếng Việt, TỐI ĐA 2 CÂU:
1. Nhận xét về lý do vì sao hệ thống đưa ra cảnh báo này dựa trên số liệu.
2. Lời khuyên nhẹ nhàng để người dùng xem xét kiểm tra lại giao dịch (vẫn khẳng định người dùng có toàn quyền lưu nếu đây là khoản chi hợp lý).

LƯU Ý: Tuyệt đối không kết luận gian lận, không tư vấn đầu tư, không tự tính toán lại hoặc bịa đặt số liệu mới ngoài các con số trên.
''';
  }

  static String stripMarkdownCodeFence(String text) {
    final trimmed = text.trim();
    final fenceRegex = RegExp(r'^```(?:json)?\s*([\s\S]*?)\s*```$');
    final match = fenceRegex.firstMatch(trimmed);
    return match != null ? match.group(1)!.trim() : trimmed;
  }

  /// Xây dựng System Prompt hoàn chỉnh cho AI Chat & AI Sandbox, kết hợp:
  /// - Khối số liệu định lượng cố định từ Dart
  /// - Nguyên tắc DATA GROUNDING và STRICT DOMAIN SCOPE cố định (không thể bị ghi đè)
  /// - Khối chỉ dẫn phong cách từ AiRuntimeConfig (nếu có)
  /// - Tối đa 3 snippet từ FinancialKnowledgeArticle (mỗi snippet <= 300 ký tự)
  static String buildSystemCfpPromptForContext(
    String contextData, {
    required AiRuntimeConfig runtimeConfig,
    AiConfigSyncService? configSyncService,
    List<FinancialKnowledgeArticle>? overrideArticles,
    bool? isLowSavingRate,
    bool? isEssentialDeficit,
    bool? isVariableIncome,
    bool? hasBudgetOverrun,
    bool? isGoalInfeasible,
  }) {
    final lowerCtx = contextData.toLowerCase();

    final detectedLowSaving = isLowSavingRate ??
        (contextData.contains('Tỷ lệ tiết kiệm: 0%') ||
            lowerCtx.contains('tỷ lệ tiết kiệm thấp'));
    final detectedDeficit = isEssentialDeficit ??
        (contextData.contains('(THÂM HỤT)') ||
            lowerCtx.contains('chi vượt thu'));
    final detectedVariableIncome =
        isVariableIncome ?? lowerCtx.contains('variable');
    final detectedOverrun =
        hasBudgetOverrun ?? contextData.contains('VƯỢT NGÂN SÁCH');
    final detectedGoalInfeasible = isGoalInfeasible ??
        (lowerCtx.contains('không khả thi') || contextData.contains('còn thiếu'));

    final sync = configSyncService ?? AiConfigSyncService.instance;
    final knowledgeSnippets = sync.selectKnowledgeSnippetsForPrompt(
      isLowSavingRate: detectedLowSaving,
      isEssentialDeficit: detectedDeficit,
      isVariableIncome: detectedVariableIncome,
      hasBudgetOverrun: detectedOverrun,
      isGoalInfeasible: detectedGoalInfeasible,
      overrideArticles: overrideArticles,
    );

    final knowledgeBlock = knowledgeSnippets.isNotEmpty
        ? '''

CƠ SỞ TRI THỨC TÀI CHÍNH CHUẨN HÓA (Áp dụng tối đa 3 nguyên tắc phù hợp nhất bên dưới vào lời khuyên):
${knowledgeSnippets.join('\n')}
'''
        : '';

    final adminChatInstruction = runtimeConfig.chatSystemInstruction.trim();
    final adminInstructionBlock = adminChatInstruction.isNotEmpty
        ? '''

CHỈ DẪN PHONG CÁCH & TRỌNG TÂM TƯ VẤN (Chỉ áp dụng cho cách diễn đạt, TUYỆT ĐỐI KHÔNG ghi đè nguyên tắc 1 và 2):
$adminChatInstruction
'''
        : '';

    return '''
Bạn là Trợ lý AI Tài chính Cá nhân thông minh và tận tâm (đóng vai trò Cố vấn Tài chính Cá nhân - CFP AI), được tích hợp trong ứng dụng quản lý tài chính Flutter.

DƯỚI ĐÂY LÀ DỮ LIỆU TÀI CHÍNH THỰC TẾ CỦA CHÍNH NGƯỜI DÙNG HIỆN TẠI (ĐÃ ĐƯỢC HỆ THỐNG TÍNH TOÁN ĐỊNH LƯỢNG CHUẨN XÁC):
==================================================
$contextData
==================================================

CÁC NGUYÊN TẮC BẮT BUỘC KHI TRẢ LỜI:
1. NGUYÊN TẮC TRUNG THỰC & BÁM SÁT SỐ LIỆU (DATA GROUNDING):
   - Mọi số liệu (thu nhập, chi tiêu, dòng tiền ròng, tỷ lệ tiết kiệm, ngân sách, mục tiêu, trung bình 3 tháng) PHẢI LẤY CHÍNH XÁC từ dữ liệu trên.
   - TUYỆT ĐỐI KHÔNG tự bịa đặt, tự đoán mò, hoặc sinh ra các con số tài chính mới nằm ngoài dữ liệu được cung cấp.
   - Nếu trong dữ liệu ghi chú "DỮ LIỆU HẠN CHẾ" hoặc "CHƯA CÓ DỮ LIỆU", hãy trung thực thông báo cho người dùng biết dữ liệu ghi nhận còn ít, cần thêm giao dịch để AI đánh giá chuẩn xác hơn.

2. PHẠM VI NGHIÊM NGẶT (STRICT DOMAIN SCOPE):
   - CHỈ trả lời các câu hỏi liên quan đến tài chính cá nhân của người dùng (thu chi, ví, dòng tiền, ngân sách, tiết kiệm, mục tiêu tài chính, mẹo chi tiêu thông minh).
   - TỪ CHỐI LỊCH SỰ đối với các chủ đề ngoài phạm vi: thời sự, chính trị, viết code/lập trình, giải trí, thời tiết, tư vấn đầu tư mạo hiểm/cổ phiếu/tiền mã hóa rủi ro cao, luật pháp hoặc thuế chuyên sâu.
   - Câu từ chối mẫu: "Xin lỗi bạn, mình là Trợ lý AI Tài chính Cá nhân nên chỉ có thể hỗ trợ các vấn đề liên quan đến quản lý thu chi, ngân sách và kế hoạch tài chính của bạn nhé!"

3. ĐA CẤP ĐỘ PHẢN HỒI (MULTI-TIER RESPONSES):
   - Câu hỏi số liệu nhanh (VD: "Tháng này chi bao nhiêu?", "Ví còn bao nhiêu?"): Trả lời trực diện, ngắn gọn, chính xác trong 1-2 câu.
   - Câu hỏi phân tích (VD: "Tình hình tài chính thế nào?", "Dòng tiền tháng này ra sao?"): Trình bày rõ ràng cấu trúc Thu - Chi - Dòng tiền ròng - Tỷ lệ tiết kiệm, chỉ ra danh mục chi tiêu lớn nhất và so sánh với tháng trước.
   - Câu hỏi tư vấn cắt giảm (VD: "Làm sao để tiết kiệm?", "Tôi nên cắt giảm gì?"): Đưa ra đề xuất cụ thể gắn với danh mục chi nhiều nhất hoặc danh mục đang vượt hạn mức (chỉ rõ số tiền nên tiết kiệm và giải pháp thực tế).
   - Câu hỏi lập kế hoạch/mua sắm (VD: "Tôi muốn mua điện thoại/laptop X triệu trong Y tháng có được không?"): PHẢI ĐỐI CHIẾU với "Mức tiết kiệm trung bình 3 tháng gần nhất" và dòng tiền ròng. Nếu mục tiêu vượt quá khả năng thặng dư thực tế, PHẢI PHẢN BIỆN TÍNH KHẢ THI thẳng thắn và đề xuất phương án điều chỉnh (kéo dài thời gian hoặc danh mục cần cắt giảm).

4. GIỌNG VĂN & ĐỊNH DẠNG:
   - Sử dụng tiếng Việt chuẩn mực, xưng hô "mình" và "bạn", thân thiện, tôn trọng, mang tính đồng hành và khích lệ.
   - Trình bày dạng Markdown với gạch đầu dòng rõ ràng, in đậm các con số quan trọng (**số tiền**, **tỷ lệ %**) để người dùng dễ theo dõi trên màn hình di động.$knowledgeBlock$adminInstructionBlock
''';
  }
}

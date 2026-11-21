import 'dart:convert';
import '../models/ai_runtime_config_model.dart';
import '../models/category_model.dart';
import '../models/financial_forecast_result.dart';
import '../models/financial_issue.dart';
import '../models/monthly_financial_plan.dart';
import '../models/transaction_model.dart';
import '../l10n/app_localizations.dart';
import '../utils/category_localization_helper.dart';
import '../utils/formatters.dart';
import 'language_controller.dart';

/// ============================================================================
/// AI PROMPT BUILDER (PURE DART - ZERO API KEY / IO / ML KIT DEPENDENCY)
/// Tách biệt hoàn toàn phần xây dựng Prompt, Data Grounding, Knowledge Injection
/// và kiểm duyệt JSON khỏi `AiService` và `config/api_keys.dart`.
/// Có thể sử dụng an toàn trên cả Mobile App lẫn Admin Web AI Sandbox.
/// ============================================================================
class AiPromptBuilder {
  const AiPromptBuilder._();

  static final RegExp _unformattedCurrencyRegex = RegExp(
    r'(?<![\d.,])([1-9]\d{3,})(\s*(?:đồng|vnđ|vnd|đ|₫))(?=$|[\s.,;:!?()\[\]/"'
    "'"
    r'…\-])',
    caseSensitive: false,
  );

  /// Chuẩn hóa các số tiền nguyên >= 1000 bị thiếu dấu chấm phân cách hàng nghìn
  /// trong văn bản AI trả về (ví dụ `12000000đ` -> `12.000.000đ`, `1000000 VND` -> `1.000.000 VND`),
  /// không ảnh hưởng đến ngày tháng, tỷ lệ % hay số đã có dấu chấm/phẩy.
  static String formatCurrencyNumbersInText(String text) {
    if (text.isEmpty) return text;
    return text.replaceAllMapped(_unformattedCurrencyRegex, (match) {
      final digits = match.group(1)!;
      final unit = match.group(2)!;
      return '${AppFormatters.formatDigitsWithDots(digits)}$unit';
    });
  }

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
          name: LanguageController.isEnglish ? 'Other' : 'Khác',
          type: 'expense',
          icon: 'category',
          color: 0xFF9E9E9E,
        ),
      );
      final percent = totalSpent == 0 ? 0 : (amount / totalSpent * 100).round();
      final unit = LanguageController.isEnglish ? 'VND' : 'đồng';
      buffer.writeln(
          '- ${cat.name}: ${AppFormatters.number(amount)} $unit ($percent%)');
    });
    return buffer.toString();
  }

  static String buildSpendingHabitsPrompt({
    required List<AppTransaction> transactions,
    required List<Category> categories,
  }) {
    final summary = buildCategorySummary(transactions, categories);
    if (LanguageController.isEnglish) {
      return '''
You are a personal finance assistant. Based on the last 30 days of spending data below, analyze the user's spending habits and provide a concise, friendly insight with 1-2 actionable improvement tips. Respond in English in about 3-4 sentences.

Spending data by category:
$summary
''';
    }
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
    final spentFmt = AppFormatters.number(spentSoFar);
    final dailyFmt = AppFormatters.number(dailyAvg);
    final predictedFmt = AppFormatters.number(predicted);
    if (LanguageController.isEnglish) {
      return '''
The user has spent $spentFmt VND during the first $dayOfMonth days of the month (out of $totalDaysInMonth days). At an average daily spend of $dailyFmt VND/day, estimated month-end total spending will be around $predictedFmt VND. Write one short, friendly sentence in English commenting on this projection.
''';
    }
    return '''
Người dùng đã chi $spentFmt đồng trong $dayOfMonth ngày đầu tháng (tháng có
$totalDaysInMonth ngày). Với tốc độ chi tiêu trung bình $dailyFmt đồng/ngày, ước tính
tổng chi tiêu cuối tháng sẽ khoảng $predictedFmt đồng. Hãy viết một câu nhận xét ngắn
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

    final isEn = LanguageController.isEnglish;
    final contextBuffer = StringBuffer();
    if (monthlyIncome != null && monthlyIncome > 0) {
      final exp = monthlyExpense ?? 0.0;
      final net = monthlyIncome - exp;
      if (isEn) {
        contextBuffer.writeln(
            '- Reference monthly income: ${AppFormatters.number(monthlyIncome)} VND');
        contextBuffer.writeln(
            '- Current total monthly expense: ${AppFormatters.number(exp)} VND');
        contextBuffer.writeln(
            '- Net cash flow (Income - Expense): ${AppFormatters.number(net)} VND/month');
      } else {
        contextBuffer.writeln(
            '- Thu nhập tham chiếu hàng tháng: ${AppFormatters.number(monthlyIncome)} đồng');
        contextBuffer.writeln(
            '- Tổng chi tiêu hàng tháng hiện tại: ${AppFormatters.number(exp)} đồng');
        contextBuffer.writeln(
            '- Dòng tiền ròng (Thu - Chi): ${AppFormatters.number(net)} đồng/tháng');
      }
    } else if (monthlyExpense != null && monthlyExpense > 0) {
      contextBuffer.writeln(isEn
          ? '- No income data yet; current total spending: ${AppFormatters.number(monthlyExpense)} VND/month'
          : '- Chưa có dữ liệu thu nhập; tổng chi tiêu hiện tại: ${AppFormatters.number(monthlyExpense)} đồng/tháng');
    }
    if (flexibleCategorySummaries != null &&
        flexibleCategorySummaries.isNotEmpty) {
      contextBuffer.writeln(isEn
          ? '- Flexible spending categories to optimize: ${flexibleCategorySummaries.join(", ")}'
          : '- Các danh mục chi tiêu linh hoạt có thể tối ưu: ${flexibleCategorySummaries.join(", ")}');
    }

    final advisoryRule = cfg.savingGoalAdvisoryRule.trim();
    final advisorySlot = advisoryRule.isNotEmpty
        ? (isEn
            ? '\nAdditional advisory guidance:\n$advisoryRule\n'
            : '\nĐịnh hướng tư vấn bổ sung:\n$advisoryRule\n')
        : '';

    final targetFmt = AppFormatters.number(targetAmount);
    final savedFmt = AppFormatters.number(savedAmount);
    final remainingFmt = AppFormatters.number(remaining);
    final monthlyReqFmt = AppFormatters.number(monthlyRequired);
    final dailyReqFmt = AppFormatters.number(dailyRequired);

    if (isEn) {
      return '''
You are a Personal Finance Advisor. The user is planning a saving goal:
- Goal name: "$goalName"
- Target amount: $targetFmt VND (Saved: $savedFmt VND, Remaining: $remainingFmt VND)
- Remaining timeline: $safeMonths months
- Monthly saving needed: $monthlyReqFmt VND/month (~$dailyReqFmt VND/day)
${contextBuffer.isNotEmpty ? '\nUser actual financial context:\n$contextBuffer' : ''}$advisorySlot
Provide a concise, actionable plan in English with 3 bullet points:
1. Evaluate whether saving $monthlyReqFmt VND/month is feasible against current cash flow (if it exceeds net surplus, suggest how many months to extend).
2. Identify which flexible categories to trim and by how much per month (do not cut essential expenses).
3. One concrete action to start this week.
Keep dot thousand separators on currency amounts (e.g. 1.000.000 VND) and never fabricate numbers outside the provided data.
''';
    }

    return '''
Bạn là Cố vấn Tài chính Cá nhân. Người dùng đang lập kế hoạch cho mục tiêu tiết kiệm:
- Tên mục tiêu: "$goalName"
- Tổng số tiền mục tiêu: $targetFmt đồng (Đã tích lũy: $savedFmt đồng, Còn thiếu: $remainingFmt đồng)
- Thời hạn còn lại: $safeMonths tháng
- Mức cần tiết kiệm mỗi tháng: $monthlyReqFmt đồng/tháng (~$dailyReqFmt đồng/ngày)
${contextBuffer.isNotEmpty ? '\nNgữ cảnh tài chính thực tế của người dùng:\n$contextBuffer' : ''}$advisorySlot
Hãy đưa ra kế hoạch thực hiện ngắn gọn, cụ thể bằng tiếng Việt gồm 3 ý:
1. Đánh giá tính khả thi của mức tiết kiệm $monthlyReqFmt đồng/tháng so với dòng tiền hiện tại (nếu vượt quá khả năng dòng tiền ròng, hãy đề xuất rõ số tháng nên giãn thêm).
2. Chỉ rõ nên ưu tiên cắt giảm từ danh mục chi tiêu linh hoạt nào bao nhiêu tiền/tháng (không cắt giảm chi phí thiết yếu).
3. Một hành động cụ thể dễ thực hiện ngay trong tuần này.
Luôn giữ dấu chấm phân cách hàng nghìn cho số tiền (VD: 1.000.000 đồng) và tuyệt đối không tự bịa số liệu ngoài dữ liệu đã cung cấp.
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
      return AppLocalizations.tr(
        'svc_ai_month_label',
        params: {'month': '${month.month}', 'year': '${month.year}'},
      );
    });
    final isEn = LanguageController.isEnglish;
    final unit = isEn ? 'VND' : 'đồng';
    final dataLines = List.generate(
      amounts.length,
      (i) => '- ${monthLabels[i]}: ${AppFormatters.number(amounts[i])} $unit',
    );
    if (isEn) {
      return '''
You are a personal finance assistant. Based on the spending data over the last 6 months below, analyze the trend (increasing, decreasing, or stable) and provide a concise, friendly comment in English. If spending is trending upward, calculate the % change and suggest management tips. Data:
${dataLines.join('\n')}
''';
    }
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
    final curFmt = AppFormatters.number(currentDailyAvg);
    final targetFmt = AppFormatters.number(targetDailyAvg);
    final saveFmt = AppFormatters.number(monthlySavings);
    if (LanguageController.isEnglish) {
      return '''
The user currently spends an average of $curFmt VND/day on "$categoryName". Reducing this to $targetFmt VND/day would save about $saveFmt VND per month. Write a short, practical tip in English.
''';
    }
    return '''
Người dùng đang chi trung bình $curFmt đồng/ngày cho "$categoryName".
Nếu giảm xuống còn $targetFmt đồng/ngày, mỗi tháng sẽ tiết kiệm được khoảng
$saveFmt đồng. Viết một gợi ý ngắn gọn, thực tế bằng tiếng Việt.
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
    if (LanguageController.isEnglish) {
      return '''
You are a personal finance assistant. The system has already detected the following financial issues (from quantitative data, no need to recalculate):

$issuesText

For EACH issue, write briefly (1-2 sentences) in English:
1. Likely root cause
2. Concrete improvement action WITH SPECIFIC NUMBERS (e.g., "reduce to X VND/month")

Be friendly and go straight to each issue.
''';
    }
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
    if (LanguageController.isEnglish) {
      return '''
You are a personal finance assistant. The system detected this issue (pre-calculated from data, no need to recalculate):

${issue.title}: ${issue.description}

Write AT MOST 2-3 sentences in English: 1 sentence on likely cause, 1 sentence on concrete improvement WITH SPECIFIC NUMBERS. Be direct and skip greetings.
''';
    }
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
    if (LanguageController.isEnglish) {
      buffer.writeln(
          '=== FINANCIAL HEALTH SCORE: ${summary.healthScore}/100 (${summary.healthRating}) ===');

      if (summary.strengths.isNotEmpty) {
        buffer.writeln('Recorded Strengths:');
        for (final s in summary.strengths) {
          buffer.writeln('- $s');
        }
      }

      if (summary.deductions.isNotEmpty) {
        buffer.writeln('Areas to Improve (Deductions):');
        for (final d in summary.deductions) {
          buffer.writeln('- ${d.reason} (-${d.points} pts)');
        }
      }

      buffer.writeln('\n=== INCOME & CASH FLOW ANALYSIS ===');
      buffer.writeln(
          '- Monthly income: ${AppFormatters.number(summary.incomeAnalytics.currentMonthIncome)} VND');
      buffer.writeln(
          '- MoM income growth: ${(summary.incomeAnalytics.growthRate * 100).round()}% (Stability: ${summary.incomeAnalytics.stability})');
      if (summary.incomeAnalytics.sources.isNotEmpty) {
        final topSource = summary.incomeAnalytics.sources.first;
        buffer.writeln(
            '- Top income source: ${topSource.categoryName} (${AppFormatters.number(topSource.amount)} VND, ${(topSource.percentage * 100).round()}%)');
      }

      buffer.writeln(
          '- Total actual expense: ${AppFormatters.number(summary.cashFlowAnalytics.totalExpense)} VND');
      buffer.writeln(
          '- Net cash flow: ${AppFormatters.number(summary.cashFlowAnalytics.netCashFlow)} VND (${summary.cashFlowAnalytics.isPositive ? "POSITIVE" : "NEGATIVE"}, savings rate: ${summary.cashFlowAnalytics.savingsRate.round()}%)');
      buffer.writeln(
          '- Cash flow sustainability: ${summary.cashFlowAnalytics.sustainabilityStatus}');

      if (summary.monthEndForecast.hasEnoughData) {
        buffer.writeln(
            '- Projected month-end balance: ${AppFormatters.number(summary.monthEndForecast.projectedEndBalance)} VND');
      }

      if (summary.savingsGoalAssessment != null &&
          summary.savingsGoalAssessment!.goals.isNotEmpty) {
        buffer.writeln('\n=== SAVING GOAL ASSESSMENT ===');
        buffer.writeln(
            '- Total monthly saving required: ${AppFormatters.number(summary.savingsGoalAssessment!.totalMonthlyRequired)} VND');
        buffer.writeln(
            '- Available surplus: ${AppFormatters.number(summary.savingsGoalAssessment!.availableCashFlow)} VND');
        buffer.writeln(
            '- Goal budget gap: ${summary.savingsGoalAssessment!.gapAmount > 0 ? "Short ${AppFormatters.number(summary.savingsGoalAssessment!.gapAmount)} VND/month" : "Sufficient"}');
        for (final g in summary.savingsGoalAssessment!.goals) {
          buffer.writeln(
              '  * Goal "${g.goalName}": Needs ${AppFormatters.number(g.monthlyRequired)} VND/month (${(g.percentComplete * 100).round()}% done) - ${g.statusText}');
        }
      }

      if (summary.issues.isNotEmpty) {
        buffer.writeln('\n=== DETECTED FINANCIAL ISSUES ===');
        for (final i in summary.issues) {
          buffer.writeln(
              '- ${i.title} (Severity: ${i.severity == IssueSeverity.critical ? "Critical" : "Warning"})');
          buffer.writeln('  Root cause: ${i.effectiveRootCause}');
          buffer.writeln('  Impact: ${i.effectiveImpact}');
          buffer.writeln('  Recommendation: ${i.effectiveRecommendation}');
        }
      }

      if (summary.actionPlan.items.isNotEmpty) {
        buffer.writeln('\n=== RECOMMENDED ACTION PLAN ===');
        buffer.writeln(
            'Target: Save an additional ${AppFormatters.number(summary.actionPlan.totalProjectedSavings)} VND/month');
        for (final item in summary.actionPlan.items) {
          buffer.writeln(
              '- ${item.actionTitle}: Cut ${AppFormatters.number(item.targetReduction)} VND (Suggested cap: ${AppFormatters.number(item.suggestedBudget)} VND)');
        }
      }

      return '''
You are a Smart Personal Finance Advisor (AI Financial Advisor).
Below is the VERIFIED FINANCIAL METRICS REPORT DETERMINISTICALLY COMPUTED from the user's real data:

${buffer.toString()}

Act as a Professional Financial Advisor, analyze and present your advice in 4 clear Markdown sections:

### 1. Overview & Cash Flow Assessment
Provide a grounded, practical assessment of this month's financial health, net cash flow, and savings rate (2-3 sentences).

### 2. Root Causes & Spending Bottlenecks
Pinpoint what is impacting cash flow or budgets based on the spending categories and detected issues above.

### 3. Saving Goal Feasibility
Assess whether the existing saving goals are achievable. Give practical next steps (extending the timeline or cutting back if short).

### 4. Next Month Action Strategy
Reinforce and guide the user to follow the exact budget targets in the Action Plan calculated above.

IMPORTANT RULES:
- Stick STRICTLY to the calculated figures above and keep their dot thousand-separator format (e.g., 1.000.000 VND); NEVER invent new amounts or percentages.
- NEVER recommend stocks, crypto, real estate investing, or borrowing.
- Respond in warm, objective, encouraging, professional English.
''';
    }

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
        '- Tổng thu nhập tháng: ${AppFormatters.number(summary.incomeAnalytics.currentMonthIncome)}đ');
    buffer.writeln(
        '- Tăng trưởng thu so tháng trước: ${(summary.incomeAnalytics.growthRate * 100).round()}% (Độ ổn định: ${summary.incomeAnalytics.stability})');
    if (summary.incomeAnalytics.sources.isNotEmpty) {
      final topSource = summary.incomeAnalytics.sources.first;
      buffer.writeln(
          '- Nguồn thu lớn nhất: ${topSource.categoryName} (${AppFormatters.number(topSource.amount)}đ, ${(topSource.percentage * 100).round()}%)');
    }

    buffer.writeln(
        '- Tổng chi tiêu thực tế: ${AppFormatters.number(summary.cashFlowAnalytics.totalExpense)}đ');
    buffer.writeln(
        '- Dòng tiền ròng (Số tiền còn lại): ${AppFormatters.number(summary.cashFlowAnalytics.netCashFlow)}đ (${summary.cashFlowAnalytics.isPositive ? "DƯƠNG" : "ÂM"}, tỷ lệ tiết kiệm: ${summary.cashFlowAnalytics.savingsRate.round()}%)');
    buffer.writeln(
        '- Trạng thái duy trì dòng tiền: ${summary.cashFlowAnalytics.sustainabilityStatus}');

    if (summary.monthEndForecast.hasEnoughData) {
      buffer.writeln(
          '- Số dư dự kiến cuối tháng: ${AppFormatters.number(summary.monthEndForecast.projectedEndBalance)}đ');
    }

    if (summary.savingsGoalAssessment != null &&
        summary.savingsGoalAssessment!.goals.isNotEmpty) {
      buffer.writeln('\n=== ĐÁNH GIÁ MỤC TIÊU TIẾT KIỆM ===');
      buffer.writeln(
          '- Tổng tiền cần tích lũy/tháng: ${AppFormatters.number(summary.savingsGoalAssessment!.totalMonthlyRequired)}đ');
      buffer.writeln(
          '- Thặng dư khả dụng: ${AppFormatters.number(summary.savingsGoalAssessment!.availableCashFlow)}đ');
      buffer.writeln(
          '- Chênh lệch ngân sách mục tiêu: ${summary.savingsGoalAssessment!.gapAmount > 0 ? "Thiếu ${AppFormatters.number(summary.savingsGoalAssessment!.gapAmount)}đ/tháng" : "Đủ ngân sách"}');
      for (final g in summary.savingsGoalAssessment!.goals) {
        buffer.writeln(
            '  * Mục tiêu "${g.goalName}": Cần ${AppFormatters.number(g.monthlyRequired)}đ/tháng (${(g.percentComplete * 100).round()}% hoàn thành) - ${g.statusText}');
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
          'Mục tiêu: Tiết kiệm thêm ${AppFormatters.number(summary.actionPlan.totalProjectedSavings)}đ/tháng');
      for (final item in summary.actionPlan.items) {
        buffer.writeln(
            '- ${item.actionTitle}: Giảm ${AppFormatters.number(item.targetReduction)}đ (Hạn mức trần: ${AppFormatters.number(item.suggestedBudget)}đ)');
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
- Bám sát CHÍNH XÁC các con số và giữ nguyên dấu chấm phân cách hàng nghìn (VD: 1.000.000đ, 12.000.000đ) từ dữ liệu ở trên, TUYỆT ĐỐI KHÔNG tự bịa ra số tiền hoặc tỷ lệ mới.
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

    final isEn = LanguageController.isEnglish;
    final sourceMonth = draftPlan.sourceMonth.trim().isNotEmpty
        ? draftPlan.sourceMonth.trim()
        : draftPlan.targetMonth.trim();
    final targetMonth = draftPlan.targetMonth.trim();
    final isSequentialNextMonth = sourceMonth != targetMonth;

    final actualIncome = summary.cashFlowAnalytics.totalIncome;
    final actualExpense = summary.cashFlowAnalytics.totalExpense;
    final netCashFlow = summary.cashFlowAnalytics.netCashFlow;
    final refIncome = draftPlan.referenceIncome;
    final hasIncomeBasis =
        draftPlan.incomeMode != IncomeStabilityMode.noIncomeBasis &&
            refIncome > 0;
    final hasSavingGoals = summary.savingsGoalAssessment != null &&
        summary.savingsGoalAssessment!.goals.isNotEmpty;

    final allocText = draftPlan.currentAllocations.isEmpty
        ? (isEn
            ? '- No expense categories recorded in $sourceMonth.'
            : '- Chưa có danh mục chi tiêu nào được ghi nhận trong tháng $sourceMonth.')
        : draftPlan.currentAllocations
            .map((a) => isEn
                ? '- ${a.categoryName} (${a.isEssential ? "Essential" : "Flexible"}): Actual spent in $sourceMonth = ${AppFormatters.number(a.sourceMonthSpent)} VND -> Planned limit for $targetMonth = ${AppFormatters.number(a.recommendedLimit)} VND (${a.calculationBasis})'
                : '- ${a.categoryName} (${a.isEssential ? "Thiết yếu" : "Linh hoạt"}): Thực chi tháng $sourceMonth ${AppFormatters.number(a.sourceMonthSpent)}đ -> Hạn mức kế hoạch tháng $targetMonth ${AppFormatters.number(a.recommendedLimit)}đ (${a.calculationBasis})')
            .join('\n');

    final noExpenseNote = actualExpense == 0
        ? (isEn
            ? ' Note: $sourceMonth currently has 0 recorded expense transactions; state clearly that spending has not been recorded yet rather than assuming it is the start of the month.'
            : ' Lưu ý: Tháng $sourceMonth hiện chưa có giao dịch chi tiêu nào phát sinh (tổng chi 0đ), hãy nêu rõ là chưa ghi nhận khoản chi tiêu thay vì tự suy đoán là "đầu tháng".')
        : '';

    final tierConstraintNote = isEn
        ? switch (tier) {
            DataSufficiencyTier.preliminary =>
              'DATA TIER: PRELIMINARY. MUST state data is limited in $sourceMonth; only comment on current structure and NEVER extrapolate trends or month-end forecasts.$noExpenseNote',
            DataSufficiencyTier.currentMonthAnalysis =>
              'DATA TIER: CURRENT_MONTH_ONLY. Analyze within $sourceMonth and plan for $targetMonth; NEVER compare increases/decreases against prior months.',
            DataSufficiencyTier.monthOverMonthComparison =>
              'DATA TIER: MOM_COMPARISON. May compare $sourceMonth against the prior month, but DO NOT call it a multi-month trend.',
            DataSufficiencyTier.multiMonthTrend =>
              'DATA TIER: MULTI_MONTH_TREND. Full multi-month spending trend analysis leading into $sourceMonth is permitted.',
            DataSufficiencyTier.empty => '',
          }
        : switch (tier) {
            DataSufficiencyTier.preliminary =>
              'CẤP ĐỘ DỮ LIỆU: SƠ BỘ (PRELIMINARY). BẮT BUỘC nêu rõ dữ liệu tháng $sourceMonth còn ít, chỉ nhận xét sơ bộ cơ cấu hiện tại, TUYỆT ĐỐI KHÔNG kết luận xu hướng hay dự báo cuối tháng.$noExpenseNote',
            DataSufficiencyTier.currentMonthAnalysis =>
              'CẤP ĐỘ DỮ LIỆU: ĐỦ TRONG THÁNG (CURRENT_MONTH_ONLY). Chỉ phân tích trong tháng $sourceMonth và lập kế hoạch cho tháng $targetMonth, TUYỆT ĐỐI KHÔNG so sánh tăng/giảm với tháng trước.',
            DataSufficiencyTier.monthOverMonthComparison =>
              'CẤP ĐỘ DỮ LIỆU: SO SÁNH 2 THÁNG (MOM_COMPARISON). Được phép so sánh tháng $sourceMonth với tháng liền trước, nhưng KHÔNG gọi là xu hướng nhiều tháng.',
            DataSufficiencyTier.multiMonthTrend =>
              'CẤP ĐỘ DỮ LIỆU: ĐỦ XU HƯỚNG ĐA THÁNG (MULTI_MONTH_TREND). Được phép phân tích xu hướng và thói quen qua nhiều tháng tính đến tháng $sourceMonth.',
            DataSufficiencyTier.empty => '',
          };

    final incomeModeDesc = isEn
        ? switch (draftPlan.incomeMode) {
            IncomeStabilityMode.declared => 'user-declared expected monthly income',
            IncomeStabilityMode.stable => 'stable historical income',
            IncomeStabilityMode.variable =>
              'conservative baseline from variable income',
            IncomeStabilityMode.singleMonth => 'single-month income reference',
            IncomeStabilityMode.noIncomeBasis => 'no income data',
          }
        : switch (draftPlan.incomeMode) {
            IncomeStabilityMode.declared =>
              'thu nhập dự kiến do người dùng khai báo',
            IncomeStabilityMode.stable => 'thu nhập lịch sử ổn định',
            IncomeStabilityMode.variable =>
              'mức thận trọng từ thu nhập biến động',
            IncomeStabilityMode.singleMonth => 'tham chiếu từ 1 tháng thu nhập',
            IncomeStabilityMode.noIncomeBasis => 'chưa có dữ liệu thu nhập',
          };

    final incomeDiffClarification =
        hasIncomeBasis && (refIncome - actualIncome).abs() >= 1000
            ? (isEn
                ? ' (Differs from actual recorded income of ${AppFormatters.number(actualIncome)} VND in $sourceMonth because planning uses $incomeModeDesc; clarify this distinction in the summary.)'
                : ' (Khác với tổng thu thực tế tháng $sourceMonth là ${AppFormatters.number(actualIncome)}đ vì kế hoạch lấy theo $incomeModeDesc để ổn định ngân sách; hãy giải thích rõ sự khác biệt này.)')
            : '';

    final incomeConstraintNote = isEn
        ? (!hasIncomeBasis
            ? 'INCOME NOTE: No income data yet. NEVER infer income or compute savings rate over income.'
            : 'Reference income for planning $targetMonth ($incomeModeDesc): ${AppFormatters.number(refIncome)} VND.$incomeDiffClarification')
        : (!hasIncomeBasis
            ? 'LƯU Ý THU NHẬP: Chưa có dữ liệu thu nhập. Tuyệt đối không tự suy đoán thu nhập và không tính tỷ lệ tiết kiệm trên thu nhập.'
            : 'Thu nhập tham chiếu dùng lập kế hoạch tháng $targetMonth ($incomeModeDesc): ${AppFormatters.number(refIncome)}đ.$incomeDiffClarification');

    final emptyAllocNote = draftPlan.currentAllocations.isEmpty && hasIncomeBasis
        ? (isEn
            ? ' (Note: Essential and Flexible caps are 0 VND only because no expense categories or budgets are recorded yet; ${AppFormatters.number((refIncome - draftPlan.targetSavingAmount).clamp(0.0, double.infinity))} VND remains unallocated for future expenses.)'
            : ' (Lưu ý: Hạn mức Thiết yếu và Linh hoạt hiện là 0đ do chưa có danh mục chi tiêu hay ngân sách nào được ghi nhận; phần thu nhập tham chiếu còn lại chưa phân bổ là ${AppFormatters.number((refIncome - draftPlan.targetSavingAmount).clamp(0.0, double.infinity))}đ.)')
        : '';

    final savingTargetContext = (!hasSavingGoals && draftPlan.targetSavingAmount > 0)
        ? (isEn
            ? 'default recommended saving target as no specific saving goal has been created yet'
            : 'mức tiết kiệm khuyến nghị mặc định vì người dùng chưa tạo mục tiêu tiết kiệm cụ thể')
        : (isEn
            ? 'Original goal feasible: ${draftPlan.isSavingGoalFeasible ? "YES" : "NO, short ${AppFormatters.number(draftPlan.infeasibleSavingGap)} VND/month"}'
            : 'Khả thi với mục tiêu gốc: ${draftPlan.isSavingGoalFeasible ? "CÓ" : "KHÔNG, thiếu ${AppFormatters.number(draftPlan.infeasibleSavingGap)}đ/tháng"}');

    final planAdvisoryRule = cfg.monthlyPlanAdvisoryRule.trim();
    final planAdvisorySlot = planAdvisoryRule.isNotEmpty
        ? (isEn
            ? '\nMONTHLY PLAN ADVISORY GUIDANCE:\n- $planAdvisoryRule\n'
            : '\nĐỊNH HƯỚNG TƯ VẤN KẾ HOẠCH THÁNG:\n- $planAdvisoryRule\n')
        : '';

    if (isEn) {
      final headerEn = isSequentialNextMonth
          ? '''1) CURRENT MONTH FINANCIAL STATUS ($sourceMonth - analysis baseline):
- Analysis month (current): $sourceMonth
- Financial health score for $sourceMonth: ${summary.healthScore}/100 (${summary.healthRating})
- Recorded actual income in $sourceMonth: ${AppFormatters.number(actualIncome)} VND
- Recorded actual spending in $sourceMonth: ${AppFormatters.number(actualExpense)} VND
- Net cash flow in $sourceMonth: ${AppFormatters.number(netCashFlow)} VND
- $tierConstraintNote
- $incomeConstraintNote

2) PROPOSED FINANCIAL PLAN FOR NEXT MONTH ($targetMonth, built from $sourceMonth data):'''
          : '''1) FINANCIAL STATUS & MONTHLY PLAN FOR $targetMonth:
- Financial health score for $sourceMonth: ${summary.healthScore}/100 (${summary.healthRating})
- Recorded actual income in $sourceMonth: ${AppFormatters.number(actualIncome)} VND
- Recorded actual spending in $sourceMonth: ${AppFormatters.number(actualExpense)} VND
- Net cash flow in $sourceMonth: ${AppFormatters.number(netCashFlow)} VND
- $tierConstraintNote
- $incomeConstraintNote''';

      final timeframeRuleEn = isSequentialNextMonth
          ? '- TIMEFRAME ACCURACY (CRITICAL): The health score (${summary.healthScore}/100), recorded income/expense, and behavioral spending metrics belong strictly to the CURRENT month ($sourceMonth). The planned budget caps and saving target belong to the NEXT month ($targetMonth). NEVER attribute $sourceMonth\'s health score or actual spending to $targetMonth.'
          : '- Refer accurately to month $targetMonth for all metrics and budget caps.';

      return '''
You are an AI Personal Financial Planning Advisor.
Below are the verified deterministic metrics computed by the Dart engine:

$headerEn
- Total Essential Expense Cap ($targetMonth): ${AppFormatters.number(draftPlan.essentialExpenseCap)} VND$emptyAllocNote
- Total Flexible Expense Cap ($targetMonth): ${AppFormatters.number(draftPlan.flexibleExpenseCap)} VND
- Feasible saving target ($targetMonth): ${AppFormatters.number(draftPlan.targetSavingAmount)} VND ($savingTargetContext)
- Category allocations:
$allocText$planAdvisorySlot
Return ONLY ONE valid JSON object (do not wrap in markdown ```json fences) in English matching this exact schema and consistent prose style:
{
  "executiveSummary": "Plain 2-sentence prose paragraph (NO newlines, NO bullets, NO markdown). Sentence 1: State $sourceMonth health score (${summary.healthScore}/100 (${summary.healthRating})), actual income (${AppFormatters.number(actualIncome)} VND), actual spending (${AppFormatters.number(actualExpense)} VND), net cash flow (${AppFormatters.number(netCashFlow)} VND), and the data-sufficiency scope. Sentence 2: Transition cleanly to $targetMonth ('For $targetMonth, the budget plan is based on ...'), stating reference income (${AppFormatters.number(refIncome)} VND and why it differs from $sourceMonth actuals if applicable), essential cap, flexible cap, and feasible saving target.",
  "behavioralInsights": [
    "Plain prose sentence (NO leading bullet or emoji): Assess total $sourceMonth spending against income and data scope.",
    "Plain prose sentence (NO leading bullet or emoji): Break down concrete spending across Essential and Flexible categories (naming key categories and exact amounts if spent > 0)."
  ],
  "categoryActionTips": {
    "Category Name": "1 concrete, practical action in English to stay within the planned limit in $targetMonth"
  },
  "savingStrategyNote": "1 concrete, natural action sentence (NO leading 🎯 emoji) explaining how to allocate the $targetMonth saving target upon receiving income."
}
MANDATORY RULES:
$timeframeRuleEn
- Always adhere strictly to the 2-sentence summary + 2 behavioral insights + 1 saving strategy note structure above regardless of which Gemini model responds.
- Always format currency amounts with dot thousand separators (e.g., 1.000.000 VND); keep 100% of numbers exact from the input data and never invent new amounts.
- Never suggest cutting Essential categories.
''';
    }

    final headerVi = isSequentialNextMonth
        ? '''1) HIỆN TRẠNG TÀI CHÍNH THÁNG HIỆN TẠI ($sourceMonth - cơ sở đánh giá):
- Tháng đang phân tích (hiện tại): $sourceMonth
- Điểm sức khỏe tài chính tháng $sourceMonth: ${summary.healthScore}/100 (${summary.healthRating})
- Tổng thu thực tế đã ghi nhận tháng $sourceMonth: ${AppFormatters.number(actualIncome)}đ
- Tổng chi thực tế đã ghi nhận tháng $sourceMonth: ${AppFormatters.number(actualExpense)}đ
- Dòng tiền ròng tháng $sourceMonth: ${AppFormatters.number(netCashFlow)}đ
- $tierConstraintNote
- $incomeConstraintNote

2) KẾ HOẠCH NGÂN SÁCH DỰ KIẾN CHO THÁNG TIẾP THEO ($targetMonth - lập từ dữ liệu tháng $sourceMonth):'''
        : '''1) HIỆN TRẠNG TÀI CHÍNH & KẾ HOẠCH THÁNG $targetMonth:
- Điểm sức khỏe tài chính tháng $sourceMonth: ${summary.healthScore}/100 (${summary.healthRating})
- Tổng thu thực tế tháng $sourceMonth: ${AppFormatters.number(actualIncome)}đ
- Tổng chi thực tế tháng $sourceMonth: ${AppFormatters.number(actualExpense)}đ
- Dòng tiền ròng tháng $sourceMonth: ${AppFormatters.number(netCashFlow)}đ
- $tierConstraintNote
- $incomeConstraintNote''';

    final timeframeRuleVi = isSequentialNextMonth
        ? '- PHÂN BIỆT CHÍNH XÁC MỐC THỜI GIAN (BẮT BUỘC): Điểm sức khỏe tài chính (${summary.healthScore}/100), thu chi thực tế và hành vi chi tiêu thuộc về THÁNG HIỆN TẠI ($sourceMonth). Còn các "Hạn mức kế hoạch" và "Mục tiêu tiết kiệm dự kiến" là định hướng áp dụng cho THÁNG TIẾP THEO ($targetMonth). Tuyệt đối KHÔNG gọi điểm sức khỏe tài chính hay thực chi của tháng $sourceMonth là của tháng $targetMonth.'
        : '- Ghi rõ đúng tháng $targetMonth cho các số liệu và hạn mức trong kế hoạch.';

    return '''
Bạn là Cố vấn Lập kế hoạch Tài chính Cá nhân AI.
Dưới đây là các chỉ số tài chính ĐÃ ĐƯỢC THUẬT TOÁN DART TÍNH TOÁN CHÍNH XÁC:

$headerVi
- Tổng hạn mức Chi phí Thiết yếu ($targetMonth): ${AppFormatters.number(draftPlan.essentialExpenseCap)}đ$emptyAllocNote
- Tổng hạn mức Chi phí Linh hoạt ($targetMonth): ${AppFormatters.number(draftPlan.flexibleExpenseCap)}đ
- Mục tiêu tiết kiệm khả thi ($targetMonth): ${AppFormatters.number(draftPlan.targetSavingAmount)}đ ($savingTargetContext)
- Chi tiết phân bổ từng danh mục:
$allocText$planAdvisorySlot
Hãy trả về DUY NHẤT một chuỗi JSON hợp lệ (không bọc trong markdown ```json) tuân thủ CHẶT CHẼ đúng bố cục và văn phong cố vấn chuyên nghiệp sau:
{
  "executiveSummary": "Đoạn văn xuôi ĐÚNG 2 CÂU liền mạch (không xuống dòng, không gạch đầu dòng, không markdown). Câu 1: Nêu sức khỏe tài chính tháng $sourceMonth đạt ${summary.healthScore}/100 (${summary.healthRating}) với tổng thu thực tế ${AppFormatters.number(actualIncome)}đ, tổng chi thực tế ${AppFormatters.number(actualExpense)}đ, dòng tiền ròng ${AppFormatters.number(netCashFlow)}đ và nêu rõ giới hạn theo cấp độ dữ liệu. Câu 2: Chuyển tiếp sang kế hoạch tháng $targetMonth (bắt đầu tự nhiên như 'Sang tháng $targetMonth, kế hoạch ngân sách được thiết lập dựa trên ...'), nêu thu nhập tham chiếu ${AppFormatters.number(refIncome)}đ (giải thích ngắn nếu khác thực thu tháng $sourceMonth), hạn mức thiết yếu ${AppFormatters.number(draftPlan.essentialExpenseCap)}đ, linh hoạt ${AppFormatters.number(draftPlan.flexibleExpenseCap)}đ và mục tiêu tiết kiệm khả thi ${AppFormatters.number(draftPlan.targetSavingAmount)}đ.",
  "behavioralInsights": [
    "Ý 1 (văn xuôi thuần, không tiền tố bullet/emoji): Nhận xét tổng chi thực tế tháng $sourceMonth (${AppFormatters.number(actualExpense)}đ) so với thu nhập và mức độ dữ liệu.",
    "Ý 2 (văn xuôi thuần, không tiền tố bullet/emoji): Phân tích hành vi chi tiêu theo nhóm Thiết yếu và Linh hoạt, nêu rõ tên các danh mục cụ thể kèm số tiền thực chi nếu có."
  ],
  "categoryActionTips": {
    "Tên danh mục": "1 hành động cụ thể, thực tế để giữ chi tiêu tháng $targetMonth trong hạn mức kế hoạch"
  },
  "savingStrategyNote": "ĐÚNG 1 câu hành động thực tế (không thêm emoji 🎯 hay bullet) hướng dẫn phân bổ ngay khoản tiết kiệm khi nhận thu nhập trong tháng $targetMonth."
}
NGUYÊN TẮC BẮT BUỘC:
$timeframeRuleVi
- Giữ cố định 100% bố cục 2 câu tổng quan + 2 nhận định hành vi + 1 câu chiến lược tiết kiệm như mẫu cấu trúc trên dù dùng model Gemini nào.
- Luôn định dạng số tiền có dấu chấm phân cách hàng nghìn gắn liền 'đ' (ví dụ: 1.000.000đ, 12.000.000đ); giữ nguyên 100% các con số từ dữ liệu đầu vào, không tự tạo số tiền mới.
- Không đề xuất cắt giảm các danh mục Thiết yếu.
''';
  }

  static String _sanitizeAdvisorParagraph(String raw) {
    return raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _stripLeadingBulletOrTarget(String raw) {
    return raw
        .trim()
        .replaceFirst(
          RegExp(r'^[\s•\-\*\u2022\u25CF\u{1F3AF}]+', unicode: true),
          '',
        )
        .trim();
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
      final execSummary = formatCurrencyNumbersInText(
        _sanitizeAdvisorParagraph((map['executiveSummary'] ?? '').toString()),
      );
      if (execSummary.isEmpty) return null;

      final rawInsights = (map['behavioralInsights'] as List<dynamic>?) ?? [];
      final insights = rawInsights
          .map((e) => formatCurrencyNumbersInText(
              _stripLeadingBulletOrTarget(e.toString())))
          .where((s) => s.isNotEmpty)
          .toList();

      final Map<String, String> tips = {};
      if (map['categoryActionTips'] is Map) {
        final rawTips = Map<String, dynamic>.from(map['categoryActionTips']);
        for (final entry in rawTips.entries) {
          final val =
              formatCurrencyNumbersInText(entry.value.toString().trim());
          if (val.isNotEmpty) {
            tips[entry.key.trim()] = val;
          }
        }
      }

      final savingNote = formatCurrencyNumbersInText(
        _stripLeadingBulletOrTarget(
            (map['savingStrategyNote'] ?? '').toString()),
      );

      final isEn = LanguageController.isEnglish;
      final fallbackInsights = _buildConsistentBehavioralInsights(
        draftPlan: draftPlan,
        summary: null,
        isEn: isEn,
      );

      return AiStructuredPlanInsight(
        executiveSummary: execSummary,
        behavioralInsights: insights.isNotEmpty ? insights : fallbackInsights,
        categoryActionTips: tips,
        savingStrategyNote: savingNote.isNotEmpty
            ? savingNote
            : _buildConsistentSavingStrategy(draftPlan, isEn: isEn),
        isFromFallback: false,
      );
    } catch (_) {
      return null;
    }
  }

  static String _formatAdvisorAmount(double amount, bool isEn) {
    return isEn
        ? '${AppFormatters.number(amount)} VND'
        : '${AppFormatters.number(amount)}đ';
  }

  static String _incomeModeLabel(IncomeStabilityMode mode, bool isEn) {
    if (isEn) {
      return switch (mode) {
        IncomeStabilityMode.declared => 'expected income',
        IncomeStabilityMode.stable => 'stable historical income',
        IncomeStabilityMode.variable => 'conservative variable-income baseline',
        IncomeStabilityMode.singleMonth => 'single-month reference income',
        IncomeStabilityMode.noIncomeBasis => 'no income baseline',
      };
    }
    return switch (mode) {
      IncomeStabilityMode.declared => 'thu nhập dự kiến',
      IncomeStabilityMode.stable => 'thu nhập lịch sử ổn định',
      IncomeStabilityMode.variable => 'mức thu nhập thận trọng',
      IncomeStabilityMode.singleMonth => 'thu nhập tham chiếu',
      IncomeStabilityMode.noIncomeBasis => 'chưa có dữ liệu thu nhập',
    };
  }

  static String _formatCategoryBreakdownList(
    List<PlannedCategoryAllocation> items,
    bool isEn,
  ) {
    final sorted = [...items]
      ..sort((a, b) => b.sourceMonthSpent.compareTo(a.sourceMonthSpent));
    final top = sorted.take(2).toList();
    if (top.length == 1) {
      final name = CategoryLocalizationHelper.localizeName(top.first.categoryName);
      final amt = _formatAdvisorAmount(top.first.sourceMonthSpent, isEn);
      return isEn ? '$name at $amt' : '$name là $amt';
    }
    final formatted = top
        .map((a) =>
            '${CategoryLocalizationHelper.localizeName(a.categoryName)} (${_formatAdvisorAmount(a.sourceMonthSpent, isEn)})')
        .join(', ');
    return formatted;
  }

  static List<String> _buildConsistentBehavioralInsights({
    required MonthlyFinancialPlan draftPlan,
    required FinancialInsightSummary? summary,
    required bool isEn,
  }) {
    final sourceMonth = draftPlan.sourceMonth.trim().isNotEmpty
        ? draftPlan.sourceMonth.trim()
        : draftPlan.targetMonth.trim();
    final actualExpense = summary != null
        ? summary.cashFlowAnalytics.totalExpense
        : draftPlan.currentAllocations
            .fold<double>(0.0, (sum, a) => sum + a.sourceMonthSpent);
    final actualIncome = summary?.cashFlowAnalytics.totalIncome ?? 0.0;
    final isPrelim = draftPlan.dataTierUsed == DataSufficiencyTier.preliminary;

    final String bullet1;
    if (actualExpense <= 0) {
      bullet1 = isEn
          ? 'In $sourceMonth, no spending transactions have been recorded yet, so the assessment reflects current inflows while leaving budget room open.'
          : 'Trong tháng $sourceMonth, chưa có khoản chi tiêu nào được ghi nhận nên hệ thống chỉ phản ánh dòng thu hiện tại và giữ nguyên dư địa theo dõi.';
    } else if (summary != null && actualIncome > 0) {
      final ratioPct = (actualExpense / actualIncome) * 100;
      if (isEn) {
        final level = ratioPct <= 35
            ? 'currently very low relative to income'
            : ratioPct <= 75
                ? 'well balanced against income'
                : ratioPct <= 100
                    ? 'approaching total recorded income'
                    : 'exceeding actual recorded income';
        final dataPrefix = isPrelim ? 'with limited data available, ' : '';
        bullet1 =
            'In $sourceMonth, ${dataPrefix}actual spending totals ${_formatAdvisorAmount(actualExpense, true)}, showing a spending structure $level.';
      } else {
        final level = ratioPct <= 35
            ? 'đang ở mức rất thấp so với thu nhập'
            : ratioPct <= 75
                ? 'đang ở mức cân đối so với thu nhập'
                : ratioPct <= 100
                    ? 'đang tiệm cận ngưỡng thu nhập thực tế'
                    : 'đang vượt mức thu nhập thực tế';
        final dataPrefix = isPrelim ? 'dữ liệu còn ít với ' : '';
        bullet1 =
            'Trong tháng $sourceMonth, ${dataPrefix}tổng chi thực tế ghi nhận là ${_formatAdvisorAmount(actualExpense, false)}, cho thấy cơ cấu chi tiêu hiện tại $level.';
      }
    } else {
      bullet1 = isEn
          ? 'In $sourceMonth, recorded actual spending is ${_formatAdvisorAmount(actualExpense, true)} across active categories.'
          : 'Trong tháng $sourceMonth, tổng chi thực tế ghi nhận là ${_formatAdvisorAmount(actualExpense, false)} qua các danh mục đã phát sinh.';
    }

    final essentialSpent = draftPlan.currentAllocations
        .where((a) => a.isEssential && a.sourceMonthSpent > 0)
        .toList();
    final flexibleSpent = draftPlan.currentAllocations
        .where((a) => !a.isEssential && a.sourceMonthSpent > 0)
        .toList();

    final String bullet2;
    if (essentialSpent.isNotEmpty && flexibleSpent.isNotEmpty) {
      final essDesc = _formatCategoryBreakdownList(essentialSpent, isEn);
      final flexDesc = _formatCategoryBreakdownList(flexibleSpent, isEn);
      final isOverIncome =
          summary != null && actualIncome > 0 && actualExpense > actualIncome;
      if (isEn) {
        final tone = isOverIncome
            ? 'highlights concentrated spending pressure as'
            : 'reflects disciplined spending control with';
        bullet2 =
            'Spending behavior in $sourceMonth $tone Essential costs for $essDesc and Flexible spending on $flexDesc.';
      } else {
        final tone = isOverIncome
            ? 'cho thấy áp lực chi tiêu tập trung khi'
            : 'phản ánh sự kiểm soát chặt chẽ khi';
        bullet2 =
            'Hành vi chi tiêu tháng $sourceMonth $tone chi phí thiết yếu cho $essDesc và chi phí linh hoạt cho $flexDesc.';
      }
    } else if (essentialSpent.isNotEmpty) {
      final essDesc = _formatCategoryBreakdownList(essentialSpent, isEn);
      bullet2 = isEn
          ? 'Spending in $sourceMonth concentrated on Essential categories ($essDesc), with no Flexible expenses recorded yet.'
          : 'Hành vi chi tiêu tháng $sourceMonth tập trung hoàn toàn ở nhóm thiết yếu ($essDesc) và chưa ghi nhận chi phí linh hoạt.';
    } else if (flexibleSpent.isNotEmpty) {
      final flexDesc = _formatCategoryBreakdownList(flexibleSpent, isEn);
      bullet2 = isEn
          ? 'Spending in $sourceMonth occurred primarily in Flexible categories ($flexDesc), with no Essential expenses recorded yet.'
          : 'Hành vi chi tiêu tháng $sourceMonth chủ yếu phát sinh ở nhóm linh hoạt ($flexDesc) và chưa ghi nhận chi phí thiết yếu.';
    } else {
      bullet2 = isEn
          ? 'No expense categories have been recorded in $sourceMonth yet; continued tracking will build a more accurate baseline.'
          : 'Do chưa có danh mục chi tiêu nào được ghi nhận trong tháng $sourceMonth, việc tiếp tục theo dõi giao dịch sẽ giúp hoàn thiện bức tranh ngân sách.';
    }

    return [bullet1, bullet2];
  }

  static String _buildConsistentSavingStrategy(
    MonthlyFinancialPlan draftPlan, {
    required bool isEn,
  }) {
    final targetMonth = draftPlan.targetMonth.trim();
    final refIncome = draftPlan.referenceIncome;
    final hasIncomeBasis =
        draftPlan.incomeMode != IncomeStabilityMode.noIncomeBasis &&
            refIncome > 0;
    final saveTarget = draftPlan.targetSavingAmount;

    if (!hasIncomeBasis) {
      return isEn
          ? 'Update your expected monthly income or record an income transaction so the planner can set a feasible saving target for $targetMonth.'
          : 'Cập nhật mức thu nhập dự kiến hoặc ghi nhận giao dịch thu nhập thực tế để hệ thống tính toán mục tiêu tiết kiệm khả thi cho tháng $targetMonth.';
    }
    if (draftPlan.isEssentialDeficit || saveTarget <= 0) {
      return isEn
          ? 'Prioritize reviewing essential and flexible spending in $targetMonth to restore a positive surplus before allocating to savings.'
          : 'Ưu tiên rà soát lại các khoản chi thiết yếu và linh hoạt trong tháng $targetMonth để khôi phục thặng dư trước khi phân bổ quỹ tiết kiệm.';
    }

    final incomeLabel = _incomeModeLabel(draftPlan.incomeMode, isEn);
    final saveAmt = _formatAdvisorAmount(saveTarget, isEn);
    final incAmt = _formatAdvisorAmount(refIncome, isEn);

    if (!draftPlan.isSavingGoalFeasible && draftPlan.infeasibleSavingGap > 0) {
      final gapAmt = _formatAdvisorAmount(draftPlan.infeasibleSavingGap, isEn);
      return isEn
          ? 'Allocate $saveAmt to your savings fund as soon as you receive your $incomeLabel of $incAmt in $targetMonth, and consider extending your goal timeline or trimming flexible expenses to close the $gapAmt/month gap.'
          : 'Thực hiện phân bổ ngay $saveAmt vào quỹ tiết kiệm ngay khi nhận được $incomeLabel $incAmt trong tháng $targetMonth, đồng thời cân nhắc nới thời hạn mục tiêu hoặc giảm chi linh hoạt để bù khoản thiếu $gapAmt/tháng.';
    }

    return isEn
        ? 'Allocate $saveAmt into your savings fund immediately upon receiving your $incomeLabel of $incAmt in $targetMonth to stay on track for your feasible saving target.'
        : 'Thực hiện phân bổ ngay $saveAmt vào quỹ tiết kiệm ngay khi nhận được $incomeLabel $incAmt trong tháng $targetMonth để đảm bảo hoàn thành mục tiêu tiết kiệm khả thi.';
  }

  /// Bản diễn giải định lượng dự phòng (Deterministic Fallback) khi mất mạng hoặc JSON lỗi,
  /// đồng bộ hoàn toàn cấu trúc & văn phong chuẩn cố vấn (2 câu tổng quan + 2 nhận định hành vi + 1 chiến lược).
  static AiStructuredPlanInsight buildDeterministicFallbackInsight(
    MonthlyFinancialPlan draftPlan, {
    FinancialInsightSummary? summary,
  }) {
    final isEn = LanguageController.isEnglish;
    final sourceMonth = draftPlan.sourceMonth.trim().isNotEmpty
        ? draftPlan.sourceMonth.trim()
        : draftPlan.targetMonth.trim();
    final targetMonth = draftPlan.targetMonth.trim();
    final isSequentialNextMonth = sourceMonth != targetMonth;
    final refIncome = draftPlan.referenceIncome;
    final hasIncomeBasis =
        draftPlan.incomeMode != IncomeStabilityMode.noIncomeBasis &&
            refIncome > 0;
    final essCap = draftPlan.essentialExpenseCap;
    final flexCap = draftPlan.flexibleExpenseCap;
    final saveTarget = draftPlan.targetSavingAmount;

    final StringBuffer execBuffer = StringBuffer();
    if (summary != null) {
      final actualIncome = summary.cashFlowAnalytics.totalIncome;
      final actualExpense = summary.cashFlowAnalytics.totalExpense;
      final netCashFlow = summary.cashFlowAnalytics.netCashFlow;

      final tierSuffix = switch (draftPlan.dataTierUsed) {
        DataSufficiencyTier.preliminary => isEn
            ? '; this is PRELIMINARY data, so it only evaluates current structure without concluding month-end trends'
            : '; đây là dữ liệu SƠ BỘ nên chỉ đánh giá cơ cấu hiện tại và tuyệt đối chưa kết luận xu hướng cuối tháng',
        DataSufficiencyTier.currentMonthAnalysis => isEn
            ? '; current-month data is sufficient for internal budget analysis'
            : '; dữ liệu đủ để phân tích cơ cấu thu chi nội bộ trong tháng $sourceMonth',
        DataSufficiencyTier.monthOverMonthComparison => isEn
            ? '; historical data supports month-over-month comparison'
            : '; dữ liệu đủ cơ sở đối chiếu biến động với tháng liền trước',
        DataSufficiencyTier.multiMonthTrend => isEn
            ? '; multi-month history provides reliable trend visibility'
            : '; dữ liệu đa tháng đủ độ tin cậy để đánh giá xu hướng dài hạn',
        DataSufficiencyTier.empty => '',
      };

      if (isEn) {
        execBuffer.write(
          'Financial health in $sourceMonth reached ${summary.healthScore}/100 (${summary.healthRating}) '
          'with actual income ${_formatAdvisorAmount(actualIncome, true)}, '
          'actual spending ${_formatAdvisorAmount(actualExpense, true)}, '
          'and net cash flow ${_formatAdvisorAmount(netCashFlow, true)}$tierSuffix. ',
        );
      } else {
        execBuffer.write(
          'Sức khỏe tài chính tháng $sourceMonth đạt ${summary.healthScore}/100 (${summary.healthRating}) '
          'với tổng thu thực tế ${_formatAdvisorAmount(actualIncome, false)}, '
          'tổng chi thực tế ${_formatAdvisorAmount(actualExpense, false)} '
          'và dòng tiền ròng ${_formatAdvisorAmount(netCashFlow, false)}$tierSuffix. ',
        );
      }
    }

    final diffClarification = (summary != null &&
            hasIncomeBasis &&
            (refIncome - summary.cashFlowAnalytics.totalIncome).abs() >= 1000)
        ? (isEn
            ? ' (differing from actual $sourceMonth income to keep the budget stable)'
            : ' (khác biệt với thu thực tế tháng $sourceMonth để đảm bảo tính ổn định)')
        : '';

    final incomeLabel = _incomeModeLabel(draftPlan.incomeMode, isEn);

    if (!hasIncomeBasis) {
      execBuffer.write(isEn
          ? 'For $targetMonth, without a reference income baseline yet, the plan tentatively records an essential cap of ${_formatAdvisorAmount(essCap, true)}, flexible cap of ${_formatAdvisorAmount(flexCap, true)}, and a 0 VND saving target.'
          : '${isSequentialNextMonth ? "Sang" : "Trong"} tháng $targetMonth, do chưa có cơ sở thu nhập tham chiếu nên kế hoạch tạm ghi nhận hạn mức thiết yếu ${_formatAdvisorAmount(essCap, false)}, linh hoạt ${_formatAdvisorAmount(flexCap, false)} và mục tiêu tiết kiệm 0đ.');
    } else if (draftPlan.isEssentialDeficit) {
      execBuffer.write(isEn
          ? 'For $targetMonth, based on $incomeLabel of ${_formatAdvisorAmount(refIncome, true)}$diffClarification, essential spending (${_formatAdvisorAmount(essCap, true)}) exceeds income so flexible spending and saving targets are paused at 0 VND.'
          : '${isSequentialNextMonth ? "Sang" : "Trong"} tháng $targetMonth, dựa trên $incomeLabel ${_formatAdvisorAmount(refIncome, false)}$diffClarification, chi phí thiết yếu (${_formatAdvisorAmount(essCap, false)}) đang vượt khả năng cân đối nên hạn mức linh hoạt và mục tiêu tiết kiệm tạm đưa về 0đ.');
    } else {
      execBuffer.write(isEn
          ? '${isSequentialNextMonth ? "For $targetMonth, the budget plan is established" : "The $targetMonth budget plan is established"} based on $incomeLabel of ${_formatAdvisorAmount(refIncome, true)}$diffClarification, setting an essential cap of ${_formatAdvisorAmount(essCap, true)}, flexible cap of ${_formatAdvisorAmount(flexCap, true)}, and feasible saving target of ${_formatAdvisorAmount(saveTarget, true)}.'
          : '${isSequentialNextMonth ? "Sang tháng $targetMonth, kế hoạch ngân sách được thiết lập" : "Kế hoạch ngân sách tháng $targetMonth được thiết lập"} dựa trên $incomeLabel ${_formatAdvisorAmount(refIncome, false)}$diffClarification, gồm hạn mức thiết yếu ${_formatAdvisorAmount(essCap, false)}, linh hoạt ${_formatAdvisorAmount(flexCap, false)} và mục tiêu tiết kiệm khả thi ${_formatAdvisorAmount(saveTarget, false)}.');
    }

    final Map<String, String> tips = {};
    for (final a in draftPlan.currentAllocations) {
      tips[a.categoryName] = formatCurrencyNumbersInText(a.aiActionTip);
    }

    return AiStructuredPlanInsight(
      executiveSummary:
          formatCurrencyNumbersInText(execBuffer.toString().trim()),
      behavioralInsights: _buildConsistentBehavioralInsights(
        draftPlan: draftPlan,
        summary: summary,
        isEn: isEn,
      ),
      categoryActionTips: tips,
      savingStrategyNote:
          _buildConsistentSavingStrategy(draftPlan, isEn: isEn),
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
    final isEn = LanguageController.isEnglish;
    final anomalyAdvisorySlot = anomalyRule.isNotEmpty
        ? (isEn
            ? '\nAdvisory tone guidance:\n- $anomalyRule\n'
            : '\nĐịnh hướng giọng điệu tư vấn:\n- $anomalyRule\n')
        : '';

    final currentFmt = AppFormatters.number(currentAmount);
    final expectedFmt = AppFormatters.number(expectedAmount);

    if (isEn) {
      return '''
You are a personal finance assistant. The system detected an unusual expense based on quantitative analysis:
- Category: $categoryName
- Transaction amount: $currentFmt VND
- Usual median spending (last 90 days, $historySampleSize samples): $expectedFmt VND
- Ratio: about ${ratioFormatted}x your normal spending.
$anomalyAdvisorySlot
Write a brief explanation in English, AT MOST 2 SENTENCES:
1. Note why this alert appeared based on the numbers.
2. Gently suggest reviewing the transaction (confirming the user can freely save it if it is a valid expense).

NOTE: Never claim fraud, never give investment advice, keep dot thousand separators (e.g. 1.000.000 VND), and never recalculate or invent figures outside those above.
''';
    }

    return '''
Bạn là trợ lý tài chính cá nhân. Hệ thống đã phát hiện một khoản chi bất thường dựa trên thuật toán Dart xác định:
- Danh mục: $categoryName
- Số tiền chi giao dịch này: $currentFmt VNĐ
- Mức chi trung vị thông thường (90 ngày qua, $historySampleSize mẫu): $expectedFmt VNĐ
- Tỷ lệ chênh lệch: khoảng $ratioFormatted lần mức thông thường.
$anomalyAdvisorySlot
Hãy viết giải thích ngắn gọn bằng tiếng Việt, TỐI ĐA 2 CÂU:
1. Nhận xét về lý do vì sao hệ thống đưa ra cảnh báo này dựa trên số liệu.
2. Lời khuyên nhẹ nhàng để người dùng xem xét kiểm tra lại giao dịch (vẫn khẳng định người dùng có toàn quyền lưu nếu đây là khoản chi hợp lý).

LƯU Ý: Tuyệt đối không kết luận gian lận, không tư vấn đầu tư, giữ nguyên dấu chấm phân cách hàng nghìn cho số tiền (VD: 1.000.000 VNĐ), không tự tính toán lại hoặc bịa đặt số liệu mới ngoài các con số trên.
''';
  }

  static String stripMarkdownCodeFence(String text) {
    final trimmed = text.trim();
    final fenceRegex = RegExp(r'^```(?:json)?\s*([\s\S]*?)\s*```$');
    final match = fenceRegex.firstMatch(trimmed);
    return match != null ? match.group(1)!.trim() : trimmed;
  }

  /// Xây dựng System Prompt hoàn chỉnh cho AI Chat, kết hợp:
  /// - Khối số liệu định lượng cố định từ Dart
  /// - Nguyên tắc DATA GROUNDING và STRICT DOMAIN SCOPE cố định (không thể bị ghi đè)
  /// - Khối chỉ dẫn phong cách từ AiRuntimeConfig (nếu có)
  /// - Tối đa 3 snippet từ FinancialKnowledgeArticle (mỗi snippet <= 300 ký tự)
  static String buildSystemCfpPromptForContext(
    String contextData, {
    required AiRuntimeConfig runtimeConfig,
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
            contextData.contains('Savings rate: 0%') ||
            lowerCtx.contains('tỷ lệ tiết kiệm thấp') ||
            lowerCtx.contains('low savings rate'));
    final detectedDeficit = isEssentialDeficit ??
        (contextData.contains('(THÂM HỤT)') ||
            contextData.contains('(DEFICIT)') ||
            lowerCtx.contains('chi vượt thu') ||
            lowerCtx.contains('spending exceeds income'));
    final detectedVariableIncome = isVariableIncome ??
        (lowerCtx.contains('variable') ||
            lowerCtx.contains('biến động') ||
            lowerCtx.contains('không ổn định') ||
            lowerCtx.contains('volatile'));
    final detectedOverrun = hasBudgetOverrun ??
        (contextData.contains('VƯỢT NGÂN SÁCH') ||
            contextData.contains('OVER BUDGET'));
    final detectedGoalInfeasible = isGoalInfeasible ??
        (lowerCtx.contains('không khả thi') ||
            lowerCtx.contains('infeasible') ||
            contextData.contains('còn thiếu') ||
            contextData.contains('short '));

    final knowledgeSnippets = FinancialKnowledgeArticle.selectSnippetsForPrompt(
      isLowSavingRate: detectedLowSaving,
      isEssentialDeficit: detectedDeficit,
      isVariableIncome: detectedVariableIncome,
      hasBudgetOverrun: detectedOverrun,
      isGoalInfeasible: detectedGoalInfeasible,
      overrideArticles: overrideArticles,
    );

    final isEn = LanguageController.isEnglish;
    final knowledgeBlock = knowledgeSnippets.isNotEmpty
        ? (isEn
            ? '''

STANDARDIZED FINANCIAL KNOWLEDGE BASE (Apply at most the 3 most relevant principles below to your advice):
${knowledgeSnippets.join('\n')}
'''
            : '''

CƠ SỞ TRI THỨC TÀI CHÍNH CHUẨN HÓA (Áp dụng tối đa 3 nguyên tắc phù hợp nhất bên dưới vào lời khuyên):
${knowledgeSnippets.join('\n')}
''')
        : '';

    final adminChatInstruction = runtimeConfig.chatSystemInstruction.trim();
    final adminInstructionBlock = adminChatInstruction.isNotEmpty
        ? (isEn
            ? '''

STYLE & ADVISORY FOCUS DIRECTIVES (Apply to tone only; NEVER override principles 1 and 2):
$adminChatInstruction
'''
            : '''

CHỈ DẪN PHONG CÁCH & TRỌNG TÂM TƯ VẤN (Chỉ áp dụng cho cách diễn đạt, TUYỆT ĐỐI KHÔNG ghi đè nguyên tắc 1 và 2):
$adminChatInstruction
''')
        : '';

    if (isEn) {
      return '''
You are a smart, empathetic Personal Finance AI Assistant (acting as a Personal Financial Advisor - CFP AI), built into a personal finance Flutter application.

BELOW IS THE USER'S ACTUAL FINANCIAL DATA (QUANTITATIVELY COMPUTED BY THE SYSTEM):
==================================================
$contextData
==================================================

MANDATORY RESPONSE PRINCIPLES:
1. TRUTHFULNESS & DATA GROUNDING:
   - All numbers (income, expenses, net cash flow, savings rate, budgets, goals, 3-month average) MUST COME EXACTLY from the data above.
   - NEVER fabricate, guess, or invent financial figures outside the provided data.
   - If the data indicates "LIMITED DATA" or "NO TRANSACTIONS YET", honestly inform the user that recorded data is limited and more transactions are needed for deeper accuracy.

2. STRICT DOMAIN SCOPE:
   - ONLY answer questions related to the user's personal finance (income/expense, wallets, cash flow, budgets, savings, financial goals, smart spending tips).
   - POLITELY DECLINE out-of-scope topics: news, politics, coding, entertainment, weather, risky investments/stocks/crypto, legal or deep tax advice.
   - Sample refusal: "Sorry, I am your Personal Finance AI Assistant, so I can only help with managing your income, expenses, budgets, and financial plans!"

3. MULTI-TIER RESPONSES:
   - Quick figure questions (e.g., "How much did I spend this month?", "What is my balance?"): Answer directly and concisely in 1-2 sentences.
   - Analysis questions (e.g., "How are my finances doing?", "How is my cash flow?"): Clearly present Income - Expense - Net Cash Flow - Savings Rate, top spending category, and comparison with last month.
   - Optimization questions (e.g., "How can I save?", "What should I cut?"): Give specific suggestions tied to top or over-budget categories with exact saving targets.
   - Goal/Purchase feasibility (e.g., "Can I save X in Y months?"): MUST CHECK against the 3-month average savings and net cash flow. If infeasible, candidly challenge feasibility and suggest extending months or trimming specific flexible categories.

4. TONE & FORMATTING:
   - Respond in natural, warm, respectful, encouraging English.
   - Format with clean Markdown bullets and bold key figures (**amounts**, **percentages**) for mobile readability.$knowledgeBlock$adminInstructionBlock
''';
    }

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

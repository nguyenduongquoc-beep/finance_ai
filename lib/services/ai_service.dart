import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart' show getTemporaryDirectory;
import 'dart:typed_data';
import 'dart:convert';
import '../models/receipt_info.dart';
import '../models/financial_issue.dart';
import '../models/trend_result.dart';
import '../models/transaction_model.dart';
import '../models/category_model.dart';
import '../models/financial_forecast_result.dart';
import '../config/api_keys.dart';

/// ============================================================
/// AI SERVICE
/// Gọi Gemini API để phân tích chi tiêu, dự đoán, chatbot tài chính
///
/// LƯU Ý BẢO MẬT:
/// Gọi trực tiếp Gemini từ client (như hiện tại) sẽ lộ API key trong app.
/// Khi lên bản chính thức, nên chuyển sang gọi qua Cloud Functions
/// (proxy) để giấu API key, tương tự kiến trúc dùng cho các dự án AI khác.
/// Tạm thời dùng trực tiếp để thuận tiện phát triển & demo khóa luận.
/// ============================================================
class AiService {
  // Danh sách model dự phòng, thử lần lượt nếu model chính bị lỗi 404/not found
  static const List<String> _modelFallbackChain = [
    'gemini-3.5-flash', // model chính, đã xác nhận hoạt động qua Bước 1
    'gemini-3.5-flash-lite', // dự phòng 1
    'gemini-3.6-flash', // dự phòng 2
    'gemini-flash-latest', // dự phòng 3
  ];

  final List<Content> _chatHistory = [];

  AiService() {
    debugPrint('🔧 Model fallback chain: $_modelFallbackChain');
    if (geminiApiKey.isEmpty || geminiApiKey == 'YOUR_GEMINI_API_KEY_HERE') {
      throw Exception(
          'Gemini API key chưa được cấu hình trong config/api_keys.dart');
    }
  }

  /// Nhận diện lỗi do MẤT MẠNG (khác với lỗi riêng của 1 model AI).
  /// Khi gặp lỗi loại này, thử tiếp các model dự phòng khác là vô nghĩa
  /// (vì tất cả đều cần mạng để gọi API) — nên phải dừng ngay, không lãng
  /// phí thời gian chờ của người dùng.
  bool _isNetworkError(Object e) {
    if (e is SocketException) return true;
    final msg = e.toString().toLowerCase();
    return msg.contains('failed host lookup') ||
        msg.contains('no address associated') ||
        msg.contains('network is unreachable') ||
        msg.contains('connection refused') ||
        msg.contains('connection reset') ||
        msg.contains('software caused connection abort');
  }

  /// Kiểm tra 1 exception có phải là lỗi "mất mạng" do _generateWithFallback
  /// ném ra hay không — dùng ở tầng UI để hiển thị đúng thông báo.
  static bool isNoNetworkException(Object e) {
    return e.toString().contains('NO_NETWORK');
  }

  // Hàm helper gọi generateContent có tự động thử model dự phòng khi gặp lỗi "not found"
  Future<GenerateContentResponse> _generateWithFallback(
      List<Content> content) async {
    Exception? lastError;
    for (final modelName in _modelFallbackChain) {
      try {
        debugPrint('🚀 Đang gọi Gemini với model: $modelName');
        final model = GenerativeModel(model: modelName, apiKey: geminiApiKey);
        final response = await model
            .generateContent(content)
            .timeout(const Duration(seconds: 15));
        return response;
      } catch (e) {
        if (_isNetworkError(e)) {
          debugPrint(
              '⚠️ Phát hiện lỗi mất mạng khi gọi model "$modelName" — dừng ngay, không thử model dự phòng khác: $e');
          throw Exception('NO_NETWORK');
        }
        lastError = e is Exception ? e : Exception(e.toString());
        debugPrint(
            '⚠️ Model "$modelName" thất bại: $e — thử model dự phòng tiếp theo...');
        continue;
      }
    }
    throw lastError ?? Exception('Tất cả model AI đều không khả dụng');
  }

  /// AI 1: Phân tích thói quen chi tiêu (30 ngày gần đây)
  Future<String> analyzeSpendingHabits({
    required List<AppTransaction> transactions,
    required List<Category> categories,
  }) async {
    final summary = _buildCategorySummary(transactions, categories);
    final prompt = '''
Bạn là trợ lý tài chính cá nhân. Dựa trên dữ liệu chi tiêu 30 ngày gần đây sau đây, hãy
phân tích thói quen chi tiêu của người dùng và đưa ra nhận xét ngắn gọn, thân thiện,
kèm 1-2 gợi ý cải thiện cụ thể. Trả lời bằng tiếng Việt, khoảng 3-4 câu.

Dữ liệu chi tiêu theo danh mục:
$summary
''';
    final response = await _generateWithFallback([Content.text(prompt)]);
    return response.text ?? 'Không thể phân tích dữ liệu lúc này.';
  }

  /// AI 3: Dự đoán số tiền chi tiêu cuối tháng
  Future<String> predictMonthEnd({
    required double spentSoFar,
    required int dayOfMonth,
    required int totalDaysInMonth,
  }) async {
    final dailyAvg = spentSoFar / dayOfMonth;
    final predicted = dailyAvg * totalDaysInMonth;
    final prompt = '''
Người dùng đã chi $spentSoFar đồng trong $dayOfMonth ngày đầu tháng (tháng có
$totalDaysInMonth ngày). Với tốc độ chi tiêu trung bình $dailyAvg đồng/ngày, ước tính
tổng chi tiêu cuối tháng sẽ khoảng $predicted đồng. Hãy viết một câu nhận xét ngắn
gọn bằng tiếng Việt cho người dùng về dự đoán này.
''';
    final response = await _generateWithFallback([Content.text(prompt)]);
    return response.text ??
        'Theo tốc độ hiện tại, dự kiến chi tiêu cuối tháng khoảng ${predicted.round()} đồng.';
  }

  /// AI 4: Lập kế hoạch tiết kiệm
  Future<String> generateSavingPlan({
    required String goalName,
    required double targetAmount,
    required int months,
  }) async {
    final monthlyRequired = targetAmount / months;
    final dailyRequired = monthlyRequired / 30;
    final prompt = '''
Người dùng muốn tiết kiệm để mua "$goalName" với số tiền $targetAmount đồng trong
$months tháng. Số tiền cần tiết kiệm là khoảng $monthlyRequired đồng/tháng, tương
đương $dailyRequired đồng/ngày. Hãy viết lời khuyên ngắn gọn, khích lệ bằng tiếng Việt.
''';
    final response = await _generateWithFallback([Content.text(prompt)]);
    return response.text ??
        'Bạn cần tiết kiệm khoảng ${monthlyRequired.round()} đồng/tháng để đạt mục tiêu.';
  }

  /// AI 5: Chatbot tài chính - Trợ lý AI tài chính cá nhân dựa trên dữ liệu định lượng
  Future<String> chatWithFinancialData({
    required String userQuestion,
    required String contextData, // Dữ liệu tài chính định lượng tổng hợp từ Firestore
  }) async {
    _syncSystemPromptAndHistory(contextData, userQuestion);
    try {
      final response = await _generateWithFallback(_chatHistory);
      if (response.text != null) {
        _chatHistory.add(Content.model([TextPart(response.text!)]));
      }
      return response.text ?? 'Xin lỗi, mình chưa thể trả lời câu hỏi này.';
    } catch (e) {
      // Remove last user question to allow retrying
      if (_chatHistory.isNotEmpty) {
        _chatHistory.removeLast();
      }
      rethrow;
    }
  }

  /// AI 5 (Stream): Trợ lý AI tài chính cá nhân phản hồi dạng dòng (Stream) giảm độ trễ hiển thị
  Stream<String> chatWithFinancialDataStream({
    required String userQuestion,
    required String contextData,
  }) async* {
    _syncSystemPromptAndHistory(contextData, userQuestion);

    final accumulatedText = StringBuffer();
    bool streamSucceeded = false;
    Exception? lastError;

    for (final modelName in _modelFallbackChain) {
      try {
        debugPrint('🚀 Đang gọi Gemini Stream với model: $modelName');
        final model = GenerativeModel(model: modelName, apiKey: geminiApiKey);
        final stream = model
            .generateContentStream(_chatHistory)
            .timeout(const Duration(seconds: 25));

        await for (final chunk in stream) {
          final text = chunk.text;
          if (text != null && text.isNotEmpty) {
            accumulatedText.write(text);
            yield text;
          }
        }
        streamSucceeded = true;
        break;
      } catch (e) {
        if (_isNetworkError(e)) {
          debugPrint('⚠️ Phát hiện lỗi mất mạng khi gọi stream model "$modelName": $e');
          throw Exception('NO_NETWORK');
        }
        lastError = e is Exception ? e : Exception(e.toString());
        debugPrint('⚠️ Model Stream "$modelName" thất bại: $e — thử fallback tiếp theo...');
        accumulatedText.clear();
      }
    }

    // Nếu toàn bộ stream fallback thất bại, thử gọi fallback chuẩn (non-streaming)
    if (!streamSucceeded) {
      try {
        debugPrint('⚠️ Chuyển sang fallback non-streaming cho câu trả lời');
        final response = await _generateWithFallback(_chatHistory);
        final fullText = response.text ?? 'Xin lỗi, mình chưa thể trả lời câu hỏi này.';
        accumulatedText.write(fullText);
        yield fullText;
        streamSucceeded = true;
      } catch (fallbackError) {
        if (_chatHistory.isNotEmpty) {
          _chatHistory.removeLast();
        }
        throw lastError ?? fallbackError;
      }
    }

    if (streamSucceeded && accumulatedText.isNotEmpty) {
      _chatHistory.add(Content.model([TextPart(accumulatedText.toString())]));
    }
  }

  /// Đồng bộ System Prompt định lượng mới nhất và duy trì Sliding Window lịch sử (tối đa 10 tin gần nhất)
  void _syncSystemPromptAndHistory(String contextData, String userQuestion) {
    if (_chatHistory.isEmpty) {
      _chatHistory.add(Content.text(_buildSystemCfpPrompt(contextData)));
    } else {
      // Cập nhật System Prompt với ngữ cảnh tài chính mới nhất
      _chatHistory[0] = Content.text(_buildSystemCfpPrompt(contextData));
    }
    _chatHistory.add(Content.text(userQuestion));

    // Duy trì sliding window: Giữ index 0 (System Prompt) và tối đa 10 tin nhắn gần nhất
    if (_chatHistory.length > 11) {
      _chatHistory.removeRange(1, _chatHistory.length - 10);
    }
  }

  /// AI 2: Phân tích xu hướng tài chính (6 tháng gần nhất)
  Future<TrendResult> analyzeTrend({
    required List<double> monthlySpending, // oldest -> newest (6 months)
  }) async {
    // Ensure we have exactly 6 values, pad with zeros if needed
    final List<double> amounts = List<double>.from(monthlySpending);
    while (amounts.length < 6) {
      amounts.insert(0, 0);
    }
    // Compute overall percent change
    double? percentChange;
    if (amounts.first != 0) {
      percentChange = ((amounts.last - amounts.first) / amounts.first) * 100;
    }
    // Build prompt for Gemini
    final now = DateTime.now();
    final monthLabels = List.generate(6, (i) {
      final month = DateTime(now.year, now.month - (5 - i), 1);
      return 'Tháng ${month.month}/${month.year}';
    });
    final dataLines = List.generate(
        6, (i) => '- ${monthLabels[i]}: ${amounts[i].toStringAsFixed(0)} đồng');
    final prompt = '''
Bạn là trợ lý tài chính cá nhân. Dựa trên dữ liệu chi tiêu trong 6 tháng gần nhất dưới đây, hãy phân tích xu hướng (tăng, giảm, ổn định) và đưa ra nhận xét ngắn gọn, thân thiện bằng tiếng Việt. Nếu có xu hướng tăng, hãy tính % thay đổi và cung cấp gợi ý quản lý. Dữ liệu:
${dataLines.join('\n')}
''';
    final response = await _generateWithFallback([Content.text(prompt)]);
    final insight = response.text ?? 'Không thể phân tích xu hướng lúc này.';
    return TrendResult(
      monthlyAmounts: amounts,
      insight: insight,
      percentChange: percentChange,
    );
  }

  /// AI 6: Gợi ý cắt giảm chi tiêu cho 1 danh mục cụ thể
  Future<String> suggestSpendingCuts({
    required String categoryName,
    required double currentDailyAvg,
    required double targetDailyAvg,
  }) async {
    final monthlySavings = (currentDailyAvg - targetDailyAvg) * 30;
    final prompt = '''
Người dùng đang chi trung bình $currentDailyAvg đồng/ngày cho "$categoryName".
Nếu giảm xuống còn $targetDailyAvg đồng/ngày, mỗi tháng sẽ tiết kiệm được khoảng
$monthlySavings đồng. Viết một gợi ý ngắn gọn, thực tế bằng tiếng Việt.
''';
    final response = await _generateWithFallback([Content.text(prompt)]);
    return response.text ??
        'Giảm chi tiêu cho $categoryName có thể giúp bạn tiết kiệm thêm.';
  }

  /// AI 7: OCR trích xuất thông tin hoá đơn
  /// Kiến trúc: ML Kit (on-device) → raw text → Gemini (structured extraction)
  /// Fallback: nếu ML Kit không nhận diện được text → gửi ảnh thẳng cho Gemini
  Future<ReceiptInfo?> extractReceiptInfo(Uint8List imageBytes) async {
    try {
      // Bước 1: Thử nhận diện text on-device bằng ML Kit
      final rawText = await _recognizeTextOnDevice(imageBytes);

      GenerateContentResponse response;

      if (rawText != null && rawText.trim().isNotEmpty) {
        // Bước 2a: Có raw text từ ML Kit → gửi text cho Gemini parse cấu trúc
        debugPrint(
            '🔧 ML Kit OCR thành công, gửi raw text cho Gemini để parse cấu trúc');
        final prompt = '''
Dưới đây là văn bản được trích xuất từ ảnh hóa đơn bằng OCR (có thể còn nhiễu/sai sót):
---
$rawText
---
Hãy phân tích và trả về JSON gồm: merchant (tên cửa hàng), total (tổng tiền, số), date (ngày, ISO string hoặc null), address (địa chỉ nếu có), items (mảng các đối tượng gồm description và amount). Chỉ trả về JSON thuần túy, không markdown fence.''';
        response = await _generateWithFallback([Content.text(prompt)]);
      } else {
        // Bước 2b: ML Kit không nhận diện được → fallback gửi ảnh thẳng cho Gemini
        debugPrint(
            '🔧 ML Kit không nhận diện được text, fallback gửi ảnh cho Gemini');
        const prompt = '''
Bạn là trợ lý tài chính. Hãy trích xuất các thông tin sau từ hoá đơn (ngôn ngữ tiếng Việt):
- Tên cửa hàng/merchant
- Tổng số tiền (đồng)
- Ngày giao dịch (dd/MM/yyyy) nếu có
- Địa chỉ (address) nếu có
- Các mục (items) dưới dạng mảng, mỗi mục có description và amount
Chỉ trả về kết quả dưới dạng JSON có các trường: merchant, total, date (ISO string hoặc null), address, items. Không bọc trong markdown code block, không thêm giải thích.''';
        final content = Content.multi([
          TextPart(prompt),
          DataPart('image/jpeg', imageBytes),
        ]);
        response = await _generateWithFallback([content]);
      }

      if (response.text == null) return null;
      final cleanedText = _stripMarkdownCodeFence(response.text!);
      final Map<String, dynamic> data = jsonDecode(cleanedText);
      return ReceiptInfo.fromJson(data);
    } catch (e) {
      debugPrint('OCR Receipt extraction error: $e');
      if (_isNetworkError(e) || isNoNetworkException(e)) {
        rethrow;
      }
      return null;
    }
  }

  /// Nhận diện text on-device bằng Google ML Kit Text Recognition.
  /// Trả về raw text hoặc null nếu không nhận diện được / lỗi.
  Future<String?> _recognizeTextOnDevice(Uint8List imageBytes) async {
    // ML Kit on-device không hỗ trợ Flutter Web
    if (kIsWeb) {
      debugPrint(
          '🔧 ML Kit không hỗ trợ trên Flutter Web, bỏ qua bước OCR on-device');
      return null;
    }

    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    File? tempFile;
    try {
      // Lưu tạm file vì InputImage.fromBytes yêu cầu metadata (size, rotation)
      // mà không phải lúc nào cũng có sẵn từ Uint8List thuần túy.
      // InputImage.fromFilePath là cách ổn định nhất trên cả Android/iOS.
      final tempDir = await getTemporaryDirectory();
      tempFile = File(
          '${tempDir.path}/receipt_ocr_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tempFile.writeAsBytes(imageBytes);

      final inputImage = InputImage.fromFilePath(tempFile.path);
      final recognizedText = await textRecognizer.processImage(inputImage);

      debugPrint(
          '🔧 ML Kit nhận diện được ${recognizedText.blocks.length} block(s), '
          'tổng ${recognizedText.text.length} ký tự');

      return recognizedText.text.isEmpty ? null : recognizedText.text;
    } catch (e) {
      debugPrint(
          '⚠️ ML Kit TextRecognizer lỗi, sẽ fallback sang gửi ảnh cho Gemini: $e');
      return null;
    } finally {
      // Dọn file tạm
      if (tempFile != null && await tempFile.exists()) {
        await tempFile.delete();
      }
      // Luôn close để giải phóng tài nguyên native
      textRecognizer.close();
    }
  }

  /// AI Insight nâng cao: nhận danh sách vấn đề ĐÃ PHÁT HIỆN SẴN (bằng
  /// FinancialAnalyticsService), yêu cầu Gemini giải thích nguyên nhân và
  /// đề xuất phương án — KHÔNG đưa dữ liệu thô, không để Gemini tự tính %.
  Future<String> explainAndSuggestForIssues(List<FinancialIssue> issues) async {
    if (issues.isEmpty) {
      return 'Chúc mừng bạn! Chưa phát hiện vấn đề tài chính đáng chú ý nào trong tháng này.';
    }
    final issuesText =
        issues.map((i) => '- ${i.title}: ${i.description}').join('\n');
    final prompt = '''
Bạn là trợ lý tài chính cá nhân. Hệ thống đã PHÁT HIỆN SẴN các vấn đề tài chính
sau đây (dựa trên phân tích số liệu, không cần bạn tính toán lại):

$issuesText

Với MỖI vấn đề, hãy viết ngắn gọn (1-2 câu):
1. Nguyên nhân có thể (dựa trên loại vấn đề)
2. Đề xuất phương án cải thiện CÓ SỐ LIỆU CỤ THỂ (VD "giảm xuống còn X đồng/tháng")

Trả lời bằng tiếng Việt, giọng thân thiện, đi thẳng vào từng vấn đề.
''';
    final response = await _generateWithFallback([Content.text(prompt)]);
    return response.text ?? 'Không thể tạo đề xuất lúc này.';
  }

  /// Giải thích + đề xuất cho ĐÚNG 1 vấn đề, gọi khi người dùng bấm xem chi
  /// tiết trên 1 thẻ cụ thể — ngắn gọn, không viết đoạn văn dài.
  Future<String> explainSingleIssue(FinancialIssue issue) async {
    final prompt = '''
Bạn là trợ lý tài chính cá nhân. Hệ thống đã phát hiện vấn đề sau (đã tính
sẵn bằng số liệu, không cần bạn tính toán lại):

${issue.title}: ${issue.description}

Viết TỐI ĐA 2-3 câu bằng tiếng Việt: 1 câu nêu nguyên nhân có thể, 1 câu đề
xuất phương án cải thiện CÓ SỐ LIỆU CỤ THỂ. Không lan man, không mở đầu bằng
lời chào.
''';
    final response = await _generateWithFallback([Content.text(prompt)]);
    return response.text ?? 'Không thể tạo đề xuất lúc này.';
  }

  /// AI Cố vấn tài chính diễn giải tổng hợp FinancialInsightSummary đã được Dart tính sẵn.
  /// Tuyệt đối không gửi UID, email, ảnh hay thông tin cá nhân.
  Future<String> explainFinancialInsights(
      FinancialInsightSummary summary) async {
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

    final prompt = '''
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

    final response = await _generateWithFallback([Content.text(prompt)]);
    return response.text ?? 'Không thể tải phần giải thích AI lúc này.';
  }

  /// Giải thích khoản chi bất thường dựa trên số liệu Dart đã tính sẵn.
  /// Tuyệt đối KHÔNG gửi UID, email, note đầy đủ, vị trí hoặc ảnh.
  Future<String> explainTransactionAnomaly({
    required String categoryName,
    required double currentAmount,
    required double expectedAmount,
    required double ratio,
    required int historySampleSize,
  }) async {
    final ratioFormatted = ratio.toStringAsFixed(1).replaceAll('.0', '');
    final prompt = '''
Bạn là trợ lý tài chính cá nhân. Hệ thống đã phát hiện một khoản chi bất thường dựa trên thuật toán Dart xác định:
- Danh mục: $categoryName
- Số tiền chi giao dịch này: ${currentAmount.round()} VNĐ
- Mức chi trung vị thông thường (90 ngày qua, $historySampleSize mẫu): ${expectedAmount.round()} VNĐ
- Tỷ lệ chênh lệch: khoảng $ratioFormatted lần mức thông thường.

Hãy viết giải thích ngắn gọn bằng tiếng Việt, TỐI ĐA 2 CÂU:
1. Nhận xét về lý do vì sao hệ thống đưa ra cảnh báo này dựa trên số liệu.
2. Lời khuyên nhẹ nhàng để người dùng xem xét kiểm tra lại giao dịch (vẫn khẳng định người dùng có toàn quyền lưu nếu đây là khoản chi hợp lý).

LƯU Ý: Tuyệt đối không kết luận gian lận, không tư vấn đầu tư, không tự tính toán lại hoặc bịa đặt số liệu mới ngoài các con số trên.
''';

    final response = await _generateWithFallback([Content.text(prompt)]);
    return response.text ??
        'Khoản chi này cao hơn khoảng $ratioFormatted lần mức chi thông thường của bạn cho $categoryName.';
  }


  String _stripMarkdownCodeFence(String text) {
    final trimmed = text.trim();
    final fenceRegex = RegExp(r'^```(?:json)?\s*([\s\S]*?)\s*```$');
    final match = fenceRegex.firstMatch(trimmed);
    return match != null ? match.group(1)!.trim() : trimmed;
  }

  /// Reset phiên chat (khi người dùng vào lại màn hình AI Chat)
  void resetChatSession() {
    _chatHistory.clear();
  }

  /// Khôi phục lịch sử chat từ phiên hội thoại cũ (Conversation Context)
  void restoreChatHistory({
    required String contextData,
    required List<Map<String, dynamic>> previousMessages,
  }) {
    _chatHistory.clear();
    _chatHistory.add(Content.text(_buildSystemCfpPrompt(contextData)));
    final recent = previousMessages.length > 10
        ? previousMessages.sublist(previousMessages.length - 10)
        : previousMessages;
    for (final m in recent) {
      final isUser = m['isUser'] == true;
      final text = m['text'] as String? ?? '';
      if (text.isEmpty) continue;
      if (isUser) {
        _chatHistory.add(Content.text(text));
      } else {
        _chatHistory.add(Content.model([TextPart(text)]));
      }
    }
  }

  String _buildSystemCfpPrompt(String contextData) {
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
   - Trình bày dạng Markdown với gạch đầu dòng rõ ràng, in đậm các con số quan trọng (**số tiền**, **tỷ lệ %**) để người dùng dễ theo dõi trên màn hình di động.
''';
  }

  String _buildCategorySummary(
      List<AppTransaction> transactions, List<Category> categories) {
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
            color: 0xFF9E9E9E),
      );
      final percent = totalSpent == 0 ? 0 : (amount / totalSpent * 100).round();
      buffer.writeln('- ${cat.name}: ${amount.round()} đồng ($percent%)');
    });
    return buffer.toString();
  }
}

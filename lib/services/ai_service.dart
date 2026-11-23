import 'dart:io';
import 'package:flutter/foundation.dart'
    show debugPrint, kIsWeb, visibleForTesting;
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart' show getTemporaryDirectory;
import 'dart:typed_data';
import 'dart:convert';
import '../models/ai_runtime_config_model.dart';
import '../models/receipt_info.dart';
import '../models/financial_forecast_result.dart';
import '../models/monthly_financial_plan.dart';
import '../config/api_keys.dart';
import '../utils/formatters.dart';
import 'ai_prompt_builder.dart';
import '../l10n/app_localizations.dart';

/// ============================================================
/// AI SERVICE
/// Gọi Gemini API để phân tích chi tiêu, dự đoán, chatbot tài chính
///
/// LƯU Ý BẢO MẬT & KIẾN TRÚC SDK:
/// 1. Gói `google_generative_ai` hiện được giữ cho tương thích ngược nhưng đã
///    ở trạng thái deprecated; lộ trình sản phẩm là di trú sang `firebase_ai`
///    (Firebase AI Logic) kết hợp Firebase App Check hoặc Cloud Functions Proxy.
/// 2. Gọi trực tiếp Gemini từ client trên bản demo/khóa luận có rủi ro lộ API key
///    trong binary client. Tuyệt đối KHÔNG lưu hoặc truyền Gemini API Key qua
///    Firestore / Admin Web Config.
/// ============================================================
class AiService {
  // Danh sách model dự phòng mặc định khi chưa có cấu hình động
  static const List<String> _defaultModelFallbackChain = [
    'gemini-3.5-flash', // model chính, đã xác nhận hoạt động qua Bước 1
    'gemini-3.5-flash-lite', // dự phòng 1
    'gemini-3.6-flash', // dự phòng 2
    'gemini-flash-latest', // dự phòng 3
  ];

  final AiRuntimeConfig? _runtimeConfigOverride;
  final List<FinancialKnowledgeArticle>? _knowledgeArticlesOverride;
  final Future<String?> Function(
    String modelName,
    List<Content> content,
    double temperature,
  )? _contentGeneratorOverride;
  final Stream<String> Function(
    String modelName,
    List<Content> content,
    double temperature,
  )? _streamGeneratorOverride;

  final List<Content> _chatHistory = [];
  String _lastModelUsed = '';

  AiService({
    AiRuntimeConfig? runtimeConfigOverride,
    List<FinancialKnowledgeArticle>? knowledgeArticlesOverride,
    bool allowMissingApiKeyForTest = false,
    Future<String?> Function(
      String modelName,
      List<Content> content,
      double temperature,
    )? contentGeneratorOverride,
    Stream<String> Function(
      String modelName,
      List<Content> content,
      double temperature,
    )? streamGeneratorOverride,
  })  : _runtimeConfigOverride = runtimeConfigOverride,
        _knowledgeArticlesOverride = knowledgeArticlesOverride,
        _contentGeneratorOverride = contentGeneratorOverride,
        _streamGeneratorOverride = streamGeneratorOverride {
    debugPrint('🔧 Model fallback chain: $effectiveModelChain');
    if (!allowMissingApiKeyForTest &&
        _contentGeneratorOverride == null &&
        _streamGeneratorOverride == null &&
        (geminiApiKey.isEmpty || geminiApiKey == 'YOUR_GEMINI_API_KEY_HERE')) {
      throw Exception(
          AppLocalizations.tr('svc_ai_no_api_key'));
    }
  }

  /// Cấu hình AI Runtime hiệu lực (ưu tiên override trong Test, mặc định dùng hằng số chuẩn cố định)
  AiRuntimeConfig get effectiveRuntimeConfig =>
      _runtimeConfigOverride ?? AiRuntimeConfig.defaults();

  /// Chuỗi model thực thi hiệu lực (Primary + Fallbacks từ AiRuntimeConfig, luôn thuộc Whitelist)
  List<String> get effectiveModelChain {
    final chain = effectiveRuntimeConfig.effectiveModelChain;
    return chain.isNotEmpty ? chain : _defaultModelFallbackChain;
  }

  /// Model thực tế đã trả lời thành công ở lần gọi gần nhất (phục vụ gắn metadata cho AI Feedback Report & Sandbox)
  String get lastModelUsed =>
      _lastModelUsed.isNotEmpty ? _lastModelUsed : effectiveModelChain.first;

  /// Số lượng phần tử hiện tại trong bộ nhớ lịch sử hội thoại (bao gồm System Prompt ở index 0)
  int get chatHistoryLength => _chatHistory.length;

  /// Ảnh chụp lịch sử hội thoại hiện tại phục vụ kiểm thử (không cho phép sửa trực tiếp)
  @visibleForTesting
  List<Content> get chatHistorySnapshot => List<Content>.unmodifiable(_chatHistory);

  /// Xóa câu hỏi user vừa đẩy vào ở lượt hiện tại nếu gọi API thất bại (tránh trùng lặp khi bấm Thử lại)
  void _rollbackLastUserTurn(String userQuestion) {
    if (_chatHistory.length <= 1) return;
    final last = _chatHistory.last;
    final isCurrentUserTurn = last.role != 'model' &&
        last.parts.length == 1 &&
        last.parts.first is TextPart &&
        (last.parts.first as TextPart).text == userQuestion;
    if (isCurrentUserTurn) {
      _chatHistory.removeLast();
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

  // Hàm helper gọi generateContent có tự động thử model dự phòng khi gặp lỗi hoặc đầu ra không hợp lệ
  Future<GenerateContentResponse> _generateWithFallback(
    List<Content> content, {
    double? temperatureOverride,
    String? responseMimeType,
    bool Function(String text)? responseValidator,
    Duration timeout = const Duration(seconds: 18),
  }) async {
    final cfg = effectiveRuntimeConfig;
    if (!cfg.isEnabled) {
      throw Exception('AI_FEATURES_DISABLED');
    }
    final chain = effectiveModelChain;
    final effectiveTemp = (temperatureOverride ?? cfg.temperature).clamp(
      AiRuntimeConfig.kMinTemperature,
      AiRuntimeConfig.kMaxTemperature,
    );
    final customGen = _contentGeneratorOverride;

    Exception? lastError;
    for (final modelName in chain) {
      try {
        debugPrint(
            '🚀 Đang gọi Gemini với model: $modelName (temp: $effectiveTemp)');
        if (customGen != null) {
          final text = await customGen(
            modelName,
            content,
            effectiveTemp,
          );
          if (responseValidator != null && !responseValidator(text ?? '')) {
            throw const FormatException('INVALID_STRUCTURED_RESPONSE');
          }
          _lastModelUsed = modelName;
          return GenerateContentResponse([
            Candidate(
              Content.model([TextPart(text ?? '')]),
              null,
              null,
              null,
              null,
            ),
          ], null);
        }

        final model = GenerativeModel(
          model: modelName,
          apiKey: geminiApiKey,
          generationConfig: GenerationConfig(
            temperature: effectiveTemp,
            responseMimeType: responseMimeType,
          ),
        );
        final response = await model.generateContent(content).timeout(timeout);
        if (responseValidator != null &&
            !responseValidator(response.text ?? '')) {
          throw const FormatException('INVALID_STRUCTURED_RESPONSE');
        }
        _lastModelUsed = modelName;
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
    throw lastError ?? Exception(AppLocalizations.tr('svc_ai_all_failed'));
  }

  /// AI 4: Lập kế hoạch tiết kiệm có gắn ngữ cảnh thu nhập & chi tiêu thực tế
  Future<String> generateSavingPlan({
    required String goalName,
    required double targetAmount,
    required int months,
    double savedAmount = 0,
    double? monthlyIncome,
    double? monthlyExpense,
    List<String>? flexibleCategorySummaries,
  }) async {
    final remaining = (targetAmount - savedAmount).clamp(0.0, double.infinity);
    final safeMonths = months <= 0 ? 1 : months;
    final monthlyRequired = remaining / safeMonths;
    final prompt = AiPromptBuilder.buildSavingPlanPrompt(
      goalName: goalName,
      targetAmount: targetAmount,
      months: months,
      savedAmount: savedAmount,
      monthlyIncome: monthlyIncome,
      monthlyExpense: monthlyExpense,
      flexibleCategorySummaries: flexibleCategorySummaries,
      runtimeConfig: effectiveRuntimeConfig,
    );
    final response = await _generateWithFallback([Content.text(prompt)]);
    return response.text != null
        ? AiPromptBuilder.formatCurrencyNumbersInText(response.text!)
        : AppLocalizations.tr('svc_ai_save_plan_fb', params: {
            'amount': AppFormatters.number(monthlyRequired),
            'goal': goalName,
          });
  }

  /// AI 5: Chatbot tài chính - Trợ lý AI tài chính cá nhân dựa trên dữ liệu định lượng
  Future<String> chatWithFinancialData({
    required String userQuestion,
    required String contextData, // Dữ liệu tài chính định lượng tổng hợp từ Firestore
  }) async {
    _syncSystemPromptAndHistory(contextData, userQuestion);
    try {
      final response = await _generateWithFallback(_chatHistory);
      final formatted = response.text != null
          ? AiPromptBuilder.formatCurrencyNumbersInText(response.text!)
          : null;
      if (formatted != null) {
        _chatHistory.add(Content.model([TextPart(formatted)]));
      }
      return formatted ?? AppLocalizations.tr('svc_ai_cant_answer');
    } catch (e) {
      // Xóa câu hỏi user vừa thêm để người dùng bấm Thử lại không bị gửi trùng 2 lần
      _rollbackLastUserTurn(userQuestion);
      rethrow;
    }
  }

  /// AI 5 (Stream): Trợ lý AI tài chính cá nhân phản hồi dạng dòng (Stream) giảm độ trễ hiển thị.
  /// - [onStreamReset] được gọi khi model trước đã phát một phần nội dung nhưng bị đứt giữa chừng
  ///   và chuyển sang model dự phòng / fallback non-streaming, giúp UI reset sạch buffer tránh nối chữ.
  Stream<String> chatWithFinancialDataStream({
    required String userQuestion,
    required String contextData,
    void Function()? onStreamReset,
  }) async* {
    final cfg = effectiveRuntimeConfig;
    if (!cfg.isEnabled) {
      throw Exception('AI_FEATURES_DISABLED');
    }

    _syncSystemPromptAndHistory(contextData, userQuestion);

    final accumulatedText = StringBuffer();
    bool streamSucceeded = false;
    Exception? lastError;
    final chain = effectiveModelChain;
    final effectiveTemp = cfg.temperature.clamp(
      AiRuntimeConfig.kMinTemperature,
      AiRuntimeConfig.kMaxTemperature,
    );
    final customGen = _contentGeneratorOverride;
    final customStreamGen = _streamGeneratorOverride;

    try {
      for (final modelName in chain) {
        bool emittedInCurrentAttempt = false;
        try {
          debugPrint(
              '🚀 Đang gọi Gemini Stream với model: $modelName (temp: $effectiveTemp)');
          if (customStreamGen != null) {
            await for (final text in customStreamGen(
              modelName,
              _chatHistory,
              effectiveTemp,
            )) {
              if (text.isNotEmpty) {
                emittedInCurrentAttempt = true;
                accumulatedText.write(text);
                yield text;
              }
            }
            _lastModelUsed = modelName;
            streamSucceeded = true;
            break;
          }

          if (customGen != null) {
            final text = await customGen(
              modelName,
              _chatHistory,
              effectiveTemp,
            );
            _lastModelUsed = modelName;
            if (text != null && text.isNotEmpty) {
              emittedInCurrentAttempt = true;
              accumulatedText.write(text);
              yield text;
            }
            streamSucceeded = true;
            break;
          }

          final model = GenerativeModel(
            model: modelName,
            apiKey: geminiApiKey,
            generationConfig: GenerationConfig(temperature: effectiveTemp),
          );
          final stream = model
              .generateContentStream(_chatHistory)
              .timeout(const Duration(seconds: 25));

          await for (final chunk in stream) {
            final text = chunk.text;
            if (text != null && text.isNotEmpty) {
              emittedInCurrentAttempt = true;
              accumulatedText.write(text);
              yield text;
            }
          }
          _lastModelUsed = modelName;
          streamSucceeded = true;
          break;
        } catch (e) {
          if (_isNetworkError(e)) {
            debugPrint(
                '⚠️ Phát hiện lỗi mất mạng khi gọi stream model "$modelName": $e');
            _rollbackLastUserTurn(userQuestion);
            throw Exception('NO_NETWORK');
          }
          lastError = e is Exception ? e : Exception(e.toString());
          debugPrint(
              '⚠️ Model Stream "$modelName" thất bại: $e — thử fallback tiếp theo...');
          accumulatedText.clear();
          if (emittedInCurrentAttempt) {
            // Báo UI reset sạch buffer trước khi model dự phòng bắt đầu phát lại từ đầu
            onStreamReset?.call();
          }
        }
      }

      // Nếu toàn bộ stream fallback thất bại, thử gọi fallback chuẩn (non-streaming)
      if (!streamSucceeded) {
        try {
          debugPrint('⚠️ Chuyển sang fallback non-streaming cho câu trả lời');
          final response = await _generateWithFallback(_chatHistory);
          final rawFullText =
              response.text ?? AppLocalizations.tr('svc_ai_cant_answer');
          final fullText =
              AiPromptBuilder.formatCurrencyNumbersInText(rawFullText);
          accumulatedText.write(fullText);
          yield fullText;
          streamSucceeded = true;
        } catch (fallbackError) {
          _rollbackLastUserTurn(userQuestion);
          throw lastError ?? fallbackError;
        }
      }

      if (streamSucceeded && accumulatedText.isNotEmpty) {
        final formattedFinal = AiPromptBuilder.formatCurrencyNumbersInText(
          accumulatedText.toString(),
        );
        _chatHistory.add(Content.model([TextPart(formattedFinal)]));
      }
    } finally {
      if (!streamSucceeded) {
        _rollbackLastUserTurn(userQuestion);
      }
    }
  }

  /// Đồng bộ System Prompt định lượng mới nhất và duy trì Sliding Window lịch sử theo cấu hình AiRuntimeConfig
  void _syncSystemPromptAndHistory(String contextData, String userQuestion) {
    final maxMessages =
        effectiveRuntimeConfig.maxChatHistoryMessages.clamp(4, 20);
    if (_chatHistory.isEmpty) {
      _chatHistory.add(Content.text(_buildSystemCfpPrompt(contextData)));
    } else {
      // Cập nhật System Prompt với ngữ cảnh tài chính mới nhất
      _chatHistory[0] = Content.text(_buildSystemCfpPrompt(contextData));
    }
    _chatHistory.add(Content.text(userQuestion));

    // Duy trì sliding window: Giữ index 0 (System Prompt) và tối đa maxMessages tin nhắn gần nhất
    if (_chatHistory.length > maxMessages + 1) {
      _chatHistory.removeRange(1, _chatHistory.length - maxMessages);
    }
  }

  /// AI 7: OCR trích xuất thông tin hoá đơn
  /// Kiến trúc: Kết hợp ML Kit (on-device OCR) + Ảnh gốc + Gemini Multimodal
  /// để vừa đọc chính xác bảng mặt hàng nhiều dòng (Tên món, SL, Đơn giá, Thành tiền),
  /// vừa suy luận/khôi phục ngữ cảnh khi chữ bị mờ hoặc mất dấu.
  Future<ReceiptInfo?> extractReceiptInfo(Uint8List imageBytes) async {
    try {
      // Bước 1: Thử nhận diện text on-device bằng ML Kit để làm dữ liệu tham chiếu
      final rawText = await _recognizeTextOnDevice(imageBytes);

      final hasRawText = rawText != null && rawText.trim().isNotEmpty;
      final prompt = AiPromptBuilder.buildReceiptExtractionPrompt(
        ocrText: rawText,
        runtimeConfig: effectiveRuntimeConfig,
      );

      GenerateContentResponse response;
      try {
        debugPrint(
            '🔧 Gửi kết hợp ảnh hóa đơn + ML Kit OCR reference (${hasRawText ? "có rawText" : "không có rawText"}) cho Gemini');
        final content = Content.multi([
          TextPart(prompt),
          DataPart('image/jpeg', imageBytes),
        ]);
        response =
            await _generateWithFallback([content], temperatureOverride: 0.1);
      } catch (multimodalError) {
        if (hasRawText &&
            !_isNetworkError(multimodalError) &&
            !isNoNetworkException(multimodalError)) {
          debugPrint(
              '🔧 Multimodal gặp lỗi, fallback sang gửi rawText từ ML Kit: $multimodalError');
          response = await _generateWithFallback(
            [Content.text(prompt)],
            temperatureOverride: 0.1,
          );
        } else {
          rethrow;
        }
      }

      if (response.text == null) return null;
      final cleanedText = _stripMarkdownCodeFence(response.text!);
      final Map<String, dynamic> data = jsonDecode(cleanedText);
      return ReceiptInfo.fromJson(data, rawText: rawText);
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

  /// AI Cố vấn tài chính diễn giải tổng hợp FinancialInsightSummary đã được Dart tính sẵn.
  /// Tuyệt đối không gửi UID, email, ảnh hay thông tin cá nhân.
  Future<String> explainFinancialInsights(
      FinancialInsightSummary summary) async {
    final prompt = AiPromptBuilder.buildFinancialInsightsPrompt(summary);
    final response = await _generateWithFallback([Content.text(prompt)]);
    return response.text != null
        ? AiPromptBuilder.formatCurrencyNumbersInText(response.text!)
        : AppLocalizations.tr('svc_ai_cant_explain');
  }

  /// Diễn giải và đề xuất kế hoạch tài chính theo định dạng JSON có cấu trúc,
  /// tuân thủ chặt chẽ DataSufficiencyTier và có cơ chế hậu kiểm + fallback an toàn.
  Future<AiStructuredPlanInsight> explainFinancialInsightsStructured({
    required FinancialInsightSummary summary,
    required MonthlyFinancialPlan draftPlan,
  }) async {
    final tier = draftPlan.dataTierUsed;
    if (tier == DataSufficiencyTier.empty) {
      return AiStructuredPlanInsight(
        executiveSummary:
            AppLocalizations.tr('svc_ai_empty_exec'),
        behavioralInsights: [],
        categoryActionTips: {},
        savingStrategyNote:
            AppLocalizations.tr('svc_ai_empty_strat'),
        isFromFallback: true,
      );
    }

    // Nếu quản trị viên tắt tính năng AI (isEnabled == false), bỏ qua hoàn toàn
    // việc gọi Gemini API và trả về bản diễn giải định lượng nội bộ mượt mà.
    if (!effectiveRuntimeConfig.isEnabled) {
      return buildDeterministicFallbackInsight(draftPlan, summary: summary);
    }

    final prompt = AiPromptBuilder.buildStructuredPlanPrompt(
      summary: summary,
      draftPlan: draftPlan,
      runtimeConfig: effectiveRuntimeConfig,
    );

    AiStructuredPlanInsight? parsedResult;
    try {
      await _generateWithFallback(
        [Content.text(prompt)],
        responseMimeType: 'application/json',
        timeout: const Duration(seconds: 22),
        responseValidator: (rawText) {
          parsedResult = parseAndValidateStructuredInsight(
            rawText: rawText,
            draftPlan: draftPlan,
          );
          return parsedResult != null;
        },
      );
      if (parsedResult != null) {
        return parsedResult!;
      }
    } catch (e) {
      debugPrint('⚠️ Lỗi gọi/parse explainFinancialInsightsStructured: $e');
    }

    return buildDeterministicFallbackInsight(draftPlan, summary: summary);
  }

  /// Parse và kiểm duyệt JSON trả về từ Gemini; trả về null nếu JSON sai cấu trúc.
  static AiStructuredPlanInsight? parseAndValidateStructuredInsight({
    required String rawText,
    required MonthlyFinancialPlan draftPlan,
  }) {
    return AiPromptBuilder.parseAndValidateStructuredInsight(
      rawText: rawText,
      draftPlan: draftPlan,
    );
  }

  /// Bản diễn giải định lượng dự phòng (Deterministic Fallback) khi mất mạng hoặc JSON lỗi.
  static AiStructuredPlanInsight buildDeterministicFallbackInsight(
    MonthlyFinancialPlan draftPlan, {
    FinancialInsightSummary? summary,
  }) {
    return AiPromptBuilder.buildDeterministicFallbackInsight(
      draftPlan,
      summary: summary,
    );
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
    final prompt = AiPromptBuilder.buildTransactionAnomalyPrompt(
      categoryName: categoryName,
      currentAmount: currentAmount,
      expectedAmount: expectedAmount,
      ratio: ratio,
      historySampleSize: historySampleSize,
      runtimeConfig: effectiveRuntimeConfig,
    );

    final response = await _generateWithFallback([Content.text(prompt)]);
    return response.text != null
        ? AiPromptBuilder.formatCurrencyNumbersInText(response.text!)
        : AppLocalizations.tr('svc_ai_anom_fb',
            params: {'ratio': ratioFormatted, 'cat': categoryName});
  }

  String _stripMarkdownCodeFence(String text) {
    return AiPromptBuilder.stripMarkdownCodeFence(text);
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
    final maxMessages =
        effectiveRuntimeConfig.maxChatHistoryMessages.clamp(4, 20);
    _chatHistory.clear();
    _chatHistory.add(Content.text(_buildSystemCfpPrompt(contextData)));
    final recent = previousMessages.length > maxMessages
        ? previousMessages.sublist(previousMessages.length - maxMessages)
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

  /// Xây dựng System Prompt hoàn chỉnh cho AI Chat & AI Sandbox, kết hợp:
  /// - Khối số liệu định lượng cố định từ Dart
  /// - Nguyên tắc DATA GROUNDING và STRICT DOMAIN SCOPE cố định (không thể bị ghi đè)
  /// - Khối chỉ dẫn phong cách từ AiRuntimeConfig (nếu có)
  /// - Tối đa 3 snippet từ FinancialKnowledgeArticle (mỗi snippet <= 300 ký tự)
  String buildSystemCfpPromptForContext(
    String contextData, {
    bool? isLowSavingRate,
    bool? isEssentialDeficit,
    bool? isVariableIncome,
    bool? hasBudgetOverrun,
    bool? isGoalInfeasible,
  }) {
    return AiPromptBuilder.buildSystemCfpPromptForContext(
      contextData,
      runtimeConfig: effectiveRuntimeConfig,
      overrideArticles: _knowledgeArticlesOverride,
      isLowSavingRate: isLowSavingRate,
      isEssentialDeficit: isEssentialDeficit,
      isVariableIncome: isVariableIncome,
      hasBudgetOverrun: hasBudgetOverrun,
      isGoalInfeasible: isGoalInfeasible,
    );
  }

  String _buildSystemCfpPrompt(String contextData) {
    return buildSystemCfpPromptForContext(contextData);
  }
}

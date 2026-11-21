import 'budget_model.dart';
import 'category_model.dart';
import 'saving_goal_model.dart';
import 'transaction_model.dart';
import 'wallet_model.dart';

/// ============================================================================
/// AI RUNTIME CONFIG, FINANCIAL HEURISTICS & KNOWLEDGE BASE MODELS (HARDCODED DEFAULTS)
/// ============================================================================
/// LƯU Ý KIẾN TRÚC & BẢO MẬT:
/// 1. Dự án hiện giữ `package:google_generative_ai` ở tầng thực thi để bảo toàn
///    độ ổn định của Streaming Chatbot và Multimodal OCR, nhưng ghi nhận gói này
///    đã ngưng phát triển tính năng mới (deprecated) để sẵn sàng lộ trình nâng cấp
///    sang `firebase_ai` hoặc Backend Proxy.
/// 2. Tuyệt đối KHÔNG lưu trữ Gemini API Key hay khóa bí mật (Secret Salt)
///    trong bất kỳ model cấu hình nào.
/// 3. Toàn bộ ứng dụng Mobile sử dụng trực tiếp hằng số cấu hình chuẩn cố định
///    trong mã nguồn (`defaults()`), không đọc cấu hình động từ Firestore.
/// ============================================================================

/// Phân loại kênh phát hành của Model theo tài liệu Gemini API chính thức:
/// - `stable`: Model ổn định chính thức (GA), khuyến nghị dùng cho Production.
/// - `preview`: Model thử nghiệm thế hệ mới (Preview).
/// - `legacy`: Model thế hệ cũ (ví dụ dòng 2.5), không mặc định khả dụng cho mọi tài khoản mới.
/// - `mutableAlias`: Bí danh tự động thay đổi đích trỏ theo thời gian (không dùng làm fallback duy nhất).
enum GeminiModelReleaseChannel {
  stable,
  preview,
  legacy,
  mutableAlias,
}

/// Mô tả thông tin một Model Gemini nằm trong Whitelist được phép sử dụng
class GeminiModelDescriptor {
  final String modelId;
  final String displayName;
  final String roleBadge;
  final String description;
  final GeminiModelReleaseChannel releaseChannel;
  final bool supportsStreaming;
  final bool supportsMultimodalOcr;
  final bool supportsStructuredJson;
  final bool isRecommendedPrimary;

  const GeminiModelDescriptor({
    required this.modelId,
    required this.displayName,
    required this.roleBadge,
    required this.description,
    this.releaseChannel = GeminiModelReleaseChannel.stable,
    this.supportsStreaming = true,
    this.supportsMultimodalOcr = true,
    this.supportsStructuredJson = true,
    this.isRecommendedPrimary = false,
  });

  bool get isStable => releaseChannel == GeminiModelReleaseChannel.stable;
  bool get isLegacy => releaseChannel == GeminiModelReleaseChannel.legacy;
  bool get isMutableAlias =>
      releaseChannel == GeminiModelReleaseChannel.mutableAlias;
}

/// Danh sách Whitelist các Model ID hợp lệ đối chiếu theo tài liệu Gemini Developer API chính thức.
/// - Giữ nguyên `gemini-3.5-flash` làm model mặc định đã kiểm chứng tương thích với `AiService`.
/// - Bổ sung các model ổn định mới (`gemini-3.8-flash`, `gemini-3.7-flash`) và `gemini-3-flash-preview`.
/// - Phân loại rõ nhóm `legacy` (dòng 2.5 — tùy tài khoản) và `mutableAlias` (`gemini-flash-latest`).
const List<GeminiModelDescriptor> kSupportedGeminiModels = [
  GeminiModelDescriptor(
    modelId: 'gemini-3.5-flash',
    displayName: 'Gemini 3.5 Flash',
    roleBadge: 'Mặc định (Đã kiểm chứng)',
    description:
        'Model chính mặc định của hệ thống, cân bằng tối ưu giữa tốc độ phản hồi, tư vấn tài chính và OCR hóa đơn.',
    releaseChannel: GeminiModelReleaseChannel.stable,
    isRecommendedPrimary: true,
  ),
  GeminiModelDescriptor(
    modelId: 'gemini-3.5-flash-lite',
    displayName: 'Gemini 3.5 Flash-Lite',
    roleBadge: 'Ổn định / Fallback #1',
    description:
        'Model ổn định chính thức (GA) độ trễ cực thấp, thông lượng cao, ưu tiên làm fallback số 1.',
    releaseChannel: GeminiModelReleaseChannel.stable,
  ),
  GeminiModelDescriptor(
    modelId: 'gemini-3.6-flash',
    displayName: 'Gemini 3.6 Flash',
    roleBadge: 'Ổn định / Fallback #2',
    description:
        'Phiên bản Flash ổn định hỗ trợ tốt ngữ cảnh dài và lập kế hoạch tài chính có cấu trúc.',
    releaseChannel: GeminiModelReleaseChannel.stable,
    isRecommendedPrimary: true,
  ),
  GeminiModelDescriptor(
    modelId: 'gemini-3.7-flash',
    displayName: 'Gemini 3.7 Flash',
    roleBadge: 'Ổn định (Thế hệ mới)',
    description:
        'Nâng cấp khả năng suy luận đa bước và độ chính xác khi tuân thủ ràng buộc số liệu.',
    releaseChannel: GeminiModelReleaseChannel.stable,
    isRecommendedPrimary: true,
  ),
  GeminiModelDescriptor(
    modelId: 'gemini-3.8-flash',
    displayName: 'Gemini 3.8 Flash',
    roleBadge: 'Ổn định (Mới nhất)',
    description:
        'Phiên bản Flash mới nhất theo tài liệu Gemini API hiện hành, mạnh về tác vụ định lượng và JSON.',
    releaseChannel: GeminiModelReleaseChannel.stable,
    isRecommendedPrimary: true,
  ),
  GeminiModelDescriptor(
    modelId: 'gemini-3-flash-preview',
    displayName: 'Gemini 3 Flash Preview',
    roleBadge: 'Preview',
    description:
        'Bản xem trước (Preview) dòng Gemini 3 Flash, dùng để thử nghiệm trên AI Sandbox.',
    releaseChannel: GeminiModelReleaseChannel.preview,
    isRecommendedPrimary: false,
  ),
  GeminiModelDescriptor(
    modelId: 'gemini-2.5-flash',
    displayName: 'Gemini 2.5 Flash (Legacy)',
    roleBadge: 'Legacy (Tùy tài khoản)',
    description:
        'Thế hệ 2.5 cũ — chỉ khả dụng trên một số dự án/tài khoản đã kích hoạt từ trước, không mặc định dùng.',
    releaseChannel: GeminiModelReleaseChannel.legacy,
    isRecommendedPrimary: false,
  ),
  GeminiModelDescriptor(
    modelId: 'gemini-2.5-flash-lite',
    displayName: 'Gemini 2.5 Flash-Lite (Legacy)',
    roleBadge: 'Legacy (Tùy tài khoản)',
    description:
        'Phiên bản nhẹ dòng 2.5 cũ — không mặc định khả dụng cho mọi tài khoản mới.',
    releaseChannel: GeminiModelReleaseChannel.legacy,
    isRecommendedPrimary: false,
  ),
  GeminiModelDescriptor(
    modelId: 'gemini-2.5-pro',
    displayName: 'Gemini 2.5 Pro (Legacy)',
    roleBadge: 'Legacy (Tùy tài khoản)',
    description:
        'Phiên bản Pro dòng 2.5 cũ — độ trễ cao và phụ thuộc quyền truy cập từng tài khoản.',
    releaseChannel: GeminiModelReleaseChannel.legacy,
    isRecommendedPrimary: false,
  ),
  GeminiModelDescriptor(
    modelId: 'gemini-flash-latest',
    displayName: 'Gemini Flash Latest (Auto-Alias)',
    roleBadge: 'Alias động (Dự phòng cuối)',
    description:
        'Bí danh tự động thay đổi theo thời gian; chỉ được phép đứng sau ít nhất một model ổn định trong chuỗi fallback.',
    releaseChannel: GeminiModelReleaseChannel.mutableAlias,
    isRecommendedPrimary: false,
  ),
];

/// Tra cứu thông tin Descriptor của một Model ID trong Whitelist
GeminiModelDescriptor? findGeminiModelDescriptor(String? modelId) {
  if (modelId == null || modelId.trim().isEmpty) return null;
  final trimmed = modelId.trim();
  for (final m in kSupportedGeminiModels) {
    if (m.modelId == trimmed) return m;
  }
  return null;
}

/// Kiểm tra một mã model có nằm trong danh sách Whitelist được phép hay không
bool isSupportedGeminiModelId(String? modelId) {
  return findGeminiModelDescriptor(modelId) != null;
}

/// Kiểm tra một mã model có phải là bí danh thay đổi theo thời gian (Mutable Alias) hay không
bool isMutableAliasGeminiModelId(String? modelId) {
  final desc = findGeminiModelDescriptor(modelId);
  return desc != null && desc.isMutableAlias;
}

/// Làm sạch và khử trùng lặp chuỗi model:
/// - Không cho phép dùng Mutable Alias (`gemini-flash-latest`) làm model chính.
/// - Không bao giờ để Mutable Alias hoặc model Legacy làm cơ chế fallback duy nhất:
///   luôn đảm bảo có ít nhất các model ổn định (`gemini-3.5-flash-lite`, `gemini-3.6-flash`)
///   đứng trước alias động trong chuỗi dự phòng.
List<String> sanitizeGeminiModelChain({
  required String primaryModel,
  required List<String> fallbackModels,
}) {
  const defaultPrimary = 'gemini-3.5-flash';
  const defaultStableFallbacks = <String>[
    'gemini-3.5-flash-lite',
    'gemini-3.6-flash',
  ];
  const defaultFinalAlias = 'gemini-flash-latest';

  final primaryDesc = findGeminiModelDescriptor(primaryModel);
  final validPrimary = (primaryDesc != null && !primaryDesc.isMutableAlias)
      ? primaryDesc.modelId
      : defaultPrimary;

  final nonAliasFallbacks = <String>[];
  final aliasFallbacks = <String>[];

  for (final fb in fallbackModels) {
    final desc = findGeminiModelDescriptor(fb);
    if (desc == null || desc.modelId == validPrimary) continue;
    if (desc.isMutableAlias) {
      if (!aliasFallbacks.contains(desc.modelId)) {
        aliasFallbacks.add(desc.modelId);
      }
    } else {
      if (!nonAliasFallbacks.contains(desc.modelId)) {
        nonAliasFallbacks.add(desc.modelId);
      }
    }
  }

  // Đảm bảo có ít nhất 1 model thuộc kênh `stable` trong danh sách fallback trước khi đến alias
  final hasStableFallback = nonAliasFallbacks.any((id) {
    final d = findGeminiModelDescriptor(id);
    return d != null && d.isStable;
  });

  if (!hasStableFallback) {
    for (final stableId in defaultStableFallbacks) {
      if (stableId != validPrimary && !nonAliasFallbacks.contains(stableId)) {
        nonAliasFallbacks.add(stableId);
      }
    }
  } else {
    for (final stableId in defaultStableFallbacks) {
      if (stableId != validPrimary && !nonAliasFallbacks.contains(stableId)) {
        nonAliasFallbacks.add(stableId);
      }
    }
  }

  final result = <String>[
    validPrimary,
    ...nonAliasFallbacks,
    ...aliasFallbacks,
  ];
  if (!result.contains(defaultFinalAlias)) {
    result.add(defaultFinalAlias);
  }

  return List<String>.unmodifiable(result);
}

const Set<String> kForbiddenSecretFieldKeys = {
  'apikey',
  'geminiapikey',
  'gemini_api_key',
  'api_key',
  'secret',
  'privatekey',
  'private_key',
  'secretsalt',
  'accesstoken',
};

/// Kiểm tra đệ quy xem payload có chứa key nhạy cảm (API Key, Secret, Private Key...) không.
bool containsForbiddenSecretField(Object? value) {
  if (value is Map) {
    for (final entry in value.entries) {
      final keyLower = entry.key.toString().toLowerCase().trim();
      if (kForbiddenSecretFieldKeys.contains(keyLower)) {
        return true;
      }
      if (containsForbiddenSecretField(entry.value)) {
        return true;
      }
    }
  } else if (value is List) {
    for (final item in value) {
      if (containsForbiddenSecretField(item)) {
        return true;
      }
    }
  }
  return false;
}

/// ============================================================================
/// 1. MODEL CẤU HÌNH RUNTIME & PROMPT TEMPLATES CỦA AI
/// ============================================================================
class AiRuntimeConfig {
  static const int kMinChatHistory = 4;
  static const int kMaxChatHistory = 20;
  static const double kMinTemperature = 0.1;
  static const double kMaxTemperature = 0.8;
  static const int kMaxInstructionChars = 2500;

  static const String defaultChatSystemInstruction = '''
CÁC NGUYÊN TẮC BẮT BUỘC KHI TRẢ LỜI:
1. NGUYÊN TẮC TRUNG THỰC & BÁM SÁT SỐ LIỆU (DATA GROUNDING):
   - Mọi số liệu (thu nhập, chi tiêu, dòng tiền ròng, tỷ lệ tiết kiệm, ngân sách, mục tiêu, trung bình 3 tháng) PHẢI LẤY CHÍNH XÁC từ dữ liệu hệ thống cung cấp.
   - TUYỆT ĐỐI KHÔNG tự bịa đặt, tự đoán mò, hoặc sinh ra các con số tài chính mới nằm ngoài dữ liệu được cung cấp.
   - Nếu trong dữ liệu ghi chú "DỮ LIỆU HẠN CHẾ" hoặc "CHƯA CÓ DỮ LIỆU", hãy trung thực thông báo cho người dùng biết dữ liệu ghi nhận còn ít, cần thêm giao dịch để AI đánh giá chuẩn xác hơn.

2. PHẠM VI NGHIÊM NGẶT (STRICT DOMAIN SCOPE):
   - CHỈ trả lời các câu hỏi liên quan đến tài chính cá nhân của người dùng (thu chi, ví, dòng tiền, ngân sách, tiết kiệm, mục tiêu tài chính, mẹo chi tiêu thông minh).
   - TỪ CHỐI LỊCH SỰ đối với các chủ đề ngoài phạm vi: thời sự, chính trị, viết code/lập trình, giải trí, thời tiết, tư vấn đầu tư mạo hiểm/cổ phiếu/tiền mã hóa rủi ro cao, luật pháp hoặc thuế chuyên sâu.
   - Câu từ chối mẫu: "Xin lỗi bạn, mình là Trợ lý AI Tài chính Cá nhân nên chỉ có thể hỗ trợ các vấn đề liên quan đến quản lý thu chi, ngân sách và kế hoạch tài chính của bạn nhé!"

3. ĐA CẤP ĐỘ PHẢN HỒI (MULTI-TIER RESPONSES):
   - Câu hỏi số liệu nhanh: Trả lời trực diện, ngắn gọn, chính xác trong 1-2 câu.
   - Câu hỏi phân tích: Trình bày rõ ràng cấu trúc Thu - Chi - Dòng tiền ròng - Tỷ lệ tiết kiệm, chỉ ra danh mục chi tiêu lớn nhất và so sánh với tháng trước.
   - Câu hỏi tư vấn cắt giảm: Đưa ra đề xuất cụ thể gắn với danh mục chi nhiều nhất hoặc danh mục đang vượt hạn mức.
   - Câu hỏi lập kế hoạch/mua sắm: PHẢI ĐỐI CHIẾU với "Mức tiết kiệm trung bình 3 tháng gần nhất" và dòng tiền ròng. Nếu mục tiêu vượt quá khả năng thặng dư thực tế, PHẢI PHẢN BIỆN TÍNH KHẢ THI thẳng thắn và đề xuất phương án điều chỉnh.

4. GIỌNG VĂN & ĐỊNH DẠNG:
   - Sử dụng tiếng Việt chuẩn mực, xưng hô "mình" và "bạn", thân thiện, tôn trọng, mang tính đồng hành và khích lệ.
   - Trình bày dạng Markdown với gạch đầu dòng rõ ràng, in đậm các con số quan trọng.
''';

  static const String defaultMonthlyPlanAdvisoryRule = '''
1. TUYỆT ĐỐI KHÔNG TỰ TÍNH TOÁN LẠI SỐ TIỀN. Mọi con số nhắc đến trong lời giải thích PHẢI khớp chính xác với dữ liệu đã được hệ thống tính toán.
2. Bảo toàn chi phí thiết yếu; chỉ đề xuất tinh giản ở các danh mục chi tiêu linh hoạt.
3. Gợi ý hành động cho từng danh mục phải thực tế, cụ thể theo thói quen chi tiêu tại Việt Nam (chia ngân sách theo tuần, ưu đãi thanh toán, nấu ăn tại nhà).
''';

  static const String defaultAnomalyAdvisoryRule = '''
Hãy viết giải thích ngắn gọn bằng tiếng Việt, TỐI ĐA 2 CÂU:
1. Nhận xét về lý do vì sao hệ thống đưa ra cảnh báo này dựa trên số liệu trung vị 90 ngày.
2. Lời khuyên nhẹ nhàng để người dùng xem xét kiểm tra lại giao dịch (vẫn khẳng định người dùng có toàn quyền lưu nếu đây là khoản chi hợp lý).
LƯU Ý: Tuyệt đối không kết luận gian lận, không tư vấn đầu tư, không tự tính toán lại hoặc bịa đặt số liệu mới.
''';

  static const String defaultSavingGoalAdvisoryRule = '''
Đưa ra kế hoạch 3 mục ngắn gọn (Đánh giá khả thi -> Đề xuất cắt giảm gắn với danh mục chi tiêu linh hoạt -> Lộ trình thực hiện theo tháng/tuần), mỗi mục 1-2 câu thực tế, động viên người dùng.
''';

  static const String defaultOcrExtraHints = '''
Ưu tiên dòng "Tổng cộng", "Thành tiền", "Tổng thanh toán", "Total". Không lấy nhầm dòng "Tiền khách đưa" hoặc "Tiền thừa". Nhận diện rõ phương thức thanh toán (Tiền mặt, MoMo, ZaloPay, VNPay, VietQR hoặc tên ngân hàng).
''';

  final int version;
  final bool isEnabled;
  final String primaryModel;
  final List<String> fallbackModels;
  final double temperature;
  final int maxChatHistoryMessages;
  final String chatSystemInstruction;
  final String monthlyPlanAdvisoryRule;
  final String anomalyAdvisoryRule;
  final String savingGoalAdvisoryRule;
  final String ocrExtraHints;
  final Map<String, List<String>> customSuggestedChatPrompts;
  final DateTime? updatedAt;
  final String? updatedBy;
  final String? changeNote;

  const AiRuntimeConfig({
    this.version = 1,
    this.isEnabled = true,
    this.primaryModel = kDefaultPrimaryModel,
    this.fallbackModels = kDefaultFallbackModels,
    this.temperature = 0.35,
    this.maxChatHistoryMessages = 10,
    this.chatSystemInstruction = defaultChatSystemInstruction,
    this.monthlyPlanAdvisoryRule = defaultMonthlyPlanAdvisoryRule,
    this.anomalyAdvisoryRule = defaultAnomalyAdvisoryRule,
    this.savingGoalAdvisoryRule = defaultSavingGoalAdvisoryRule,
    this.ocrExtraHints = defaultOcrExtraHints,
    this.customSuggestedChatPrompts = const {},
    this.updatedAt,
    this.updatedBy,
    this.changeNote,
  });

  static const String kDefaultPrimaryModel = 'gemini-3.5-flash';
  static const List<String> kDefaultFallbackModels = [
    'gemini-3.5-flash-lite',
    'gemini-3.6-flash',
    'gemini-flash-latest',
  ];

  factory AiRuntimeConfig.defaults() => const AiRuntimeConfig();

  List<String> get effectiveModelChain => sanitizeGeminiModelChain(
        primaryModel: primaryModel,
        fallbackModels: fallbackModels,
      );

  static String _sanitizeText(String? input, String fallback, int maxLen) {
    if (input == null) return fallback;
    final trimmed = input.trim();
    if (trimmed.isEmpty) return fallback;
    return trimmed.length <= maxLen ? trimmed : trimmed.substring(0, maxLen);
  }

  factory AiRuntimeConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null || map.isEmpty) {
      return AiRuntimeConfig.defaults();
    }

    final payload = map['payload'] is Map
        ? Map<String, dynamic>.from(map['payload'] as Map)
        : map;

    final rawPrimary = (payload['primaryModel'] as String?)?.trim() ?? '';
    final primaryDesc = findGeminiModelDescriptor(rawPrimary);
    final safePrimary =
        (primaryDesc != null && !primaryDesc.isMutableAlias)
            ? primaryDesc.modelId
            : 'gemini-3.5-flash';

    final rawFallbacks = (payload['fallbackModels'] as List<dynamic>?)
            ?.map((e) => e.toString().trim())
            .where((e) => isSupportedGeminiModelId(e) && e != safePrimary)
            .toList() ??
        const [
          'gemini-3.5-flash-lite',
          'gemini-3.6-flash',
          'gemini-flash-latest',
        ];

    final rawTemp = (payload['temperature'] as num?)?.toDouble() ?? 0.35;
    final safeTemp = double.parse(
      rawTemp.clamp(kMinTemperature, kMaxTemperature).toStringAsFixed(2),
    );

    final rawMaxHist = (payload['maxChatHistoryMessages'] as num?)?.toInt() ?? 10;
    final safeMaxHist = rawMaxHist.clamp(kMinChatHistory, kMaxChatHistory);

    final promptsMap = payload['prompts'] is Map
        ? Map<String, dynamic>.from(payload['prompts'] as Map)
        : payload;

    final rawSuggested = payload['customSuggestedChatPrompts'];
    final parsedSuggested = <String, List<String>>{};
    if (rawSuggested is Map) {
      for (final entry in rawSuggested.entries) {
        final key = entry.key.toString().trim();
        if (entry.value is List) {
          final list = (entry.value as List)
              .map((e) => e.toString().trim())
              .where((s) => s.isNotEmpty && s.length <= 120)
              .take(6)
              .toList();
          if (list.isNotEmpty) {
            parsedSuggested[key] = list;
          }
        }
      }
    }

    return AiRuntimeConfig(
      version: (map['version'] as num?)?.toInt() ?? 1,
      isEnabled: payload['isEnabled'] != false,
      primaryModel: safePrimary,
      fallbackModels: rawFallbacks.isEmpty
          ? const [
              'gemini-3.5-flash-lite',
              'gemini-3.6-flash',
              'gemini-flash-latest',
            ]
          : rawFallbacks,
      temperature: safeTemp,
      maxChatHistoryMessages: safeMaxHist,
      chatSystemInstruction: _sanitizeText(
        promptsMap['chatSystemInstruction'] as String?,
        defaultChatSystemInstruction,
        kMaxInstructionChars,
      ),
      monthlyPlanAdvisoryRule: _sanitizeText(
        promptsMap['monthlyPlanAdvisoryRule'] as String?,
        defaultMonthlyPlanAdvisoryRule,
        1500,
      ),
      anomalyAdvisoryRule: _sanitizeText(
        promptsMap['anomalyAdvisoryRule'] as String?,
        defaultAnomalyAdvisoryRule,
        600,
      ),
      savingGoalAdvisoryRule: _sanitizeText(
        promptsMap['savingGoalAdvisoryRule'] as String?,
        defaultSavingGoalAdvisoryRule,
        800,
      ),
      ocrExtraHints: _sanitizeText(
        promptsMap['ocrExtraHints'] as String?,
        defaultOcrExtraHints,
        800,
      ),
      customSuggestedChatPrompts: parsedSuggested,
      updatedAt: map['updatedAt'] != null
          ? DateTime.tryParse(map['updatedAt'].toString())
          : null,
      updatedBy: map['updatedBy'] as String?,
      changeNote: map['changeNote'] as String?,
    );
  }

  /// Bản đồ dữ liệu thuần (không chứa timestamp/version) để tính Canonical SHA-256 Hash
  Map<String, dynamic> toPayloadMap() {
    return {
      'isEnabled': isEnabled,
      'primaryModel': primaryModel,
      'fallbackModels': fallbackModels,
      'temperature': temperature,
      'maxChatHistoryMessages': maxChatHistoryMessages,
      'prompts': {
        'chatSystemInstruction': chatSystemInstruction.trim(),
        'monthlyPlanAdvisoryRule': monthlyPlanAdvisoryRule.trim(),
        'anomalyAdvisoryRule': anomalyAdvisoryRule.trim(),
        'savingGoalAdvisoryRule': savingGoalAdvisoryRule.trim(),
        'ocrExtraHints': ocrExtraHints.trim(),
      },
      'customSuggestedChatPrompts': customSuggestedChatPrompts,
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'version': version,
      ...toPayloadMap(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      if (updatedBy != null) 'updatedBy': updatedBy,
      if (changeNote != null) 'changeNote': changeNote,
    };
  }

  /// Kiểm tra hợp lệ một Map cấu hình thô trước khi lưu nháp hoặc Publish
  static List<String> validateRawInput(Map<String, dynamic> raw) {
    final errors = <String>[];
    if (containsForbiddenSecretField(raw)) {
      errors.add(
        'Tuyệt đối không được đưa API Key hoặc khóa bí mật vào cấu hình động.',
      );
    }

    final primary = (raw['primaryModel'] as String?)?.trim() ?? '';
    if (!isSupportedGeminiModelId(primary)) {
      errors.add('Model chính "$primary" không nằm trong danh sách Whitelist hỗ trợ.');
    } else if (isMutableAliasGeminiModelId(primary)) {
      errors.add('Không được chọn alias động "$primary" làm model chính.');
    }

    final fallbacks = raw['fallbackModels'];
    if (fallbacks is List) {
      final validFallbacks = <String>[];
      for (final fb in fallbacks) {
        final fbStr = fb.toString().trim();
        if (!isSupportedGeminiModelId(fbStr)) {
          errors.add('Model dự phòng "$fbStr" không nằm trong danh sách Whitelist.');
        } else {
          validFallbacks.add(fbStr);
        }
      }
      final nonAliasFallbacks = validFallbacks
          .where((id) => !isMutableAliasGeminiModelId(id))
          .toList();
      if (validFallbacks.isNotEmpty && nonAliasFallbacks.isEmpty) {
        errors.add(
          'Không được chỉ sử dụng alias động (gemini-flash-latest) làm cơ chế fallback duy nhất.',
        );
      }
    }

    final temp = (raw['temperature'] as num?)?.toDouble();
    if (temp != null && (temp < kMinTemperature || temp > kMaxTemperature)) {
      errors.add(
        'Temperature phải nằm trong khoảng $kMinTemperature đến $kMaxTemperature.',
      );
    }

    final maxHist = (raw['maxChatHistoryMessages'] as num?)?.toInt();
    if (maxHist != null &&
        (maxHist < kMinChatHistory || maxHist > kMaxChatHistory)) {
      errors.add(
        'Số tin nhắn lịch sử hội thoại phải từ $kMinChatHistory đến $kMaxChatHistory.',
      );
    }

    final prompts = raw['prompts'] is Map
        ? Map<String, dynamic>.from(raw['prompts'] as Map)
        : raw;
    final chatInst = (prompts['chatSystemInstruction'] as String?)?.trim() ?? '';
    if (chatInst.isEmpty) {
      errors.add('System Instruction của Trợ lý AI không được để trống.');
    } else if (chatInst.length > kMaxInstructionChars) {
      errors.add(
        'System Instruction vượt quá giới hạn $kMaxInstructionChars ký tự.',
      );
    }

    return errors;
  }

  AiRuntimeConfig copyWith({
    int? version,
    bool? isEnabled,
    String? primaryModel,
    List<String>? fallbackModels,
    double? temperature,
    int? maxChatHistoryMessages,
    String? chatSystemInstruction,
    String? monthlyPlanAdvisoryRule,
    String? anomalyAdvisoryRule,
    String? savingGoalAdvisoryRule,
    String? ocrExtraHints,
    Map<String, List<String>>? customSuggestedChatPrompts,
    DateTime? updatedAt,
    String? updatedBy,
    String? changeNote,
  }) {
    return AiRuntimeConfig(
      version: version ?? this.version,
      isEnabled: isEnabled ?? this.isEnabled,
      primaryModel: primaryModel ?? this.primaryModel,
      fallbackModels: fallbackModels ?? this.fallbackModels,
      temperature: temperature ?? this.temperature,
      maxChatHistoryMessages:
          maxChatHistoryMessages ?? this.maxChatHistoryMessages,
      chatSystemInstruction:
          chatSystemInstruction ?? this.chatSystemInstruction,
      monthlyPlanAdvisoryRule:
          monthlyPlanAdvisoryRule ?? this.monthlyPlanAdvisoryRule,
      anomalyAdvisoryRule: anomalyAdvisoryRule ?? this.anomalyAdvisoryRule,
      savingGoalAdvisoryRule:
          savingGoalAdvisoryRule ?? this.savingGoalAdvisoryRule,
      ocrExtraHints: ocrExtraHints ?? this.ocrExtraHints,
      customSuggestedChatPrompts:
          customSuggestedChatPrompts ?? this.customSuggestedChatPrompts,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
      changeNote: changeNote ?? this.changeNote,
    );
  }
}

/// ============================================================================
/// 2. MODEL BỘ THAM SỐ & NGƯỠNG ĐỊNH LƯỢNG TÀI CHÍNH (`financial_heuristics`)
/// ============================================================================
class FinancialHeuristicsConfig {
  final int version;

  // Nhóm 1: Phát hiện vấn đề chi tiêu tháng (FinancialAnalyticsService)
  final double categorySpikeRatio; // Mặc định 0.30 (30%) [0.15 .. 0.60]
  final double categoryIncomeShareThreshold; // Mặc định 0.25 (25%) [0.15 .. 0.50]
  final double minRecommendedSavingRate; // Mặc định 0.20 (20%) [0.05 .. 0.40]
  final double incomeDropWarningRatio; // Mặc định 0.20 (20%) [0.10 .. 0.40]
  final double incomeDropCriticalRatio; // Mặc định 0.40 (40%) [0.25 .. 0.70]

  // Nhóm 2: Lập kế hoạch tài chính tháng bậc thang (FinancialAnalyticsService)
  final double defaultSavingRateNoGoal; // Mặc định 0.15 (15%) [0.05 .. 0.35]
  final double flexibleSpendFloorRatio; // Mặc định 0.70 (70%) [0.50 .. 0.85]
  final double planBudgetAdherenceWeight; // Mặc định 0.60 (60%) [0.40 .. 0.80]

  // Nhóm 3: Dự báo danh mục, Ngân sách & Điểm sức khỏe (FinancialForecastService)
  final double budgetNearLimitRatio; // Mặc định 0.80 (80%) [0.70 .. 0.95]
  final double categoryForecastWarningRatio; // Mặc định 1.30 (1.3x) [1.15 .. 1.60]
  final double categoryForecastCriticalRatio; // Mặc định 1.60 (1.6x) [1.40 .. 2.50]
  final double categoryForecastMinDiffVnd; // Mặc định 100000 [50000 .. 500000]
  final int healthNegativeBalancePenalty; // Mặc định 25 [10 .. 40]
  final int healthBudgetExceededPenalty; // Mặc định 15 [5 .. 25]
  final int healthBudgetAtRiskPenalty; // Mặc định 10 [5 .. 20]

  // Nhóm 4: Cảnh báo giao dịch đơn lẻ bất thường (TransactionIntelligenceService)
  final double txAnomalyMinDiffVnd; // Mặc định 100000 [50000 .. 500000]
  final double txAnomalyWarningMultiplier; // Mặc định 2.0 (2.0x) [1.5 .. 3.5]
  final double txAnomalyCriticalMultiplier; // Mặc định 4.0 (4.0x) [3.0 .. 6.0]

  final DateTime? updatedAt;
  final String? updatedBy;
  final String? changeNote;

  const FinancialHeuristicsConfig({
    this.version = 1,
    this.categorySpikeRatio = 0.30,
    this.categoryIncomeShareThreshold = 0.25,
    this.minRecommendedSavingRate = 0.20,
    this.incomeDropWarningRatio = 0.20,
    this.incomeDropCriticalRatio = 0.40,
    this.defaultSavingRateNoGoal = 0.15,
    this.flexibleSpendFloorRatio = 0.70,
    this.planBudgetAdherenceWeight = 0.60,
    this.budgetNearLimitRatio = 0.80,
    this.categoryForecastWarningRatio = 1.30,
    this.categoryForecastCriticalRatio = 1.60,
    this.categoryForecastMinDiffVnd = 100000.0,
    this.healthNegativeBalancePenalty = 25,
    this.healthBudgetExceededPenalty = 15,
    this.healthBudgetAtRiskPenalty = 10,
    this.txAnomalyMinDiffVnd = 100000.0,
    this.txAnomalyWarningMultiplier = 2.0,
    this.txAnomalyCriticalMultiplier = 4.0,
    this.updatedAt,
    this.updatedBy,
    this.changeNote,
  });

  factory FinancialHeuristicsConfig.defaults() =>
      const FinancialHeuristicsConfig();

  /// Trọng số điểm tuân thủ tiết kiệm luôn tự động bằng `1.0 - planBudgetAdherenceWeight`
  double get planSavingAdherenceWeight =>
      double.parse((1.0 - planBudgetAdherenceWeight).toStringAsFixed(2));

  static double _clampDouble(
    Object? raw,
    double fallback,
    double min,
    double max,
  ) {
    final val = (raw is num) ? raw.toDouble() : fallback;
    if (val.isNaN || val.isInfinite) return fallback;
    return double.parse(val.clamp(min, max).toStringAsFixed(4));
  }

  static int _clampInt(Object? raw, int fallback, int min, int max) {
    final val = (raw is num) ? raw.toInt() : fallback;
    return val.clamp(min, max);
  }

  factory FinancialHeuristicsConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null || map.isEmpty) {
      return FinancialHeuristicsConfig.defaults();
    }

    final p = map['payload'] is Map
        ? Map<String, dynamic>.from(map['payload'] as Map)
        : map;

    final minRecSaving = _clampDouble(
      p['minRecommendedSavingRate'],
      0.20,
      0.05,
      0.40,
    );
    final rawDefSaving = _clampDouble(
      p['defaultSavingRateNoGoal'],
      0.15,
      0.05,
      0.35,
    );
    // Đảm bảo tỷ lệ tiết kiệm mặc định khi chưa có mục tiêu không vượt quá mức chuẩn khuyến nghị
    final safeDefSaving =
        rawDefSaving > minRecSaving ? minRecSaving : rawDefSaving;

    final incWarn = _clampDouble(p['incomeDropWarningRatio'], 0.20, 0.10, 0.40);
    final rawIncCrit = _clampDouble(
      p['incomeDropCriticalRatio'],
      0.40,
      0.25,
      0.70,
    );
    final safeIncCrit = rawIncCrit < (incWarn + 0.10)
        ? double.parse((incWarn + 0.10).clamp(0.25, 0.70).toStringAsFixed(2))
        : rawIncCrit;

    final catWarn = _clampDouble(
      p['categoryForecastWarningRatio'],
      1.30,
      1.15,
      1.60,
    );
    final rawCatCrit = _clampDouble(
      p['categoryForecastCriticalRatio'],
      1.60,
      1.40,
      2.50,
    );
    final safeCatCrit = rawCatCrit < (catWarn + 0.15)
        ? double.parse((catWarn + 0.15).clamp(1.40, 2.50).toStringAsFixed(2))
        : rawCatCrit;

    final txWarn = _clampDouble(
      p['txAnomalyWarningMultiplier'],
      2.0,
      1.5,
      3.5,
    );
    final rawTxCrit = _clampDouble(
      p['txAnomalyCriticalMultiplier'],
      4.0,
      3.0,
      6.0,
    );
    final safeTxCrit = rawTxCrit < (txWarn + 1.0)
        ? double.parse((txWarn + 1.0).clamp(3.0, 6.0).toStringAsFixed(2))
        : rawTxCrit;

    return FinancialHeuristicsConfig(
      version: (map['version'] as num?)?.toInt() ?? 1,
      categorySpikeRatio: _clampDouble(
        p['categorySpikeRatio'],
        0.30,
        0.15,
        0.60,
      ),
      categoryIncomeShareThreshold: _clampDouble(
        p['categoryIncomeShareThreshold'],
        0.25,
        0.15,
        0.50,
      ),
      minRecommendedSavingRate: minRecSaving,
      incomeDropWarningRatio: incWarn,
      incomeDropCriticalRatio: safeIncCrit,
      defaultSavingRateNoGoal: safeDefSaving,
      flexibleSpendFloorRatio: _clampDouble(
        p['flexibleSpendFloorRatio'],
        0.70,
        0.50,
        0.85,
      ),
      planBudgetAdherenceWeight: _clampDouble(
        p['planBudgetAdherenceWeight'],
        0.60,
        0.40,
        0.80,
      ),
      budgetNearLimitRatio: _clampDouble(
        p['budgetNearLimitRatio'],
        0.80,
        0.70,
        0.95,
      ),
      categoryForecastWarningRatio: catWarn,
      categoryForecastCriticalRatio: safeCatCrit,
      categoryForecastMinDiffVnd: _clampDouble(
        p['categoryForecastMinDiffVnd'],
        100000.0,
        50000.0,
        500000.0,
      ),
      healthNegativeBalancePenalty: _clampInt(
        p['healthNegativeBalancePenalty'],
        25,
        10,
        40,
      ),
      healthBudgetExceededPenalty: _clampInt(
        p['healthBudgetExceededPenalty'],
        15,
        5,
        25,
      ),
      healthBudgetAtRiskPenalty: _clampInt(
        p['healthBudgetAtRiskPenalty'],
        10,
        5,
        20,
      ),
      txAnomalyMinDiffVnd: _clampDouble(
        p['txAnomalyMinDiffVnd'],
        100000.0,
        50000.0,
        500000.0,
      ),
      txAnomalyWarningMultiplier: txWarn,
      txAnomalyCriticalMultiplier: safeTxCrit,
      updatedAt: map['updatedAt'] != null
          ? DateTime.tryParse(map['updatedAt'].toString())
          : null,
      updatedBy: map['updatedBy'] as String?,
      changeNote: map['changeNote'] as String?,
    );
  }

  Map<String, dynamic> toPayloadMap() {
    return {
      'categorySpikeRatio': categorySpikeRatio,
      'categoryIncomeShareThreshold': categoryIncomeShareThreshold,
      'minRecommendedSavingRate': minRecommendedSavingRate,
      'incomeDropWarningRatio': incomeDropWarningRatio,
      'incomeDropCriticalRatio': incomeDropCriticalRatio,
      'defaultSavingRateNoGoal': defaultSavingRateNoGoal,
      'flexibleSpendFloorRatio': flexibleSpendFloorRatio,
      'planBudgetAdherenceWeight': planBudgetAdherenceWeight,
      'budgetNearLimitRatio': budgetNearLimitRatio,
      'categoryForecastWarningRatio': categoryForecastWarningRatio,
      'categoryForecastCriticalRatio': categoryForecastCriticalRatio,
      'categoryForecastMinDiffVnd': categoryForecastMinDiffVnd,
      'healthNegativeBalancePenalty': healthNegativeBalancePenalty,
      'healthBudgetExceededPenalty': healthBudgetExceededPenalty,
      'healthBudgetAtRiskPenalty': healthBudgetAtRiskPenalty,
      'txAnomalyMinDiffVnd': txAnomalyMinDiffVnd,
      'txAnomalyWarningMultiplier': txAnomalyWarningMultiplier,
      'txAnomalyCriticalMultiplier': txAnomalyCriticalMultiplier,
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'version': version,
      ...toPayloadMap(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      if (updatedBy != null) 'updatedBy': updatedBy,
      if (changeNote != null) 'changeNote': changeNote,
    };
  }

  /// Kiểm tra tính hợp lệ và tính nhất quán của dữ liệu thô do Admin nhập (khớp 1:1 với Server)
  static List<String> validateRawInput(Map<String, dynamic> raw) {
    final errors = <String>[];
    if (containsForbiddenSecretField(raw)) {
      errors.add(
        'Tuyệt đối không được đưa API Key hoặc khóa bí mật vào cấu hình tham số định lượng.',
      );
    }

    void checkDoubleRange(String key, String label, double min, double max) {
      final rawVal = raw[key];
      if (rawVal is! num) {
        errors.add('$label phải là số trong khoảng $min đến $max.');
        return;
      }
      final v = rawVal.toDouble();
      if (v.isNaN || v.isInfinite || v < min || v > max) {
        errors.add('$label phải nằm trong khoảng $min đến $max.');
      }
    }

    void checkIntRange(String key, String label, int min, int max) {
      final rawVal = raw[key];
      if (rawVal is! num) {
        errors.add('$label phải là số nguyên trong khoảng $min đến $max.');
        return;
      }
      final d = rawVal.toDouble();
      if (d.isNaN || d.isInfinite || d != rawVal.toInt().toDouble()) {
        errors.add('$label phải là số nguyên hợp lệ.');
        return;
      }
      final iv = rawVal.toInt();
      if (iv < min || iv > max) {
        errors.add('$label phải nằm trong khoảng $min đến $max.');
      }
    }

    checkDoubleRange('categorySpikeRatio', 'Ngưỡng đột biến danh mục', 0.15, 0.60);
    checkDoubleRange(
      'categoryIncomeShareThreshold',
      'Ngưỡng tỷ trọng danh mục/thu nhập',
      0.15,
      0.50,
    );
    checkDoubleRange(
      'minRecommendedSavingRate',
      'Tỷ lệ tiết kiệm khuyến nghị',
      0.05,
      0.40,
    );
    checkDoubleRange(
      'incomeDropWarningRatio',
      'Ngưỡng cảnh báo sụt giảm thu nhập',
      0.10,
      0.40,
    );
    checkDoubleRange(
      'incomeDropCriticalRatio',
      'Ngưỡng nghiêm trọng sụt giảm thu nhập',
      0.25,
      0.70,
    );
    checkDoubleRange(
      'defaultSavingRateNoGoal',
      'Tỷ lệ tiết kiệm mặc định khi chưa có mục tiêu',
      0.05,
      0.35,
    );
    checkDoubleRange(
      'flexibleSpendFloorRatio',
      'Ngưỡng sàn chi tiêu linh hoạt',
      0.50,
      0.85,
    );
    checkDoubleRange(
      'planBudgetAdherenceWeight',
      'Trọng số điểm tuân thủ ngân sách',
      0.40,
      0.80,
    );
    checkDoubleRange(
      'budgetNearLimitRatio',
      'Ngưỡng cảnh báo sắp vượt ngân sách',
      0.70,
      0.95,
    );
    checkDoubleRange(
      'categoryForecastWarningRatio',
      'Ngưỡng cảnh báo dự báo danh mục tháng',
      1.15,
      1.60,
    );
    checkDoubleRange(
      'categoryForecastCriticalRatio',
      'Ngưỡng nghiêm trọng dự báo danh mục tháng',
      1.40,
      2.50,
    );
    checkDoubleRange(
      'categoryForecastMinDiffVnd',
      'Chênh lệch tối thiểu cảnh báo dự báo danh mục',
      50000.0,
      500000.0,
    );
    checkIntRange(
      'healthNegativeBalancePenalty',
      'Điểm trừ số dư dự báo âm',
      10,
      40,
    );
    checkIntRange(
      'healthBudgetExceededPenalty',
      'Điểm trừ ngân sách vượt hạn mức',
      5,
      25,
    );
    checkIntRange(
      'healthBudgetAtRiskPenalty',
      'Điểm trừ ngân sách có nguy cơ vượt',
      5,
      20,
    );
    checkDoubleRange(
      'txAnomalyMinDiffVnd',
      'Chênh lệch tối thiểu giao dịch bất thường',
      50000.0,
      500000.0,
    );
    checkDoubleRange(
      'txAnomalyWarningMultiplier',
      'Hệ số cảnh báo giao dịch lẻ bất thường',
      1.5,
      3.5,
    );
    checkDoubleRange(
      'txAnomalyCriticalMultiplier',
      'Hệ số nghiêm trọng giao dịch lẻ bất thường',
      3.0,
      6.0,
    );

    final minRec = (raw['minRecommendedSavingRate'] as num?)?.toDouble();
    final defSav = (raw['defaultSavingRateNoGoal'] as num?)?.toDouble();
    if (minRec != null && defSav != null && defSav > minRec + 1e-9) {
      errors.add(
        'Tỷ lệ tiết kiệm mặc định khi chưa có mục tiêu ($defSav) không được lớn hơn tỷ lệ tiết kiệm khuyến nghị chuẩn ($minRec).',
      );
    }

    final incWarn = (raw['incomeDropWarningRatio'] as num?)?.toDouble();
    final incCrit = (raw['incomeDropCriticalRatio'] as num?)?.toDouble();
    if (incWarn != null && incCrit != null && incCrit + 1e-9 < incWarn + 0.10) {
      errors.add(
        'Ngưỡng sụt giảm thu nhập nghiêm trọng ($incCrit) phải lớn hơn ngưỡng cảnh báo ($incWarn) ít nhất 0.10.',
      );
    }

    final catWarn = (raw['categoryForecastWarningRatio'] as num?)?.toDouble();
    final catCrit = (raw['categoryForecastCriticalRatio'] as num?)?.toDouble();
    if (catWarn != null && catCrit != null && catCrit + 1e-9 < catWarn + 0.15) {
      errors.add(
        'Ngưỡng dự báo nghiêm trọng ($catCrit) phải lớn hơn ngưỡng cảnh báo ($catWarn) ít nhất 0.15.',
      );
    }

    final txWarn = (raw['txAnomalyWarningMultiplier'] as num?)?.toDouble();
    final txCrit = (raw['txAnomalyCriticalMultiplier'] as num?)?.toDouble();
    if (txWarn != null && txCrit != null && txCrit + 1e-9 < txWarn + 1.0) {
      errors.add(
        'Hệ số giao dịch bất thường nghiêm trọng (${txCrit}x) phải lớn hơn hệ số cảnh báo (${txWarn}x) ít nhất 1.0x.',
      );
    }

    return errors;
  }
}

/// ============================================================================
/// 3. MODEL TỪ ĐIỂN NHẬN DIỆN GIAO DỊCH & HÓA ĐƠN OCR (`transaction_rules`)
/// Phân tách rõ Nhóm ngữ nghĩa hệ thống (Canonical Semantic Groups) và
/// Danh mục/Ví cá nhân của từng người dùng.
/// ============================================================================

/// 7 Nhóm ngữ nghĩa chi tiêu chuẩn của hệ thống (tuyệt đối không chứa categoryId cá nhân)
const Map<String, String> kCanonicalExpenseGroupLabels = {
  'di chuyen': 'Di chuyển & Giao thông',
  'an uong': 'Ăn uống & Cà phê',
  'mua sam': 'Mua sắm & Siêu thị',
  'hoa don': 'Hóa đơn & Tiện ích',
  'suc khoe': 'Sức khỏe & Y tế',
  'giai tri': 'Giải trí & Du lịch',
  'giao duc': 'Giáo dục & Học tập',
};

/// 2 Nhóm ngữ nghĩa thu nhập chuẩn của hệ thống
const Map<String, String> kCanonicalIncomeGroupLabels = {
  'luong': 'Lương & Thu nhập chính',
  'thuong': 'Thưởng & Phụ cấp',
};

/// 3 Loại ví chuẩn để ánh xạ với nhà cung cấp thanh toán trên hóa đơn
const List<String> kCanonicalWalletTypes = ['cash', 'eWallet', 'bank'];

/// Bộ từ khóa chi tiêu mặc định được bảo vệ (chỉ đọc, không thể bị vô hiệu hóa hoặc ghi đè).
const Map<String, List<String>> kProtectedBuiltInExpenseKeywords = {
  'di chuyen': [
    'grab',
    'be',
    'xanh sm',
    'gojek',
    'taxi',
    'xang',
    'xe bus',
    've xe',
    'gui xe',
    'bai xe',
    'di chuyen',
    'giao thong',
  ],
  'an uong': [
    'highlands',
    'starbucks',
    'ca phe',
    'pho',
    'com',
    'tra sua',
    'kfc',
    'mcdonalds',
    'lotte',
    'nha hang',
    'an sang',
    'an trua',
    'an toi',
    'banh mi',
    'nuoc ep',
    'tai xin',
    'quan an',
    'bun',
    'lau',
    'nuong',
    'tra',
    'banh',
    'food',
    'coffee',
    'sua da',
    'bac xiu',
    'matcha',
    'sinh to',
  ],
  'mua sam': [
    'shopee',
    'lazada',
    'tiki',
    'sieu thi',
    'quan ao',
    'giay',
    'bach hoa xanh',
    'winmart',
    'circle k',
    '7-eleven',
    'mua sam',
    'thoi trang',
    'my pham',
    'shopping',
  ],
  'hoa don': [
    'dien',
    'nuoc',
    'internet',
    'wifi',
    'truyen hinh',
    'tien dien',
    'tien nuoc',
    'tien nha',
    'rac',
    'hoa don',
    'dich vu',
    'bill',
  ],
  'suc khoe': [
    'thuoc',
    'nha thuoc',
    'benh vien',
    'phong kham',
    'kham benh',
    'pharmedic',
    'pharmacity',
    'long chau',
    'y te',
    'suc khoe',
  ],
  'giai tri': [
    'xem phim',
    'cgv',
    'lotte cinema',
    'du lich',
    'game',
    've xem phim',
    'giai tri',
    'cinema',
    'movie',
  ],
  'giao duc': [
    'hoc phi',
    'sach',
    'khoa hoc',
    'giao duc',
    'truong hoc',
    'hoc tap',
    'hoc tieng anh',
  ],
};

/// Bộ từ khóa thu nhập mặc định được bảo vệ (chỉ đọc, không thể bị vô hiệu hóa hoặc ghi đè).
const Map<String, List<String>> kProtectedBuiltInIncomeKeywords = {
  'thuong': ['thuong', 'tien thuong', 'bonus', 'khen thuong', 'thuong tet'],
  'luong': [
    'luong',
    'thuong',
    'income',
    'salary',
    'tien luong',
    'tien thuong',
    'freelance',
    'hoa hong',
    'ban hang',
    'doanh thu',
    'thu nhap',
    'bonus',
  ],
};

/// Khóa nhà cung cấp thanh toán mặc định hệ thống được bảo vệ (không cho phép ghi đè).
const List<String> kProtectedPaymentProviderKeys = [
  'cash',
  'momo',
  'zalopay',
  'shopeepay',
  'vnpay',
  'viettel_money',
  'apple_pay',
  'google_pay',
  'samsung_pay',
  'mbbank',
  'vietcombank',
  'techcombank',
  'vietinbank',
  'bidv',
  'agribank',
  'acb',
  'tpbank',
  'vpbank',
  'sacombank',
  'vib',
  'hdbank',
  'shb',
  'msb',
  'ocb',
  'seabank',
  'lpbank',
  'eximbank',
  'cake',
  'timo',
  'generic_bank',
  'generic_ewallet',
];

/// Chuẩn hóa chuỗi tiếng Việt không dấu, chữ thường để đối chiếu từ khóa
String normalizeVietnameseKeyword(String input) {
  var str = input.toLowerCase().trim();
  const vietnameseSigns = [
    'aàáạảãâầấậẩẫăằắặẳẵ',
    'eèéẹẻẽêềếệểễ',
    'iìíịỉĩ',
    'oòóọỏõôồốộổỗơờớợởỡ',
    'uùúụủũưừứựửữ',
    'yỳýỵỷỹ',
    'dđ',
  ];
  for (var i = 0; i < vietnameseSigns.length; i++) {
    for (var j = 1; j < vietnameseSigns[i].length; j++) {
      str = str.replaceAll(vietnameseSigns[i][j], vietnameseSigns[i][0]);
    }
  }
  return str.replaceAll(RegExp(r'\s+'), ' ');
}

/// Quy tắc nhà cung cấp thanh toán bổ sung cho OCR
class CustomPaymentProviderRule {
  final String key;
  final String displayLabel;
  final String walletType; // 'cash' | 'eWallet' | 'bank'
  final List<String> receiptKeywords;
  final List<String> walletNameAliases;
  final bool isActive;

  const CustomPaymentProviderRule({
    required this.key,
    required this.displayLabel,
    required this.walletType,
    required this.receiptKeywords,
    required this.walletNameAliases,
    this.isActive = true,
  });

  factory CustomPaymentProviderRule.fromMap(Map<String, dynamic> map) {
    final rawType = (map['walletType'] as String?)?.trim() ?? 'bank';
    final safeType = kCanonicalWalletTypes.contains(rawType) ? rawType : 'bank';

    final rawKeywords = (map['receiptKeywords'] as List<dynamic>?)
            ?.map((e) => normalizeVietnameseKeyword(e.toString()))
            .where((s) => s.length >= 2)
            .toSet()
            .toList() ??
        const [];

    final rawAliases = (map['walletNameAliases'] as List<dynamic>?)
            ?.map((e) => normalizeVietnameseKeyword(e.toString()))
            .where((s) => s.length >= 2)
            .toSet()
            .toList() ??
        const [];

    return CustomPaymentProviderRule(
      key: normalizeVietnameseKeyword((map['key'] as String?) ?? '')
          .replaceAll(' ', '_'),
      displayLabel: ((map['displayLabel'] as String?) ?? '').trim(),
      walletType: safeType,
      receiptKeywords: rawKeywords,
      walletNameAliases: rawAliases.isEmpty ? rawKeywords : rawAliases,
      isActive: map['isActive'] != false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'key': key,
      'displayLabel': displayLabel,
      'walletType': walletType,
      'receiptKeywords': receiptKeywords,
      'walletNameAliases': walletNameAliases,
      'isActive': isActive,
    };
  }
}

/// Kết quả kiểm tra xung đột từ khóa
class KeywordConflictCheckResult {
  final bool isValid;
  final String normalizedKeyword;
  final String? errorMessage;
  final String? warningMessage;
  final String? conflictingGroupKey;

  const KeywordConflictCheckResult({
    required this.isValid,
    required this.normalizedKeyword,
    this.errorMessage,
    this.warningMessage,
    this.conflictingGroupKey,
  });
}

/// Cấu hình mở rộng cho `TransactionIntelligenceService`
class TransactionIntelligenceConfig {
  final int version;
  final Map<String, List<String>> addedExpenseKeywords;
  final Map<String, List<String>> addedIncomeKeywords;
  final List<String> disabledBuiltInKeywords;
  final List<String> disabledAdminKeywords;
  final List<CustomPaymentProviderRule> customPaymentProviders;
  final DateTime? updatedAt;
  final String? updatedBy;
  final String? changeNote;

  const TransactionIntelligenceConfig({
    this.version = 1,
    this.addedExpenseKeywords = const {},
    this.addedIncomeKeywords = const {},
    this.disabledBuiltInKeywords = const [],
    this.disabledAdminKeywords = const [],
    this.customPaymentProviders = const [],
    this.updatedAt,
    this.updatedBy,
    this.changeNote,
  });

  factory TransactionIntelligenceConfig.defaults() =>
      const TransactionIntelligenceConfig();

  static Map<String, List<String>> _parseKeywordMap(
    Object? raw,
    Iterable<String> allowedGroupKeys,
  ) {
    final result = <String, List<String>>{};
    if (raw is! Map) return result;
    final allowedSet = allowedGroupKeys.toSet();
    for (final entry in raw.entries) {
      final groupKey = normalizeVietnameseKeyword(entry.key.toString());
      if (!allowedSet.contains(groupKey)) continue;
      if (entry.value is List) {
        final normalizedList = (entry.value as List)
            .map((e) => normalizeVietnameseKeyword(e.toString()))
            .where((s) => s.length >= 2 && s.length <= 60)
            .toSet()
            .toList()
          ..sort();
        if (normalizedList.isNotEmpty) {
          result[groupKey] = normalizedList;
        }
      }
    }
    return result;
  }

  factory TransactionIntelligenceConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null || map.isEmpty) {
      return TransactionIntelligenceConfig.defaults();
    }
    final p = map['payload'] is Map
        ? Map<String, dynamic>.from(map['payload'] as Map)
        : map;

    final expMap = _parseKeywordMap(
      p['addedExpenseKeywords'],
      kCanonicalExpenseGroupLabels.keys,
    );
    final incMap = _parseKeywordMap(
      p['addedIncomeKeywords'],
      kCanonicalIncomeGroupLabels.keys,
    );

    final disabledList = (p['disabledBuiltInKeywords'] as List<dynamic>?)
            ?.map((e) => normalizeVietnameseKeyword(e.toString()))
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList() ??
        const [];

    final disabledAdminList = (p['disabledAdminKeywords'] as List<dynamic>?)
            ?.map((e) => normalizeVietnameseKeyword(e.toString()))
            .where((s) => s.length >= 2)
            .toSet()
            .toList() ??
        const [];

    final providers = <CustomPaymentProviderRule>[];
    if (p['customPaymentProviders'] is List) {
      for (final item in (p['customPaymentProviders'] as List)) {
        if (item is Map) {
          final rule = CustomPaymentProviderRule.fromMap(
            Map<String, dynamic>.from(item),
          );
          if (rule.key.isNotEmpty &&
              rule.displayLabel.isNotEmpty &&
              rule.receiptKeywords.isNotEmpty) {
            providers.add(rule);
          }
        }
      }
    }

    return TransactionIntelligenceConfig(
      version: (map['version'] as num?)?.toInt() ?? 1,
      addedExpenseKeywords: expMap,
      addedIncomeKeywords: incMap,
      disabledBuiltInKeywords: disabledList,
      disabledAdminKeywords: disabledAdminList,
      customPaymentProviders: providers,
      updatedAt: map['updatedAt'] != null
          ? DateTime.tryParse(map['updatedAt'].toString())
          : null,
      updatedBy: map['updatedBy'] as String?,
      changeNote: map['changeNote'] as String?,
    );
  }

  Map<String, dynamic> toPayloadMap() {
    return {
      'addedExpenseKeywords': addedExpenseKeywords,
      'addedIncomeKeywords': addedIncomeKeywords,
      'disabledBuiltInKeywords': disabledBuiltInKeywords,
      if (disabledAdminKeywords.isNotEmpty)
        'disabledAdminKeywords': disabledAdminKeywords,
      'customPaymentProviders':
          customPaymentProviders.map((e) => e.toMap()).toList(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'version': version,
      ...toPayloadMap(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      if (updatedBy != null) 'updatedBy': updatedBy,
      if (changeNote != null) 'changeNote': changeNote,
    };
  }

  /// Kiểm tra một từ khóa mới trước khi thêm vào một nhóm ngữ nghĩa
  static KeywordConflictCheckResult validateCandidateKeyword({
    required String rawKeyword,
    required String targetGroupKey,
    required bool isIncomeGroup,
    required Map<String, List<String>> builtInKeywordsByGroup,
    required Map<String, List<String>> addedKeywordsByGroup,
    List<String> disabledBuiltInKeywords = const [],
  }) {
    final norm = normalizeVietnameseKeyword(rawKeyword);
    if (norm.length < 2) {
      return KeywordConflictCheckResult(
        isValid: false,
        normalizedKeyword: norm,
        errorMessage: 'Từ khóa phải có ít nhất 2 ký tự.',
      );
    }
    if (norm.length > 60) {
      return KeywordConflictCheckResult(
        isValid: false,
        normalizedKeyword: norm,
        errorMessage: 'Từ khóa không được vượt quá 60 ký tự.',
      );
    }

    final allowedKeys = isIncomeGroup
        ? kCanonicalIncomeGroupLabels.keys
        : kCanonicalExpenseGroupLabels.keys;
    if (!allowedKeys.contains(targetGroupKey)) {
      return KeywordConflictCheckResult(
        isValid: false,
        normalizedKeyword: norm,
        errorMessage:
            'Nhóm ngữ nghĩa "$targetGroupKey" không hợp lệ. Chỉ sử dụng các nhóm ngữ nghĩa chuẩn của hệ thống.',
      );
    }

    // Luôn kiểm tra TOÀN BỘ từ khóa built-in được bảo vệ (tuyệt đối không loại trừ qua disabledBuiltInKeywords)
    for (final groupKey in allowedKeys) {
      final builtIn = (builtInKeywordsByGroup[groupKey] ?? const [])
          .map(normalizeVietnameseKeyword);
      final added = (addedKeywordsByGroup[groupKey] ?? const [])
          .map(normalizeVietnameseKeyword);
      final combined = <String>{...builtIn, ...added};

      if (combined.contains(norm)) {
        if (groupKey == targetGroupKey) {
          return KeywordConflictCheckResult(
            isValid: false,
            normalizedKeyword: norm,
            conflictingGroupKey: groupKey,
            errorMessage: 'Từ khóa "$norm" đã tồn tại trong nhóm này.',
          );
        } else {
          final groupLabel = isIncomeGroup
              ? (kCanonicalIncomeGroupLabels[groupKey] ?? groupKey)
              : (kCanonicalExpenseGroupLabels[groupKey] ?? groupKey);
          return KeywordConflictCheckResult(
            isValid: false,
            normalizedKeyword: norm,
            conflictingGroupKey: groupKey,
            errorMessage:
                'Xung đột từ khóa: "$norm" đã thuộc nhóm "$groupLabel". Vui lòng dùng cụm từ cụ thể hơn (VD: "$norm food", "$norm mart").',
          );
        }
      }
    }

    String? shortWarning;
    if (norm.length <= 3 && !norm.contains(' ')) {
      shortWarning =
          'Từ viết tắt ngắn (<= 3 ký tự) sẽ được hệ thống khớp theo ranh giới từ độc lập (Word Boundary).';
    }

    return KeywordConflictCheckResult(
      isValid: true,
      normalizedKeyword: norm,
      warningMessage: shortWarning,
    );
  }

  /// Kiểm tra toàn diện payload `transaction_rules` khớp 1:1 với Server validation.
  static List<String> validateRawInput(Map<String, dynamic> raw) {
    final errors = <String>[];
    if (containsForbiddenSecretField(raw)) {
      errors.add(
        'Tuyệt đối không được đưa API Key hoặc khóa bí mật vào cấu hình từ điển.',
      );
    }

    // 1. Chặn vô hiệu hóa từ khóa built-in mặc định hệ thống
    final rawDisabledBuiltIn = raw['disabledBuiltInKeywords'];
    if (rawDisabledBuiltIn != null) {
      if (rawDisabledBuiltIn is! List) {
        errors.add('disabledBuiltInKeywords phải là danh sách.');
      } else if (rawDisabledBuiltIn.isNotEmpty) {
        errors.add(
          'Không được phép vô hiệu hóa từ khóa mặc định hệ thống (Built-in Keywords là quy tắc lõi chỉ đọc).',
        );
      }
    }

    // 2. Kiểm tra danh sách disabledAdminKeywords (nếu có)
    final rawDisabledAdmin = raw['disabledAdminKeywords'];
    if (rawDisabledAdmin != null) {
      if (rawDisabledAdmin is! List) {
        errors.add('disabledAdminKeywords phải là danh sách chuỗi.');
      } else {
        for (final item in rawDisabledAdmin) {
          final norm = normalizeVietnameseKeyword(item.toString());
          if (item is! String || norm.length < 2 || norm.length > 60) {
            errors.add(
              'disabledAdminKeywords chứa phần tử không hợp lệ: "$item".',
            );
          }
        }
      }
    }

    void validateKeywordMap({
      required Object? rawMap,
      required String sectionLabel,
      required Iterable<String> allowedGroups,
      required Map<String, List<String>> builtInMap,
    }) {
      if (rawMap == null) return;
      if (rawMap is! Map) {
        errors.add('$sectionLabel phải là Map nhóm chuẩn -> danh sách từ khóa.');
        return;
      }

      final builtInGroupsByKw = <String, Set<String>>{};
      for (final g in allowedGroups) {
        for (final kw in (builtInMap[g] ?? const <String>[])) {
          final norm = normalizeVietnameseKeyword(kw);
          if (norm.isEmpty) continue;
          builtInGroupsByKw.putIfAbsent(norm, () => <String>{}).add(g);
        }
      }

      final adminGroupByKw = <String, String>{};
      for (final entry in rawMap.entries) {
        final groupKey = normalizeVietnameseKeyword(entry.key.toString());
        if (!allowedGroups.contains(groupKey)) {
          errors.add(
            'Nhóm ngữ nghĩa "${entry.key}" trong $sectionLabel không thuộc nhóm chuẩn hệ thống.',
          );
          continue;
        }
        if (entry.value is! List) {
          errors.add('Danh sách từ khóa nhóm "$groupKey" phải là mảng.');
          continue;
        }
        final seenInGroup = <String>{};
        for (final item in (entry.value as List)) {
          if (item is! String) {
            errors.add('Từ khóa trong nhóm "$groupKey" phải là chuỗi.');
            continue;
          }
          final normKw = normalizeVietnameseKeyword(item);
          if (normKw.length < 2 || normKw.length > 60) {
            errors.add(
              'Từ khóa "$item" trong nhóm "$groupKey" phải dài từ 2 đến 60 ký tự.',
            );
            continue;
          }
          if (seenInGroup.contains(normKw)) {
            errors.add(
              'Từ khóa "$normKw" bị trùng lặp trong cùng nhóm "$groupKey".',
            );
            continue;
          }
          seenInGroup.add(normKw);

          final builtInGroups = builtInGroupsByKw[normKw];
          if (builtInGroups != null && builtInGroups.isNotEmpty) {
            if (builtInGroups.contains(groupKey)) {
              errors.add(
                'Từ khóa "$normKw" đã tồn tại trong từ điển mặc định hệ thống của nhóm "$groupKey".',
              );
            } else {
              errors.add(
                'Xung đột với từ khóa mặc định được bảo vệ: "$normKw" đang thuộc nhóm "${builtInGroups.first}".',
              );
            }
            continue;
          }

          final prevAdminGroup = adminGroupByKw[normKw];
          if (prevAdminGroup != null && prevAdminGroup != groupKey) {
            errors.add(
              'Xung đột từ khóa bổ sung giữa hai nhóm "$prevAdminGroup" và "$groupKey" cho từ "$normKw".',
            );
            continue;
          }
          adminGroupByKw[normKw] = groupKey;
        }
      }
    }

    validateKeywordMap(
      rawMap: raw['addedExpenseKeywords'],
      sectionLabel: 'addedExpenseKeywords',
      allowedGroups: kCanonicalExpenseGroupLabels.keys,
      builtInMap: kProtectedBuiltInExpenseKeywords,
    );
    validateKeywordMap(
      rawMap: raw['addedIncomeKeywords'],
      sectionLabel: 'addedIncomeKeywords',
      allowedGroups: kCanonicalIncomeGroupLabels.keys,
      builtInMap: kProtectedBuiltInIncomeKeywords,
    );

    // 3. Kiểm tra danh sách nhà cung cấp thanh toán mở rộng
    final rawProviders = raw['customPaymentProviders'];
    if (rawProviders != null) {
      if (rawProviders is! List) {
        errors.add('customPaymentProviders phải là danh sách.');
      } else {
        final seenKeys = <String>{};
        for (final item in rawProviders) {
          if (item is! Map) {
            errors.add('Mỗi mục trong customPaymentProviders phải là Map hợp lệ.');
            continue;
          }
          final rawKey = (item['key'] ?? '').toString();
          final normKey = normalizeVietnameseKeyword(rawKey).replaceAll(' ', '_');
          if (!RegExp(r'^[a-z0-9_]{2,40}$').hasMatch(normKey)) {
            errors.add(
              'Mã nhà cung cấp thanh toán "$rawKey" phải gồm 2-40 ký tự a-z, 0-9 hoặc _.',
            );
          } else if (kProtectedPaymentProviderKeys.contains(normKey)) {
            errors.add(
              'Không được phép ghi đè nhà cung cấp thanh toán mặc định được bảo vệ: "$normKey".',
            );
          } else if (seenKeys.contains(normKey)) {
            errors.add('Mã nhà cung cấp thanh toán "$normKey" bị trùng lặp.');
          } else {
            seenKeys.add(normKey);
          }

          final label = (item['displayLabel'] ?? '').toString().trim();
          if (label.length < 2 || label.length > 60) {
            errors.add(
              'Tên hiển thị nhà cung cấp "${normKey.isEmpty ? rawKey : normKey}" phải từ 2 đến 60 ký tự.',
            );
          }

          final walletType = item['walletType'];
          if (!kCanonicalWalletTypes.contains(walletType)) {
            errors.add(
              'walletType "$walletType" không hợp lệ (chỉ nhận cash, eWallet, bank).',
            );
          }

          if (item.containsKey('isActive') && item['isActive'] is! bool) {
            errors.add('Trường isActive của nhà cung cấp phải là bool.');
          }

          final receiptKws = item['receiptKeywords'];
          if (receiptKws is! List || receiptKws.isEmpty) {
            errors.add(
              'Nhà cung cấp "${normKey.isEmpty ? label : normKey}" phải có ít nhất 1 receiptKeywords.',
            );
          } else {
            for (final kw in receiptKws) {
              final normKw = normalizeVietnameseKeyword(kw.toString());
              if (kw is! String || normKw.length < 2 || normKw.length > 60) {
                errors.add('receiptKeywords chứa từ khóa không hợp lệ: "$kw".');
              }
            }
          }
        }
      }
    }

    return errors;
  }
}

/// ============================================================================
/// 4. MODEL KHO TRI THỨC TÀI CHÍNH (`financial_knowledge_base`)
/// ============================================================================

/// Tập điều kiện kích hoạt cố định và được kiểm soát trong code
enum KnowledgeTriggerCondition {
  always('always', 'Luôn áp dụng (Nguyên tắc cốt lõi)'),
  lowSavingRate('low_saving_rate', 'Khi tỷ lệ tiết kiệm thấp hơn mức chuẩn'),
  essentialDeficit('essential_deficit', 'Khi chi phí thiết yếu vượt thu nhập'),
  variableIncome('variable_income', 'Khi thu nhập biến động giữa các tháng'),
  budgetOverrun('budget_overrun', 'Khi có danh mục vượt ngân sách'),
  infeasibleGoal('infeasible_goal', 'Khi mục tiêu tiết kiệm vượt khả năng thặng dư');

  final String code;
  final String displayLabel;
  const KnowledgeTriggerCondition(this.code, this.displayLabel);

  static KnowledgeTriggerCondition fromCode(String? code) {
    if (code == null) return KnowledgeTriggerCondition.always;
    return KnowledgeTriggerCondition.values.firstWhere(
      (e) => e.code == code.trim(),
      orElse: () => KnowledgeTriggerCondition.always,
    );
  }
}

class FinancialKnowledgeArticle {
  static const int kMaxSummaryLength = 250;
  static const int kMaxSnippetLength = 300;
  static const int kMaxInjectedSnippetsPerPrompt = 3;
  static const List<String> kAllowedTopics = [
    'budget_rule',
    'saving_strategy',
    'spending_control',
    'crisis_recovery',
  ];

  static List<String> validateRawInput(Map<String, dynamic> raw) {
    final errors = <String>[];
    if (containsForbiddenSecretField(raw)) {
      errors.add(
        'Tuyệt đối không được chứa API Key hoặc khóa bí mật trong bài viết tri thức.',
      );
    }

    final articleId = (raw['articleId'] ?? '').toString().trim();
    if (!RegExp(r'^[a-zA-Z0-9_-]{3,80}$').hasMatch(articleId)) {
      errors.add(
        'articleId phải dài 3-80 ký tự và chỉ gồm chữ cái, số, "_" hoặc "-".',
      );
    }

    final title = (raw['title'] ?? '').toString().trim();
    if (title.length < 3 || title.length > 120) {
      errors.add('Tiêu đề bài viết phải dài từ 3 đến 120 ký tự.');
    }

    final topic = (raw['topic'] ?? '').toString().trim();
    if (!kAllowedTopics.contains(topic)) {
      errors.add('Chủ đề (topic) "$topic" không hợp lệ.');
    }

    final triggerCode = (raw['triggerCondition'] ?? '').toString().trim();
    final validTrigger = KnowledgeTriggerCondition.values
        .any((e) => e.code == triggerCode);
    if (!validTrigger) {
      errors.add('Điều kiện kích hoạt (triggerCondition) "$triggerCode" không hợp lệ.');
    }

    final rawPriority = raw['priority'];
    if (rawPriority is! num ||
        rawPriority.toDouble() != rawPriority.toInt().toDouble() ||
        rawPriority.toInt() < 1 ||
        rawPriority.toInt() > 10) {
      errors.add('Độ ưu tiên (priority) phải là số nguyên từ 1 đến 10.');
    }

    final summary = (raw['summaryForUser'] ?? '').toString().trim();
    if (summary.isEmpty || summary.length > kMaxSummaryLength) {
      errors.add(
        'Tóm tắt cho người dùng bắt buộc nhập và tối đa $kMaxSummaryLength ký tự.',
      );
    }

    final snippet = (raw['aiGroundingSnippet'] ?? '').toString().trim();
    if (snippet.isEmpty || snippet.length > kMaxSnippetLength) {
      errors.add(
        'Đoạn tri thức tiêm vào AI bắt buộc nhập và tối đa $kMaxSnippetLength ký tự.',
      );
    }

    final prompts = raw['suggestedPrompts'];
    if (prompts != null) {
      if (prompts is! List) {
        errors.add('suggestedPrompts phải là danh sách chuỗi.');
      } else if (prompts.length > 3) {
        errors.add('suggestedPrompts tối đa chỉ được chứa 3 câu gợi ý.');
      } else {
        for (final p in prompts) {
          if (p is! String || p.trim().isEmpty || p.trim().length > 120) {
            errors.add('Mỗi câu gợi ý trong suggestedPrompts phải dài từ 1 đến 120 ký tự.');
          }
        }
      }
    }

    if (raw.containsKey('isActive') && raw['isActive'] is! bool) {
      errors.add('Trường isActive phải là bool.');
    }

    return errors;
  }

  final String articleId;
  final String title;
  final String topic; // 'budget_rule' | 'saving_strategy' | 'spending_control' | 'crisis_recovery'
  final KnowledgeTriggerCondition triggerCondition;
  final int priority; // 1 .. 10 (cao hơn được ưu tiên chọn trước)
  final String summaryForUser;
  final String aiGroundingSnippet;
  final List<String> suggestedPrompts;
  final bool isActive;
  final DateTime? updatedAt;
  final String? updatedBy;

  const FinancialKnowledgeArticle({
    required this.articleId,
    required this.title,
    required this.topic,
    required this.triggerCondition,
    this.priority = 5,
    required this.summaryForUser,
    required this.aiGroundingSnippet,
    this.suggestedPrompts = const [],
    this.isActive = true,
    this.updatedAt,
    this.updatedBy,
  });

  factory FinancialKnowledgeArticle.fromMap(
    Map<String, dynamic> map, {
    String? docId,
  }) {
    final rawSummary = ((map['summaryForUser'] as String?) ?? '').trim();
    final rawSnippet = ((map['aiGroundingSnippet'] as String?) ?? '').trim();

    return FinancialKnowledgeArticle(
      articleId: (map['articleId'] as String?)?.trim().isNotEmpty == true
          ? (map['articleId'] as String).trim()
          : (docId ?? ''),
      title: ((map['title'] as String?) ?? '').trim(),
      topic: ((map['topic'] as String?) ?? 'budget_rule').trim(),
      triggerCondition: KnowledgeTriggerCondition.fromCode(
        map['triggerCondition'] as String?,
      ),
      priority: ((map['priority'] as num?)?.toInt() ?? 5).clamp(1, 10),
      summaryForUser: rawSummary.length <= kMaxSummaryLength
          ? rawSummary
          : rawSummary.substring(0, kMaxSummaryLength),
      aiGroundingSnippet: rawSnippet.length <= kMaxSnippetLength
          ? rawSnippet
          : rawSnippet.substring(0, kMaxSnippetLength),
      suggestedPrompts: (map['suggestedPrompts'] as List<dynamic>?)
              ?.map((e) => e.toString().trim())
              .where((s) => s.isNotEmpty && s.length <= 120)
              .take(3)
              .toList() ??
          const [],
      isActive: map['isActive'] != false,
      updatedAt: map['updatedAt'] != null
          ? DateTime.tryParse(map['updatedAt'].toString())
          : null,
      updatedBy: map['updatedBy'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'articleId': articleId,
      'title': title,
      'topic': topic,
      'triggerCondition': triggerCondition.code,
      'priority': priority,
      'summaryForUser': summaryForUser,
      'aiGroundingSnippet': aiGroundingSnippet,
      'suggestedPrompts': suggestedPrompts,
      'isActive': isActive,
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      if (updatedBy != null) 'updatedBy': updatedBy,
    };
  }

  /// Danh sách bài viết tri thức mặc định sẵn có trong code
  static List<FinancialKnowledgeArticle> defaultArticles() {
    return const [
      FinancialKnowledgeArticle(
        articleId: 'kb_50_30_20_rule',
        title: 'Nguyên tắc phân bổ 50/30/20 linh hoạt theo thu nhập',
        topic: 'budget_rule',
        triggerCondition: KnowledgeTriggerCondition.always,
        priority: 9,
        summaryForUser:
            'Ưu tiên tối đa 50-60% thu nhập cho nhu cầu thiết yếu, 20-30% cho chi tiêu linh hoạt và duy trì ít nhất 15-20% cho tiết kiệm/quỹ dự phòng.',
        aiGroundingSnippet:
            'Áp dụng khung tham chiếu 50/30/20 có điều chỉnh: bảo toàn chi thiết yếu trước, giới hạn chi linh hoạt và ưu tiên trích lập tiết kiệm ngay từ đầu kỳ lương.',
        suggestedPrompts: [
          'Cơ cấu thu chi hiện tại của tôi so với quy tắc 50/30/20 thế nào?',
        ],
      ),
      FinancialKnowledgeArticle(
        articleId: 'kb_essential_deficit_recovery',
        title: 'Kịch bản xử lý khi chi phí thiết yếu vượt thu nhập',
        topic: 'crisis_recovery',
        triggerCondition: KnowledgeTriggerCondition.essentialDeficit,
        priority: 10,
        summaryForUser:
            'Khi chi thiết yếu vượt thu nhập, cần rà soát lại các khoản chi linh hoạt bị gắn nhầm nhãn Thiết yếu và tạm dừng các khoản mua sắm không cấp bách.',
        aiGroundingSnippet:
            'Người dùng đang bị thâm hụt ngay ở nhóm Thiết yếu: tuyệt đối không khuyên cắt giảm tiền nhà/điện/nước/y tế một cách máy móc; hãy hướng dẫn rà soát xem có khoản ăn ngoài/mua sắm nào bị phân loại nhầm vào nhóm Thiết yếu hay không.',
        suggestedPrompts: [
          'Làm sao cân đối lại khi chi phí thiết yếu đang vượt thu nhập?',
        ],
      ),
      FinancialKnowledgeArticle(
        articleId: 'kb_variable_income_buffer',
        title: 'Chiến lược ngân sách theo mức thu nhập thận trọng cho Freelancer',
        topic: 'saving_strategy',
        triggerCondition: KnowledgeTriggerCondition.variableIncome,
        priority: 8,
        summaryForUser:
            'Với thu nhập biến động giữa các tháng, hãy lập ngân sách dựa trên mức thu nhập tháng thấp (mức thận trọng) và chuyển phần vượt trội ở tháng cao vào quỹ đệm.',
        aiGroundingSnippet:
            'Thu nhập người dùng biến động mạnh: khuyến nghị lập ngân sách chi tiêu trên mức thu nhập thận trọng, phần thu nhập tăng thêm ở các tháng thuận lợi nên đưa thẳng vào quỹ dự phòng thay vì nâng mức sống.',
        suggestedPrompts: [
          'Thu nhập tháng cao tháng thấp thì nên lập ngân sách thế nào?',
        ],
      ),
    ];
  }

  /// Chọn lọc tối đa 3 đoạn tri thức tài chính (`<= 300` ký tự/đoạn) khớp với
  /// trạng thái định lượng thực tế của người dùng để tiêm vào Prompt gửi cho Gemini.
  static List<FinancialKnowledgeArticle> selectMatchingArticles({
    bool isLowSavingRate = false,
    bool isEssentialDeficit = false,
    bool isVariableIncome = false,
    bool hasBudgetOverrun = false,
    bool isGoalInfeasible = false,
    List<FinancialKnowledgeArticle>? overrideArticles,
  }) {
    final source = overrideArticles ?? defaultArticles();
    final matched = source.where((article) {
      if (!article.isActive || article.aiGroundingSnippet.trim().isEmpty) {
        return false;
      }
      switch (article.triggerCondition) {
        case KnowledgeTriggerCondition.always:
          return true;
        case KnowledgeTriggerCondition.lowSavingRate:
          return isLowSavingRate;
        case KnowledgeTriggerCondition.essentialDeficit:
          return isEssentialDeficit;
        case KnowledgeTriggerCondition.variableIncome:
          return isVariableIncome;
        case KnowledgeTriggerCondition.budgetOverrun:
          return hasBudgetOverrun;
        case KnowledgeTriggerCondition.infeasibleGoal:
          return isGoalInfeasible;
      }
    }).toList();

    matched.sort((a, b) => b.priority.compareTo(a.priority));

    return matched.take(kMaxInjectedSnippetsPerPrompt).toList();
  }

  /// Trích xuất danh sách chuỗi chỉ dẫn ngắn gọn (đã giới hạn nghiêm ngặt độ dài) để tiêm vào Prompt.
  static List<String> selectSnippetsForPrompt({
    bool isLowSavingRate = false,
    bool isEssentialDeficit = false,
    bool isVariableIncome = false,
    bool hasBudgetOverrun = false,
    bool isGoalInfeasible = false,
    List<FinancialKnowledgeArticle>? overrideArticles,
  }) {
    final articles = selectMatchingArticles(
      isLowSavingRate: isLowSavingRate,
      isEssentialDeficit: isEssentialDeficit,
      isVariableIncome: isVariableIncome,
      hasBudgetOverrun: hasBudgetOverrun,
      isGoalInfeasible: isGoalInfeasible,
      overrideArticles: overrideArticles,
    );

    return articles.map((a) {
      final snippet = a.aiGroundingSnippet.trim();
      final bounded = snippet.length <= kMaxSnippetLength
          ? snippet
          : snippet.substring(0, kMaxSnippetLength);
      return '- [${a.title}]: $bounded';
    }).toList();
  }
}

/// ============================================================================
/// 5. DỮ LIỆU PERSONA GIẢ LẬP CHO KIỂM THỬ (`SyntheticPersona`)
/// Chạy 100% trên RAM, hoàn toàn không chạm tới dữ liệu thật của User.
/// ============================================================================
class SyntheticPersona {
  final String id;
  final String title;
  final String subtitle;
  final double declaredMonthlyIncome;
  final List<Wallet> wallets;
  final List<Category> categories;
  final List<Budget> currentBudgets;
  final List<SavingGoal> savingGoals;
  final List<AppTransaction> currentMonthTx;
  final List<List<AppTransaction>> historicalMonthsTx;

  const SyntheticPersona({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.declaredMonthlyIncome,
    required this.wallets,
    required this.categories,
    required this.currentBudgets,
    required this.savingGoals,
    required this.currentMonthTx,
    required this.historicalMonthsTx,
  });

  static List<Category> _standardSandboxCategories() {
    return [
      Category(
        categoryId: 'sb_cat_rent',
        userId: 'sandbox_persona',
        name: 'Hóa đơn & Nhà ở',
        type: 'expense',
        icon: 'home',
        color: 0xFF3B82F6,
        isEssential: true,
      ),
      Category(
        categoryId: 'sb_cat_food',
        userId: 'sandbox_persona',
        name: 'Ăn uống',
        type: 'expense',
        icon: 'restaurant',
        color: 0xFFEF4444,
        isEssential: false,
      ),
      Category(
        categoryId: 'sb_cat_move',
        userId: 'sandbox_persona',
        name: 'Di chuyển',
        type: 'expense',
        icon: 'directions_car',
        color: 0xFF10B981,
        isEssential: true,
      ),
      Category(
        categoryId: 'sb_cat_shop',
        userId: 'sandbox_persona',
        name: 'Mua sắm',
        type: 'expense',
        icon: 'shopping_bag',
        color: 0xFFF59E0B,
        isEssential: false,
      ),
      Category(
        categoryId: 'sb_cat_fun',
        userId: 'sandbox_persona',
        name: 'Giải trí',
        type: 'expense',
        icon: 'movie',
        color: 0xFF8B5CF6,
        isEssential: false,
      ),
      Category(
        categoryId: 'sb_cat_salary',
        userId: 'sandbox_persona',
        name: 'Lương',
        type: 'income',
        icon: 'work',
        color: 0xFF10B981,
        isEssential: false,
      ),
    ];
  }

  /// Danh sách 3 Persona giả lập tiêu chuẩn phục vụ kiểm thử AI Sandbox
  static List<SyntheticPersona> builtInPersonas({DateTime? referenceDate}) {
    final now = referenceDate ?? DateTime(2026, 11, 15);
    final m0 = DateTime(now.year, now.month, 1);
    final m1 = DateTime(now.year, now.month - 1, 1);
    final m2 = DateTime(now.year, now.month - 2, 1);
    final cats = _standardSandboxCategories();

    AppTransaction tx(
      String id,
      String catId,
      double amount,
      String type,
      DateTime baseMonth,
      int dayOffset,
      String note,
    ) {
      return AppTransaction(
        transactionId: id,
        userId: 'sandbox_persona',
        walletId: 'sb_wal_main',
        categoryId: catId,
        amount: amount,
        type: type,
        note: note,
        date: baseMonth.add(Duration(days: dayOffset)),
      );
    }

    return [
      // Persona 1: Nhân viên văn phòng có chi tiêu Mua sắm & Ăn uống tăng đột biến
      SyntheticPersona(
        id: 'office_worker_spike',
        title: 'Nhân viên văn phòng — Chi linh hoạt tăng đột biến',
        subtitle:
            'Thu nhập ổn định 18 triệu/tháng, chi Mua sắm tăng +60% so với tháng trước, vượt ngân sách.',
        declaredMonthlyIncome: 18000000,
        wallets: [
          Wallet(
            walletId: 'sb_wal_main',
            userId: 'sandbox_persona',
            walletName: 'Vietcombank Chính',
            type: 'bank',
            balance: 6500000,
            createdAt: m2,
          ),
        ],
        categories: cats,
        currentBudgets: [
          Budget(
            budgetId: 'sb_b1',
            userId: 'sandbox_persona',
            categoryId: 'sb_cat_food',
            limit: 4000000,
            month: '${now.month.toString().padLeft(2, '0')}/${now.year}',
          ),
          Budget(
            budgetId: 'sb_b2',
            userId: 'sandbox_persona',
            categoryId: 'sb_cat_shop',
            limit: 2500000,
            month: '${now.month.toString().padLeft(2, '0')}/${now.year}',
          ),
        ],
        savingGoals: [
          SavingGoal(
            goalId: 'sb_g1',
            userId: 'sandbox_persona',
            name: 'Quỹ dự phòng khẩn cấp',
            targetAmount: 36000000,
            savedAmount: 12000000,
            months: 6,
            createdAt: m2,
          ),
        ],
        currentMonthTx: [
          tx('t1', 'sb_cat_salary', 18000000, 'income', m0, 1, 'Lương tháng'),
          tx('t2', 'sb_cat_rent', 5000000, 'expense', m0, 2, 'Tiền thuê nhà & điện nước'),
          tx('t3', 'sb_cat_move', 1200000, 'expense', m0, 4, 'Xăng xe & Grab'),
          tx('t4', 'sb_cat_food', 4600000, 'expense', m0, 6, 'Ăn uống & Cà phê Highlands'),
          tx('t5', 'sb_cat_shop', 4000000, 'expense', m0, 9, 'Mua sắm Shopee'),
          tx('t6', 'sb_cat_fun', 1200000, 'expense', m0, 11, 'Xem phim CGV'),
        ],
        historicalMonthsTx: [
          [
            tx('h1_1', 'sb_cat_salary', 18000000, 'income', m1, 1, 'Lương tháng trước'),
            tx('h1_2', 'sb_cat_rent', 5000000, 'expense', m1, 2, 'Tiền nhà'),
            tx('h1_3', 'sb_cat_move', 1100000, 'expense', m1, 5, 'Xăng xe'),
            tx('h1_4', 'sb_cat_food', 3200000, 'expense', m1, 8, 'Ăn uống'),
            tx('h1_5', 'sb_cat_shop', 2500000, 'expense', m1, 12, 'Mua sắm'),
            tx('h1_6', 'sb_cat_fun', 900000, 'expense', m1, 15, 'Giải trí'),
          ],
          [
            tx('h2_1', 'sb_cat_salary', 18000000, 'income', m2, 1, 'Lương 2 tháng trước'),
            tx('h2_2', 'sb_cat_rent', 5000000, 'expense', m2, 2, 'Tiền nhà'),
            tx('h2_3', 'sb_cat_move', 1150000, 'expense', m2, 5, 'Xăng xe'),
            tx('h2_4', 'sb_cat_food', 3300000, 'expense', m2, 8, 'Ăn uống'),
            tx('h2_5', 'sb_cat_shop', 2200000, 'expense', m2, 12, 'Mua sắm'),
          ],
        ],
      ),

      // Persona 2: Sinh viên mới ra trường — Mục tiêu tiết kiệm vượt khả năng thặng dư
      SyntheticPersona(
        id: 'student_tight_budget',
        title: 'Sinh viên mới ra trường — Mục tiêu tiết kiệm quá sức',
        subtitle:
            'Thu nhập 8 triệu/tháng, chi thiết yếu 4.5 triệu, đặt mục tiêu mua Laptop 20 triệu trong 4 tháng.',
        declaredMonthlyIncome: 8000000,
        wallets: [
          Wallet(
            walletId: 'sb_wal_main',
            userId: 'sandbox_persona',
            walletName: 'Ví MoMo',
            type: 'eWallet',
            balance: 1800000,
            createdAt: m2,
          ),
        ],
        categories: cats,
        currentBudgets: const [],
        savingGoals: [
          SavingGoal(
            goalId: 'sb_g_laptop',
            userId: 'sandbox_persona',
            name: 'Mua Laptop học tập',
            targetAmount: 20000000,
            savedAmount: 2000000,
            months: 4,
            createdAt: m1,
          ),
        ],
        currentMonthTx: [
          tx('s1', 'sb_cat_salary', 8000000, 'income', m0, 1, 'Lương part-time & trợ cấp'),
          tx('s2', 'sb_cat_rent', 3500000, 'expense', m0, 2, 'Tiền trọ & điện nước'),
          tx('s3', 'sb_cat_move', 1000000, 'expense', m0, 4, 'Xe bus & xăng'),
          tx('s4', 'sb_cat_food', 2200000, 'expense', m0, 6, 'Ăn uống & Trà sữa'),
          tx('s5', 'sb_cat_shop', 700000, 'expense', m0, 9, 'Đồ dùng cá nhân'),
          tx('s6', 'sb_cat_fun', 400000, 'expense', m0, 11, 'Cà phê bạn bè'),
        ],
        historicalMonthsTx: [
          [
            tx('sh1', 'sb_cat_salary', 8000000, 'income', m1, 1, 'Thu nhập'),
            tx('sh2', 'sb_cat_rent', 3500000, 'expense', m1, 3, 'Tiền trọ'),
            tx('sh3', 'sb_cat_move', 950000, 'expense', m1, 5, 'Di chuyển'),
            tx('sh4', 'sb_cat_food', 2100000, 'expense', m1, 8, 'Ăn uống'),
            tx('sh5', 'sb_cat_shop', 600000, 'expense', m1, 12, 'Mua sắm'),
          ],
        ],
      ),

      // Persona 3: Freelancer thu nhập biến động mạnh
      SyntheticPersona(
        id: 'freelancer_volatile_income',
        title: 'Freelancer — Thu nhập biến động mạnh giữa các tháng',
        subtitle:
            'Tháng trước thu 28 triệu, tháng này thu 10 triệu (CV > 0.35), cần lập kế hoạch theo mức thận trọng.',
        declaredMonthlyIncome: 0,
        wallets: [
          Wallet(
            walletId: 'sb_wal_main',
            userId: 'sandbox_persona',
            walletName: 'Techcombank',
            type: 'bank',
            balance: 14000000,
            createdAt: m2,
          ),
        ],
        categories: cats,
        currentBudgets: const [],
        savingGoals: const [],
        currentMonthTx: [
          tx('f1', 'sb_cat_salary', 10000000, 'income', m0, 2, 'Thanh toán dự án đợt 1'),
          tx('f2', 'sb_cat_rent', 6000000, 'expense', m0, 3, 'Thuê căn hộ & Internet'),
          tx('f3', 'sb_cat_move', 1200000, 'expense', m0, 5, 'Di chuyển'),
          tx('f4', 'sb_cat_food', 3100000, 'expense', m0, 7, 'Ăn uống'),
          tx('f5', 'sb_cat_shop', 1500000, 'expense', m0, 10, 'Thiết bị làm việc'),
        ],
        historicalMonthsTx: [
          [
            tx('fh1_1', 'sb_cat_salary', 28000000, 'income', m1, 2, 'Dự án lớn tháng trước'),
            tx('fh1_2', 'sb_cat_rent', 6000000, 'expense', m1, 3, 'Thuê nhà'),
            tx('fh1_3', 'sb_cat_move', 1300000, 'expense', m1, 5, 'Di chuyển'),
            tx('fh1_4', 'sb_cat_food', 3500000, 'expense', m1, 8, 'Ăn uống'),
            tx('fh1_5', 'sb_cat_shop', 2800000, 'expense', m1, 14, 'Mua sắm'),
          ],
          [
            tx('fh2_1', 'sb_cat_salary', 14000000, 'income', m2, 2, 'Dự án 2 tháng trước'),
            tx('fh2_2', 'sb_cat_rent', 6000000, 'expense', m2, 3, 'Thuê nhà'),
            tx('fh2_3', 'sb_cat_move', 1100000, 'expense', m2, 6, 'Di chuyển'),
            tx('fh2_4', 'sb_cat_food', 3000000, 'expense', m2, 9, 'Ăn uống'),
            tx('fh2_5', 'sb_cat_shop', 1600000, 'expense', m2, 15, 'Mua sắm'),
          ],
        ],
      ),
    ];
  }
}

import 'dart:convert';
import 'dart:typed_data';
import 'budget_model.dart';
import 'category_model.dart';
import 'saving_goal_model.dart';
import 'transaction_model.dart';
import 'wallet_model.dart';

/// ============================================================================
/// AI RUNTIME CONFIG, FINANCIAL HEURISTICS, KNOWLEDGE BASE & SANDBOX MODELS
/// ============================================================================
/// LƯU Ý KIẾN TRÚC & BẢO MẬT:
/// 1. Dự án hiện giữ `package:google_generative_ai` ở tầng thực thi để bảo toàn
///    độ ổn định của Streaming Chatbot và Multimodal OCR, nhưng ghi nhận gói này
///    đã ngưng phát triển tính năng mới (deprecated) để sẵn sàng lộ trình nâng cấp
///    sang `firebase_ai` hoặc Backend Proxy.
/// 2. Tuyệt đối KHÔNG lưu trữ Gemini API Key hay khóa bí mật (Secret Salt)
///    trong bất kỳ model cấu hình Firestore hoặc giao diện Admin Web nào.
/// 3. Mọi cấu hình Draft và Published được tách riêng ở tầng Firestore Collection.
/// ============================================================================

/// Mô tả thông tin một Model Gemini nằm trong Whitelist được phép sử dụng
class GeminiModelDescriptor {
  final String modelId;
  final String displayName;
  final String roleBadge;
  final String description;
  final bool supportsStreaming;
  final bool supportsMultimodalOcr;
  final bool supportsStructuredJson;
  final bool isRecommendedPrimary;

  const GeminiModelDescriptor({
    required this.modelId,
    required this.displayName,
    required this.roleBadge,
    required this.description,
    this.supportsStreaming = true,
    this.supportsMultimodalOcr = true,
    this.supportsStructuredJson = true,
    this.isRecommendedPrimary = false,
  });
}

/// Danh sách Whitelist các Model ID hợp lệ theo tài liệu Gemini Developer API hiện hành.
/// Admin chỉ được chọn từ danh sách này, không được nhập chuỗi tự do.
const List<GeminiModelDescriptor> kSupportedGeminiModels = [
  GeminiModelDescriptor(
    modelId: 'gemini-3.5-flash',
    displayName: 'Gemini 3.5 Flash',
    roleBadge: 'Khuyên dùng (Mặc định)',
    description:
        'Cân bằng tối ưu giữa tốc độ phản hồi, lập luận tài chính cá nhân và đọc hóa đơn đa phương thức.',
    isRecommendedPrimary: true,
  ),
  GeminiModelDescriptor(
    modelId: 'gemini-3.5-flash-lite',
    displayName: 'Gemini 3.5 Flash-Lite',
    roleBadge: 'Tốc độ cao / Fallback #1',
    description:
        'Độ trễ cực thấp, thông lượng cao, phù hợp làm model dự phòng ưu tiên hoặc bóc tách dữ liệu nhanh.',
  ),
  GeminiModelDescriptor(
    modelId: 'gemini-3.6-flash',
    displayName: 'Gemini 3.6 Flash',
    roleBadge: 'Thế hệ mới',
    description:
        'Phiên bản Flash thế hệ mới hỗ trợ tốt ngữ cảnh dài và phân tích kế hoạch tài chính.',
    isRecommendedPrimary: true,
  ),
  GeminiModelDescriptor(
    modelId: 'gemini-2.5-flash',
    displayName: 'Gemini 2.5 Flash (LTS)',
    roleBadge: 'Ổn định dài hạn',
    description:
        'Phiên bản ổn định rộng rãi (GA), tương thích cao với mọi tác vụ tư vấn và trích xuất JSON.',
    isRecommendedPrimary: true,
  ),
  GeminiModelDescriptor(
    modelId: 'gemini-2.5-flash-lite',
    displayName: 'Gemini 2.5 Flash-Lite',
    roleBadge: 'Tiết kiệm Quota',
    description: 'Phiên bản nhẹ của dòng 2.5, tối ưu hạn mức gọi API.',
  ),
  GeminiModelDescriptor(
    modelId: 'gemini-2.5-pro',
    displayName: 'Gemini 2.5 Pro',
    roleBadge: 'Phân tích chuyên sâu',
    description:
        'Khả năng suy luận phức tạp cao nhất, nhưng độ trễ lớn hơn và hạn mức (RPM) thấp hơn dòng Flash.',
  ),
  GeminiModelDescriptor(
    modelId: 'gemini-flash-latest',
    displayName: 'Gemini Flash Latest (Auto-Alias)',
    roleBadge: 'Dự phòng cuối',
    description:
        'Bí danh tự động trỏ tới phiên bản Flash ổn định mới nhất của Google Gemini API.',
  ),
];

/// Kiểm tra một mã model có nằm trong danh sách Whitelist được phép hay không
bool isSupportedGeminiModelId(String? modelId) {
  if (modelId == null || modelId.trim().isEmpty) return false;
  final trimmed = modelId.trim();
  return kSupportedGeminiModels.any((m) => m.modelId == trimmed);
}

/// Làm sạch và khử trùng lặp chuỗi model (luôn đảm bảo có ít nhất chuỗi mặc định an toàn)
List<String> sanitizeGeminiModelChain({
  required String primaryModel,
  required List<String> fallbackModels,
}) {
  const defaultPrimary = 'gemini-3.5-flash';
  const defaultFallbacks = <String>[
    'gemini-3.5-flash-lite',
    'gemini-3.6-flash',
    'gemini-flash-latest',
  ];

  final validPrimary = isSupportedGeminiModelId(primaryModel)
      ? primaryModel.trim()
      : defaultPrimary;

  final result = <String>[validPrimary];
  for (final fb in fallbackModels) {
    final trimmed = fb.trim();
    if (isSupportedGeminiModelId(trimmed) && !result.contains(trimmed)) {
      result.add(trimmed);
    }
  }

  for (final def in defaultFallbacks) {
    if (!result.contains(def)) {
      result.add(def);
    }
  }

  return List<String>.unmodifiable(result);
}

/// ============================================================================
/// CANONICAL JSON & RFC-6234 SHA-256 IMPLEMENTATION (PURE DART)
/// Đảm bảo mã băm cấu hình (Config Digest) tính trên Dart (Mobile / Admin Web)
/// và trên Node.js (`crypto.createHash('sha256')` tại Cloud Functions) khớp nhau 100%.
/// ============================================================================

/// Chuẩn hóa cấu trúc dữ liệu (sắp xếp key của Map theo thứ tự từ điển đệ quy)
Object? canonicalizeJsonValue(Object? value) {
  if (value == null || value is bool || value is String) {
    return value;
  }
  if (value is num) {
    if (value is double && value == value.roundToDouble()) {
      return value.toInt();
    }
    if (value is double) {
      return double.parse(value.toStringAsFixed(6));
    }
    return value;
  }
  if (value is List) {
    return value.map(canonicalizeJsonValue).toList();
  }
  if (value is Map) {
    final sortedKeys = value.keys.map((k) => k.toString()).toList()..sort();
    final result = <String, Object?>{};
    for (final k in sortedKeys) {
      result[k] = canonicalizeJsonValue(value[k]);
    }
    return result;
  }
  return value.toString();
}

/// Sinh chuỗi JSON chuẩn hóa (Canonical JSON String)
String encodeCanonicalJson(Map<String, dynamic> map) {
  final canonical = canonicalizeJsonValue(map);
  return jsonEncode(canonical);
}

/// Tính mã băm SHA-256 chuẩn RFC 6234 (trả về chuỗi 64 ký tự hex chữ thường)
String sha256HexFromString(String input) {
  final data = utf8.encode(input);
  return _sha256BytesToHex(data);
}

/// Tính mã băm chuẩn hóa cho một Payload cấu hình
String computeCanonicalConfigHash(Map<String, dynamic> payload) {
  return sha256HexFromString(encodeCanonicalJson(payload));
}

String _sha256BytesToHex(List<int> messageBytes) {
  const k = <int>[
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];

  int rotr(int n, int x) => ((x & 0xffffffff) >>> n) | ((x << (32 - n)) & 0xffffffff);

  var h0 = 0x6a09e667;
  var h1 = 0xbb67ae85;
  var h2 = 0x3c6ef372;
  var h3 = 0xa54ff53a;
  var h4 = 0x510e527f;
  var h5 = 0x9b05688c;
  var h6 = 0x1f83d9ab;
  var h7 = 0x5be0cd19;

  final bitLength = messageBytes.length * 8;
  final paddedLength = ((messageBytes.length + 9 + 63) ~/ 64) * 64;
  final padded = Uint8List(paddedLength);
  padded.setRange(0, messageBytes.length, messageBytes);
  padded[messageBytes.length] = 0x80;

  final bd = ByteData.sublistView(padded);
  bd.setUint32(paddedLength - 8, (bitLength >>> 32) & 0xffffffff, Endian.big);
  bd.setUint32(paddedLength - 4, bitLength & 0xffffffff, Endian.big);

  final w = Uint32List(64);
  for (var chunkStart = 0; chunkStart < paddedLength; chunkStart += 64) {
    for (var i = 0; i < 16; i++) {
      w[i] = bd.getUint32(chunkStart + (i * 4), Endian.big);
    }
    for (var i = 16; i < 64; i++) {
      final s0 = rotr(7, w[i - 15]) ^ rotr(18, w[i - 15]) ^ ((w[i - 15] & 0xffffffff) >>> 3);
      final s1 = rotr(17, w[i - 2]) ^ rotr(19, w[i - 2]) ^ ((w[i - 2] & 0xffffffff) >>> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
    }

    var a = h0;
    var b = h1;
    var c = h2;
    var d = h3;
    var e = h4;
    var f = h5;
    var g = h6;
    var h = h7;

    for (var i = 0; i < 64; i++) {
      final s1 = rotr(6, e) ^ rotr(11, e) ^ rotr(25, e);
      final ch = (e & f) ^ ((~e) & g);
      final temp1 = (h + s1 + ch + k[i] + w[i]) & 0xffffffff;
      final s0 = rotr(2, a) ^ rotr(13, a) ^ rotr(22, a);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final temp2 = (s0 + maj) & 0xffffffff;

      h = g;
      g = f;
      f = e;
      e = (d + temp1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) & 0xffffffff;
    }

    h0 = (h0 + a) & 0xffffffff;
    h1 = (h1 + b) & 0xffffffff;
    h2 = (h2 + c) & 0xffffffff;
    h3 = (h3 + d) & 0xffffffff;
    h4 = (h4 + e) & 0xffffffff;
    h5 = (h5 + f) & 0xffffffff;
    h6 = (h6 + g) & 0xffffffff;
    h7 = (h7 + h) & 0xffffffff;
  }

  String hex32(int v) => (v & 0xffffffff).toRadixString(16).padLeft(8, '0');
  return '${hex32(h0)}${hex32(h1)}${hex32(h2)}${hex32(h3)}'
      '${hex32(h4)}${hex32(h5)}${hex32(h6)}${hex32(h7)}';
}

/// ============================================================================
/// 1. MODEL CẤU HÌNH RUNTIME & PROMPT TEMPLATES CỦA AI (`ai_runtime`)
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
    this.primaryModel = 'gemini-3.5-flash',
    this.fallbackModels = const [
      'gemini-3.5-flash-lite',
      'gemini-3.6-flash',
      'gemini-flash-latest',
    ],
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
    final safePrimary = isSupportedGeminiModelId(rawPrimary)
        ? rawPrimary
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

  String get canonicalHash => computeCanonicalConfigHash(toPayloadMap());

  /// Kiểm tra hợp lệ một Map cấu hình thô trước khi lưu nháp hoặc Publish
  static List<String> validateRawInput(Map<String, dynamic> raw) {
    final errors = <String>[];
    final primary = (raw['primaryModel'] as String?)?.trim() ?? '';
    if (!isSupportedGeminiModelId(primary)) {
      errors.add('Model chính "$primary" không nằm trong danh sách Whitelist hỗ trợ.');
    }

    final fallbacks = raw['fallbackModels'];
    if (fallbacks is List) {
      for (final fb in fallbacks) {
        final fbStr = fb.toString().trim();
        if (!isSupportedGeminiModelId(fbStr)) {
          errors.add('Model dự phòng "$fbStr" không nằm trong danh sách Whitelist.');
        }
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

  String get canonicalHash => computeCanonicalConfigHash(toPayloadMap());

  /// Kiểm tra tính hợp lệ và tính nhất quán của dữ liệu thô do Admin nhập
  static List<String> validateRawInput(Map<String, dynamic> raw) {
    final errors = <String>[];

    void checkRange(String key, String label, double min, double max) {
      final v = (raw[key] as num?)?.toDouble();
      if (v == null || v.isNaN || v < min || v > max) {
        errors.add('$label phải nằm trong khoảng $min đến $max.');
      }
    }

    checkRange('categorySpikeRatio', 'Ngưỡng đột biến danh mục', 0.15, 0.60);
    checkRange(
      'categoryIncomeShareThreshold',
      'Ngưỡng tỷ trọng danh mục/thu nhập',
      0.15,
      0.50,
    );
    checkRange(
      'minRecommendedSavingRate',
      'Tỷ lệ tiết kiệm khuyến nghị',
      0.05,
      0.40,
    );
    checkRange(
      'defaultSavingRateNoGoal',
      'Tỷ lệ tiết kiệm mặc định khi chưa có mục tiêu',
      0.05,
      0.35,
    );
    checkRange(
      'flexibleSpendFloorRatio',
      'Ngưỡng sàn chi tiêu linh hoạt',
      0.50,
      0.85,
    );
    checkRange(
      'planBudgetAdherenceWeight',
      'Trọng số điểm tuân thủ ngân sách',
      0.40,
      0.80,
    );
    checkRange(
      'budgetNearLimitRatio',
      'Ngưỡng cảnh báo sắp vượt ngân sách',
      0.70,
      0.95,
    );
    checkRange(
      'categoryForecastWarningRatio',
      'Ngưỡng cảnh báo dự báo danh mục tháng',
      1.15,
      1.60,
    );
    checkRange(
      'categoryForecastCriticalRatio',
      'Ngưỡng nghiêm trọng dự báo danh mục tháng',
      1.40,
      2.50,
    );
    checkRange(
      'txAnomalyWarningMultiplier',
      'Hệ số cảnh báo giao dịch lẻ bất thường',
      1.5,
      3.5,
    );
    checkRange(
      'txAnomalyCriticalMultiplier',
      'Hệ số nghiêm trọng giao dịch lẻ bất thường',
      3.0,
      6.0,
    );

    final minRec = (raw['minRecommendedSavingRate'] as num?)?.toDouble() ?? 0.20;
    final defSav = (raw['defaultSavingRateNoGoal'] as num?)?.toDouble() ?? 0.15;
    if (defSav > minRec) {
      errors.add(
        'Tỷ lệ tiết kiệm mặc định khi chưa có mục tiêu ($defSav) không được lớn hơn tỷ lệ tiết kiệm khuyến nghị chuẩn ($minRec).',
      );
    }

    final catWarn =
        (raw['categoryForecastWarningRatio'] as num?)?.toDouble() ?? 1.30;
    final catCrit =
        (raw['categoryForecastCriticalRatio'] as num?)?.toDouble() ?? 1.60;
    if (catCrit < catWarn + 0.15) {
      errors.add(
        'Ngưỡng dự báo nghiêm trọng ($catCrit) phải lớn hơn ngưỡng cảnh báo ($catWarn) ít nhất 0.15.',
      );
    }

    final txWarn =
        (raw['txAnomalyWarningMultiplier'] as num?)?.toDouble() ?? 2.0;
    final txCrit =
        (raw['txAnomalyCriticalMultiplier'] as num?)?.toDouble() ?? 4.0;
    if (txCrit < txWarn + 1.0) {
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

  const CustomPaymentProviderRule({
    required this.key,
    required this.displayLabel,
    required this.walletType,
    required this.receiptKeywords,
    required this.walletNameAliases,
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
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'key': key,
      'displayLabel': displayLabel,
      'walletType': walletType,
      'receiptKeywords': receiptKeywords,
      'walletNameAliases': walletNameAliases,
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
  final List<CustomPaymentProviderRule> customPaymentProviders;
  final DateTime? updatedAt;
  final String? updatedBy;
  final String? changeNote;

  const TransactionIntelligenceConfig({
    this.version = 1,
    this.addedExpenseKeywords = const {},
    this.addedIncomeKeywords = const {},
    this.disabledBuiltInKeywords = const [],
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

  String get canonicalHash => computeCanonicalConfigHash(toPayloadMap());

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

    final disabledSet =
        disabledBuiltInKeywords.map(normalizeVietnameseKeyword).toSet();

    for (final groupKey in allowedKeys) {
      final builtIn = (builtInKeywordsByGroup[groupKey] ?? const [])
          .map(normalizeVietnameseKeyword)
          .where((k) => !disabledSet.contains(k));
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
}

/// ============================================================================
/// 5. MODEL BẢN NHÁP (`DraftConfigEnvelope`) & LỊCH SỬ PHIÊN BẢN (`ConfigVersionSnapshot`)
/// Đảm bảo khi nội dung Draft thay đổi dù chỉ 1 ký tự, mã băm `draftHash` sẽ
/// khác với `verifiedSandboxHash` và bắt buộc Admin phải chạy lại AI Sandbox.
/// ============================================================================
class DraftConfigEnvelope {
  final String configType; // 'ai_runtime' | 'financial_heuristics' | 'transaction_rules'
  final Map<String, dynamic> draftPayload;
  final String draftHash;
  final String? verifiedSandboxHash;
  final String? serverSandboxSignature;
  final DateTime? sandboxVerifiedAt;
  final String? sandboxVerifiedBy;
  final DateTime? updatedAt;
  final String? updatedBy;

  const DraftConfigEnvelope({
    required this.configType,
    required this.draftPayload,
    required this.draftHash,
    this.verifiedSandboxHash,
    this.serverSandboxSignature,
    this.sandboxVerifiedAt,
    this.sandboxVerifiedBy,
    this.updatedAt,
    this.updatedBy,
  });

  /// Kiểm tra kết quả kiểm thử Sandbox có còn hiệu lực với nội dung bản nháp hiện tại hay không.
  /// Nếu Admin chỉnh sửa bất kỳ trường nào trong `draftPayload`, `currentComputedHash` sẽ thay đổi
  /// và làm kết quả Sandbox trước đó mất hiệu lực ngay lập tức.
  bool get isSandboxVerificationValid {
    final currentComputedHash = computeCanonicalConfigHash(draftPayload);
    return verifiedSandboxHash != null &&
        verifiedSandboxHash!.isNotEmpty &&
        verifiedSandboxHash == draftHash &&
        verifiedSandboxHash == currentComputedHash;
  }

  factory DraftConfigEnvelope.fromMap(
    Map<String, dynamic> map, {
    required String configType,
    Map<String, dynamic>? verificationDoc,
  }) {
    final payload = map['draftPayload'] is Map
        ? Map<String, dynamic>.from(map['draftPayload'] as Map)
        : <String, dynamic>{};
    final computedHash = computeCanonicalConfigHash(payload);

    final verMap = verificationDoc ?? map;
    return DraftConfigEnvelope(
      configType: configType,
      draftPayload: payload,
      draftHash: computedHash,
      verifiedSandboxHash: verMap['verifiedDraftHash'] as String?,
      serverSandboxSignature: verMap['verificationSignature'] as String?,
      sandboxVerifiedAt: verMap['verifiedAt'] != null
          ? DateTime.tryParse(verMap['verifiedAt'].toString())
          : null,
      sandboxVerifiedBy: verMap['verifiedBy'] as String?,
      updatedAt: map['updatedAt'] != null
          ? DateTime.tryParse(map['updatedAt'].toString())
          : null,
      updatedBy: map['updatedBy'] as String?,
    );
  }
}

class ConfigVersionSnapshot {
  final String versionId;
  final String configType;
  final int versionNumber;
  final Map<String, dynamic> payloadSnapshot;
  final String payloadHash;
  final String changeNote;
  final int? rollbackFromVersion;
  final String publishedBy;
  final String publishedByEmail;
  final DateTime publishedAt;

  const ConfigVersionSnapshot({
    required this.versionId,
    required this.configType,
    required this.versionNumber,
    required this.payloadSnapshot,
    required this.payloadHash,
    required this.changeNote,
    this.rollbackFromVersion,
    required this.publishedBy,
    this.publishedByEmail = '',
    required this.publishedAt,
  });

  factory ConfigVersionSnapshot.fromMap(
    Map<String, dynamic> map, {
    String? docId,
  }) {
    final payload = map['payloadSnapshot'] is Map
        ? Map<String, dynamic>.from(map['payloadSnapshot'] as Map)
        : <String, dynamic>{};
    return ConfigVersionSnapshot(
      versionId: (map['versionId'] as String?) ?? docId ?? '',
      configType: (map['configType'] as String?) ?? '',
      versionNumber: (map['versionNumber'] as num?)?.toInt() ?? 1,
      payloadSnapshot: payload,
      payloadHash: (map['payloadHash'] as String?) ??
          computeCanonicalConfigHash(payload),
      changeNote: (map['changeNote'] as String?) ?? '',
      rollbackFromVersion: (map['rollbackFromVersion'] as num?)?.toInt(),
      publishedBy: (map['publishedBy'] as String?) ?? '',
      publishedByEmail: (map['publishedByEmail'] as String?) ?? '',
      publishedAt: map['publishedAt'] != null
          ? (DateTime.tryParse(map['publishedAt'].toString()) ?? DateTime.now())
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'versionId': versionId,
      'configType': configType,
      'versionNumber': versionNumber,
      'payloadSnapshot': payloadSnapshot,
      'payloadHash': payloadHash,
      'changeNote': changeNote,
      if (rollbackFromVersion != null)
        'rollbackFromVersion': rollbackFromVersion,
      'publishedBy': publishedBy,
      'publishedByEmail': publishedByEmail,
      'publishedAt': publishedAt.toIso8601String(),
    };
  }
}

/// ============================================================================
/// 6. MODEL PHẢN HỒI CHẤT LƯỢNG AI TỪ NGƯỜI DÙNG (`ai_feedback_reports`)
/// Tách biệt rõ chế độ Ẩn danh (`anonymous`) và Giả danh (`pseudonymous`).
/// Tuyệt đối không chứa số dư ví, số tiền giao dịch hay lịch sử hội thoại.
/// ============================================================================
class AiFeedbackReport {
  static const List<String> allowedTargetFeatures = [
    'ai_chat',
    'monthly_plan',
    'ocr_suggestion',
    'anomaly_alert',
  ];

  static const List<String> allowedRatings = ['positive', 'negative'];
  static const List<String> allowedModes = ['anonymous', 'pseudonymous'];
  static const List<String> allowedStatuses = ['open', 'resolved', 'ignored'];

  static const List<String> requiredCreateKeys = [
    'reportId',
    'targetFeature',
    'rating',
    'reasonCode',
    'aiConfigVersion',
    'heuristicsVersion',
    'modelUsed',
    'dataTier',
    'feedbackMode',
    'status',
    'createdAt',
  ];

  static const List<String> allowedCreateKeys = [
    ...requiredCreateKeys,
    'userNote',
    'suggestedKeywordOrMerchant',
    'reporterHash',
  ];

  static const List<String> allowedAdminUpdateKeys = [
    'status',
    'adminResolutionNote',
    'resolvedAt',
    'resolvedBy',
    'appliedAction',
  ];

  final String reportId;
  final String targetFeature;
  final String rating; // 'positive' | 'negative'
  final String reasonCode;
  final String? userNote;
  final String? suggestedKeywordOrMerchant;
  final int aiConfigVersion;
  final int heuristicsVersion;
  final String modelUsed;
  final String dataTier;
  final String feedbackMode; // 'anonymous' | 'pseudonymous'
  final String? reporterHash;
  final String status; // 'open' | 'resolved' | 'ignored'
  final String? adminResolutionNote;
  final String? appliedAction;
  final String? resolvedBy;
  final DateTime? resolvedAt;
  final DateTime createdAt;

  const AiFeedbackReport({
    required this.reportId,
    required this.targetFeature,
    required this.rating,
    required this.reasonCode,
    this.userNote,
    this.suggestedKeywordOrMerchant,
    this.aiConfigVersion = 1,
    this.heuristicsVersion = 1,
    this.modelUsed = 'gemini-3.5-flash',
    this.dataTier = 'unknown',
    this.feedbackMode = 'anonymous',
    this.reporterHash,
    this.status = 'open',
    this.adminResolutionNote,
    this.appliedAction,
    this.resolvedBy,
    this.resolvedAt,
    required this.createdAt,
  });

  /// Làm sạch ghi chú của người dùng: cắt tối đa 250 ký tự và che các chuỗi số dài (>= 6 chữ số)
  /// để ngăn người dùng vô tình nhập số tài khoản ngân hàng, số điện thoại hoặc số tiền cụ thể.
  static String? sanitizeUserNote(String? raw) {
    if (raw == null) return null;
    var cleaned = raw.trim();
    if (cleaned.isEmpty) return null;
    cleaned = cleaned.replaceAll(RegExp(r'\d[\d\.,\s]{5,}\d'), '[SỐ_ẨN_DANH]');
    if (cleaned.length > 250) {
      cleaned = cleaned.substring(0, 250);
    }
    return cleaned;
  }

  static String? sanitizeSuggestedKeyword(String? raw) {
    if (raw == null) return null;
    final cleaned = raw.trim();
    if (cleaned.isEmpty) return null;
    return cleaned.length <= 80 ? cleaned : cleaned.substring(0, 80);
  }

  /// Tạo Map đúng chuẩn Schema `hasAll` & `hasOnly` của Firestore Security Rules
  Map<String, dynamic> toCreateMap() {
    final cleanNote = sanitizeUserNote(userNote);
    final cleanKeyword = sanitizeSuggestedKeyword(suggestedKeywordOrMerchant);

    return {
      'reportId': reportId,
      'targetFeature': allowedTargetFeatures.contains(targetFeature)
          ? targetFeature
          : 'ai_chat',
      'rating': allowedRatings.contains(rating) ? rating : 'positive',
      'reasonCode': reasonCode.trim().isEmpty ? 'general' : reasonCode.trim(),
      if (cleanNote != null) 'userNote': cleanNote,
      if (cleanKeyword != null) 'suggestedKeywordOrMerchant': cleanKeyword,
      'aiConfigVersion': aiConfigVersion,
      'heuristicsVersion': heuristicsVersion,
      'modelUsed': modelUsed,
      'dataTier': dataTier,
      'feedbackMode':
          allowedModes.contains(feedbackMode) ? feedbackMode : 'anonymous',
      if (reporterHash != null && reporterHash!.isNotEmpty)
        'reporterHash': reporterHash,
      'status': 'open',
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory AiFeedbackReport.fromMap(Map<String, dynamic> map, {String? docId}) {
    return AiFeedbackReport(
      reportId: (map['reportId'] as String?) ?? docId ?? '',
      targetFeature: (map['targetFeature'] as String?) ?? 'ai_chat',
      rating: (map['rating'] as String?) ?? 'positive',
      reasonCode: (map['reasonCode'] as String?) ?? 'general',
      userNote: map['userNote'] as String?,
      suggestedKeywordOrMerchant: map['suggestedKeywordOrMerchant'] as String?,
      aiConfigVersion: (map['aiConfigVersion'] as num?)?.toInt() ?? 1,
      heuristicsVersion: (map['heuristicsVersion'] as num?)?.toInt() ?? 1,
      modelUsed: (map['modelUsed'] as String?) ?? 'gemini-3.5-flash',
      dataTier: (map['dataTier'] as String?) ?? 'unknown',
      feedbackMode: (map['feedbackMode'] as String?) ?? 'anonymous',
      reporterHash: map['reporterHash'] as String?,
      status: (map['status'] as String?) ?? 'open',
      adminResolutionNote: map['adminResolutionNote'] as String?,
      appliedAction: map['appliedAction'] as String?,
      resolvedBy: map['resolvedBy'] as String?,
      resolvedAt: map['resolvedAt'] != null
          ? DateTime.tryParse(map['resolvedAt'].toString())
          : null,
      createdAt: map['createdAt'] != null
          ? (DateTime.tryParse(map['createdAt'].toString()) ?? DateTime.now())
          : DateTime.now(),
    );
  }
}

/// ============================================================================
/// 7. DỮ LIỆU PERSONA GIẢ LẬP CHO AI SANDBOX (`SyntheticPersona`)
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

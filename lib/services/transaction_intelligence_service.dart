import '../models/ai_runtime_config_model.dart';
import '../models/category_model.dart';
import '../models/category_suggestion.dart';
import '../models/transaction_anomaly_result.dart';
import '../models/transaction_model.dart';
import '../models/wallet_model.dart';
import '../models/wallet_suggestion.dart';
import '../l10n/app_localizations.dart';
import '../utils/category_localization_helper.dart';

class _PaymentProviderRule {
  final String key;
  final String displayLabel;

  String get localizedLabel {
    switch (key) {
      case 'cash':
        return AppLocalizations.tr('svc_ti_provider_cash');
      case 'generic_bank':
        return AppLocalizations.tr('svc_ti_provider_bank');
      case 'generic_ewallet':
        return AppLocalizations.tr('svc_ti_provider_ewallet');
      default:
        return displayLabel;
    }
  }
  final String walletType; // cash | eWallet | bank
  final List<String> receiptKeywords;
  final List<String> walletNameAliases;
  final bool isGenericType;

  const _PaymentProviderRule({
    required this.key,
    required this.displayLabel,
    required this.walletType,
    required this.receiptKeywords,
    required this.walletNameAliases,
    this.isGenericType = false,
  });
}

/// ============================================================
/// TRANSACTION INTELLIGENCE SERVICE
/// Pure Dart service cho Smart Transaction Assistant:
/// 1. Gợi ý danh mục dựa trên keyword, OCR merchant và lịch sử giao dịch.
/// 2. Gợi ý ví thanh toán dựa trên phương thức thanh toán từ OCR hóa đơn.
/// 3. Phát hiện khoản chi bất thường so với lịch sử 90 ngày.
/// ============================================================
class TransactionIntelligenceService {
  final TransactionIntelligenceConfig? _rulesOverride;
  final FinancialHeuristicsConfig? _heuristicsOverride;

  TransactionIntelligenceService({
    TransactionIntelligenceConfig? rulesOverride,
    FinancialHeuristicsConfig? heuristicsOverride,
  })  : _rulesOverride = rulesOverride,
        _heuristicsOverride = heuristicsOverride;

  /// Cấu hình từ điển nhận diện giao dịch đang hiệu lực (mặc định dùng bộ từ khóa tích hợp sẵn)
  TransactionIntelligenceConfig get effectiveRules =>
      _rulesOverride ?? TransactionIntelligenceConfig.defaults();

  /// Cấu hình ngưỡng bất thường giao dịch đơn lẻ đang hiệu lực
  FinancialHeuristicsConfig get effectiveHeuristics =>
      _heuristicsOverride ?? FinancialHeuristicsConfig.defaults();

  /// Truy cập chỉ đọc bộ từ khóa hệ thống mặc định (phục vụ kiểm tra xung đột trên Admin/Sandbox)
  static Map<String, List<String>> get builtInExpenseKeywords =>
      _expenseKeywords;
  static Map<String, List<String>> get builtInIncomeKeywords =>
      _incomeKeywords;

  /// Bảng từ khóa mở rộng cho các danh mục phổ biến (nguồn chuẩn dùng chung với Validation & Admin)
  static const Map<String, List<String>> _expenseKeywords =
      kProtectedBuiltInExpenseKeywords;

  static const Map<String, List<String>> _incomeKeywords =
      kProtectedBuiltInIncomeKeywords;

  static const _PaymentProviderRule _cashRule = _PaymentProviderRule(
    key: 'cash',
    displayLabel: 'Tiền mặt',
    walletType: 'cash',
    receiptKeywords: [
      'thanh toan tien mat',
      'tien mat',
      'tra tien mat',
      'thu tien mat',
      'cash',
    ],
    walletNameAliases: [
      'tien mat',
      'vi tien mat',
      'cash',
    ],
    isGenericType: true,
  );

  static const List<_PaymentProviderRule> _specificProviderRules = [
    // Ví điện tử cụ thể
    _PaymentProviderRule(
      key: 'momo',
      displayLabel: 'MoMo',
      walletType: 'eWallet',
      receiptKeywords: ['momo', 'vi momo'],
      walletNameAliases: ['momo'],
    ),
    _PaymentProviderRule(
      key: 'zalopay',
      displayLabel: 'ZaloPay',
      walletType: 'eWallet',
      receiptKeywords: ['zalopay', 'zalo pay', 'vi zalopay'],
      walletNameAliases: ['zalopay', 'zalo pay'],
    ),
    _PaymentProviderRule(
      key: 'shopeepay',
      displayLabel: 'ShopeePay',
      walletType: 'eWallet',
      receiptKeywords: ['shopeepay', 'shopee pay', 'airpay'],
      walletNameAliases: ['shopeepay', 'shopee pay', 'airpay'],
    ),
    _PaymentProviderRule(
      key: 'vnpay',
      displayLabel: 'VNPay',
      walletType: 'eWallet',
      receiptKeywords: ['vnpay', 'vn pay', 'vnpay-qr', 'vnpay qr'],
      walletNameAliases: ['vnpay', 'vn pay'],
    ),
    _PaymentProviderRule(
      key: 'viettel_money',
      displayLabel: 'Viettel Money',
      walletType: 'eWallet',
      receiptKeywords: ['viettel money', 'viettelpay', 'viettel pay'],
      walletNameAliases: ['viettel money', 'viettelpay', 'viettel pay'],
    ),
    _PaymentProviderRule(
      key: 'apple_pay',
      displayLabel: 'Apple Pay',
      walletType: 'eWallet',
      receiptKeywords: ['apple pay', 'applepay'],
      walletNameAliases: ['apple pay', 'applepay'],
    ),
    _PaymentProviderRule(
      key: 'google_pay',
      displayLabel: 'Google Pay',
      walletType: 'eWallet',
      receiptKeywords: ['google pay', 'googlepay', 'gpay'],
      walletNameAliases: ['google pay', 'googlepay', 'gpay'],
    ),
    _PaymentProviderRule(
      key: 'samsung_pay',
      displayLabel: 'Samsung Pay',
      walletType: 'eWallet',
      receiptKeywords: ['samsung pay', 'samsungpay'],
      walletNameAliases: ['samsung pay', 'samsungpay'],
    ),

    // Ngân hàng cụ thể
    _PaymentProviderRule(
      key: 'mbbank',
      displayLabel: 'MB Bank',
      walletType: 'bank',
      receiptKeywords: [
        'mb bank',
        'mbbank',
        'ngan hang mb',
        'ngan hang quan doi',
        'mb'
      ],
      walletNameAliases: ['mb bank', 'mbbank', 'quan doi', 'mb'],
    ),
    _PaymentProviderRule(
      key: 'vietcombank',
      displayLabel: 'Vietcombank',
      walletType: 'bank',
      receiptKeywords: ['vietcombank', 'vcb', 'ngan hang ngoai thuong'],
      walletNameAliases: ['vietcombank', 'vcb', 'ngoai thuong'],
    ),
    _PaymentProviderRule(
      key: 'techcombank',
      displayLabel: 'Techcombank',
      walletType: 'bank',
      receiptKeywords: ['techcombank', 'tcb', 'ngan hang ky thuong'],
      walletNameAliases: ['techcombank', 'tcb', 'ky thuong'],
    ),
    _PaymentProviderRule(
      key: 'vietinbank',
      displayLabel: 'VietinBank',
      walletType: 'bank',
      receiptKeywords: ['vietinbank', 'vietin bank', 'ctg', 'cong thuong'],
      walletNameAliases: ['vietinbank', 'vietin bank', 'ctg', 'cong thuong'],
    ),
    _PaymentProviderRule(
      key: 'bidv',
      displayLabel: 'BIDV',
      walletType: 'bank',
      receiptKeywords: ['bidv', 'dau tu va phat trien'],
      walletNameAliases: ['bidv'],
    ),
    _PaymentProviderRule(
      key: 'agribank',
      displayLabel: 'Agribank',
      walletType: 'bank',
      receiptKeywords: ['agribank', 'nong nghiep'],
      walletNameAliases: ['agribank'],
    ),
    _PaymentProviderRule(
      key: 'acb',
      displayLabel: 'ACB',
      walletType: 'bank',
      receiptKeywords: ['ngan hang acb', 'ngan hang a chau', 'acb'],
      walletNameAliases: ['acb', 'a chau'],
    ),
    _PaymentProviderRule(
      key: 'tpbank',
      displayLabel: 'TPBank',
      walletType: 'bank',
      receiptKeywords: ['tpbank', 'tp bank', 'tien phong bank'],
      walletNameAliases: ['tpbank', 'tp bank', 'tien phong'],
    ),
    _PaymentProviderRule(
      key: 'vpbank',
      displayLabel: 'VPBank',
      walletType: 'bank',
      receiptKeywords: ['vpbank', 'vp bank', 'thinh vuong'],
      walletNameAliases: ['vpbank', 'vp bank', 'thinh vuong'],
    ),
    _PaymentProviderRule(
      key: 'sacombank',
      displayLabel: 'Sacombank',
      walletType: 'bank',
      receiptKeywords: ['sacombank', 'stb', 'sai gon thuong tin'],
      walletNameAliases: ['sacombank', 'stb'],
    ),
    _PaymentProviderRule(
      key: 'vib',
      displayLabel: 'VIB',
      walletType: 'bank',
      receiptKeywords: ['ngan hang vib', 'quoc te vib', 'vib'],
      walletNameAliases: ['vib'],
    ),
    _PaymentProviderRule(
      key: 'hdbank',
      displayLabel: 'HDBank',
      walletType: 'bank',
      receiptKeywords: ['hdbank', 'hd bank'],
      walletNameAliases: ['hdbank', 'hd bank'],
    ),
    _PaymentProviderRule(
      key: 'shb',
      displayLabel: 'SHB',
      walletType: 'bank',
      receiptKeywords: ['ngan hang shb', 'sai gon ha noi', 'shb'],
      walletNameAliases: ['shb'],
    ),
    _PaymentProviderRule(
      key: 'msb',
      displayLabel: 'MSB',
      walletType: 'bank',
      receiptKeywords: ['ngan hang msb', 'hang hai', 'msb'],
      walletNameAliases: ['msb', 'hang hai'],
    ),
    _PaymentProviderRule(
      key: 'ocb',
      displayLabel: 'OCB',
      walletType: 'bank',
      receiptKeywords: ['ngan hang ocb', 'phuong dong', 'ocb'],
      walletNameAliases: ['ocb', 'phuong dong'],
    ),
    _PaymentProviderRule(
      key: 'seabank',
      displayLabel: 'SeABank',
      walletType: 'bank',
      receiptKeywords: ['seabank', 'sea bank'],
      walletNameAliases: ['seabank', 'sea bank'],
    ),
    _PaymentProviderRule(
      key: 'lpbank',
      displayLabel: 'LPBank',
      walletType: 'bank',
      receiptKeywords: ['lpbank', 'lienvietpostbank', 'lien viet'],
      walletNameAliases: ['lpbank', 'lienvietpostbank', 'lien viet'],
    ),
    _PaymentProviderRule(
      key: 'eximbank',
      displayLabel: 'Eximbank',
      walletType: 'bank',
      receiptKeywords: ['eximbank', 'exim bank'],
      walletNameAliases: ['eximbank', 'exim bank'],
    ),
    _PaymentProviderRule(
      key: 'cake',
      displayLabel: 'Cake',
      walletType: 'bank',
      receiptKeywords: ['cake by vpbank', 'ngan hang so cake', 'cake'],
      walletNameAliases: ['cake'],
    ),
    _PaymentProviderRule(
      key: 'timo',
      displayLabel: 'Timo',
      walletType: 'bank',
      receiptKeywords: ['timo'],
      walletNameAliases: ['timo'],
    ),
  ];

  static const List<_PaymentProviderRule> _genericProviderRules = [
    _PaymentProviderRule(
      key: 'generic_bank',
      displayLabel: 'Ngân hàng / Chuyển khoản',
      walletType: 'bank',
      receiptKeywords: [
        'chuyen khoan',
        'vietqr',
        'qr ngan hang',
        'the ngan hang',
        'the atm',
        'the tin dung',
        'quet the',
        'thanh toan the',
        'visa',
        'mastercard',
        'jcb',
        'napas',
        'pos',
        'bank transfer',
        'ngan hang',
      ],
      walletNameAliases: ['ngan hang', 'chuyen khoan', 'the', 'bank'],
      isGenericType: true,
    ),
    _PaymentProviderRule(
      key: 'generic_ewallet',
      displayLabel: 'Ví điện tử',
      walletType: 'eWallet',
      receiptKeywords: ['vi dien tu', 'e-wallet', 'ewallet'],
      walletNameAliases: ['vi dien tu', 'ewallet', 'e-wallet'],
      isGenericType: true,
    ),
  ];

  /// Loại bỏ dấu tiếng Việt và đưa về chữ thường
  static String removeVietnameseDiacritics(String str) {
    var withDiacritics = str.toLowerCase().trim();

    const vietnameseSigns = [
      'aàáạảãâầấậẩẫăằắặẳẵ',
      'eèéẹẻẽêềếệểễ',
      'iìíịỉĩ',
      'oòóọỏõôồốộổỗơờớợởỡ',
      'uùúụủũưừứựửữ',
      'yỳýỵỷỹ',
      'dđ'
    ];

    for (var i = 0; i < vietnameseSigns.length; i++) {
      for (var j = 1; j < vietnameseSigns[i].length; j++) {
        withDiacritics = withDiacritics.replaceAll(
            vietnameseSigns[i][j], vietnameseSigns[i][0]);
      }
    }
    return withDiacritics;
  }

  static bool _containsKeywordOrAlias(String text, String keyword) {
    if (text.isEmpty || keyword.isEmpty) return false;
    // Các từ viết tắt ngắn (<= 3 ký tự như mb, vcb, tcb, acb, vib, shb, msb, ocb, stb, ctg, pos, jcb)
    // phải khớp theo ranh giới từ để tránh khớp nhầm trong từ khác (VD: "combo" chứa "mb").
    if (keyword.length <= 3 && !keyword.contains(' ')) {
      final pattern = RegExp(
        '(^|[^a-z0-9])${RegExp.escape(keyword)}(\$|[^a-z0-9])',
      );
      return pattern.hasMatch(text);
    }
    return text.contains(keyword);
  }

  static bool _hasCashReceiptIndicators(String normText) {
    if (normText.isEmpty) return false;
    if (normText.contains('thanh toan tien mat') ||
        normText.contains('tra tien mat') ||
        normText.contains('thu tien mat')) {
      return true;
    }
    final hasCashReceived = normText.contains('tien nhan') ||
        normText.contains('tien khach dua') ||
        normText.contains('khach dua');
    final hasCashChange = normText.contains('tien thua') ||
        normText.contains('tien thoi') ||
        normText.contains('tien tra lai') ||
        normText.contains('tra lai khach');
    return hasCashReceived && hasCashChange;
  }

  /// Gợi ý ví thanh toán từ dữ liệu OCR hóa đơn.
  /// - Nếu hóa đơn có phương thức thanh toán khớp với ví của người dùng -> trả về isMatched = true kèm walletId.
  /// - Nếu hóa đơn có phương thức thanh toán nhưng người dùng KHÔNG có ví tương ứng -> trả về isMatched = false kèm detectedPaymentLabel.
  WalletSuggestion suggestWallet({
    String? paymentMethod,
    String? ocrRawText,
    String? ocrMerchant,
    required List<Wallet> wallets,
  }) {
    final validWallets = wallets.where((w) => w.isActive).toList();

    var normPayment = paymentMethod != null
        ? removeVietnameseDiacritics(paymentMethod)
        : '';
    if (normPayment == 'null' ||
        normPayment == 'none' ||
        normPayment == 'n/a' ||
        normPayment == 'khong ro' ||
        normPayment == 'khong co' ||
        normPayment == 'unknown') {
      normPayment = '';
    }

    final normRaw =
        ocrRawText != null ? removeVietnameseDiacritics(ocrRawText) : '';
    final normMerchant =
        ocrMerchant != null ? removeVietnameseDiacritics(ocrMerchant) : '';

    if (normPayment.isEmpty && normRaw.isEmpty && normMerchant.isEmpty) {
      return WalletSuggestion.none();
    }

    // 1. Ưu tiên kiểm tra trường paymentMethod đã được AI bóc tách từ hóa đơn
    if (normPayment.isNotEmpty) {
      // 1a. Kiểm tra Tiền mặt
      if (_cashRule.receiptKeywords
              .any((kw) => _containsKeywordOrAlias(normPayment, kw)) ||
          _hasCashReceiptIndicators(normPayment)) {
        return _resolveWalletFromRule(_cashRule, validWallets);
      }

      // 1b. Kiểm tra các Ví điện tử / Ngân hàng cụ thể (Hệ thống chuẩn + Admin bổ sung không xung đột)
      for (final rule in _effectiveSpecificProviderRules()) {
        if (rule.receiptKeywords
            .any((kw) => _containsKeywordOrAlias(normPayment, kw))) {
          return _resolveWalletFromRule(rule, validWallets);
        }
      }

      // 1c. Kiểm tra tên ví tùy chỉnh của người dùng xuất hiện trực tiếp trong paymentMethod
      for (final w in validWallets) {
        final wNorm = removeVietnameseDiacritics(w.walletName);
        if (wNorm.length >= 2 &&
            (_containsKeywordOrAlias(normPayment, wNorm) ||
                _containsKeywordOrAlias(wNorm, normPayment))) {
          return WalletSuggestion(
            walletId: w.walletId,
            walletName: w.walletName,
            detectedPaymentLabel: w.walletName,
            detectedWalletType: w.type,
            confidence: 90,
            reason: AppLocalizations.tr('svc_ti_wallet_match', params: {'wallet': w.walletName}),
            source: 'ocr',
            isMatched: true,
          );
        }
      }

      // 1d. Kiểm tra nhóm Ngân hàng / Chuyển khoản hoặc Ví điện tử chung
      for (final rule in _genericProviderRules) {
        if (rule.receiptKeywords
            .any((kw) => _containsKeywordOrAlias(normPayment, kw))) {
          return _resolveWalletFromRule(rule, validWallets);
        }
      }

      // 1e. Có paymentMethod từ hóa đơn nhưng không khớp bất kỳ ví nào của người dùng
      final cleanLabel = paymentMethod!.trim();
      return WalletSuggestion(
        walletId: '',
        walletName: '',
        detectedPaymentLabel: cleanLabel,
        detectedWalletType: 'other',
        confidence: 85,
        reason: AppLocalizations.tr('svc_ti_wallet_missing', params: {'label': cleanLabel}),
        source: 'ocr',
        isMatched: false,
      );
    }

    // 2. Fallback phân tích văn bản thô từ hóa đơn (ocrRawText + ocrMerchant)
    final combinedRaw = '$normRaw $normMerchant'.trim();
    if (combinedRaw.isNotEmpty) {
      // 2a. Dấu hiệu thanh toán tiền mặt rõ ràng trên hóa đơn ("Thanh toán tiền mặt" hoặc "Tiền nhận" + "Tiền thừa")
      if (_hasCashReceiptIndicators(combinedRaw)) {
        return _resolveWalletFromRule(_cashRule, validWallets);
      }

      // 2b. Kiểm tra các Ví điện tử / Ngân hàng cụ thể trong văn bản hóa đơn
      for (final rule in _effectiveSpecificProviderRules()) {
        if (rule.receiptKeywords
            .any((kw) => _containsKeywordOrAlias(combinedRaw, kw))) {
          return _resolveWalletFromRule(rule, validWallets);
        }
      }

      // 2c. Kiểm tra từ khóa tiền mặt thông thường
      if (_cashRule.receiptKeywords
          .any((kw) => _containsKeywordOrAlias(combinedRaw, kw))) {
        return _resolveWalletFromRule(_cashRule, validWallets);
      }

      // 2d. Kiểm tra nhóm Ngân hàng / Chuyển khoản / Thẻ hoặc Ví điện tử chung
      for (final rule in _genericProviderRules) {
        if (rule.receiptKeywords
            .any((kw) => _containsKeywordOrAlias(combinedRaw, kw))) {
          return _resolveWalletFromRule(rule, validWallets);
        }
      }

      // 2e. Kiểm tra tên ví tùy chỉnh của người dùng trong văn bản hóa đơn
      for (final w in validWallets) {
        final wNorm = removeVietnameseDiacritics(w.walletName);
        if (wNorm.length >= 3 && _containsKeywordOrAlias(combinedRaw, wNorm)) {
          return WalletSuggestion(
            walletId: w.walletId,
            walletName: w.walletName,
            detectedPaymentLabel: w.walletName,
            detectedWalletType: w.type,
            confidence: 85,
            reason: AppLocalizations.tr('svc_ti_wallet_match', params: {'wallet': w.walletName}),
            source: 'ocr',
            isMatched: true,
          );
        }
      }
    }

    return WalletSuggestion.none();
  }

  WalletSuggestion _resolveWalletFromRule(
    _PaymentProviderRule rule,
    List<Wallet> validWallets,
  ) {
    // 1. Tìm ví có tên khớp trực tiếp với các alias của rule
    for (final w in validWallets) {
      final wNorm = removeVietnameseDiacritics(w.walletName);
      final nameMatched = rule.walletNameAliases.any(
        (alias) =>
            _containsKeywordOrAlias(wNorm, alias) ||
            (wNorm.length >= 3 && _containsKeywordOrAlias(alias, wNorm)),
      );
      if (nameMatched) {
        return WalletSuggestion(
          walletId: w.walletId,
          walletName: w.walletName,
          detectedPaymentLabel: rule.localizedLabel,
          detectedWalletType: rule.walletType,
          confidence: 90,
          reason: AppLocalizations.tr('svc_ti_wallet_provider', params: {'label': rule.localizedLabel}),
          source: 'ocr',
          isMatched: true,
        );
      }
    }

    // 2. Nếu là loại ví chung (VD: Tiền mặt, Chuyển khoản ngân hàng chung, Ví điện tử chung),
    // cho phép khớp theo thuộc tính w.type tương ứng ('cash', 'bank', 'eWallet')
    if (rule.isGenericType) {
      for (final w in validWallets) {
        if (w.type == rule.walletType) {
          return WalletSuggestion(
            walletId: w.walletId,
            walletName: w.walletName,
            detectedPaymentLabel: rule.localizedLabel,
            detectedWalletType: rule.walletType,
            confidence: rule.walletType == 'cash' ? 90 : 85,
            reason: AppLocalizations.tr('svc_ti_wallet_provider', params: {'label': rule.localizedLabel}),
            source: 'ocr',
            isMatched: true,
          );
        }
      }
    }

    // 3. Người dùng không có loại ví này
    return WalletSuggestion(
      walletId: '',
      walletName: '',
      detectedPaymentLabel: rule.localizedLabel,
      detectedWalletType: rule.walletType,
      confidence: 85,
      reason:
          AppLocalizations.tr('svc_ti_wallet_missing', params: {'label': rule.localizedLabel}),
      source: 'ocr',
      isMatched: false,
    );
  }

  /// Gợi ý danh mục cho giao dịch
  /// Thứ tự ưu tiên:
  /// 1. Tên cửa hàng từ OCR (nếu có)
  /// 2. Từ khóa trong note
  /// 3. Lịch sử giao dịch tương tự cùng user
  CategorySuggestion suggestCategory({
    required String note,
    String? ocrMerchant,
    required List<Category> categories,
    required String transactionType, // income | expense
    List<AppTransaction>? userHistory,
  }) {
    // Chỉ xét các danh mục active thuộc đúng type (income/expense)
    final validCategories =
        categories.where((c) => c.type == transactionType).toList();

    if (validCategories.isEmpty) {
      return CategorySuggestion.none();
    }

    final normalizedNote = removeVietnameseDiacritics(note);
    final normalizedOcr =
        ocrMerchant != null ? removeVietnameseDiacritics(ocrMerchant) : '';

    if (normalizedNote.isEmpty && normalizedOcr.isEmpty) {
      return CategorySuggestion.none();
    }

    // 1. Ưu tiên từ OCR merchant
    if (normalizedOcr.isNotEmpty) {
      // 1a. So khớp trực tiếp tên OCR với danh mục (hỗ trợ đa ngôn ngữ cho danh mục hệ thống)
      for (final cat in validCategories) {
        for (final variant
            in CategoryLocalizationHelper.allSearchVariants(cat.name)) {
          final catNameNorm = removeVietnameseDiacritics(variant);
          if (catNameNorm.isNotEmpty &&
              (normalizedOcr.contains(catNameNorm) ||
                  catNameNorm.contains(normalizedOcr))) {
            return CategorySuggestion(
              categoryId: cat.categoryId,
              categoryName: cat.name,
              confidence: 90,
              reason: AppLocalizations.tr('svc_ti_cat_merchant',
                  params: {'merchant': ocrMerchant ?? ''}),
              source: 'ocr',
            );
          }
        }
      }
      // 1b. So khớp OCR merchant với bảng từ khóa
      final keywordMatchFromOcr =
          _matchKeyword(normalizedOcr, validCategories, transactionType);
      if (keywordMatchFromOcr != null) {
        return CategorySuggestion(
          categoryId: keywordMatchFromOcr.categoryId,
          categoryName: keywordMatchFromOcr.name,
          confidence: 85,
          reason: AppLocalizations.tr('svc_ti_cat_merchant_kw', params: {'merchant': ocrMerchant ?? ''}),
          source: 'ocr',
        );
      }
    }

    // 2. Từ khóa trong note
    if (normalizedNote.isNotEmpty) {
      // 2a. So khớp trực tiếp tên danh mục trong note (hỗ trợ đa ngôn ngữ cho danh mục hệ thống)
      for (final cat in validCategories) {
        for (final variant
            in CategoryLocalizationHelper.allSearchVariants(cat.name)) {
          final catNameNorm = removeVietnameseDiacritics(variant);
          if (catNameNorm.length >= 3 &&
              (normalizedNote.contains(catNameNorm) ||
                  catNameNorm.contains(normalizedNote))) {
            return CategorySuggestion(
              categoryId: cat.categoryId,
              categoryName: cat.name,
              confidence: 85,
              reason: AppLocalizations.tr('svc_ti_cat_note_name', params: {
                'cat': CategoryLocalizationHelper.localizeName(cat.name),
              }),
              source: 'keyword',
            );
          }
        }
      }

      // 2b. So khớp bảng từ khóa
      final keywordMatchFromNote =
          _matchKeyword(normalizedNote, validCategories, transactionType);
      if (keywordMatchFromNote != null) {
        return CategorySuggestion(
          categoryId: keywordMatchFromNote.categoryId,
          categoryName: keywordMatchFromNote.name,
          confidence: 85,
          reason: AppLocalizations.tr('svc_ti_cat_note_kw'),
          source: 'keyword',
        );
      }
    }

    // 3. Từ lịch sử giao dịch tương tự
    if (userHistory != null && userHistory.isNotEmpty) {
      final searchKey =
          normalizedOcr.isNotEmpty ? normalizedOcr : normalizedNote;
      if (searchKey.isNotEmpty) {
        final categoryCounts = <String, int>{};

        for (final tx in userHistory) {
          if (tx.type != transactionType) continue;
          final txNoteNorm =
              tx.note != null ? removeVietnameseDiacritics(tx.note!) : '';
          if (txNoteNorm.isEmpty) continue;

          if (txNoteNorm.contains(searchKey) ||
              searchKey.contains(txNoteNorm)) {
            // Chỉ đếm nếu categoryId nằm trong danh mục hợp lệ
            if (validCategories.any((c) => c.categoryId == tx.categoryId)) {
              categoryCounts[tx.categoryId] =
                  (categoryCounts[tx.categoryId] ?? 0) + 1;
            }
          }
        }

        if (categoryCounts.isNotEmpty) {
          // Lấy categoryId có số lần lặp nhiều nhất
          String? bestCatId;
          int maxCount = 0;
          categoryCounts.forEach((catId, count) {
            if (count > maxCount) {
              maxCount = count;
              bestCatId = catId;
            }
          });

          if (bestCatId != null) {
            final cat =
                validCategories.firstWhere((c) => c.categoryId == bestCatId);
            return CategorySuggestion(
              categoryId: cat.categoryId,
              categoryName: cat.name,
              confidence: 80,
              reason: AppLocalizations.tr('svc_ti_cat_history', params: {'count': '$maxCount'}),
              source: 'history',
            );
          }
        }
      }
    }

    // Không đoán nếu không khớp hoặc confidence thấp
    return CategorySuggestion.none();
  }

  /// Kết hợp danh sách nhà cung cấp thanh toán mặc định của hệ thống và các quy tắc bổ sung hợp lệ của Admin.
  /// Quy tắc hệ thống luôn đứng trước và không thể bị ghi đè bởi quy tắc Admin.
  List<_PaymentProviderRule> _effectiveSpecificProviderRules() {
    final customList = effectiveRules.customPaymentProviders;
    if (customList.isEmpty) return _specificProviderRules;

    final systemKeywords = <String>{
      ..._cashRule.receiptKeywords,
      for (final r in _specificProviderRules) ...r.receiptKeywords,
      for (final r in _genericProviderRules) ...r.receiptKeywords,
    };

    final merged = List<_PaymentProviderRule>.from(_specificProviderRules);
    for (final custom in customList) {
      if (!custom.isActive) continue;
      if (kProtectedPaymentProviderKeys.contains(custom.key)) continue;
      if (!kCanonicalWalletTypes.contains(custom.walletType)) continue;
      final safeReceiptKeywords = custom.receiptKeywords
          .map(removeVietnameseDiacritics)
          .where((kw) => kw.length >= 2 && !systemKeywords.contains(kw))
          .toList();
      if (safeReceiptKeywords.isEmpty) continue;

      final safeAliases = custom.walletNameAliases
          .map(removeVietnameseDiacritics)
          .where((a) => a.length >= 2)
          .toList();

      merged.add(_PaymentProviderRule(
        key: custom.key,
        displayLabel: custom.displayLabel,
        walletType: custom.walletType,
        receiptKeywords: safeReceiptKeywords,
        walletNameAliases:
            safeAliases.isEmpty ? safeReceiptKeywords : safeAliases,
      ));
    }
    return merged;
  }

  /// Xây dựng bảng từ khóa hợp nhất an toàn:
  /// 1. Giữ nguyên 100% ngữ nghĩa các quy tắc hệ thống mặc định (ưu tiên khớp trước).
  /// 2. Các từ khóa do Admin bổ sung phải thuộc nhóm chuẩn (`kCanonicalExpenseGroupLabels` / `kCanonicalIncomeGroupLabels`).
  /// 3. Nếu từ khóa Admin trùng với bất kỳ từ khóa hệ thống nào hoặc bị xung đột chéo giữa 2 nhóm Admin,
  ///    tự động loại bỏ phần xung đột để không bao giờ ghi đè sai ngữ nghĩa hệ thống.
  Map<String, List<String>> _buildConflictSafeAdminKeywordMap(
    String transactionType,
  ) {
    final bool isIncome = transactionType == 'income';
    final systemMap = isIncome ? _incomeKeywords : _expenseKeywords;
    final allowedGroups = isIncome
        ? kCanonicalIncomeGroupLabels.keys.toSet()
        : kCanonicalExpenseGroupLabels.keys.toSet();
    final rawAdminMap = isIncome
        ? effectiveRules.addedIncomeKeywords
        : effectiveRules.addedExpenseKeywords;

    if (rawAdminMap.isEmpty) return const {};

    final disabledAdminSet = effectiveRules.disabledAdminKeywords
        .map(removeVietnameseDiacritics)
        .toSet();

    // Tập hợp mọi từ khóa chuẩn đã thuộc quy tắc hệ thống
    final allSystemKeywords = <String>{
      for (final list in systemMap.values)
        for (final kw in list) removeVietnameseDiacritics(kw),
    };

    // Đếm tần suất xuất hiện của mỗi từ khóa Admin giữa các nhóm khác nhau để phát hiện xung đột chéo
    final adminKeywordGroupClaims = <String, Set<String>>{};
    for (final entry in rawAdminMap.entries) {
      final groupKey = removeVietnameseDiacritics(entry.key);
      if (!allowedGroups.contains(groupKey)) continue;
      for (final rawKw in entry.value) {
        final kwNorm = removeVietnameseDiacritics(rawKw);
        if (kwNorm.length < 2 ||
            allSystemKeywords.contains(kwNorm) ||
            disabledAdminSet.contains(kwNorm)) {
          continue;
        }
        adminKeywordGroupClaims.putIfAbsent(kwNorm, () => <String>{}).add(groupKey);
      }
    }

    final safeAdminMap = <String, List<String>>{};
    for (final entry in rawAdminMap.entries) {
      final groupKey = removeVietnameseDiacritics(entry.key);
      if (!allowedGroups.contains(groupKey)) continue;
      final cleanList = <String>[];
      for (final rawKw in entry.value) {
        final kwNorm = removeVietnameseDiacritics(rawKw);
        if (kwNorm.length < 2) continue;
        // Bỏ qua từ khóa Admin đang tạm tắt
        if (disabledAdminSet.contains(kwNorm)) continue;
        // Chặn ghi đè từ khóa hệ thống
        if (allSystemKeywords.contains(kwNorm)) continue;
        // Chặn từ khóa bị gán đồng thời vào >= 2 nhóm khác nhau
        final claims = adminKeywordGroupClaims[kwNorm];
        if (claims == null || claims.length != 1) continue;
        if (!cleanList.contains(kwNorm)) {
          cleanList.add(kwNorm);
        }
      }
      if (cleanList.isNotEmpty) {
        safeAdminMap[groupKey] = cleanList;
      }
    }
    return safeAdminMap;
  }

  /// Helper so khớp từ khóa (Ưu tiên quy tắc hệ thống trước, quy tắc Admin hợp lệ sau)
  Category? _matchKeyword(
      String text, List<Category> validCategories, String transactionType) {
    final systemKeywordsMap =
        transactionType == 'income' ? _incomeKeywords : _expenseKeywords;

    // Bước 1: So khớp theo bảng từ khóa hệ thống mặc định
    final systemMatch = _matchFromKeywordMap(
      text: text,
      keywordsMap: systemKeywordsMap,
      validCategories: validCategories,
      useWordBoundaryForShortKeywords: false,
    );
    if (systemMatch != null) {
      return systemMatch;
    }

    // Bước 2: So khớp theo bảng từ khóa mở rộng do Admin cấu hình (đã lọc xung đột)
    final adminKeywordsMap = _buildConflictSafeAdminKeywordMap(transactionType);
    if (adminKeywordsMap.isNotEmpty) {
      return _matchFromKeywordMap(
        text: text,
        keywordsMap: adminKeywordsMap,
        validCategories: validCategories,
        useWordBoundaryForShortKeywords: true,
      );
    }

    return null;
  }

  Category? _matchFromKeywordMap({
    required String text,
    required Map<String, List<String>> keywordsMap,
    required List<Category> validCategories,
    required bool useWordBoundaryForShortKeywords,
  }) {
    for (final entry in keywordsMap.entries) {
      final categoryGroupKey = entry.key; // e.g. 'di chuyen', 'an uong'
      final keywords = entry.value;

      final matched = keywords.any(
        (kw) => useWordBoundaryForShortKeywords
            ? _containsKeywordOrAlias(text, kw)
            : text.contains(kw),
      );
      if (matched) {
        // Tìm category nào khớp nhất với categoryGroupKey (cả tiếng Việt & tiếng Anh)
        for (final cat in validCategories) {
          for (final variant
              in CategoryLocalizationHelper.allSearchVariants(cat.name)) {
            final catNorm = removeVietnameseDiacritics(variant);
            if (catNorm.contains(categoryGroupKey) ||
                categoryGroupKey.contains(catNorm)) {
              return cat;
            }
          }
        }
        // Thử tìm category đầu tiên có tên chứa một trong các keyword
        for (final cat in validCategories) {
          for (final variant
              in CategoryLocalizationHelper.allSearchVariants(cat.name)) {
            final catNorm = removeVietnameseDiacritics(variant);
            for (final kw in keywords) {
              if (catNorm.contains(kw) || kw.contains(catNorm)) {
                return cat;
              }
            }
          }
        }
      }
    }
    return null;
  }

  /// Phát hiện khoản chi bất thường
  /// Chỉ áp dụng cho `expense`. Không áp dụng cho `income`, `transfer`, `goal_deposit`, `goal_withdraw`.
  /// So sánh với lịch sử 90 ngày gần nhất cùng category.
  TransactionAnomalyResult detectAnomaly({
    required double amount,
    required String categoryId,
    required String categoryName,
    required String transactionType,
    required List<AppTransaction> userHistory,
    DateTime? currentDate,
    String? excludeTransactionId,
    FinancialHeuristicsConfig? heuristicsOverride,
  }) {
    // Chỉ áp dụng cho expense
    if (transactionType != 'expense' || categoryId.isEmpty || amount <= 0) {
      return TransactionAnomalyResult.normal();
    }

    final h = heuristicsOverride ?? effectiveHeuristics;
    final warnMultiplier = h.txAnomalyWarningMultiplier;
    final critMultiplier = h.txAnomalyCriticalMultiplier;
    final minDiffVnd = h.txAnomalyMinDiffVnd;

    final now = currentDate ?? DateTime.now();
    final ninetyDaysAgo = now.subtract(const Duration(days: 90));

    // Lọc lịch sử 90 ngày cùng danh mục
    // Loại trừ giao dịch định kỳ có recurringScheduleId để không làm sai mức chi thông thường
    // Loại trừ giao dịch đang sửa (excludeTransactionId) nếu có
    final filteredHistory = userHistory.where((tx) {
      if (tx.type != 'expense') return false;
      if (tx.categoryId != categoryId) return false;
      if (tx.date.isBefore(ninetyDaysAgo)) return false;
      if (tx.recurringScheduleId != null &&
          tx.recurringScheduleId!.isNotEmpty) {
        return false;
      }
      if (excludeTransactionId != null &&
          excludeTransactionId.isNotEmpty &&
          tx.transactionId == excludeTransactionId) {
        return false;
      }
      return true;
    }).toList();

    // Cần ít nhất 5 giao dịch lịch sử
    if (filteredHistory.length < 5) {
      return TransactionAnomalyResult.normal();
    }

    // Tính median
    final amounts = filteredHistory.map((t) => t.amount).toList()..sort();
    final int n = amounts.length;
    final double median = (n % 2 == 1)
        ? amounts[n ~/ 2]
        : (amounts[(n ~/ 2) - 1] + amounts[n ~/ 2]) / 2.0;

    if (median <= 0) {
      return TransactionAnomalyResult.normal();
    }

    final ratio = amount / median;
    final difference = amount - median;

    // Ngưỡng cảnh báo giao dịch đơn lẻ (mặc định: amount >= median * 2 VÀ difference >= 100.000 VNĐ)
    if (ratio >= warnMultiplier && difference >= minDiffVnd) {
      final severity = ratio >= critMultiplier ? 'critical' : 'warning';
      final ratioFormatted = ratio.toStringAsFixed(1).replaceAll('.0', '');
      final reason = AppLocalizations.tr('svc_ti_anom_reason', params: {
        'ratio': ratioFormatted,
        'cat': CategoryLocalizationHelper.localizeName(categoryName),
      });

      return TransactionAnomalyResult(
        isAnomalous: true,
        severity: severity,
        currentAmount: amount,
        expectedAmount: median,
        ratio: ratio,
        difference: difference,
        categoryName: categoryName,
        historySampleSize: filteredHistory.length,
        reason: reason,
      );
    }

    return TransactionAnomalyResult.normal();
  }
}

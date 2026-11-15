/// ============================================================
/// WALLET SUGGESTION MODEL
/// Chứa thông tin gợi ý ví thanh toán từ OCR hóa đơn
/// ============================================================
class WalletSuggestion {
  final String walletId;
  final String walletName;
  final String detectedPaymentLabel;
  final String detectedWalletType; // cash | eWallet | bank | other | ''
  final int confidence; // 0–100
  final String reason;
  final String source; // ocr | none
  final bool isMatched;

  const WalletSuggestion({
    required this.walletId,
    required this.walletName,
    required this.detectedPaymentLabel,
    this.detectedWalletType = '',
    required this.confidence,
    required this.reason,
    required this.source,
    required this.isMatched,
  });

  bool get hasDetection =>
      source != 'none' &&
      (walletId.isNotEmpty || detectedPaymentLabel.isNotEmpty);

  factory WalletSuggestion.none() {
    return const WalletSuggestion(
      walletId: '',
      walletName: '',
      detectedPaymentLabel: '',
      detectedWalletType: '',
      confidence: 0,
      reason: '',
      source: 'none',
      isMatched: false,
    );
  }

  @override
  String toString() {
    return 'WalletSuggestion(walletId: $walletId, walletName: $walletName, detectedPaymentLabel: $detectedPaymentLabel, confidence: $confidence, isMatched: $isMatched, reason: $reason, source: $source)';
  }
}

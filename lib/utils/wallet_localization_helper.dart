import 'package:flutter/widgets.dart';
import '../l10n/app_localizations.dart';
import '../models/wallet_model.dart';

/// ============================================================
/// WALLET LOCALIZATION HELPER
/// Bản địa hóa tên ví Tiền mặt mặc định được khởi tạo từ setup ban đầu
/// (`Tiền mặt` <-> `Cash`), đồng thời giữ nguyên 100% tên các ví thương hiệu
/// (MB Bank, MoMo, ZaloPay...) và các ví do người dùng tự đặt/tùy chỉnh.
/// ============================================================
class WalletLocalizationHelper {
  WalletLocalizationHelper._();

  static bool isSystemCashName(String rawName) {
    final normalized = rawName.trim().toLowerCase();
    return normalized == 'tiền mặt' || normalized == 'cash';
  }

  static bool isSystemCashWallet(Wallet wallet) {
    return !wallet.isUserNamed &&
        wallet.type == 'cash' &&
        isSystemCashName(wallet.walletName);
  }

  static String localizeName(
    String rawName, {
    String? type,
    bool isUserNamed = false,
  }) {
    if (isUserNamed) return rawName;
    if (type != null && type != 'cash') return rawName;
    if (!isSystemCashName(rawName)) return rawName;
    return AppLocalizations.tr('wallet_type_cash');
  }

  static String localizeNameWithContext(
    BuildContext context,
    String rawName, {
    String? type,
    bool isUserNamed = false,
  }) {
    if (isUserNamed) return rawName;
    if (type != null && type != 'cash') return rawName;
    if (!isSystemCashName(rawName)) return rawName;
    return context.tr('wallet_type_cash');
  }

  static String localizeWallet(Wallet wallet) => localizeName(
        wallet.walletName,
        type: wallet.type,
        isUserNamed: wallet.isUserNamed,
      );

  static String localizeWalletWithContext(
    BuildContext context,
    Wallet wallet,
  ) =>
      localizeNameWithContext(
        context,
        wallet.walletName,
        type: wallet.type,
        isUserNamed: wallet.isUserNamed,
      );

  static List<String> allSearchVariants(Wallet wallet) {
    if (!isSystemCashWallet(wallet)) return [wallet.walletName];
    return <String>{wallet.walletName, 'Tiền mặt', 'Cash'}.toList();
  }
}

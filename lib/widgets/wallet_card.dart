import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/wallet_model.dart';
import '../utils/constants.dart';
import '../utils/formatters.dart';
import '../utils/wallet_localization_helper.dart';
import 'app_card.dart';

/// Nhóm loại ví dùng chung cho màn hình Ví và thẻ ví.
/// Loại không xác định sẽ được gom vào [other].
class WalletTypeStyle {
  final String key;
  final String _labelKey;
  final String _pluralKey;
  final IconData icon;

  /// Màu dùng trên nền sáng/tối thông thường (icon, thanh tỷ trọng).
  final Color color;

  /// Màu sáng hơn dùng trên nền hero gradient tối.
  final Color onDarkColor;

  const WalletTypeStyle._(
    this.key,
    this._labelKey,
    this._pluralKey,
    this.icon,
    this.color,
    this.onDarkColor,
  );

  String get label => AppLocalizations.tr(_labelKey);
  String get pluralLabel => AppLocalizations.tr(_pluralKey);

  static const bank = WalletTypeStyle._(
    'bank',
    'setup_wallet_opt_bank',
    'wallet_type_bank',
    Icons.account_balance_rounded,
    Color(0xFF2F7FB5),
    Color(0xFF8FD3EA),
  );
  static const eWallet = WalletTypeStyle._(
    'eWallet',
    'wallet_type_ewallet',
    'wallet_type_ewallet',
    Icons.phone_iphone_rounded,
    Color(0xFF7A5FC9),
    Color(0xFFC3B5F2),
  );
  static const cash = WalletTypeStyle._(
    'cash',
    'wallet_type_cash',
    'wallet_type_cash',
    Icons.payments_rounded,
    Color(0xFF2E8B57),
    Color(0xFF86DBA9),
  );
  static const other = WalletTypeStyle._(
    'other',
    'wallet_type_other',
    'wallet_type_other',
    Icons.account_balance_wallet_rounded,
    Color(0xFF6D6E69),
    Color(0xFFD3D3CE),
  );

  /// Thứ tự hiển thị các nhóm.
  static const List<WalletTypeStyle> values = [bank, eWallet, cash, other];

  static WalletTypeStyle of(String type) {
    switch (type) {
      case 'bank':
        return bank;
      case 'eWallet':
        return eWallet;
      case 'cash':
        return cash;
      default:
        return other;
    }
  }
}

/// Widget hiển thị thẻ ví tiền chuẩn Fintech
class WalletCard extends StatelessWidget {
  final Wallet wallet;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onMore;
  final double shareOfTotal;

  const WalletCard({
    super.key,
    required this.wallet,
    this.onTap,
    this.onLongPress,
    this.onMore,
    required this.shareOfTotal,
  });

  @override
  Widget build(BuildContext context) {
    final style = WalletTypeStyle.of(wallet.type);
    final isNegative = wallet.balance < 0;
    final hasDesc = wallet.description != null && wallet.description!.trim().isNotEmpty;
    final share = shareOfTotal.clamp(0.0, 1.0);

    return GestureDetector(
      onLongPress: onLongPress,
      child: AppCard(
        onTap: onTap,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: style.color.withAlpha(context.isDarkMode ? 45 : 28),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(style.icon, color: style.color, size: 23),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        WalletLocalizationHelper.localizeWalletWithContext(
                          context,
                          wallet,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: context.appTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        hasDesc ? '${style.label} • ${wallet.description!.trim()}' : style.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.appTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 130),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      AppFormatters.compactCurrency(wallet.balance, unit: '₫'),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: isNegative ? AppColors.expense : context.appTextPrimary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
                if (onMore != null)
                  IconButton(
                    onPressed: onMore,
                    visualDensity: VisualDensity.compact,
                    tooltip: context.tr('wallet_options_tooltip'),
                    icon: Icon(Icons.more_vert_rounded, size: 20, color: context.appTextSecondary),
                  )
                else
                  const SizedBox(width: 8),
              ],
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: share,
                        minHeight: 5,
                        backgroundColor: context.appInputFill,
                        valueColor: AlwaysStoppedAnimation<Color>(style.color),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        context.tr(
                          'wallet_share_of_total',
                          params: {'percent': '${(share * 100).round()}'},
                        ),
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: context.appTextSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

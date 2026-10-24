import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/wallet_model.dart';
import '../../services/firestore_service.dart';
import '../../utils/constants.dart';
import '../../utils/formatters.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_text_field.dart';
import 'category_setup_screen.dart';

/// Thiết lập ví tiền đầu tiên (Bước 2/3)
class WalletSetupScreen extends StatefulWidget {
  const WalletSetupScreen({super.key});

  @override
  State<WalletSetupScreen> createState() => _WalletSetupScreenState();
}

class _SetupWallet {
  final String name;
  final String type;
  final IconData icon;
  final Color color;
  final TextEditingController controller = TextEditingController();
  bool selected;
  _SetupWallet(this.name, this.type, this.icon, this.color,
      {this.selected = false});
}

class _WalletSetupScreenState extends State<WalletSetupScreen> {
  final _firestoreService = FirestoreService();
  bool _isLoading = false;

  final List<_SetupWallet> _suggestedWallets = [
    _SetupWallet('Tiền mặt', 'cash', Icons.money_rounded, AppColors.income,
        selected: true),
    _SetupWallet(
        'MB Bank', 'bank', Icons.account_balance_rounded, AppColors.info),
    _SetupWallet(
        'Vietcombank', 'bank', Icons.account_balance_rounded, AppColors.info),
    _SetupWallet('MoMo', 'eWallet', Icons.account_balance_wallet_rounded,
        AppColors.aiAccent),
    _SetupWallet('ZaloPay', 'eWallet', Icons.account_balance_wallet_rounded,
        AppColors.secondary),
  ];

  Future<void> _handleContinue() async {
    setState(() => _isLoading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final selectedWallets =
          _suggestedWallets.where((w) => w.selected).toList();

      for (final w in selectedWallets) {
        final balance = AppFormatters.parseCurrencyInput(w.controller.text);
        final wallet = Wallet(
          walletId: '',
          userId: uid,
          walletName: w.name,
          balance: balance,
          type: w.type,
          createdAt: DateTime.now(),
        );
        await _firestoreService.createWallet(wallet);
      }
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const CategorySetupScreen()),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        backgroundColor: context.appBackground,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight.withAlpha(25),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'BƯỚC 2/3',
                      style: GoogleFonts.inter(
                        color: AppColors.primaryLight,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Thiết lập ví',
                    style: GoogleFonts.inter(
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                      color: context.appTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Chọn loại ví bạn đang dùng và nhập số dư hiện tại để quản lý chi tiêu.',
                    style: GoogleFonts.inter(
                      color: context.appTextSecondary,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: _suggestedWallets.length,
                itemBuilder: (context, i) {
                  final wallet = _suggestedWallets[i];
                  return AppCard(
                    margin: const EdgeInsets.only(bottom: 12),
                    borderColor: wallet.selected
                        ? AppColors.primaryLight
                        : context.appBorder,
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: wallet.color.withAlpha(25),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(wallet.icon,
                                  color: wallet.color, size: 22),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    wallet.name,
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                      color: context.appTextPrimary,
                                    ),
                                  ),
                                  Text(
                                    wallet.type == 'cash'
                                        ? 'Tiền mặt'
                                        : wallet.type == 'bank'
                                            ? 'Tài khoản ngân hàng'
                                            : 'Ví điện tử',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: context.appTextSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: wallet.selected,
                              activeColor: AppColors.primaryLight,
                              onChanged: (v) =>
                                  setState(() => wallet.selected = v),
                            ),
                          ],
                        ),
                        if (wallet.selected) ...[
                          const SizedBox(height: 14),
                          AppTextField(
                            controller: wallet.controller,
                            hintText: 'Nhập số dư hiện tại (₫)',
                            prefixIcon: Icons.account_balance_wallet_outlined,
                            keyboardType: TextInputType.number,
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: AppButton(
                text: 'Tiếp tục',
                isLoading: _isLoading,
                onPressed: _handleContinue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

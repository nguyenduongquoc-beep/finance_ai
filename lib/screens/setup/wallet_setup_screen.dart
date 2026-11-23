import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../l10n/app_localizations.dart';
import '../../models/wallet_model.dart';
import '../../services/firestore_service.dart';
import '../../utils/constants.dart';
import '../../utils/formatters.dart';
import '../../utils/wallet_localization_helper.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/app_text_field.dart';
import 'category_setup_screen.dart';

/// Thiết lập ví tiền đầu tiên (Bước 1/2) — Hiện đại, thân thiện & logic
/// Chỉ giữ danh sách ví tạm trong phiên thiết lập và truyền sang Bước 2;
/// dữ liệu chỉ được ghi nguyên tử xuống Firestore khi người dùng bấm Hoàn tất ở Bước 2,
/// tránh tạo trùng ví nếu người dùng quay lại Bước 1 nhiều lần.
class WalletSetupScreen extends StatefulWidget {
  final FirestoreService? firestoreService;
  final String? userIdOverride;
  final VoidCallback? onSetupCompleted;

  const WalletSetupScreen({
    super.key,
    this.firestoreService,
    this.userIdOverride,
    this.onSetupCompleted,
  });

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
  final bool isUserNamed;

  _SetupWallet(
    this.name,
    this.type,
    this.icon,
    this.color, {
    this.selected = false,
    this.isUserNamed = false,
  });
}

class _WalletSetupScreenState extends State<WalletSetupScreen> {

  List<Map<String, String>> _quickBalances(BuildContext context) => [
        {'label': '0 ₫', 'value': '0'},
        {'label': '500K', 'value': '500.000'},
        {
          'label': context.tr('setup_wallet_million_short', params: {'n': '1'}),
          'value': '1.000.000',
        },
        {
          'label': context.tr('setup_wallet_million_short', params: {'n': '5'}),
          'value': '5.000.000',
        },
        {
          'label':
              context.tr('setup_wallet_million_short', params: {'n': '10'}),
          'value': '10.000.000',
        },
      ];

  final List<_SetupWallet> _suggestedWallets = [
    _SetupWallet(
      AppLocalizations.tr('wallet_type_cash'),
      'cash',
      Icons.payments_rounded,
      const Color(0xFF10B981),
      selected: true,
    ),
    _SetupWallet(
      'MB Bank',
      'bank',
      Icons.account_balance_rounded,
      const Color(0xFF0EA5E9),
      selected: true,
    ),
    _SetupWallet(
      'Vietcombank',
      'bank',
      Icons.account_balance_rounded,
      const Color(0xFF059669),
    ),
    _SetupWallet(
      'MoMo',
      'eWallet',
      Icons.account_balance_wallet_rounded,
      const Color(0xFFD946EF),
    ),
    _SetupWallet(
      'ZaloPay',
      'eWallet',
      Icons.account_balance_wallet_rounded,
      const Color(0xFF3B82F6),
    ),
  ];

  @override
  void dispose() {
    for (final w in _suggestedWallets) {
      w.controller.dispose();
    }
    super.dispose();
  }

  double get _totalInitialBalance {
    double sum = 0;
    for (final w in _suggestedWallets) {
      if (w.selected) {
        sum += AppFormatters.parseCurrencyInput(w.controller.text);
      }
    }
    return sum;
  }

  int get _selectedCount =>
      _suggestedWallets.where((w) => w.selected).length;

  String _walletTypeLabel(String type) {
    switch (type) {
      case 'cash':
        return context.tr('setup_wallet_type_cash_desc');
      case 'bank':
        return context.tr('setup_wallet_type_bank_desc');
      default:
        return context.tr('setup_wallet_type_ewallet_desc');
    }
  }

  void _showAddCustomWalletSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.appCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddCustomWalletSheet(
        onSubmit: ({
          required String name,
          required String selectedType,
          required String balanceText,
        }) {
          final normalizedName = name.toLowerCase();
          final existingIndex = _suggestedWallets.indexWhere(
            (w) =>
                w.type == selectedType &&
                (w.name.trim().toLowerCase() == normalizedName ||
                    (!w.isUserNamed &&
                        w.type == 'cash' &&
                        WalletLocalizationHelper.isSystemCashName(w.name) &&
                        WalletLocalizationHelper.isSystemCashName(name))),
          );

          if (existingIndex != -1) {
            setState(() {
              _suggestedWallets[existingIndex].selected = true;
              if (balanceText.isNotEmpty) {
                _suggestedWallets[existingIndex].controller.text = balanceText;
              }
            });
            return;
          }

          final icon = selectedType == 'cash'
              ? Icons.payments_rounded
              : selectedType == 'bank'
                  ? Icons.account_balance_rounded
                  : Icons.account_balance_wallet_rounded;
          final color = selectedType == 'cash'
              ? const Color(0xFF10B981)
              : selectedType == 'bank'
                  ? const Color(0xFF0EA5E9)
                  : const Color(0xFF8B5CF6);

          final newWallet = _SetupWallet(
            name,
            selectedType,
            icon,
            color,
            selected: true,
            isUserNamed: true,
          );
          newWallet.controller.text = balanceText;

          setState(() {
            _suggestedWallets.add(newWallet);
          });
        },
      ),
    );
  }

  void _handleContinue() {
    final selectedWallets =
        _suggestedWallets.where((w) => w.selected).toList();
    if (selectedWallets.isEmpty) {
      AppSnackbar.show(
        context,
        context.tr('setup_wallet_min_one'),
        isError: true,
      );
      return;
    }

    final baseTime = DateTime.now();
    final pendingWallets = <Wallet>[
      for (int i = 0; i < selectedWallets.length; i++)
        () {
          final w = selectedWallets[i];
          final balance = AppFormatters.parseCurrencyInput(w.controller.text);
          return Wallet(
            walletId: '',
            userId: widget.userIdOverride ?? '',
            walletName: w.name.trim(),
            balance: balance,
            initialBalance: balance,
            type: w.type,
            isUserNamed: w.isUserNamed,
            createdAt: baseTime.add(Duration(milliseconds: i)),
          );
        }(),
    ];

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CategorySetupScreen(
          pendingWallets: pendingWallets,
          firestoreService: widget.firestoreService,
          userIdOverride: widget.userIdOverride,
          onSetupCompleted: widget.onSetupCompleted,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        backgroundColor: context.appBackground,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 18,
                  color: context.appTextPrimary,
                ),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        title: _buildStepperHeader(currentStep: 1),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Hero Summary Card (Màu gốc dự án AppColors.primary)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.primary,
                      Color(0xFF17576E),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withAlpha(45),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              const Icon(
                                Icons.account_balance_wallet_rounded,
                                size: 16,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  context.tr('setup_wallet_hero_title'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.8,
                                    color: Colors.white.withAlpha(210),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 135),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(28),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withAlpha(60),
                              ),
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                context.tr(
                                  'setup_wallet_hero_count',
                                  params: {'count': '$_selectedCount'},
                                ),
                                maxLines: 1,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      AppFormatters.compactCurrency(_totalInitialBalance),
                      style: GoogleFonts.inter(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.tr('setup_wallet_hero_sub'),
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.white.withAlpha(220),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Danh sách ví & Nút thêm ví tùy chỉnh
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _suggestedWallets.length + 1,
                itemBuilder: (context, i) {
                  if (i == _suggestedWallets.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 20),
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primaryLight,
                          side: BorderSide(
                            color: context.appBorder,
                            width: 1.2,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _showAddCustomWalletSheet,
                        icon: const Icon(Icons.add_circle_outline_rounded,
                            size: 18),
                        label: Text(
                          context.tr('setup_wallet_add_other'),
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  }

                  final wallet = _suggestedWallets[i];
                  return AppCard(
                    margin: const EdgeInsets.only(bottom: 12),
                    borderColor: wallet.selected
                        ? AppColors.primaryLight
                        : context.appBorder,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => setState(
                              () => wallet.selected = !wallet.selected),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: wallet.color.withAlpha(24),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  wallet.icon,
                                  color: wallet.color,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      WalletLocalizationHelper
                                          .localizeNameWithContext(
                                        context,
                                        wallet.name,
                                        type: wallet.type,
                                        isUserNamed: wallet.isUserNamed,
                                      ),
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                        color: context.appTextPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _walletTypeLabel(wallet.type),
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
                                activeThumbColor: Colors.white,
                                activeTrackColor: AppColors.primaryLight,
                                onChanged: (v) =>
                                    setState(() => wallet.selected = v),
                              ),
                            ],
                          ),
                        ),
                        if (wallet.selected) ...[
                          const SizedBox(height: 12),
                          AppTextField(
                            controller: wallet.controller,
                            hintText:
                                context.tr('setup_wallet_init_bal_hint'),
                            prefixIcon: Icons.payments_outlined,
                            keyboardType: TextInputType.number,
                            inputFormatters: const [CurrencyInputFormatter()],
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 8),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: _quickBalances(context).map((preset) {
                                final label = preset['label']!;
                                final val = preset['value']!;
                                final isCurrent =
                                    wallet.controller.text.trim() == val;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        wallet.controller.text = val;
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isCurrent
                                            ? AppColors.primary.withAlpha(24)
                                            : context.appBackground,
                                        borderRadius:
                                            BorderRadius.circular(16),
                                        border: Border.all(
                                          color: isCurrent
                                              ? AppColors.primary
                                              : context.appBorder,
                                        ),
                                      ),
                                      child: Text(
                                        label,
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          fontWeight: isCurrent
                                              ? FontWeight.w600
                                              : FontWeight.w500,
                                          color: isCurrent
                                              ? AppColors.primary
                                              : context.appTextSecondary,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),

            // Thanh nút điều hướng cố định dưới đáy
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
                color: context.appCard,
                border: Border(top: BorderSide(color: context.appBorder)),
              ),
              child: AppButton(
                text: context.tr('setup_wallet_next'),
                icon: Icons.arrow_forward_rounded,
                onPressed: _handleContinue,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepperHeader({required int currentStep}) {
    final steps = [
      {'step': 1, 'label': context.tr('setup_step_wallets')},
      {'step': 2, 'label': context.tr('setup_step_categories')},
    ];

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(steps.length * 2 - 1, (index) {
          if (index.isOdd) {
            final prevStep = (index ~/ 2) + 1;
            final isPassed = currentStep > prevStep;
            return Container(
              width: 22,
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              color: isPassed ? const Color(0xFF10B981) : context.appBorder,
            );
          }

          final item = steps[index ~/ 2];
          final stepNum = item['step'] as int;
          final label = item['label'] as String;
          final isActive = stepNum == currentStep;
          final isDone = stepNum < currentStep;

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDone
                      ? const Color(0xFF10B981)
                      : isActive
                          ? AppColors.primary
                          : context.appInputFill,
                  border: Border.all(
                    color: isDone
                        ? const Color(0xFF10B981)
                        : isActive
                            ? AppColors.primaryLight
                            : context.appBorder,
                    width: 1.2,
                  ),
                ),
                child: isDone
                    ? const Icon(Icons.check_rounded,
                        size: 14, color: Colors.white)
                    : Text(
                        '$stepNum',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isActive
                              ? Colors.white
                              : context.appTextSecondary,
                        ),
                      ),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight:
                      isActive || isDone ? FontWeight.w700 : FontWeight.w500,
                  color: isActive
                      ? context.appTextPrimary
                      : isDone
                          ? const Color(0xFF10B981)
                          : context.appTextSecondary,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _AddCustomWalletSheet extends StatefulWidget {
  final void Function({
    required String name,
    required String selectedType,
    required String balanceText,
  }) onSubmit;

  const _AddCustomWalletSheet({required this.onSubmit});

  @override
  State<_AddCustomWalletSheet> createState() => _AddCustomWalletSheetState();
}

class _AddCustomWalletSheetState extends State<_AddCustomWalletSheet> {
  final _nameCtrl = TextEditingController();
  final _balanceCtrl = TextEditingController();
  String _selectedType = 'bank';

  @override
  void dispose() {
    _nameCtrl.dispose();
    _balanceCtrl.dispose();
    super.dispose();
  }

  Widget _buildTypeOption({
    required String label,
    required String value,
    required IconData icon,
  }) {
    final isSelected = value == _selectedType;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedType = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary.withAlpha(24)
                : context.appBackground,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? AppColors.primary : context.appBorder,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected
                    ? AppColors.primary
                    : context.appTextSecondary,
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected
                        ? AppColors.primary
                        : context.appTextSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  context.tr('setup_wallet_add_custom'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: context.appTextPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: _nameCtrl,
            labelText: context.tr('setup_wallet_name_label'),
            hintText: context.tr('setup_wallet_name_hint'),
            prefixIcon: Icons.account_balance_wallet_outlined,
          ),
          const SizedBox(height: 14),
          Text(
            context.tr('setup_wallet_type_label'),
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.appTextSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildTypeOption(
                label: context.tr('setup_wallet_opt_bank'),
                value: 'bank',
                icon: Icons.account_balance_rounded,
              ),
              const SizedBox(width: 8),
              _buildTypeOption(
                label: context.tr('setup_wallet_opt_ewallet'),
                value: 'eWallet',
                icon: Icons.account_balance_wallet_rounded,
              ),
              const SizedBox(width: 8),
              _buildTypeOption(
                label: context.tr('setup_wallet_opt_cash'),
                value: 'cash',
                icon: Icons.payments_rounded,
              ),
            ],
          ),
          const SizedBox(height: 14),
          AppTextField(
            controller: _balanceCtrl,
            labelText: context.tr('setup_wallet_init_bal_label'),
            hintText: '0',
            prefixIcon: Icons.attach_money_rounded,
            keyboardType: TextInputType.number,
            inputFormatters: const [CurrencyInputFormatter()],
          ),
          const SizedBox(height: 20),
          AppButton(
            text: context.tr('setup_wallet_add_to_list'),
            onPressed: () {
              final name = _nameCtrl.text.trim();
              if (name.isEmpty) return;
              widget.onSubmit(
                name: name,
                selectedType: _selectedType,
                balanceText: _balanceCtrl.text.trim(),
              );
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}

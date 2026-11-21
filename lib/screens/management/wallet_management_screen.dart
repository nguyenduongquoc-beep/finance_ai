import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../l10n/app_localizations.dart';
import '../../models/wallet_model.dart';
import '../../services/firestore_service.dart';
import '../../utils/constants.dart';
import '../../utils/formatters.dart';
import '../../utils/wallet_localization_helper.dart';
import '../../widgets/wallet_card.dart';
import '../../widgets/app_card.dart';
import '../../widgets/stream_error_widget.dart';
import '../../widgets/app_snackbar.dart';

/// 13. Ví của tôi — Danh sách, Thêm, Sửa, Ẩn/Xóa ví
class WalletManagementScreen extends StatelessWidget {
  const WalletManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final firestoreService = FirestoreService();

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(title: Text(context.tr('wal_mgmt_title'))),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        onPressed: () => _showWalletDialog(context, firestoreService, uid),
        icon: const Icon(Icons.add_rounded),
        label: Text(context.tr('wal_mgmt_add_fab'),
            style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: StreamBuilder<List<Wallet>>(
        stream: firestoreService.streamWallets(uid),
        builder: (context, snap) {
          if (snap.hasError)
            return StreamErrorWidget(error: snap.error.toString());
          final wallets = snap.data ?? [];
          if (!snap.hasData)
            return const Center(child: CircularProgressIndicator());

          final activeWallets = wallets.where((w) => w.isActive).toList();
          final totalAssets =
              activeWallets.fold<double>(0, (a, w) => a + w.balance);

          if (activeWallets.isEmpty) {
            return _EmptyWallets(
              onAdd: () => _showWalletDialog(context, firestoreService, uid),
            );
          }

          // Gom ví theo loại, mỗi nhóm sắp xếp theo số dư giảm dần.
          final groups = <WalletTypeStyle, List<Wallet>>{};
          for (final style in WalletTypeStyle.values) {
            final list = activeWallets
                .where((w) => WalletTypeStyle.of(w.type) == style)
                .toList()
              ..sort((a, b) => b.balance.compareTo(a.balance));
            if (list.isNotEmpty) groups[style] = list;
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            children: [
              _AssetsHero(
                totalAssets: totalAssets,
                walletCount: activeWallets.length,
                groups: groups,
              ),
              const SizedBox(height: 22),
              for (final entry in groups.entries) ...[
                _GroupHeader(
                  style: entry.key,
                  count: entry.value.length,
                  subtotal:
                      entry.value.fold<double>(0, (a, w) => a + w.balance),
                ),
                for (final wallet in entry.value)
                  WalletCard(
                    wallet: wallet,
                    shareOfTotal: totalAssets <= 0 || wallet.balance <= 0
                        ? 0.0
                        : (wallet.balance / totalAssets).clamp(0.0, 1.0),
                    onTap: () => _showWalletDialog(
                        context, firestoreService, uid,
                        wallet: wallet),
                    onLongPress: () => _handleDeleteWallet(
                      context,
                      firestoreService,
                      uid,
                      wallet,
                      activeWallets,
                    ),
                    onMore: () => _showWalletActions(
                      context,
                      firestoreService,
                      uid,
                      wallet,
                      activeWallets,
                    ),
                  ),
                const SizedBox(height: 10),
              ],
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    context.tr('wal_mgmt_footer_hint'),
                    style: TextStyle(
                        fontSize: 12, color: context.appTextSecondary),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Bottom sheet thao tác nhanh cho một ví (Sửa / Ẩn hoặc xóa).
  void _showWalletActions(
    BuildContext context,
    FirestoreService firestoreService,
    String uid,
    Wallet wallet,
    List<Wallet> activeWallets,
  ) {
    final style = WalletTypeStyle.of(wallet.type);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.appCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.appBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: style.color.withAlpha(28),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(style.icon, color: style.color, size: 20),
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
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: context.appTextPrimary,
                          ),
                        ),
                        Text(
                          AppFormatters.currency(wallet.balance),
                          style: TextStyle(
                              fontSize: 13, color: context.appTextSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.edit_rounded),
                title: Text(ctx.tr('wal_mgmt_action_edit')),
                onTap: () {
                  Navigator.pop(ctx);
                  _showWalletDialog(context, firestoreService, uid,
                      wallet: wallet);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.delete_outline_rounded,
                    color: AppColors.expense),
                title: Text(ctx.tr('wal_mgmt_action_del'),
                    style: const TextStyle(color: AppColors.expense)),
                onTap: () {
                  Navigator.pop(ctx);
                  _handleDeleteWallet(
                      context, firestoreService, uid, wallet, activeWallets);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleDeleteWallet(
    BuildContext context,
    FirestoreService firestoreService,
    String uid,
    Wallet wallet,
    List<Wallet> activeWallets,
  ) async {
    try {
      final inUse =
          await firestoreService.checkWalletInUse(uid, wallet.walletId);
      if (!inUse) {
        if (!context.mounted) return;
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(ctx.tr('wal_mgmt_del_title')),
            content: Text(ctx.tr('wal_mgmt_del_msg', params: {
              'name': WalletLocalizationHelper.localizeWalletWithContext(
                ctx,
                wallet,
              ),
            })),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(ctx.tr('common_cancel'))),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(ctx.tr('common_delete'),
                    style: const TextStyle(color: AppColors.expense)),
              ),
            ],
          ),
        );
        if (confirm == true) {
          await firestoreService.deleteWallet(wallet.walletId);
        }
        return;
      }

      // Ví đang được sử dụng -> Cung cấp 2 lựa chọn "Ẩn ví" hoặc "Chuyển & Xóa"
      if (!context.mounted) return;
      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.tr('wal_mgmt_in_use_title')),
          content: Text(
            ctx.tr('wal_mgmt_in_use_msg', params: {
              'name': WalletLocalizationHelper.localizeWalletWithContext(
                ctx,
                wallet,
              ),
            }),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: Text(ctx.tr('common_cancel'))),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'hide'),
              child: Text(ctx.tr('wal_mgmt_hide_btn'),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'reassign'),
              child: Text(ctx.tr('wal_mgmt_transfer_del_btn'),
                  style: const TextStyle(color: AppColors.expense)),
            ),
          ],
        ),
      );

      if (action == 'hide') {
        await firestoreService.setWalletActive(wallet.walletId, false);
        return;
      }

      if (action == 'reassign') {
        final otherWallets =
            activeWallets.where((w) => w.walletId != wallet.walletId).toList();
        if (otherWallets.isEmpty) {
          if (context.mounted) {
            AppSnackbar.show(context, context.tr('wal_mgmt_del_only_err'),
                isError: true);
          }
          return;
        }

        String? selectedWalletId = otherWallets.first.walletId;
        if (!context.mounted) return;
        final confirmReassign = await showDialog<bool>(
          context: context,
          builder: (ctx) {
            return StatefulBuilder(
              builder: (context, setState) => AlertDialog(
                title: Text(ctx.tr('wal_mgmt_transfer_title')),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(ctx.tr('wal_mgmt_transfer_desc')),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedWalletId,
                      decoration: InputDecoration(
                        labelText: ctx.tr('wal_mgmt_transfer_label'),
                        border: const OutlineInputBorder(),
                      ),
                      items: otherWallets
                          .map((w) => DropdownMenuItem(
                                value: w.walletId,
                                child: Text(
                                  WalletLocalizationHelper
                                      .localizeWalletWithContext(ctx, w),
                                ),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => selectedWalletId = v),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(ctx.tr('common_cancel'))),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(ctx.tr('cat_mgmt_del_transfer_btn'),
                        style: const TextStyle(color: AppColors.expense)),
                  ),
                ],
              ),
            );
          },
        );

        if (confirmReassign == true && selectedWalletId != null) {
          await firestoreService.reassignAndDeleteWallet(
              uid, wallet.walletId, selectedWalletId!);
          return;
        }
      }
    } catch (e) {
      debugPrint('❌ Lỗi khi xử lý xóa/ẩn ví: $e');
      if (context.mounted) {
        AppSnackbar.show(context, context.tr('wal_mgmt_action_err'),
            isError: true);
      }
    }
  }

  void _showWalletDialog(
    BuildContext context,
    FirestoreService firestoreService,
    String uid, {
    Wallet? wallet,
  }) {
    final displayedInitialName = wallet == null
        ? ''
        : WalletLocalizationHelper.localizeWalletWithContext(context, wallet);
    final nameController =
        TextEditingController(text: displayedInitialName);
    final descController =
        TextEditingController(text: wallet?.description ?? '');
    final balanceController = TextEditingController(
        text: wallet != null ? AppFormatters.number(wallet.balance) : '');
    String type = wallet?.type ?? 'cash';
    bool saving = false;
    String? nameError;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.appCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final selected = WalletTypeStyle.of(type);

          Future<void> save() async {
            final name = nameController.text.trim();
            if (name.isEmpty) {
              setSheetState(
                  () => nameError = ctx.tr('wal_mgmt_name_empty_err'));
              return;
            }

            final desc = descController.text.trim();
            final balance =
                AppFormatters.parseCurrencyInput(balanceController.text);

            setSheetState(() => saving = true);
            try {
              if (wallet == null) {
                await firestoreService.createWallet(Wallet(
                  walletId: '',
                  userId: uid,
                  walletName: name,
                  balance: balance,
                  initialBalance: balance,
                  type: type,
                  description: desc.isNotEmpty ? desc : null,
                  isUserNamed: true,
                  createdAt: DateTime.now(),
                ));
              } else {
                final keepSystemName = WalletLocalizationHelper.isSystemCashWallet(
                      wallet,
                    ) &&
                    type == 'cash' &&
                    (name == displayedInitialName || name == wallet.walletName);
                await firestoreService.updateWallet(wallet.walletId, {
                  'walletName': keepSystemName ? wallet.walletName : name,
                  'type': type,
                  'description': desc.isNotEmpty ? desc : null,
                  'isUserNamed': !keepSystemName,
                  'updatedAt': DateTime.now().toIso8601String(),
                });
              }
              if (ctx.mounted) Navigator.pop(ctx);
            } catch (e) {
              debugPrint('❌ Lỗi khi lưu ví: $e');
              if (ctx.mounted) {
                setSheetState(() => saving = false);
                AppSnackbar.show(context, ctx.tr('wal_mgmt_save_err'),
                    isError: true);
              }
            }
          }

          return Padding(
            padding:
                EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: context.appBorder,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: selected.color.withAlpha(30),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(selected.icon,
                            color: selected.color, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              wallet == null
                                  ? ctx.tr('wal_mgmt_sheet_add')
                                  : ctx.tr('wal_mgmt_sheet_edit'),
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: context.appTextPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              wallet == null
                                  ? ctx.tr('wal_mgmt_sub_add')
                                  : ctx.tr('wal_mgmt_sub_edit'),
                              style: TextStyle(
                                  fontSize: 13,
                                  color: context.appTextSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _sheetLabel(ctx, ctx.tr('wal_mgmt_type_label')),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in WalletTypeStyle.values)
                        ChoiceChip(
                          showCheckmark: false,
                          avatar: Icon(
                            s.icon,
                            size: 18,
                            color: WalletTypeStyle.of(type) == s
                                ? Colors.white
                                : s.color,
                          ),
                          label: Text(s.label),
                          selected: WalletTypeStyle.of(type) == s,
                          selectedColor: s.color,
                          labelStyle: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: WalletTypeStyle.of(type) == s
                                ? Colors.white
                                : context.appTextPrimary,
                          ),
                          onSelected: (_) => setSheetState(() => type = s.key),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _sheetLabel(ctx, ctx.tr('wal_mgmt_name_label')),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameController,
                    autofocus: wallet == null,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) {
                      if (nameError != null)
                        setSheetState(() => nameError = null);
                    },
                    decoration: InputDecoration(
                      hintText: ctx.tr('wal_mgmt_name_hint'),
                      errorText: nameError,
                      prefixIcon:
                          const Icon(Icons.label_outline_rounded, size: 20),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _sheetLabel(
                      ctx,
                      wallet == null
                          ? ctx.tr('wal_mgmt_init_balance')
                          : ctx.tr('wal_mgmt_cur_balance')),
                  const SizedBox(height: 8),
                  TextField(
                    controller: balanceController,
                    enabled: wallet ==
                        null, // Khóa field số dư khi sửa ví đã tồn tại
                    keyboardType: TextInputType.number,
                    inputFormatters: const [CurrencyInputFormatter()],
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700),
                    decoration: InputDecoration(
                      hintText: '0',
                      suffixText: '₫',
                      prefixIcon: const Icon(Icons.payments_outlined, size: 20),
                      helperText: wallet != null
                          ? ctx.tr('wal_mgmt_balance_locked_hint')
                          : null,
                      helperMaxLines: 2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _sheetLabel(ctx, ctx.tr('wal_mgmt_desc_label')),
                  const SizedBox(height: 8),
                  TextField(
                    controller: descController,
                    decoration: InputDecoration(
                      hintText: ctx.tr('wal_mgmt_desc_hint'),
                      prefixIcon: const Icon(Icons.notes_rounded, size: 20),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: OutlinedButton(
                            onPressed: saving ? null : () => Navigator.pop(ctx),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: context.appTextPrimary,
                              side: BorderSide(color: context.appBorder),
                            ),
                            child: Text(ctx.tr('common_cancel'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            onPressed: saving ? null : save,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                            ),
                            child: saving
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                    ),
                                  )
                                : Text(
                                    wallet == null
                                        ? ctx.tr('wal_mgmt_create_btn')
                                        : ctx.tr('cat_mgmt_save_changes'),
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _sheetLabel(BuildContext context, String text) => Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: context.appTextSecondary,
        ),
      );
}

/// Thẻ tổng quan tài sản: tổng số dư + cơ cấu theo loại ví (đồng bộ màu Dark Slate với Báo cáo AI).
class _AssetsHero extends StatelessWidget {
  final double totalAssets;
  final int walletCount;
  final Map<WalletTypeStyle, List<Wallet>> groups;

  const _AssetsHero({
    required this.totalAssets,
    required this.walletCount,
    required this.groups,
  });

  @override
  Widget build(BuildContext context) {
    final subtotals = {
      for (final e in groups.entries)
        e.key: e.value.fold<double>(0, (a, w) => a + w.balance),
    };
    final positiveSum =
        subtotals.values.fold<double>(0, (a, v) => a + (v > 0 ? v : 0));
    final isLarge = totalAssets.abs() >= 1e9;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1F6F8B), Color(0xFF134A5D)],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.account_balance_wallet_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        context.tr('wallet_total_assets'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.95),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.layers_rounded,
                          color: Colors.white,
                          size: 12,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          context.tr('wallet_in_use',
                              params: {'count': '$walletCount'}),
                          maxLines: 1,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            context.tr('wallet_total_balance_sub'),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              isLarge
                  ? AppFormatters.compactCurrency(totalAssets)
                  : AppFormatters.currency(totalAssets),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 30,
                color: Colors.white,
                letterSpacing: -0.6,
              ),
            ),
          ),
          if (isLarge) ...[
            const SizedBox(height: 2),
            Text(
              context.tr('wal_mgmt_detail_amount',
                  params: {'amount': AppFormatters.currency(totalAssets)}),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.75),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thanh cơ cấu tài sản theo loại ví
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    height: 8,
                    child: positiveSum <= 0
                        ? Container(color: Colors.white.withValues(alpha: 0.2))
                        : Row(
                            children: [
                              for (final e in subtotals.entries)
                                if (e.value > 0)
                                  Expanded(
                                    flex: ((e.value / positiveSum) * 1000)
                                        .round()
                                        .clamp(1, 1000),
                                    child: Container(
                                      margin: const EdgeInsets.only(right: 2),
                                      color: e.key.onDarkColor,
                                    ),
                                  ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    for (final e in subtotals.entries)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: e.key.onDarkColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            positiveSum > 0 && e.value > 0
                                ? '${e.key.label} ${((e.value / positiveSum) * 100).round()}%'
                                : e.key.label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tiêu đề nhóm ví theo loại, kèm tổng số dư của nhóm.
class _GroupHeader extends StatelessWidget {
  final WalletTypeStyle style;
  final int count;
  final double subtotal;

  const _GroupHeader({
    required this.style,
    required this.count,
    required this.subtotal,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
              color: style.color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${style.pluralLabel} · $count',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.appTextPrimary,
              ),
            ),
          ),
          Text(
            AppFormatters.compactCurrency(subtotal, unit: '₫'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color:
                  subtotal < 0 ? AppColors.expense : context.appTextSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Trạng thái chưa có ví nào.
class _EmptyWallets extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyWallets({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: AppCard(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.primary.withAlpha(24),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.account_balance_wallet_rounded,
                  size: 34,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                context.tr('wal_mgmt_empty_title'),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: context.appTextPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.tr('wal_mgmt_empty_desc'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13, height: 1.4, color: context.appTextSecondary),
              ),
              const SizedBox(height: 22),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(context.tr('wal_mgmt_empty_btn')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

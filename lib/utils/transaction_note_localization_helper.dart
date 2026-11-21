import 'package:flutter/widgets.dart';
import '../l10n/app_localizations.dart';
import '../models/saving_goal_model.dart';
import '../models/transaction_model.dart';
import '../models/wallet_model.dart';
import 'wallet_localization_helper.dart';

/// ============================================================
/// TRANSACTION NOTE LOCALIZATION HELPER
/// Dịch động ghi chú hệ thống của giao dịch nạp/rút mục tiêu tiết kiệm
/// (bao gồm cả các bản ghi đã lưu từ ngôn ngữ khác hoặc format cũ),
/// giữ nguyên tên mục tiêu cá nhân và mọi ghi chú do người dùng tự nhập.
/// ============================================================
class TransactionNoteLocalizationHelper {
  TransactionNoteLocalizationHelper._();

  static final RegExp _viDepositWithWallet = RegExp(
    r'^Nạp vào mục tiêu(?:\s+tiết kiệm)?\s+"(.+?)"\s+từ\s+(?:ví\s+)?(.+)$',
  );
  static final RegExp _viDepositNoQuotesWithWallet = RegExp(
    r'^Nạp vào mục tiêu(?:\s+tiết kiệm)?\s+(.+?)\s+từ\s+(?:ví\s+)?(.+)$',
  );
  static final RegExp _enDepositWithWallet = RegExp(
    r'^Deposit to goal\s+"(.+?)"\s+from\s+(?:wallet\s+)?(.+)$',
  );
  static final RegExp _viDepositGoalOnly = RegExp(
    r'^Nạp vào mục tiêu(?:\s+tiết kiệm)?(?:\s*[:\-]\s*|\s+)"?([^"]+?)"?$',
  );
  static final RegExp _enDepositGoalOnly = RegExp(
    r'^Deposit to goal\s+"(.+?)"$',
  );

  static final RegExp _viWithdrawWithWallet = RegExp(
    r'^Rút từ mục tiêu(?:\s+tiết kiệm)?\s+"(.+?)"\s+(?:hoàn trả\s+)?về\s+(?:ví\s+)?(.+)$',
  );
  static final RegExp _viWithdrawNoQuotesWithWallet = RegExp(
    r'^Rút từ mục tiêu(?:\s+tiết kiệm)?\s+(.+?)\s+(?:hoàn trả\s+)?về\s+(?:ví\s+)?(.+)$',
  );
  static final RegExp _enWithdrawWithWallet = RegExp(
    r'^Withdraw from goal\s+"(.+?)"\s+(?:back\s+)?to\s+(?:wallet\s+)?(.+)$',
  );
  static final RegExp _viWithdrawGoalOnly = RegExp(
    r'^Rút từ mục tiêu(?:\s+tiết kiệm)?(?:\s*[:\-]\s*|\s+)"?([^"]+?)"?$',
  );
  static final RegExp _enWithdrawGoalOnly = RegExp(
    r'^Withdraw from goal\s+"(.+?)"$',
  );

  static ({bool isSystemNote, String goalName, String walletName})? _parseGoalNote({
    required String type,
    required String note,
  }) {
    final trimmed = note.trim();
    if (trimmed.isEmpty) return null;

    if (type == 'goal_deposit') {
      for (final re in [
        _viDepositWithWallet,
        _enDepositWithWallet,
        _viDepositNoQuotesWithWallet,
      ]) {
        final m = re.firstMatch(trimmed);
        if (m != null) {
          return (
            isSystemNote: true,
            goalName: (m.group(1) ?? '').trim(),
            walletName: (m.group(2) ?? '').trim(),
          );
        }
      }
      if (trimmed == 'Nạp vào mục tiêu tiết kiệm' ||
          trimmed == 'Nạp tiền mục tiêu tiết kiệm' ||
          trimmed == 'Deposit to saving goal' ||
          trimmed == 'Saving goal deposit') {
        return (isSystemNote: true, goalName: '', walletName: '');
      }
      for (final re in [_enDepositGoalOnly, _viDepositGoalOnly]) {
        final m = re.firstMatch(trimmed);
        if (m != null) {
          return (
            isSystemNote: true,
            goalName: (m.group(1) ?? '').trim(),
            walletName: '',
          );
        }
      }
      if (trimmed.startsWith('Nạp vào mục tiêu') ||
          trimmed.startsWith('Deposit to goal')) {
        return (isSystemNote: true, goalName: '', walletName: '');
      }
      return null;
    }

    if (type == 'goal_withdraw') {
      for (final re in [
        _viWithdrawWithWallet,
        _enWithdrawWithWallet,
        _viWithdrawNoQuotesWithWallet,
      ]) {
        final m = re.firstMatch(trimmed);
        if (m != null) {
          return (
            isSystemNote: true,
            goalName: (m.group(1) ?? '').trim(),
            walletName: (m.group(2) ?? '').trim(),
          );
        }
      }
      if (trimmed == 'Rút từ mục tiêu tiết kiệm' ||
          trimmed == 'Withdraw from saving goal' ||
          trimmed == 'Saving goal withdrawal') {
        return (isSystemNote: true, goalName: '', walletName: '');
      }
      for (final re in [_enWithdrawGoalOnly, _viWithdrawGoalOnly]) {
        final m = re.firstMatch(trimmed);
        if (m != null) {
          return (
            isSystemNote: true,
            goalName: (m.group(1) ?? '').trim(),
            walletName: '',
          );
        }
      }
      if (trimmed.startsWith('Rút từ mục tiêu') ||
          trimmed.startsWith('Withdraw from goal')) {
        return (isSystemNote: true, goalName: '', walletName: '');
      }
      return null;
    }

    return null;
  }

  static String _formatWithTranslator({
    required AppTransaction tx,
    required String Function(String key, {Map<String, String>? params}) tr,
    required String Function(Wallet wallet) localizeWalletFn,
    required String Function(String rawWallet) localizeRawWalletFn,
    Wallet? wallet,
    SavingGoal? goal,
  }) {
    final rawNote = tx.note?.trim() ?? '';
    if (tx.type != 'goal_deposit' && tx.type != 'goal_withdraw') {
      return rawNote;
    }
    if (rawNote.isEmpty) return '';

    final parsed = _parseGoalNote(type: tx.type, note: rawNote);
    if (parsed == null) return tx.note ?? '';

    final resolvedGoal = parsed.goalName.isNotEmpty
        ? parsed.goalName
        : (goal?.name.trim() ?? '');
    final resolvedWallet = wallet != null
        ? localizeWalletFn(wallet)
        : (parsed.walletName.isNotEmpty
            ? localizeRawWalletFn(parsed.walletName)
            : '');

    final isDeposit = tx.type == 'goal_deposit';
    if (resolvedGoal.isNotEmpty && resolvedWallet.isNotEmpty) {
      return tr(
        isDeposit ? 'goal_mgmt_dep_tx_note' : 'goal_mgmt_wdr_tx_note',
        params: {'goal': resolvedGoal, 'wallet': resolvedWallet},
      );
    }
    if (resolvedGoal.isNotEmpty) {
      return tr(
        isDeposit
            ? 'goal_tx_note_dep_no_wallet'
            : 'goal_tx_note_wdr_no_wallet',
        params: {'goal': resolvedGoal},
      );
    }
    return tr(isDeposit ? 'tx_card_goal_deposit' : 'tx_card_goal_withdraw');
  }

  static String localizeNote(
    AppTransaction tx, {
    Wallet? wallet,
    SavingGoal? goal,
  }) {
    return _formatWithTranslator(
      tx: tx,
      tr: (key, {params}) => AppLocalizations.tr(key, params: params),
      localizeWalletFn: WalletLocalizationHelper.localizeWallet,
      localizeRawWalletFn: (raw) =>
          WalletLocalizationHelper.localizeName(raw),
      wallet: wallet,
      goal: goal,
    );
  }

  static String localizeNoteWithContext(
    BuildContext context,
    AppTransaction tx, {
    Wallet? wallet,
    SavingGoal? goal,
  }) {
    return _formatWithTranslator(
      tx: tx,
      tr: (key, {params}) => context.tr(key, params: params),
      localizeWalletFn: (w) =>
          WalletLocalizationHelper.localizeWalletWithContext(context, w),
      localizeRawWalletFn: (raw) =>
          WalletLocalizationHelper.localizeNameWithContext(context, raw),
      wallet: wallet,
      goal: goal,
    );
  }

  /// Tất cả biến thể phục vụ tìm kiếm thông minh hai chiều (VI & EN) cho giao dịch mục tiêu.
  static List<String> allSearchVariants(
    AppTransaction tx, {
    Wallet? wallet,
    SavingGoal? goal,
  }) {
    final raw = tx.note?.trim() ?? '';
    if (tx.type != 'goal_deposit' && tx.type != 'goal_withdraw') {
      return raw.isEmpty ? const [] : [raw];
    }

    final variants = <String>{
      if (raw.isNotEmpty) raw,
      localizeNote(tx, wallet: wallet, goal: goal),
    };
    if (tx.type == 'goal_deposit') {
      variants.addAll([
        'Nạp vào mục tiêu',
        'Nạp mục tiêu tiết kiệm',
        'Deposit to goal',
        'Saving goal deposit',
      ]);
    } else {
      variants.addAll([
        'Rút từ mục tiêu',
        'Rút mục tiêu tiết kiệm',
        'Withdraw from goal',
        'Saving goal withdrawal',
      ]);
    }
    if (wallet != null) {
      variants.addAll(WalletLocalizationHelper.allSearchVariants(wallet));
    }
    return variants.toList();
  }
}

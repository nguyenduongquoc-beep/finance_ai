import 'package:flutter/widgets.dart';
import '../l10n/app_localizations.dart';
import '../models/notification_model.dart';
import '../services/language_controller.dart';
import 'category_localization_helper.dart';

/// ============================================================
/// NOTIFICATION LOCALIZATION HELPER
/// Bản địa hóa động tiêu đề và nội dung thông báo hệ thống trong
/// `NotificationScreen` (bao gồm cả các thông báo đã lưu trước đó
/// bằng ngôn ngữ khác trong Firestore), đồng thời giữ nguyên văn
/// các nội dung tùy chỉnh của người dùng/Admin.
/// ============================================================
class NotificationLocalizationHelper {
  NotificationLocalizationHelper._();

  // --- Title regexes (VI & EN) ---
  static final RegExp _viRecTodayTitle = RegExp(r'^Khoản (.+?) đến hạn hôm nay$');
  static final RegExp _enRecTodayTitle = RegExp(r'^(.+?) is due today$');
  static final RegExp _viRecOverdueTitle = RegExp(r'^Khoản (.+?) đang quá hạn$');
  static final RegExp _enRecOverdueTitle = RegExp(r'^(.+?) is overdue$');
  static final RegExp _viRecSoonTitle = RegExp(r'^Khoản (.+?) sắp đến hạn$');
  static final RegExp _enRecSoonTitle = RegExp(r'^(.+?) is due soon$');
  static final RegExp _viRecFailTitle =
      RegExp(r'^Không thể ghi nhận "(.+?)" vì ví không đủ số dư$');
  static final RegExp _enRecFailTitle =
      RegExp(r'^Cannot post "(.+?)" due to insufficient balance$');
  static final RegExp _viRecOkTitle = RegExp(r'^Đã tự động hạch toán "(.+?)"$');
  static final RegExp _enRecOkTitle = RegExp(r'^Auto-posted "(.+?)"$');

  // --- Content regexes (VI & EN) ---
  static final RegExp _viBudWarnAdd = RegExp(
      r'^Bạn đã tiêu vượt 80% ngân sách tháng (.+?) cho danh mục này\.$');
  static final RegExp _enBudWarnAdd = RegExp(
      r'^You have spent over 80% of your (.+?) budget for this category\.$');
  static final RegExp _viBudWarnEdit = RegExp(
      r'^Giao dịch vừa sửa đã làm bạn tiêu vượt 80% ngân sách tháng (.+?) cho danh mục này\.$');
  static final RegExp _enBudWarnEdit = RegExp(
      r'^This edited transaction pushed spending over 80% of your (.+?) budget for this category\.$');

  static final RegExp _viRecTodayManual = RegExp(
      r'^Khoản (thu|chi) (.+?) cần bạn xác nhận để ghi nhận vào sổ\.$');
  static final RegExp _enRecTodayManual =
      RegExp(r'^Recurring (income|expense) of (.+?) awaits your confirmation\.$');

  static final RegExp _viRecTodayAuto =
      RegExp(r'^Khoản (thu|chi) (.+?) sẽ được tự động hạch toán\.$');
  static final RegExp _enRecTodayAuto = RegExp(
      r'^Recurring (income|expense) of (.+?) will be posted automatically\.$');

  static final RegExp _viRecOverdueBody = RegExp(
      r'^Khoản (thu|chi) (.+?) đã quá hạn (\d+) ngày \(từ (.+?)\)\. Chạm để xử lý ngay\.$');
  static final RegExp _enRecOverdueBody = RegExp(
      r'^Recurring (income|expense) of (.+?) is (\d+) days overdue \(since (.+?)\)\. Tap to handle\.$');

  static final RegExp _viRecSoonBody =
      RegExp(r'^Còn (\d+) ngày nữa đến hạn khoản (thu|chi) (.+?) \((.+?)\)\.$');
  static final RegExp _enRecSoonBody =
      RegExp(r'^(\d+) days until (income|expense) of (.+?) is due \((.+?)\)\.$');

  static final RegExp _viRecFailBody = RegExp(
      r'^Ví không đủ số dư để tự động thanh toán (.+?) cho kỳ (.+?)\. Vui lòng nạp thêm tiền hoặc đổi ví khác\.$');
  static final RegExp _enRecFailBody = RegExp(
      r'^Insufficient wallet balance to auto-pay (.+?) for period (.+?)\. Top up or switch wallet\.$');

  static final RegExp _viRecOkBody =
      RegExp(r'^Đã ghi nhận giao dịch (thu nhập|chi tiêu|thu|chi) (.+?) cho kỳ (.+?)\.$');
  static final RegExp _enRecOkBody =
      RegExp(r'^Recorded (income|expense) transaction of (.+?) for period (.+?)\.$');

  static final RegExp _viConfirmedNote =
      RegExp(r'^Đã xác nhận thanh toán (.+?) vào lúc (.+?)\.$');
  static final RegExp _enConfirmedNote =
      RegExp(r'^Confirmed payment of (.+?) at (.+?)\.$');

  static final RegExp _viSkippedNote =
      RegExp(r'^Đã bỏ qua kỳ giao dịch (.+?)\.$');
  static final RegExp _enSkippedNote =
      RegExp(r'^Skipped occurrence for (.+?)\.$');

  static final RegExp _viDeferredNote =
      RegExp(r'^Đã dời kỳ thanh toán sang ngày (.+?)\.$');
  static final RegExp _enDeferredNote =
      RegExp(r'^Deferred due date to (.+?)\.$');

  static String _localizeScheduleName(
    String rawName,
    String Function(String key, {Map<String, String>? params}) tr,
  ) {
    final trimmed = rawName.trim();
    final norm = trimmed.toLowerCase();
    if (norm == 'thu nhập định kỳ' || norm == 'recurring income') {
      return tr('svc_fs_rec_in_default');
    }
    if (norm == 'khoản chi định kỳ' ||
        norm == 'recurring expense' ||
        norm == 'hóa đơn định kỳ' ||
        norm == 'recurring bill') {
      return tr('svc_fs_rec_out_default');
    }
    if (norm == 'giao dịch định kỳ' || norm == 'recurring transaction') {
      return tr('svc_fs_rec_tx_default');
    }
    final catKey = CategoryLocalizationHelper.localizationKeyForName(trimmed);
    if (catKey != null) return tr(catKey);
    return trimmed;
  }

  static String _localizeDirWord(
    String token,
    String Function(String key, {Map<String, String>? params}) tr, {
    bool fullWord = false,
  }) {
    final lower = token.trim().toLowerCase();
    final isIncome = lower == 'thu' ||
        lower == 'thu nhập' ||
        lower == 'income' ||
        lower == 'in';
    if (fullWord) {
      return tr(isIncome ? 'svc_fs_rec_in_full_word' : 'svc_fs_rec_out_full_word');
    }
    return tr(isIncome ? 'svc_fs_rec_in_word' : 'svc_fs_rec_out_word');
  }

  static String _localizeAmountUnit(String rawAmount, {required bool isEnglish}) {
    final trimmed = rawAmount.trim();
    if (isEnglish) {
      return trimmed
          .replaceAll(RegExp(r'\s*VNĐ$'), ' VND')
          .replaceAll(RegExp(r'(\d)đ$'), r'$1 ₫');
    }
    return trimmed
        .replaceAll(RegExp(r'\s*VND$'), ' VNĐ')
        .replaceAll(RegExp(r'(\d)đ$'), r'$1 ₫');
  }

  static String _renderFromKey({
    required String key,
    required Map<String, String> params,
    required String Function(String key, {Map<String, String>? params}) tr,
    required bool isEnglish,
  }) {
    final resolved = <String, String>{};
    params.forEach((k, v) {
      if (k == 'name') {
        resolved[k] = _localizeScheduleName(v, tr);
      } else if (k == 'dir') {
        final full = key == 'svc_fs_rec_ok_body';
        resolved[k] = _localizeDirWord(v, tr, fullWord: full);
      } else if (k == 'amount') {
        resolved[k] = _localizeAmountUnit(v, isEnglish: isEnglish);
      } else {
        resolved[k] = v;
      }
    });
    return tr(key, params: resolved);
  }

  static String _localizeTitleInternal(
    AppNotification n, {
    required String Function(String key, {Map<String, String>? params}) tr,
    required bool isEnglish,
  }) {
    if (n.titleKey != null && n.titleKey!.isNotEmpty) {
      return _renderFromKey(
        key: n.titleKey!,
        params: n.titleParams ?? const {},
        tr: tr,
        isEnglish: isEnglish,
      );
    }

    final raw = n.title.trim();
    if (raw == 'Cảnh báo ngân sách' || raw == 'Budget Alert') {
      return tr('svc_fs_bud_warn_title');
    }

    RegExpMatch? m;
    if ((m = _viRecTodayTitle.firstMatch(raw)) != null ||
        (m = _enRecTodayTitle.firstMatch(raw)) != null) {
      return tr('svc_fs_rec_today_title', params: {
        'name': _localizeScheduleName(m!.group(1)!, tr),
      });
    }
    if ((m = _viRecOverdueTitle.firstMatch(raw)) != null ||
        (m = _enRecOverdueTitle.firstMatch(raw)) != null) {
      return tr('svc_fs_rec_overdue_title', params: {
        'name': _localizeScheduleName(m!.group(1)!, tr),
      });
    }
    if ((m = _viRecSoonTitle.firstMatch(raw)) != null ||
        (m = _enRecSoonTitle.firstMatch(raw)) != null) {
      return tr('svc_fs_rec_soon_title', params: {
        'name': _localizeScheduleName(m!.group(1)!, tr),
      });
    }
    if ((m = _viRecFailTitle.firstMatch(raw)) != null ||
        (m = _enRecFailTitle.firstMatch(raw)) != null) {
      return tr('svc_fs_rec_fail_title', params: {
        'name': _localizeScheduleName(m!.group(1)!, tr),
      });
    }
    if ((m = _viRecOkTitle.firstMatch(raw)) != null ||
        (m = _enRecOkTitle.firstMatch(raw)) != null) {
      return tr('svc_fs_rec_ok_title', params: {
        'name': _localizeScheduleName(m!.group(1)!, tr),
      });
    }

    return n.title;
  }

  static String _localizeContentInternal(
    AppNotification n, {
    required String Function(String key, {Map<String, String>? params}) tr,
    required bool isEnglish,
  }) {
    if (n.contentKey != null && n.contentKey!.isNotEmpty) {
      return _renderFromKey(
        key: n.contentKey!,
        params: n.contentParams ?? const {},
        tr: tr,
        isEnglish: isEnglish,
      );
    }

    final raw = n.content.trim();
    RegExpMatch? m;

    if ((m = _viBudWarnAdd.firstMatch(raw)) != null ||
        (m = _enBudWarnAdd.firstMatch(raw)) != null) {
      return tr('svc_fs_bud_warn_add', params: {'month': m!.group(1)!});
    }
    if ((m = _viBudWarnEdit.firstMatch(raw)) != null ||
        (m = _enBudWarnEdit.firstMatch(raw)) != null) {
      return tr('svc_fs_bud_warn_edit', params: {'month': m!.group(1)!});
    }
    if ((m = _viRecTodayManual.firstMatch(raw)) != null ||
        (m = _enRecTodayManual.firstMatch(raw)) != null) {
      return tr('svc_fs_rec_today_manual', params: {
        'dir': _localizeDirWord(m!.group(1)!, tr),
        'amount': _localizeAmountUnit(m.group(2)!, isEnglish: isEnglish),
      });
    }
    if ((m = _viRecTodayAuto.firstMatch(raw)) != null ||
        (m = _enRecTodayAuto.firstMatch(raw)) != null) {
      return tr('svc_fs_rec_today_auto', params: {
        'dir': _localizeDirWord(m!.group(1)!, tr),
        'amount': _localizeAmountUnit(m.group(2)!, isEnglish: isEnglish),
      });
    }
    if ((m = _viRecOverdueBody.firstMatch(raw)) != null ||
        (m = _enRecOverdueBody.firstMatch(raw)) != null) {
      return tr('svc_fs_rec_overdue_body', params: {
        'dir': _localizeDirWord(m!.group(1)!, tr),
        'amount': _localizeAmountUnit(m.group(2)!, isEnglish: isEnglish),
        'days': m.group(3)!,
        'date': m.group(4)!,
      });
    }
    if ((m = _viRecSoonBody.firstMatch(raw)) != null ||
        (m = _enRecSoonBody.firstMatch(raw)) != null) {
      return tr('svc_fs_rec_soon_body', params: {
        'days': m!.group(1)!,
        'dir': _localizeDirWord(m.group(2)!, tr),
        'amount': _localizeAmountUnit(m.group(3)!, isEnglish: isEnglish),
        'date': m.group(4)!,
      });
    }
    if ((m = _viRecFailBody.firstMatch(raw)) != null ||
        (m = _enRecFailBody.firstMatch(raw)) != null) {
      return tr('svc_fs_rec_fail_body', params: {
        'amount': _localizeAmountUnit(m!.group(1)!, isEnglish: isEnglish),
        'key': m.group(2)!,
      });
    }
    if ((m = _viRecOkBody.firstMatch(raw)) != null ||
        (m = _enRecOkBody.firstMatch(raw)) != null) {
      return tr('svc_fs_rec_ok_body', params: {
        'dir': _localizeDirWord(m!.group(1)!, tr, fullWord: true),
        'amount': _localizeAmountUnit(m.group(2)!, isEnglish: isEnglish),
        'key': m.group(3)!,
      });
    }
    if ((m = _viConfirmedNote.firstMatch(raw)) != null ||
        (m = _enConfirmedNote.firstMatch(raw)) != null) {
      return tr('svc_fs_rec_confirmed_note', params: {
        'amount': _localizeAmountUnit(m!.group(1)!, isEnglish: isEnglish),
        'time': m.group(2)!,
      });
    }
    if ((m = _viSkippedNote.firstMatch(raw)) != null ||
        (m = _enSkippedNote.firstMatch(raw)) != null) {
      return tr('svc_fs_rec_skipped_note', params: {'date': m!.group(1)!});
    }
    if ((m = _viDeferredNote.firstMatch(raw)) != null ||
        (m = _enDeferredNote.firstMatch(raw)) != null) {
      return tr('svc_fs_rec_deferred_note', params: {'date': m!.group(1)!});
    }
    if (raw == 'Tự động bỏ qua sau 3 ngày quá hạn xác nhận.' ||
        raw == 'Auto-skipped after 3-day confirmation grace window.') {
      return tr('svc_fs_rec_autoskip_note');
    }

    return n.content;
  }

  static String localizeTitle(AppNotification notification) =>
      _localizeTitleInternal(
        notification,
        tr: (key, {params}) => AppLocalizations.tr(key, params: params),
        isEnglish: LanguageController.isEnglish,
      );

  static String localizeContent(AppNotification notification) =>
      _localizeContentInternal(
        notification,
        tr: (key, {params}) => AppLocalizations.tr(key, params: params),
        isEnglish: LanguageController.isEnglish,
      );

  static String localizeTitleWithContext(
    BuildContext context,
    AppNotification notification,
  ) =>
      _localizeTitleInternal(
        notification,
        tr: (key, {params}) => context.tr(key, params: params),
        isEnglish: LanguageController.isEnglish,
      );

  static String localizeContentWithContext(
    BuildContext context,
    AppNotification notification,
  ) =>
      _localizeContentInternal(
        notification,
        tr: (key, {params}) => context.tr(key, params: params),
        isEnglish: LanguageController.isEnglish,
      );
}

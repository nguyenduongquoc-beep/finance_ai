import 'dart:convert';
import 'package:flutter/scheduler.dart' show SchedulerPhase;
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/recurring_transaction_model.dart';
import '../utils/category_localization_helper.dart';
import '../utils/formatters.dart';
import '../utils/wallet_localization_helper.dart';
import 'language_controller.dart';
import 'recurring_transaction_service.dart';

/// Item mô tả 1 thông báo cục bộ cần lên lịch (dùng cho cả test & production)
class ScheduledNotificationItem {
  final int notificationId;
  final String scheduleId;
  final DateTime scheduledTime;
  final String title;
  final String body;
  final String payload;
  final bool isOnDueDate;

  ScheduledNotificationItem({
    required this.notificationId,
    required this.scheduleId,
    required this.scheduledTime,
    required this.title,
    required this.body,
    required this.payload,
    required this.isOnDueDate,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScheduledNotificationItem &&
          runtimeType == other.runtimeType &&
          notificationId == other.notificationId &&
          scheduleId == other.scheduleId &&
          scheduledTime == other.scheduledTime;

  @override
  int get hashCode =>
      notificationId.hashCode ^ scheduleId.hashCode ^ scheduledTime.hashCode;
}

/// ============================================================
/// LOCAL NOTIFICATION SERVICE
/// Quản lý thông báo cục bộ trên Android/iOS cho Giao dịch định kỳ & Hóa đơn
/// ============================================================
class LocalNotificationService {
  static final LocalNotificationService _instance =
      LocalNotificationService._internal();
  factory LocalNotificationService() => _instance;
  LocalNotificationService._internal();

  static const String payloadPrefix = 'bill_reminder_v1:';
  static const String channelId = 'recurring_bill_channel';

  /// Callback điều hướng do ứng dụng người dùng đăng ký khi khởi động
  /// để tránh service tầng dữ liệu phụ thuộc vào toàn bộ UI routes.
  static void Function(String scheduleId)? onOpenRecurringSchedule;

  /// Trạng thái sẵn sàng nhận deep-link sau khi đã vượt qua Splash & đăng nhập.
  static bool isAppReadyForDeepLink = false;

  /// Điều kiện kiểm tra bổ sung (vd: user đã đăng nhập & navigator sẵn sàng).
  static bool Function()? canNavigateToDeepLink;

  static const String channelName = 'Nhắc nhở hóa đơn & Giao dịch định kỳ';
  static const String channelDesc =
      'Thông báo nhắc nhở khi sắp đến hạn hoặc đến hạn các khoản thu chi định kỳ';

  static String get _localizedChannelName => _t(
        'Nhắc nhở hóa đơn & Giao dịch định kỳ',
        'Recurring Bills & Reminders',
      );
  static String get _localizedChannelDesc => _t(
        'Thông báo nhắc nhở khi sắp đến hạn hoặc đến hạn các khoản thu chi định kỳ',
        'Reminders for upcoming and due recurring income and expenses',
      );

  static const String _dedupPrefPrefix = 'bill_notif_shown_v1_';

  FlutterLocalNotificationsPlugin? _plugin;
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;
  String? _pendingPayload;
  String? _lastSyncedFingerprint;

  NotificationDetails get _notificationDetails => NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          _localizedChannelName,
          channelDescription: _localizedChannelDesc,
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          visibility: NotificationVisibility.public,
          category: AndroidNotificationCategory.reminder,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

  Future<void> _ensureLocalizedAndroidChannel() async {
    try {
      final androidImpl = _plugin?.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        await androidImpl.createNotificationChannel(
          AndroidNotificationChannel(
            channelId,
            _localizedChannelName,
            description: _localizedChannelDesc,
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
          ),
        );
      }
    } catch (e) {
      debugPrint('[NotificationService] Error creating Android channel: $e');
    }
  }

  static String _t(
    String vi,
    String en, {
    Map<String, String> params = const {},
  }) {
    var result = LanguageController.isEnglish ? en : vi;
    params.forEach((k, v) {
      result = result.replaceAll('{$k}', v);
    });
    return result;
  }

  /// Khởi tạo plugin, đăng ký Notification Channel Android & cấu hình Timezone thực tế
  Future<void> initialize({FlutterLocalNotificationsPlugin? plugin}) async {
    if (_isInitialized && plugin == null) return;

    tz.initializeTimeZones();
    try {
      final String timeZoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timeZoneName));
      debugPrint('[NotificationService] Configured timezone: $timeZoneName');
    } catch (e) {
      debugPrint('[NotificationService] Error fetching device timezone: $e');
      try {
        tz.setLocalLocation(tz.getLocation('Asia/Ho_Chi_Minh'));
      } catch (_) {}
    }

    _plugin = plugin ?? FlutterLocalNotificationsPlugin();

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _plugin?.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          _instance._handleOrQueuePayload(payload);
        }
      },
    );

    // Đăng ký rõ ràng Android Notification Channel với mức ưu tiên cao để hiện trên thanh trạng thái
    await _ensureLocalizedAndroidChannel();

    // Xử lý khi app mở từ trạng thái bị tắt hoàn toàn (terminated) thông qua thông báo
    try {
      final launchDetails = await _plugin?.getNotificationAppLaunchDetails();
      if (launchDetails != null &&
          launchDetails.didNotificationLaunchApp &&
          launchDetails.notificationResponse?.payload != null &&
          launchDetails.notificationResponse!.payload!.isNotEmpty) {
        _pendingPayload = launchDetails.notificationResponse!.payload;
        debugPrint(
            '[NotificationService] Captured launch notification payload: $_pendingPayload');
      }
    } catch (e) {
      debugPrint(
          '[NotificationService] Error checking launch notification: $e');
    }

    _isInitialized = true;
  }

  /// Nếu app đã sẵn sàng (MainNavigation đã mount & user đã đăng nhập) thì mở ngay;
  /// ngược lại giữ [_pendingPayload] để điều hướng ngay khi vào màn hình chính.
  void _handleOrQueuePayload(String rawPayload) {
    final canOpenNow = isAppReadyForDeepLink &&
        onOpenRecurringSchedule != null &&
        (canNavigateToDeepLink == null || canNavigateToDeepLink!());
    if (!canOpenNow) {
      _pendingPayload = rawPayload;
      debugPrint(
          '[NotificationService] App not ready yet, queued payload: $rawPayload');
      return;
    }
    _pendingPayload = null;
    handleNotificationPayload(rawPayload);
  }

  /// Tiêu thụ payload mở app (dùng khi UI chính đã sẵn sàng navigatorKey)
  void consumePendingPayloadIfAny() {
    if (_pendingPayload == null || _pendingPayload!.isEmpty) return;
    final canOpenNow = isAppReadyForDeepLink &&
        onOpenRecurringSchedule != null &&
        (canNavigateToDeepLink == null || canNavigateToDeepLink!());
    if (!canOpenNow) return;

    final payload = _pendingPayload!;
    _pendingPayload = null;
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        handleNotificationPayload(payload);
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    } else {
      handleNotificationPayload(payload);
    }
  }

  /// Phục vụ kiểm thử điều hướng deep-link (cold start / in-app tap)
  @visibleForTesting
  String? get pendingPayloadForTest => _pendingPayload;

  @visibleForTesting
  void handleOrQueuePayloadForTest(String rawPayload) =>
      _handleOrQueuePayload(rawPayload);

  /// Đặt lại trạng thái sẵn sàng deep link khi đăng xuất hoặc quay lại login
  void resetNavigationReadiness() {
    isAppReadyForDeepLink = false;
    _lastSyncedFingerprint = null;
  }

  /// Kiểm tra quyền thông báo hiện tại trên thiết bị
  Future<bool> areNotificationsEnabled() async {
    if (_plugin == null || !_isInitialized) return false;
    try {
      final androidImpl = _plugin!.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        final enabled = await androidImpl.areNotificationsEnabled();
        return enabled ?? true;
      }
    } catch (_) {}
    return true;
  }

  /// Kiểm tra quyền lên lịch đúng giờ (Android 12+)
  Future<bool> canScheduleExactAlarms() async {
    if (_plugin == null || !_isInitialized) return true;
    try {
      final androidImpl = _plugin!.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        final canExact = await androidImpl.canScheduleExactNotifications();
        return canExact ?? true;
      }
    } catch (_) {}
    return true;
  }

  /// Xin quyền Notification trên Android 13+ và iOS (chỉ xin nếu chưa được cấp)
  Future<bool> requestPermission() async {
    if (_plugin == null) return false;

    try {
      final androidImplementation =
          _plugin!.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        final areEnabled =
            await androidImplementation.areNotificationsEnabled();
        if (areEnabled == true) {
          return true;
        }
        final granted =
            await androidImplementation.requestNotificationsPermission();
        return granted ?? false;
      }

      final iosImplementation = _plugin!.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (iosImplementation != null) {
        final granted = await iosImplementation.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        return granted ?? false;
      }
    } catch (e) {
      debugPrint('[NotificationService] Error requesting permission: $e');
    }

    return true;
  }

  /// Mở hộp thoại/cài đặt xin quyền nhắc đúng giờ trên Android 12+ khi người dùng chủ động bật
  Future<bool> requestExactAlarmsPermission() async {
    if (_plugin == null || !_isInitialized) return false;
    try {
      final androidImplementation =
          _plugin!.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        final already =
            await androidImplementation.canScheduleExactNotifications();
        if (already == true) return true;
        final granted =
            await androidImplementation.requestExactAlarmsPermission();
        return granted ?? false;
      }
    } catch (e) {
      debugPrint('[NotificationService] Error requesting exact alarm permission: $e');
    }
    return true;
  }

  Future<AndroidScheduleMode> _resolveAndroidScheduleMode() async {
    try {
      final androidImpl = _plugin?.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        final canExact = await androidImpl.canScheduleExactNotifications();
        if (canExact == true) {
          return AndroidScheduleMode.exactAllowWhileIdle;
        }
      }
    } catch (_) {}
    return AndroidScheduleMode.inexactAllowWhileIdle;
  }

  Future<void> _zonedScheduleWithFallback({
    required ScheduledNotificationItem item,
    required AndroidScheduleMode preferredMode,
  }) async {
    if (_plugin == null) return;
    final tzScheduledTime = tz.TZDateTime.from(item.scheduledTime, tz.local);
    try {
      await _plugin!.zonedSchedule(
        item.notificationId,
        item.title,
        item.body,
        tzScheduledTime,
        _notificationDetails,
        androidScheduleMode: preferredMode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: item.payload,
      );
    } catch (e) {
      if (preferredMode == AndroidScheduleMode.exactAllowWhileIdle) {
        try {
          await _plugin!.zonedSchedule(
            item.notificationId,
            item.title,
            item.body,
            tzScheduledTime,
            _notificationDetails,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            payload: item.payload,
          );
          return;
        } catch (fallbackError) {
          debugPrint(
              '[NotificationService] Fallback schedule error ${item.notificationId}: $fallbackError');
        }
      } else {
        debugPrint(
            '[NotificationService] Error scheduling notification ${item.notificationId}: $e');
      }
    }
  }

  /// Hiển thị thông báo ngay lập tức lên thanh trạng thái Android/iOS
  Future<void> showImmediateNotification({
    required int notificationId,
    required String title,
    required String body,
    String? scheduleId,
  }) async {
    if (_plugin == null || !_isInitialized) return;
    try {
      final payload = scheduleId != null && scheduleId.isNotEmpty
          ? '$payloadPrefix${jsonEncode({'scheduleId': scheduleId})}'
          : null;
      await _plugin!.show(
        notificationId,
        title,
        body,
        _notificationDetails,
        payload: payload,
      );
    } catch (e) {
      debugPrint(
          '[NotificationService] Error showing immediate notification: $e');
    }
  }

  /// Parse payload để lấy scheduleId
  static String? extractScheduleIdFromPayload(String rawPayload) {
    try {
      String payload = rawPayload;
      if (payload.startsWith(payloadPrefix)) {
        payload = payload.substring(payloadPrefix.length);
      }
      String scheduleId = payload;
      if (payload.startsWith('{')) {
        final map = jsonDecode(payload) as Map<String, dynamic>;
        scheduleId = (map['scheduleId'] ?? '').toString();
      }
      return scheduleId.trim().isNotEmpty ? scheduleId.trim() : null;
    } catch (_) {
      return null;
    }
  }

  /// Xử lý điều hướng khi bấm vào thông báo trên thanh trạng thái
  static void handleNotificationPayload(String rawPayload) {
    try {
      final scheduleId = extractScheduleIdFromPayload(rawPayload);
      if (scheduleId != null && scheduleId.isNotEmpty) {
        onOpenRecurringSchedule?.call(scheduleId);
      }
    } catch (e) {
      debugPrint('[NotificationService] Error handling payload: $e');
    }
  }

  /// Tính toán ID thông báo deterministic từ scheduleId và occurrenceKey
  static int generateNotificationId(String scheduleId, String occurrenceKey,
      {required bool isOnDueDate}) {
    final input =
        '$scheduleId#$occurrenceKey#${isOnDueDate ? 'due' : 'advance'}';
    int hash = 0;
    for (int i = 0; i < input.length; i++) {
      hash = (hash * 31 + input.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    return hash;
  }

  static String _resolveDisplayName(RecurringTransactionSchedule schedule) {
    if (schedule.note != null && schedule.note!.trim().isNotEmpty) {
      return CategoryLocalizationHelper.localizeName(schedule.note!.trim());
    }
    return schedule.type == 'income'
        ? _t('Thu nhập định kỳ', 'Recurring income')
        : _t('Hóa đơn định kỳ', 'Recurring bill');
  }

  /// Logic thuần Dart: Tính toán các thông báo cần lên lịch trong 90 ngày tới
  static List<ScheduledNotificationItem> calculateScheduledNotifications({
    required RecurringTransactionSchedule schedule,
    String? walletName,
    DateTime? referenceDate,
    int maxDaysAhead = 90,
  }) {
    if (!schedule.isActive) {
      return [];
    }

    final now = referenceDate ?? DateTime.now();
    final recService = RecurringTransactionService();
    final List<ScheduledNotificationItem> items = [];

    // Tính toán các kỳ lặp trong 90 ngày tới
    final occurrences = recService.nextOccurrencesInWindow(
      schedule: schedule,
      referenceDate: now,
      daysAhead: maxDaysAhead,
    );

    final String displayName = _resolveDisplayName(schedule);
    final String isTypeLabel = schedule.type == 'income'
        ? _t('Thu nhập', 'Income')
        : _t('Chi tiêu', 'Expense');
    final String walletText =
        (walletName != null && walletName.trim().isNotEmpty)
            ? WalletLocalizationHelper.localizeName(walletName.trim())
            : _t('Ví', 'Wallet');
    final String formattedAmount = AppFormatters.number(schedule.amount);
    final bool isManual =
        schedule.postingMode == RecurringTransactionSchedule.postingModeManual;

    for (final date in occurrences) {
      final occurrenceKey = RecurringTransactionService.getOccurrenceKey(date);
      final payload =
          '$payloadPrefix${jsonEncode({'scheduleId': schedule.scheduleId})}';

      // 1. Thông báo trước hạn (nếu reminderDaysBefore > 0)
      if (schedule.reminderDaysBefore > 0) {
        final advanceDate = DateTime(
          date.year,
          date.month,
          date.day - schedule.reminderDaysBefore,
          9, // 09:00 sáng
          0,
        );

        if (advanceDate.isAfter(now)) {
          final advanceId = generateNotificationId(
              schedule.scheduleId, occurrenceKey,
              isOnDueDate: false);
          final daysLeftText = schedule.reminderDaysBefore.toString();
          items.add(ScheduledNotificationItem(
            notificationId: advanceId,
            scheduleId: schedule.scheduleId,
            scheduledTime: advanceDate,
            title: isManual
                ? _t(
                    'Sắp đến hạn cần xác nhận: {name}',
                    'Confirmation due soon: {name}',
                    params: {'name': displayName},
                  )
                : _t(
                    'Sắp đến hạn: {name}',
                    'Upcoming due bill: {name}',
                    params: {'name': displayName},
                  ),
            body: isManual
                ? _t(
                    '{type}: {amount} ₫ • Ví: {wallet} • Còn {days} ngày (Cần xác nhận)',
                    '{type}: {amount} ₫ • Wallet: {wallet} • {days} days left (Confirmation required)',
                    params: {
                      'type': isTypeLabel,
                      'amount': formattedAmount,
                      'wallet': walletText,
                      'days': daysLeftText,
                    },
                  )
                : _t(
                    '{type}: {amount} ₫ • Ví: {wallet} • Còn {days} ngày',
                    '{type}: {amount} ₫ • Wallet: {wallet} • {days} days left',
                    params: {
                      'type': isTypeLabel,
                      'amount': formattedAmount,
                      'wallet': walletText,
                      'days': daysLeftText,
                    },
                  ),
            payload: payload,
            isOnDueDate: false,
          ));
        }
      }

      // 2. Thông báo đúng ngày đến hạn
      final dueDateNotificationTime = DateTime(
        date.year,
        date.month,
        date.day,
        9, // 09:00 sáng
        0,
      );

      if (dueDateNotificationTime.isAfter(now)) {
        final dueId = generateNotificationId(schedule.scheduleId, occurrenceKey,
            isOnDueDate: true);
        items.add(ScheduledNotificationItem(
          notificationId: dueId,
          scheduleId: schedule.scheduleId,
          scheduledTime: dueDateNotificationTime,
          title: isManual
              ? _t(
                  'Hôm nay cần xác nhận: {name}',
                  'Action required today: {name}',
                  params: {'name': displayName},
                )
              : _t(
                  'Hôm nay đến hạn: {name}',
                  'Due today: {name}',
                  params: {'name': displayName},
                ),
          body: isManual
              ? _t(
                  '{type}: {amount} ₫ • Ví: {wallet} • Chờ bạn xác nhận',
                  '{type}: {amount} ₫ • Wallet: {wallet} • Waiting for confirmation',
                  params: {
                    'type': isTypeLabel,
                    'amount': formattedAmount,
                    'wallet': walletText,
                  },
                )
              : '$isTypeLabel: $formattedAmount ₫ • ${_t('Ví', 'Wallet')}: $walletText',
          payload: payload,
          isOnDueDate: true,
        ));
      }
    }

    return items;
  }

  /// Kiểm tra & phát thông báo đúng 1 lần/ngày cho lịch rơi vào hôm nay sau 09:00 sáng
  /// hoặc lịch cần xác nhận đang trong thời hạn chờ 3 ngày.
  Future<void> _notifySameDayOrActiveGraceOnceIfNeeded({
    required RecurringTransactionSchedule schedule,
    String? walletName,
    required DateTime now,
  }) async {
    if (_plugin == null || !_isInitialized || !schedule.isActive) return;

    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(
      schedule.nextDueDate.year,
      schedule.nextDueDate.month,
      schedule.nextDueDate.day,
    );
    final todayNineAm = DateTime(now.year, now.month, now.day, 9, 0);

    final String displayName = _resolveDisplayName(schedule);
    final String formattedAmount = AppFormatters.number(schedule.amount);
    final String walletText =
        (walletName != null && walletName.trim().isNotEmpty)
            ? WalletLocalizationHelper.localizeName(walletName.trim())
            : _t('Ví', 'Wallet');
    final String occurrenceKey =
        RecurringTransactionService.getOccurrenceKey(schedule.nextDueDate);
    final String todayKey = RecurringTransactionService.getOccurrenceKey(today);
    final bool isManual =
        schedule.postingMode == RecurringTransactionSchedule.postingModeManual;

    final daysOverdue =
        RecurringTransactionService.calendarDaysBetween(dueDay, today);

    // A) Đúng ngày đến hạn (sau 09:00) hoặc đang quá hạn trong cửa sổ chờ 3 ngày
    final isManualInGrace = isManual &&
        daysOverdue >= 0 &&
        daysOverdue < RecurringTransactionService.manualConfirmationGraceDays;
    final isDueTodayAfterNine = daysOverdue == 0 && now.isAfter(todayNineAm);

    if (isDueTodayAfterNine || (isManualInGrace && daysOverdue > 0)) {
      final remainingGrace =
          (RecurringTransactionService.manualConfirmationGraceDays -
                  daysOverdue)
              .clamp(1, RecurringTransactionService.manualConfirmationGraceDays);
      final dueId = generateNotificationId(
        schedule.scheduleId,
        occurrenceKey,
        isOnDueDate: true,
      );
      final dedupKey =
          '$_dedupPrefPrefix${schedule.scheduleId}_${occurrenceKey}_${todayKey}_due';
      if (await _claimDailyDedupKey(dedupKey)) {
        final String title = isManual
            ? (daysOverdue == 0
                ? _t(
                    'Hôm nay cần xác nhận: {name}',
                    'Action required today: {name}',
                    params: {'name': displayName},
                  )
                : _t(
                    'Còn {days} ngày xác nhận: {name}',
                    '{days}d left to confirm: {name}',
                    params: {
                      'days': remainingGrace.toString(),
                      'name': displayName,
                    },
                  ))
            : _t(
                'Hôm nay đến hạn: {name}',
                'Due today: {name}',
                params: {'name': displayName},
              );
        final String body = isManual
            ? _t(
                '{amount} ₫ • Ví: {wallet} • Nhấn để xác nhận, bỏ qua hoặc dời ngày',
                '{amount} ₫ • Wallet: {wallet} • Tap to confirm, skip or defer',
                params: {'amount': formattedAmount, 'wallet': walletText},
              )
            : _t(
                '{amount} ₫ • Ví: {wallet} • Đến hạn hôm nay',
                '{amount} ₫ • Wallet: {wallet} • Due today',
                params: {'amount': formattedAmount, 'wallet': walletText},
              );
        await showImmediateNotification(
          notificationId: dueId,
          title: title,
          body: body,
          scheduleId: schedule.scheduleId,
        );
      }
      return;
    }

    // B) Nhắc trước hạn có ngày nhắc rơi vào hôm nay sau 09:00
    if (now.isAfter(todayNineAm) &&
        schedule.reminderDaysBefore > 0 &&
        dueDay.isAfter(today)) {
      final reminderDay = DateTime(
        dueDay.year,
        dueDay.month,
        dueDay.day - schedule.reminderDaysBefore,
      );
      if (!today.isBefore(reminderDay) && today.isBefore(dueDay)) {
        final daysLeft =
            RecurringTransactionService.calendarDaysBetween(today, dueDay);
        final advId = generateNotificationId(
          schedule.scheduleId,
          occurrenceKey,
          isOnDueDate: false,
        );
        final dedupKey =
            '$_dedupPrefPrefix${schedule.scheduleId}_${occurrenceKey}_${todayKey}_adv';
        if (await _claimDailyDedupKey(dedupKey)) {
          await showImmediateNotification(
            notificationId: advId,
            title: isManual
                ? _t(
                    'Sắp đến hạn cần xác nhận: {name}',
                    'Confirmation due soon: {name}',
                    params: {'name': displayName},
                  )
                : _t(
                    'Sắp đến hạn: {name}',
                    'Upcoming due bill: {name}',
                    params: {'name': displayName},
                  ),
            body: _t(
              '{amount} ₫ • Ví: {wallet} • Còn {days} ngày',
              '{amount} ₫ • Wallet: {wallet} • {days} days left',
              params: {
                'amount': formattedAmount,
                'wallet': walletText,
                'days': daysLeft.toString(),
              },
            ),
            scheduleId: schedule.scheduleId,
          );
        }
      }
    }
  }

  Future<bool> _claimDailyDedupKey(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentLang = LanguageController.currentLanguageCode;
      final langPrefKey = '${key}_lang';
      if (prefs.getBool(key) == true &&
          prefs.getString(langPrefKey) == currentLang) {
        return false;
      }
      await prefs.setBool(key, true);
      await prefs.setString(langPrefKey, currentLang);
      return true;
    } catch (_) {
      return true;
    }
  }

  /// Lên lịch thông báo trên thiết bị cho 1 lịch định kỳ
  Future<void> scheduleRemindersForSchedule({
    required RecurringTransactionSchedule schedule,
    String? walletName,
    DateTime? referenceDate,
  }) async {
    if (_plugin == null || !_isInitialized) return;

    // Hủy các thông báo cũ trước khi lên lịch lại
    await cancelRemindersForSchedule(
      schedule.scheduleId,
      currentNextDueDate: schedule.nextDueDate,
    );

    if (!schedule.isActive) return;

    final now = referenceDate ?? DateTime.now();
    await _notifySameDayOrActiveGraceOnceIfNeeded(
      schedule: schedule,
      walletName: walletName,
      now: now,
    );

    final items = calculateScheduledNotifications(
      schedule: schedule,
      walletName: walletName,
      referenceDate: referenceDate,
    );
    final scheduleMode = await _resolveAndroidScheduleMode();

    for (final item in items) {
      await _zonedScheduleWithFallback(
        item: item,
        preferredMode: scheduleMode,
      );
    }
    _lastSyncedFingerprint = null;
  }

  /// Hủy thông báo của 1 kỳ cụ thể (khi kỳ đó đã được xác nhận, bỏ qua hoặc hoãn),
  /// đồng thời xóa luôn thông báo đã hiển thị trên thanh trạng thái nếu đang mở.
  Future<void> cancelNotificationForOccurrence(
    String scheduleId,
    String occurrenceKey,
  ) async {
    if (_plugin == null || !_isInitialized) return;
    try {
      final dueId = generateNotificationId(
        scheduleId,
        occurrenceKey,
        isOnDueDate: true,
      );
      final advId = generateNotificationId(
        scheduleId,
        occurrenceKey,
        isOnDueDate: false,
      );
      await _plugin!.cancel(dueId);
      await _plugin!.cancel(advId);
    } catch (e) {
      debugPrint(
          '[NotificationService] Error canceling occurrence notification: $e');
    }
  }

  /// Hủy các thông báo liên quan đến 1 scheduleId (cả pending lẫn đã hiện trên tray)
  Future<void> cancelRemindersForSchedule(
    String scheduleId, {
    DateTime? currentNextDueDate,
  }) async {
    if (_plugin == null || !_isInitialized) return;

    try {
      if (currentNextDueDate != null) {
        final key =
            RecurringTransactionService.getOccurrenceKey(currentNextDueDate);
        await cancelNotificationForOccurrence(scheduleId, key);
      }
      final todayKey =
          RecurringTransactionService.getOccurrenceKey(DateTime.now());
      await cancelNotificationForOccurrence(scheduleId, todayKey);

      final pending = await _plugin!.pendingNotificationRequests();
      for (final req in pending) {
        final reqScheduleId = req.payload != null
            ? extractScheduleIdFromPayload(req.payload!)
            : null;
        if (reqScheduleId == scheduleId ||
            (req.payload != null &&
                req.payload!.startsWith(payloadPrefix) &&
                req.payload!.contains(scheduleId))) {
          await _plugin!.cancel(req.id);
        }
      }

      // Xóa cả thông báo đã xuất hiện trên thanh trạng thái Android (active tray)
      try {
        final active = await _plugin!.getActiveNotifications();
        for (final act in active) {
          final actScheduleId = act.payload != null
              ? extractScheduleIdFromPayload(act.payload!)
              : null;
          if (act.id != null &&
              (actScheduleId == scheduleId ||
                  (act.payload != null &&
                      act.payload!.startsWith(payloadPrefix) &&
                      act.payload!.contains(scheduleId)))) {
            await _plugin!.cancel(act.id!);
          }
        }
      } catch (_) {}
      _lastSyncedFingerprint = null;
    } catch (e) {
      debugPrint('[NotificationService] Error canceling reminders: $e');
    }
  }

  static const int maxTotalNotifications = 50;

  /// Logic thuần Dart: Gom toàn bộ thông báo ứng viên trong [maxDaysAhead] ngày tới
  /// của TẤT CẢ các lịch đang hoạt động, sắp xếp tăng dần theo `scheduledTime`
  /// rồi mới cắt lấy tối đa [maxTotal] (mặc định 50) thông báo gần nhất.
  /// Nhờ đó lịch hàng tuần sẽ không chiếm hết slot của các lịch đứng sau.
  static List<ScheduledNotificationItem> selectFairScheduledNotifications({
    required List<RecurringTransactionSchedule> schedules,
    required Map<String, String> walletNamesMap,
    DateTime? referenceDate,
    int maxDaysAhead = 90,
    int maxTotal = maxTotalNotifications,
  }) {
    if (maxTotal <= 0) return const [];
    final now = referenceDate ?? DateTime.now();
    final allCandidates = <ScheduledNotificationItem>[];

    for (final schedule in schedules) {
      if (!schedule.isActive) continue;
      final walletName = walletNamesMap[schedule.walletId];
      allCandidates.addAll(
        calculateScheduledNotifications(
          schedule: schedule,
          walletName: walletName,
          referenceDate: now,
          maxDaysAhead: maxDaysAhead,
        ),
      );
    }

    allCandidates.sort((a, b) {
      final timeCmp = a.scheduledTime.compareTo(b.scheduledTime);
      if (timeCmp != 0) return timeCmp;
      // Ưu tiên nhắc đúng hạn trước nhắc sớm nếu trùng đúng mốc thời gian
      if (a.isOnDueDate != b.isOnDueDate) {
        return a.isOnDueDate ? -1 : 1;
      }
      final schedCmp = a.scheduleId.compareTo(b.scheduleId);
      if (schedCmp != 0) return schedCmp;
      return a.notificationId.compareTo(b.notificationId);
    });

    if (allCandidates.length <= maxTotal) {
      return allCandidates;
    }
    return allCandidates.sublist(0, maxTotal);
  }

  String _buildSyncFingerprint({
    required List<RecurringTransactionSchedule> schedules,
    required Map<String, String> walletNamesMap,
  }) {
    final sorted = [...schedules]
      ..sort((a, b) => a.scheduleId.compareTo(b.scheduleId));
    final parts = sorted.map((s) {
      final wName = walletNamesMap[s.walletId] ?? '';
      return '${s.scheduleId}|${s.isActive}|${s.postingMode}|${s.frequency}|${s.walletId}|${s.nextDueDate.toIso8601String()}|${s.reminderDaysBefore}|${s.amount}|${s.note ?? ''}|$wName';
    }).join(';');
    final todayKey = RecurringTransactionService.getOccurrenceKey(DateTime.now());
    return '${LanguageController.currentLanguageCode}|$todayKey|$parts';
  }

  /// Đồng bộ toàn bộ thông báo cho danh sách tất cả các lịch lặp của user (tối đa 50,
  /// phân bổ công bằng theo thời gian gần nhất trên toàn bộ lịch đang bật).
  Future<void> syncAllReminders({
    required List<RecurringTransactionSchedule> schedules,
    required Map<String, String> walletNamesMap,
    DateTime? referenceDate,
    bool force = false,
  }) async {
    if (_plugin == null || !_isInitialized) return;

    final fingerprint = _buildSyncFingerprint(
      schedules: schedules,
      walletNamesMap: walletNamesMap,
    );
    if (!force &&
        referenceDate == null &&
        _lastSyncedFingerprint == fingerprint) {
      return;
    }

    try {
      await _ensureLocalizedAndroidChannel();
      final now = referenceDate ?? DateTime.now();

      // Hủy các thông báo lặp cũ của Bill Reminder (dựa vào payloadPrefix)
      final pending = await _plugin!.pendingNotificationRequests();
      for (final req in pending) {
        if (req.payload != null && req.payload!.startsWith(payloadPrefix)) {
          await _plugin!.cancel(req.id);
        }
      }

      // Dọn các thông báo trên tray thuộc các lịch đã tạm dừng / xóa / không còn ở hạn
      try {
        final activeIdsBySchedule = <String, RecurringTransactionSchedule>{
          for (final s in schedules.where((e) => e.isActive)) s.scheduleId: s,
        };
        final active = await _plugin!.getActiveNotifications();
        for (final act in active) {
          if (act.id == null || act.payload == null) continue;
          if (!act.payload!.startsWith(payloadPrefix)) continue;
          final sId = extractScheduleIdFromPayload(act.payload!);
          final schedule = sId != null ? activeIdsBySchedule[sId] : null;
          if (schedule == null) {
            await _plugin!.cancel(act.id!);
          } else {
            final dueOnly =
                RecurringTransactionService.dateOnly(schedule.nextDueDate);
            final todayOnly = RecurringTransactionService.dateOnly(now);
            final daysUntilDue =
                RecurringTransactionService.calendarDaysBetween(
                    todayOnly, dueOnly);
            if (daysUntilDue > schedule.reminderDaysBefore) {
              // Kỳ đã xác nhận/bỏ qua/hoãn sang kỳ xa hơn -> xóa thông báo cũ trên tray
              await _plugin!.cancel(act.id!);
            }
          }
        }
      } catch (_) {}

      final scheduleMode = await _resolveAndroidScheduleMode();

      // 1. Kiểm tra & phát bù thông báo trong ngày / trong cửa sổ ân hạn cho mọi lịch bật
      for (final schedule in schedules) {
        if (!schedule.isActive) continue;
        await _notifySameDayOrActiveGraceOnceIfNeeded(
          schedule: schedule,
          walletName: walletNamesMap[schedule.walletId],
          now: now,
        );
      }

      // 2. Gom tất cả ứng viên trong 90 ngày tới, sắp xếp tăng dần theo scheduledTime
      // rồi cắt lấy tối đa 50 thông báo gần nhất để lập lịch công bằng lên OS.
      final fairItems = selectFairScheduledNotifications(
        schedules: schedules,
        walletNamesMap: walletNamesMap,
        referenceDate: now,
        maxDaysAhead: 90,
        maxTotal: maxTotalNotifications,
      );

      for (final item in fairItems) {
        await _zonedScheduleWithFallback(
          item: item,
          preferredMode: scheduleMode,
        );
      }
      if (referenceDate == null) {
        _lastSyncedFingerprint = fingerprint;
      }
    } catch (e) {
      debugPrint('[NotificationService] Error syncing all reminders: $e');
    }
  }
}

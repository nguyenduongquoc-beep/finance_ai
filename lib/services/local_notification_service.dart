import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../models/recurring_transaction_model.dart';
import '../utils/formatters.dart';
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
  static const String channelName = 'Nhắc nhở hóa đơn & Giao dịch định kỳ';
  static const String channelDesc =
      'Thông báo nhắc nhở khi sắp đến hạn hoặc đến hạn các khoản thu chi định kỳ';

  FlutterLocalNotificationsPlugin? _plugin;
  bool _isInitialized = false;
  String? _pendingPayload;

  static const AndroidNotificationDetails _androidDetails =
      AndroidNotificationDetails(
    channelId,
    channelName,
    channelDescription: channelDesc,
    importance: Importance.max,
    priority: Priority.high,
    playSound: true,
    enableVibration: true,
    icon: '@mipmap/ic_launcher',
  );

  static const NotificationDetails _notificationDetails = NotificationDetails(
    android: _androidDetails,
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    ),
  );

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
        if (response.payload != null && response.payload!.isNotEmpty) {
          handleNotificationPayload(response.payload!);
        }
      },
    );

    // Đăng ký rõ ràng Android Notification Channel với mức ưu tiên cao để hiện trên thanh trạng thái
    try {
      final androidImpl = _plugin?.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        await androidImpl.createNotificationChannel(
          const AndroidNotificationChannel(
            channelId,
            channelName,
            description: channelDesc,
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
          ),
        );
      }
    } catch (e) {
      debugPrint('[NotificationService] Error creating Android channel: $e');
    }

    // Xử lý khi app mở từ trạng thái bị tắt hoàn toàn (terminated) thông qua thông báo
    try {
      final launchDetails = await _plugin?.getNotificationAppLaunchDetails();
      if (launchDetails != null &&
          launchDetails.didNotificationLaunchApp &&
          launchDetails.notificationResponse?.payload != null) {
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

  /// Tiêu thụ payload mở app (dùng khi UI chính đã sẵn sàng navigatorKey)
  void consumePendingPayloadIfAny() {
    if (_pendingPayload != null && _pendingPayload!.isNotEmpty) {
      final payload = _pendingPayload!;
      _pendingPayload = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        handleNotificationPayload(payload);
      });
    }
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

  /// Xử lý điều hướng khi bấm vào thông báo trên thanh trạng thái
  static void handleNotificationPayload(String rawPayload) {
    try {
      String payload = rawPayload;
      if (payload.startsWith(payloadPrefix)) {
        payload = payload.substring(payloadPrefix.length);
      }
      String scheduleId = payload;
      if (payload.startsWith('{')) {
        final map = jsonDecode(payload) as Map<String, dynamic>;
        scheduleId = map['scheduleId'] ?? payload;
      }

      if (scheduleId.isNotEmpty) {
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

    final String displayName =
        (schedule.note != null && schedule.note!.trim().isNotEmpty)
            ? schedule.note!.trim()
            : (schedule.type == 'income'
                ? 'Thu nhập định kỳ'
                : 'Hóa đơn định kỳ');
    final String isTypeLabel =
        schedule.type == 'income' ? 'Thu nhập' : 'Chi tiêu';
    final String walletText = walletName ?? 'Ví';
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
          items.add(ScheduledNotificationItem(
            notificationId: advanceId,
            scheduleId: schedule.scheduleId,
            scheduledTime: advanceDate,
            title: isManual
                ? 'Sắp đến hạn cần xác nhận: $displayName'
                : 'Sắp đến hạn: $displayName',
            body: isManual
                ? '$isTypeLabel: $formattedAmountđ • Ví: $walletText • Còn ${schedule.reminderDaysBefore} ngày (Cần xác nhận)'
                : '$isTypeLabel: $formattedAmountđ • Ví: $walletText • Còn ${schedule.reminderDaysBefore} ngày',
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
              ? 'Hôm nay cần xác nhận: $displayName'
              : 'Hôm nay đến hạn: $displayName',
          body: isManual
              ? '$isTypeLabel: $formattedAmountđ • Ví: $walletText • Chờ bạn xác nhận'
              : '$isTypeLabel: $formattedAmountđ • Ví: $walletText',
          payload: payload,
          isOnDueDate: true,
        ));
      }
    }

    return items;
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
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(
      schedule.nextDueDate.year,
      schedule.nextDueDate.month,
      schedule.nextDueDate.day,
    );

    final String displayName =
        (schedule.note != null && schedule.note!.trim().isNotEmpty)
            ? schedule.note!.trim()
            : (schedule.type == 'income'
                ? 'Thu nhập định kỳ'
                : 'Hóa đơn định kỳ');
    final String formattedAmount = AppFormatters.number(schedule.amount);
    final String occurrenceKey =
        RecurringTransactionService.getOccurrenceKey(schedule.nextDueDate);

    // Nếu người dùng tạo/sửa lịch sau 09:00 sáng mà ngày nhắc trước hoặc ngày đến hạn rơi vào đúng hôm nay,
    // hiển thị ngay thông báo trên thanh trạng thái Android để không bị bỏ lỡ khung 09:00 sáng đã qua.
    final todayNineAm = DateTime(now.year, now.month, now.day, 9, 0);
    if (now.isAfter(todayNineAm)) {
      if (dueDay == today) {
        final dueId = generateNotificationId(
          schedule.scheduleId,
          occurrenceKey,
          isOnDueDate: true,
        );
        await showImmediateNotification(
          notificationId: dueId,
          title: 'Giao dịch định kỳ đến hạn hôm nay',
          body: '$displayName — $formattedAmount VNĐ — Đến hạn hôm nay.',
          scheduleId: schedule.scheduleId,
        );
      } else if (schedule.reminderDaysBefore > 0) {
        final reminderDay = DateTime(
          dueDay.year,
          dueDay.month,
          dueDay.day - schedule.reminderDaysBefore,
        );
        if (!today.isBefore(reminderDay) && today.isBefore(dueDay)) {
          final daysLeft = dueDay.difference(today).inDays;
          final advId = generateNotificationId(
            schedule.scheduleId,
            occurrenceKey,
            isOnDueDate: false,
          );
          await showImmediateNotification(
            notificationId: advId,
            title: 'Giao dịch định kỳ sắp đến hạn',
            body:
                '$displayName — $formattedAmount VNĐ — Đến hạn sau $daysLeft ngày.',
            scheduleId: schedule.scheduleId,
          );
        }
      }
    }

    final items = calculateScheduledNotifications(
      schedule: schedule,
      walletName: walletName,
      referenceDate: referenceDate,
    );

    for (final item in items) {
      try {
        final tzScheduledTime =
            tz.TZDateTime.from(item.scheduledTime, tz.local);
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
      } catch (e) {
        debugPrint(
            '[NotificationService] Error scheduling notification ${item.notificationId}: $e');
      }
    }
  }

  /// Hủy thông báo của 1 kỳ cụ thể (khi kỳ đó đã được xác nhận, bỏ qua hoặc hoãn)
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

  /// Hủy các thông báo liên quan đến 1 scheduleId (chỉ hủy notification thuộc Bill Reminder)
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
        if (req.payload != null &&
            req.payload!.startsWith(payloadPrefix) &&
            req.payload!.contains(scheduleId)) {
          await _plugin!.cancel(req.id);
        }
      }
    } catch (e) {
      debugPrint('[NotificationService] Error canceling reminders: $e');
    }
  }

  /// Đồng bộ toàn bộ thông báo cho danh sách tất cả các lịch lặp của user (tối đa 50)
  Future<void> syncAllReminders({
    required List<RecurringTransactionSchedule> schedules,
    required Map<String, String> walletNamesMap,
    DateTime? referenceDate,
  }) async {
    if (_plugin == null || !_isInitialized) return;

    try {
      // Hủy các thông báo lặp cũ của Bill Reminder (dựa vào payloadPrefix)
      final pending = await _plugin!.pendingNotificationRequests();
      for (final req in pending) {
        if (req.payload != null && req.payload!.startsWith(payloadPrefix)) {
          await _plugin!.cancel(req.id);
        }
      }

      int scheduledCount = 0;
      const int maxTotalNotifications = 50; // Giới hạn tổng số thông báo

      for (final schedule in schedules) {
        if (scheduledCount >= maxTotalNotifications) break;
        if (!schedule.isActive) continue;

        final walletName = walletNamesMap[schedule.walletId];
        final items = calculateScheduledNotifications(
          schedule: schedule,
          walletName: walletName,
          referenceDate: referenceDate,
        );

        for (final item in items) {
          if (scheduledCount >= maxTotalNotifications) break;

          try {
            final tzScheduledTime =
                tz.TZDateTime.from(item.scheduledTime, tz.local);
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
            scheduledCount++;
          } catch (e) {
            debugPrint(
                '[NotificationService] Error scheduling notification ${item.notificationId}: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('[NotificationService] Error syncing all reminders: $e');
    }
  }
}

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../l10n/app_localizations.dart';
import '../../models/recurring_transaction_model.dart';
import '../../models/recurring_transaction_occurrence_model.dart';
import '../../models/wallet_model.dart';
import '../../models/category_model.dart';
import '../../services/firestore_service.dart';
import '../../services/local_notification_service.dart';
import '../../services/recurring_transaction_service.dart';
import '../../utils/category_localization_helper.dart';
import '../../utils/constants.dart';
import '../../utils/formatters.dart';
import '../../utils/wallet_localization_helper.dart';
import '../../widgets/app_snackbar.dart';
import 'wallet_management_screen.dart';

/// ============================================================
/// RECURRING TRANSACTION SCREEN
/// Giao dịch định kỳ & Lịch hóa đơn
/// ============================================================
class RecurringTransactionScreen extends StatefulWidget {
  final String? targetScheduleId;

  const RecurringTransactionScreen({super.key, this.targetScheduleId});

  static void Function(String scheduleId)? _activeFocusHandler;

  /// Nếu màn hình đang mở, điều hướng focus tới [scheduleId] thay vì push màn mới.
  static bool focusActiveScheduleIfOpen(String scheduleId) {
    final handler = _activeFocusHandler;
    if (handler == null) return false;
    handler(scheduleId);
    return true;
  }

  @override
  State<RecurringTransactionScreen> createState() =>
      _RecurringTransactionScreenState();
}

class _RecurringTransactionScreenState extends State<RecurringTransactionScreen>
    with WidgetsBindingObserver {
  final _firestoreService = FirestoreService();
  final _recService = RecurringTransactionService();
  final _notificationService = LocalNotificationService();
  final ScrollController _scrollController = ScrollController();

  late final String _uid;
  late final Stream<List<RecurringTransactionSchedule>> _schedulesStream;
  late final Stream<List<RecurringTransactionOccurrence>> _occurrencesStream;
  late final Stream<List<Wallet>> _walletsStream;
  late final Stream<List<Category>> _categoriesStream;

  List<RecurringTransactionSchedule> _cachedSchedules = [];
  List<RecurringTransactionOccurrence> _cachedOccurrences = [];
  List<Wallet> _cachedWallets = [];
  List<Category> _cachedCategories = [];

  bool _isProcessingDue = false;
  int _selectedUpcomingDays = 14; // 7, 14, 30 ngày
  bool _handledTargetSchedule = false;
  String? _activeTargetScheduleId;
  bool _notificationsEnabled = true;
  bool _exactAlarmsEnabled = true;

  bool _showNeedsActionSection = true;
  bool _showUpcomingSection = true;
  bool _showAllUpcoming = false;
  bool _showTemplatesSection = true;
  String _templateFilter = 'all'; // 'all' | 'active' | 'paused'

  final Map<String, GlobalKey> _dueCardKeys = {};
  final Map<String, GlobalKey> _templateCardKeys = {};

  /// Tracks scheduleIds currently processing an action (confirm/skip/defer)
  /// to prevent double-tap while an async operation is in flight.
  final Set<String> _actionInProgressIds = {};

  /// Optimistic active state overrides so toggling a switch updates UI & Hero instantly without jumping
  final Map<String, bool> _optimisticActiveStates = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    RecurringTransactionScreen._activeFocusHandler =
        _handleNotificationFocusInPlace;
    _activeTargetScheduleId = widget.targetScheduleId;

    _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _schedulesStream = _firestoreService.streamRecurringTransactions(_uid);
    _occurrencesStream = _firestoreService.streamRecurringOccurrences(_uid);
    _walletsStream = _firestoreService.streamWallets(_uid);
    _categoriesStream = _firestoreService.streamCategories(_uid);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _notificationService.requestPermission();
      await _refreshNotificationPermissions();
      await _processDueTransactions(showFeedback: false);
      if (_uid.isNotEmpty) {
        await _firestoreService.syncRecurringNotifications(_uid);
      }
    });
  }

  Future<void> _refreshNotificationPermissions() async {
    final notifEnabled = await _notificationService.areNotificationsEnabled();
    final exactEnabled = await _notificationService.canScheduleExactAlarms();
    if (!mounted) return;
    setState(() {
      _notificationsEnabled = notifEnabled;
      _exactAlarmsEnabled = exactEnabled;
    });
  }

  void _handleNotificationFocusInPlace(String scheduleId) {
    if (!mounted) return;
    setState(() {
      _activeTargetScheduleId = scheduleId;
      _handledTargetSchedule = false;
      _showNeedsActionSection = true;
      _showUpcomingSection = true;
      _showTemplatesSection = true;
      _templateFilter = 'all';
      _selectedUpcomingDays = 30;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _refreshNotificationPermissions();
      _processDueTransactions(showFeedback: false);
    }
  }

  @override
  void dispose() {
    if (RecurringTransactionScreen._activeFocusHandler ==
        _handleNotificationFocusInPlace) {
      RecurringTransactionScreen._activeFocusHandler = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    super.dispose();
  }

  String _scheduleDisplayName(
    RecurringTransactionSchedule schedule, [
    List<Category>? categories,
  ]) {
    if (schedule.note != null && schedule.note!.trim().isNotEmpty) {
      return CategoryLocalizationHelper.localizeNameWithContext(
        context,
        schedule.note!.trim(),
      );
    }
    final cats = categories ?? _cachedCategories;
    if (cats.isNotEmpty && schedule.categoryId.isNotEmpty) {
      final matched = cats
          .where((c) => c.categoryId == schedule.categoryId)
          .firstOrNull;
      if (matched != null && matched.name.trim().isNotEmpty) {
        return CategoryLocalizationHelper.localizeNameWithContext(
            context, matched.name.trim());
      }
    }
    return schedule.type == 'income'
        ? context.tr('rec_dlg_default_inc')
        : context.tr('rec_dlg_default_exp');
  }

  /// Kiểm tra lịch đang chờ xử lý tại mục Cần xử lý (không bao gồm manual đã quá 3 ngày grace).
  List<RecurringTransactionSchedule> _computeDueActionSchedules(
    List<RecurringTransactionSchedule> schedules,
    List<RecurringTransactionOccurrence> occurrences,
    DateTime referenceDate,
  ) {
    final todayOnly = RecurringTransactionService.dateOnly(referenceDate);
    return schedules.where((s) {
      if (!s.isActive) return false;
      final dueOnly = RecurringTransactionService.dateOnly(s.nextDueDate);
      if (dueOnly.isAfter(todayOnly)) return false;

      final key = RecurringTransactionService.getOccurrenceKey(s.nextDueDate);
      if (s.lastProcessedKey == key) return false;
      final isProcessed = occurrences.any(
        (o) => o.scheduleId == s.scheduleId && o.occurrenceKey == key,
      );
      if (isProcessed) return false;

      if (s.postingMode == RecurringTransactionSchedule.postingModeManual) {
        final graceEval = _recService.evaluateManualGracePeriod(
          schedule: s,
          referenceDate: referenceDate,
        );
        if (graceEval.wasAutoSkipped) return false;
      }
      return true;
    }).toList();
  }

  void _scrollToTargetKey(String scheduleId, {required bool preferDueCard}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final targetCtx = (preferDueCard
              ? _dueCardKeys[scheduleId]?.currentContext
              : null) ??
          _templateCardKeys[scheduleId]?.currentContext ??
          _dueCardKeys[scheduleId]?.currentContext;
      if (targetCtx != null) {
        Scrollable.ensureVisible(
          targetCtx,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          alignment: 0.12,
        );
      }
    });
  }

  void _checkTargetScheduleStatus(
    List<RecurringTransactionSchedule> schedules,
    List<RecurringTransactionOccurrence> occurrences,
    List<Category> categories,
  ) {
    final targetId = _activeTargetScheduleId;
    if (targetId == null || targetId.isEmpty || _handledTargetSchedule) return;
    _handledTargetSchedule = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target =
          schedules.where((s) => s.scheduleId == targetId).firstOrNull;
      if (target == null) {
        AppSnackbar.show(
          context,
          context.tr('rec_dlg_notif_missing'),
          isWarning: true,
        );
        return;
      }

      final now = DateTime.now();
      final dueList =
          _computeDueActionSchedules(schedules, occurrences, now);
      final isInDue = dueList.any((s) => s.scheduleId == targetId);

      setState(() {
        if (isInDue) {
          _showNeedsActionSection = true;
        } else {
          _showTemplatesSection = true;
          _templateFilter = 'all';
        }
      });

      _scrollToTargetKey(targetId, preferDueCard: isInDue);

      final name = _scheduleDisplayName(target, categories);
      if (!target.isActive) {
        AppSnackbar.show(
          context,
          context.tr('rec_dlg_paused', params: {'name': name}),
          isInfo: true,
        );
        return;
      }

      if (!isInDue) {
        AppSnackbar.show(
          context,
          context.tr(
            'rec_dlg_already_done',
            params: {
              'name': name,
              'date': DateFormat('dd/MM/yyyy').format(target.nextDueDate),
            },
          ),
          isInfo: true,
        );
      } else if (target.postingMode ==
          RecurringTransactionSchedule.postingModeManual) {
        AppSnackbar.show(
          context,
          context.tr('rec_dlg_awaiting_confirm', params: {'name': name}),
          isInfo: true,
        );
      }
    });
  }

  /// Xử lý các kỳ đến hạn bằng Firestore transaction atomic & idempotent (autoPost + auto-skip 3 ngày cho manualConfirmation)
  Future<void> _processDueTransactions({bool showFeedback = true}) async {
    if (_uid.isEmpty) return;

    setState(() => _isProcessingDue = true);

    try {
      final result =
          await _firestoreService.processDueRecurringTransactions(_uid);
      await _firestoreService.syncRecurringNotifications(_uid);
      final int processed = result['processedCount'] ?? 0;
      final int autoSkippedManual = result['autoSkippedManualCount'] ?? 0;
      final List<String> failedMessages =
          List<String>.from(result['failedSchedules'] ?? []);

      if (!mounted) return;
      setState(() => _isProcessingDue = false);

      if (processed > 0) {
        AppSnackbar.show(
          context,
          context.tr('rec_toast_auto_created',
              params: {'count': processed.toString()}),
        );
      } else if (autoSkippedManual > 0 && showFeedback) {
        AppSnackbar.show(
          context,
          context.tr('rec_toast_auto_skipped',
              params: {'count': autoSkippedManual.toString()}),
          isInfo: true,
        );
      } else if (showFeedback && failedMessages.isEmpty) {
        AppSnackbar.show(
          context,
          context.tr('rec_toast_all_updated'),
          isInfo: true,
        );
      }

      // Cảnh báo nếu có khoản không tạo được vì ví không đủ số dư
      if (failedMessages.isNotEmpty && showFeedback) {
        _showFailedDialog(failedMessages);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessingDue = false);
      debugPrint('[Recurring] Error checking due transactions: $e');
      if (showFeedback) {
        AppSnackbar.show(
          context,
          context.tr('rec_dlg_check_due_err'),
          isError: true,
        );
      }
    }
  }

  void _showFailedDialog(List<String> messages) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.expense),
            const SizedBox(width: 8),
            Expanded(child: Text(context.tr('rec_dlg_unposted_title'))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('rec_dlg_unposted_desc'),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            ...messages.map((msg) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.expense)),
                      Expanded(
                          child:
                              Text(msg, style: const TextStyle(fontSize: 12))),
                    ],
                  ),
                )),
            const SizedBox(height: 8),
            Text(
              context.tr('rec_dlg_unposted_hint'),
              style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.tr('rec_dlg_got_it')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(context.tr('recurring_title')),
        actions: [
          IconButton(
            icon: _isProcessingDue
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                : const Icon(Icons.sync_rounded),
            tooltip: context.tr('rec_sync_tooltip'),
            onPressed: _isProcessingDue
                ? null
                : () => _processDueTransactions(showFeedback: true),
          ),
        ],
      ),
      body: StreamBuilder<List<RecurringTransactionSchedule>>(
        stream: _schedulesStream,
        builder: (context, scheduleSnap) {
          if (scheduleSnap.hasData) {
            _cachedSchedules = scheduleSnap.data!;
            // Clear optimistic overrides once Firestore stream confirms the new state
            for (final s in _cachedSchedules) {
              if (_optimisticActiveStates[s.scheduleId] == s.isActive) {
                _optimisticActiveStates.remove(s.scheduleId);
              }
            }
          }

          if (scheduleSnap.connectionState == ConnectionState.waiting &&
              !scheduleSnap.hasData &&
              _cachedSchedules.isEmpty) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.primary));
          }

          final schedules = _cachedSchedules.map((s) {
            final override = _optimisticActiveStates[s.scheduleId];
            return override != null ? s.copyWith(isActive: override) : s;
          }).toList();

          return StreamBuilder<List<RecurringTransactionOccurrence>>(
            stream: _occurrencesStream,
            builder: (context, occurrenceSnap) {
              if (occurrenceSnap.hasData) {
                _cachedOccurrences = occurrenceSnap.data!;
              }
              final occurrences = _cachedOccurrences;

              return StreamBuilder<List<Wallet>>(
                stream: _walletsStream,
                builder: (context, walletSnap) {
                  if (walletSnap.hasData) {
                    _cachedWallets = walletSnap.data!;
                  }
                  final wallets = _cachedWallets;

                  return StreamBuilder<List<Category>>(
                    stream: _categoriesStream,
                    builder: (context, categorySnap) {
                      if (categorySnap.hasData) {
                        _cachedCategories = categorySnap.data!;
                      }
                      final categories = _cachedCategories;

                      if (scheduleSnap.hasData) {
                        _checkTargetScheduleStatus(
                            schedules, occurrences, categories);
                      }

                      final now = DateTime.now();
                      final dueSchedules = _computeDueActionSchedules(
                          schedules, occurrences, now);

                      return ListView(
                        key: const PageStorageKey('recurring_main_list_view'),
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                        children: [
                          _buildRecurringHero(
                            context: context,
                            schedules: schedules,
                            dueCount: dueSchedules.length,
                          ),
                          _buildPermissionBanner(),
                          _buildNeedsConfirmationSection(
                              dueSchedules, wallets, categories),
                          const SizedBox(height: 12),
                          _buildUpcomingSection(schedules, wallets, categories),
                          const SizedBox(height: 12),
                          _buildScheduleListSection(
                              schedules, wallets, categories),
                        ],
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showFormDialog(),
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: Text(
          context.tr('recurring_btn_add'),
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  Widget _buildPermissionBanner() {
    if (_notificationsEnabled && _exactAlarmsEnabled) {
      return const SizedBox.shrink();
    }
    final isNotifDisabled = !_notificationsEnabled;
    final message = isNotifDisabled
        ? context.tr('rec_perm_notif_off')
        : context.tr('rec_perm_exact_off');
    final btnLabel = isNotifDisabled
        ? context.tr('rec_perm_notif_btn')
        : context.tr('rec_perm_exact_btn');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.notifications_paused_rounded,
            size: 18,
            color: Colors.amber.shade900,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12,
                color: Colors.amber.shade900,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () async {
              if (isNotifDisabled) {
                await _notificationService.requestPermission();
              } else {
                await _notificationService.requestExactAlarmsPermission();
              }
              await _refreshNotificationPermissions();
              if (_uid.isNotEmpty) {
                await _firestoreService.resyncLocalNotifications(
                  _uid,
                  force: true,
                );
              }
            },
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            child: Text(
              btnLabel,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecurringHero({
    required BuildContext context,
    required List<RecurringTransactionSchedule> schedules,
    required int dueCount,
  }) {
    return RecurringHeroCard(
      schedules: schedules,
      dueCount: dueCount,
      onTapDueBadge: () => setState(() => _showNeedsActionSection = true),
    );
  }

  // ============================================================
  // 0. NEEDS CONFIRMATION & OVERDUE SECTION (KHU VỰC ƯU TIÊN)
  // ============================================================
  Widget _buildNeedsConfirmationSection(
    List<RecurringTransactionSchedule> dueSchedules,
    List<Wallet> wallets,
    List<Category> categories,
  ) {
    final now = DateTime.now();

    if (dueSchedules.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: context.appCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: context.appBorder.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline_rounded,
                size: 18, color: AppColors.income),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.tr('rec_sec_action_empty'),
                style: TextStyle(
                  fontSize: 13,
                  color: context.appTextSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.3), width: 1.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(
                () => _showNeedsActionSection = !_showNeedsActionSection),
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.assignment_late_rounded,
                      color: AppColors.primary, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('rec_sec_action_title'),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: context.appTextPrimary,
                        ),
                      ),
                      Text(
                        context.tr('rec_sec_action_sub'),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: context.appTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.expense.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    context.tr(
                      'rec_count_items',
                      params: {'count': dueSchedules.length.toString()},
                    ),
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.expense,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _showNeedsActionSection
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: context.appTextSecondary,
                  size: 20,
                ),
              ],
            ),
          ),
          if (_showNeedsActionSection) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            ...dueSchedules.map((schedule) {
              final isIncome = schedule.type == 'income';
              final color = isIncome ? AppColors.income : AppColors.expense;
              final wallet = wallets.firstWhere(
                (w) => w.walletId == schedule.walletId,
                orElse: () => Wallet(
                  walletId: '',
                  userId: '',
                  walletName: context.tr('tx_wallet_label'),
                  balance: 0,
                  type: 'cash',
                  createdAt: DateTime.now(),
                ),
              );

              final isManual = schedule.postingMode ==
                  RecurringTransactionSchedule.postingModeManual;
              final graceEval = _recService.evaluateManualGracePeriod(
                schedule: schedule,
                referenceDate: now,
              );
              final daysOverdue =
                  RecurringTransactionService.calendarDaysBetween(
                schedule.nextDueDate,
                now,
              );
              final displayName = _scheduleDisplayName(schedule, categories);
              final isTargeted = _activeTargetScheduleId != null &&
                  _activeTargetScheduleId == schedule.scheduleId;
              final cardKey = _dueCardKeys.putIfAbsent(
                schedule.scheduleId,
                () => GlobalKey(),
              );
              final isBusy =
                  _actionInProgressIds.contains(schedule.scheduleId);

              String statusLabel;
              Color statusColor;
              if (isManual) {
                if (daysOverdue <= 0) {
                  statusLabel = context.tr('rec_grace_due_today');
                  statusColor = Colors.orange.shade800;
                } else if (graceEval.remainingGraceDays <= 1) {
                  statusLabel = context.tr(
                    'rec_grace_last_day',
                    params: {'overdue': daysOverdue.toString()},
                  );
                  statusColor = AppColors.expense;
                } else {
                  statusLabel = context.tr(
                    'rec_grace_overdue_days',
                    params: {
                      'overdue': daysOverdue.toString(),
                      'left': graceEval.remainingGraceDays.toString(),
                    },
                  );
                  statusColor = Colors.orange.shade800;
                }
              } else {
                statusLabel = context.tr('rec_badge_auto_stuck');
                statusColor = AppColors.expense;
              }

              final textScale = MediaQuery.textScalerOf(context).scale(1.0);
              final useWrapButtons = textScale > 1.25;

              final confirmBtn = FilledButton.icon(
                key: ValueKey('btn_confirm_${schedule.scheduleId}'),
                onPressed: isBusy
                    ? null
                    : () => _showConfirmOccurrenceDialog(
                          schedule: schedule,
                          occurrenceDate: schedule.nextDueDate,
                          wallet: wallet,
                          allWallets: wallets,
                        ),
                style: FilledButton.styleFrom(
                  backgroundColor: color,
                  minimumSize: const Size(0, 34),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  visualDensity: VisualDensity.compact,
                ),
                icon: isBusy
                    ? const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_rounded, size: 15),
                label: Text(
                  context.tr('rec_btn_confirm_short'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              );

              final deferBtn = OutlinedButton.icon(
                key: ValueKey('btn_defer_${schedule.scheduleId}'),
                onPressed: isBusy
                    ? null
                    : () => _handleDeferOccurrence(
                        schedule, schedule.nextDueDate),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 34),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.edit_calendar_rounded, size: 14),
                label: Text(
                  context.tr('rec_btn_defer_short'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              );

              final skipBtn = OutlinedButton.icon(
                key: ValueKey('btn_skip_${schedule.scheduleId}'),
                onPressed: isBusy
                    ? null
                    : () => _showSkipOccurrenceDialog(
                        schedule, schedule.nextDueDate),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 34),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.skip_next_rounded, size: 15),
                label: Text(
                  context.tr('rec_btn_skip_short'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              );

              return Container(
                key: cardKey,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: isTargeted
                      ? AppColors.primary.withValues(alpha: 0.08)
                      : color.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isTargeted
                        ? AppColors.primary
                        : color.withValues(alpha: 0.22),
                    width: isTargeted ? 1.8 : 1.0,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isTargeted)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            const Icon(Icons.notifications_active_rounded,
                                size: 12, color: AppColors.primary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                context.tr('rec_badge_from_notif'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isIncome
                                ? Icons.arrow_upward_rounded
                                : Icons.arrow_downward_rounded,
                            color: color,
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${context.tr('rec_wallet_prefix', params: {'name': WalletLocalizationHelper.localizeWalletWithContext(context, wallet)})} • ${context.tr('rec_cycle_date', params: {'date': DateFormat('dd/MM/yyyy').format(schedule.nextDueDate)})}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: context.appTextSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 112),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              '${isIncome ? '+' : '-'}${AppFormatters.compactCurrency(schedule.amount)}',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14.5,
                                color: color,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 9),
                    if (useWrapButtons)
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [confirmBtn, deferBtn, skipBtn],
                      )
                    else
                      Row(
                        children: [
                          Expanded(flex: 5, child: confirmBtn),
                          const SizedBox(width: 6),
                          Expanded(flex: 4, child: deferBtn),
                          const SizedBox(width: 6),
                          Expanded(flex: 4, child: skipBtn),
                        ],
                      ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildBalanceInfoRow(String label, String value,
      {bool isShortfall = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isShortfall
                  ? AppColors.expense
                  : context.appTextSecondary,
              fontWeight: isShortfall ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isShortfall ? FontWeight.w700 : FontWeight.w600,
              color: isShortfall ? AppColors.expense : context.appTextPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }

  void _showInsufficientBalanceDialog({
    required RecurringTransactionSchedule schedule,
    required DateTime occurrenceDate,
    required Wallet wallet,
    required List<Wallet> allWallets,
  }) {
    final displayName = _scheduleDisplayName(schedule);
    final shortfall = schedule.amount - wallet.balance;
    final otherAvailableWallets = allWallets
        .where((w) =>
            w.walletId != wallet.walletId &&
            w.isActive &&
            w.balance >= schedule.amount)
        .toList();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.warning_amber_rounded,
                  color: AppColors.warning, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                ctx.tr('rec_dlg_insuff_title'),
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ctx.tr('rec_dlg_insuff_sub', params: {'name': displayName}),
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.appBackground,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.appBorder),
                ),
                child: Column(
                  children: [
                    _buildBalanceInfoRow(
                        ctx.tr('rec_dlg_pay_wallet'),
                        WalletLocalizationHelper.localizeWalletWithContext(
                            ctx, wallet)),
                    const Divider(height: 14),
                    _buildBalanceInfoRow(ctx.tr('rec_dlg_avail_bal'),
                        AppFormatters.currency(wallet.balance)),
                    const SizedBox(height: 4),
                    _buildBalanceInfoRow(ctx.tr('rec_dlg_due_amt'),
                        AppFormatters.currency(schedule.amount)),
                    const Divider(height: 14),
                    _buildBalanceInfoRow(
                      ctx.tr('rec_dlg_shortfall'),
                      AppFormatters.currency(shortfall),
                      isShortfall: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                otherAvailableWallets.isNotEmpty
                    ? ctx.tr('rec_dlg_insuff_hint_alt')
                    : ctx.tr('rec_dlg_insuff_hint_topup'),
                style:
                    TextStyle(fontSize: 12, color: context.appTextSecondary),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.tr('rec_dlg_later_btn')),
          ),
          if (otherAvailableWallets.isNotEmpty)
            OutlinedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _showSelectAlternativeWalletDialog(
                  schedule: schedule,
                  occurrenceDate: occurrenceDate,
                  availableWallets: otherAvailableWallets,
                );
              },
              child: Text(ctx.tr('rec_dlg_switch_wallet_btn')),
            ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const WalletManagementScreen()),
              );
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: Text(ctx.tr('rec_dlg_manage_wallets_btn')),
          ),
        ],
      ),
    );
  }

  void _showSelectAlternativeWalletDialog({
    required RecurringTransactionSchedule schedule,
    required DateTime occurrenceDate,
    required List<Wallet> availableWallets,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Row(
          children: [
            const Icon(Icons.swap_horiz_rounded,
                color: AppColors.primary, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                ctx.tr('rec_dlg_alt_title'),
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ctx.tr(
                  'rec_dlg_alt_sub',
                  params: {'amount': AppFormatters.currency(schedule.amount)},
                ),
                style: TextStyle(fontSize: 12, color: context.appTextSecondary),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: availableWallets.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final w = availableWallets[i];
                    return InkWell(
                      onTap: () async {
                        Navigator.of(ctx).pop();
                        setState(() =>
                            _actionInProgressIds.add(schedule.scheduleId));
                        try {
                          // Thanh toán nguyên tử RIÊNG kỳ hiện tại bằng ví thay thế
                          // trong đúng 1 Firestore Transaction mà không đổi ví mặc định của lịch.
                          await _firestoreService.confirmRecurringOccurrence(
                            userId: _uid,
                            schedule: schedule,
                            occurrenceDate: occurrenceDate,
                            overrideWalletId: w.walletId,
                          );
                          if (mounted) {
                            AppSnackbar.show(
                              this.context,
                              this.context.tr(
                                'rec_dlg_alt_ok',
                                params: {
                                  'wallet': WalletLocalizationHelper
                                      .localizeWalletWithContext(
                                          this.context, w),
                                },
                              ),
                            );
                          }
                        } on InsufficientBalanceException catch (e) {
                          if (mounted) {
                            AppSnackbar.show(
                              this.context,
                              e.message,
                              isError: true,
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            AppSnackbar.show(
                              this.context,
                              this.context.tr(
                                'rec_dlg_alt_err',
                                params: {'err': e.toString()},
                              ),
                              isError: true,
                            );
                          }
                        } finally {
                          if (mounted) {
                            setState(() => _actionInProgressIds
                                .remove(schedule.scheduleId));
                          }
                        }
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: context.appBackground,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: context.appBorder),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(
                                WalletLocalizationHelper
                                    .localizeWalletWithContext(context, w),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 135),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  AppFormatters.currency(w.balance),
                                  maxLines: 1,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.income,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.tr('common_close')),
          ),
        ],
      ),
    );
  }

  void _showConfirmOccurrenceDialog({
    required RecurringTransactionSchedule schedule,
    required DateTime occurrenceDate,
    required Wallet wallet,
    required List<Wallet> allWallets,
  }) {
    final isIncome = schedule.type == 'income';
    final displayName = _scheduleDisplayName(schedule);

    // Nếu là chi tiêu mà ví không đủ số dư -> Hiển thị hộp thoại thiếu số dư ngay lập tức
    if (!isIncome && wallet.balance < schedule.amount) {
      _showInsufficientBalanceDialog(
        schedule: schedule,
        occurrenceDate: occurrenceDate,
        wallet: wallet,
        allWallets: allWallets,
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) {
        bool isSubmitting = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              title: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: (isIncome ? AppColors.income : AppColors.expense)
                          .withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isIncome
                          ? Icons.arrow_upward_rounded
                          : Icons.receipt_long_rounded,
                      color: isIncome ? AppColors.income : AppColors.expense,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isIncome
                          ? ctx.tr('rec_dlg_confirm_inc_title')
                          : ctx.tr('rec_dlg_confirm_exp_title'),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ctx.tr('rec_dlg_confirm_desc'),
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.appBackground,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: context.appBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  displayName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${isIncome ? '+' : '-'}${AppFormatters.currency(schedule.amount)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: isIncome
                                  ? AppColors.income
                                  : AppColors.expense,
                              fontSize: 18,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            ),
                          ),
                          const Divider(height: 16),
                          _buildBalanceInfoRow(
                              ctx.tr('rec_dlg_post_wallet'),
                              WalletLocalizationHelper
                                  .localizeWalletWithContext(ctx, wallet)),
                          const SizedBox(height: 4),
                          _buildBalanceInfoRow(ctx.tr('rec_dlg_avail_bal'),
                              AppFormatters.currency(wallet.balance)),
                          const SizedBox(height: 4),
                          _buildBalanceInfoRow(
                            ctx.tr('rec_dlg_after_bal'),
                            AppFormatters.currency(
                              isIncome
                                  ? wallet.balance + schedule.amount
                                  : wallet.balance - schedule.amount,
                            ),
                          ),
                          const SizedBox(height: 4),
                          _buildBalanceInfoRow(
                            ctx.tr('rec_dlg_post_date'),
                            DateFormat('dd/MM/yyyy').format(occurrenceDate),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      isSubmitting ? null : () => Navigator.of(ctx).pop(),
                  child: Text(ctx.tr('common_cancel')),
                ),
                FilledButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          setDialogState(() => isSubmitting = true);
                          setState(() => _actionInProgressIds
                              .add(schedule.scheduleId));
                          try {
                            await _firestoreService.confirmRecurringOccurrence(
                              userId: _uid,
                              schedule: schedule,
                              occurrenceDate: occurrenceDate,
                            );
                            if (ctx.mounted) {
                              Navigator.of(ctx).pop();
                            }
                            if (mounted) {
                              AppSnackbar.show(
                                this.context,
                                this.context.tr(
                                  'rec_dlg_confirm_ok',
                                  params: {'name': displayName},
                                ),
                              );
                            }
                          } on InsufficientBalanceException catch (_) {
                            if (ctx.mounted) {
                              Navigator.of(ctx).pop();
                            }
                            if (mounted) {
                              _showInsufficientBalanceDialog(
                                schedule: schedule,
                                occurrenceDate: occurrenceDate,
                                wallet: wallet,
                                allWallets: allWallets,
                              );
                            }
                          } catch (e) {
                            if (ctx.mounted) {
                              Navigator.of(ctx).pop();
                            }
                            if (mounted) {
                              AppSnackbar.show(
                                this.context,
                                this.context.tr(
                                  'rec_dlg_confirm_err',
                                  params: {'err': e.toString()},
                                ),
                                isError: true,
                              );
                            }
                          } finally {
                            if (mounted) {
                              setState(() => _actionInProgressIds
                                  .remove(schedule.scheduleId));
                            }
                          }
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        isIncome ? AppColors.income : AppColors.expense,
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(ctx.tr('common_confirm')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showSkipOccurrenceDialog(
    RecurringTransactionSchedule schedule,
    DateTime occurrenceDate,
  ) {
    final displayName = _scheduleDisplayName(schedule);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: context.appBorder.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.skip_next_rounded, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                ctx.tr('rec_dlg_skip_title'),
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ctx.tr(
                'rec_dlg_item_summary',
                params: {
                  'name': displayName,
                  'amount': AppFormatters.currency(schedule.amount),
                },
              ),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Text(
              ctx.tr(
                'rec_dlg_skip_desc',
                params: {
                  'date': DateFormat('dd/MM/yyyy').format(occurrenceDate),
                },
              ),
              style: TextStyle(
                  fontSize: 12, color: context.appTextSecondary, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.tr('common_cancel')),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              setState(() => _actionInProgressIds.add(schedule.scheduleId));
              try {
                await _firestoreService.skipRecurringOccurrence(
                  userId: _uid,
                  schedule: schedule,
                  occurrenceDate: occurrenceDate,
                );
                if (mounted) {
                  AppSnackbar.show(
                    context,
                    context.tr(
                      'rec_dlg_skip_ok',
                      params: {'name': displayName},
                    ),
                    isInfo: true,
                  );
                }
              } catch (e) {
                if (mounted) {
                  AppSnackbar.show(
                    context,
                    context.tr('rec_dlg_skip_err', params: {'err': e.toString()}),
                    isError: true,
                  );
                }
              } finally {
                if (mounted) {
                  setState(
                      () => _actionInProgressIds.remove(schedule.scheduleId));
                }
              }
            },
            style: FilledButton.styleFrom(
                backgroundColor: context.appTextSecondary),
            child: Text(ctx.tr('rec_dlg_skip_btn')),
          ),
        ],
      ),
    );
  }

  Future<void> _handleDeferOccurrence(
    RecurringTransactionSchedule schedule,
    DateTime occurrenceDate,
  ) async {
    final now = DateTime.now();
    final minDeferDate = RecurringTransactionService.minValidDeferDate(
      occurrenceDate: occurrenceDate,
      referenceDate: now,
    );
    final maxDeferDate =
        DateTime(minDeferDate.year > 2035 ? minDeferDate.year + 1 : 2035);

    final picked = await showDatePicker(
      context: context,
      initialDate: minDeferDate,
      firstDate: minDeferDate,
      lastDate: maxDeferDate,
      helpText: context.tr('rec_dlg_defer_picker_help'),
    );

    if (picked == null || !mounted) return;

    final displayName = _scheduleDisplayName(schedule);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.edit_calendar_rounded,
                  color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                ctx.tr('rec_dlg_defer_title'),
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ctx.tr(
                'rec_dlg_item_summary',
                params: {
                  'name': displayName,
                  'amount': AppFormatters.currency(schedule.amount),
                },
              ),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Text(
              ctx.tr(
                'rec_dlg_defer_desc',
                params: {
                  'oldDate': DateFormat('dd/MM/yyyy').format(occurrenceDate),
                  'newDate': DateFormat('dd/MM/yyyy').format(picked),
                },
              ),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      ctx.tr('rec_dlg_defer_note'),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.tr('common_cancel')),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              setState(() => _actionInProgressIds.add(schedule.scheduleId));
              try {
                await _firestoreService.deferRecurringOccurrence(
                  userId: _uid,
                  schedule: schedule,
                  occurrenceDate: occurrenceDate,
                  newDueDate: picked,
                );
                if (mounted) {
                  AppSnackbar.show(
                    context,
                    context.tr(
                      'rec_dlg_defer_ok',
                      params: {
                        'name': displayName,
                        'date': DateFormat('dd/MM/yyyy').format(picked),
                      },
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  AppSnackbar.show(
                    context,
                    context.tr('rec_dlg_defer_err', params: {'err': e.toString()}),
                    isError: true,
                  );
                }
              } finally {
                if (mounted) {
                  setState(
                      () => _actionInProgressIds.remove(schedule.scheduleId));
                }
              }
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: Text(ctx.tr('rec_dlg_defer_btn')),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 1. UPCOMING BILLS SECTION (Compact & Collapsible)
  // ============================================================
  Widget _buildUpcomingSection(
    List<RecurringTransactionSchedule> schedules,
    List<Wallet> wallets,
    List<Category> categories,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final upcomingList = _recService.upcomingOccurrences(
      schedules: schedules,
      referenceDate: now,
      daysAhead: _selectedUpcomingDays,
    );
    const maxPreviewItems = 5;
    final visibleUpcoming = _showAllUpcoming
        ? upcomingList
        : upcomingList.take(maxPreviewItems).toList();
    final hiddenCount = upcomingList.length - visibleUpcoming.length;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: context.appBorder.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () =>
                setState(() => _showUpcomingSection = !_showUpcomingSection),
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.calendar_month_rounded,
                      color: AppColors.primary, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('rec_sec_upcoming_title'),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: context.appTextPrimary,
                        ),
                      ),
                      Text(
                        context.tr(
                          'rec_sec_upcoming_sub',
                          params: {'days': '$_selectedUpcomingDays'},
                        ),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: context.appTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (upcomingList.isNotEmpty) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      context.tr(
                        'rec_count_items',
                        params: {'count': '${upcomingList.length}'},
                      ),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                Icon(
                  _showUpcomingSection
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: context.appTextSecondary,
                ),
              ],
            ),
          ),
          if (_showUpcomingSection) ...[
            const SizedBox(height: 12),
            // Clean Segmented Tabs (7 / 14 / 30 days)
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: context.appBackground,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: context.appBorder.withValues(alpha: 0.08),
                ),
              ),
              child: Row(
                children: [7, 14, 30].map((days) {
                  final isSelected = _selectedUpcomingDays == days;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (!isSelected) {
                          setState(() {
                            _selectedUpcomingDays = days;
                            _showAllUpcoming = false;
                          });
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primary
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          context.tr(
                            'rec_days_unit',
                            params: {'days': '$days'},
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.w500,
                            color: isSelected
                                ? Colors.white
                                : context.appTextSecondary,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 10),
            if (upcomingList.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Center(
                  child: Text(
                    context.tr(
                      'rec_upcoming_empty',
                      params: {'days': '$_selectedUpcomingDays'},
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12.5, color: context.appTextSecondary),
                  ),
                ),
              )
            else ...[
              Container(
                decoration: BoxDecoration(
                  color: context.appBackground.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: context.appBorder.withValues(alpha: 0.08),
                  ),
                ),
                child: Column(
                  children: List.generate(visibleUpcoming.length, (index) {
                    final item = visibleUpcoming[index];
                    final isIncome = item.schedule.type == 'income';
                    final color = isIncome ? AppColors.income : AppColors.expense;
                    final isManual = item.schedule.postingMode ==
                        RecurringTransactionSchedule.postingModeManual;
                    final wallet = wallets.firstWhere(
                      (w) => w.walletId == item.schedule.walletId,
                      orElse: () => Wallet(
                        walletId: '',
                        userId: '',
                        walletName: context.tr('common_not_set'),
                        balance: 0,
                        type: 'cash',
                        createdAt: DateTime.now(),
                      ),
                    );

                    final dueDay = DateTime(
                      item.dueDate.year,
                      item.dueDate.month,
                      item.dueDate.day,
                    );
                    final daysUntil = dueDay.difference(today).inDays;
                    final String dueBadgeText;
                    if (daysUntil <= 0) {
                      dueBadgeText = context.tr('rec_today');
                    } else if (daysUntil == 1) {
                      dueBadgeText = context.tr('rec_tomorrow');
                    } else {
                      dueBadgeText = context.tr(
                        'rec_days_left',
                        params: {'days': '$daysUntil'},
                      );
                    }

                    final isTargeted = _activeTargetScheduleId != null &&
                        _activeTargetScheduleId == item.schedule.scheduleId;

                    return Column(
                      children: [
                        if (index > 0) const Divider(height: 1),
                        InkWell(
                          onTap: () {
                            setState(() {
                              _showTemplatesSection = true;
                              _templateFilter = 'all';
                              _activeTargetScheduleId =
                                  item.schedule.scheduleId;
                            });
                            _scrollToTargetKey(
                              item.schedule.scheduleId,
                              preferDueCard: false,
                            );
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            color: isTargeted
                                ? AppColors.primary.withValues(alpha: 0.06)
                                : Colors.transparent,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 9),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 4),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        DateFormat('dd').format(dueDay),
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: color,
                                          height: 1.05,
                                        ),
                                      ),
                                      Text(
                                        DateFormat('MM').format(dueDay),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: context.appTextSecondary,
                                          height: 1.1,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _scheduleDisplayName(
                                            item.schedule, categories),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                          color: context.appTextPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '$dueBadgeText • ${WalletLocalizationHelper.localizeWalletWithContext(context, wallet)} • ${isManual ? context.tr('rec_badge_manual') : context.tr('rec_badge_auto')}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: daysUntil <= 1
                                              ? AppColors.expense
                                              : context.appTextSecondary,
                                          fontWeight: daysUntil <= 1
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 110),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                      '${isIncome ? '+' : '-'}${AppFormatters.compactCurrency(item.schedule.amount, unit: '₫')}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13.5,
                                        color: color,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ),
              if (upcomingList.length > maxPreviewItems) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.center,
                  child: TextButton.icon(
                    onPressed: () =>
                        setState(() => _showAllUpcoming = !_showAllUpcoming),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                    ),
                    icon: Icon(
                      _showAllUpcoming
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 18,
                    ),
                    label: Text(
                      _showAllUpcoming
                          ? context.tr('rec_collapse')
                          : context.tr(
                              'rec_show_more_upcoming',
                              params: {'count': '$hiddenCount'},
                            ),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ],
      ),
    );
  }

  // ============================================================
  // 2. SCHEDULE LIST SECTION (Compact, Filterable & Collapsible)
  // ============================================================
  Future<void> _toggleScheduleActive(
    RecurringTransactionSchedule schedule,
    String displayName,
    bool val,
  ) async {
    final toggleKey = 'toggle_${schedule.scheduleId}';
    setState(() {
      _actionInProgressIds.add(toggleKey);
      _optimisticActiveStates[schedule.scheduleId] = val;
    });
    try {
      await _firestoreService.setRecurringTransactionActive(
          schedule.scheduleId, val);
      if (val && _uid.isNotEmpty) {
        await _firestoreService.syncRecurringNotifications(_uid);
      }
      if (mounted) {
        AppSnackbar.show(
          context,
          val
              ? '${context.tr('common_activated')}: "$displayName"'
              : '${context.tr('rec_paused_status')}: "$displayName"',
          isInfo: !val,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _optimisticActiveStates.remove(schedule.scheduleId);
        });
        AppSnackbar.show(
          context,
          '${context.tr('common_error')}: $e',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _actionInProgressIds.remove(toggleKey));
      }
    }
  }

  Widget _buildTemplatePill({
    required IconData icon,
    required String label,
    required Color tint,
    Color? textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor ?? tint),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: textColor ?? tint,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleListSection(
    List<RecurringTransactionSchedule> schedules,
    List<Wallet> wallets,
    List<Category> categories,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final activeCount = schedules.where((s) => s.isActive).length;
    final pausedCount = schedules.length - activeCount;

    final filteredSchedules = schedules.where((s) {
      if (_templateFilter == 'active') return s.isActive;
      if (_templateFilter == 'paused') return !s.isActive;
      return true;
    }).toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: context.appBorder.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () =>
                setState(() => _showTemplatesSection = !_showTemplatesSection),
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.event_repeat_rounded,
                      color: AppColors.primary, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('rec_sec_templates_title'),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: context.appTextPrimary,
                        ),
                      ),
                      Text(
                        context.tr('rec_sec_templates_sub'),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: context.appTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: context.appBorder.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    context.tr(
                      'rec_count_schedules',
                      params: {'count': '${schedules.length}'},
                    ),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: context.appTextSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _showTemplatesSection
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: context.appTextSecondary,
                ),
              ],
            ),
          ),
          if (_showTemplatesSection) ...[
            const SizedBox(height: 12),
            if (schedules.isNotEmpty) ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ('all', context.tr('rec_filter_all', params: {'count': '${schedules.length}'})),
                    ('active', context.tr('rec_filter_active', params: {'count': '$activeCount'})),
                    ('paused', context.tr('rec_filter_paused', params: {'count': '$pausedCount'})),
                  ].map((entry) {
                    final key = entry.$1;
                    final label = entry.$2;
                    final selected = _templateFilter == key;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(
                          label,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: selected
                                ? Colors.white
                                : context.appTextSecondary,
                          ),
                        ),
                        selected: selected,
                        showCheckmark: false,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        selectedColor: AppColors.primary,
                        backgroundColor: context.appBackground,
                        side: BorderSide(
                          color: selected
                              ? AppColors.primary
                              : context.appBorder.withValues(alpha: 0.14),
                        ),
                        onSelected: (_) =>
                            setState(() => _templateFilter = key),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (schedules.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 22),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.event_repeat_rounded,
                          size: 38,
                          color:
                              context.appTextSecondary.withValues(alpha: 0.4)),
                      const SizedBox(height: 8),
                      Text(
                        context.tr('rec_templates_empty'),
                        style: TextStyle(
                          fontSize: 13,
                          color: context.appTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (filteredSchedules.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Center(
                  child: Text(
                    context.tr('rec_filter_empty'),
                    style: TextStyle(
                      fontSize: 12.5,
                      color: context.appTextSecondary,
                    ),
                  ),
                ),
              )
            else
              ...filteredSchedules.map((schedule) {
                final isIncome = schedule.type == 'income';
                final color = isIncome ? AppColors.income : AppColors.expense;
                final wallet = wallets.firstWhere(
                  (w) => w.walletId == schedule.walletId,
                  orElse: () => Wallet(
                    walletId: '',
                    userId: '',
                    walletName: context.tr('common_not_set'),
                    balance: 0,
                    type: 'cash',
                    createdAt: DateTime.now(),
                  ),
                );

                final isManual = schedule.postingMode ==
                    RecurringTransactionSchedule.postingModeManual;
                final nextDueDay = DateTime(
                  schedule.nextDueDate.year,
                  schedule.nextDueDate.month,
                  schedule.nextDueDate.day,
                );
                final isDueNow =
                    schedule.isActive && !nextDueDay.isAfter(today);
                final isTargeted = _activeTargetScheduleId != null &&
                    _activeTargetScheduleId == schedule.scheduleId;
                final displayName =
                    _scheduleDisplayName(schedule, categories);
                final toggleKey = 'toggle_${schedule.scheduleId}';
                final isToggling = _actionInProgressIds.contains(toggleKey);
                final templateKey = _templateCardKeys.putIfAbsent(
                    schedule.scheduleId, GlobalKey.new);

                return KeyedSubtree(
                  key: templateKey,
                  child: Container(
                    key: ValueKey('schedule_card_${schedule.scheduleId}'),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: isTargeted
                          ? AppColors.primary.withValues(alpha: 0.05)
                          : context.appBackground.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isTargeted
                            ? AppColors.primary
                            : (isDueNow
                                ? Colors.orange.withValues(alpha: 0.32)
                                : context.appBorder.withValues(alpha: 0.12)),
                        width: isTargeted ? 1.8 : 1.0,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isTargeted)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(11),
                                topRight: Radius.circular(11),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.notifications_active_rounded,
                                    size: 13, color: AppColors.primary),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    context.tr('rec_badge_from_notif'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        // Top Row: Icon + Name + Amount + Overflow Menu
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 6, 6),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundColor: color.withValues(alpha: 0.12),
                                child: Icon(
                                  isIncome
                                      ? Icons.account_balance_wallet_outlined
                                      : Icons.receipt_long_outlined,
                                  color: color,
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    color: schedule.isActive
                                        ? context.appTextPrimary
                                        : context.appTextSecondary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 115),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    '${isIncome ? '+' : '-'}${AppFormatters.compactCurrency(schedule.amount, unit: '₫')}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14.5,
                                      color: schedule.isActive
                                          ? color
                                          : Colors.grey,
                                    ),
                                  ),
                                ),
                              ),
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert, size: 19),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onSelected: (val) {
                                  if (val == 'edit') {
                                    _showFormDialog(schedule: schedule);
                                  } else if (val == 'toggle') {
                                    if (!isToggling) {
                                      _toggleScheduleActive(schedule,
                                          displayName, !schedule.isActive);
                                    }
                                  } else if (val == 'delete') {
                                    _confirmDelete(schedule);
                                  }
                                },
                                itemBuilder: (context) => [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        const Icon(Icons.edit_outlined,
                                            size: 18),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            context.tr('rec_menu_edit'),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'toggle',
                                    child: Row(
                                      children: [
                                        Icon(
                                          schedule.isActive
                                              ? Icons.pause_circle_outline
                                              : Icons.play_circle_outline,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            schedule.isActive
                                                ? context.tr('rec_menu_pause')
                                                : context.tr('rec_menu_resume'),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        const Icon(Icons.delete_outline,
                                            size: 18,
                                            color: AppColors.expense),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            context.tr('rec_menu_delete'),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                color: AppColors.expense),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // Compact Metadata Wrap Pills (Overflow-proof)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _buildTemplatePill(
                                icon: Icons.repeat_rounded,
                                label: schedule.frequency == 'weekly'
                                    ? context.tr('recurring_freq_weekly')
                                    : context.tr('recurring_freq_monthly'),
                                tint: context.appTextSecondary,
                              ),
                              _buildTemplatePill(
                                icon: isManual
                                    ? Icons.touch_app_outlined
                                    : Icons.bolt_rounded,
                                label: isManual
                                    ? context.tr('rec_badge_manual')
                                    : context.tr('rec_badge_auto'),
                                tint: isManual
                                    ? Colors.orange
                                    : AppColors.primary,
                                textColor: isManual
                                    ? Colors.orange.shade800
                                    : AppColors.primary,
                              ),
                              _buildTemplatePill(
                                icon: Icons.account_balance_wallet_outlined,
                                label: WalletLocalizationHelper
                                    .localizeWalletWithContext(context, wallet),
                                tint: context.appTextSecondary,
                              ),
                              _buildTemplatePill(
                                icon: Icons.notifications_none_rounded,
                                label: schedule.reminderDaysBefore > 0
                                    ? context.tr(
                                        'rec_reminder_before',
                                        params: {
                                          'days':
                                              '${schedule.reminderDaysBefore}'
                                        },
                                      )
                                    : context.tr('rec_reminder_due_day'),
                                tint: context.appTextSecondary,
                              ),
                            ],
                          ),
                        ),
                        // Compact Footer Bar (Next due / paused + Active switch)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
                          child: Row(
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: !schedule.isActive
                                      ? context.appTextSecondary
                                      : (isDueNow
                                          ? Colors.orange.shade700
                                          : AppColors.primary),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  schedule.isActive
                                      ? context.tr(
                                          'rec_next_cycle',
                                          params: {
                                            'date': DateFormat('dd/MM/yyyy')
                                                .format(schedule.nextDueDate)
                                          },
                                        )
                                      : context.tr('rec_paused_status'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: isDueNow
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    color: !schedule.isActive
                                        ? context.appTextSecondary
                                        : (isDueNow
                                            ? Colors.orange.shade800
                                            : context.appTextPrimary),
                                  ),
                                ),
                              ),
                              Transform.scale(
                                scale: 0.82,
                                child: Switch(
                                  value: schedule.isActive,
                                  activeThumbColor: Colors.white,
                                  activeTrackColor: AppColors.primary,
                                  inactiveThumbColor:
                                      context.appTextSecondary,
                                  inactiveTrackColor: context.isDarkMode
                                      ? AppColors.slate700
                                      : AppColors.slate200,
                                  trackOutlineColor:
                                      WidgetStateProperty.resolveWith(
                                    (states) => schedule.isActive
                                        ? AppColors.primary
                                        : context.appBorder,
                                  ),
                                  onChanged: isToggling
                                      ? null
                                      : (val) => _toggleScheduleActive(
                                            schedule,
                                            displayName,
                                            val,
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
              }),
          ],
        ],
      ),
    );
  }

  void _confirmDelete(RecurringTransactionSchedule schedule) {
    final displayName = _scheduleDisplayName(schedule);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Row(
          children: [
            const Icon(Icons.delete_outline_rounded,
                color: AppColors.expense, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.tr('rec_dlg_del_title'),
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Text(
          context.tr('rec_dlg_del_desc', params: {'name': displayName}),
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.tr('common_cancel')),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _notificationService
                  .cancelRemindersForSchedule(schedule.scheduleId);
              await _firestoreService
                  .deleteRecurringTransaction(schedule.scheduleId);
              if (mounted) {
                AppSnackbar.show(
                  this.context,
                  this.context.tr('rec_dlg_del_ok', params: {'name': displayName}),
                );
              }
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.expense),
            child: Text(context.tr('common_delete')),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 3. ADD / EDIT FORM DIALOG
  // ============================================================
  void _showFormDialog({RecurringTransactionSchedule? schedule}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.appCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _RecurringFormSheet(
        schedule: schedule,
        initialWallets: _cachedWallets,
        initialCategories: _cachedCategories,
      ),
    );
  }
}

class _RecurringFormSheet extends StatefulWidget {
  final RecurringTransactionSchedule? schedule;
  final List<Wallet> initialWallets;
  final List<Category> initialCategories;

  const _RecurringFormSheet({
    this.schedule,
    this.initialWallets = const [],
    this.initialCategories = const [],
  });

  @override
  State<_RecurringFormSheet> createState() => _RecurringFormSheetState();
}

class _RecurringFormSheetState extends State<_RecurringFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _firestoreService = FirestoreService();
  final _recService = RecurringTransactionService();
  final _notificationService = LocalNotificationService();

  late final String _uid;
  late final Stream<List<Wallet>> _walletsStream;
  late final Stream<List<Category>> _allCategoriesStream;

  late List<Wallet> _cachedWallets;
  late List<Category> _cachedCategories;

  late String _type;
  late TextEditingController _amountController;
  late TextEditingController _noteController;
  String? _selectedWalletId;
  String? _selectedCategoryId;
  late String _frequency;
  late DateTime _startDate;
  late int _reminderDaysBefore;
  late String _postingMode;
  double _parsedAmount = 0;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _walletsStream = _firestoreService.streamWallets(_uid);
    _allCategoriesStream = _firestoreService.streamCategories(_uid);

    _cachedWallets = List<Wallet>.from(widget.initialWallets);
    _cachedCategories = List<Category>.from(widget.initialCategories);

    final s = widget.schedule;
    _type = s?.type ?? 'expense';
    _amountController = TextEditingController(
      text: s != null && s.amount > 0 ? AppFormatters.number(s.amount) : '',
    );
    _parsedAmount = s?.amount ?? 0;
    _amountController.addListener(_onAmountChanged);
    _noteController = TextEditingController(text: s?.note ?? '');
    _selectedWalletId = s?.walletId;
    _selectedCategoryId = s?.categoryId;
    _frequency = s?.frequency ?? 'monthly';
    _startDate = s?.startDate ?? DateTime.now();
    _reminderDaysBefore = s?.reminderDaysBefore ?? 1;
    _postingMode =
        s?.postingMode ?? RecurringTransactionSchedule.postingModeManual;

    final activeWallets = _cachedWallets.where((w) => w.isActive).toList();
    if (_selectedWalletId == null && activeWallets.isNotEmpty) {
      _selectedWalletId = activeWallets.first.walletId;
    }
    final typedCategories =
        _cachedCategories.where((c) => c.type == _type).toList();
    if (_selectedCategoryId == null && typedCategories.isNotEmpty) {
      _selectedCategoryId = typedCategories.first.categoryId;
    }
  }

  void _onAmountChanged() {
    if (!mounted) return;
    final nextAmount =
        AppFormatters.parseCurrencyInput(_amountController.text);
    if (nextAmount != _parsedAmount) {
      setState(() => _parsedAmount = nextAmount);
    }
  }

  @override
  void dispose() {
    _amountController.removeListener(_onAmountChanged);
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedWalletId == null || _selectedWalletId!.isEmpty) {
      AppSnackbar.show(context, context.tr('rec_form_err_wallet'),
          isError: true);
      return;
    }
    if (_selectedCategoryId == null || _selectedCategoryId!.isEmpty) {
      AppSnackbar.show(
        context,
        context.tr(
          _type == 'income' ? 'rec_form_err_cat_inc' : 'rec_form_err_cat_exp',
        ),
        isError: true,
      );
      return;
    }

    final double amount =
        AppFormatters.parseCurrencyInput(_amountController.text);
    if (amount <= 0) {
      AppSnackbar.show(context, context.tr('rec_form_err_amt_pos'),
          isError: true);
      return;
    }

    setState(() => _isSaving = true);

    final fallbackWalletName = context.tr('goal_mgmt_wdr_wallet_default');
    String walletName = fallbackWalletName;
    final cachedWallet = _cachedWallets
        .where((w) => w.walletId == _selectedWalletId)
        .firstOrNull;
    if (cachedWallet != null && cachedWallet.walletName.trim().isNotEmpty) {
      walletName = WalletLocalizationHelper.localizeWallet(cachedWallet).trim();
    } else {
      try {
        final walletDoc = await FirebaseFirestore.instance
            .collection('wallets')
            .doc(_selectedWalletId)
            .get();
        if (walletDoc.exists && walletDoc.data() != null) {
          final parsed = Wallet.fromMap(walletDoc.data()!, walletDoc.id);
          final resolved = WalletLocalizationHelper.localizeWallet(parsed).trim();
          if (resolved.isNotEmpty) walletName = resolved;
        }
      } catch (_) {}
    }

    String scheduleNote = _noteController.text.trim();
    if (scheduleNote.isEmpty) {
      final matchedCategory = _cachedCategories
          .where((c) => c.categoryId == _selectedCategoryId)
          .firstOrNull;
      if (matchedCategory != null && matchedCategory.name.trim().isNotEmpty) {
        scheduleNote = matchedCategory.name.trim();
      }
    }

    try {
      if (widget.schedule == null) {
        // Tạo mới schedule
        final newSchedule = RecurringTransactionSchedule(
          scheduleId: '',
          userId: _uid,
          type: _type,
          walletId: _selectedWalletId!,
          categoryId: _selectedCategoryId!,
          amount: amount,
          note: scheduleNote,
          frequency: _frequency,
          startDate: _startDate,
          nextDueDate: _startDate,
          isActive: true,
          createdAt: DateTime.now(),
          reminderDaysBefore: _reminderDaysBefore,
          postingMode: _postingMode,
        );

        final docId =
            await _firestoreService.createRecurringTransaction(newSchedule);

        final scheduledItem = RecurringTransactionSchedule(
          scheduleId: docId,
          userId: _uid,
          type: _type,
          walletId: _selectedWalletId!,
          categoryId: _selectedCategoryId!,
          amount: amount,
          note: scheduleNote,
          frequency: _frequency,
          startDate: _startDate,
          nextDueDate: _startDate,
          isActive: true,
          createdAt: DateTime.now(),
          reminderDaysBefore: _reminderDaysBefore,
          postingMode: _postingMode,
        );

        await _notificationService.scheduleRemindersForSchedule(
          schedule: scheduledItem,
          walletName: walletName,
        );
        await _firestoreService.syncRecurringNotifications(_uid);

        if (!mounted) return;
        AppSnackbar.show(context, context.tr('rec_form_created_ok'));
      } else {
        // Cập nhật schedule cũ — bảo toàn nextDueDate nếu startDate và frequency không đổi
        final existing = widget.schedule!;
        final startDateChanged =
            RecurringTransactionService.dateOnly(_startDate) !=
                RecurringTransactionService.dateOnly(existing.startDate);
        final effectiveStartDate =
            startDateChanged ? _startDate : existing.startDate;
        final resolvedNextDueDate = _recService.resolveNextDueDateOnEdit(
          existing: existing,
          newStartDate: effectiveStartDate,
          newFrequency: _frequency,
        );

        final updateData = {
          'type': _type,
          'walletId': _selectedWalletId,
          'categoryId': _selectedCategoryId,
          'amount': amount,
          'note': scheduleNote,
          'frequency': _frequency,
          'startDate': effectiveStartDate.toIso8601String(),
          'nextDueDate': resolvedNextDueDate.toIso8601String(),
          'reminderDaysBefore': _reminderDaysBefore,
          'postingMode': _postingMode,
        };

        await _firestoreService.updateRecurringTransaction(
            existing.scheduleId, updateData);

        final updatedSchedule = existing.copyWith(
          type: _type,
          walletId: _selectedWalletId,
          categoryId: _selectedCategoryId,
          amount: amount,
          note: scheduleNote,
          frequency: _frequency,
          startDate: effectiveStartDate,
          nextDueDate: resolvedNextDueDate,
          isActive: existing.isActive,
          reminderDaysBefore: _reminderDaysBefore,
          postingMode: _postingMode,
        );
        await _notificationService.scheduleRemindersForSchedule(
          schedule: updatedSchedule,
          walletName: walletName,
        );
        await _firestoreService.syncRecurringNotifications(_uid);

        if (!mounted) return;
        AppSnackbar.show(context, context.tr('rec_form_updated_ok'));
      }

      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      AppSnackbar.show(
        context,
        context.tr('rec_form_save_err', params: {'err': e.toString()}),
        isError: true,
      );
    }
  }

  Widget _buildSummaryLine(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            flex: 4,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: context.appTextSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 5,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: valueColor ?? context.appTextPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final parsedAmount = _parsedAmount;
    final isIncome = _type == 'income';
    final cycleLabel = _frequency == 'weekly'
        ? context.tr('rec_form_cycle_weekly')
        : context.tr('rec_form_cycle_monthly');

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        widget.schedule == null
                            ? context.tr('rec_form_title_add')
                            : context.tr('rec_form_title_edit'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Segmented Button: Thu nhập / Chi tiêu
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'expense',
                        label: Text(context.tr('common_expense')),
                        icon: const Icon(Icons.arrow_downward_rounded),
                      ),
                      ButtonSegment(
                        value: 'income',
                        label: Text(context.tr('common_income')),
                        icon: const Icon(Icons.arrow_upward_rounded),
                      ),
                    ],
                    selected: {_type},
                    onSelectionChanged: (val) {
                      final newType = val.first;
                      if (newType != _type) {
                        setState(() {
                          _type = newType;
                          final matchingCats = _cachedCategories
                              .where((c) => c.type == _type)
                              .toList();
                          if (_selectedCategoryId != null &&
                              !matchingCats.any(
                                  (c) => c.categoryId == _selectedCategoryId)) {
                            _selectedCategoryId = matchingCats.isNotEmpty
                                ? matchingCats.first.categoryId
                                : null;
                          }
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(height: 16),

                // Input Số tiền
                TextFormField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  inputFormatters: const [CurrencyInputFormatter()],
                  decoration: InputDecoration(
                    labelText: context.tr('rec_form_amt_label'),
                    prefixIcon: const Icon(Icons.attach_money_rounded),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return context.tr('rec_form_amt_empty');
                    }
                    final n = AppFormatters.parseCurrencyInput(val);
                    if (n <= 0) return context.tr('rec_form_amt_invalid');
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // Wallet Dropdown & Thông tin ví / Cảnh báo số dư
                StreamBuilder<List<Wallet>>(
                  stream: _walletsStream,
                  builder: (context, walletSnap) {
                    if (walletSnap.hasData) {
                      _cachedWallets = walletSnap.data!;
                    }
                    final activeWallets =
                        _cachedWallets.where((w) => w.isActive).toList();

                    if (_selectedWalletId != null &&
                        !activeWallets
                            .any((w) => w.walletId == _selectedWalletId)) {
                      _selectedWalletId = null;
                    }
                    if (activeWallets.isNotEmpty && _selectedWalletId == null) {
                      _selectedWalletId = activeWallets.first.walletId;
                    }

                    final selectedWallet = activeWallets
                        .where((w) => w.walletId == _selectedWalletId)
                        .firstOrNull;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DropdownButtonFormField<String>(
                          key: ValueKey(
                              'wallet_dropdown_${_selectedWalletId ?? 'none'}_${activeWallets.length}'),
                          initialValue: _selectedWalletId,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: isIncome
                                ? context.tr('rec_form_wallet_inc')
                                : context.tr('rec_form_wallet_exp'),
                            prefixIcon: const Icon(
                                Icons.account_balance_wallet_outlined),
                            border: const OutlineInputBorder(),
                          ),
                          selectedItemBuilder: (context) {
                            return activeWallets.map((w) {
                              return Align(
                                alignment: Alignment.centerLeft,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        w.walletName.trim().isNotEmpty
                                            ? WalletLocalizationHelper
                                                .localizeWalletWithContext(
                                                    context, w)
                                            : context.tr(
                                                'rec_form_unnamed_wallet'),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: context.appTextPrimary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      AppFormatters.compactCurrency(w.balance,
                                          unit: '₫'),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: context.appTextSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList();
                          },
                          items: activeWallets.map((w) {
                            return DropdownMenuItem<String>(
                              value: w.walletId,
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      w.walletName.trim().isNotEmpty
                                          ? WalletLocalizationHelper
                                              .localizeWalletWithContext(
                                                  context, w)
                                          : context.tr(
                                              'rec_form_unnamed_wallet'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    AppFormatters.compactCurrency(w.balance,
                                        unit: '₫'),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: context.appTextSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null && val != _selectedWalletId) {
                              setState(() => _selectedWalletId = val);
                            }
                          },
                          validator: (val) {
                            if (val == null || val.isEmpty) {
                              return context.tr('rec_form_wallet_req');
                            }
                            return null;
                          },
                        ),

                        // Thẻ tóm tắt Ví & Cảnh báo số dư trực quan
                        if (selectedWallet != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: (!isIncome &&
                                      parsedAmount > 0 &&
                                      parsedAmount > selectedWallet.balance)
                                  ? AppColors.warning.withValues(alpha: 0.08)
                                  : AppColors.primary.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: (!isIncome &&
                                        parsedAmount > 0 &&
                                        parsedAmount > selectedWallet.balance)
                                    ? AppColors.warning.withValues(alpha: 0.35)
                                    : AppColors.primary.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildSummaryLine(
                                  isIncome
                                      ? context.tr('rec_form_sum_wallet_inc')
                                      : context.tr('rec_dlg_pay_wallet'),
                                  WalletLocalizationHelper
                                      .localizeWalletWithContext(
                                          context, selectedWallet),
                                ),
                                _buildSummaryLine(
                                  context.tr('rec_dlg_avail_bal'),
                                  AppFormatters.currency(
                                      selectedWallet.balance),
                                  valueColor: selectedWallet.balance > 0
                                      ? AppColors.income
                                      : context.appTextPrimary,
                                ),
                                if (parsedAmount > 0) ...[
                                  _buildSummaryLine(
                                    context.tr(
                                      isIncome
                                          ? 'rec_form_sum_inc_cycle'
                                          : 'rec_form_sum_exp_cycle',
                                      params: {'cycle': cycleLabel},
                                    ),
                                    AppFormatters.currency(parsedAmount),
                                    valueColor: isIncome
                                        ? AppColors.income
                                        : AppColors.expense,
                                  ),
                                  const Divider(height: 12),
                                  if (!isIncome &&
                                      parsedAmount > selectedWallet.balance)
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Icon(
                                            Icons.warning_amber_rounded,
                                            color: AppColors.warning,
                                            size: 16),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            context.tr(
                                              'rec_form_warn_shortfall',
                                              params: {
                                                'shortfall':
                                                    AppFormatters.currency(
                                                        parsedAmount -
                                                            selectedWallet
                                                                .balance),
                                                'autoNote': _postingMode ==
                                                        RecurringTransactionSchedule
                                                            .postingModeAuto
                                                    ? context.tr(
                                                        'rec_form_warn_auto_note')
                                                    : '',
                                              },
                                            ),
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.warning,
                                              height: 1.35,
                                            ),
                                          ),
                                        ),
                                      ],
                                    )
                                  else if (!isIncome)
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Icon(Icons.info_outline_rounded,
                                            color: AppColors.primary, size: 15),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            context.tr(
                                              'rec_form_est_cycles',
                                              params: {
                                                'count':
                                                    '${(selectedWallet.balance / parsedAmount).floor()}',
                                              },
                                            ),
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: AppColors.primary,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ],
                                    )
                                  else
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Icon(
                                            Icons.check_circle_outline_rounded,
                                            color: AppColors.income,
                                            size: 15),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            context.tr(
                                              'rec_form_est_after_inc',
                                              params: {
                                                'amount':
                                                    AppFormatters.currency(
                                                        selectedWallet.balance +
                                                            parsedAmount),
                                              },
                                            ),
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: AppColors.income,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),

                // Category Dropdown (Áp dụng cho CẢ Thu nhập và Chi tiêu, lọc tức thì trong bộ nhớ)
                StreamBuilder<List<Category>>(
                  stream: _allCategoriesStream,
                  builder: (context, catSnap) {
                    if (catSnap.hasData) {
                      _cachedCategories = catSnap.data!;
                    }

                    if (catSnap.connectionState == ConnectionState.waiting &&
                        !catSnap.hasData &&
                        _cachedCategories.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child:
                            LinearProgressIndicator(color: AppColors.primary),
                      );
                    }

                    final categories = _cachedCategories
                        .where((c) => c.type == _type)
                        .toList();

                    // Reset _selectedCategoryId nếu không thuộc danh sách hiện tại
                    if (_selectedCategoryId != null &&
                        !categories
                            .any((c) => c.categoryId == _selectedCategoryId)) {
                      _selectedCategoryId = null;
                    }

                    if (categories.isNotEmpty && _selectedCategoryId == null) {
                      _selectedCategoryId = categories.first.categoryId;
                    }

                    if (categories.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.warning.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline_rounded,
                                color: AppColors.warning, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                context.tr(
                                  _type == 'income'
                                      ? 'rec_form_no_cat_inc'
                                      : 'rec_form_no_cat_exp',
                                ),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return DropdownButtonFormField<String>(
                      key: ValueKey(
                          'category_dropdown_${_type}_${_selectedCategoryId ?? 'none'}_${categories.length}'),
                      initialValue: _selectedCategoryId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: context.tr(
                          _type == 'income'
                              ? 'rec_form_cat_inc_label'
                              : 'rec_form_cat_exp_label',
                        ),
                        prefixIcon: const Icon(Icons.category_outlined),
                        border: const OutlineInputBorder(),
                      ),
                      items: categories.map((c) {
                        return DropdownMenuItem<String>(
                          value: c.categoryId,
                          child: Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: Color(c.color),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  CategoryLocalizationHelper
                                      .localizeNameWithContext(context, c.name),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null && val != _selectedCategoryId) {
                          setState(() => _selectedCategoryId = val);
                        }
                      },
                      validator: (val) {
                        if (val == null || val.isEmpty) {
                          return context.tr('rec_form_cat_req');
                        }
                        return null;
                      },
                    );
                  },
                ),
                const SizedBox(height: 14),

                // Input Ghi chú / Tên lịch
                TextFormField(
                  controller: _noteController,
                  decoration: InputDecoration(
                    labelText: context.tr('rec_form_note_label'),
                    prefixIcon: const Icon(Icons.edit_note_rounded),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),

                // Dropdown Tần suất
                DropdownButtonFormField<String>(
                  key: ValueKey('frequency_dropdown_$_frequency'),
                  initialValue: _frequency,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: context.tr('rec_form_freq_label'),
                    prefixIcon: const Icon(Icons.repeat_rounded),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'monthly',
                      child: Text(
                        context.tr('rec_form_freq_monthly'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'weekly',
                      child: Text(
                        context.tr('rec_form_freq_weekly'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null && val != _frequency) {
                      setState(() => _frequency = val);
                    }
                  },
                ),
                const SizedBox(height: 14),

                // Selection: Cách ghi nhận giao dịch
                Text(
                  context.tr('rec_form_posting_label'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    border:
                        Border.all(color: Colors.grey.withValues(alpha: 0.4)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: RadioGroup<String>(
                    groupValue: _postingMode,
                    onChanged: (val) {
                      if (val != null && val != _postingMode) {
                        setState(() => _postingMode = val);
                      }
                    },
                    child: Column(
                      children: [
                        RadioListTile<String>(
                          value: RecurringTransactionSchedule.postingModeManual,
                          title: Text(context.tr('rec_form_manual_title'),
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                          subtitle: Text(context.tr('rec_form_manual_sub'),
                              style: const TextStyle(fontSize: 11)),
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 8),
                          dense: true,
                        ),
                        const Divider(height: 1),
                        RadioListTile<String>(
                          value: RecurringTransactionSchedule.postingModeAuto,
                          title: Text(context.tr('rec_form_auto_title'),
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                          subtitle: Text(context.tr('rec_form_auto_sub'),
                              style: const TextStyle(fontSize: 11)),
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 8),
                          dense: true,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Picker Ngày bắt đầu / Ngày đến hạn đầu tiên
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _startDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                    );
                    if (picked != null && picked != _startDate) {
                      setState(() => _startDate = picked);
                    }
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: context.tr('rec_form_start_label'),
                      prefixIcon: const Icon(Icons.calendar_today_rounded),
                      border: const OutlineInputBorder(),
                    ),
                    child: Text(DateFormat('dd/MM/yyyy').format(_startDate)),
                  ),
                ),
                const SizedBox(height: 14),

                // Dropdown Nhắc nhở trước hạn (isExpanded: true để chống tràn pixel tuyệt đối)
                DropdownButtonFormField<int>(
                  key: ValueKey('reminder_dropdown_$_reminderDaysBefore'),
                  initialValue: _reminderDaysBefore,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: context.tr('rec_form_rem_label'),
                    prefixIcon: const Icon(Icons.notifications_active_outlined),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 0,
                      child: Text(
                        context.tr('rec_form_rem_0'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 1,
                      child: Text(
                        context.tr('rec_form_rem_1'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 3,
                      child: Text(
                        context.tr('rec_form_rem_3'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 7,
                      child: Text(
                        context.tr('rec_form_rem_7'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null && val != _reminderDaysBefore) {
                      setState(() => _reminderDaysBefore = val);
                    }
                  },
                ),
                const SizedBox(height: 20),

                // Submit Button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isSaving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            widget.schedule == null
                                ? context.tr('rec_form_save_btn')
                                : context.tr('rec_form_update_btn'),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ============================================================
/// RECURRING HERO CARD (Quy đổi ước tính hàng tháng, chống tràn đa ngôn ngữ)
/// ============================================================
class RecurringHeroCard extends StatelessWidget {
  final List<RecurringTransactionSchedule> schedules;
  final int dueCount;
  final VoidCallback? onTapDueBadge;

  const RecurringHeroCard({
    super.key,
    required this.schedules,
    required this.dueCount,
    this.onTapDueBadge,
  });

  @override
  Widget build(BuildContext context) {
    final summary =
        RecurringTransactionService.computeMonthlySummary(schedules);
    final expenseTotal = summary.estimatedMonthlyExpense;
    final incomeTotal = summary.estimatedMonthlyIncome;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1F6F8B), Color(0xFF134A5D)],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
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
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Icon(Icons.event_repeat_rounded,
                          color: Colors.white, size: 16),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        context.tr('rec_hero_planned_period'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (dueCount > 0)
                Flexible(
                  child: GestureDetector(
                    onTap: onTapDueBadge,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.expense.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.warning_amber_rounded,
                                color: Colors.white, size: 12),
                            const SizedBox(width: 4),
                            Text(
                              context.tr(
                                'rec_hero_pending_badge',
                                params: {'count': dueCount.toString()},
                              ),
                              maxLines: 1,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              else
                Flexible(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        context.tr(
                          'rec_hero_active_badge',
                          params: {'count': summary.activeCount.toString()},
                        ),
                        maxLines: 1,
                        style: const TextStyle(
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
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: FittedBox(
              key: ValueKey('hero_expense_${expenseTotal.round()}'),
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                AppFormatters.compactCurrency(expenseTotal, unit: '₫'),
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ),
          if (summary.hasWeeklySchedules) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 12,
                  color: Colors.white.withValues(alpha: 0.78),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    context.tr(
                      'rec_hero_weekly_converted_note',
                      params: {'count': summary.activeWeeklyCount.toString()},
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: Colors.white.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  flex: 6,
                  child: Row(
                    children: [
                      const Icon(Icons.arrow_downward_rounded,
                          color: Color(0xFF56D69B), size: 13),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          context.tr(
                            'rec_hero_income_sub',
                            params: {
                              'amount': AppFormatters.compactCurrency(
                                  incomeTotal,
                                  unit: '₫')
                            },
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.95),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  flex: 4,
                  child: Text(
                    context.tr(
                      'rec_hero_active_ratio',
                      params: {
                        'active': summary.activeCount.toString(),
                        'total': schedules.length.toString(),
                      },
                    ),
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

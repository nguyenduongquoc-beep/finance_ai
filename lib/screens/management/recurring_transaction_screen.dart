import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../models/recurring_transaction_model.dart';
import '../../models/recurring_transaction_occurrence_model.dart';
import '../../models/wallet_model.dart';
import '../../models/category_model.dart';
import '../../services/firestore_service.dart';
import '../../services/local_notification_service.dart';
import '../../services/recurring_transaction_service.dart';
import '../../services/theme_controller.dart';
import '../../utils/constants.dart';
import '../../utils/formatters.dart';
import '../../widgets/app_snackbar.dart';

/// ============================================================
/// RECURRING TRANSACTION SCREEN
/// Giao dịch định kỳ & Lịch hóa đơn
/// ============================================================
class RecurringTransactionScreen extends StatefulWidget {
  final String? targetScheduleId;

  const RecurringTransactionScreen({super.key, this.targetScheduleId});

  @override
  State<RecurringTransactionScreen> createState() =>
      _RecurringTransactionScreenState();
}

class _RecurringTransactionScreenState
    extends State<RecurringTransactionScreen> {
  final _firestoreService = FirestoreService();
  final _recService = RecurringTransactionService();
  final _notificationService = LocalNotificationService();

  bool _isProcessingDue = false;
  int _selectedUpcomingDays = 30; // 7, 14, 30 ngày
  /// Tracks scheduleIds currently processing an action (confirm/skip/defer)
  /// to prevent double-tap while an async operation is in flight.
  final Set<String> _actionInProgressIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _processDueTransactions(showFeedback: false);
      _notificationService.requestPermission();
    });
  }

  /// Xử lý các kỳ đến hạn bằng Firestore transaction atomic & idempotent (chỉ tự động post các lịch autoPost)
  Future<void> _processDueTransactions({bool showFeedback = true}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;

    setState(() => _isProcessingDue = true);

    try {
      final result =
          await _firestoreService.processDueRecurringTransactions(uid);
      final int processed = result['processedCount'] ?? 0;
      final List<String> failedMessages =
          List<String>.from(result['failedSchedules'] ?? []);

      if (!mounted) return;
      setState(() => _isProcessingDue = false);

      if (processed > 0) {
        AppSnackbar.show(
            context, 'Đã tự động tạo $processed giao dịch định kỳ đến hạn!');
      } else if (showFeedback && failedMessages.isEmpty) {
        AppSnackbar.show(context, 'Tất cả khoản định kỳ đều đã được cập nhật!');
      }

      // Cảnh báo nếu có khoản không tạo được vì ví không đủ số dư
      if (failedMessages.isNotEmpty) {
        _showFailedDialog(failedMessages);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessingDue = false);
      AppSnackbar.show(context, 'Lỗi kiểm tra giao dịch đến hạn: $e',
          isError: true);
    }
  }

  void _showFailedDialog(List<String> messages) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.expense),
            SizedBox(width: 8),
            Text('Khoản đến hạn chưa tạo'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Không thể tự động tạo các giao dịch sau do ví không đủ số dư:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            ...messages.map((msg) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.expense)),
                      Expanded(
                          child:
                              Text(msg, style: const TextStyle(fontSize: 12))),
                    ],
                  ),
                )),
            const SizedBox(height: 8),
            const Text(
              'Vui lòng nạp thêm tiền vào ví và bấm "Kiểm tra giao dịch đến hạn" để thực hiện lại.',
              style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Đã hiểu'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, _, __) {
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Giao dịch định kỳ & Hóa đơn'),
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
                tooltip: 'Kiểm tra giao dịch đến hạn',
                onPressed: _isProcessingDue
                    ? null
                    : () => _processDueTransactions(showFeedback: true),
              ),
            ],
          ),
          body: StreamBuilder<List<RecurringTransactionSchedule>>(
            stream: _firestoreService.streamRecurringTransactions(uid),
            builder: (context, scheduleSnap) {
              if (scheduleSnap.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: AppColors.primary));
              }

              final schedules = scheduleSnap.data ?? [];

              return StreamBuilder<List<RecurringTransactionOccurrence>>(
                stream: _firestoreService.streamRecurringOccurrences(uid),
                builder: (context, occurrenceSnap) {
                  final occurrences = occurrenceSnap.data ?? [];

                  return StreamBuilder<List<Wallet>>(
                    stream: _firestoreService.streamWallets(uid),
                    builder: (context, walletSnap) {
                      final wallets = walletSnap.data ?? [];

                      return StreamBuilder<List<Category>>(
                        stream: _firestoreService.streamCategories(uid),
                        builder: (context, categorySnap) {
                          final categories = categorySnap.data ?? [];

                          return ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              // Section 0: Cần xác nhận hôm nay (Ưu tiên)
                              _buildNeedsConfirmationSection(
                                  schedules, occurrences, wallets, categories),

                              // Section 1: Lịch hóa đơn sắp tới
                              _buildUpcomingSection(
                                  schedules, wallets, categories),
                              const SizedBox(height: 20),

                              // Section 2: Danh sách lịch định kỳ
                              _buildScheduleListSection(
                                  schedules, wallets, categories),
                              const SizedBox(height: 80), // Padding cho FAB
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
            icon: const Icon(Icons.add_rounded),
            label: const Text('Thêm lịch mới'),
            backgroundColor: AppColors.primary,
          ),
        );
      },
    );
  }

  // ============================================================
  // 0. NEEDS CONFIRMATION SECTION (KHU VỰC ƯU TIÊN)
  // ============================================================
  Widget _buildNeedsConfirmationSection(
    List<RecurringTransactionSchedule> schedules,
    List<RecurringTransactionOccurrence> occurrences,
    List<Wallet> wallets,
    List<Category> categories,
  ) {
    final now = DateTime.now();

    final manualSchedules = schedules.where((s) {
      if (!s.isActive) return false;
      if (s.postingMode != RecurringTransactionSchedule.postingModeManual) {
        return false;
      }
      if (s.nextDueDate.isAfter(now)) return false;

      final key = RecurringTransactionService.getOccurrenceKey(s.nextDueDate);
      final isProcessed = occurrences.any(
        (o) => o.scheduleId == s.scheduleId && o.occurrenceKey == key,
      );
      return !isProcessed;
    }).toList();

    if (manualSchedules.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.assignment_late_rounded,
                    color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Cần xác nhận hôm nay',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${manualSchedules.length} khoản',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          ...manualSchedules.map((schedule) {
            final isIncome = schedule.type == 'income';
            final color = isIncome ? AppColors.income : AppColors.expense;
            final wallet = wallets.firstWhere(
              (w) => w.walletId == schedule.walletId,
              orElse: () => Wallet(
                walletId: '',
                userId: '',
                walletName: 'Ví',
                balance: 0,
                type: 'cash',
                createdAt: DateTime.now(),
              ),
            );

            final displayName = schedule.note != null && schedule.note!.isNotEmpty
                ? schedule.note!
                : (isIncome ? 'Thu nhập định kỳ' : 'Hóa đơn định kỳ');

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isIncome
                              ? Icons.arrow_downward_rounded
                              : Icons.arrow_upward_rounded,
                          color: color,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              'Ví: ${wallet.walletName} • Đã đến hạn (${DateFormat('dd/MM/yyyy').format(schedule.nextDueDate)})',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${isIncome ? '+' : '-'}${AppFormatters.number(schedule.amount)}đ',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        key: ValueKey('btn_confirm_${schedule.scheduleId}'),
                        onPressed: _actionInProgressIds.contains(schedule.scheduleId)
                            ? null
                            : () => _showConfirmOccurrenceDialog(
                                schedule, schedule.nextDueDate, wallet.walletName),
                        style: FilledButton.styleFrom(
                          backgroundColor: color,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: _actionInProgressIds.contains(schedule.scheduleId)
                            ? const SizedBox(
                                width: 14, height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.check_circle_outline, size: 16),
                        label: Text(
                          isIncome ? 'Xác nhận đã nhận' : 'Xác nhận thanh toán',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      OutlinedButton.icon(
                        key: ValueKey('btn_skip_${schedule.scheduleId}'),
                        onPressed: _actionInProgressIds.contains(schedule.scheduleId)
                            ? null
                            : () => _showSkipOccurrenceDialog(
                                schedule, schedule.nextDueDate),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.skip_next_rounded, size: 16),
                        label: const Text('Bỏ qua kỳ này',
                            style: TextStyle(fontSize: 12)),
                      ),
                      TextButton.icon(
                        key: ValueKey('btn_defer_${schedule.scheduleId}'),
                        onPressed: _actionInProgressIds.contains(schedule.scheduleId)
                            ? null
                            : () => _handleDeferOccurrence(
                                schedule, schedule.nextDueDate),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.edit_calendar_rounded, size: 16),
                        label: const Text('Dời ngày',
                            style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  void _showConfirmOccurrenceDialog(
    RecurringTransactionSchedule schedule,
    DateTime occurrenceDate,
    String walletName,
  ) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final isIncome = schedule.type == 'income';
    final displayName = schedule.note != null && schedule.note!.isNotEmpty
        ? schedule.note!
        : (isIncome ? 'Thu nhập định kỳ' : 'Hóa đơn định kỳ');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              isIncome ? Icons.account_balance_wallet : Icons.receipt_long,
              color: isIncome ? AppColors.income : AppColors.expense,
            ),
            const SizedBox(width: 8),
            Text(isIncome ? 'Xác nhận thu nhập' : 'Xác nhận thanh toán'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Bạn có chắc muốn hạch toán khoản tiền thật này vào tài khoản?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tên khoản: $displayName',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text('Số tiền: ${AppFormatters.number(schedule.amount)} VNĐ',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isIncome ? AppColors.income : AppColors.expense,
                          fontSize: 14)),
                  const SizedBox(height: 4),
                  Text('Ví hạch toán: $walletName', style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 4),
                  Text('Ngày hạch toán: ${DateFormat('dd/MM/yyyy').format(occurrenceDate)}',
                      style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              setState(() => _actionInProgressIds.add(schedule.scheduleId));
              try {
                await _firestoreService.confirmRecurringOccurrence(
                  userId: uid,
                  schedule: schedule,
                  occurrenceDate: occurrenceDate,
                );
                if (mounted) {
                  AppSnackbar.show(
                      context, 'Đã hạch toán giao dịch tiền thật thành công!');
                }
              } catch (e) {
                if (mounted) {
                  AppSnackbar.show(context, 'Lỗi xác nhận giao dịch: $e',
                      isError: true);
                }
              } finally {
                if (mounted) {
                  setState(() => _actionInProgressIds.remove(schedule.scheduleId));
                }
              }
            },
            style: FilledButton.styleFrom(
                backgroundColor: isIncome ? AppColors.income : AppColors.expense),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
  }

  void _showSkipOccurrenceDialog(
    RecurringTransactionSchedule schedule,
    DateTime occurrenceDate,
  ) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bỏ qua kỳ này?'),
        content: const Text(
          'Lịch định kỳ sẽ được chuyển sang kỳ kế tiếp. App sẽ không tạo giao dịch và không thay đổi số dư ví.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              setState(() => _actionInProgressIds.add(schedule.scheduleId));
              try {
                await _firestoreService.skipRecurringOccurrence(
                  userId: uid,
                  schedule: schedule,
                  occurrenceDate: occurrenceDate,
                );
                if (mounted) {
                  AppSnackbar.show(context, 'Đã bỏ qua kỳ giao dịch này.');
                }
              } catch (e) {
                if (mounted) {
                  AppSnackbar.show(context, 'Lỗi bỏ qua kỳ: $e', isError: true);
                }
              } finally {
                if (mounted) {
                  setState(() => _actionInProgressIds.remove(schedule.scheduleId));
                }
              }
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.expense),
            child: const Text('Bỏ qua'),
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
    final initial = occurrenceDate.isBefore(now) ? now : occurrenceDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(2035),
      helpText: 'CHỌN NGÀY DỜI ĐẾN HẠN MỚI',
    );

    if (picked == null || !mounted) return;

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận dời ngày'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Dời ngày đến hạn từ ${DateFormat('dd/MM/yyyy').format(occurrenceDate)} sang ${DateFormat('dd/MM/yyyy').format(picked)}.'),
            const SizedBox(height: 10),
            const Text(
              'Lưu ý: Các kỳ sau sẽ được tính tiếp từ ngày đã dời.',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              setState(() => _actionInProgressIds.add(schedule.scheduleId));
              try {
                await _firestoreService.deferRecurringOccurrence(
                  userId: uid,
                  schedule: schedule,
                  occurrenceDate: occurrenceDate,
                  newDueDate: picked,
                );
                if (mounted) {
                  AppSnackbar.show(context,
                      'Đã dời ngày đến hạn sang ${DateFormat('dd/MM/yyyy').format(picked)}.');
                }
              } catch (e) {
                if (mounted) {
                  AppSnackbar.show(context, 'Lỗi dời ngày: $e', isError: true);
                }
              } finally {
                if (mounted) {
                  setState(() => _actionInProgressIds.remove(schedule.scheduleId));
                }
              }
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Đồng ý dời'),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 1. UPCOMING BILLS SECTION
  // ============================================================
  Widget _buildUpcomingSection(
    List<RecurringTransactionSchedule> schedules,
    List<Wallet> wallets,
    List<Category> categories,
  ) {
    final now = DateTime.now();
    final upcomingList = _recService.upcomingOccurrences(
      schedules: schedules,
      referenceDate: now,
      daysAhead: _selectedUpcomingDays,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.calendar_month_rounded,
                      color: AppColors.primary, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Sắp đến hạn',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Row(
                children: [7, 14, 30].map((days) {
                  final isSelected = _selectedUpcomingDays == days;
                  return Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: ChoiceChip(
                      label: Text('$days ngày',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected
                                ? Colors.white
                                : AppColors.textSecondary,
                          )),
                      selected: isSelected,
                      selectedColor: AppColors.primary,
                      backgroundColor: AppColors.background,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      visualDensity: VisualDensity.compact,
                      onSelected: (val) {
                        if (val) {
                          setState(() => _selectedUpcomingDays = days);
                        }
                      },
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          if (upcomingList.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'Không có khoản thu/chi nào sắp đến hạn trong $_selectedUpcomingDays ngày tới.',
                  style:
                      TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ),
            )
          else
            ...upcomingList.map((item) {
              final isIncome = item.schedule.type == 'income';
              final color = isIncome ? AppColors.income : AppColors.expense;
              final wallet = wallets.firstWhere(
                (w) => w.walletId == item.schedule.walletId,
                orElse: () => Wallet(
                  walletId: '',
                  userId: '',
                  walletName: 'Ví',
                  balance: 0,
                  type: 'cash',
                  createdAt: DateTime.now(),
                ),
              );

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withOpacity(0.15)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isIncome
                            ? Icons.arrow_downward_rounded
                            : Icons.arrow_upward_rounded,
                        color: color,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.schedule.note != null &&
                                    item.schedule.note!.isNotEmpty
                                ? item.schedule.note!
                                : (isIncome
                                    ? 'Thu nhập định kỳ'
                                    : 'Hóa đơn định kỳ'),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Ví: ${wallet.walletName} • Hạn: ${DateFormat('dd/MM/yyyy').format(item.dueDate)}',
                            style: TextStyle(
                                fontSize: 11, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${isIncome ? '+' : '-'}${AppFormatters.number(item.schedule.amount)}đ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: color,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // ============================================================
  // 2. SCHEDULE LIST SECTION
  // ============================================================
  Widget _buildScheduleListSection(
    List<RecurringTransactionSchedule> schedules,
    List<Wallet> wallets,
    List<Category> categories,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Danh sách lịch lặp lại',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              '${schedules.length} lịch',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (schedules.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.event_repeat_rounded,
                      size: 40,
                      color: AppColors.textSecondary.withOpacity(0.5)),
                  const SizedBox(height: 8),
                  Text(
                    'Chưa có lịch giao dịch định kỳ nào',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          )
        else
          ...schedules.map((schedule) {
            final isIncome = schedule.type == 'income';
            final color = isIncome ? AppColors.income : AppColors.expense;
            final wallet = wallets.firstWhere(
              (w) => w.walletId == schedule.walletId,
              orElse: () => Wallet(
                walletId: '',
                userId: '',
                walletName: 'Ví',
                balance: 0,
                type: 'cash',
                createdAt: DateTime.now(),
              ),
            );

            final isManual = schedule.postingMode ==
                RecurringTransactionSchedule.postingModeManual;

            return Card(
              color: AppColors.card,
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                leading: CircleAvatar(
                  backgroundColor: color.withOpacity(0.12),
                  child: Icon(
                    isIncome
                        ? Icons.account_balance_wallet_outlined
                        : Icons.receipt_long_outlined,
                    color: color,
                    size: 20,
                  ),
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        schedule.note != null && schedule.note!.isNotEmpty
                            ? schedule.note!
                            : (isIncome
                                ? 'Thu nhập lặp lại'
                                : 'Chi phí lặp lại'),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          decoration: schedule.isActive
                              ? null
                              : TextDecoration.lineThrough,
                          color: schedule.isActive
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                    Text(
                      '${isIncome ? '+' : '-'}${AppFormatters.number(schedule.amount)}đ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: schedule.isActive ? color : Colors.grey,
                      ),
                    ),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(
                      'Ví: ${wallet.walletName} • Tần suất: ${schedule.frequency == 'weekly' ? 'Hàng tuần' : 'Hàng tháng'}',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                    Text(
                      'Ghi nhận: ${isManual ? 'Cần xác nhận' : 'Tự động'}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isManual
                            ? Colors.orange.shade800
                            : AppColors.primary,
                      ),
                    ),
                    Text(
                      'Hạn tiếp theo: ${DateFormat('dd/MM/yyyy').format(schedule.nextDueDate)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: schedule.isActive
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                    ),
                    if (schedule.reminderDaysBefore > 0)
                      Row(
                        children: [
                          Icon(Icons.notifications_active_outlined,
                              size: 12, color: AppColors.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            'Nhắc trước ${schedule.reminderDaysBefore} ngày',
                            style: TextStyle(
                                fontSize: 11, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: schedule.isActive,
                      activeColor: AppColors.primary,
                      onChanged: (val) async {
                        await _firestoreService.setRecurringTransactionActive(
                            schedule.scheduleId, val);
                        if (val) {
                          final w = wallets.firstWhere(
                            (w) => w.walletId == schedule.walletId,
                            orElse: () => Wallet(
                              walletId: '', userId: '', walletName: 'Ví',
                              balance: 0, type: 'cash', createdAt: DateTime.now(),
                            ),
                          );
                          await _notificationService.scheduleRemindersForSchedule(
                            schedule: schedule.copyWith(isActive: true),
                            walletName: w.walletName,
                          );
                        } else {
                          await _notificationService.cancelRemindersForSchedule(
                              schedule.scheduleId);
                        }
                      },
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, size: 20),
                      onSelected: (val) {
                        if (val == 'edit') {
                          _showFormDialog(schedule: schedule);
                        } else if (val == 'delete') {
                          _confirmDelete(schedule);
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit_outlined, size: 18),
                              SizedBox(width: 8),
                              Text('Chỉnh sửa'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline,
                                  size: 18, color: AppColors.expense),
                              SizedBox(width: 8),
                              Text('Xóa lịch',
                                  style: TextStyle(color: AppColors.expense)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  void _confirmDelete(RecurringTransactionSchedule schedule) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa lịch định kỳ?'),
        content: const Text(
          'Xóa lịch định kỳ này sẽ không xóa các giao dịch lịch sử đã phát sinh trước đây.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _notificationService.cancelRemindersForSchedule(
                  schedule.scheduleId);
              await _firestoreService
                  .deleteRecurringTransaction(schedule.scheduleId);
              if (mounted) {
                AppSnackbar.show(context, 'Đã xóa lịch định kỳ.');
              }
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.expense),
            child: const Text('Xóa'),
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
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _RecurringFormSheet(schedule: schedule),
    );
  }
}

class _RecurringFormSheet extends StatefulWidget {
  final RecurringTransactionSchedule? schedule;

  const _RecurringFormSheet({this.schedule});

  @override
  State<_RecurringFormSheet> createState() => _RecurringFormSheetState();
}

class _RecurringFormSheetState extends State<_RecurringFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _firestoreService = FirestoreService();
  final _notificationService = LocalNotificationService();

  late String _type;
  late TextEditingController _amountController;
  late TextEditingController _noteController;
  String? _selectedWalletId;
  String? _selectedCategoryId;
  late String _frequency;
  late DateTime _startDate;
  late int _reminderDaysBefore;
  late String _postingMode;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final s = widget.schedule;
    _type = s?.type ?? 'expense';
    _amountController = TextEditingController(
      text: s != null ? s.amount.toStringAsFixed(0) : '',
    );
    _noteController = TextEditingController(text: s?.note ?? '');
    _selectedWalletId = s?.walletId;
    _selectedCategoryId = s?.categoryId;
    _frequency = s?.frequency ?? 'monthly';
    _startDate = s?.startDate ?? DateTime.now();
    _reminderDaysBefore = s?.reminderDaysBefore ?? 1;
    _postingMode =
        s?.postingMode ?? RecurringTransactionSchedule.postingModeManual;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedWalletId == null || _selectedWalletId!.isEmpty) {
      AppSnackbar.show(context, 'Vui lòng chọn ví thực hiện.', isError: true);
      return;
    }
    if (_type == 'expense' &&
        (_selectedCategoryId == null || _selectedCategoryId!.isEmpty)) {
      AppSnackbar.show(context, 'Vui lòng chọn danh mục chi tiêu.',
          isError: true);
      return;
    }

    final double amount = double.tryParse(_amountController.text.trim()) ?? 0;
    if (amount <= 0) {
      AppSnackbar.show(context, 'Số tiền phải lớn hơn 0.', isError: true);
      return;
    }

    setState(() => _isSaving = true);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    String walletName = 'Ví';
    try {
      final walletDoc = await FirebaseFirestore.instance
          .collection('wallets')
          .doc(_selectedWalletId)
          .get();
      if (walletDoc.exists) {
        walletName = walletDoc.data()?['walletName'] ?? 'Ví';
      }
    } catch (_) {}

    try {
      if (widget.schedule == null) {
        // Tạo mới schedule (mặc định manualConfirmation nếu không chọn khác)
        final newSchedule = RecurringTransactionSchedule(
          scheduleId: '',
          userId: uid,
          type: _type,
          walletId: _selectedWalletId!,
          categoryId: _type == 'expense' ? _selectedCategoryId! : '',
          amount: amount,
          note: _noteController.text.trim(),
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

        if (_reminderDaysBefore > 0) {
          final savedSchedule = RecurringTransactionSchedule(
            scheduleId: docId,
            userId: uid,
            type: _type,
            walletId: _selectedWalletId!,
            categoryId: _type == 'expense' ? _selectedCategoryId! : '',
            amount: amount,
            note: _noteController.text.trim(),
            frequency: _frequency,
            startDate: _startDate,
            nextDueDate: _startDate,
            isActive: true,
            createdAt: DateTime.now(),
            reminderDaysBefore: _reminderDaysBefore,
            postingMode: _postingMode,
          );
          await _notificationService.scheduleRemindersForSchedule(
            schedule: savedSchedule,
            walletName: walletName,
          );
        }

        if (!mounted) return;
        AppSnackbar.show(context, 'Đã tạo lịch định kỳ thành công!');
      } else {
        // Cập nhật schedule cũ
        final updateData = {
          'type': _type,
          'walletId': _selectedWalletId,
          'categoryId': _type == 'expense' ? _selectedCategoryId : '',
          'amount': amount,
          'note': _noteController.text.trim(),
          'frequency': _frequency,
          'startDate': _startDate.toIso8601String(),
          'nextDueDate': _startDate.toIso8601String(),
          'reminderDaysBefore': _reminderDaysBefore,
          'postingMode': _postingMode,
        };

        await _firestoreService.updateRecurringTransaction(
            widget.schedule!.scheduleId, updateData);

        final updatedSchedule = widget.schedule!.copyWith(
          type: _type,
          walletId: _selectedWalletId,
          categoryId: _type == 'expense' ? _selectedCategoryId : '',
          amount: amount,
          note: _noteController.text.trim(),
          frequency: _frequency,
          startDate: _startDate,
          nextDueDate: _startDate,
          isActive: widget.schedule!.isActive,
          reminderDaysBefore: _reminderDaysBefore,
          postingMode: _postingMode,
        );
        await _notificationService.scheduleRemindersForSchedule(
          schedule: updatedSchedule,
          walletName: walletName,
        );

        if (!mounted) return;
        AppSnackbar.show(context, 'Đã cập nhật lịch định kỳ!');
      }

      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      AppSnackbar.show(context, 'Lỗi lưu lịch định kỳ: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Padding(
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
                  Text(
                    widget.schedule == null
                        ? 'Thêm lịch định kỳ mới'
                        : 'Chỉnh sửa lịch định kỳ',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Segmented Button: Thu nhập / Chi tiêu
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'expense',
                    label: Text('Chi tiêu'),
                    icon: Icon(Icons.arrow_upward_rounded),
                  ),
                  ButtonSegment(
                    value: 'income',
                    label: Text('Thu nhập'),
                    icon: Icon(Icons.arrow_downward_rounded),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (val) {
                  setState(() {
                    _type = val.first;
                  });
                },
              ),
              const SizedBox(height: 16),

              // Input Số tiền
              TextFormField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Số tiền (VNĐ) *',
                  prefixIcon: Icon(Icons.attach_money_rounded),
                  border: OutlineInputBorder(),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Vui lòng nhập số tiền';
                  }
                  final n = double.tryParse(val.trim());
                  if (n == null || n <= 0) return 'Số tiền không hợp lệ';
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // Wallet Dropdown
              StreamBuilder<List<Wallet>>(
                stream: _firestoreService.streamWallets(uid),
                builder: (context, walletSnap) {
                  final activeWallets =
                      (walletSnap.data ?? []).where((w) => w.isActive).toList();

                  if (activeWallets.isNotEmpty && _selectedWalletId == null) {
                    _selectedWalletId = activeWallets.first.walletId;
                  }

                  return DropdownButtonFormField<String>(
                    value: _selectedWalletId,
                    decoration: const InputDecoration(
                      labelText: 'Ví thực hiện *',
                      prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                      border: OutlineInputBorder(),
                    ),
                    items: activeWallets.map((w) {
                      return DropdownMenuItem(
                        value: w.walletId,
                        child: Text(w.walletName),
                      );
                    }).toList(),
                    onChanged: (val) => setState(() => _selectedWalletId = val),
                  );
                },
              ),
              const SizedBox(height: 14),

              // Category Dropdown (chỉ hiện khi type == expense)
              if (_type == 'expense') ...[
                StreamBuilder<List<Category>>(
                  stream:
                      _firestoreService.streamCategories(uid, type: 'expense'),
                  builder: (context, catSnap) {
                    final categories = catSnap.data ?? [];

                    if (categories.isNotEmpty && _selectedCategoryId == null) {
                      _selectedCategoryId = categories.first.categoryId;
                    }

                    return DropdownButtonFormField<String>(
                      value: _selectedCategoryId,
                      decoration: const InputDecoration(
                        labelText: 'Danh mục chi tiêu *',
                        prefixIcon: Icon(Icons.category_outlined),
                        border: OutlineInputBorder(),
                      ),
                      items: categories.map((c) {
                        return DropdownMenuItem(
                          value: c.categoryId,
                          child: Text(c.name),
                        );
                      }).toList(),
                      onChanged: (val) =>
                          setState(() => _selectedCategoryId = val),
                    );
                  },
                ),
                const SizedBox(height: 14),
              ],

              // Input Ghi chú / Tên lịch
              TextFormField(
                controller: _noteController,
                decoration: const InputDecoration(
                  labelText: 'Ghi chú / Tên khoản (VD: Tiền nhà, Lương)',
                  prefixIcon: Icon(Icons.edit_note_rounded),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),

              // Dropdown Tần suất
              DropdownButtonFormField<String>(
                value: _frequency,
                decoration: const InputDecoration(
                  labelText: 'Tần suất lặp *',
                  prefixIcon: Icon(Icons.repeat_rounded),
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                      value: 'monthly', child: Text('Hàng tháng (Monthly)')),
                  DropdownMenuItem(
                      value: 'weekly', child: Text('Hàng tuần (Weekly)')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _frequency = val);
                },
              ),
              const SizedBox(height: 14),

              // Selection: Cách ghi nhận giao dịch
              const Text(
                'Cách ghi nhận giao dịch',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.withOpacity(0.4)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    RadioListTile<String>(
                      value: RecurringTransactionSchedule.postingModeManual,
                      groupValue: _postingMode,
                      title: const Text('Cần xác nhận khi đến hạn',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: const Text(
                          'App nhắc bạn, chỉ ghi nhận sau khi bạn xác nhận.',
                          style: TextStyle(fontSize: 11)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      dense: true,
                      onChanged: (val) {
                        if (val != null) setState(() => _postingMode = val);
                      },
                    ),
                    const Divider(height: 1),
                    RadioListTile<String>(
                      value: RecurringTransactionSchedule.postingModeAuto,
                      groupValue: _postingMode,
                      title: const Text('Tự động ghi nhận khi đến hạn',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: const Text(
                          'App tự ghi nhận khi đến hạn và được kiểm tra lúc mở ứng dụng.',
                          style: TextStyle(fontSize: 11)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      dense: true,
                      onChanged: (val) {
                        if (val != null) setState(() => _postingMode = val);
                      },
                    ),
                  ],
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
                  if (picked != null) {
                    setState(() => _startDate = picked);
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Ngày bắt đầu / Kỳ đầu tiên *',
                    prefixIcon: Icon(Icons.calendar_today_rounded),
                    border: OutlineInputBorder(),
                  ),
                  child: Text(DateFormat('dd/MM/yyyy').format(_startDate)),
                ),
              ),
              const SizedBox(height: 14),

              // Dropdown Nhắc nhở trước hạn
              DropdownButtonFormField<int>(
                value: _reminderDaysBefore,
                decoration: const InputDecoration(
                  labelText: 'Nhắc nhở trước hạn',
                  prefixIcon: Icon(Icons.notifications_active_outlined),
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Không nhắc')),
                  DropdownMenuItem(value: 1, child: Text('Trước 1 ngày')),
                  DropdownMenuItem(value: 3, child: Text('Trước 3 ngày')),
                  DropdownMenuItem(value: 7, child: Text('Trước 7 ngày')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _reminderDaysBefore = val);
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
                      : Text(widget.schedule == null
                          ? 'Lưu lịch định kỳ'
                          : 'Cập nhật'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/monthly_financial_plan.dart';
import '../models/notification_model.dart';
import '../models/support_ticket_model.dart';
import '../services/firestore_service.dart';
import '../services/support_service.dart';
import '../utils/constants.dart';
import '../utils/notification_localization_helper.dart';
import '../widgets/app_card.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/stream_error_widget.dart';
import 'management/recurring_transaction_screen.dart';
import 'management/budget_management_screen.dart';
import 'support/support_ticket_detail_screen.dart';
import '../l10n/app_localizations.dart';

/// 20. Notification - Danh sách thông báo (Thông báo Hệ thống + Phản hồi Hỗ trợ + Thông báo cá nhân)
class NotificationScreen extends StatefulWidget {
  final FirestoreService? firestoreService;
  final SupportService? supportService;
  final String? userIdOverride;

  const NotificationScreen({
    super.key,
    this.firestoreService,
    this.supportService,
    this.userIdOverride,
  });

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  late final FirestoreService _firestoreService;
  late final SupportService _supportService;
  late final String _uid;
  late final Stream<List<AppNotification>> _notificationsStream;
  late final Stream<List<SystemAnnouncement>> _announcementsStream;
  late final Stream<List<SupportTicket>> _unreadSupportStream;

  @override
  void initState() {
    super.initState();
    _firestoreService = widget.firestoreService ?? FirestoreService();
    _supportService = widget.supportService ??
        SupportService(firestore: _firestoreService.firestoreInstance);
    _uid =
        widget.userIdOverride ?? FirebaseAuth.instance.currentUser?.uid ?? '';
    _notificationsStream = _firestoreService.streamNotifications(_uid);
    _announcementsStream =
        _firestoreService.streamSystemAnnouncements(activeOnly: true);
    _unreadSupportStream = _supportService.streamUnreadUserTickets(_uid);
    if (_uid.isNotEmpty) {
      _firestoreService.syncRecurringNotifications(_uid);
    }
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'budget':
        return Icons.warning_amber_rounded;
      case 'ai_insight':
        return Icons.auto_awesome_rounded;
      case 'recurring_due':
        return Icons.event_available_rounded;
      case 'recurring_reminder':
        return Icons.calendar_month_rounded;
      case 'recurring_failed':
        return Icons.error_outline_rounded;
      case 'recurring_success':
        return Icons.check_circle_outline_rounded;
      default:
        return Icons.notifications_outlined;
    }
  }

  Color _iconColorForType(String type) {
    switch (type) {
      case 'budget':
        return AppColors.warning;
      case 'ai_insight':
        return AppColors.primary;
      case 'recurring_due':
        return Colors.orange.shade800;
      case 'recurring_reminder':
        return AppColors.primary;
      case 'recurring_failed':
        return AppColors.expense;
      case 'recurring_success':
        return AppColors.income;
      default:
        return AppColors.secondary;
    }
  }

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final itemDate = DateTime(date.year, date.month, date.day);

    if (itemDate == today) {
      return context.tr('notif_today',
          params: {'time': DateFormat('HH:mm').format(date)});
    } else if (itemDate == today.subtract(const Duration(days: 1))) {
      return context.tr('notif_yesterday',
          params: {'time': DateFormat('HH:mm').format(date)});
    } else {
      return DateFormat('dd/MM/yyyy HH:mm').format(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          context.tr('notif_title'),
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            color: context.appTextPrimary,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all_rounded, size: 22),
            tooltip: context.tr('notif_mark_all_tooltip'),
            onPressed: () async {
              await Future.wait([
                _firestoreService.markAllNotificationsRead(_uid),
                _supportService.markAllUserTicketsRead(_uid),
              ]);
              if (context.mounted) {
                AppSnackbar.show(context, context.tr('notif_mark_all_done'));
              }
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, size: 22),
            onSelected: (val) async {
              if (val == 'clear_all') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(ctx.tr('notif_clear_dlg_title')),
                    content: Text(ctx.tr('notif_clear_dlg_body')),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: Text(ctx.tr('common_cancel')),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        style: FilledButton.styleFrom(
                            backgroundColor: AppColors.expense),
                        child: Text(ctx.tr('notif_clear_btn')),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await _firestoreService.clearAllNotifications(_uid);
                  if (context.mounted) {
                    AppSnackbar.show(context, context.tr('notif_clear_done'));
                  }
                }
              }
            },
            itemBuilder: (menuCtx) => [
              PopupMenuItem(
                value: 'clear_all',
                child: Row(
                  children: [
                    const Icon(Icons.delete_sweep_outlined,
                        size: 18, color: AppColors.expense),
                    const SizedBox(width: 8),
                    Text(menuCtx.tr('notif_clear_menu'),
                        style: const TextStyle(color: AppColors.expense)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: StreamBuilder<List<SystemAnnouncement>>(
        stream: _announcementsStream,
        builder: (context, annSnap) {
          final announcements = annSnap.data ?? const <SystemAnnouncement>[];

          return StreamBuilder<List<SupportTicket>>(
            stream: _unreadSupportStream,
            builder: (context, supportSnap) {
              final supportTickets =
                  supportSnap.data ?? const <SupportTicket>[];

              return StreamBuilder<List<AppNotification>>(
                stream: _notificationsStream,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return StreamErrorWidget(error: snap.error.toString());
                  }
                  if (!snap.hasData &&
                      annSnap.connectionState == ConnectionState.waiting &&
                      supportSnap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final notifications = snap.data ?? [];
                  if (notifications.isEmpty &&
                      announcements.isEmpty &&
                      supportTickets.isEmpty) {
                    return AppEmptyState(
                      icon: Icons.notifications_off_outlined,
                      title: context.tr('notif_empty_title'),
                      subtitle: context.tr('notif_empty_sub'),
                    );
                  }

                  final totalItems = announcements.length +
                      supportTickets.length +
                      notifications.length;

                  return ListView.separated(
                    key: const PageStorageKey('notifications_list_view'),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    itemCount: totalItems,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      // 1. Hiển thị Thông báo Hệ thống từ Admin lên đầu
                      if (i < announcements.length) {
                        final a = announcements[i];
                        return AppCard(
                          padding: const EdgeInsets.all(16),
                          color: AppColors.primary.withValues(alpha: 0.06),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.primary.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.campaign_rounded,
                                  color: AppColors.primary,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary,
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            context.tr('notif_system_badge'),
                                            style: const TextStyle(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            a.title,
                                            style: GoogleFonts.inter(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: context.appTextPrimary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      a.content,
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        color: context.appTextSecondary,
                                        height: 1.4,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _formatTime(a.createdAt),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: context.appTextSecondary
                                            .withValues(alpha: 0.8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      // 2. Hiển thị cập nhật mới từ Trung tâm Tư vấn & Hỗ trợ (chạm mở đúng ticket)
                      final supportIdx = i - announcements.length;
                      if (supportIdx < supportTickets.length) {
                        final ticket = supportTickets[supportIdx];
                        final IconData supportIcon;
                        final String supportTitleKey;
                        final String supportActionKey;
                        switch (ticket.status) {
                          case SupportTicketStatus.resolved:
                            supportIcon = Icons.task_alt_rounded;
                            supportTitleKey = 'support_notif_resolved_title';
                            supportActionKey = 'support_notif_action_rate';
                            break;
                          case SupportTicketStatus.waitingForUser:
                            supportIcon = Icons.pending_actions_rounded;
                            supportTitleKey = 'support_notif_waiting_title';
                            supportActionKey = 'support_notif_action_reply';
                            break;
                          case SupportTicketStatus.inProgress:
                            supportIcon = Icons.assignment_ind_outlined;
                            supportTitleKey = 'support_notif_in_progress_title';
                            supportActionKey = 'support_notif_action_view';
                            break;
                          case SupportTicketStatus.closed:
                            supportIcon = Icons.lock_outline_rounded;
                            supportTitleKey = 'support_notif_closed_title';
                            supportActionKey = 'support_notif_action_view';
                            break;
                          default:
                            supportIcon = Icons.support_agent_rounded;
                            supportTitleKey = 'support_notif_reply_title';
                            supportActionKey = 'support_notif_open_action';
                        }

                        return AppCard(
                          key: ValueKey(
                            'notif_support_ticket_${ticket.ticketId}',
                          ),
                          padding: const EdgeInsets.all(16),
                          color: AppColors.primary.withValues(alpha: 0.05),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => SupportTicketDetailScreen(
                                  ticketId: ticket.ticketId,
                                  supportService: _supportService,
                                  userIdOverride: widget.userIdOverride,
                                ),
                              ),
                            );
                          },
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: ticket.status.backgroundColor,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  supportIcon,
                                  color: ticket.status.color,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: ticket.status.color,
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            context.tr(
                                              'support_notif_section_badge',
                                            ),
                                            style: const TextStyle(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            context.tr(
                                              supportTitleKey,
                                              params: {
                                                'code': ticket.ticketCode,
                                              },
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.inter(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: context.appTextPrimary,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: const BoxDecoration(
                                            color: AppColors.expense,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      ticket.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: context.appTextPrimary,
                                      ),
                                    ),
                                    if (ticket
                                        .lastMessagePreview.isNotEmpty) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        ticket.lastMessagePreview,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.inter(
                                          fontSize: 12.5,
                                          color: context.appTextSecondary,
                                          height: 1.35,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          _formatTime(
                                              ticket.updatedAt.toLocal()),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: context.appTextSecondary
                                                .withValues(alpha: 0.8),
                                          ),
                                        ),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              context.tr(supportActionKey),
                                              style: const TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w600,
                                                color: AppColors.primary,
                                              ),
                                            ),
                                            const Icon(
                                              Icons.chevron_right_rounded,
                                              size: 14,
                                              color: AppColors.primary,
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

                      // 3. Thông báo cá nhân khác
                      final n = notifications[
                          i - announcements.length - supportTickets.length];
                      final isUnread = n.isUnread;
                      final color = _iconColorForType(n.type);

                      return AppCard(
                        padding: const EdgeInsets.all(16),
                        color: isUnread
                            ? AppColors.primary.withValues(alpha: 0.04)
                            : context.appCard,
                        onTap: () async {
                          if (isUnread) {
                            await _firestoreService
                                .markNotificationRead(n.notificationId);
                          }

                          if (!context.mounted) return;

                          if (n.scheduleId != null &&
                              n.scheduleId!.isNotEmpty) {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => RecurringTransactionScreen(
                                  targetScheduleId: n.scheduleId,
                                ),
                              ),
                            );
                          } else if (n.type == 'budget') {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const BudgetManagementScreen(),
                              ),
                            );
                          }
                        },
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                _iconForType(n.type),
                                color: color,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          NotificationLocalizationHelper
                                              .localizeTitleWithContext(
                                                  context, n),
                                          style: GoogleFonts.inter(
                                            fontSize: 14,
                                            fontWeight: isUnread
                                                ? FontWeight.w700
                                                : FontWeight.w600,
                                            color: context.appTextPrimary,
                                          ),
                                        ),
                                      ),
                                      if (isUnread) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: const BoxDecoration(
                                            color: AppColors.expense,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    NotificationLocalizationHelper
                                        .localizeContentWithContext(context, n),
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      color: context.appTextSecondary,
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          _formatTime(n.createdAt),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: context.appTextSecondary
                                                .withValues(alpha: 0.8),
                                          ),
                                        ),
                                      ),
                                      if (n.scheduleId != null &&
                                          n.scheduleId!.isNotEmpty) ...[
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  context.tr(
                                                      'notif_view_schedule'),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: AppColors.primary,
                                                  ),
                                                ),
                                              ),
                                              const Icon(
                                                Icons.chevron_right_rounded,
                                                size: 14,
                                                color: AppColors.primary,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
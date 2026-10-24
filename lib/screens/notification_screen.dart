import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/notification_model.dart';
import '../services/firestore_service.dart';
import '../utils/constants.dart';
import '../widgets/app_card.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/stream_error_widget.dart';

/// 20. Notification - Danh sách thông báo (vượt ngân sách, nhắc hóa đơn, AI Insight)
class NotificationScreen extends StatelessWidget {
  const NotificationScreen({super.key});

  IconData _iconForType(String type) {
    switch (type) {
      case 'budget':
        return Icons.warning_amber_rounded;
      case 'ai_insight':
        return Icons.auto_awesome_rounded;
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
      default:
        return AppColors.secondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final firestoreService = FirestoreService();

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Thông báo',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            color: context.appTextPrimary,
          ),
        ),
      ),
      body: StreamBuilder<List<AppNotification>>(
        stream: firestoreService.streamNotifications(uid),
        builder: (context, snap) {
          if (snap.hasError)
            return StreamErrorWidget(error: snap.error.toString());
          if (!snap.hasData)
            return const Center(child: CircularProgressIndicator());

          final notifications = snap.data ?? [];
          if (notifications.isEmpty) {
            return const AppEmptyState(
              icon: Icons.notifications_off_outlined,
              title: 'Không có thông báo',
              subtitle: 'Bạn chưa có thông báo mới nào từ hệ thống.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: notifications.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final n = notifications[i];
              final isUnread = n.status == 'unread';

              return AppCard(
                padding: const EdgeInsets.all(16),
                color: isUnread
                    ? AppColors.primary.withValues(alpha: 0.04)
                    : context.appCard,
                onTap: () =>
                    firestoreService.markNotificationRead(n.notificationId),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color:
                            _iconColorForType(n.type).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(_iconForType(n.type),
                          color: _iconColorForType(n.type), size: 22),
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
                                  n.title,
                                  style: GoogleFonts.inter(
                                    fontSize: 15,
                                    fontWeight: isUnread
                                        ? FontWeight.w600
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
                            n.content,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: context.appTextSecondary,
                              height: 1.4,
                            ),
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
      ),
    );
  }
}

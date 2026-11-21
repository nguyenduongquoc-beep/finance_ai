import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../l10n/app_localizations.dart';
import '../../models/support_ticket_model.dart';
import '../../services/support_service.dart';
import '../../utils/constants.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/stream_error_widget.dart';
import 'create_support_ticket_screen.dart';
import 'support_ticket_detail_screen.dart';

/// Màn hình Danh sách Yêu cầu - Trung tâm Tư vấn & Hỗ trợ Người dùng (User App)
class SupportCenterScreen extends StatefulWidget {
  final SupportService? supportService;
  final String? userIdOverride;
  final String? userNameOverride;
  final String? userEmailOverride;

  const SupportCenterScreen({
    super.key,
    this.supportService,
    this.userIdOverride,
    this.userNameOverride,
    this.userEmailOverride,
  });

  @override
  State<SupportCenterScreen> createState() => _SupportCenterScreenState();
}

class _SupportCenterScreenState extends State<SupportCenterScreen> {
  static const int _pageSize = 25;

  late final SupportService _supportService;
  late final String _uid;
  int _limit = _pageSize;
  String _filter = 'all'; // 'all' | 'active' | 'action_needed' | 'done'
  late Stream<List<SupportTicket>> _ticketsStream;

  @override
  void initState() {
    super.initState();
    _supportService = widget.supportService ?? SupportService();
    _uid = widget.userIdOverride ?? FirebaseAuth.instance.currentUser?.uid ?? '';
    _ticketsStream = _supportService.streamUserTickets(_uid, limit: _limit);
  }

  void _loadMore() {
    setState(() {
      _limit += _pageSize;
      _ticketsStream = _supportService.streamUserTickets(_uid, limit: _limit);
    });
  }

  void _retryStream() {
    setState(() {
      _ticketsStream = _supportService.streamUserTickets(_uid, limit: _limit);
    });
  }

  Future<void> _openCreateTicket() async {
    final created = await Navigator.of(context).push<SupportTicket>(
      MaterialPageRoute(
        builder: (_) => CreateSupportTicketScreen(
          supportService: _supportService,
          userIdOverride: widget.userIdOverride,
          userNameOverride: widget.userNameOverride,
          userEmailOverride: widget.userEmailOverride,
        ),
      ),
    );
    if (created != null && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SupportTicketDetailScreen(
            ticketId: created.ticketId,
            supportService: _supportService,
            userIdOverride: widget.userIdOverride,
            userNameOverride: widget.userNameOverride,
          ),
        ),
      );
    }
  }

  bool _matchesFilter(SupportTicket t, String filter) {
    switch (filter) {
      case 'active':
        return t.status == SupportTicketStatus.newTicket ||
            t.status == SupportTicketStatus.inProgress;
      case 'action_needed':
        return t.status == SupportTicketStatus.waitingForUser ||
            t.status == SupportTicketStatus.replied;
      case 'done':
        return t.status.isCompleted;
      default:
        return true;
    }
  }

  List<SupportTicket> _applyFilter(List<SupportTicket> tickets) {
    if (_filter == 'all') return tickets;
    return tickets.where((t) => _matchesFilter(t, _filter)).toList();
  }

  String _formatDateTime(DateTime date) {
    final local = date.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final itemDay = DateTime(local.year, local.month, local.day);
    if (itemDay == today) {
      return DateFormat('HH:mm').format(local);
    }
    return DateFormat('dd/MM/yyyy HH:mm').format(local);
  }

  Widget _buildFilterChip(String value, String label, int count) {
    final selected = _filter == value;
    final displayLabel = count > 0 ? '$label ($count)' : label;
    return ChoiceChip(
      key: ValueKey('support_filter_$value'),
      label: Text(displayLabel),
      selected: selected,
      onSelected: (_) => setState(() => _filter = value),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(
          context.tr('support_title'),
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            color: context.appTextPrimary,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('support_create_fab'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        onPressed: _openCreateTicket,
        icon: const Icon(Icons.add_comment_outlined, size: 20),
        label: Text(
          context.tr('support_new_ticket_btn'),
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
      ),
      body: StreamBuilder<List<SupportTicket>>(
        stream: _ticketsStream,
        builder: (context, snapshot) {
          final allTickets = snapshot.data ?? const <SupportTicket>[];
          final activeCount =
              allTickets.where((t) => _matchesFilter(t, 'active')).length;
          final actionCount = allTickets
              .where((t) => _matchesFilter(t, 'action_needed'))
              .length;
          final doneCount =
              allTickets.where((t) => _matchesFilter(t, 'done')).length;

          return Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    _buildFilterChip(
                      'all',
                      context.tr('support_filter_all'),
                      allTickets.length,
                    ),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      'active',
                      context.tr('support_filter_active'),
                      activeCount,
                    ),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      'action_needed',
                      context.tr('support_filter_action_needed'),
                      actionCount,
                    ),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      'done',
                      context.tr('support_filter_done'),
                      doneCount,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _buildListBody(context, snapshot, allTickets),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildListBody(
    BuildContext context,
    AsyncSnapshot<List<SupportTicket>> snapshot,
    List<SupportTicket> allTickets,
  ) {
    if (snapshot.hasError) {
      return StreamErrorWidget(
        error: snapshot.error.toString(),
        onRetry: _retryStream,
      );
    }
    if (snapshot.connectionState == ConnectionState.waiting &&
        !snapshot.hasData) {
      return const Center(child: CircularProgressIndicator());
    }

    if (allTickets.isEmpty) {
      return AppEmptyState(
        icon: Icons.support_agent_rounded,
        title: context.tr('support_empty_title'),
        subtitle: context.tr('support_empty_sub'),
        actionText: context.tr('support_new_ticket_btn'),
        onAction: _openCreateTicket,
      );
    }

    final filtered = _applyFilter(allTickets);
    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            context.tr('support_filter_empty'),
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: context.appTextSecondary,
            ),
          ),
        ),
      );
    }

    final canLoadMore = allTickets.length >= _limit;

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 92),
      itemCount: filtered.length + (canLoadMore ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == filtered.length) {
          return Center(
            child: OutlinedButton(
              onPressed: _loadMore,
              child: Text(context.tr('support_load_more')),
            ),
          );
        }
        final ticket = filtered[index];
        return _buildTicketCard(context, ticket);
      },
    );
  }

  Widget _buildTicketCard(BuildContext context, SupportTicket ticket) {
    final statusLabel = ticket.isClosed
        ? (ticket.isClosedUnresolved
            ? context.tr('support_closed_unresolved_tag')
            : context.tr('support_closed_resolved_tag'))
        : ticket.status.localizedLabel(context);

    return AppCard(
      key: ValueKey('user_ticket_card_${ticket.ticketId}'),
      padding: const EdgeInsets.all(14),
      color: ticket.unreadByUser
          ? AppColors.primary.withValues(alpha: 0.04)
          : context.appCard,
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SupportTicketDetailScreen(
              ticketId: ticket.ticketId,
              supportService: _supportService,
              userIdOverride: widget.userIdOverride,
              userNameOverride: widget.userNameOverride,
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ticket.category.icon,
                size: 16,
                color: ticket.category.accentColor,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${ticket.ticketCode} · ${ticket.category.localizedLabel(context)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: context.appTextSecondary,
                  ),
                ),
              ),
              if (ticket.unreadByUser) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.expense,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    context.tr('support_unread_badge'),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            ticket.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight:
                  ticket.unreadByUser ? FontWeight.w700 : FontWeight.w600,
              color: context.appTextPrimary,
            ),
          ),
          if (ticket.lastMessagePreview.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              ticket.lastMessagePreview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: context.appTextSecondary,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: ticket.status.backgroundColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        statusLabel,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: ticket.status.color,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: ticket.priority.backgroundColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        ticket.priority.localizedLabel(context),
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: ticket.priority.color,
                        ),
                      ),
                    ),
                    if (ticket.hasRating)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.warningBackground,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          context.tr(
                            'support_card_rated_badge',
                            params: {'score': '${ticket.ratingScore}'},
                          ),
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.warning,
                          ),
                        ),
                      )
                    else if (ticket.isResolved)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.infoBackground,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          context.tr('support_card_awaiting_rating'),
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatDateTime(ticket.updatedAt),
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  color: context.appTextSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

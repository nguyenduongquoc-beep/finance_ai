import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../l10n/app_localizations.dart';
import '../../models/support_ticket_model.dart';
import '../../services/support_service.dart';
import '../../utils/constants.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/stream_error_widget.dart';
import 'create_support_ticket_screen.dart';

/// Màn hình Chi tiết Yêu cầu & Hội thoại riêng theo từng Ticket (User App)
class SupportTicketDetailScreen extends StatefulWidget {
  final String ticketId;
  final SupportService? supportService;
  final String? userIdOverride;
  final String? userNameOverride;

  const SupportTicketDetailScreen({
    super.key,
    required this.ticketId,
    this.supportService,
    this.userIdOverride,
    this.userNameOverride,
  });

  @override
  State<SupportTicketDetailScreen> createState() =>
      _SupportTicketDetailScreenState();
}

class _SupportTicketDetailScreenState extends State<SupportTicketDetailScreen> {
  final _msgCtrl = TextEditingController();
  final _ratingCommentCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  late final SupportService _supportService;
  late Stream<SupportTicket?> _ticketStream;
  late Stream<List<SupportMessage>> _messagesStream;

  bool _isSending = false;
  bool _isConfirmingResolved = false;
  bool _isSubmittingRating = false;
  bool _isMarkingRead = false;
  bool _isEditingRating = false;
  int _selectedRatingScore = 0;

  @override
  void initState() {
    super.initState();
    _supportService = widget.supportService ?? SupportService();
    _ticketStream = _supportService.streamTicketById(widget.ticketId);
    _messagesStream = _supportService.streamTicketMessages(widget.ticketId);
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _ratingCommentCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  String _resolvedUid(SupportTicket ticket) {
    return widget.userIdOverride ??
        FirebaseAuth.instance.currentUser?.uid ??
        ticket.userId;
  }

  Future<void> _markReadIfNeeded(SupportTicket ticket) async {
    if (!ticket.unreadByUser || _isMarkingRead) return;
    _isMarkingRead = true;
    try {
      await _supportService.markTicketReadByUser(ticket.ticketId);
    } catch (_) {
      // Không làm gián đoạn hiển thị nếu mất mạng tạm thời
    } finally {
      _isMarkingRead = false;
    }
  }

  Future<void> _sendMessage(SupportTicket ticket) async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _isSending || ticket.isClosed) return;

    setState(() => _isSending = true);
    try {
      await _supportService.sendUserMessage(
        ticket: ticket,
        body: text,
        userIdOverride: _resolvedUid(ticket),
        userNameOverride: widget.userNameOverride ?? ticket.userName,
      );
      if (!mounted) return;
      _msgCtrl.clear();
      if (_isEditingRating) {
        setState(() => _isEditingRating = false);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent + 80,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.show(
        context,
        e is SupportServiceException
            ? e.message
            : context.tr('support_detail_send_error'),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _confirmResolved(SupportTicket ticket) async {
    if (_isConfirmingResolved || !ticket.canUserConfirmResolved) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('support_detail_confirm_resolved_title')),
        content: Text(context.tr('support_detail_confirm_resolved_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.tr('common_cancel')),
          ),
          FilledButton(
            key: const ValueKey('support_confirm_resolved_dialog_ok'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.income),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.tr('common_confirm')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isConfirmingResolved = true);
    try {
      await _supportService.confirmResolvedByUser(
        ticket: ticket,
        userIdOverride: _resolvedUid(ticket),
        userNameOverride: widget.userNameOverride ?? ticket.userName,
      );
      if (!mounted) return;
      AppSnackbar.show(
        context,
        context.tr('support_detail_confirm_resolved_success'),
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.show(
        context,
        e is SupportServiceException
            ? e.message
            : context.tr('support_detail_send_error'),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isConfirmingResolved = false);
      }
    }
  }

  Future<void> _submitRating(SupportTicket ticket) async {
    if (_isSubmittingRating || !ticket.isResolved) return;
    if (_selectedRatingScore < 1 || _selectedRatingScore > 5) {
      AppSnackbar.show(
        context,
        context.tr('support_rating_err_select'),
        isError: true,
      );
      return;
    }

    final isEdit = ticket.hasRating;
    FocusScope.of(context).unfocus();
    setState(() => _isSubmittingRating = true);
    try {
      await _supportService.submitOrUpdateRating(
        ticket: ticket,
        score: _selectedRatingScore,
        comment: _ratingCommentCtrl.text,
        userIdOverride: _resolvedUid(ticket),
      );
      if (!mounted) return;
      setState(() {
        _isEditingRating = false;
        _selectedRatingScore = 0;
        _ratingCommentCtrl.clear();
      });
      AppSnackbar.show(
        context,
        isEdit
            ? context.tr('support_rating_update_success')
            : context.tr('support_rating_submit_success'),
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.show(
        context,
        e is SupportServiceException
            ? e.message
            : context.tr('support_detail_send_error'),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmittingRating = false);
      }
    }
  }

  Future<void> _openCreateRelatedTicket(SupportTicket closedTicket) async {
    final created = await Navigator.of(context).push<SupportTicket>(
      MaterialPageRoute(
        builder: (_) => CreateSupportTicketScreen(
          supportService: _supportService,
          relatedTicket: closedTicket,
          userIdOverride: widget.userIdOverride,
          userNameOverride: widget.userNameOverride,
          userEmailOverride: closedTicket.userEmail,
        ),
      ),
    );
    if (created != null && mounted) {
      Navigator.of(context).pushReplacement(
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

  String _formatTime(DateTime dt) {
    return DateFormat('dd/MM HH:mm').format(dt.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SupportTicket?>(
      stream: _ticketStream,
      builder: (context, ticketSnap) {
        if (ticketSnap.hasError) {
          return Scaffold(
            appBar: AppBar(title: Text(context.tr('support_detail_title'))),
            body: StreamErrorWidget(
              error: ticketSnap.error.toString(),
              onRetry: () {
                setState(() {
                  _ticketStream =
                      _supportService.streamTicketById(widget.ticketId);
                  _messagesStream =
                      _supportService.streamTicketMessages(widget.ticketId);
                });
              },
            ),
          );
        }

        if (ticketSnap.connectionState == ConnectionState.waiting &&
            !ticketSnap.hasData) {
          return Scaffold(
            appBar: AppBar(title: Text(context.tr('support_detail_title'))),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final ticket = ticketSnap.data;
        if (ticket == null) {
          return Scaffold(
            appBar: AppBar(title: Text(context.tr('support_detail_title'))),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  context.tr('support_detail_not_found'),
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: context.appTextSecondary,
                  ),
                ),
              ),
            ),
          );
        }

        if (ticket.unreadByUser) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _markReadIfNeeded(ticket);
          });
        }

        if (!ticket.isResolved && _isEditingRating) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _isEditingRating = false);
          });
        }

        final statusLabel = ticket.isClosed
            ? (ticket.isClosedUnresolved
                ? context.tr('support_closed_unresolved_tag')
                : context.tr('support_closed_resolved_tag'))
            : ticket.status.localizedLabel(context);

        return Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ticket.ticketCode,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: context.appTextPrimary,
                  ),
                ),
                Text(
                  ticket.category.localizedLabel(context),
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    color: context.appTextSecondary,
                  ),
                ),
              ],
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: ticket.status.backgroundColor,
                      borderRadius: BorderRadius.circular(8),
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
                ),
              ),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              Widget buildMessageArea() {
                return StreamBuilder<List<SupportMessage>>(
                  stream: _messagesStream,
                  builder: (context, msgSnap) {
                    if (msgSnap.hasError) {
                      return StreamErrorWidget(
                        error: msgSnap.error.toString(),
                      );
                    }
                    if (msgSnap.connectionState == ConnectionState.waiting &&
                        !msgSnap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final messages = msgSnap.data ?? const <SupportMessage>[];
                    final hasUserTextMsg = messages.any(
                      (m) =>
                          m.senderRole == SupportSenderRole.user &&
                          m.messageType == SupportMessageType.text,
                    );
                    final contextCards =
                        _buildTicketContextCards(context, ticket);
                    final topBanners = _buildContextualBanners(context, ticket);
                    final ratingSection = _buildRatingSection(context, ticket);

                    return ListView(
                      controller: _scrollCtrl,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      children: [
                        ...contextCards,
                        ...topBanners,
                        if (!hasUserTextMsg &&
                            ticket.description.trim().isNotEmpty) ...[
                          _buildMessageBubble(
                            context,
                            SupportMessage(
                              messageId: 'initial_desc_${ticket.ticketId}',
                              senderId: ticket.userId,
                              senderRole: SupportSenderRole.user,
                              senderDisplayName: ticket.userName,
                              body: ticket.description,
                              messageType: SupportMessageType.text,
                              createdAt: ticket.createdAt,
                            ),
                          ),
                          if (messages.isNotEmpty) const SizedBox(height: 10),
                        ],
                        for (int i = 0; i < messages.length; i++) ...[
                          _buildMessageBubble(context, messages[i]),
                          if (i < messages.length - 1)
                            const SizedBox(height: 10),
                        ],
                        if (ratingSection != null) ...[
                          const SizedBox(height: 16),
                          ratingSection,
                        ],
                      ],
                    );
                  },
                );
              }

              if (constraints.maxHeight < 220) {
                return SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildTicketSummaryHeader(context, ticket),
                      SizedBox(
                        height: 180,
                        child: buildMessageArea(),
                      ),
                      _buildBottomComposerOrClosedBanner(context, ticket),
                    ],
                  ),
                );
              }

              return Column(
                children: [
                  _buildTicketSummaryHeader(context, ticket),
                  Expanded(child: buildMessageArea()),
                  _buildBottomComposerOrClosedBanner(context, ticket),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildTicketSummaryHeader(BuildContext context, SupportTicket ticket) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: context.appCard,
        border: Border(bottom: BorderSide(color: context.appBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ticket.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: context.appTextPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                key: const ValueKey('support_detail_priority_badge'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: ticket.priority.backgroundColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      ticket.priority.icon,
                      size: 13,
                      color: ticket.priority.color,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${context.tr('support_priority_label')}: ${ticket.priority.localizedLabel(context)}',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: ticket.priority.color,
                      ),
                    ),
                  ],
                ),
              ),
              if (ticket.hasRelatedTicket)
                InkWell(
                  key: const ValueKey('support_detail_related_chip'),
                  borderRadius: BorderRadius.circular(6),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SupportTicketDetailScreen(
                          ticketId: ticket.relatedTicketId!,
                          supportService: _supportService,
                          userIdOverride: widget.userIdOverride,
                          userNameOverride: widget.userNameOverride,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.infoBackground,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.link_rounded,
                          size: 13,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          context.tr(
                            'support_related_chip',
                            params: {'code': ticket.relatedTicketCode!},
                          ),
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (ticket.canUserConfirmResolved)
                OutlinedButton.icon(
                  key: const ValueKey('support_user_confirm_resolved_btn'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.income,
                    side: BorderSide(
                      color: AppColors.income.withValues(alpha: 0.5),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    minimumSize: const Size(0, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: _isConfirmingResolved
                      ? null
                      : () => _confirmResolved(ticket),
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 15),
                  label: Text(
                    context.tr('support_detail_confirm_resolved_btn'),
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTicketContextCards(
    BuildContext context,
    SupportTicket ticket,
  ) {
    final cards = <Widget>[];
    if (ticket.technicalInfo != null) {
      cards.add(
        Container(
          key: const ValueKey('support_detail_tech_info'),
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: context.appInputFill,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.devices_other_rounded,
                size: 15,
                color: context.appTextSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${context.tr('support_tech_info_attached')}: ${ticket.technicalInfo!.summaryLine}',
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    color: context.appTextSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (ticket.sharedContext != null && ticket.sharedContext!.isNotEmpty) {
      cards.add(
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.infoBackground,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('support_detail_shared_ctx'),
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                ticket.sharedContext!,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppColors.slate700,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return cards;
  }

  List<Widget> _buildContextualBanners(
    BuildContext context,
    SupportTicket ticket,
  ) {
    final banners = <Widget>[];
    if (ticket.status == SupportTicketStatus.waitingForUser) {
      banners.add(
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.warningBackground,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppColors.warning.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.pending_actions_rounded,
                size: 18,
                color: AppColors.warning,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.tr('support_detail_waiting_banner'),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.slate700,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } else if (ticket.isResolved) {
      banners.add(
        Container(
          key: const ValueKey('support_detail_resolved_banner'),
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.incomeBackground,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppColors.income.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.task_alt_rounded,
                size: 18,
                color: AppColors.income,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.tr('support_detail_resolved_banner'),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.slate700,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return banners;
  }

  Widget? _buildRatingSection(BuildContext context, SupportTicket ticket) {
    // 1. Khi ticket đang `resolved` và chưa đánh giá HOẶC đang mở form chỉnh sửa 1 lần
    if (ticket.isResolved && (!ticket.hasRating || _isEditingRating)) {
      final isEdit = ticket.hasRating && _isEditingRating;
      return Container(
        key: const ValueKey('support_rating_card'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.appCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.star_outline_rounded,
                  size: 18,
                  color: AppColors.warning,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    context.tr('support_rating_title'),
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: context.appTextPrimary,
                    ),
                  ),
                ),
                if (isEdit)
                  TextButton(
                    onPressed: _isSubmittingRating
                        ? null
                        : () => setState(() => _isEditingRating = false),
                    child: Text(context.tr('common_cancel')),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              context.tr('support_rating_sub'),
              style: GoogleFonts.inter(
                fontSize: 12,
                color: context.appTextSecondary,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                final starVal = index + 1;
                final filled = starVal <= _selectedRatingScore;
                return IconButton(
                  key: ValueKey('support_rating_star_$starVal'),
                  onPressed: _isSubmittingRating
                      ? null
                      : () => setState(() => _selectedRatingScore = starVal),
                  icon: Icon(
                    filled ? Icons.star_rounded : Icons.star_border_rounded,
                    size: 32,
                    color: filled ? AppColors.warning : AppColors.slate400,
                  ),
                );
              }),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('support_rating_comment_input'),
              controller: _ratingCommentCtrl,
              maxLines: 3,
              minLines: 2,
              maxLength: SupportTicket.kMaxRatingCommentLength,
              decoration: InputDecoration(
                hintText: context.tr('support_rating_comment_hint'),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('support_rating_submit_btn'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                onPressed:
                    _isSubmittingRating ? null : () => _submitRating(ticket),
                child: _isSubmittingRating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        isEdit
                            ? context.tr('support_rating_update_btn')
                            : context.tr('support_rating_submit_btn'),
                      ),
              ),
            ),
          ],
        ),
      );
    }

    // 2. Đã có đánh giá (hiển thị chính thức khi resolved, hoặc phản hồi lịch sử chỉ đọc khi in_progress/closed)
    if (ticket.hasRating) {
      final score = ticket.ratingScore!;
      return Container(
        key: const ValueKey('support_rating_summary'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.appCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.appBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  context.tr('support_rating_official_badge'),
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: context.appTextPrimary,
                  ),
                ),
                const Spacer(),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(5, (index) {
                    final filled = (index + 1) <= score;
                    return Icon(
                      filled ? Icons.star_rounded : Icons.star_border_rounded,
                      size: 18,
                      color: filled ? AppColors.warning : AppColors.slate300,
                    );
                  }),
                ),
                const SizedBox(width: 6),
                Text(
                  '$score/5',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.warning,
                  ),
                ),
              ],
            ),
            if (ticket.ratingComment != null &&
                ticket.ratingComment!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                ticket.ratingComment!,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: context.appTextPrimary,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 8),
            if (ticket.canUserEditRating)
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  key: const ValueKey('support_rating_edit_btn'),
                  onPressed: () {
                    setState(() {
                      _selectedRatingScore = score;
                      _ratingCommentCtrl.text = ticket.ratingComment ?? '';
                      _isEditingRating = true;
                    });
                  },
                  icon: const Icon(Icons.edit_outlined, size: 15),
                  label: Text(
                    context.tr('support_rating_edit_btn'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              )
            else if (ticket.isClosed)
              Text(
                context.tr('support_rating_closed_locked'),
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  color: context.appTextSecondary,
                ),
              )
            else if (!ticket.isResolved)
              Text(
                context.tr('support_rating_history_note'),
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  color: context.appTextSecondary,
                  height: 1.35,
                ),
              )
            else
              Text(
                context.tr('support_rating_edit_used'),
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  color: context.appTextSecondary,
                ),
              ),
          ],
        ),
      );
    }

    return null;
  }

  Widget _buildMessageBubble(BuildContext context, SupportMessage msg) {
    if (msg.senderRole == SupportSenderRole.system ||
        msg.messageType == SupportMessageType.statusChange) {
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.slate100,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.slate200),
          ),
          child: Text(
            '${msg.body} · ${_formatTime(msg.createdAt)}',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              color: AppColors.slate600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    }

    final isUser = msg.senderRole == SupportSenderRole.user;
    final isRequestInfo = msg.messageType == SupportMessageType.requestInfo;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isUser
                ? AppColors.primary
                : (isRequestInfo
                    ? AppColors.warningBackground
                    : context.appCard),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(isUser ? 14 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 14),
            ),
            border: isUser
                ? null
                : Border.all(
                    color: isRequestInfo
                        ? AppColors.warning.withValues(alpha: 0.45)
                        : context.appBorder,
                  ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isUser
                        ? context.tr('support_detail_sender_you')
                        : (msg.senderDisplayName.isNotEmpty
                            ? msg.senderDisplayName
                            : context.tr('support_detail_sender_admin')),
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: isUser
                          ? Colors.white.withValues(alpha: 0.9)
                          : AppColors.primary,
                    ),
                  ),
                  if (isRequestInfo) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.warning,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        context.tr('support_detail_req_info_tag'),
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Text(
                msg.body,
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  height: 1.45,
                  color: isUser ? Colors.white : context.appTextPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _formatTime(msg.createdAt),
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  color: isUser
                      ? Colors.white.withValues(alpha: 0.78)
                      : context.appTextSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomComposerOrClosedBanner(
    BuildContext context,
    SupportTicket ticket,
  ) {
    if (ticket.isClosed) {
      final bannerText = ticket.isClosedUnresolved
          ? context.tr('support_detail_closed_unresolved_banner')
          : context.tr('support_detail_closed_banner');
      return SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          decoration: BoxDecoration(
            color: context.appCard,
            border: Border(top: BorderSide(color: context.appBorder)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                bannerText,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  color: context.appTextSecondary,
                  height: 1.35,
                ),
              ),
              if (ticket.isClosedUnresolved && ticket.closeReason != null) ...[
                const SizedBox(height: 4),
                Text(
                  ticket.closeReason!.localizedLabel(context),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.appTextPrimary,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const ValueKey('support_closed_new_ticket_btn'),
                onPressed: () => _openCreateRelatedTicket(ticket),
                icon: const Icon(Icons.add_comment_outlined, size: 18),
                label: Text(
                  context.tr(
                    'support_detail_create_new_ref',
                    params: {'code': ticket.ticketCode},
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: BoxDecoration(
          color: context.appCard,
          border: Border(top: BorderSide(color: context.appBorder)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('support_user_message_input'),
                controller: _msgCtrl,
                minLines: 1,
                maxLines: 4,
                maxLength: SupportTicket.kMaxMessageLength,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: context.tr('support_detail_input_hint'),
                  counterText: '',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 46,
              width: 46,
              child: FilledButton(
                key: const ValueKey('support_user_send_btn'),
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.zero,
                  backgroundColor: AppColors.primary,
                ),
                onPressed: _isSending ? null : () => _sendMessage(ticket),
                child: _isSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

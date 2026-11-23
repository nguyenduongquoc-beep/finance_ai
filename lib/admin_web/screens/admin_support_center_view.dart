import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../models/support_ticket_model.dart';
import '../../services/support_service.dart';
import '../../utils/constants.dart';
import '../../widgets/app_snackbar.dart';
import '../widgets/admin_governance_widgets.dart';

/// 3 trạng thái hiển thị gọn nhẹ trên Cổng Quản trị Web.
/// Ánh xạ an toàn mọi trạng thái chi tiết/cũ từ Firestore để không vỡ dữ liệu cũ:
/// - `new` -> Mới
/// - `in_progress`, `replied`, `waiting_for_user` -> Đang xử lý
/// - `resolved`, `closed` (gồm cả dữ liệu cũ `closed_unresolved`) -> Đã giải quyết
enum _AdminSupportStage {
  newTicket('new', 'Mới', Color(0xFF0284C7), Color(0xFFE0F2FE)),
  inProgress(
    'in_progress',
    'Đang xử lý',
    AppColors.primary,
    AppColors.infoBackground,
  ),
  resolved(
    'resolved',
    'Đã giải quyết',
    AppColors.income,
    AppColors.incomeBackground,
  );

  final String code;
  final String label;
  final Color color;
  final Color backgroundColor;

  const _AdminSupportStage(
    this.code,
    this.label,
    this.color,
    this.backgroundColor,
  );

  static _AdminSupportStage fromTicketStatus(SupportTicketStatus status) {
    switch (status) {
      case SupportTicketStatus.newTicket:
        return _AdminSupportStage.newTicket;
      case SupportTicketStatus.inProgress:
      case SupportTicketStatus.replied:
      case SupportTicketStatus.waitingForUser:
        return _AdminSupportStage.inProgress;
      case SupportTicketStatus.resolved:
      case SupportTicketStatus.closed:
        return _AdminSupportStage.resolved;
    }
  }
}

/// Bộ mẫu trả lời nhanh tĩnh cho Helpdesk (0 lượt đọc Firestore, không CRUD phức tạp).
/// Khi bấm chỉ điền vào ô nhập tin nhắn để Admin kiểm tra/chỉnh sửa trước khi gửi.
class _QuickReplyPreset {
  final String id;
  final String label;
  final String content;

  const _QuickReplyPreset({
    required this.id,
    required this.label,
    required this.content,
  });

  static const List<_QuickReplyPreset> defaults = [
    _QuickReplyPreset(
      id: 'ack',
      label: 'Tiếp nhận',
      content:
          'Chào bạn, đội ngũ hỗ trợ Finance AI đã tiếp nhận yêu cầu và đang kiểm tra giúp bạn.',
    ),
    _QuickReplyPreset(
      id: 'ask_info',
      label: 'Hỏi thêm thông tin',
      content:
          'Bạn vui lòng mô tả rõ hơn thao tác gặp lỗi hoặc thời điểm phát sinh để mình hỗ trợ nhanh hơn nhé.',
    ),
    _QuickReplyPreset(
      id: 'ocr_guide',
      label: 'Hướng dẫn OCR',
      content:
          'Với tính năng quét hóa đơn OCR, bạn lưu ý chụp ở nơi đủ sáng và giữ hóa đơn phẳng để hệ thống nhận diện chính xác nhất.',
    ),
    _QuickReplyPreset(
      id: 'wallet_budget',
      label: 'Ví & Ngân sách',
      content:
          'Bạn có thể kiểm tra lại ví nguồn và hạn mức ngân sách tháng trong mục Quản lý; mọi thay đổi giao dịch sẽ tự động cập nhật số dư ví và tiến độ ngân sách.',
    ),
    _QuickReplyPreset(
      id: 'account_sync',
      label: 'Đăng nhập & Đồng bộ',
      content:
          'Nếu gặp sự cố đăng nhập hoặc dữ liệu chưa cập nhật, bạn hãy kiểm tra kết nối mạng, kéo xuống để làm mới dữ liệu hoặc đăng xuất và đăng nhập lại đúng email đã đăng ký nhé.',
    ),
    _QuickReplyPreset(
      id: 'confirm_done',
      label: 'Xác nhận xong',
      content:
          'Vấn đề của bạn đã được xử lý xong. Nếu không còn vướng mắc nào khác, mình xin phép đánh dấu yêu cầu này là Đã giải quyết nhé.',
    ),
  ];
}

/// Màn hình Trung tâm Hỗ trợ CSKH gọn nhẹ trên Admin Web Portal (Firebase Spark).
/// - Đọc/ghi trực tiếp qua Cloud Firestore + Firestore Security Rules (`isAdmin()`).
/// - Tìm kiếm theo mã vé / tiêu đề / người dùng và lọc theo 3 trạng thái chuẩn.
/// - Chat 2 chiều Realtime trên `support_tickets/{id}/messages` và cập nhật trạng thái xử lý.
class AdminSupportCenterView extends StatefulWidget {
  final SupportService supportService;
  final String currentAdminUid;
  final String currentAdminName;
  final String? initialTicketId;
  final VoidCallback? onInitialTicketHandled;

  const AdminSupportCenterView({
    super.key,
    required this.supportService,
    required this.currentAdminUid,
    required this.currentAdminName,
    this.initialTicketId,
    this.onInitialTicketHandled,
  });

  @override
  State<AdminSupportCenterView> createState() => _AdminSupportCenterViewState();
}

class _AdminSupportCenterViewState extends State<AdminSupportCenterView> {
  static const int _pageSize = 30;

  final _searchCtrl = TextEditingController();
  final _replyCtrl = TextEditingController();
  final _replyFocusNode = FocusNode();
  final _msgScrollCtrl = ScrollController();

  int _limit = _pageSize;
  String _searchQuery = '';
  _AdminSupportStage? _stageFilter;

  late Stream<List<SupportTicket>> _ticketsStream;
  String? _selectedTicketId;
  Stream<SupportTicket?>? _selectedTicketStream;
  Stream<List<SupportMessage>>? _selectedMessagesStream;

  // Lưu bộ đếm từ luồng đầy đủ để giữ nhãn ổn định khi đang lọc phía server cho nhóm "Mới"
  bool _hasCachedUnfilteredCounts = false;
  int _cachedAllCount = 0;
  int _cachedInProgressCount = 0;
  int _cachedResolvedCount = 0;

  bool _isSubmitting = false;
  String? _markingReadTicketId;

  @override
  void initState() {
    super.initState();
    _ticketsStream = _buildTicketsStream();
    final initialId = widget.initialTicketId?.trim();
    if (initialId != null && initialId.isNotEmpty) {
      _applyInitialTicketSelection(initialId);
    }
  }

  @override
  void didUpdateWidget(covariant AdminSupportCenterView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextId = widget.initialTicketId?.trim();
    if (nextId != null &&
        nextId.isNotEmpty &&
        nextId != oldWidget.initialTicketId?.trim()) {
      _applyInitialTicketSelection(nextId);
    }
  }

  void _applyInitialTicketSelection(String ticketId) {
    _selectedTicketId = ticketId;
    _selectedTicketStream = widget.supportService.streamTicketById(ticketId);
    _selectedMessagesStream =
        widget.supportService.streamTicketMessages(ticketId);
    _markReadByAdmin(ticketId);
    if (widget.onInitialTicketHandled != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onInitialTicketHandled?.call();
      });
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _replyCtrl.dispose();
    _replyFocusNode.dispose();
    _msgScrollCtrl.dispose();
    super.dispose();
  }

  Stream<List<SupportTicket>> _buildTicketsStream() {
    // Tận dụng composite index `(status ASC, updatedAt DESC)` khi Admin chọn lọc "Mới"
    // để không bao giờ sót vé mới nằm ngoài top 30 vé cập nhật gần nhất.
    return widget.supportService.streamAdminTickets(
      statusFilter: _stageFilter == _AdminSupportStage.newTicket
          ? SupportTicketStatus.newTicket
          : null,
      limit: _limit,
    );
  }

  void _onStageChanged(_AdminSupportStage? nextStage) {
    final prevWasNew = _stageFilter == _AdminSupportStage.newTicket;
    final nextIsNew = nextStage == _AdminSupportStage.newTicket;
    setState(() {
      _stageFilter = nextStage;
      if (prevWasNew != nextIsNew) {
        _limit = _pageSize;
        _ticketsStream = _buildTicketsStream();
      }
    });
  }

  void _loadMore() {
    setState(() {
      _limit += _pageSize;
      _ticketsStream = _buildTicketsStream();
    });
  }

  void _refreshTickets() {
    setState(() {
      _ticketsStream = _buildTicketsStream();
    });
  }

  void _selectTicket(SupportTicket ticket) {
    if (_selectedTicketId != ticket.ticketId) {
      setState(() {
        _selectedTicketId = ticket.ticketId;
        _selectedTicketStream =
            widget.supportService.streamTicketById(ticket.ticketId);
        _selectedMessagesStream =
            widget.supportService.streamTicketMessages(ticket.ticketId);
      });
    }
    if (ticket.unreadByAdmin) {
      _markReadByAdmin(ticket.ticketId);
    }
  }

  Future<void> _markReadByAdmin(String ticketId) async {
    if (_markingReadTicketId == ticketId) return;
    _markingReadTicketId = ticketId;
    try {
      await widget.supportService.markTicketReadByAdmin(ticketId);
    } catch (_) {
      // Bỏ qua lỗi mạng nhẹ khi đánh dấu đã đọc
    } finally {
      if (_markingReadTicketId == ticketId) {
        _markingReadTicketId = null;
      }
    }
  }

  Future<void> _handleClaim(SupportTicket ticket) async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      await widget.supportService.claimTicketByAdmin(
        ticket: ticket,
        adminUid: widget.currentAdminUid,
        adminName: widget.currentAdminName,
      );
      if (!mounted) return;
      AppSnackbar.show(context, 'Đã tiếp nhận yêu cầu ${ticket.ticketCode}.');
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.show(context, formatAdminErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _handleReply(SupportTicket ticket) async {
    final text = _replyCtrl.text.trim();
    if (text.isEmpty || _isSubmitting || !ticket.status.canAdminReply) return;

    setState(() => _isSubmitting = true);
    try {
      await widget.supportService.sendAdminReply(
        ticket: ticket,
        adminUid: widget.currentAdminUid,
        adminName: widget.currentAdminName,
        body: text,
      );
      if (!mounted) return;
      _replyCtrl.clear();
      AppSnackbar.show(context, 'Đã gửi phản hồi tới người dùng.');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_msgScrollCtrl.hasClients) {
          _msgScrollCtrl.animateTo(
            _msgScrollCtrl.position.maxScrollExtent + 80,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.show(context, formatAdminErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _insertQuickReply(_QuickReplyPreset preset) {
    final existing = _replyCtrl.text;
    final nextText = existing.trim().isEmpty
        ? preset.content
        : '${existing.trimRight()}\n${preset.content}';
    final clamped = nextText.length > SupportTicket.kMaxMessageLength
        ? nextText.substring(0, SupportTicket.kMaxMessageLength)
        : nextText;
    _replyCtrl.value = TextEditingValue(
      text: clamped,
      selection: TextSelection.collapsed(offset: clamped.length),
    );
    _replyFocusNode.requestFocus();
  }

  Future<void> _handleReopenResolved(SupportTicket ticket) async {
    if (_isSubmitting || !ticket.status.canAdminReopenResolved) return;
    setState(() => _isSubmitting = true);
    try {
      await widget.supportService.reopenResolvedTicketByAdmin(
        ticket: ticket,
        adminUid: widget.currentAdminUid,
        adminName: widget.currentAdminName,
      );
      if (!mounted) return;
      AppSnackbar.show(
        context,
        'Đã mở lại xử lý yêu cầu ${ticket.ticketCode}.',
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.show(context, formatAdminErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _handleMarkResolved(SupportTicket ticket) async {
    if (_isSubmitting || !ticket.status.canAdminMarkResolved) return;
    setState(() => _isSubmitting = true);
    try {
      await widget.supportService.markResolvedByAdmin(
        ticket: ticket,
        adminUid: widget.currentAdminUid,
        adminName: widget.currentAdminName,
      );
      if (!mounted) return;
      AppSnackbar.show(
        context,
        'Đã đánh dấu ${ticket.ticketCode} là Đã giải quyết.',
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.show(context, formatAdminErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _handleCloseResolved(SupportTicket ticket) async {
    if (_isSubmitting || !ticket.status.canAdminCloseResolved) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận đóng yêu cầu'),
        content: Text(
          'Sau khi đóng yêu cầu ${ticket.ticketCode}, cuộc hội thoại sẽ kết thúc hoàn toàn và không thể gửi thêm tin nhắn.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            key: const ValueKey('admin_support_confirm_close_btn'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.expense),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Đóng yêu cầu'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isSubmitting = true);
    try {
      await widget.supportService.closeResolvedTicketByAdmin(
        ticket: ticket,
        adminUid: widget.currentAdminUid,
        adminName: widget.currentAdminName,
      );
      if (!mounted) return;
      AppSnackbar.show(context, 'Đã đóng yêu cầu ${ticket.ticketCode}.');
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.show(context, formatAdminErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  List<SupportTicket> _filterTickets(List<SupportTicket> tickets) {
    final q = _searchQuery.trim().toLowerCase();
    return tickets.where((t) {
      if (_stageFilter != null &&
          _AdminSupportStage.fromTicketStatus(t.status) != _stageFilter) {
        return false;
      }
      if (q.isNotEmpty) {
        final match = t.ticketCode.toLowerCase().contains(q) ||
            t.title.toLowerCase().contains(q) ||
            t.userName.toLowerCase().contains(q) ||
            t.userEmail.toLowerCase().contains(q);
        if (!match) return false;
      }
      return true;
    }).toList();
  }

  SupportTicket? _resolveSelectedTicket(List<SupportTicket> allTickets) {
    if (_selectedTicketId == null) return null;
    for (final t in allTickets) {
      if (t.ticketId == _selectedTicketId) return t;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<SupportTicket>>(
      stream: _ticketsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: AdminErrorStateCard(
              error: snapshot.error!,
              onRetry: _refreshTickets,
            ),
          );
        }

        final allTickets = snapshot.data ?? const <SupportTicket>[];
        final isServerFilteredNew =
            _stageFilter == _AdminSupportStage.newTicket;
        if (!isServerFilteredNew) {
          _hasCachedUnfilteredCounts = true;
          _cachedAllCount = allTickets.length;
          _cachedInProgressCount = allTickets
              .where((t) =>
                  _AdminSupportStage.fromTicketStatus(t.status) ==
                  _AdminSupportStage.inProgress)
              .length;
          _cachedResolvedCount = allTickets
              .where((t) =>
                  _AdminSupportStage.fromTicketStatus(t.status) ==
                  _AdminSupportStage.resolved)
              .length;
        }

        final filteredTickets = _filterTickets(allTickets);
        final listMatchedSelected = _resolveSelectedTicket(allTickets);
        final hasMore = allTickets.length >= _limit;

        return StreamBuilder<SupportTicket?>(
          stream: _selectedTicketStream,
          initialData: listMatchedSelected,
          builder: (context, selectedSnap) {
            final selectedTicket =
                selectedSnap.data ?? listMatchedSelected;

            // Tự động tắt `unreadByAdmin` khi ticket đang mở nhận tin nhắn mới từ User theo thời gian thực
            if (selectedTicket != null && selectedTicket.unreadByAdmin) {
              final ticketIdToMark = selectedTicket.ticketId;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _selectedTicketId == ticketIdToMark) {
                  _markReadByAdmin(ticketIdToMark);
                }
              });
            }

            return LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 900;
                final isCompactHeight = constraints.maxHeight < 520;
                final pad = isCompactHeight ? 10.0 : 20.0;

                final listPane = _SupportTicketListPane(
                  allTickets: allTickets,
                  filteredTickets: filteredTickets,
                  selectedTicketId: selectedTicket?.ticketId,
                  stageFilter: _stageFilter,
                  isServerFilteredNew: isServerFilteredNew,
                  cachedAllCount:
                      _hasCachedUnfilteredCounts ? _cachedAllCount : null,
                  cachedInProgressCount: _hasCachedUnfilteredCounts
                      ? _cachedInProgressCount
                      : null,
                  cachedResolvedCount:
                      _hasCachedUnfilteredCounts ? _cachedResolvedCount : null,
                  searchController: _searchCtrl,
                  hasMore: hasMore,
                  isCompact: isCompactHeight,
                  onSearchChanged: (v) => setState(() => _searchQuery = v),
                  onStageChanged: _onStageChanged,
                  onSelectTicket: _selectTicket,
                  onLoadMore: _loadMore,
                );

                final conversationPane = _SupportConversationPane(
                  ticket: selectedTicket,
                  messagesStream: _selectedMessagesStream,
                  replyController: _replyCtrl,
                  replyFocusNode: _replyFocusNode,
                  scrollController: _msgScrollCtrl,
                  isSubmitting: _isSubmitting,
                  isCompactHeight: isCompactHeight,
                  showBackButton: !isWide,
                  onBack: () => setState(() {
                    _selectedTicketId = null;
                    _selectedTicketStream = null;
                    _selectedMessagesStream = null;
                  }),
                  onClaim: selectedTicket == null
                      ? null
                      : () => _handleClaim(selectedTicket),
                  onSendReply: selectedTicket == null
                      ? null
                      : () => _handleReply(selectedTicket),
                  onInsertQuickReply: _insertQuickReply,
                  onMarkResolved: selectedTicket == null
                      ? null
                      : () => _handleMarkResolved(selectedTicket),
                  onReopenResolved: selectedTicket == null
                      ? null
                      : () => _handleReopenResolved(selectedTicket),
                  onCloseResolved: selectedTicket == null
                      ? null
                      : () => _handleCloseResolved(selectedTicket),
                );

                return Padding(
                  padding: EdgeInsets.all(pad),
                  child: isWide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(width: 360, child: listPane),
                            const SizedBox(width: 16),
                            Expanded(child: conversationPane),
                          ],
                        )
                      : (selectedTicket == null ? listPane : conversationPane),
                );
              },
            );
          },
        );
      },
    );
  }
}

/// Khung bên trái: Tìm kiếm, lọc 3 trạng thái đơn giản và danh sách vé hỗ trợ.
class _SupportTicketListPane extends StatelessWidget {
  final List<SupportTicket> allTickets;
  final List<SupportTicket> filteredTickets;
  final String? selectedTicketId;
  final _AdminSupportStage? stageFilter;
  final bool isServerFilteredNew;
  final int? cachedAllCount;
  final int? cachedInProgressCount;
  final int? cachedResolvedCount;
  final TextEditingController searchController;
  final bool hasMore;
  final bool isCompact;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<_AdminSupportStage?> onStageChanged;
  final ValueChanged<SupportTicket> onSelectTicket;
  final VoidCallback onLoadMore;

  const _SupportTicketListPane({
    required this.allTickets,
    required this.filteredTickets,
    required this.selectedTicketId,
    required this.stageFilter,
    required this.isServerFilteredNew,
    this.cachedAllCount,
    this.cachedInProgressCount,
    this.cachedResolvedCount,
    required this.searchController,
    required this.hasMore,
    required this.isCompact,
    required this.onSearchChanged,
    required this.onStageChanged,
    required this.onSelectTicket,
    required this.onLoadMore,
  });

  int _countForStage(_AdminSupportStage stage) {
    return allTickets
        .where((t) => _AdminSupportStage.fromTicketStatus(t.status) == stage)
        .length;
  }

  @override
  Widget build(BuildContext context) {
    final newCount = isServerFilteredNew
        ? allTickets.length
        : _countForStage(_AdminSupportStage.newTicket);
    final allCount =
        isServerFilteredNew ? cachedAllCount : allTickets.length;
    final inProgressCount = isServerFilteredNew
        ? cachedInProgressCount
        : _countForStage(_AdminSupportStage.inProgress);
    final resolvedCount = isServerFilteredNew
        ? cachedResolvedCount
        : _countForStage(_AdminSupportStage.resolved);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.all(isCompact ? 10 : 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  key: const ValueKey('admin_support_search_input'),
                  controller: searchController,
                  onChanged: onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'Tìm theo mã vé, tiêu đề hoặc email...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 19),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    suffixIcon: searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 17),
                            onPressed: () {
                              searchController.clear();
                              onSearchChanged('');
                            },
                          )
                        : null,
                  ),
                ),
                SizedBox(height: isCompact ? 8 : 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _buildFilterChip(
                      key: const ValueKey('admin_support_status_chip_all'),
                      label: allCount != null ? 'Tất cả ($allCount)' : 'Tất cả',
                      selected: stageFilter == null,
                      onTap: () => onStageChanged(null),
                    ),
                    _buildFilterChip(
                      key: const ValueKey('admin_support_status_chip_new'),
                      label: 'Mới ($newCount)',
                      selected: stageFilter == _AdminSupportStage.newTicket,
                      onTap: () => onStageChanged(_AdminSupportStage.newTicket),
                    ),
                    _buildFilterChip(
                      key: const ValueKey(
                        'admin_support_status_chip_in_progress',
                      ),
                      label: inProgressCount != null
                          ? 'Đang xử lý ($inProgressCount)'
                          : 'Đang xử lý',
                      selected: stageFilter == _AdminSupportStage.inProgress,
                      onTap: () =>
                          onStageChanged(_AdminSupportStage.inProgress),
                    ),
                    _buildFilterChip(
                      key: const ValueKey('admin_support_status_chip_resolved'),
                      label: resolvedCount != null
                          ? 'Đã giải quyết ($resolvedCount)'
                          : 'Đã giải quyết',
                      selected: stageFilter == _AdminSupportStage.resolved,
                      onTap: () => onStageChanged(_AdminSupportStage.resolved),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.slate200),
          Expanded(
            child: filteredTickets.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'Không có yêu cầu hỗ trợ nào phù hợp.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppColors.slate500,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: filteredTickets.length + (hasMore ? 1 : 0),
                    separatorBuilder: (_, __) => const Divider(
                      height: 1,
                      color: AppColors.slate100,
                    ),
                    itemBuilder: (context, index) {
                      if (index == filteredTickets.length) {
                        return Padding(
                          padding: const EdgeInsets.all(10),
                          child: OutlinedButton(
                            onPressed: onLoadMore,
                            child: const Text('Tải thêm yêu cầu'),
                          ),
                        );
                      }
                      final ticket = filteredTickets[index];
                      return _SupportTicketTile(
                        ticket: ticket,
                        isSelected: ticket.ticketId == selectedTicketId,
                        onTap: () => onSelectTicket(ticket),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ChoiceChip(
      key: key,
      label: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 11.5,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? AppColors.primary : AppColors.slate700,
        ),
      ),
      selected: selected,
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      selectedColor: AppColors.infoBackground,
      backgroundColor: AppColors.slate50,
      side: BorderSide(
        color: selected ? AppColors.primary : AppColors.slate200,
      ),
    );
  }
}

/// Một dòng vé hỗ trợ gọn trong danh sách bên trái.
class _SupportTicketTile extends StatelessWidget {
  final SupportTicket ticket;
  final bool isSelected;
  final VoidCallback onTap;

  const _SupportTicketTile({
    required this.ticket,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final stage = _AdminSupportStage.fromTicketStatus(ticket.status);
    final timeStr = DateFormat('dd/MM HH:mm').format(ticket.updatedAt.toLocal());

    return Material(
      color: isSelected
          ? AppColors.infoBackground.withValues(alpha: 0.7)
          : Colors.transparent,
      child: InkWell(
        key: ValueKey('admin_ticket_row_${ticket.ticketId}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (ticket.unreadByAdmin) ...[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.expense,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      ticket.ticketCode,
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.slate600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StageBadge(stage: stage, isClosed: ticket.isClosed),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                ticket.title,
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  fontWeight:
                      ticket.unreadByAdmin ? FontWeight.w700 : FontWeight.w600,
                  color: AppColors.slate900,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Text(
                ticket.lastMessagePreview.isNotEmpty
                    ? ticket.lastMessagePreview
                    : ticket.description,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppColors.slate500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      ticket.userEmail.isNotEmpty
                          ? '${ticket.userName} · ${ticket.userEmail}'
                          : ticket.userName,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppColors.slate400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    timeStr,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppColors.slate400,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Khung bên phải: Chi tiết vé, nút chuyển trạng thái, chat 2 chiều Realtime & ô nhập phản hồi.
class _SupportConversationPane extends StatelessWidget {
  final SupportTicket? ticket;
  final Stream<List<SupportMessage>>? messagesStream;
  final TextEditingController replyController;
  final FocusNode replyFocusNode;
  final ScrollController scrollController;
  final bool isSubmitting;
  final bool isCompactHeight;
  final bool showBackButton;
  final VoidCallback onBack;
  final VoidCallback? onClaim;
  final VoidCallback? onSendReply;
  final ValueChanged<_QuickReplyPreset> onInsertQuickReply;
  final VoidCallback? onMarkResolved;
  final VoidCallback? onReopenResolved;
  final VoidCallback? onCloseResolved;

  const _SupportConversationPane({
    required this.ticket,
    required this.messagesStream,
    required this.replyController,
    required this.replyFocusNode,
    required this.scrollController,
    required this.isSubmitting,
    required this.isCompactHeight,
    required this.showBackButton,
    required this.onBack,
    required this.onInsertQuickReply,
    this.onClaim,
    this.onSendReply,
    this.onMarkResolved,
    this.onReopenResolved,
    this.onCloseResolved,
  });

  @override
  Widget build(BuildContext context) {
    if (ticket == null) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.slate200),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.forum_outlined,
                  size: 42,
                  color: AppColors.slate300,
                ),
                const SizedBox(height: 10),
                Text(
                  'Chọn một yêu cầu hỗ trợ để xem chi tiết và trao đổi trực tiếp.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    color: AppColors.slate500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final current = ticket!;
    final stage = _AdminSupportStage.fromTicketStatus(current.status);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(current, stage),
          const Divider(height: 1, color: AppColors.slate200),
          Expanded(
            child: StreamBuilder<List<SupportMessage>>(
              stream: messagesStream,
              builder: (context, msgSnap) {
                if (msgSnap.connectionState == ConnectionState.waiting &&
                    !msgSnap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (msgSnap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: AdminErrorStateCard(error: msgSnap.error!),
                  );
                }
                final messages = msgSnap.data ?? const <SupportMessage>[];
                if (messages.isEmpty) {
                  return Center(
                    child: Text(
                      'Chưa có tin nhắn trong yêu cầu này.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppColors.slate500,
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  controller: scrollController,
                  padding: EdgeInsets.all(isCompactHeight ? 10 : 16),
                  itemCount: messages.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, idx) =>
                      _SupportMessageBubble(message: messages[idx]),
                );
              },
            ),
          ),
          const Divider(height: 1, color: AppColors.slate200),
          _buildReplyBar(current),
        ],
      ),
    );
  }

  Widget _buildHeader(SupportTicket current, _AdminSupportStage stage) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: isCompactHeight ? 104 : 220),
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: isCompactHeight ? 12 : 18,
          vertical: isCompactHeight ? 8 : 14,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (showBackButton) ...[
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.arrow_back_rounded, size: 20),
                    tooltip: 'Quay lại danh sách',
                    onPressed: onBack,
                  ),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(
                    '${current.ticketCode} · ${current.title}',
                    style: GoogleFonts.inter(
                      fontSize: isCompactHeight ? 13.5 : 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.slate900,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                _StageBadge(stage: stage, isClosed: current.isClosed),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${current.userName}${current.userEmail.isNotEmpty ? ' (${current.userEmail})' : ''}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.slate600,
                  ),
                ),
                Text(
                  '· ${current.category.viLabel}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.slate500,
                  ),
                ),
                if (current.assignedAdminName != null &&
                    current.assignedAdminName!.isNotEmpty)
                  Text(
                    '· Phụ trách: ${current.assignedAdminName}',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppColors.slate500,
                    ),
                  ),
              ],
            ),
            if (current.sharedContext != null &&
                current.sharedContext!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.slate50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.slate200),
                ),
                child: Text(
                  'Thông tin người dùng chủ động chia sẻ:\n${current.sharedContext!}',
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    color: AppColors.slate700,
                    height: 1.35,
                  ),
                ),
              ),
            ],
            if (current.technicalInfo != null) ...[
              const SizedBox(height: 6),
              Container(
                key: const ValueKey('admin_support_tech_info'),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.slate50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.slate200),
                ),
                child: Text(
                  'Thiết bị: ${current.technicalInfo!.summaryLine}',
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    color: AppColors.slate600,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (current.status == SupportTicketStatus.newTicket)
                  OutlinedButton.icon(
                    key: const ValueKey('admin_support_claim_btn'),
                    onPressed: isSubmitting ? null : onClaim,
                    icon: const Icon(Icons.assignment_ind_outlined, size: 16),
                    label: const Text('Tiếp nhận xử lý'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                if (current.status.canAdminMarkResolved)
                  FilledButton.icon(
                    key: const ValueKey('admin_support_resolve_btn'),
                    onPressed: isSubmitting ? null : onMarkResolved,
                    icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                    label: const Text('Đánh dấu đã giải quyết'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.income,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                if (current.status.canAdminCloseResolved)
                  OutlinedButton.icon(
                    key: const ValueKey('admin_support_close_btn'),
                    onPressed: isSubmitting ? null : onCloseResolved,
                    icon: const Icon(Icons.lock_outline_rounded, size: 16),
                    label: const Text('Đóng yêu cầu'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.expense,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickRepliesBar() {
    return Padding(
      key: const ValueKey('admin_support_quick_replies_bar'),
      padding: EdgeInsets.only(
        left: isCompactHeight ? 10 : 14,
        right: isCompactHeight ? 10 : 14,
        top: isCompactHeight ? 6 : 8,
        bottom: isCompactHeight ? 2 : 4,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Icon(
              Icons.bolt_rounded,
              size: 15,
              color: AppColors.primary.withValues(alpha: 0.8),
            ),
            const SizedBox(width: 4),
            for (final preset in _QuickReplyPreset.defaults) ...[
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ActionChip(
                  key: ValueKey('admin_support_quick_reply_${preset.id}'),
                  label: Text(
                    preset.label,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.slate700,
                    ),
                  ),
                  tooltip: preset.content,
                  onPressed:
                      isSubmitting ? null : () => onInsertQuickReply(preset),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 0,
                  ),
                  backgroundColor: AppColors.slate50,
                  side: const BorderSide(color: AppColors.slate200),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildReplyBar(SupportTicket current) {
    if (current.isClosed) {
      return Container(
        key: const ValueKey('admin_support_closed_banner'),
        padding: EdgeInsets.symmetric(
          horizontal: isCompactHeight ? 12 : 16,
          vertical: isCompactHeight ? 10 : 12,
        ),
        color: AppColors.slate50,
        child: Row(
          children: [
            const Icon(
              Icons.lock_outline_rounded,
              size: 16,
              color: AppColors.slate500,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Yêu cầu đã được đóng — không thể gửi thêm tin nhắn.',
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  color: AppColors.slate600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (!current.status.canAdminReply) {
      return Container(
        key: const ValueKey('admin_support_resolved_banner'),
        padding: EdgeInsets.symmetric(
          horizontal: isCompactHeight ? 12 : 16,
          vertical: isCompactHeight ? 8 : 11,
        ),
        color: AppColors.incomeBackground,
        child: Row(
          children: [
            const Icon(
              Icons.check_circle_outline_rounded,
              size: 16,
              color: AppColors.income,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Yêu cầu này đã được giải quyết.',
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.slate700,
                ),
              ),
            ),
            if (current.status.canAdminReopenResolved) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const ValueKey('admin_support_reopen_btn'),
                onPressed: isSubmitting ? null : onReopenResolved,
                icon: const Icon(Icons.replay_rounded, size: 15),
                label: const Text('Mở lại xử lý'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildQuickRepliesBar(),
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isCompactHeight ? 10 : 14,
            vertical: isCompactHeight ? 6 : 12,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('admin_support_reply_input'),
                  controller: replyController,
                  focusNode: replyFocusNode,
                  minLines: 1,
                  maxLines: isCompactHeight ? 2 : 4,
                  maxLength: SupportTicket.kMaxMessageLength,
                  decoration: const InputDecoration(
                    hintText: 'Nhập nội dung phản hồi cho người dùng...',
                    counterText: '',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  onSubmitted: (_) {
                    if (!isSubmitting && onSendReply != null) {
                      onSendReply!();
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                key: const ValueKey('admin_support_send_reply_btn'),
                onPressed: isSubmitting ? null : onSendReply,
                icon: isSubmitting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded, size: 16),
                label: const Text('Gửi phản hồi'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SupportMessageBubble extends StatelessWidget {
  final SupportMessage message;

  const _SupportMessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final timeStr =
        DateFormat('dd/MM HH:mm').format(message.createdAt.toLocal());

    final isSystem = message.senderRole == SupportSenderRole.system ||
        message.messageType == SupportMessageType.statusChange;

    if (isSystem) {
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.slate100,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            '${message.body} · $timeStr',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              color: AppColors.slate600,
            ),
          ),
        ),
      );
    }

    final isAdmin = message.senderRole == SupportSenderRole.admin;
    return Align(
      alignment: isAdmin ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: isAdmin ? AppColors.infoBackground : AppColors.slate50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isAdmin
                  ? AppColors.primary.withValues(alpha: 0.28)
                  : AppColors.slate200,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isAdmin
                        ? '${message.senderDisplayName} (Admin)'
                        : message.senderDisplayName,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: isAdmin ? AppColors.primary : AppColors.slate700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    timeStr,
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      color: AppColors.slate400,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              SelectableText(
                message.body,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.slate900,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StageBadge extends StatelessWidget {
  final _AdminSupportStage stage;
  final bool isClosed;

  const _StageBadge({required this.stage, required this.isClosed});

  @override
  Widget build(BuildContext context) {
    final label = isClosed ? '${stage.label} · Đã đóng' : stage.label;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: stage.backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: stage.color,
        ),
      ),
    );
  }
}

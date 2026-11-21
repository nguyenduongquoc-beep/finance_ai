import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../models/support_ticket_model.dart';
import '../utils/formatters.dart';
import 'firestore_service.dart';

/// Ngoại lệ nghiệp vụ dành riêng cho Trung tâm Tư vấn & Hỗ trợ
class SupportServiceException implements Exception {
  final String message;
  const SupportServiceException(this.message);

  @override
  String toString() => message;
}

/// ============================================================
/// SUPPORT SERVICE (TRUNG TÂM TƯ VẤN & HỖ TRỢ NGƯỜI DÙNG)
/// - Tách độc lập khỏi FirestoreService để giữ mã nguồn gọn gàng.
/// - Vận hành trực tiếp qua Cloud Firestore + Security Rules (Firebase Spark),
///   không phụ thuộc Cloud Functions hay Firebase Storage.
/// - Mọi thao tác tạo/gửi tin nhắn/đổi trạng thái đều dùng Firestore WriteBatch
///   nguyên tử để khớp chặt với kiểm soát đồng bộ 2 chiều `getAfter()` trong `firestore.rules`.
/// ============================================================
class SupportService {
  static const String kTicketsCollection = 'support_tickets';
  static const String kMessagesSubcollection = 'messages';

  final FirebaseFirestore? _customDb;
  final FirebaseAuth? _customAuth;

  SupportService({
    FirebaseFirestore? firestore,
    FirebaseAuth? firebaseAuth,
  })  : _customDb = firestore,
        _customAuth = firebaseAuth;

  FirebaseFirestore get _db => _customDb ?? FirebaseFirestore.instance;
  FirebaseAuth get _auth => _customAuth ?? FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _ticketsCol =>
      _db.collection(kTicketsCollection);

  CollectionReference<Map<String, dynamic>> _messagesCol(String ticketId) =>
      _ticketsCol.doc(ticketId).collection(kMessagesSubcollection);

  String _sanitizeDisplayName(String? raw, {required String fallback}) {
    final clean = (raw ?? '').trim();
    if (clean.isEmpty) return fallback;
    return clean.length <= 80 ? clean : clean.substring(0, 80);
  }

  String _sanitizeEmail(String? raw) {
    final clean = (raw ?? '').trim();
    return clean.length <= 120 ? clean : clean.substring(0, 120);
  }

  // =========================================================================
  // 1. LUỒNG NGƯỜI DÙNG (USER APP)
  // =========================================================================

  /// Stream danh sách yêu cầu của chính User hiện tại (có giới hạn trang để tiết kiệm Spark reads)
  Stream<List<SupportTicket>> streamUserTickets(
    String userId, {
    int limit = 25,
  }) {
    if (userId.trim().isEmpty) {
      return Stream.value(const <SupportTicket>[]);
    }
    return _ticketsCol
        .where('userId', isEqualTo: userId)
        .orderBy('updatedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => SupportTicket.fromMap(d.data(), d.id))
            .toList());
  }

  /// Stream các yêu cầu có cập nhật chưa đọc của User (truy vấn nhẹ cho badge Home/Profile/Notification)
  Stream<List<SupportTicket>> streamUnreadUserTickets(
    String userId, {
    int limit = 20,
  }) {
    if (userId.trim().isEmpty) {
      return Stream.value(const <SupportTicket>[]);
    }
    return _ticketsCol
        .where('userId', isEqualTo: userId)
        .where('unreadByUser', isEqualTo: true)
        .limit(limit)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => SupportTicket.fromMap(d.data(), d.id))
          .toList();
      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return list;
    });
  }

  /// Stream chi tiết 1 yêu cầu theo ID
  Stream<SupportTicket?> streamTicketById(String ticketId) {
    if (ticketId.trim().isEmpty) return Stream.value(null);
    return _ticketsCol.doc(ticketId).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return SupportTicket.fromMap(snap.data()!, snap.id);
    });
  }

  /// Tải 1 yêu cầu theo ID khi người dùng hoặc Admin chủ động bấm xem ticket tham chiếu
  Future<SupportTicket?> getTicketById(String ticketId) async {
    if (ticketId.trim().isEmpty) return null;
    final snap = await _ticketsCol.doc(ticketId).get();
    if (!snap.exists || snap.data() == null) return null;
    return SupportTicket.fromMap(snap.data()!, snap.id);
  }

  /// Stream lịch sử tin nhắn chỉ của 1 yêu cầu đang mở (không tải toàn hệ thống)
  Stream<List<SupportMessage>> streamTicketMessages(
    String ticketId, {
    int limit = 100,
  }) {
    if (ticketId.trim().isEmpty) {
      return Stream.value(const <SupportMessage>[]);
    }
    return _messagesCol(ticketId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => SupportMessage.fromMap(d.data(), d.id))
          .toList();
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return list;
    });
  }

  /// Tạo yêu cầu hỗ trợ mới + tin nhắn khởi đầu trong 1 WriteBatch nguyên tử.
  /// Mức ưu tiên xử lý mặc định luôn là `normal` (Admin có quyền đánh giá & điều chỉnh sau).
  Future<SupportTicket> createTicket({
    required SupportCategory category,
    required String title,
    required String description,
    String? sharedContext,
    SupportUserImpact? userImpact,
    SupportTechnicalInfo? technicalInfo,
    SupportTicket? relatedTicket,
    String? userIdOverride,
    String? userNameOverride,
    String? userEmailOverride,
  }) async {
    final currentUser = _customAuth == null && userIdOverride != null
        ? null
        : _auth.currentUser;
    final uid = (userIdOverride ?? currentUser?.uid ?? '').trim();
    if (uid.isEmpty) {
      throw const SupportServiceException(
        'Vui lòng đăng nhập để gửi yêu cầu hỗ trợ.',
      );
    }

    final cleanTitle = title.trim();
    final cleanDesc = description.trim();
    final cleanContext = sharedContext?.trim();

    if (cleanTitle.length < SupportTicket.kMinTitleLength ||
        cleanTitle.length > SupportTicket.kMaxTitleLength) {
      throw const SupportServiceException(
        'Tiêu đề phải dài từ 5 đến 120 ký tự.',
      );
    }
    if (cleanDesc.length < SupportTicket.kMinDescriptionLength ||
        cleanDesc.length > SupportTicket.kMaxDescriptionLength) {
      throw const SupportServiceException(
        'Nội dung mô tả phải dài từ 10 đến 2000 ký tự.',
      );
    }
    if (cleanContext != null &&
        cleanContext.length > SupportTicket.kMaxSharedContextLength) {
      throw const SupportServiceException(
        'Thông tin chia sẻ bổ sung không được vượt quá 800 ký tự.',
      );
    }
    if (technicalInfo != null && category != SupportCategory.bugReport) {
      throw const SupportServiceException(
        'Thông tin kỹ thuật cơ bản chỉ đính kèm cho yêu cầu Báo lỗi hoặc sự cố.',
      );
    }
    if (relatedTicket != null) {
      if (relatedTicket.userId != uid) {
        throw const SupportServiceException(
          'Bạn chỉ có thể tham chiếu yêu cầu hỗ trợ của chính mình.',
        );
      }
      if (!relatedTicket.isClosed) {
        throw const SupportServiceException(
          'Chỉ có thể tham chiếu yêu cầu trước đó đã được đóng.',
        );
      }
    }

    final nowUtc = DateTime.now().toUtc();
    final ticketRef = _ticketsCol.doc();
    final firstMsgRef = _messagesCol(ticketRef.id).doc();

    final resolvedName = _sanitizeDisplayName(
      userNameOverride ?? currentUser?.displayName,
      fallback: 'Người dùng',
    );
    final resolvedEmail = _sanitizeEmail(
      userEmailOverride ?? currentUser?.email,
    );
    final ticketCode = SupportTicket.generateTicketCode(ticketRef.id, nowUtc);

    final ticket = SupportTicket(
      ticketId: ticketRef.id,
      ticketCode: ticketCode,
      userId: uid,
      userName: resolvedName,
      userEmail: resolvedEmail,
      category: category,
      title: cleanTitle,
      description: cleanDesc,
      sharedContext: (cleanContext != null && cleanContext.isNotEmpty)
          ? cleanContext
          : null,
      status: SupportTicketStatus.newTicket,
      priority: SupportPriority.normal,
      userImpact: userImpact ?? SupportUserImpact.normal,
      technicalInfo: technicalInfo,
      relatedTicketId: relatedTicket?.ticketId,
      relatedTicketCode: relatedTicket?.ticketCode,
      assignedAdminId: null,
      assignedAdminName: null,
      lastMessageId: firstMsgRef.id,
      lastMessagePreview: SupportTicket.buildPreview(cleanDesc),
      lastMessageSenderRole: SupportSenderRole.user,
      lastMessageAt: nowUtc,
      unreadByAdmin: true,
      unreadByUser: false,
      createdAt: nowUtc,
      updatedAt: nowUtc,
      claimedAt: null,
      firstAdminResponseAt: null,
      resolvedAt: null,
      resolvedByRole: null,
      closedAt: null,
      closeReason: null,
      ratingScore: null,
      ratingComment: null,
      ratedAt: null,
      ratingUpdatedAt: null,
      ratingEditCount: 0,
    );

    final firstMessage = SupportMessage(
      messageId: firstMsgRef.id,
      senderId: uid,
      senderRole: SupportSenderRole.user,
      senderDisplayName: resolvedName,
      body: cleanDesc,
      messageType: SupportMessageType.text,
      createdAt: nowUtc,
    );

    final batch = _db.batch();
    batch.set(ticketRef, ticket.toMap());
    batch.set(firstMsgRef, firstMessage.toMap());
    await batch.commit();

    return ticket;
  }

  /// User gửi thêm tin nhắn vào một yêu cầu chưa đóng (WriteBatch nguyên tử 2 chiều).
  /// - Tự động chuyển `waiting_for_user` / `replied` / `resolved` -> `in_progress`.
  /// - Khi quay lại `in_progress` từ `resolved`: xóa `resolvedAt` & `resolvedByRole`,
  ///   nhưng GIỮ NGUYÊN đánh giá cũ (nếu có) như phản hồi lịch sử.
  Future<SupportMessage> sendUserMessage({
    required SupportTicket ticket,
    required String body,
    String? userIdOverride,
    String? userNameOverride,
  }) async {
    final currentUser = _customAuth == null && userIdOverride != null
        ? null
        : _auth.currentUser;
    final uid = (userIdOverride ?? currentUser?.uid ?? '').trim();
    if (uid.isEmpty || uid != ticket.userId) {
      throw const SupportServiceException(
        'Bạn không có quyền gửi tin nhắn cho yêu cầu này.',
      );
    }
    if (ticket.isClosed) {
      throw const SupportServiceException(
        'Yêu cầu này đã đóng và không thể gửi thêm tin nhắn.',
      );
    }

    final cleanBody = body.trim();
    if (cleanBody.isEmpty ||
        cleanBody.length > SupportTicket.kMaxMessageLength) {
      throw const SupportServiceException(
        'Nội dung tin nhắn phải từ 1 đến 2000 ký tự.',
      );
    }

    final nextStatus = ticket.status.nextStatusOnUserMessage();
    if (nextStatus == null) {
      throw const SupportServiceException(
        'Yêu cầu này đã đóng và không thể tiếp tục trao đổi.',
      );
    }

    final nowUtc = DateTime.now().toUtc();
    final nowIso = nowUtc.toIso8601String();
    final ticketRef = _ticketsCol.doc(ticket.ticketId);
    final msgRef = _messagesCol(ticket.ticketId).doc();
    final resolvedName = _sanitizeDisplayName(
      userNameOverride ?? ticket.userName,
      fallback: 'Người dùng',
    );

    final msg = SupportMessage(
      messageId: msgRef.id,
      senderId: uid,
      senderRole: SupportSenderRole.user,
      senderDisplayName: resolvedName,
      body: cleanBody,
      messageType: SupportMessageType.text,
      createdAt: nowUtc,
    );

    final updates = <String, dynamic>{
      'status': nextStatus.code,
      'lastMessageId': msgRef.id,
      'lastMessagePreview': SupportTicket.buildPreview(cleanBody),
      'lastMessageSenderRole': SupportSenderRole.user.code,
      'lastMessageAt': nowIso,
      'unreadByAdmin': true,
      'unreadByUser': false,
      'updatedAt': nowIso,
    };

    if (ticket.status == SupportTicketStatus.resolved) {
      updates['resolvedAt'] = null;
      updates['resolvedByRole'] = null;
    }

    final batch = _db.batch();
    batch.set(msgRef, msg.toMap());
    batch.update(ticketRef, updates);
    await batch.commit();

    return msg;
  }

  /// User chủ động xác nhận vấn đề đã được giải quyết (`in_progress | waiting_for_user | replied` -> `resolved`)
  /// trong 1 WriteBatch nguyên tử đồng bộ kèm tin nhắn sự kiện.
  Future<void> confirmResolvedByUser({
    required SupportTicket ticket,
    String? userIdOverride,
    String? userNameOverride,
  }) async {
    final currentUser = _customAuth == null && userIdOverride != null
        ? null
        : _auth.currentUser;
    final uid = (userIdOverride ?? currentUser?.uid ?? '').trim();
    if (uid.isEmpty || uid != ticket.userId) {
      throw const SupportServiceException(
        'Bạn không có quyền xác nhận cho yêu cầu này.',
      );
    }
    if (!ticket.canUserConfirmResolved) {
      throw const SupportServiceException(
        'Chỉ có thể xác nhận đã giải quyết sau khi Admin đã tiếp nhận hoặc phản hồi yêu cầu.',
      );
    }

    final nowUtc = DateTime.now().toUtc();
    final nowIso = nowUtc.toIso8601String();
    final resolvedName = _sanitizeDisplayName(
      userNameOverride ?? ticket.userName,
      fallback: 'Người dùng',
    );
    final body = '$resolvedName đã xác nhận vấn đề đã được giải quyết.';

    final ticketRef = _ticketsCol.doc(ticket.ticketId);
    final msgRef = _messagesCol(ticket.ticketId).doc();
    final statusMsg = SupportMessage(
      messageId: msgRef.id,
      senderId: uid,
      senderRole: SupportSenderRole.user,
      senderDisplayName: resolvedName,
      body: body,
      messageType: SupportMessageType.statusChange,
      createdAt: nowUtc,
    );

    final batch = _db.batch();
    batch.set(msgRef, statusMsg.toMap());
    batch.update(ticketRef, {
      'status': SupportTicketStatus.resolved.code,
      'resolvedAt': nowIso,
      'resolvedByRole': 'user',
      'lastMessageId': msgRef.id,
      'lastMessagePreview': SupportTicket.buildPreview(body),
      'lastMessageSenderRole': SupportSenderRole.user.code,
      'lastMessageAt': nowIso,
      'unreadByAdmin': true,
      'unreadByUser': false,
      'updatedAt': nowIso,
    });
    await batch.commit();
  }

  /// User gửi đánh giá chính thức hoặc chỉnh sửa tối đa 1 lần — CHỈ khi ticket ở trạng thái `resolved`.
  Future<void> submitOrUpdateRating({
    required SupportTicket ticket,
    required int score,
    String? comment,
    String? userIdOverride,
  }) async {
    final currentUser = _customAuth == null && userIdOverride != null
        ? null
        : _auth.currentUser;
    final uid = (userIdOverride ?? currentUser?.uid ?? '').trim();
    if (uid.isEmpty || uid != ticket.userId) {
      throw const SupportServiceException(
        'Bạn không có quyền đánh giá yêu cầu hỗ trợ này.',
      );
    }
    if (ticket.isClosed) {
      throw const SupportServiceException(
        'Yêu cầu đã đóng nên không thể gửi hoặc chỉnh sửa đánh giá.',
      );
    }
    if (!ticket.isResolved) {
      throw const SupportServiceException(
        'Chỉ có thể gửi đánh giá sau khi yêu cầu đã ở trạng thái Đã giải quyết.',
      );
    }
    if (score < 1 || score > 5) {
      throw const SupportServiceException(
        'Điểm đánh giá phải nằm trong khoảng từ 1 đến 5 sao.',
      );
    }

    final cleanComment = comment?.trim();
    if (cleanComment != null &&
        cleanComment.length > SupportTicket.kMaxRatingCommentLength) {
      throw const SupportServiceException(
        'Nhận xét đánh giá không được vượt quá 500 ký tự.',
      );
    }

    final nowUtc = DateTime.now().toUtc();
    final nowIso = nowUtc.toIso8601String();
    final storedComment =
        (cleanComment != null && cleanComment.isNotEmpty) ? cleanComment : null;

    if (!ticket.hasRating) {
      await _ticketsCol.doc(ticket.ticketId).update({
        'ratingScore': score,
        'ratingComment': storedComment,
        'ratedAt': nowIso,
        'ratingUpdatedAt': nowIso,
        'ratingEditCount': 0,
      });
      return;
    }

    if (ticket.ratingEditCount >= SupportTicket.kMaxRatingEditCount) {
      throw const SupportServiceException(
        'Bạn đã sử dụng hết lượt chỉnh sửa đánh giá cho yêu cầu này.',
      );
    }

    await _ticketsCol.doc(ticket.ticketId).update({
      'ratingScore': score,
      'ratingComment': storedComment,
      if (ticket.ratedAt == null) 'ratedAt': nowIso,
      'ratingUpdatedAt': nowIso,
      'ratingEditCount': ticket.ratingEditCount + 1,
    });
  }

  /// Đánh dấu User đã đọc cập nhật mới (CHỈ đổi `unreadByUser`, KHÔNG đổi trạng thái xử lý)
  Future<void> markTicketReadByUser(String ticketId) async {
    if (ticketId.trim().isEmpty) return;
    await _ticketsCol.doc(ticketId).update({'unreadByUser': false});
  }

  /// Đánh dấu tất cả yêu cầu hỗ trợ có cập nhật mới của User là đã đọc (đồng bộ với nút Đánh dấu tất cả đã đọc ở màn Thông báo)
  Future<void> markAllUserTicketsRead(String userId) async {
    if (userId.trim().isEmpty) return;
    final snap = await _ticketsCol
        .where('userId', isEqualTo: userId)
        .where('unreadByUser', isEqualTo: true)
        .limit(20)
        .get();
    if (snap.docs.isEmpty) return;
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'unreadByUser': false});
    }
    await batch.commit();
  }

  /// Tạo bản tóm tắt tài chính tháng hiện tại CHỈ KHI người dùng chủ động bật chia sẻ tự nguyện.
  /// Không tự động gọi nếu người dùng không chọn, và chỉ trả về chuỗi văn bản tóm tắt
  /// để người dùng xem trước/chỉnh sửa trước khi gửi (không gửi danh sách giao dịch chi tiết).
  Future<String> buildOptInMonthlySummary(
    String userId, {
    FirestoreService? firestoreService,
  }) async {
    final fs = firestoreService ?? FirestoreService(firestore: _customDb);
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    final monthLabel = DateFormat('MM/yyyy').format(now);

    final results = await Future.wait<dynamic>([
      fs.getTransactionsByDateWindow(userId, from: monthStart, to: monthEnd),
      fs.getBudgetsSafely(userId, month: monthLabel),
      fs.getSavingGoalsSafely(userId),
    ]);

    final txs = results[0] as List;
    final budgets = results[1] as List;
    final goals = results[2] as List;

    double totalIncome = 0;
    double totalExpense = 0;
    for (final dynamic t in txs) {
      if (t.type == 'income') {
        totalIncome += (t.amount as num).toDouble();
      } else if (t.type == 'expense') {
        totalExpense += (t.amount as num).toDouble();
      }
    }

    final net = totalIncome - totalExpense;
    final savingRatePct =
        totalIncome > 0 ? ((net / totalIncome) * 100).clamp(-999, 100) : null;

    final buffer = StringBuffer()
      ..writeln('Tóm tắt tự nguyện tháng $monthLabel:')
      ..writeln('- Tổng thu tháng: ${AppFormatters.currency(totalIncome)}')
      ..writeln('- Tổng chi tháng: ${AppFormatters.currency(totalExpense)}')
      ..writeln(
        savingRatePct != null
            ? '- Chênh lệch thu chi: ${AppFormatters.currency(net)} (${savingRatePct.toStringAsFixed(1)}%)'
            : '- Chênh lệch thu chi: ${AppFormatters.currency(net)}',
      )
      ..write(
        '- Ngân sách tháng đang thiết lập: ${budgets.length} · Mục tiêu tiết kiệm: ${goals.length}',
      );

    final summary = buffer.toString().trim();
    if (summary.length <= SupportTicket.kMaxSharedContextLength) {
      return summary;
    }
    return summary.substring(0, SupportTicket.kMaxSharedContextLength);
  }

  // =========================================================================
  // 2. LUỒNG QUẢN TRỊ VIÊN (ADMIN WEB - CHẠY TRỰC TIẾP QUA FIRESTORE RULES)
  // =========================================================================

  /// Stream danh sách yêu cầu hỗ trợ cho Admin (giới hạn trang, lọc phía server theo status/category)
  Stream<List<SupportTicket>> streamAdminTickets({
    SupportTicketStatus? statusFilter,
    SupportCategory? categoryFilter,
    int limit = 30,
  }) {
    Query<Map<String, dynamic>> query = _ticketsCol;
    if (categoryFilter != null) {
      query = query.where('category', isEqualTo: categoryFilter.code);
    }
    if (statusFilter != null) {
      query = query.where('status', isEqualTo: statusFilter.code);
    }
    query = query.orderBy('updatedAt', descending: true).limit(limit);

    return query.snapshots().map((snap) => snap.docs
        .map((d) => SupportTicket.fromMap(d.data(), d.id))
        .toList());
  }

  /// Stream số yêu cầu có cập nhật chưa đọc từ phía User (truy vấn nhẹ cho badge Sidebar Admin)
  Stream<int> streamAdminUnreadCount({int limit = 50}) {
    return _ticketsCol
        .where('unreadByAdmin', isEqualTo: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  /// Admin đánh dấu đã đọc tin nhắn mới của User (CHỈ đổi `unreadByAdmin`, KHÔNG đổi trạng thái)
  Future<void> markTicketReadByAdmin(String ticketId) async {
    if (ticketId.trim().isEmpty) return;
    await _ticketsCol.doc(ticketId).update({'unreadByAdmin': false});
  }

  /// Admin đánh giá và điều chỉnh mức độ ưu tiên xử lý cho yêu cầu chưa đóng
  Future<void> updateTicketPriorityByAdmin({
    required SupportTicket ticket,
    required String adminUid,
    required SupportPriority priority,
  }) async {
    if (adminUid.trim().isEmpty) {
      throw const SupportServiceException('Thiếu thông tin Quản trị viên.');
    }
    if (ticket.isClosed) {
      throw const SupportServiceException(
        'Không thể điều chỉnh mức ưu tiên của yêu cầu đã đóng.',
      );
    }
    if (ticket.priority == priority) return;

    final nowIso = DateTime.now().toUtc().toIso8601String();
    await _ticketsCol.doc(ticket.ticketId).update({
      'priority': priority.code,
      'updatedAt': nowIso,
    });
  }

  /// Admin tiếp nhận yêu cầu (`new` -> `in_progress`) kèm tin nhắn hệ thống trong 1 WriteBatch
  Future<void> claimTicketByAdmin({
    required SupportTicket ticket,
    required String adminUid,
    required String adminName,
  }) async {
    if (adminUid.trim().isEmpty) {
      throw const SupportServiceException('Thiếu thông tin Quản trị viên.');
    }
    if (ticket.status != SupportTicketStatus.newTicket) {
      throw const SupportServiceException(
        'Chỉ có thể tiếp nhận yêu cầu đang ở trạng thái Mới tiếp nhận.',
      );
    }

    final nowUtc = DateTime.now().toUtc();
    final nowIso = nowUtc.toIso8601String();
    final cleanAdminName =
        _sanitizeDisplayName(adminName, fallback: 'Quản trị viên');
    final body = '$cleanAdminName đã tiếp nhận và bắt đầu xử lý yêu cầu.';

    final ticketRef = _ticketsCol.doc(ticket.ticketId);
    final msgRef = _messagesCol(ticket.ticketId).doc();
    final sysMsg = SupportMessage(
      messageId: msgRef.id,
      senderId: adminUid.trim(),
      senderRole: SupportSenderRole.system,
      senderDisplayName: cleanAdminName,
      body: body,
      messageType: SupportMessageType.statusChange,
      createdAt: nowUtc,
    );

    final batch = _db.batch();
    batch.set(msgRef, sysMsg.toMap());
    batch.update(ticketRef, {
      'status': SupportTicketStatus.inProgress.code,
      'assignedAdminId': adminUid.trim(),
      'assignedAdminName': cleanAdminName,
      if (ticket.claimedAt == null) 'claimedAt': nowIso,
      'lastMessageId': msgRef.id,
      'lastMessagePreview': SupportTicket.buildPreview(body),
      'lastMessageSenderRole': SupportSenderRole.system.code,
      'lastMessageAt': nowIso,
      'unreadByAdmin': false,
      'unreadByUser': true,
      'updatedAt': nowIso,
    });
    await batch.commit();
  }

  /// Admin gửi phản hồi (`replied`) hoặc yêu cầu người dùng bổ sung thông tin (`waiting_for_user`)
  Future<SupportMessage> sendAdminReply({
    required SupportTicket ticket,
    required String adminUid,
    required String adminName,
    required String body,
    bool requestMoreInfo = false,
  }) async {
    if (adminUid.trim().isEmpty) {
      throw const SupportServiceException('Thiếu thông tin Quản trị viên.');
    }
    if (ticket.isClosed) {
      throw const SupportServiceException(
        'Yêu cầu đã đóng nên không thể gửi thêm phản hồi.',
      );
    }
    if (!ticket.status.canAdminReply) {
      throw const SupportServiceException(
        'Yêu cầu đang ở trạng thái Đã giải quyết. Chờ người dùng xác nhận/đánh giá hoặc thực hiện đóng yêu cầu.',
      );
    }

    final cleanBody = body.trim();
    if (cleanBody.isEmpty ||
        cleanBody.length > SupportTicket.kMaxMessageLength) {
      throw const SupportServiceException(
        'Nội dung phản hồi phải từ 1 đến 2000 ký tự.',
      );
    }

    final nowUtc = DateTime.now().toUtc();
    final nowIso = nowUtc.toIso8601String();
    final cleanAdminName =
        _sanitizeDisplayName(adminName, fallback: 'Quản trị viên');
    final targetStatus = requestMoreInfo
        ? SupportTicketStatus.waitingForUser
        : SupportTicketStatus.replied;
    final msgType = requestMoreInfo
        ? SupportMessageType.requestInfo
        : SupportMessageType.text;

    final ticketRef = _ticketsCol.doc(ticket.ticketId);
    final msgRef = _messagesCol(ticket.ticketId).doc();
    final msg = SupportMessage(
      messageId: msgRef.id,
      senderId: adminUid.trim(),
      senderRole: SupportSenderRole.admin,
      senderDisplayName: cleanAdminName,
      body: cleanBody,
      messageType: msgType,
      createdAt: nowUtc,
    );

    final batch = _db.batch();
    batch.set(msgRef, msg.toMap());
    batch.update(ticketRef, {
      'status': targetStatus.code,
      'assignedAdminId': ticket.assignedAdminId ?? adminUid.trim(),
      'assignedAdminName': ticket.assignedAdminName ?? cleanAdminName,
      if (ticket.claimedAt == null) 'claimedAt': nowIso,
      if (ticket.firstAdminResponseAt == null) 'firstAdminResponseAt': nowIso,
      'lastMessageId': msgRef.id,
      'lastMessagePreview': SupportTicket.buildPreview(cleanBody),
      'lastMessageSenderRole': SupportSenderRole.admin.code,
      'lastMessageAt': nowIso,
      'unreadByAdmin': false,
      'unreadByUser': true,
      'updatedAt': nowIso,
    });
    await batch.commit();

    return msg;
  }

  /// Admin đánh dấu yêu cầu Đã giải quyết (`new | in_progress | waiting_for_user | replied` -> `resolved`)
  Future<void> markResolvedByAdmin({
    required SupportTicket ticket,
    required String adminUid,
    required String adminName,
    String? note,
  }) async {
    if (adminUid.trim().isEmpty) {
      throw const SupportServiceException('Thiếu thông tin Quản trị viên.');
    }
    if (!ticket.status.canAdminMarkResolved) {
      throw const SupportServiceException(
        'Chỉ có thể đánh dấu Đã giải quyết cho yêu cầu đang xử lý hoặc đang trao đổi.',
      );
    }

    final nowUtc = DateTime.now().toUtc();
    final nowIso = nowUtc.toIso8601String();
    final cleanAdminName =
        _sanitizeDisplayName(adminName, fallback: 'Quản trị viên');
    final cleanNote = note?.trim();

    var eventBody = '$cleanAdminName đã đánh dấu yêu cầu là Đã giải quyết.';
    if (cleanNote != null && cleanNote.isNotEmpty) {
      eventBody = '$eventBody Ghi chú: $cleanNote';
    }
    if (eventBody.length > SupportTicket.kMaxMessageLength) {
      eventBody = eventBody.substring(0, SupportTicket.kMaxMessageLength);
    }

    final ticketRef = _ticketsCol.doc(ticket.ticketId);
    final msgRef = _messagesCol(ticket.ticketId).doc();
    final sysMsg = SupportMessage(
      messageId: msgRef.id,
      senderId: adminUid.trim(),
      senderRole: SupportSenderRole.system,
      senderDisplayName: cleanAdminName,
      body: eventBody,
      messageType: SupportMessageType.statusChange,
      createdAt: nowUtc,
    );

    final batch = _db.batch();
    batch.set(msgRef, sysMsg.toMap());
    batch.update(ticketRef, {
      'status': SupportTicketStatus.resolved.code,
      'assignedAdminId': ticket.assignedAdminId ?? adminUid.trim(),
      'assignedAdminName': ticket.assignedAdminName ?? cleanAdminName,
      if (ticket.claimedAt == null) 'claimedAt': nowIso,
      'resolvedAt': nowIso,
      'resolvedByRole': 'admin',
      'closedAt': null,
      'closeReason': null,
      'lastMessageId': msgRef.id,
      'lastMessagePreview': SupportTicket.buildPreview(eventBody),
      'lastMessageSenderRole': SupportSenderRole.system.code,
      'lastMessageAt': nowIso,
      'unreadByAdmin': false,
      'unreadByUser': true,
      'updatedAt': nowIso,
    });
    await batch.commit();
  }

  /// Quy trình chuẩn: Admin đóng yêu cầu đã giải quyết (`resolved` -> `closed`).
  /// Giữ nguyên `resolvedAt` và `resolvedByRole` đã ghi nhận trước đó.
  Future<void> closeResolvedTicketByAdmin({
    required SupportTicket ticket,
    required String adminUid,
    required String adminName,
    String? note,
  }) async {
    if (adminUid.trim().isEmpty) {
      throw const SupportServiceException('Thiếu thông tin Quản trị viên.');
    }
    if (ticket.status != SupportTicketStatus.resolved) {
      throw const SupportServiceException(
        'Quy trình đóng chuẩn chỉ áp dụng cho yêu cầu đã ở trạng thái Đã giải quyết.',
      );
    }
    if (ticket.resolvedAt == null) {
      throw const SupportServiceException(
        'Yêu cầu chưa có mốc thời gian giải quyết hợp lệ.',
      );
    }

    final nowUtc = DateTime.now().toUtc();
    final nowIso = nowUtc.toIso8601String();
    final cleanAdminName =
        _sanitizeDisplayName(adminName, fallback: 'Quản trị viên');
    final cleanNote = note?.trim();

    var eventBody = '$cleanAdminName đã đóng yêu cầu hỗ trợ sau khi giải quyết.';
    if (cleanNote != null && cleanNote.isNotEmpty) {
      eventBody = '$eventBody Ghi chú: $cleanNote';
    }
    if (eventBody.length > SupportTicket.kMaxMessageLength) {
      eventBody = eventBody.substring(0, SupportTicket.kMaxMessageLength);
    }

    final ticketRef = _ticketsCol.doc(ticket.ticketId);
    final msgRef = _messagesCol(ticket.ticketId).doc();
    final sysMsg = SupportMessage(
      messageId: msgRef.id,
      senderId: adminUid.trim(),
      senderRole: SupportSenderRole.system,
      senderDisplayName: cleanAdminName,
      body: eventBody,
      messageType: SupportMessageType.statusChange,
      createdAt: nowUtc,
    );

    final batch = _db.batch();
    batch.set(msgRef, sysMsg.toMap());
    batch.update(ticketRef, {
      'status': SupportTicketStatus.closed.code,
      'assignedAdminId': ticket.assignedAdminId ?? adminUid.trim(),
      'assignedAdminName': ticket.assignedAdminName ?? cleanAdminName,
      if (ticket.resolvedByRole == null) 'resolvedByRole': 'admin',
      'closedAt': nowIso,
      'closeReason': SupportCloseReason.completed.code,
      'lastMessageId': msgRef.id,
      'lastMessagePreview': SupportTicket.buildPreview(eventBody),
      'lastMessageSenderRole': SupportSenderRole.system.code,
      'lastMessageAt': nowIso,
      'unreadByAdmin': false,
      'unreadByUser': true,
      'updatedAt': nowIso,
    });
    await batch.commit();
  }

  /// Nghiệp vụ ngoại lệ tách biệt: Admin đóng yêu cầu chưa giải quyết
  /// (`new | in_progress | waiting_for_user | replied` -> `closed`) kèm lý do bắt buộc.
  /// Bắt buộc giữ `resolvedAt = null` và `resolvedByRole = null` (không giả mạo đã giải quyết).
  Future<void> closeUnresolvedTicketByAdmin({
    required SupportTicket ticket,
    required String adminUid,
    required String adminName,
    required SupportCloseReason closeReason,
    String? note,
  }) async {
    if (adminUid.trim().isEmpty) {
      throw const SupportServiceException('Thiếu thông tin Quản trị viên.');
    }
    if (!ticket.status.canAdminCloseUnresolved) {
      throw const SupportServiceException(
        'Thao tác đóng chưa giải quyết chỉ áp dụng cho yêu cầu chưa ở trạng thái Đã giải quyết hoặc Đã đóng.',
      );
    }
    if (!closeReason.isUnresolvedException) {
      throw const SupportServiceException(
        'Vui lòng chọn lý do đóng ngoại lệ hợp lệ cho yêu cầu chưa giải quyết.',
      );
    }

    final nowUtc = DateTime.now().toUtc();
    final nowIso = nowUtc.toIso8601String();
    final cleanAdminName =
        _sanitizeDisplayName(adminName, fallback: 'Quản trị viên');
    final cleanNote = note?.trim();

    var eventBody =
        '$cleanAdminName đã đóng yêu cầu (chưa giải quyết). Lý do: ${closeReason.viLabel}.';
    if (cleanNote != null && cleanNote.isNotEmpty) {
      eventBody = '$eventBody Ghi chú: $cleanNote';
    }
    if (eventBody.length > SupportTicket.kMaxMessageLength) {
      eventBody = eventBody.substring(0, SupportTicket.kMaxMessageLength);
    }

    final ticketRef = _ticketsCol.doc(ticket.ticketId);
    final msgRef = _messagesCol(ticket.ticketId).doc();
    final sysMsg = SupportMessage(
      messageId: msgRef.id,
      senderId: adminUid.trim(),
      senderRole: SupportSenderRole.system,
      senderDisplayName: cleanAdminName,
      body: eventBody,
      messageType: SupportMessageType.statusChange,
      createdAt: nowUtc,
    );

    final batch = _db.batch();
    batch.set(msgRef, sysMsg.toMap());
    batch.update(ticketRef, {
      'status': SupportTicketStatus.closed.code,
      'assignedAdminId': ticket.assignedAdminId ?? adminUid.trim(),
      'assignedAdminName': ticket.assignedAdminName ?? cleanAdminName,
      'resolvedAt': null,
      'resolvedByRole': null,
      'closedAt': nowIso,
      'closeReason': closeReason.code,
      'lastMessageId': msgRef.id,
      'lastMessagePreview': SupportTicket.buildPreview(eventBody),
      'lastMessageSenderRole': SupportSenderRole.system.code,
      'lastMessageAt': nowIso,
      'unreadByAdmin': false,
      'unreadByUser': true,
      'updatedAt': nowIso,
    });
    await batch.commit();
  }

  /// Tương thích gọi chuyển trạng thái chuẩn (`resolved`, `closed` sau giải quyết, hoặc đóng ngoại lệ khi truyền rõ `unresolvedReason`).
  /// Không cho phép mở lại yêu cầu đã đóng.
  Future<void> updateTicketStatusByAdmin({
    required SupportTicket ticket,
    required String adminUid,
    required String adminName,
    required SupportTicketStatus targetStatus,
    SupportCloseReason? unresolvedReason,
    String? note,
  }) async {
    if (targetStatus == SupportTicketStatus.resolved) {
      return markResolvedByAdmin(
        ticket: ticket,
        adminUid: adminUid,
        adminName: adminName,
        note: note,
      );
    }
    if (targetStatus == SupportTicketStatus.closed) {
      if (ticket.status == SupportTicketStatus.resolved &&
          unresolvedReason == null) {
        return closeResolvedTicketByAdmin(
          ticket: ticket,
          adminUid: adminUid,
          adminName: adminName,
          note: note,
        );
      }
      if (unresolvedReason != null && unresolvedReason.isUnresolvedException) {
        return closeUnresolvedTicketByAdmin(
          ticket: ticket,
          adminUid: adminUid,
          adminName: adminName,
          closeReason: unresolvedReason,
          note: note,
        );
      }
      throw const SupportServiceException(
        'Chỉ có thể đóng chuẩn yêu cầu đã giải quyết; nếu đóng yêu cầu chưa giải quyết phải chọn lý do đóng ngoại lệ.',
      );
    }
    throw const SupportServiceException(
      'Trạng thái chuyển đổi không hợp lệ hoặc không được phép mở lại yêu cầu đã đóng.',
    );
  }
}

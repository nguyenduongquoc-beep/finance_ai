import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../utils/constants.dart';

/// ============================================================
/// SUPPORT TICKET & MESSAGE MODELS
/// Firestore collections:
/// - support_tickets/{ticketId}
/// - support_tickets/{ticketId}/messages/{messageId}
/// Vận hành hoàn toàn trên Firebase Spark + Firestore Security Rules.
/// ============================================================

/// 4 nhóm yêu cầu hỗ trợ bắt buộc
enum SupportCategory {
  appGuide('app_guide'),
  bugReport('bug_report'),
  financialAdvisory('financial_advisory'),
  other('other');

  final String code;
  const SupportCategory(this.code);

  static SupportCategory fromCode(String? code) {
    final normalized = (code ?? '').trim();
    return SupportCategory.values.firstWhere(
      (e) => e.code == normalized,
      orElse: () => SupportCategory.other,
    );
  }

  /// Nhãn tiếng Việt cố định (dùng cho Admin Web & fallback)
  String get viLabel {
    switch (this) {
      case SupportCategory.appGuide:
        return 'Hướng dẫn sử dụng ứng dụng';
      case SupportCategory.bugReport:
        return 'Báo lỗi hoặc sự cố';
      case SupportCategory.financialAdvisory:
        return 'Tư vấn quản lý tài chính cá nhân';
      case SupportCategory.other:
        return 'Nội dung khác';
    }
  }

  /// Nhãn ngắn gọn theo ngôn ngữ hiện tại (User App)
  String localizedLabel(BuildContext context) {
    switch (this) {
      case SupportCategory.appGuide:
        return context.tr('support_cat_app_guide');
      case SupportCategory.bugReport:
        return context.tr('support_cat_bug_report');
      case SupportCategory.financialAdvisory:
        return context.tr('support_cat_financial_advisory');
      case SupportCategory.other:
        return context.tr('support_cat_other');
    }
  }

  String localizedDescription(BuildContext context) {
    switch (this) {
      case SupportCategory.appGuide:
        return context.tr('support_cat_app_guide_desc');
      case SupportCategory.bugReport:
        return context.tr('support_cat_bug_report_desc');
      case SupportCategory.financialAdvisory:
        return context.tr('support_cat_financial_advisory_desc');
      case SupportCategory.other:
        return context.tr('support_cat_other_desc');
    }
  }

  String localizedTitleHint(BuildContext context) {
    switch (this) {
      case SupportCategory.appGuide:
        return context.tr('support_hint_title_app_guide');
      case SupportCategory.bugReport:
        return context.tr('support_hint_title_bug_report');
      case SupportCategory.financialAdvisory:
        return context.tr('support_hint_title_financial_advisory');
      case SupportCategory.other:
        return context.tr('support_hint_title_other');
    }
  }

  String localizedDescHint(BuildContext context) {
    switch (this) {
      case SupportCategory.appGuide:
        return context.tr('support_hint_desc_app_guide');
      case SupportCategory.bugReport:
        return context.tr('support_hint_desc_bug_report');
      case SupportCategory.financialAdvisory:
        return context.tr('support_hint_desc_financial_advisory');
      case SupportCategory.other:
        return context.tr('support_hint_desc_other');
    }
  }

  IconData get icon {
    switch (this) {
      case SupportCategory.appGuide:
        return Icons.menu_book_outlined;
      case SupportCategory.bugReport:
        return Icons.bug_report_outlined;
      case SupportCategory.financialAdvisory:
        return Icons.savings_outlined;
      case SupportCategory.other:
        return Icons.help_outline_rounded;
    }
  }

  Color get accentColor {
    switch (this) {
      case SupportCategory.appGuide:
        return AppColors.primary;
      case SupportCategory.bugReport:
        return AppColors.expense;
      case SupportCategory.financialAdvisory:
        return AppColors.income;
      case SupportCategory.other:
        return AppColors.slate600;
    }
  }
}

/// 6 trạng thái xử lý chuẩn nghiệp vụ
enum SupportTicketStatus {
  newTicket('new'),
  inProgress('in_progress'),
  waitingForUser('waiting_for_user'),
  replied('replied'),
  resolved('resolved'),
  closed('closed');

  final String code;
  const SupportTicketStatus(this.code);

  static SupportTicketStatus fromCode(String? code) {
    final normalized = (code ?? '').trim();
    if (normalized == 'closed_unresolved') {
      return SupportTicketStatus.closed;
    }
    return SupportTicketStatus.values.firstWhere(
      (e) => e.code == normalized,
      orElse: () => SupportTicketStatus.newTicket,
    );
  }

  bool get isClosed => this == SupportTicketStatus.closed;
  bool get isResolved => this == SupportTicketStatus.resolved;
  bool get isCompleted =>
      this == SupportTicketStatus.resolved ||
      this == SupportTicketStatus.closed;
  bool get isActiveWork =>
      this == SupportTicketStatus.newTicket ||
      this == SupportTicketStatus.inProgress ||
      this == SupportTicketStatus.waitingForUser ||
      this == SupportTicketStatus.replied;
  bool get needsUserAction =>
      this == SupportTicketStatus.waitingForUser ||
      this == SupportTicketStatus.replied;
  bool get needsAdminAction =>
      this == SupportTicketStatus.newTicket ||
      this == SupportTicketStatus.inProgress;

  /// User chỉ được xác nhận đã giải quyết sau khi Admin đã tiếp nhận hoặc phản hồi
  bool get canUserConfirmResolved =>
      this == SupportTicketStatus.inProgress ||
      this == SupportTicketStatus.waitingForUser ||
      this == SupportTicketStatus.replied;

  /// Admin gửi phản hồi / yêu cầu bổ sung / đánh dấu giải quyết trên các yêu cầu đang xử lý
  bool get canAdminReply => isActiveWork;
  bool get canAdminMarkResolved => isActiveWork;
  bool get canAdminReopenResolved => this == SupportTicketStatus.resolved;
  bool get canAdminCloseResolved => this == SupportTicketStatus.resolved;
  bool get canAdminCloseUnresolved => isActiveWork;

  /// Nhãn tiếng Việt (dùng cho Admin Web & fallback)
  String get viLabel {
    switch (this) {
      case SupportTicketStatus.newTicket:
        return 'Mới tiếp nhận';
      case SupportTicketStatus.inProgress:
        return 'Đang xử lý';
      case SupportTicketStatus.waitingForUser:
        return 'Chờ người dùng phản hồi';
      case SupportTicketStatus.replied:
        return 'Đã phản hồi';
      case SupportTicketStatus.resolved:
        return 'Đã giải quyết';
      case SupportTicketStatus.closed:
        return 'Đã đóng';
    }
  }

  /// Nhãn theo ngôn ngữ hiện tại (User App)
  String localizedLabel(BuildContext context) {
    switch (this) {
      case SupportTicketStatus.newTicket:
        return context.tr('support_status_new');
      case SupportTicketStatus.inProgress:
        return context.tr('support_status_in_progress');
      case SupportTicketStatus.waitingForUser:
        return context.tr('support_status_waiting_user');
      case SupportTicketStatus.replied:
        return context.tr('support_status_replied');
      case SupportTicketStatus.resolved:
        return context.tr('support_status_resolved');
      case SupportTicketStatus.closed:
        return context.tr('support_status_closed');
    }
  }

  Color get color {
    switch (this) {
      case SupportTicketStatus.newTicket:
        return const Color(0xFF0284C7);
      case SupportTicketStatus.inProgress:
        return AppColors.primary;
      case SupportTicketStatus.waitingForUser:
        return AppColors.warning;
      case SupportTicketStatus.replied:
        return const Color(0xFF0D9488);
      case SupportTicketStatus.resolved:
        return AppColors.income;
      case SupportTicketStatus.closed:
        return AppColors.slate500;
    }
  }

  Color get backgroundColor {
    switch (this) {
      case SupportTicketStatus.newTicket:
        return const Color(0xFFE0F2FE);
      case SupportTicketStatus.inProgress:
        return AppColors.infoBackground;
      case SupportTicketStatus.waitingForUser:
        return AppColors.warningBackground;
      case SupportTicketStatus.replied:
        return const Color(0xFFCCFBF1);
      case SupportTicketStatus.resolved:
        return AppColors.incomeBackground;
      case SupportTicketStatus.closed:
        return AppColors.slate100;
    }
  }

  /// Tính trạng thái tiếp theo khi User gửi thêm tin nhắn
  SupportTicketStatus? nextStatusOnUserMessage() {
    switch (this) {
      case SupportTicketStatus.newTicket:
        return SupportTicketStatus.newTicket;
      case SupportTicketStatus.inProgress:
        return SupportTicketStatus.inProgress;
      case SupportTicketStatus.waitingForUser:
      case SupportTicketStatus.replied:
      case SupportTicketStatus.resolved:
        return SupportTicketStatus.inProgress;
      case SupportTicketStatus.closed:
        return null;
    }
  }
}

/// 4 mức độ ưu tiên xử lý chính thức (mặc định `normal` khi User tạo; Admin đánh giá & điều chỉnh)
enum SupportPriority {
  low('low'),
  normal('normal'),
  high('high'),
  urgent('urgent');

  final String code;
  const SupportPriority(this.code);

  static SupportPriority fromCode(String? code) {
    final normalized = (code ?? '').trim();
    return SupportPriority.values.firstWhere(
      (e) => e.code == normalized,
      orElse: () => SupportPriority.normal,
    );
  }

  int get sortWeight {
    switch (this) {
      case SupportPriority.low:
        return 1;
      case SupportPriority.normal:
        return 2;
      case SupportPriority.high:
        return 3;
      case SupportPriority.urgent:
        return 4;
    }
  }

  String get viLabel {
    switch (this) {
      case SupportPriority.low:
        return 'Thấp';
      case SupportPriority.normal:
        return 'Bình thường';
      case SupportPriority.high:
        return 'Cao';
      case SupportPriority.urgent:
        return 'Khẩn cấp';
    }
  }

  String localizedLabel(BuildContext context) {
    switch (this) {
      case SupportPriority.low:
        return context.tr('support_priority_low');
      case SupportPriority.normal:
        return context.tr('support_priority_normal');
      case SupportPriority.high:
        return context.tr('support_priority_high');
      case SupportPriority.urgent:
        return context.tr('support_priority_urgent');
    }
  }

  Color get color {
    switch (this) {
      case SupportPriority.low:
        return AppColors.slate600;
      case SupportPriority.normal:
        return AppColors.primary;
      case SupportPriority.high:
        return AppColors.warning;
      case SupportPriority.urgent:
        return AppColors.expense;
    }
  }

  Color get backgroundColor {
    switch (this) {
      case SupportPriority.low:
        return AppColors.slate100;
      case SupportPriority.normal:
        return AppColors.infoBackground;
      case SupportPriority.high:
        return AppColors.warningBackground;
      case SupportPriority.urgent:
        return AppColors.expenseBackground;
    }
  }

  IconData get icon {
    switch (this) {
      case SupportPriority.low:
        return Icons.keyboard_arrow_down_rounded;
      case SupportPriority.normal:
        return Icons.remove_rounded;
      case SupportPriority.high:
        return Icons.keyboard_arrow_up_rounded;
      case SupportPriority.urgent:
        return Icons.priority_high_rounded;
    }
  }
}

/// Mức độ ảnh hưởng do Người dùng mô tả khi tạo yêu cầu (bất biến, tham khảo cho Admin)
enum SupportUserImpact {
  low('low'),
  normal('normal'),
  high('high'),
  blocking('blocking');

  final String code;
  const SupportUserImpact(this.code);

  static SupportUserImpact? tryFromCode(String? code) {
    final normalized = (code ?? '').trim();
    if (normalized.isEmpty) return null;
    for (final item in SupportUserImpact.values) {
      if (item.code == normalized) return item;
    }
    return null;
  }

  String get viLabel {
    switch (this) {
      case SupportUserImpact.low:
        return 'Thấp · Câu hỏi chung';
      case SupportUserImpact.normal:
        return 'Trung bình · Ảnh hưởng một phần';
      case SupportUserImpact.high:
        return 'Cao · Cản trở thao tác chính';
      case SupportUserImpact.blocking:
        return 'Rất cao · Không thể dùng chức năng';
    }
  }

  String localizedLabel(BuildContext context) {
    switch (this) {
      case SupportUserImpact.low:
        return context.tr('support_impact_low');
      case SupportUserImpact.normal:
        return context.tr('support_impact_normal');
      case SupportUserImpact.high:
        return context.tr('support_impact_high');
      case SupportUserImpact.blocking:
        return context.tr('support_impact_blocking');
    }
  }

  String localizedDescription(BuildContext context) {
    switch (this) {
      case SupportUserImpact.low:
        return context.tr('support_impact_low_desc');
      case SupportUserImpact.normal:
        return context.tr('support_impact_normal_desc');
      case SupportUserImpact.high:
        return context.tr('support_impact_high_desc');
      case SupportUserImpact.blocking:
        return context.tr('support_impact_blocking_desc');
    }
  }
}

/// Lý do đóng yêu cầu: tách rõ đóng chuẩn sau giải quyết vs đóng ngoại lệ chưa giải quyết
enum SupportCloseReason {
  completed('completed'),
  duplicate('duplicate'),
  outOfScope('out_of_scope'),
  noUserResponse('no_user_response'),
  invalidRequest('invalid_request');

  final String code;
  const SupportCloseReason(this.code);

  static const List<SupportCloseReason> unresolvedReasons = [
    SupportCloseReason.duplicate,
    SupportCloseReason.outOfScope,
    SupportCloseReason.noUserResponse,
    SupportCloseReason.invalidRequest,
  ];

  static SupportCloseReason? tryFromCode(String? code) {
    final normalized = (code ?? '').trim();
    if (normalized.isEmpty) return null;
    for (final item in SupportCloseReason.values) {
      if (item.code == normalized) return item;
    }
    return null;
  }

  bool get isUnresolvedException => this != SupportCloseReason.completed;

  String get viLabel {
    switch (this) {
      case SupportCloseReason.completed:
        return 'Hoàn tất sau khi đã giải quyết';
      case SupportCloseReason.duplicate:
        return 'Trùng lặp yêu cầu đã có';
      case SupportCloseReason.outOfScope:
        return 'Ngoài phạm vi hỗ trợ của ứng dụng';
      case SupportCloseReason.noUserResponse:
        return 'Người dùng ngừng phản hồi kéo dài';
      case SupportCloseReason.invalidRequest:
        return 'Yêu cầu không hợp lệ hoặc thiếu căn cứ xử lý';
    }
  }

  String localizedLabel(BuildContext context) {
    switch (this) {
      case SupportCloseReason.completed:
        return context.tr('support_close_reason_completed');
      case SupportCloseReason.duplicate:
        return context.tr('support_close_reason_duplicate');
      case SupportCloseReason.outOfScope:
        return context.tr('support_close_reason_out_of_scope');
      case SupportCloseReason.noUserResponse:
        return context.tr('support_close_reason_no_user_response');
      case SupportCloseReason.invalidRequest:
        return context.tr('support_close_reason_invalid_request');
    }
  }
}

/// Thông tin kỹ thuật cơ bản đính kèm an toàn cho nhóm Báo lỗi hoặc sự cố
class SupportTechnicalInfo {
  final String appVersion;
  final String platform;
  final String? osVersion;
  final DateTime capturedAt;

  const SupportTechnicalInfo({
    required this.appVersion,
    required this.platform,
    this.osVersion,
    required this.capturedAt,
  });

  String get summaryLine {
    final parts = <String>[
      'App v$appVersion',
      platform,
      if (osVersion != null && osVersion!.trim().isNotEmpty) osVersion!.trim(),
    ];
    return parts.join(' · ');
  }

  static SupportTechnicalInfo? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    final appVersion = (raw['appVersion'] ?? '').toString().trim();
    final platform = (raw['platform'] ?? '').toString().trim();
    if (appVersion.isEmpty || platform.isEmpty) return null;
    final rawOs = raw['osVersion']?.toString().trim();
    return SupportTechnicalInfo(
      appVersion: appVersion,
      platform: platform,
      osVersion: (rawOs != null && rawOs.isNotEmpty) ? rawOs : null,
      capturedAt: _parseSupportDate(raw['capturedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    final cleanOs = osVersion?.trim();
    return {
      'appVersion': appVersion.trim(),
      'platform': platform.trim(),
      if (cleanOs != null && cleanOs.isNotEmpty) 'osVersion': cleanOs,
      'capturedAt': capturedAt.toUtc().toIso8601String(),
    };
  }
}

/// Vai trò người gửi tin nhắn trong cuộc trao đổi
enum SupportSenderRole {
  user('user'),
  admin('admin'),
  system('system');

  final String code;
  const SupportSenderRole(this.code);

  static SupportSenderRole fromCode(String? code) {
    final normalized = (code ?? '').trim();
    return SupportSenderRole.values.firstWhere(
      (e) => e.code == normalized,
      orElse: () => SupportSenderRole.user,
    );
  }
}

/// Loại nội dung tin nhắn
enum SupportMessageType {
  text('text'),
  requestInfo('request_info'),
  statusChange('status_change');

  final String code;
  const SupportMessageType(this.code);

  static SupportMessageType fromCode(String? code) {
    final normalized = (code ?? '').trim();
    return SupportMessageType.values.firstWhere(
      (e) => e.code == normalized,
      orElse: () => SupportMessageType.text,
    );
  }
}

DateTime _parseSupportDate(dynamic raw) {
  if (raw is DateTime) return raw;
  if (raw is String && raw.trim().isNotEmpty) {
    return DateTime.tryParse(raw.trim()) ?? DateTime.now().toUtc();
  }
  if (raw != null) {
    try {
      return (raw as dynamic).toDate() as DateTime;
    } catch (_) {}
  }
  return DateTime.now().toUtc();
}

DateTime? _parseNullableSupportDate(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  if (raw is String && raw.trim().isNotEmpty) {
    return DateTime.tryParse(raw.trim());
  }
  try {
    return (raw as dynamic).toDate() as DateTime;
  } catch (_) {
    return null;
  }
}

int? _parseNullableInt(dynamic raw) {
  if (raw == null) return null;
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw.toString().trim());
}

/// Model Yêu cầu hỗ trợ & tư vấn (`support_tickets/{ticketId}`)
class SupportTicket {
  static const int kMinTitleLength = 5;
  static const int kMaxTitleLength = 120;
  static const int kMinDescriptionLength = 10;
  static const int kMaxDescriptionLength = 2000;
  static const int kMaxMessageLength = 2000;
  static const int kMaxSharedContextLength = 800;
  static const int kMaxPreviewLength = 200;
  static const int kMaxRatingCommentLength = 500;
  static const int kMaxRatingEditCount = 1;

  final String ticketId;
  final String ticketCode;
  final String userId;
  final String userName;
  final String userEmail;
  final SupportCategory category;
  final String title;
  final String description;
  final String? sharedContext;
  final SupportTicketStatus status;
  final SupportPriority priority;
  final SupportUserImpact? userImpact;
  final SupportTechnicalInfo? technicalInfo;
  final String? relatedTicketId;
  final String? relatedTicketCode;
  final String? assignedAdminId;
  final String? assignedAdminName;
  final String? lastMessageId;
  final String lastMessagePreview;
  final SupportSenderRole lastMessageSenderRole;
  final DateTime lastMessageAt;
  final bool unreadByAdmin;
  final bool unreadByUser;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? claimedAt;
  final DateTime? firstAdminResponseAt;
  final DateTime? resolvedAt;
  final String? resolvedByRole; // 'admin' | 'user' | null
  final DateTime? closedAt;
  final SupportCloseReason? closeReason;
  final int? ratingScore; // 1..5
  final String? ratingComment;
  final DateTime? ratedAt;
  final DateTime? ratingUpdatedAt;
  final int ratingEditCount;

  const SupportTicket({
    required this.ticketId,
    required this.ticketCode,
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.category,
    required this.title,
    required this.description,
    this.sharedContext,
    required this.status,
    this.priority = SupportPriority.normal,
    this.userImpact,
    this.technicalInfo,
    this.relatedTicketId,
    this.relatedTicketCode,
    this.assignedAdminId,
    this.assignedAdminName,
    this.lastMessageId,
    required this.lastMessagePreview,
    required this.lastMessageSenderRole,
    required this.lastMessageAt,
    required this.unreadByAdmin,
    required this.unreadByUser,
    required this.createdAt,
    required this.updatedAt,
    this.claimedAt,
    this.firstAdminResponseAt,
    this.resolvedAt,
    this.resolvedByRole,
    this.closedAt,
    this.closeReason,
    this.ratingScore,
    this.ratingComment,
    this.ratedAt,
    this.ratingUpdatedAt,
    this.ratingEditCount = 0,
  });

  bool get isClosed => status.isClosed;
  bool get isResolved => status.isResolved;
  bool get hasRating =>
      ratingScore != null && ratingScore! >= 1 && ratingScore! <= 5;
  bool get canUserConfirmResolved => status.canUserConfirmResolved;
  bool get canUserSubmitRating => isResolved && !hasRating;
  bool get canUserEditRating =>
      isResolved && hasRating && ratingEditCount < kMaxRatingEditCount;
  bool get hasRelatedTicket =>
      relatedTicketId != null &&
      relatedTicketId!.isNotEmpty &&
      relatedTicketCode != null &&
      relatedTicketCode!.isNotEmpty;

  /// Ticket đóng chuẩn sau khi đã giải quyết (phân biệt với đóng ngoại lệ chưa giải quyết)
  bool get isClosedAfterResolved =>
      isClosed &&
      resolvedAt != null &&
      (closeReason == null || closeReason == SupportCloseReason.completed);

  /// Ticket đóng ngoại lệ khi chưa giải quyết (resolvedAt == null hoặc lý do ngoại lệ)
  bool get isClosedUnresolved =>
      isClosed &&
      (resolvedAt == null ||
          (closeReason != null && closeReason!.isUnresolvedException));

  static String buildPreview(String text) {
    final compact = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (compact.length <= kMaxPreviewLength) return compact;
    return '${compact.substring(0, kMaxPreviewLength - 3)}...';
  }

  static String generateTicketCode(String docId, DateTime nowUtc) {
    final yy = (nowUtc.year % 100).toString().padLeft(2, '0');
    final mm = nowUtc.month.toString().padLeft(2, '0');
    final dd = nowUtc.day.toString().padLeft(2, '0');
    final cleanId =
        docId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
    final suffix = cleanId.length >= 4
        ? cleanId.substring(0, 4)
        : cleanId.padRight(4, 'X');
    return 'SUP-$yy$mm$dd-$suffix';
  }

  factory SupportTicket.fromMap(Map<String, dynamic> map, String id) {
    final created = _parseSupportDate(map['createdAt']);
    final updated = _parseNullableSupportDate(map['updatedAt']) ?? created;
    final lastMsgAt =
        _parseNullableSupportDate(map['lastMessageAt']) ?? updated;
    final rawShared = map['sharedContext']?.toString().trim();
    final rawRelatedId = map['relatedTicketId']?.toString().trim();
    final rawRelatedCode = map['relatedTicketCode']?.toString().trim();
    final rawLastMsgId = map['lastMessageId']?.toString().trim();
    final rawResolvedBy = map['resolvedByRole']?.toString().trim();
    final rawRatingComment = map['ratingComment']?.toString().trim();
    final parsedScore = _parseNullableInt(map['ratingScore']);
    final validScore =
        (parsedScore != null && parsedScore >= 1 && parsedScore <= 5)
            ? parsedScore
            : null;
    final parsedEditCount = _parseNullableInt(map['ratingEditCount']) ?? 0;

    return SupportTicket(
      ticketId: (map['ticketId'] as String?)?.trim().isNotEmpty == true
          ? (map['ticketId'] as String).trim()
          : id,
      ticketCode: (map['ticketCode'] as String?)?.trim().isNotEmpty == true
          ? (map['ticketCode'] as String).trim()
          : generateTicketCode(id, created.toUtc()),
      userId: (map['userId'] ?? '').toString(),
      userName: (map['userName'] ?? '').toString(),
      userEmail: (map['userEmail'] ?? '').toString(),
      category: SupportCategory.fromCode(map['category']?.toString()),
      title: (map['title'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      sharedContext:
          (rawShared != null && rawShared.isNotEmpty) ? rawShared : null,
      status: SupportTicketStatus.fromCode(map['status']?.toString()),
      priority: SupportPriority.fromCode(map['priority']?.toString()),
      userImpact: SupportUserImpact.tryFromCode(map['userImpact']?.toString()),
      technicalInfo: SupportTechnicalInfo.fromMap(map['technicalInfo']),
      relatedTicketId: (rawRelatedId != null && rawRelatedId.isNotEmpty)
          ? rawRelatedId
          : null,
      relatedTicketCode: (rawRelatedCode != null && rawRelatedCode.isNotEmpty)
          ? rawRelatedCode
          : null,
      assignedAdminId:
          (map['assignedAdminId'] as String?)?.trim().isNotEmpty == true
              ? (map['assignedAdminId'] as String).trim()
              : null,
      assignedAdminName:
          (map['assignedAdminName'] as String?)?.trim().isNotEmpty == true
              ? (map['assignedAdminName'] as String).trim()
              : null,
      lastMessageId: (rawLastMsgId != null && rawLastMsgId.isNotEmpty)
          ? rawLastMsgId
          : null,
      lastMessagePreview: (map['lastMessagePreview'] ?? '').toString(),
      lastMessageSenderRole:
          SupportSenderRole.fromCode(map['lastMessageSenderRole']?.toString()),
      lastMessageAt: lastMsgAt,
      unreadByAdmin: map['unreadByAdmin'] == true,
      unreadByUser: map['unreadByUser'] == true,
      createdAt: created,
      updatedAt: updated,
      claimedAt: _parseNullableSupportDate(map['claimedAt']),
      firstAdminResponseAt: _parseNullableSupportDate(
        map['firstAdminResponseAt'],
      ),
      resolvedAt: _parseNullableSupportDate(map['resolvedAt']),
      resolvedByRole: (rawResolvedBy == 'admin' || rawResolvedBy == 'user')
          ? rawResolvedBy
          : null,
      closedAt: _parseNullableSupportDate(map['closedAt']),
      closeReason: SupportCloseReason.tryFromCode(
        map['closeReason']?.toString(),
      ),
      ratingScore: validScore,
      ratingComment: (rawRatingComment != null && rawRatingComment.isNotEmpty)
          ? rawRatingComment
          : null,
      ratedAt: _parseNullableSupportDate(map['ratedAt']),
      ratingUpdatedAt: _parseNullableSupportDate(map['ratingUpdatedAt']),
      ratingEditCount: parsedEditCount < 0 ? 0 : parsedEditCount,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'ticketId': ticketId,
      'ticketCode': ticketCode,
      'userId': userId,
      'userName': userName,
      'userEmail': userEmail,
      'category': category.code,
      'title': title,
      'description': description,
      if (sharedContext != null && sharedContext!.trim().isNotEmpty)
        'sharedContext': sharedContext!.trim(),
      'status': status.code,
      'priority': priority.code,
      if (userImpact != null) 'userImpact': userImpact!.code,
      if (technicalInfo != null) 'technicalInfo': technicalInfo!.toMap(),
      if (hasRelatedTicket) 'relatedTicketId': relatedTicketId,
      if (hasRelatedTicket) 'relatedTicketCode': relatedTicketCode,
      'assignedAdminId': assignedAdminId,
      'assignedAdminName': assignedAdminName,
      if (lastMessageId != null && lastMessageId!.isNotEmpty)
        'lastMessageId': lastMessageId,
      'lastMessagePreview': lastMessagePreview,
      'lastMessageSenderRole': lastMessageSenderRole.code,
      'lastMessageAt': lastMessageAt.toUtc().toIso8601String(),
      'unreadByAdmin': unreadByAdmin,
      'unreadByUser': unreadByUser,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'claimedAt': claimedAt?.toUtc().toIso8601String(),
      'firstAdminResponseAt': firstAdminResponseAt?.toUtc().toIso8601String(),
      'resolvedAt': resolvedAt?.toUtc().toIso8601String(),
      'resolvedByRole': resolvedByRole,
      'closedAt': closedAt?.toUtc().toIso8601String(),
      'closeReason': closeReason?.code,
      'ratingScore': ratingScore,
      'ratingComment': ratingComment,
      'ratedAt': ratedAt?.toUtc().toIso8601String(),
      'ratingUpdatedAt': ratingUpdatedAt?.toUtc().toIso8601String(),
      'ratingEditCount': ratingEditCount,
    };
  }
}

/// Model Tin nhắn trong yêu cầu hỗ trợ (`support_tickets/{ticketId}/messages/{messageId}`)
class SupportMessage {
  final String messageId;
  final String senderId;
  final SupportSenderRole senderRole;
  final String senderDisplayName;
  final String body;
  final SupportMessageType messageType;
  final DateTime createdAt;

  const SupportMessage({
    required this.messageId,
    required this.senderId,
    required this.senderRole,
    required this.senderDisplayName,
    required this.body,
    required this.messageType,
    required this.createdAt,
  });

  factory SupportMessage.fromMap(Map<String, dynamic> map, String id) {
    return SupportMessage(
      messageId: (map['messageId'] as String?)?.trim().isNotEmpty == true
          ? (map['messageId'] as String).trim()
          : id,
      senderId: (map['senderId'] ?? '').toString(),
      senderRole: SupportSenderRole.fromCode(map['senderRole']?.toString()),
      senderDisplayName: (map['senderDisplayName'] ?? '').toString(),
      body: (map['body'] ?? '').toString(),
      messageType: SupportMessageType.fromCode(map['messageType']?.toString()),
      createdAt: _parseSupportDate(map['createdAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'messageId': messageId,
      'senderId': senderId,
      'senderRole': senderRole.code,
      'senderDisplayName': senderDisplayName,
      'body': body,
      'messageType': messageType.code,
      'createdAt': createdAt.toUtc().toIso8601String(),
    };
  }
}

/// Mẫu phản hồi nhanh hỗ trợ thao tác cho Admin (chỉ chèn vào ô soạn, không tự động gửi)
class SupportQuickReplyTemplate {
  final String id;
  final String title;
  final SupportCategory? category;
  final String body;
  final bool suggestsRequestMoreInfo;

  const SupportQuickReplyTemplate({
    required this.id,
    required this.title,
    this.category,
    required this.body,
    this.suggestsRequestMoreInfo = false,
  });
}

class SupportQuickReplyTemplates {
  static const List<SupportQuickReplyTemplate> defaults = [
    SupportQuickReplyTemplate(
      id: 'ack_in_progress',
      title: 'Thông báo đã tiếp nhận & đang kiểm tra',
      body:
          'Chào bạn, đội ngũ hỗ trợ đã tiếp nhận yêu cầu của bạn và đang kiểm tra chi tiết. Mình sẽ phản hồi ngay khi có kết quả cụ thể.',
    ),
    SupportQuickReplyTemplate(
      id: 'request_more_info',
      title: 'Yêu cầu người dùng bổ sung thông tin',
      suggestsRequestMoreInfo: true,
      body:
          'Để hỗ trợ bạn chính xác hơn, bạn vui lòng cung cấp thêm giúp mình:\n1. Màn hình hoặc chức năng bạn đang thao tác.\n2. Các bước thực hiện ngay trước khi gặp vấn đề.\n3. Thời điểm xảy ra sự cố (nếu nhớ).',
    ),
    SupportQuickReplyTemplate(
      id: 'guide_create_transaction',
      title: 'Hướng dẫn tạo giao dịch mới',
      category: SupportCategory.appGuide,
      body:
          'Để tạo giao dịch mới, bạn nhấn nút dấu (+) ở thanh điều hướng phía dưới ➔ chọn loại Thu nhập, Chi tiêu hoặc Chuyển khoản ➔ nhập số tiền, chọn ví, danh mục và ghi chú (nếu cần) ➔ nhấn Lưu. Nếu cần nhập nhanh các khoản quen thuộc, bạn có thể tạo mẫu nhanh ngay trên màn hình thêm giao dịch.',
    ),
    SupportQuickReplyTemplate(
      id: 'guide_setup_budget',
      title: 'Hướng dẫn thiết lập ngân sách tháng',
      category: SupportCategory.appGuide,
      body:
          'Để thiết lập ngân sách, bạn vào mục Quản lý (hoặc Cá nhân) ➔ Ngân sách tháng ➔ chọn tháng cần lập ➔ nhấn Tạo/Chỉnh sửa ngân sách cho từng danh mục chi tiêu. Ứng dụng sẽ tự động tính toán mức đã chi theo các giao dịch thực tế trong tháng và cảnh báo khi gần chạm hạn mức.',
    ),
    SupportQuickReplyTemplate(
      id: 'guide_saving_goal',
      title: 'Hướng dẫn sử dụng mục tiêu tiết kiệm',
      category: SupportCategory.appGuide,
      body:
          'Để tạo và theo dõi mục tiêu tiết kiệm, bạn vào mục Mục tiêu tiết kiệm ➔ nhấn dấu (+) để nhập tên mục tiêu, số tiền mục tiêu và hạn hoàn thành. Khi muốn nạp thêm tiền vào mục tiêu, bạn mở mục tiêu đó ➔ chọn Nạp tiền và chọn ví nguồn để hệ thống ghi nhận đồng bộ.',
    ),
    SupportQuickReplyTemplate(
      id: 'guide_login_issue',
      title: 'Hướng dẫn xử lý lỗi đăng nhập',
      category: SupportCategory.bugReport,
      body:
          'Khi gặp lỗi đăng nhập, bạn vui lòng kiểm tra giúp mình:\n1. Kiểm tra lại kết nối mạng ổn định.\n2. Xác nhận đúng địa chỉ email đã đăng ký (hoặc phương thức đăng nhập Google nếu bạn tạo tài khoản bằng Google).\n3. Nếu quên mật khẩu, chọn "Quên mật khẩu" tại màn hình đăng nhập để đặt lại.\nNếu vẫn chưa đăng nhập được, bạn hãy cho mình biết thông báo lỗi hiển thị trên màn hình nhé.',
    ),
    SupportQuickReplyTemplate(
      id: 'guide_recurring_tx',
      title: 'Hướng dẫn tạo giao dịch định kỳ',
      category: SupportCategory.appGuide,
      body:
          'Để cài đặt nhắc nhở hoặc tự động ghi nhận khoản thu/chi định kỳ (tiền nhà, tiền điện, lương...), bạn vào Cá nhân ➔ Giao dịch định kỳ ➔ nhấn dấu (+) ➔ điền thông tin khoản tiền, chu kỳ lặp lại và ngày đến hạn rồi lưu lại.',
    ),
    SupportQuickReplyTemplate(
      id: 'advisory_general_framework',
      title: 'Gợi ý khung phân bổ tài chính cơ bản',
      category: SupportCategory.financialAdvisory,
      body:
          'Với nhu cầu quản lý tài chính cá nhân, bạn có thể bắt đầu bằng 3 bước:\n1. Xác định tổng chi phí thiết yếu cố định hàng tháng (nhà ở, ăn uống cơ bản, hóa đơn).\n2. Thiết lập ngân sách cho từng nhóm chi tiêu linh hoạt để tránh vượt kế hoạch.\n3. Trích trước một tỷ lệ tiết kiệm phù hợp ngay khi có thu nhập vào mục tiêu dự phòng.\nNếu bạn muốn gợi ý sát hơn, bạn có thể chia sẻ thêm mức chi cố định hoặc mục tiêu tiết kiệm dự kiến của mình nhé.',
    ),
  ];

  /// Sắp xếp đưa các mẫu khớp với `category` hiện tại lên trước để Admin chọn nhanh
  static List<SupportQuickReplyTemplate> orderedForCategory(
    SupportCategory? category,
  ) {
    final list = List<SupportQuickReplyTemplate>.from(defaults);
    if (category == null) return list;
    list.sort((a, b) {
      final aMatch = a.category == category ? 0 : (a.category == null ? 1 : 2);
      final bMatch = b.category == category ? 0 : (b.category == null ? 1 : 2);
      return aMatch.compareTo(bMatch);
    });
    return list;
  }
}

/// Theo dõi thời gian xử lý & dấu hiệu tồn đọng từ dữ liệu mốc thời gian thực tế
/// (Không đặt SLA hay cam kết thời gian phản hồi cố định)
class SupportTimeTracker {
  /// Ngưỡng tham khảo hiển thị dấu hiệu tồn đọng/kéo dài để Admin dễ rà soát
  static const Duration kLongRunningOpenThreshold = Duration(hours: 48);
  static const Duration kAdminPendingAgingThreshold = Duration(hours: 24);

  static String formatDurationVi(Duration duration) {
    final safe = duration.isNegative ? Duration.zero : duration;
    if (safe.inMinutes < 1) return 'vừa xong';
    if (safe.inMinutes < 60) return '${safe.inMinutes} phút';
    if (safe.inHours < 24) {
      final mins = safe.inMinutes % 60;
      if (mins >= 15 && safe.inHours < 6) {
        return '${safe.inHours} giờ $mins phút';
      }
      return '${safe.inHours} giờ';
    }
    final days = safe.inDays;
    final hours = safe.inHours % 24;
    if (hours > 0 && days < 7) {
      return '$days ngày $hours giờ';
    }
    return '$days ngày';
  }

  /// Thời gian đã mở tính từ lúc tạo (với ticket chưa hoàn tất)
  static Duration openElapsed(SupportTicket ticket, {DateTime? now}) {
    final ref = (now ?? DateTime.now()).toUtc();
    final created = ticket.createdAt.toUtc();
    if (ref.isBefore(created)) return Duration.zero;
    return ref.difference(created);
  }

  /// Thời gian kể từ mốc trao đổi gần nhất
  static Duration sinceLastMessage(SupportTicket ticket, {DateTime? now}) {
    final ref = (now ?? DateTime.now()).toUtc();
    final last = ticket.lastMessageAt.toUtc();
    if (ref.isBefore(last)) return Duration.zero;
    return ref.difference(last);
  }

  /// Thời gian đang xử lý (từ `claimedAt` nếu có, fallback `createdAt`)
  static Duration processingElapsed(SupportTicket ticket, {DateTime? now}) {
    final ref = (now ?? DateTime.now()).toUtc();
    final start = (ticket.claimedAt ?? ticket.createdAt).toUtc();
    if (ref.isBefore(start)) return Duration.zero;
    return ref.difference(start);
  }

  /// Thời gian hoàn tất thực tế — CHỈ tính khi có `resolvedAt != null`
  /// (không tính cho ticket đóng ngoại lệ chưa giải quyết)
  static Duration? resolutionDuration(SupportTicket ticket) {
    if (ticket.resolvedAt == null) return null;
    final diff = ticket.resolvedAt!.toUtc().difference(ticket.createdAt.toUtc());
    return diff.isNegative ? Duration.zero : diff;
  }

  /// Dấu hiệu yêu cầu chưa hoàn tất nhưng đã kéo dài để Admin chủ động rà soát
  static bool isAgingOpen(SupportTicket ticket, {DateTime? now}) {
    if (ticket.status.isCompleted) return false;
    final open = openElapsed(ticket, now: now);
    if (open >= kLongRunningOpenThreshold) return true;
    if (ticket.status.needsAdminAction &&
        sinceLastMessage(ticket, now: now) >= kAdminPendingAgingThreshold) {
      return true;
    }
    return false;
  }

  /// Nhãn ngắn gọn theo trạng thái hiện tại để hiển thị trong danh sách Admin
  static String statusElapsedLabel(SupportTicket ticket, {DateTime? now}) {
    switch (ticket.status) {
      case SupportTicketStatus.newTicket:
        return 'Mới · ${formatDurationVi(openElapsed(ticket, now: now))}';
      case SupportTicketStatus.inProgress:
        return 'Đang xử lý · ${formatDurationVi(processingElapsed(ticket, now: now))}';
      case SupportTicketStatus.waitingForUser:
        return 'Chờ user · ${formatDurationVi(sinceLastMessage(ticket, now: now))}';
      case SupportTicketStatus.replied:
        final sinceReply = sinceLastMessage(ticket, now: now);
        final formattedReply = formatDurationVi(sinceReply);
        return formattedReply == 'vừa xong'
            ? 'Đã phản hồi · vừa xong'
            : 'Đã phản hồi · $formattedReply trước';
      case SupportTicketStatus.resolved:
        final resDur = resolutionDuration(ticket);
        return resDur != null
            ? 'Giải quyết sau ${formatDurationVi(resDur)}'
            : 'Đã giải quyết';
      case SupportTicketStatus.closed:
        if (ticket.isClosedUnresolved) {
          return 'Đóng (chưa giải quyết)';
        }
        final resDur = resolutionDuration(ticket);
        return resDur != null
            ? 'Hoàn tất sau ${formatDurationVi(resDur)}'
            : 'Đã đóng';
    }
  }
}

/// Thống kê đánh giá chất lượng tính trực tiếp trong bộ nhớ từ tập ticket đã tải
/// (0 lượt đọc Firestore bổ sung)
class SupportRatingStats {
  final int totalLoadedTickets;
  final int ratedCount;
  final double? averageScore;
  final Map<int, int> distribution; // 1..5 -> count
  final List<SupportTicket> attentionTickets; // ratingScore <= 3

  const SupportRatingStats({
    required this.totalLoadedTickets,
    required this.ratedCount,
    required this.averageScore,
    required this.distribution,
    required this.attentionTickets,
  });

  int get attentionCount => attentionTickets.length;

  factory SupportRatingStats.fromTickets(List<SupportTicket> tickets) {
    final dist = <int, int>{5: 0, 4: 0, 3: 0, 2: 0, 1: 0};
    int rated = 0;
    int scoreSum = 0;
    final attention = <SupportTicket>[];

    for (final t in tickets) {
      if (!t.hasRating) continue;
      final score = t.ratingScore!;
      rated++;
      scoreSum += score;
      dist[score] = (dist[score] ?? 0) + 1;
      if (score <= 3) {
        attention.add(t);
      }
    }

    attention.sort((a, b) {
      final scoreCmp = (a.ratingScore ?? 5).compareTo(b.ratingScore ?? 5);
      if (scoreCmp != 0) return scoreCmp;
      return (b.ratingUpdatedAt ?? b.ratedAt ?? b.updatedAt)
          .compareTo(a.ratingUpdatedAt ?? a.ratedAt ?? a.updatedAt);
    });

    return SupportRatingStats(
      totalLoadedTickets: tickets.length,
      ratedCount: rated,
      averageScore: rated > 0 ? scoreSum / rated : null,
      distribution: Map.unmodifiable(dist),
      attentionTickets: List.unmodifiable(attention),
    );
  }
}

/// Thống kê tổng quan hỗ trợ được tính hoàn toàn từ tập dữ liệu đã tải
class SupportOverviewStats {
  final int total;
  final int newCount;
  final int inProgressCount;
  final int waitingReplyCount; // waiting_for_user + replied
  final int waitingForUserCount;
  final int repliedCount;
  final int resolvedAndClosedCount; // resolved + closed
  final int resolvedCount;
  final int closedCompletedCount;
  final int closedUnresolvedCount;
  final int unreadByAdminCount;
  final int agingOpenCount;
  final int highOrUrgentOpenCount;

  const SupportOverviewStats({
    required this.total,
    required this.newCount,
    required this.inProgressCount,
    required this.waitingReplyCount,
    this.waitingForUserCount = 0,
    this.repliedCount = 0,
    required this.resolvedAndClosedCount,
    this.resolvedCount = 0,
    this.closedCompletedCount = 0,
    this.closedUnresolvedCount = 0,
    required this.unreadByAdminCount,
    this.agingOpenCount = 0,
    this.highOrUrgentOpenCount = 0,
  });

  int get closedTotalCount => closedCompletedCount + closedUnresolvedCount;

  factory SupportOverviewStats.fromTickets(
    List<SupportTicket> tickets, {
    DateTime? now,
  }) {
    int newCount = 0;
    int inProgress = 0;
    int waitingUser = 0;
    int replied = 0;
    int resolved = 0;
    int closedCompleted = 0;
    int closedUnresolved = 0;
    int unreadAdmin = 0;
    int agingOpen = 0;
    int highOrUrgentOpen = 0;

    for (final t in tickets) {
      if (t.unreadByAdmin) unreadAdmin++;
      if (!t.status.isCompleted) {
        if (SupportTimeTracker.isAgingOpen(t, now: now)) {
          agingOpen++;
        }
        if (t.priority == SupportPriority.high ||
            t.priority == SupportPriority.urgent) {
          highOrUrgentOpen++;
        }
      }
      switch (t.status) {
        case SupportTicketStatus.newTicket:
          newCount++;
          break;
        case SupportTicketStatus.inProgress:
          inProgress++;
          break;
        case SupportTicketStatus.waitingForUser:
          waitingUser++;
          break;
        case SupportTicketStatus.replied:
          replied++;
          break;
        case SupportTicketStatus.resolved:
          resolved++;
          break;
        case SupportTicketStatus.closed:
          if (t.isClosedUnresolved) {
            closedUnresolved++;
          } else {
            closedCompleted++;
          }
          break;
      }
    }

    return SupportOverviewStats(
      total: tickets.length,
      newCount: newCount,
      inProgressCount: inProgress,
      waitingReplyCount: waitingUser + replied,
      waitingForUserCount: waitingUser,
      repliedCount: replied,
      resolvedAndClosedCount: resolved + closedCompleted + closedUnresolved,
      resolvedCount: resolved,
      closedCompletedCount: closedCompleted,
      closedUnresolvedCount: closedUnresolved,
      unreadByAdminCount: unreadAdmin,
      agingOpenCount: agingOpen,
      highOrUrgentOpenCount: highOrUrgentOpen,
    );
  }
}

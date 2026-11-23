import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_ai_app/admin_web/screens/admin_support_center_view.dart';
import 'package:finance_ai_app/admin_web/screens/admin_web_shell_screen.dart';
import 'package:finance_ai_app/admin_web/services/admin_web_service.dart';
import 'package:finance_ai_app/models/support_ticket_model.dart';
import 'package:finance_ai_app/models/user_model.dart';
import 'package:finance_ai_app/screens/notification_screen.dart';
import 'package:finance_ai_app/screens/support/create_support_ticket_screen.dart';
import 'package:finance_ai_app/screens/support/support_center_screen.dart';
import 'package:finance_ai_app/screens/support/support_ticket_detail_screen.dart';
import 'package:finance_ai_app/services/firestore_service.dart';
import 'package:finance_ai_app/services/support_service.dart';

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late FirestoreService firestoreService;
  late SupportService supportService;
  late AdminWebService adminService;

  setUp(() async {
    fakeFirestore = FakeFirebaseFirestore();
    firestoreService = FirestoreService(firestore: fakeFirestore);
    supportService = SupportService(firestore: fakeFirestore);
    adminService = AdminWebService(
      firestoreService: firestoreService,
      cloudCaller: (fn, payload) async {
        if (fn == 'adminListUsers') {
          final snap = await fakeFirestore.collection('users').get();
          final users = snap.docs.map((doc) {
            final d = doc.data();
            return {
              'uid': doc.id,
              'name': d['name'] ?? '',
              'email': d['email'] ?? '',
              'role': d['role'] ?? 'user',
              'status': d['status'] ?? 'active',
              'occupation': d['occupation'],
              'createdAt': d['createdAt'],
            };
          }).toList();
          return {'success': true, 'users': users};
        }
        return {'success': true};
      },
    );

    await fakeFirestore.collection('users').doc('admin_01').set(
          AppUser(
            uid: 'admin_01',
            name: 'Quản trị viên Hỗ trợ',
            email: 'admin@financeai.vn',
            role: 'admin',
            status: 'active',
            createdAt: DateTime(2026, 9, 1),
          ).toMap(),
        );
    await fakeFirestore.collection('users').doc('user_a').set(
          AppUser(
            uid: 'user_a',
            name: 'Nguyễn Văn A',
            email: 'user_a@gmail.com',
            role: 'user',
            status: 'active',
            createdAt: DateTime(2026, 10, 1),
          ).toMap(),
        );
    await fakeFirestore.collection('users').doc('user_b').set(
          AppUser(
            uid: 'user_b',
            name: 'Trần Thị B',
            email: 'user_b@gmail.com',
            role: 'user',
            status: 'active',
            createdAt: DateTime(2026, 10, 2),
          ).toMap(),
        );
  });

  group('1. SupportService, State Machine, Time Tracker & Rating Unit Tests', () {
    test(
      '1.1. Luồng chuẩn đầy đủ: Tạo ticket (userImpact + technicalInfo) -> Tiếp nhận -> Chỉnh ưu tiên -> Yêu cầu bổ sung -> User nhắn -> Admin trả lời -> User xác nhận giải quyết -> Đánh giá -> Nhắn tiếp giữ đánh giá lịch sử -> Giải quyết lại -> Sửa đánh giá 1 lần -> Đóng chuẩn -> Tham chiếu ticket mới',
      () async {
        final techInfo = SupportTechnicalInfo(
          appVersion: '1.0.0+1',
          platform: 'Android',
          osVersion: 'Android 14',
          capturedAt: DateTime.utc(2026, 11, 20, 8, 0),
        );

        final created = await supportService.createTicket(
          category: SupportCategory.bugReport,
          title: 'Biểu đồ chi tiêu không cập nhật ngay',
          description:
              'Sau khi lưu giao dịch mới ở màn trang chủ, biểu đồ tháng chưa làm mới ngay lập tức.',
          userImpact: SupportUserImpact.high,
          technicalInfo: techInfo,
          userIdOverride: 'user_a',
          userNameOverride: 'Nguyễn Văn A',
          userEmailOverride: 'user_a@gmail.com',
        );

        expect(created.status, SupportTicketStatus.newTicket);
        // User không tự quyết định priority cuối cùng -> mặc định normal
        expect(created.priority, SupportPriority.normal);
        expect(created.userImpact, SupportUserImpact.high);
        expect(created.technicalInfo?.platform, 'Android');
        expect(created.lastMessageId, isNotNull);
        expect(created.unreadByAdmin, isTrue);
        expect(created.unreadByUser, isFalse);

        final initialMsgs =
            await supportService.streamTicketMessages(created.ticketId).first;
        expect(initialMsgs.length, 1);
        expect(initialMsgs.first.messageId, created.lastMessageId);

        // User B cô lập
        expect(await supportService.streamUserTickets('user_b').first, isEmpty);

        // Admin đánh dấu đọc KHÔNG đổi status
        await supportService.markTicketReadByAdmin(created.ticketId);
        var live = (await supportService.streamTicketById(created.ticketId).first)!;
        expect(live.status, SupportTicketStatus.newTicket);
        expect(live.unreadByAdmin, isFalse);

        // Admin tiếp nhận (`new -> in_progress`) ghi `claimedAt`
        await supportService.claimTicketByAdmin(
          ticket: live,
          adminUid: 'admin_01',
          adminName: 'Quản trị viên Hỗ trợ',
        );
        live = (await supportService.streamTicketById(created.ticketId).first)!;
        expect(live.status, SupportTicketStatus.inProgress);
        expect(live.claimedAt, isNotNull);
        expect(live.assignedAdminId, 'admin_01');
        expect(live.unreadByUser, isTrue);

        // Admin điều chỉnh mức ưu tiên (`normal -> urgent`)
        await supportService.updateTicketPriorityByAdmin(
          ticket: live,
          adminUid: 'admin_01',
          priority: SupportPriority.urgent,
        );
        live = (await supportService.streamTicketById(created.ticketId).first)!;
        expect(live.priority, SupportPriority.urgent);

        // Admin yêu cầu bổ sung (`waiting_for_user`) ghi `firstAdminResponseAt`
        await supportService.sendAdminReply(
          ticket: live,
          adminUid: 'admin_01',
          adminName: 'Quản trị viên Hỗ trợ',
          body: 'Bạn cho mình biết loại giao dịch vừa thêm là Thu hay Chi nhé?',
          requestMoreInfo: true,
        );
        live = (await supportService.streamTicketById(created.ticketId).first)!;
        expect(live.status, SupportTicketStatus.waitingForUser);
        expect(live.firstAdminResponseAt, isNotNull);

        // User đánh dấu đọc rồi gửi bổ sung (`waiting_for_user -> in_progress`)
        await supportService.markTicketReadByUser(created.ticketId);
        live = (await supportService.streamTicketById(created.ticketId).first)!;
        expect(live.status, SupportTicketStatus.waitingForUser);
        expect(live.unreadByUser, isFalse);

        await supportService.sendUserMessage(
          ticket: live,
          body: 'Mình vừa thêm khoản Chi ăn uống 150.000đ.',
          userIdOverride: 'user_a',
          userNameOverride: 'Nguyễn Văn A',
        );
        live = (await supportService.streamTicketById(created.ticketId).first)!;
        expect(live.status, SupportTicketStatus.inProgress);
        expect(live.unreadByAdmin, isTrue);

        // Admin gửi phản hồi (`replied`)
        await supportService.sendAdminReply(
          ticket: live,
          adminUid: 'admin_01',
          adminName: 'Quản trị viên Hỗ trợ',
          body: 'Bạn kéo xuống làm mới màn Trang chủ hoặc kiểm tra lại bộ lọc tháng nhé.',
          requestMoreInfo: false,
        );
        live = (await supportService.streamTicketById(created.ticketId).first)!;
        expect(live.status, SupportTicketStatus.replied);

        // User chủ động xác nhận đã giải quyết (`replied -> resolved`)
        await supportService.confirmResolvedByUser(
          ticket: live,
          userIdOverride: 'user_a',
          userNameOverride: 'Nguyễn Văn A',
        );
        live = (await supportService.streamTicketById(created.ticketId).first)!;
        expect(live.status, SupportTicketStatus.resolved);
        expect(live.resolvedAt, isNotNull);
        expect(live.resolvedByRole, 'user');
        expect(live.unreadByAdmin, isTrue);

        // User gửi đánh giá lần đầu (5 sao) khi `resolved`
        await supportService.submitOrUpdateRating(
          ticket: live,
          score: 5,
          comment: 'Hướng dẫn nhanh và chính xác.',
          userIdOverride: 'user_a',
        );
        live = (await supportService.streamTicketById(created.ticketId).first)!;
        expect(live.ratingScore, 5);
        expect(live.ratingComment, 'Hướng dẫn nhanh và chính xác.');
        expect(live.ratingEditCount, 0);
        final originalRatedAt = live.ratedAt;
        expect(originalRatedAt, isNotNull);

        // User gửi thêm tin nhắn từ `resolved` -> quay lại `in_progress`,
        // xóa `resolvedAt`/`resolvedByRole` nhưng GIỮ NGUYÊN đánh giá lịch sử!
        await supportService.sendUserMessage(
          ticket: live,
          body: 'Mình hỏi thêm: biểu đồ tuần có cập nhật cùng lúc không?',
          userIdOverride: 'user_a',
          userNameOverride: 'Nguyễn Văn A',
        );
        live = (await supportService.streamTicketById(created.ticketId).first)!;
        expect(live.status, SupportTicketStatus.inProgress);
        expect(live.resolvedAt, isNull);
        expect(live.resolvedByRole, isNull);
        expect(live.ratingScore, 5);
        expect(live.ratingComment, 'Hướng dẫn nhanh và chính xác.');
        expect(live.canUserEditRating, isFalse);

        // Trong khi `in_progress`, chặn sửa đánh giá lịch sử
        await expectLater(
          () => supportService.submitOrUpdateRating(
            ticket: live,
            score: 4,
            comment: 'Thử sửa khi đang in_progress',
            userIdOverride: 'user_a',
          ),
          throwsA(isA<SupportServiceException>()),
        );

        // Admin đánh dấu đã giải quyết lại (`in_progress -> resolved`)
        await supportService.markResolvedByAdmin(
          ticket: live,
          adminUid: 'admin_01',
          adminName: 'Quản trị viên Hỗ trợ',
        );
        live = (await supportService.streamTicketById(created.ticketId).first)!;
        expect(live.status, SupportTicketStatus.resolved);
        expect(live.resolvedByRole, 'admin');
        expect(live.canUserEditRating, isTrue);

        // Quay lại `resolved`, User chỉnh sửa đánh giá 1 lần duy nhất
        await supportService.submitOrUpdateRating(
          ticket: live,
          score: 4,
          comment: 'Đã rõ thêm phần biểu đồ tuần.',
          userIdOverride: 'user_a',
        );
        live = (await supportService.streamTicketById(created.ticketId).first)!;
        expect(live.ratingScore, 4);
        expect(live.ratingEditCount, 1);
        expect(live.ratedAt, originalRatedAt);
        expect(live.canUserEditRating, isFalse);

        // Chặn sửa đánh giá lần thứ 2
        await expectLater(
          () => supportService.submitOrUpdateRating(
            ticket: live,
            score: 3,
            comment: 'Sửa lần 2',
            userIdOverride: 'user_a',
          ),
          throwsA(isA<SupportServiceException>()),
        );

        // Admin đóng chuẩn (`resolved -> closed`) — giữ nguyên resolvedAt & resolvedByRole
        final resolvedAtBeforeClose = live.resolvedAt;
        await supportService.closeResolvedTicketByAdmin(
          ticket: live,
          adminUid: 'admin_01',
          adminName: 'Quản trị viên Hỗ trợ',
        );
        live = (await supportService.streamTicketById(created.ticketId).first)!;
        expect(live.status, SupportTicketStatus.closed);
        expect(live.closedAt, isNotNull);
        expect(live.closeReason, SupportCloseReason.completed);
        expect(live.resolvedAt, resolvedAtBeforeClose);
        expect(live.resolvedByRole, 'admin');
        expect(live.isClosedAfterResolved, isTrue);
        expect(live.isClosedUnresolved, isFalse);

        // Khi đã `closed`: chặn nhắn tin (User/Admin), chặn đánh giá, chặn đổi ưu tiên, chặn mở lại
        await expectLater(
          () => supportService.sendUserMessage(
            ticket: live,
            body: 'Nhắn khi đã đóng',
            userIdOverride: 'user_a',
          ),
          throwsA(isA<SupportServiceException>()),
        );
        await expectLater(
          () => supportService.sendAdminReply(
            ticket: live,
            adminUid: 'admin_01',
            adminName: 'Admin',
            body: 'Admin nhắn khi đã đóng',
          ),
          throwsA(isA<SupportServiceException>()),
        );
        await expectLater(
          () => supportService.updateTicketPriorityByAdmin(
            ticket: live,
            adminUid: 'admin_01',
            priority: SupportPriority.low,
          ),
          throwsA(isA<SupportServiceException>()),
        );
        await expectLater(
          () => supportService.submitOrUpdateRating(
            ticket: live,
            score: 5,
            userIdOverride: 'user_a',
          ),
          throwsA(isA<SupportServiceException>()),
        );
        await expectLater(
          () => supportService.updateTicketStatusByAdmin(
            ticket: live,
            adminUid: 'admin_01',
            adminName: 'Admin',
            targetStatus: SupportTicketStatus.inProgress,
          ),
          throwsA(isA<SupportServiceException>()),
        );

        // User tạo yêu cầu mới có tham chiếu ticket đã đóng
        final followUp = await supportService.createTicket(
          category: SupportCategory.bugReport,
          title: 'Phát sinh lại lỗi biểu đồ sau khi đóng',
          description:
              'Hôm nay mình thấy biểu đồ lại không tự cập nhật sau khi sửa giao dịch.',
          relatedTicket: live,
          userIdOverride: 'user_a',
          userNameOverride: 'Nguyễn Văn A',
          userEmailOverride: 'user_a@gmail.com',
        );
        expect(followUp.relatedTicketId, live.ticketId);
        expect(followUp.relatedTicketCode, live.ticketCode);
        expect(followUp.hasRelatedTicket, isTrue);
      },
    );

    test(
      '1.2. Đóng ngoại lệ chưa giải quyết: bắt buộc lý do ngoại lệ, giữ resolvedAt=null & resolvedByRole=null, chặn đánh giá',
      () async {
        final created = await supportService.createTicket(
          category: SupportCategory.other,
          title: 'Yêu cầu trùng lặp cần đóng ngoại lệ',
          description: 'Mình gửi trùng nội dung đã gửi ở yêu cầu trước đó.',
          userIdOverride: 'user_a',
          userNameOverride: 'Nguyễn Văn A',
        );

        // Chặn gọi đóng chuẩn từ `new`
        await expectLater(
          () => supportService.closeResolvedTicketByAdmin(
            ticket: created,
            adminUid: 'admin_01',
            adminName: 'Admin',
          ),
          throwsA(isA<SupportServiceException>()),
        );

        // Chặn gọi đóng ngoại lệ với lý do `completed`
        await expectLater(
          () => supportService.closeUnresolvedTicketByAdmin(
            ticket: created,
            adminUid: 'admin_01',
            adminName: 'Admin',
            closeReason: SupportCloseReason.completed,
          ),
          throwsA(isA<SupportServiceException>()),
        );

        // Đóng ngoại lệ hợp lệ với lý do `duplicate`
        await supportService.closeUnresolvedTicketByAdmin(
          ticket: created,
          adminUid: 'admin_01',
          adminName: 'Admin',
          closeReason: SupportCloseReason.duplicate,
          note: 'Trùng mã trước',
        );

        final closed =
            (await supportService.streamTicketById(created.ticketId).first)!;
        expect(closed.status, SupportTicketStatus.closed);
        expect(closed.closeReason, SupportCloseReason.duplicate);
        expect(closed.resolvedAt, isNull);
        expect(closed.resolvedByRole, isNull);
        expect(closed.isClosedUnresolved, isTrue);
        expect(closed.isClosedAfterResolved, isFalse);
        expect(SupportTimeTracker.resolutionDuration(closed), isNull);

        // Chặn User đánh giá ticket đóng ngoại lệ chưa giải quyết
        await expectLater(
          () => supportService.submitOrUpdateRating(
            ticket: closed,
            score: 1,
            userIdOverride: 'user_a',
          ),
          throwsA(isA<SupportServiceException>()),
        );
      },
    );

    test('1.3. Chặn các vi phạm nghiệp vụ ở tầng Service', () async {
      final tNew = await supportService.createTicket(
        category: SupportCategory.appGuide,
        title: 'Hướng dẫn đặt ngân sách tháng',
        description: 'Tôi muốn hỏi cách đặt ngân sách từng danh mục trong tháng.',
        userIdOverride: 'user_a',
      );

      // technicalInfo không cho phép cho nhóm khác bugReport
      await expectLater(
        () => supportService.createTicket(
          category: SupportCategory.appGuide,
          title: 'Hướng dẫn gửi kèm technicalInfo sai nhóm',
          description: 'Thử đính kèm thông tin kỹ thuật vào nhóm hướng dẫn.',
          technicalInfo: SupportTechnicalInfo(
            appVersion: '1.0.0+1',
            platform: 'Android',
            capturedAt: DateTime.now().toUtc(),
          ),
          userIdOverride: 'user_a',
        ),
        throwsA(isA<SupportServiceException>()),
      );

      // Không cho tham chiếu ticket chưa đóng hoặc của User khác
      await expectLater(
        () => supportService.createTicket(
          category: SupportCategory.appGuide,
          title: 'Tham chiếu ticket đang mở',
          description: 'Thử tham chiếu ticket chưa đóng là không hợp lệ.',
          relatedTicket: tNew,
          userIdOverride: 'user_a',
        ),
        throwsA(isA<SupportServiceException>()),
      );

      // User không được xác nhận resolved khi ticket mới ở `new`
      await expectLater(
        () => supportService.confirmResolvedByUser(
          ticket: tNew,
          userIdOverride: 'user_a',
        ),
        throwsA(isA<SupportServiceException>()),
      );

      // User B không được nhắn tin vào ticket của User A
      await expectLater(
        () => supportService.sendUserMessage(
          ticket: tNew,
          body: 'Trái phép',
          userIdOverride: 'user_b',
        ),
        throwsA(isA<SupportServiceException>()),
      );
    });

    test('1.4. Tương thích ngược với document ticket cũ thiếu toàn bộ trường mới', () async {
      final oldTime = DateTime.utc(2026, 10, 1, 9, 0).toIso8601String();
      await fakeFirestore.collection('support_tickets').doc('legacy_1').set({
        'ticketId': 'legacy_1',
        'ticketCode': 'SUP-261001-OLD1',
        'userId': 'user_a',
        'userName': 'Nguyễn Văn A',
        'userEmail': 'user_a@gmail.com',
        'category': 'app_guide',
        'title': 'Yêu cầu cũ trước khi nâng cấp',
        'description': 'Nội dung yêu cầu tạo ở phiên bản trước.',
        'status': 'resolved',
        'assignedAdminId': 'admin_01',
        'assignedAdminName': 'Admin',
        'lastMessagePreview': 'Đã giải quyết',
        'lastMessageSenderRole': 'system',
        'lastMessageAt': oldTime,
        'unreadByAdmin': false,
        'unreadByUser': false,
        'createdAt': oldTime,
        'updatedAt': oldTime,
        'resolvedAt': oldTime,
        'closedAt': null,
      });

      final legacy = (await supportService.getTicketById('legacy_1'))!;
      expect(legacy.priority, SupportPriority.normal);
      expect(legacy.userImpact, isNull);
      expect(legacy.technicalInfo, isNull);
      expect(legacy.lastMessageId, isNull);
      expect(legacy.hasRating, isFalse);
      expect(legacy.canUserSubmitRating, isTrue);

      // User đánh giá & Admin đóng chuẩn trên ticket legacy
      await supportService.submitOrUpdateRating(
        ticket: legacy,
        score: 5,
        comment: 'Rất hữu ích',
        userIdOverride: 'user_a',
      );
      final ratedLegacy = (await supportService.getTicketById('legacy_1'))!;
      expect(ratedLegacy.ratingScore, 5);

      await supportService.closeResolvedTicketByAdmin(
        ticket: ratedLegacy,
        adminUid: 'admin_01',
        adminName: 'Admin',
      );
      final closedLegacy = (await supportService.getTicketById('legacy_1'))!;
      expect(closedLegacy.status, SupportTicketStatus.closed);
      expect(closedLegacy.closeReason, SupportCloseReason.completed);
      expect(closedLegacy.resolvedByRole, 'admin');
    });

    test('1.5. SupportTimeTracker, SupportOverviewStats & SupportRatingStats phản ánh chính xác', () {
      final now = DateTime.utc(2026, 11, 21, 12, 0);
      final oldOpen = SupportTicket(
        ticketId: 't_old',
        ticketCode: 'SUP-261118-OLD1',
        userId: 'user_a',
        userName: 'User A',
        userEmail: 'a@test.vn',
        category: SupportCategory.bugReport,
        title: 'Yêu cầu tồn đọng 3 ngày',
        description: 'Mô tả tồn đọng quá 48 giờ.',
        status: SupportTicketStatus.newTicket,
        priority: SupportPriority.urgent,
        lastMessagePreview: 'Mô tả',
        lastMessageSenderRole: SupportSenderRole.user,
        lastMessageAt: now.subtract(const Duration(hours: 72)),
        unreadByAdmin: true,
        unreadByUser: false,
        createdAt: now.subtract(const Duration(hours: 72)),
        updatedAt: now.subtract(const Duration(hours: 72)),
      );
      final ratedLow = SupportTicket(
        ticketId: 't_low',
        ticketCode: 'SUP-261120-LOW1',
        userId: 'user_b',
        userName: 'User B',
        userEmail: 'b@test.vn',
        category: SupportCategory.appGuide,
        title: 'Đánh giá 2 sao cần chú ý',
        description: 'Cần hướng dẫn kỹ hơn.',
        status: SupportTicketStatus.resolved,
        priority: SupportPriority.normal,
        lastMessagePreview: 'Đã giải quyết',
        lastMessageSenderRole: SupportSenderRole.system,
        lastMessageAt: now.subtract(const Duration(hours: 2)),
        unreadByAdmin: false,
        unreadByUser: false,
        createdAt: now.subtract(const Duration(hours: 6)),
        updatedAt: now.subtract(const Duration(hours: 2)),
        resolvedAt: now.subtract(const Duration(hours: 2)),
        resolvedByRole: 'admin',
        ratingScore: 2,
        ratingComment: 'Phản hồi còn hơi ngắn gọn',
        ratedAt: now.subtract(const Duration(hours: 1)),
      );
      final closedUnresolved = SupportTicket(
        ticketId: 't_exc',
        ticketCode: 'SUP-261120-EXC1',
        userId: 'user_a',
        userName: 'User A',
        userEmail: 'a@test.vn',
        category: SupportCategory.other,
        title: 'Đóng ngoại lệ chưa giải quyết',
        description: 'Yêu cầu trùng lặp.',
        status: SupportTicketStatus.closed,
        priority: SupportPriority.low,
        lastMessagePreview: 'Đóng ngoại lệ',
        lastMessageSenderRole: SupportSenderRole.system,
        lastMessageAt: now.subtract(const Duration(hours: 5)),
        unreadByAdmin: false,
        unreadByUser: false,
        createdAt: now.subtract(const Duration(hours: 10)),
        updatedAt: now.subtract(const Duration(hours: 5)),
        resolvedAt: null,
        closedAt: now.subtract(const Duration(hours: 5)),
        closeReason: SupportCloseReason.duplicate,
      );

      expect(SupportTimeTracker.isAgingOpen(oldOpen, now: now), isTrue);
      expect(SupportTimeTracker.isAgingOpen(ratedLow, now: now), isFalse);
      expect(SupportTimeTracker.resolutionDuration(ratedLow)?.inHours, 4);
      expect(SupportTimeTracker.resolutionDuration(closedUnresolved), isNull);

      final overview = SupportOverviewStats.fromTickets(
        [oldOpen, ratedLow, closedUnresolved],
        now: now,
      );
      expect(overview.total, 3);
      expect(overview.newCount, 1);
      expect(overview.resolvedCount, 1);
      expect(overview.closedUnresolvedCount, 1);
      expect(overview.closedCompletedCount, 0);
      expect(overview.agingOpenCount, 1);
      expect(overview.highOrUrgentOpenCount, 1);

      final ratingStats = SupportRatingStats.fromTickets(
        [oldOpen, ratedLow, closedUnresolved],
      );
      expect(ratingStats.ratedCount, 1);
      expect(ratingStats.averageScore, 2.0);
      expect(ratingStats.distribution[2], 1);
      expect(ratingStats.attentionCount, 1);
      expect(ratingStats.attentionTickets.first.ticketId, 't_low');

      final emptyRatingStats = SupportRatingStats.fromTickets([oldOpen]);
      expect(emptyRatingStats.ratedCount, 0);
      expect(emptyRatingStats.averageScore, isNull);
    });
  });

  group('2. User App UI Tests (Create + Detail + Rating + Closed Reference + Notifications)', () {
    testWidgets(
      '2.1. CreateSupportTicketScreen: Báo lỗi hiện xem trước thông tin kỹ thuật & mức ảnh hưởng, Tư vấn giữ Opt-in mặc định tắt',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: CreateSupportTicketScreen(
              supportService: supportService,
              technicalInfoCollector: () => SupportTechnicalInfo(
                appVersion: '1.0.0+1',
                platform: 'Android',
                osVersion: 'Android 14',
                capturedAt: DateTime.utc(2026, 11, 21, 9, 0),
              ),
              userIdOverride: 'user_a',
              userNameOverride: 'Nguyễn Văn A',
              userEmailOverride: 'user_a@gmail.com',
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Chọn nhóm Báo lỗi hoặc sự cố -> hiện công tắc thông tin kỹ thuật mặc định BẬT + xem trước
        await tester.tap(
          find.byKey(const ValueKey('support_cat_option_bug_report')),
        );
        await tester.pumpAndSettle();
        final techSwitch = tester.widget<SwitchListTile>(
          find.byKey(const ValueKey('support_tech_info_switch')),
        );
        expect(techSwitch.value, isTrue);
        expect(find.byKey(const ValueKey('support_tech_info_preview')), findsOneWidget);
        expect(find.textContaining('App v1.0.0+1 · Android · Android 14'), findsOneWidget);

        // Chọn mức ảnh hưởng Cao
        final impactChip = find.byKey(const ValueKey('support_impact_option_high'));
        await tester.ensureVisible(impactChip);
        await tester.tap(impactChip);
        await tester.pumpAndSettle();

        // Nhập tiêu đề & mô tả rồi gửi
        await tester.enterText(
          find.byKey(const ValueKey('support_title_input')),
          'Lỗi không lưu được mục tiêu mới',
        );
        await tester.enterText(
          find.byKey(const ValueKey('support_desc_input')),
          'Khi nhấn Lưu mục tiêu tiết kiệm màn hình quay vòng rồi báo lỗi mạng.',
        );
        final submitBtn = find.byKey(const ValueKey('support_submit_btn'));
        await tester.ensureVisible(submitBtn);
        await tester.tap(submitBtn);
        await tester.pumpAndSettle();

        final tickets = await supportService.streamUserTickets('user_a').first;
        expect(tickets.length, 1);
        expect(tickets.first.userImpact, SupportUserImpact.high);
        expect(tickets.first.priority, SupportPriority.normal);
        expect(tickets.first.technicalInfo?.appVersion, '1.0.0+1');
      },
    );

    testWidgets(
      '2.2. SupportTicketDetailScreen: User xác nhận giải quyết -> gửi đánh giá -> sửa 1 lần -> đóng ticket hiện nút Tạo yêu cầu mới (tham chiếu SUP-...)',
      (tester) async {
        final ticket = await supportService.createTicket(
          category: SupportCategory.appGuide,
          title: 'Cách tạo danh mục chi tiêu mới',
          description: 'Tôi muốn tự thêm danh mục Thú cưng vào danh sách chi tiêu.',
          userIdOverride: 'user_a',
          userNameOverride: 'Nguyễn Văn A',
          userEmailOverride: 'user_a@gmail.com',
        );
        await supportService.sendAdminReply(
          ticket: ticket,
          adminUid: 'admin_01',
          adminName: 'Admin Hỗ trợ',
          body: 'Bạn vào Quản lý danh mục -> nhấn dấu (+) ở góc dưới bên phải nhé.',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: SupportTicketDetailScreen(
              ticketId: ticket.ticketId,
              supportService: supportService,
              userIdOverride: 'user_a',
              userNameOverride: 'Nguyễn Văn A',
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Nút xác nhận đã giải quyết xuất hiện khi đang ở `replied`
        final confirmBtn =
            find.byKey(const ValueKey('support_user_confirm_resolved_btn'));
        expect(confirmBtn, findsOneWidget);
        await tester.tap(confirmBtn);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('support_confirm_resolved_dialog_ok')),
        );
        await tester.pumpAndSettle();

        // Chuyển sang `resolved` -> xuất hiện form đánh giá
        await tester.drag(find.byType(ListView), const Offset(0, -350));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('support_rating_card')), findsOneWidget);
        final star5 = find.byKey(const ValueKey('support_rating_star_5'));
        await tester.tap(star5);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('support_rating_comment_input')),
          'Hướng dẫn rõ ràng!',
        );
        await tester.drag(find.byType(ListView), const Offset(0, -250));
        await tester.pumpAndSettle();
        final submitRatingBtn =
            find.byKey(const ValueKey('support_rating_submit_btn'));
        await tester.tap(submitRatingBtn);
        await tester.pumpAndSettle();

        // Hiện đánh giá chính thức + nút sửa (còn 1 lần)
        await tester.drag(find.byType(ListView), const Offset(0, -250));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('support_rating_summary')), findsOneWidget);
        final editRatingBtn = find.byKey(const ValueKey('support_rating_edit_btn'));
        expect(editRatingBtn, findsOneWidget);
        await tester.tap(editRatingBtn);
        await tester.pumpAndSettle();

        // Sửa 1 lần thành 4 sao
        await tester.drag(find.byType(ListView), const Offset(0, -250));
        await tester.pumpAndSettle();
        final star4 = find.byKey(const ValueKey('support_rating_star_4'));
        await tester.tap(star4);
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView), const Offset(0, -250));
        await tester.pumpAndSettle();
        final updateRatingBtn =
            find.byKey(const ValueKey('support_rating_submit_btn'));
        await tester.tap(updateRatingBtn);
        await tester.pumpAndSettle();

        // Sau 1 lần sửa -> không còn nút sửa
        expect(find.byKey(const ValueKey('support_rating_edit_btn')), findsNothing);

        // Admin đóng chuẩn yêu cầu -> hiện nút Tạo yêu cầu mới (tham chiếu) và chuyển sang CreateSupportTicketScreen có banner tham chiếu
        final liveResolved =
            (await supportService.getTicketById(ticket.ticketId))!;
        await supportService.closeResolvedTicketByAdmin(
          ticket: liveResolved,
          adminUid: 'admin_01',
          adminName: 'Admin Hỗ trợ',
        );
        // Chờ Snackbar cập nhật đánh giá tự ẩn trước khi nhấn nút ở thanh đáy
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();

        final createRefBtn =
            find.byKey(const ValueKey('support_closed_new_ticket_btn'));
        expect(createRefBtn, findsOneWidget);
        expect(find.textContaining(ticket.ticketCode), findsWidgets);

        await tester.tap(createRefBtn);
        await tester.pumpAndSettle();

        expect(find.byType(CreateSupportTicketScreen), findsOneWidget);
        expect(
          find.byKey(const ValueKey('support_related_ticket_banner')),
          findsOneWidget,
        );
        // User có thể gỡ tham chiếu nếu là vấn đề mới hoàn toàn
        await tester.tap(
          find.byKey(const ValueKey('support_related_remove_btn')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('support_related_ticket_banner')),
          findsNothing,
        );
      },
    );

    testWidgets(
      '2.3. NotificationScreen: phân biệt thông báo theo trạng thái (replied / waiting_for_user / resolved) và điều hướng đúng ticket',
      (tester) async {
        final tWaiting = await supportService.createTicket(
          category: SupportCategory.bugReport,
          title: 'Sự cố đồng bộ ví',
          description: 'Số dư ví chưa đồng bộ sau khi mở lại ứng dụng.',
          userIdOverride: 'user_a',
          userNameOverride: 'Nguyễn Văn A',
        );
        await supportService.sendAdminReply(
          ticket: tWaiting,
          adminUid: 'admin_01',
          adminName: 'Admin',
          body: 'Bạn cung cấp thêm tên ví bị lệch nhé.',
          requestMoreInfo: true,
        );

        final tResolved = await supportService.createTicket(
          category: SupportCategory.appGuide,
          title: 'Cách tạo lịch giao dịch định kỳ',
          description: 'Tôi muốn tự động nhắc thanh toán tiền điện hàng tháng.',
          userIdOverride: 'user_a',
          userNameOverride: 'Nguyễn Văn A',
        );
        await supportService.markResolvedByAdmin(
          ticket: tResolved,
          adminUid: 'admin_01',
          adminName: 'Admin',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: NotificationScreen(
              firestoreService: firestoreService,
              supportService: supportService,
              userIdOverride: 'user_a',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.textContaining('cần bạn bổ sung thông tin'),
          findsOneWidget,
        );
        expect(find.textContaining('đã được giải quyết'), findsOneWidget);
        expect(find.text('Xem & đánh giá'), findsOneWidget);

        // Chạm vào thông báo của ticket đã giải quyết -> mở thẳng chi tiết & thấy form đánh giá
        await tester.tap(
          find.byKey(ValueKey('notif_support_ticket_${tResolved.ticketId}')),
        );
        await tester.pumpAndSettle();

        expect(find.byType(SupportTicketDetailScreen), findsOneWidget);
        expect(find.text('Cách tạo lịch giao dịch định kỳ'), findsOneWidget);
        expect(find.byKey(const ValueKey('support_rating_card')), findsOneWidget);
      },
    );

    testWidgets(
      '2.4. SupportCenterScreen hiển thị bộ đếm chip lọc, nhãn ưu tiên và Chờ đánh giá',
      (tester) async {
        final t = await supportService.createTicket(
          category: SupportCategory.appGuide,
          title: 'Hướng dẫn lọc giao dịch theo ví',
          description: 'Tôi muốn xem riêng các khoản chi của ví tiền mặt.',
          userIdOverride: 'user_a',
          userNameOverride: 'Nguyễn Văn A',
        );
        await supportService.markResolvedByAdmin(
          ticket: t,
          adminUid: 'admin_01',
          adminName: 'Admin',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: SupportCenterScreen(
              supportService: supportService,
              userIdOverride: 'user_a',
              userNameOverride: 'Nguyễn Văn A',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Tất cả (1)'), findsOneWidget);
        expect(find.text('Đã hoàn tất (1)'), findsOneWidget);
        expect(find.text('Chờ đánh giá'), findsOneWidget);
      },
    );
  });

  group('3. Admin Web UI Tests (Helpdesk tinh gọn: 3 trạng thái, tìm kiếm, chat realtime & vòng đời chuẩn)', () {
    testWidgets(
      '3.1. AdminWebShellScreen + AdminSupportCenterView: huy hiệu Sidebar, tiếp nhận, chat realtime, giải quyết & đóng chuẩn (đã gỡ UI phức tạp thừa)',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 960);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final ticket = await supportService.createTicket(
          category: SupportCategory.bugReport,
          title: 'Không thấy nút xuất báo cáo PDF',
          description:
              'Khi vào màn Báo cáo AI tôi không thấy tùy chọn tải báo cáo PDF.',
          userImpact: SupportUserImpact.high,
          technicalInfo: SupportTechnicalInfo(
            appVersion: '1.0.0+1',
            platform: 'Android',
            osVersion: 'Android 14',
            capturedAt: DateTime.utc(2026, 11, 20, 8, 0),
          ),
          userIdOverride: 'user_a',
          userNameOverride: 'Nguyễn Văn A',
          userEmailOverride: 'user_a@gmail.com',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: AdminWebShellScreen(
              adminService: adminService,
              supportService: supportService,
              adminUidOverride: 'admin_01',
              tokenClaimsOverride: const {'admin': true},
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Sidebar badge chưa đọc hiển thị
        expect(
          find.byKey(const ValueKey('admin_support_sidebar_badge')),
          findsOneWidget,
        );

        // Chuyển sang tab Tư vấn & Hỗ trợ (index 5)
        await tester.tap(find.byKey(const ValueKey('admin_nav_tab_5')));
        await tester.pumpAndSettle();
        expect(find.byType(AdminSupportCenterView), findsOneWidget);

        // Chọn yêu cầu từ danh sách
        await tester.tap(
          find.byKey(ValueKey('admin_ticket_row_${ticket.ticketId}')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('admin_support_tech_info')),
          findsOneWidget,
        );

        // Xác nhận các phần phức tạp không cần thiết đã được gỡ bỏ
        expect(
          find.byKey(const ValueKey('admin_support_scope_banner')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('admin_support_priority_dropdown')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('admin_support_quick_reply_btn')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('admin_support_kpi_rating')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('admin_support_filter_attention_rating')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('admin_support_close_unresolved_btn')),
          findsNothing,
        );

        // Admin bấm Tiếp nhận xử lý (`new -> in_progress`)
        await tester.tap(
          find.byKey(const ValueKey('admin_support_claim_btn')),
        );
        await tester.pumpAndSettle();

        var live = (await supportService.getTicketById(ticket.ticketId))!;
        expect(live.status, SupportTicketStatus.inProgress);
        expect(live.assignedAdminId, 'admin_01');

        // Admin gửi phản hồi realtime (`in_progress -> replied`)
        await tester.enterText(
          find.byKey(const ValueKey('admin_support_reply_input')),
          'Nút xuất PDF nằm ở góc trên bên phải màn hình Báo cáo AI bạn nhé.',
        );
        await tester.tap(
          find.byKey(const ValueKey('admin_support_send_reply_btn')),
        );
        await tester.pumpAndSettle();

        live = (await supportService.getTicketById(ticket.ticketId))!;
        expect(live.status, SupportTicketStatus.replied);
        expect(live.unreadByUser, isTrue);
        expect(
          find.textContaining('Nút xuất PDF nằm ở góc trên bên phải'),
          findsWidgets,
        );

        // Admin đánh dấu đã giải quyết (`replied -> resolved`)
        await tester.tap(
          find.byKey(const ValueKey('admin_support_resolve_btn')),
        );
        await tester.pumpAndSettle();

        live = (await supportService.getTicketById(ticket.ticketId))!;
        expect(live.status, SupportTicketStatus.resolved);

        // Admin đóng chuẩn (`resolved -> closed`)
        await tester.tap(find.byKey(const ValueKey('admin_support_close_btn')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('admin_support_confirm_close_btn')),
        );
        await tester.pumpAndSettle();

        live = (await supportService.getTicketById(ticket.ticketId))!;
        expect(live.status, SupportTicketStatus.closed);
        expect(live.closeReason, SupportCloseReason.completed);
        expect(live.resolvedAt, isNotNull);
        expect(find.text('Mở lại yêu cầu'), findsNothing);
      },
    );

    testWidgets(
      '3.2. AdminSupportCenterView: tìm kiếm cơ bản, lọc 3 trạng thái và ánh xạ an toàn trạng thái cũ (replied, waiting_for_user, closed_unresolved)',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 960);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        // 1) Vé Mới (`new`)
        final tNew = await supportService.createTicket(
          category: SupportCategory.bugReport,
          title: 'Lỗi đồng bộ ví ngân hàng',
          description: 'Tôi cần kiểm tra vì sao số dư ví chưa cập nhật ngay.',
          userIdOverride: 'user_a',
          userNameOverride: 'Nguyễn Văn A',
          userEmailOverride: 'user_a@gmail.com',
        );

        // 2) Vé Đã phản hồi (`replied`) -> ánh xạ vào nhóm "Đang xử lý"
        final tReplied = await supportService.createTicket(
          category: SupportCategory.appGuide,
          title: 'Hỏi cách xuất dữ liệu Excel',
          description: 'Tôi chưa tìm thấy nút xuất bảng kê giao dịch ra file.',
          userIdOverride: 'user_a',
          userNameOverride: 'Nguyễn Văn A',
          userEmailOverride: 'user_a@gmail.com',
        );
        await supportService.sendAdminReply(
          ticket: tReplied,
          adminUid: 'admin_01',
          adminName: 'Admin',
          body: 'Bạn vào mục Báo cáo để tải xuống nhé.',
        );

        // 3) Vé Chờ người dùng bổ sung (`waiting_for_user`) -> ánh xạ vào nhóm "Đang xử lý"
        final tWaiting = await supportService.createTicket(
          category: SupportCategory.other,
          title: 'Cần xác minh lịch định kỳ',
          description: 'Lịch thanh toán tiền nhà tháng này chưa thấy nhắc nhở.',
          userIdOverride: 'user_b',
          userNameOverride: 'Trần Thị B',
          userEmailOverride: 'user_b@gmail.com',
        );
        await supportService.sendAdminReply(
          ticket: tWaiting,
          adminUid: 'admin_01',
          adminName: 'Admin',
          body: 'Bạn giúp mình cung cấp ngày đến hạn đã cài đặt nhé.',
          requestMoreInfo: true,
        );

        // 4) Dữ liệu legacy trong Firestore có `status: 'closed_unresolved'` -> ánh xạ an toàn vào "Đã giải quyết"
        const legacyId = 'legacy_closed_unresolved_1';
        final nowIso = DateTime.now().toUtc().toIso8601String();
        await fakeFirestore.collection('support_tickets').doc(legacyId).set({
          'ticketId': legacyId,
          'ticketCode': 'SUP-LEGACY-01',
          'userId': 'user_b',
          'userName': 'Trần Thị B',
          'userEmail': 'user_b@gmail.com',
          'category': 'other',
          'title': 'Yêu cầu cũ đóng ngoại lệ',
          'description': 'Dữ liệu cũ từng đóng theo luồng closed_unresolved.',
          'status': 'closed_unresolved',
          'priority': 'normal',
          'lastMessagePreview': 'Đã đóng trước đây.',
          'lastMessageSenderRole': 'system',
          'lastMessageAt': nowIso,
          'unreadByAdmin': false,
          'unreadByUser': false,
          'createdAt': nowIso,
          'updatedAt': nowIso,
          'closedAt': nowIso,
          'closeReason': 'no_user_response',
        });

        // Kiểm chứng tầng model không rơi về `newTicket`
        expect(
          SupportTicketStatus.fromCode('closed_unresolved'),
          SupportTicketStatus.closed,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AdminSupportCenterView(
                supportService: supportService,
                currentAdminUid: 'admin_01',
                currentAdminName: 'Quản trị viên Hỗ trợ',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Đếm đúng 3 nhóm trạng thái + Tất cả
        expect(find.text('Tất cả (4)'), findsOneWidget);
        expect(find.text('Mới (1)'), findsOneWidget);
        expect(find.text('Đang xử lý (2)'), findsOneWidget);
        expect(find.text('Đã giải quyết (1)'), findsOneWidget);

        // Lọc "Đang xử lý" -> chứa cả `replied` và `waiting_for_user`
        await tester.tap(
          find.byKey(const ValueKey('admin_support_status_chip_in_progress')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(ValueKey('admin_ticket_row_${tReplied.ticketId}')),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey('admin_ticket_row_${tWaiting.ticketId}')),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey('admin_ticket_row_${tNew.ticketId}')),
          findsNothing,
        );

        // Lọc "Đã giải quyết" -> chứa dữ liệu legacy `closed_unresolved` an toàn
        await tester.tap(
          find.byKey(const ValueKey('admin_support_status_chip_resolved')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('admin_ticket_row_$legacyId')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey('admin_ticket_row_$legacyId')),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Yêu cầu đã được đóng'),
          findsOneWidget,
        );

        // Quay về "Tất cả" và tìm kiếm theo mã vé / tiêu đề
        await tester.tap(
          find.byKey(const ValueKey('admin_support_status_chip_all')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('admin_support_search_input')),
          tNew.ticketCode,
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(ValueKey('admin_ticket_row_${tNew.ticketId}')),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey('admin_ticket_row_${tReplied.ticketId}')),
          findsNothing,
        );

        await tester.enterText(
          find.byKey(const ValueKey('admin_support_search_input')),
          'đồng bộ ví',
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(ValueKey('admin_ticket_row_${tNew.ticketId}')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '3.3. AdminSupportCenterView trên màn hình laptop thấp (1024x445 & 760x445): không bị BOTTOM OVERFLOWED, hiển thị đầy đủ hội thoại và nút Gửi phản hồi',
      (tester) async {
        final ticket = await supportService.createTicket(
          category: SupportCategory.appGuide,
          title: 'abcde',
          description:
              'Nội dung câu hỏi của người dùng hiển thị rõ trong khung hội thoại.',
          userIdOverride: 'user_a',
          userNameOverride: 'Nguyễn Văn A',
          userEmailOverride: 'user_a@gmail.com',
        );

        for (final size in [const Size(1024, 445), const Size(760, 445)]) {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;

          await tester.pumpWidget(
            MaterialApp(
              key: ValueKey('app_${size.width}x${size.height}'),
              home: AdminWebShellScreen(
                key: ValueKey('shell_${size.width}x${size.height}'),
                adminService: adminService,
                supportService: supportService,
                adminUidOverride: 'admin_01',
                tokenClaimsOverride: const {'admin': true},
                initialIndex: 5,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          final rowFinder =
              find.byKey(ValueKey('admin_ticket_row_${ticket.ticketId}'));
          expect(rowFinder, findsOneWidget);
          await tester.tap(rowFinder);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          // Nội dung tin nhắn của User hiển thị trong vùng cuộn hội thoại (không bị ép về 0px)
          expect(
            find.textContaining('Nội dung câu hỏi của người dùng'),
            findsWidgets,
          );
          expect(
            find.byKey(const ValueKey('admin_support_quick_replies_bar')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('admin_support_reply_input')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('admin_support_send_reply_btn')),
            findsOneWidget,
          );
        }

        addTearDown(tester.view.resetPhysicalSize);
      },
    );

    testWidgets(
      '3.4. Sidebar hai chế độ (Expanded & Collapsed Icon Rail): nhấn Logo thu gọn/mở rộng mượt mà, giữ nguyên tab đang chọn, hiển thị Tooltip & mở rộng không gian vùng nội dung',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await supportService.createTicket(
          category: SupportCategory.appGuide,
          title: 'Kiểm tra mở rộng không gian khi thu gọn Sidebar',
          description:
              'Nội dung yêu cầu kiểm tra khả năng thích ứng của vùng nội dung.',
          userIdOverride: 'user_a',
          userNameOverride: 'Nguyễn Văn A',
          userEmailOverride: 'user_a@gmail.com',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: AdminWebShellScreen(
              adminService: adminService,
              supportService: supportService,
              adminUidOverride: 'admin_01',
              tokenClaimsOverride: const {'admin': true},
              initialIndex: 5,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Trạng thái mặc định Expanded (264px): hiển thị đúng Logo ví Finance AI, tên, mô tả, chevron thu gọn & thẻ bảo mật
        final sidebarFinder =
            find.byKey(const ValueKey('admin_sidebar_container'));
        expect(tester.getSize(sidebarFinder).width, 264.0);
        expect(
          find.byIcon(Icons.account_balance_wallet_rounded),
          findsOneWidget,
        );
        final logoTopLeftExpanded = tester
            .getTopLeft(find.byIcon(Icons.account_balance_wallet_rounded));
        expect(find.text('Finance AI'), findsOneWidget);
        expect(find.text('Admin Web Portal'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('admin_sidebar_chevron_collapse')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('admin_sidebar_privacy_card')),
          findsOneWidget,
        );
        expect(find.byType(AdminSupportCenterView), findsOneWidget);
        final supportWidthExpanded =
            tester.getSize(find.byType(AdminSupportCenterView)).width;

        // 2. Nhấn vào khu vực Logo -> thu gọn thành Icon Rail (76px), KHÔNG tự chuyển về Dashboard, Logo không bị nhảy vị trí
        await tester.tap(
          find.byKey(const ValueKey('admin_sidebar_logo_toggle')),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        expect(tester.getSize(sidebarFinder).width, 76.0);
        final logoTopLeftCollapsed = tester
            .getTopLeft(find.byIcon(Icons.account_balance_wallet_rounded));
        expect(logoTopLeftCollapsed, equals(logoTopLeftExpanded));
        expect(find.text('Finance AI'), findsNothing);
        expect(find.text('Admin Web Portal'), findsNothing);
        expect(
          find.byKey(const ValueKey('admin_sidebar_privacy_card')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('admin_sidebar_chevron_expand')),
          findsOneWidget,
        );
        // Vẫn giữ nguyên màn hình Tư vấn & Hỗ trợ và badge chưa đọc
        expect(find.byType(AdminSupportCenterView), findsOneWidget);
        expect(
          find.byKey(const ValueKey('admin_support_sidebar_badge')),
          findsOneWidget,
        );
        // Không gian màn hình Tư vấn & Hỗ trợ được giải phóng rộng hơn (+188px)
        final supportWidthCollapsed =
            tester.getSize(find.byType(AdminSupportCenterView)).width;
        expect(supportWidthCollapsed, greaterThan(supportWidthExpanded + 180));

        // 3. Chuyển qua các màn hình Admin khác khi đang Collapsed -> giữ nguyên trạng thái Collapsed
        for (int tabIdx = 0; tabIdx < 6; tabIdx++) {
          await tester.tap(find.byKey(ValueKey('admin_nav_tab_$tabIdx')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(tester.getSize(sidebarFinder).width, 76.0);
        }

        // 4. Nhấn lại Logo khi đang ở tab Tư vấn & Hỗ trợ (index 5) -> mở rộng trở lại (264px) và giữ nguyên tab
        await tester.tap(
          find.byKey(const ValueKey('admin_sidebar_logo_toggle')),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        expect(tester.getSize(sidebarFinder).width, 264.0);
        expect(find.text('Finance AI'), findsOneWidget);
        expect(find.text('Admin Web Portal'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('admin_sidebar_privacy_card')),
          findsOneWidget,
        );
        expect(find.byType(AdminSupportCenterView), findsOneWidget);
      },
    );

    testWidgets(
      '3.5. Quick Replies tĩnh (chỉ điền & nối dòng, không tự gửi) và khóa ô nhập khi đã giải quyết + Mở lại xử lý (khép kín vòng đời)',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 960);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final ticket = await supportService.createTicket(
          category: SupportCategory.bugReport,
          title: 'Hóa đơn quét OCR bị lệch số tiền',
          description:
              'Khi quét hóa đơn siêu thị buổi tối, số tiền bị nhận nhầm thiếu số 0.',
          userIdOverride: 'user_a',
          userNameOverride: 'Nguyễn Văn A',
          userEmailOverride: 'user_a@gmail.com',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AdminSupportCenterView(
                supportService: supportService,
                currentAdminUid: 'admin_01',
                currentAdminName: 'Quản trị viên Hỗ trợ',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Chọn vé hỗ trợ
        await tester.tap(
          find.byKey(ValueKey('admin_ticket_row_${ticket.ticketId}')),
        );
        await tester.pumpAndSettle();

        // 1. Thanh Quick Replies hiển thị gọn ngay trên ô nhập
        expect(
          find.byKey(const ValueKey('admin_support_quick_replies_bar')),
          findsOneWidget,
        );
        final msgCountBefore =
            (await supportService.streamTicketMessages(ticket.ticketId).first)
                .length;

        // 2. Bấm chip "Tiếp nhận" -> chỉ điền vào ô nhập, đặt con trỏ về cuối và KHÔNG tự gửi
        await tester.tap(
          find.byKey(const ValueKey('admin_support_quick_reply_ack')),
        );
        await tester.pumpAndSettle();

        var replyField = tester.widget<TextField>(
          find.byKey(const ValueKey('admin_support_reply_input')),
        );
        final firstText = replyField.controller!.text;
        expect(
          firstText,
          'Chào bạn, đội ngũ hỗ trợ Finance AI đã tiếp nhận yêu cầu và đang kiểm tra giúp bạn.',
        );
        expect(replyField.controller!.selection.baseOffset, firstText.length);
        expect(replyField.controller!.selection.isCollapsed, isTrue);

        // Chưa tự gửi tin nhắn!
        var msgCountAfter =
            (await supportService.streamTicketMessages(ticket.ticketId).first)
                .length;
        expect(msgCountAfter, msgCountBefore);

        // 3. Khi ô nhập đang có sẵn chữ, bấm thêm chip "Hướng dẫn OCR" -> xuống dòng nối thêm, KHÔNG ghi đè
        await tester.tap(
          find.byKey(const ValueKey('admin_support_quick_reply_ocr_guide')),
        );
        await tester.pumpAndSettle();

        replyField = tester.widget<TextField>(
          find.byKey(const ValueKey('admin_support_reply_input')),
        );
        final combinedText = replyField.controller!.text;
        expect(
          combinedText,
          'Chào bạn, đội ngũ hỗ trợ Finance AI đã tiếp nhận yêu cầu và đang kiểm tra giúp bạn.\n'
          'Với tính năng quét hóa đơn OCR, bạn lưu ý chụp ở nơi đủ sáng và giữ hóa đơn phẳng để hệ thống nhận diện chính xác nhất.',
        );
        expect(
          replyField.controller!.selection.baseOffset,
          combinedText.length,
        );
        // Vẫn chưa tự gửi tin nhắn!
        msgCountAfter =
            (await supportService.streamTicketMessages(ticket.ticketId).first)
                .length;
        expect(msgCountAfter, msgCountBefore);

        // 4. Đánh dấu vé là Đã giải quyết -> ẩn/khóa ô nhập và thanh Quick Replies, hiện thanh trạng thái + nút Mở lại xử lý
        await tester.tap(
          find.byKey(const ValueKey('admin_support_resolve_btn')),
        );
        await tester.pumpAndSettle();

        var live = (await supportService.getTicketById(ticket.ticketId))!;
        expect(live.status, SupportTicketStatus.resolved);
        expect(
          find.byKey(const ValueKey('admin_support_reply_input')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('admin_support_send_reply_btn')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('admin_support_quick_replies_bar')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('admin_support_resolved_banner')),
          findsOneWidget,
        );
        expect(find.text('Yêu cầu này đã được giải quyết.'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('admin_support_reopen_btn')),
          findsOneWidget,
        );

        // 5. Đợi SnackBar thông báo tự ẩn rồi bấm "Mở lại xử lý" -> chuyển về `in_progress`, mở lại ô chat & thanh Quick Replies
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('admin_support_reopen_btn')),
        );
        await tester.pumpAndSettle();

        live = (await supportService.getTicketById(ticket.ticketId))!;
        expect(live.status, SupportTicketStatus.inProgress);
        expect(live.resolvedAt, isNull);
        expect(live.resolvedByRole, isNull);
        expect(live.unreadByUser, isTrue);
        expect(
          find.byKey(const ValueKey('admin_support_reply_input')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('admin_support_quick_replies_bar')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('admin_support_resolved_banner')),
          findsNothing,
        );

        // 6. Đánh dấu giải quyết lại rồi Đóng yêu cầu -> khóa hoàn toàn, không còn nút Mở lại xử lý
        await tester.tap(
          find.byKey(const ValueKey('admin_support_resolve_btn')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('admin_support_close_btn')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('admin_support_confirm_close_btn')),
        );
        await tester.pumpAndSettle();

        live = (await supportService.getTicketById(ticket.ticketId))!;
        expect(live.status, SupportTicketStatus.closed);
        expect(
          find.byKey(const ValueKey('admin_support_closed_banner')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('admin_support_reply_input')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('admin_support_quick_replies_bar')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('admin_support_reopen_btn')),
          findsNothing,
        );
      },
    );

    testWidgets(
      '3.6. Lọc chip "Mới" truy vấn phía server không bị sót vé mới ngoài top 30 & tự tắt unreadByAdmin khi ticket đang mở nhận tin mới từ User',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 960);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // 1. Tạo 1 vé "Mới" có mốc thời gian cũ hơn hẳn 32 vé "Đã giải quyết" mới hơn
        const oldNewId = 'ticket_old_new_beyond_30';
        final oldTimeIso = DateTime.utc(2026, 10, 1, 8, 0).toIso8601String();
        await fakeFirestore.collection('support_tickets').doc(oldNewId).set({
          'ticketId': oldNewId,
          'ticketCode': 'SUP-261001-OLDN',
          'userId': 'user_a',
          'userName': 'Nguyễn Văn A',
          'userEmail': 'user_a@gmail.com',
          'category': 'app_guide',
          'title': 'Vé mới cũ nằm ngoài top 30',
          'description': 'Cần hỗ trợ câu hỏi từ đầu tháng trước.',
          'status': 'new',
          'priority': 'normal',
          'assignedAdminId': null,
          'assignedAdminName': null,
          'lastMessageId': 'msg_init_old',
          'lastMessagePreview': 'Cần hỗ trợ câu hỏi từ đầu tháng trước.',
          'lastMessageSenderRole': 'user',
          'lastMessageAt': oldTimeIso,
          'unreadByAdmin': true,
          'unreadByUser': false,
          'createdAt': oldTimeIso,
          'updatedAt': oldTimeIso,
          'resolvedAt': null,
          'closedAt': null,
        });
        await fakeFirestore
            .collection('support_tickets')
            .doc(oldNewId)
            .collection('messages')
            .doc('msg_init_old')
            .set({
          'messageId': 'msg_init_old',
          'senderId': 'user_a',
          'senderRole': 'user',
          'senderDisplayName': 'Nguyễn Văn A',
          'body': 'Cần hỗ trợ câu hỏi từ đầu tháng trước.',
          'messageType': 'text',
          'createdAt': oldTimeIso,
        });

        for (int i = 1; i <= 32; i++) {
          final ts = DateTime.utc(2026, 11, 1, 0, i).toIso8601String();
          final id = 'resolved_recent_$i';
          await fakeFirestore.collection('support_tickets').doc(id).set({
            'ticketId': id,
            'ticketCode': 'SUP-261101-${i.toString().padLeft(4, '0')}',
            'userId': 'user_b',
            'userName': 'Trần Thị B',
            'userEmail': 'user_b@gmail.com',
            'category': 'other',
            'title': 'Vé đã giải quyết #$i',
            'description': 'Đã xử lý xong trước đó.',
            'status': 'resolved',
            'priority': 'normal',
            'assignedAdminId': 'admin_01',
            'assignedAdminName': 'Admin',
            'lastMessagePreview': 'Đã giải quyết.',
            'lastMessageSenderRole': 'system',
            'lastMessageAt': ts,
            'unreadByAdmin': false,
            'unreadByUser': false,
            'createdAt': ts,
            'updatedAt': ts,
            'resolvedAt': ts,
            'closedAt': null,
          });
        }

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AdminSupportCenterView(
                supportService: supportService,
                currentAdminUid: 'admin_01',
                currentAdminName: 'Quản trị viên Hỗ trợ',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Ở chế độ "Tất cả" (top 30 mới nhất), vé mới cũ nằm ở vị trí 33 nên chưa xuất hiện
        expect(
          find.byKey(const ValueKey('admin_ticket_row_$oldNewId')),
          findsNothing,
        );

        // Bấm chip "Mới" -> truy vấn server `statusFilter: newTicket` tìm thấy ngay vé mới cũ!
        await tester.tap(
          find.byKey(const ValueKey('admin_support_status_chip_new')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('admin_ticket_row_$oldNewId')),
          findsOneWidget,
        );

        // 2. Mở ticket -> unreadByAdmin chuyển sang false
        await tester.tap(
          find.byKey(const ValueKey('admin_ticket_row_$oldNewId')),
        );
        await tester.pumpAndSettle();
        var liveTicket = (await supportService.getTicketById(oldNewId))!;
        expect(liveTicket.unreadByAdmin, isFalse);

        // 3. Trong lúc Admin VẪN đang mở ticket trên màn hình, User gửi tin nhắn mới (unreadByAdmin -> true)
        await supportService.sendUserMessage(
          ticket: liveTicket,
          body: 'Mình bổ sung thêm chi tiết khi Admin đang xem màn hình!',
          userIdOverride: 'user_a',
          userNameOverride: 'Nguyễn Văn A',
        );
        await tester.pumpAndSettle();

        // addPostFrameCallback phải tự động gọi markTicketReadByAdmin để tắt unreadByAdmin về false
        liveTicket = (await supportService.getTicketById(oldNewId))!;
        expect(liveTicket.unreadByAdmin, isFalse);
        expect(
          find.textContaining('Mình bổ sung thêm chi tiết'),
          findsWidgets,
        );
      },
    );
  });
}

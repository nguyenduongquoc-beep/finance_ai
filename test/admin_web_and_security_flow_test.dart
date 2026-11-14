import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_ai_app/admin_web/screens/admin_login_screen.dart';
import 'package:finance_ai_app/admin_web/screens/admin_web_shell_screen.dart';
import 'package:finance_ai_app/admin_web/services/admin_web_service.dart';
import 'package:finance_ai_app/models/category_model.dart';
import 'package:finance_ai_app/models/monthly_financial_plan.dart';
import 'package:finance_ai_app/models/user_model.dart';
import 'package:finance_ai_app/screens/notification_screen.dart';
import 'package:finance_ai_app/screens/setup/category_setup_screen.dart';
import 'package:finance_ai_app/services/firestore_service.dart';

/// FirestoreService giả lập lỗi mạng khi truy cập `system_categories`
class _UnreachableSystemCategoriesFirestoreService extends FirestoreService {
  _UnreachableSystemCategoriesFirestoreService({required super.firestore});

  @override
  Future<SystemCategoriesSetupResult> fetchSystemCategoriesForSetup() async {
    return const SystemCategoriesSetupResult(
      activeTemplates: [],
      totalDocsInCollection: 0,
      isFirestoreAccessible: false,
    );
  }
}

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late FirestoreService firestoreService;
  late List<Map<String, dynamic>> cloudFunctionCalls;
  late AdminWebService adminService;

  setUp(() async {
    fakeFirestore = FakeFirebaseFirestore();
    firestoreService = FirestoreService(firestore: fakeFirestore);
    cloudFunctionCalls = [];

    adminService = AdminWebService(
      firestoreService: firestoreService,
      cloudCaller: (functionName, payload) async {
        cloudFunctionCalls.add({
          'functionName': functionName,
          'payload': payload,
        });

        // Mô phỏng chính xác hành vi Backend Cloud Functions (xác thực + ghi Firestore + ghi admin_logs nguyên tử)
        switch (functionName) {
          case 'adminVerifySession':
            return {
              'success': true,
              'uid': 'admin_01',
              'email': 'admin@financeai.vn',
              'name': 'Quản trị viên Hệ thống',
              'role': 'admin',
              'status': 'active',
              'hasAdminClaim': true,
              'hasFirestoreRole': true,
              'claimsSynced': false,
            };
          case 'adminSetUserStatus':
            final targetUid = payload['targetUid'].toString();
            final status = payload['status'].toString();
            final reason = (payload['reason'] ?? '').toString();
            await fakeFirestore.collection('users').doc(targetUid).set({
              'status': status,
              'updatedAt': DateTime(2026, 11, 14).toIso8601String(),
            }, SetOptions(merge: true));
            await fakeFirestore.collection('admin_logs').add({
              'adminId': 'admin_01',
              'adminEmail': 'admin@financeai.vn',
              'action': status == 'locked' ? 'LOCK_USER' : 'UNLOCK_USER',
              'targetType': 'user',
              'targetId': targetUid,
              'details': reason.isNotEmpty
                  ? 'Cập nhật trạng thái $status: $reason'
                  : 'Cập nhật trạng thái $status',
              'createdAt': DateTime(2026, 11, 14, 10).toIso8601String(),
            });
            return {'success': true, 'status': status};
          case 'adminSetUserRole':
            final targetUid = payload['targetUid'].toString();
            final role = payload['role'].toString();
            await fakeFirestore.collection('users').doc(targetUid).set({
              'role': role,
              'updatedAt': DateTime(2026, 11, 14).toIso8601String(),
            }, SetOptions(merge: true));
            await fakeFirestore.collection('admin_logs').add({
              'adminId': 'admin_01',
              'adminEmail': 'admin@financeai.vn',
              'action': role == 'admin' ? 'GRANT_ADMIN' : 'REVOKE_ADMIN',
              'targetType': 'user',
              'targetId': targetUid,
              'details': 'Đổi vai trò thành $role',
              'createdAt': DateTime(2026, 11, 14, 10).toIso8601String(),
            });
            return {'success': true, 'role': role};
          case 'adminManageSystemCategory':
            final action = payload['action'].toString();
            if (action == 'save') {
              final tpl = Map<String, dynamic>.from(payload['template'] as Map);
              final id = tpl['id'].toString();
              await fakeFirestore
                  .collection('system_categories')
                  .doc(id)
                  .set(tpl);
              await fakeFirestore.collection('admin_logs').add({
                'adminId': 'admin_01',
                'adminEmail': 'admin@financeai.vn',
                'action': payload['isNew'] == true
                    ? 'CREATE_SYSTEM_CATEGORY'
                    : 'UPDATE_SYSTEM_CATEGORY',
                'targetType': 'system_category',
                'targetId': id,
                'details': 'Lưu danh mục ${tpl['name']}',
                'createdAt': DateTime(2026, 11, 14, 10).toIso8601String(),
              });
              return {'success': true, 'categoryId': id};
            }
            if (action == 'toggle_active') {
              final id = payload['categoryId'].toString();
              await fakeFirestore.collection('system_categories').doc(id).update({
                'isActive': payload['isActive'],
              });
              await fakeFirestore.collection('admin_logs').add({
                'adminId': 'admin_01',
                'adminEmail': 'admin@financeai.vn',
                'action': 'TOGGLE_SYSTEM_CATEGORY',
                'targetType': 'system_category',
                'targetId': id,
                'details': 'Bật/tắt danh mục',
                'createdAt': DateTime(2026, 11, 14, 10).toIso8601String(),
              });
              return {'success': true};
            }
            if (action == 'seed_defaults') {
              final items = List<Map<String, dynamic>>.from(
                (payload['seedItems'] as List)
                    .map((e) => Map<String, dynamic>.from(e as Map)),
              );
              for (final item in items) {
                final id = item['id'].toString();
                await fakeFirestore.collection('system_categories').doc(id).set({
                  ...item,
                  'isActive': true,
                });
              }
              await fakeFirestore.collection('admin_logs').add({
                'adminId': 'admin_01',
                'adminEmail': 'admin@financeai.vn',
                'action': 'SEED_SYSTEM_CATEGORIES',
                'targetType': 'system_category',
                'targetId': 'batch',
                'details': 'Khởi tạo ${items.length} danh mục chuẩn',
                'createdAt': DateTime(2026, 11, 14, 10).toIso8601String(),
              });
              return {'success': true, 'seededCount': items.length};
            }
            return {'success': true};
          case 'adminManageAnnouncement':
            final action = payload['action'].toString();
            if (action == 'save') {
              final ann = Map<String, dynamic>.from(payload['announcement'] as Map);
              final id = ann['id'].toString();
              await fakeFirestore
                  .collection('system_announcements')
                  .doc(id)
                  .set(ann);
              await fakeFirestore.collection('admin_logs').add({
                'adminId': 'admin_01',
                'adminEmail': 'admin@financeai.vn',
                'action': payload['isNew'] == true
                    ? 'CREATE_ANNOUNCEMENT'
                    : 'UPDATE_ANNOUNCEMENT',
                'targetType': 'system_announcement',
                'targetId': id,
                'details': 'Lưu thông báo ${ann['title']}',
                'createdAt': DateTime(2026, 11, 14, 10).toIso8601String(),
              });
              return {'success': true, 'announcementId': id};
            }
            if (action == 'toggle_active') {
              final id = payload['announcementId'].toString();
              await fakeFirestore
                  .collection('system_announcements')
                  .doc(id)
                  .update({'isActive': payload['isActive']});
              return {'success': true};
            }
            if (action == 'delete') {
              final id = payload['announcementId'].toString();
              await fakeFirestore
                  .collection('system_announcements')
                  .doc(id)
                  .delete();
              return {'success': true};
            }
            return {'success': true};
          default:
            return {'success': true};
        }
      },
    );

    // Khởi tạo tài khoản Admin mặc định và 2 tài khoản User
    await firestoreService.createUserProfile(
      AppUser(
        uid: 'admin_01',
        name: 'Quản trị viên Hệ thống',
        email: 'admin@financeai.vn',
        role: 'admin',
        status: 'active',
        createdAt: DateTime(2026, 9, 10),
      ),
    );

    await firestoreService.createUserProfile(
      AppUser(
        uid: 'user_active_01',
        name: 'Nguyễn Văn A',
        email: 'nguyenvana@gmail.com',
        role: 'user',
        status: 'active',
        createdAt: DateTime(2026, 10, 15),
      ),
    );

    await firestoreService.createUserProfile(
      AppUser(
        uid: 'user_locked_02',
        name: 'Trần Văn B',
        email: 'tranvanb@gmail.com',
        role: 'user',
        status: 'locked',
        createdAt: DateTime(2026, 11, 2),
      ),
    );
  });

  group('Giai đoạn 2: Phân quyền và Đăng nhập Admin', () {
    test('2.1. Xác thực quyền Admin qua Firebase Custom Claims hoặc Firestore role',
        () async {
      // 1. Có Custom Claim admin=true
      final claimRes = await adminService.verifyAdminAccess(
        uidOverride: 'user_active_01',
        tokenClaimsOverride: const {'admin': true},
      );
      expect(claimRes.isAuthorized, isTrue);
      expect(claimRes.hasAdminCustomClaim, isTrue);

      // 2. Có role='admin' trong Firestore
      final roleRes = await adminService.verifyAdminAccess(
        uidOverride: 'admin_01',
        tokenClaimsOverride: const {'admin': false},
      );
      expect(roleRes.isAuthorized, isTrue);
      expect(roleRes.hasAdminFirestoreRole, isTrue);

      // 3. Tài khoản User thường bị từ chối
      final normalUserRes = await adminService.verifyAdminAccess(
        uidOverride: 'user_active_01',
        tokenClaimsOverride: const {'admin': false},
      );
      expect(normalUserRes.isAuthorized, isFalse);
      expect(normalUserRes.errorMessage, contains('Người dùng (User)'));

      // 4. Tài khoản bị khóa (kể cả có claim admin) vẫn bị từ chối
      final lockedRes = await adminService.verifyAdminAccess(
        uidOverride: 'user_locked_02',
        tokenClaimsOverride: const {'admin': true},
      );
      expect(lockedRes.isAuthorized, isFalse);
      expect(lockedRes.isLocked, isTrue);
    });

    testWidgets(
        '2.2. AdminLoginScreen chặn tài khoản User thường, gọi signOut ngay lập tức và hiển thị lỗi',
        (tester) async {
      bool signOutCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: AdminLoginScreen(
            adminService: adminService,
            customSignInUidProvider: (_, __) async => 'user_active_01',
            customSignOutHandler: () async {
              signOutCalled = true;
            },
            tokenClaimsOverride: const {'admin': false},
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey('admin_login_email')),
        'nguyenvana@gmail.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('admin_login_password')),
        '123456',
      );
      await tester.tap(find.byKey(const ValueKey('admin_login_submit_btn')));
      await tester.pumpAndSettle();

      expect(signOutCalled, isTrue);
      expect(
        find.byKey(const ValueKey('admin_login_error_banner')),
        findsOneWidget,
      );
      expect(find.textContaining('Truy cập bị từ chối'), findsOneWidget);
    });

    testWidgets(
        '2.3. AdminWebShellScreen chặn đứng nếu tài khoản không có quyền Admin',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AdminWebShellScreen(
            adminService: adminService,
            adminUidOverride: 'user_active_01',
            tokenClaimsOverride: const {'admin': false},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('admin_unauthorized_guard_view')),
        findsOneWidget,
      );
      expect(find.text('Truy cập bị từ chối'), findsOneWidget);
    });
  });

  group('Giai đoạn 3: Quản lý tài khoản và Cơ chế Khóa / Mở khóa', () {
    test(
        '3.1. Admin khóa và mở khóa tài khoản User -> Đồng bộ Cloud Function, Firestore và ghi Audit Log',
        () async {
      final targetUser =
          (await firestoreService.getUserProfile('user_active_01'))!;
      expect(targetUser.isLocked, isFalse);

      // 1. Khóa tài khoản
      await adminService.setUserAccountStatus(
        adminUid: 'admin_01',
        adminEmail: 'admin@financeai.vn',
        targetUser: targetUser,
        lockAccount: true,
        reason: 'Vi phạm quy định sử dụng',
      );

      // Kiểm tra Cloud Function đã được gọi (adminVerifySession + adminSetUserStatus)
      final statusCalls = cloudFunctionCalls
          .where((c) => c['functionName'] == 'adminSetUserStatus')
          .toList();
      expect(statusCalls.length, 1);
      expect(
        statusCalls.first['payload']['status'],
        'locked',
      );

      // Kiểm tra trạng thái trên Firestore
      final updatedUser =
          (await firestoreService.getUserProfile('user_active_01'))!;
      expect(updatedUser.isLocked, isTrue);

      // Kiểm tra Nhật ký quản trị (admin_logs)
      final logsAfterLock =
          await firestoreService.streamAdminAuditLogs().first;
      expect(logsAfterLock.length, 1);
      expect(logsAfterLock.first.action, 'LOCK_USER');
      expect(logsAfterLock.first.targetId, 'user_active_01');
      expect(logsAfterLock.first.details, contains('Vi phạm quy định sử dụng'));

      // 2. Mở khóa tài khoản
      await adminService.setUserAccountStatus(
        adminUid: 'admin_01',
        adminEmail: 'admin@financeai.vn',
        targetUser: updatedUser,
        lockAccount: false,
        reason: 'Đã xác minh tài khoản',
      );

      final unlockedUser =
          (await firestoreService.getUserProfile('user_active_01'))!;
      expect(unlockedUser.isLocked, isFalse);

      final logsAfterUnlock =
          await firestoreService.streamAdminAuditLogs().first;
      expect(logsAfterUnlock.length, 2);
      expect(
        logsAfterUnlock.any((l) => l.action == 'UNLOCK_USER'),
        isTrue,
      );
    });

    test('3.2. Ngăn Admin tự khóa chính mình và ngăn User thường khóa người khác',
        () async {
      final adminProfile =
          (await firestoreService.getUserProfile('admin_01'))!;
      final targetUser =
          (await firestoreService.getUserProfile('user_active_01'))!;

      // Admin tự khóa chính mình -> Ném lỗi AdminPermissionException
      expect(
        () => adminService.setUserAccountStatus(
          adminUid: 'admin_01',
          adminEmail: 'admin@financeai.vn',
          targetUser: adminProfile,
          lockAccount: true,
        ),
        throwsA(isA<AdminPermissionException>()),
      );

      // User thường gọi hàm khóa -> Ném lỗi AdminPermissionException
      expect(
        () => adminService.setUserAccountStatus(
          adminUid: 'user_active_01',
          adminEmail: 'nguyenvana@gmail.com',
          targetUser: targetUser,
          lockAccount: true,
          tokenClaimsOverride: const {'admin': false},
        ),
        throwsA(isA<AdminPermissionException>()),
      );
    });
  });

  group('Giai đoạn 4: Quản lý Danh mục Hệ thống & Kết nối với User App', () {
    test(
        '4.1. Admin thêm, sửa, ẩn/hiện danh mục hệ thống mà không ảnh hưởng danh mục cá nhân của User hiện tại',
        () async {
      // User hiện tại đã có danh mục cá nhân
      final personalCatId = await firestoreService.createCategory(
        Category(
          categoryId: '',
          userId: 'user_active_01',
          name: 'Ăn uống Cá nhân',
          type: 'expense',
          icon: 'restaurant',
          color: 0xFFEF4444,
          isEssential: false,
        ),
      );

      // Admin thêm danh mục hệ thống
      final sysCatId = await adminService.saveSystemCategory(
        adminUid: 'admin_01',
        adminEmail: 'admin@financeai.vn',
        template: const SystemCategoryTemplate(
          id: 'sys_pet',
          name: 'Chăm sóc Thú cưng',
          type: 'expense',
          icon: 'pets',
          color: 0xFFF97316,
          isEssential: false,
          isActive: true,
        ),
        isNew: true,
      );
      expect(sysCatId, 'sys_pet');

      // Admin ẩn danh mục hệ thống qua isActive=false
      final createdTemplate = (await firestoreService
              .streamSystemCategoryTemplates()
              .first)
          .firstWhere((c) => c.id == 'sys_pet');

      await adminService.toggleSystemCategoryActive(
        adminUid: 'admin_01',
        adminEmail: 'admin@financeai.vn',
        template: createdTemplate,
        isActive: false,
      );

      final activeSetupResult =
          await firestoreService.fetchSystemCategoriesForSetup();
      expect(activeSetupResult.isFirestoreAccessible, isTrue);
      expect(activeSetupResult.activeTemplates, isEmpty);

      // Danh mục cá nhân của User hiện tại vẫn giữ nguyên 100%, không bị ghi đè
      final userCats =
          await firestoreService.streamCategories('user_active_01').first;
      expect(userCats.length, 1);
      expect(userCats.first.categoryId, personalCatId);
      expect(userCats.first.name, 'Ăn uống Cá nhân');
    });

    testWidgets(
        '4.2. CategorySetupScreen đọc danh mục đang hoạt động từ Firestore (system_categories)',
        (tester) async {
      await firestoreService.saveSystemCategoryTemplate(
        const SystemCategoryTemplate(
          id: 'sys_1',
          name: 'Tiền thuê nhà Hệ thống',
          type: 'expense',
          icon: 'home',
          color: 0xFF1F6F8B,
          isEssential: true,
          isActive: true,
        ),
      );
      await firestoreService.saveSystemCategoryTemplate(
        const SystemCategoryTemplate(
          id: 'sys_2',
          name: 'Danh mục Đã Ẩn',
          type: 'expense',
          icon: 'movie',
          color: 0xFF8B5CF6,
          isEssential: false,
          isActive: false,
        ),
      );
      await firestoreService.saveSystemCategoryTemplate(
        const SystemCategoryTemplate(
          id: 'sys_3',
          name: 'Lương Chính thức',
          type: 'income',
          icon: 'work',
          color: 0xFF10B981,
          isActive: true,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: CategorySetupScreen(
            firestoreService: firestoreService,
            userIdOverride: 'user_new_01',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Hiển thị danh mục active từ Firestore, không hiển thị danh mục đã ẩn và không lấy danh sách hardcode
      expect(find.text('Tiền thuê nhà Hệ thống'), findsOneWidget);
      expect(find.text('Thiết yếu'), findsOneWidget);
      expect(find.text('Danh mục Đã Ẩn'), findsNothing);
      expect(find.text('Du lịch'), findsNothing);
    });

    testWidgets(
        '4.3. CategorySetupScreen KHÔNG tự động khôi phục danh mục mặc định nếu collection system_categories rỗng',
        (tester) async {
      // Collection system_categories hoàn toàn rỗng trên Firestore (nhưng truy cập Firestore thành công)
      await tester.pumpWidget(
        MaterialApp(
          home: CategorySetupScreen(
            firestoreService: firestoreService,
            userIdOverride: 'user_new_02',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Chưa có danh mục mặc định trong mục này.'),
        findsOneWidget,
      );
      // Không tự động nạp các danh mục hardcode như 'Ăn uống', 'Mua sắm'
      expect(find.text('Ăn uống'), findsNothing);
      expect(find.text('Mua sắm'), findsNothing);
    });

    testWidgets(
        '4.4. CategorySetupScreen CHỈ fallback về constants.dart khi không thể truy cập nguồn dữ liệu từ Firestore',
        (tester) async {
      final unreachableService = _UnreachableSystemCategoriesFirestoreService(
        firestore: fakeFirestore,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: CategorySetupScreen(
            firestoreService: unreachableService,
            userIdOverride: 'user_new_03',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Khi Firestore không thể truy cập, fallback về danh mục trong constants.dart
      expect(find.text('Ăn uống'), findsOneWidget);
      expect(find.text('Mua sắm'), findsOneWidget);
    });
  });

  group('Giai đoạn 5 & 6: Thông báo Hệ thống, Nhật ký Quản trị & Dashboard', () {
    testWidgets(
        '5.1. Admin đăng thông báo hệ thống -> User App (NotificationScreen) nhận thông báo realtime',
        (tester) async {
      await adminService.saveAnnouncement(
        adminUid: 'admin_01',
        adminEmail: 'admin@financeai.vn',
        announcement: SystemAnnouncement(
          id: 'ann_01',
          title: 'Nâng cấp mô hình AI Gemini',
          content: 'Hệ thống phân tích tài chính đã được nâng cấp.',
          isActive: true,
          createdAt: DateTime(2026, 11, 14, 9, 0),
        ),
        isNew: true,
      );

      await adminService.saveAnnouncement(
        adminUid: 'admin_01',
        adminEmail: 'admin@financeai.vn',
        announcement: SystemAnnouncement(
          id: 'ann_02',
          title: 'Thông báo Đã Tạm Ẩn',
          content: 'Nội dung ẩn',
          isActive: false,
          createdAt: DateTime(2026, 11, 14, 8, 0),
        ),
        isNew: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: NotificationScreen(
            firestoreService: firestoreService,
            userIdOverride: 'user_active_01',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('HỆ THỐNG'), findsOneWidget);
      expect(find.text('Nâng cấp mô hình AI Gemini'), findsOneWidget);
      expect(find.text('Thông báo Đã Tạm Ẩn'), findsNothing);
    });

    test(
        '6.1. Dashboard tính toán chính xác 100% số liệu thực tế từ Users, System Categories và Audit Logs',
        () async {
      await adminService.seedInitialSystemCategories(
        adminUid: 'admin_01',
        adminEmail: 'admin@financeai.vn',
      );

      final users = await firestoreService.streamAllUsersForAdmin().first;
      final categories =
          await firestoreService.streamSystemCategoryTemplates().first;
      final logs = await firestoreService.streamAdminAuditLogs().first;

      final metrics = adminService.computeDashboardMetrics(
        users: users,
        categories: categories,
        logs: logs,
        referenceNow: DateTime(2026, 11, 14),
      );

      expect(metrics.totalUsers, 3);
      expect(metrics.activeUsers, 2);
      expect(metrics.lockedUsers, 1);
      expect(metrics.adminUsers, 1);
      expect(metrics.totalSystemCategories, 10); // 7 chi tiêu + 3 thu nhập
      expect(metrics.activeSystemCategories, 10);
      expect(metrics.monthlyGrowth.length, 6);
      expect(metrics.recentLogs.isNotEmpty, isTrue);
      expect(metrics.recentLogs.first.action, 'SEED_SYSTEM_CATEGORIES');
    });
  });
}

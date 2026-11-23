import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_ai_app/admin_web/screens/admin_announcements_and_logs_view.dart';
import 'package:finance_ai_app/admin_web/screens/admin_categories_view.dart';
import 'package:finance_ai_app/admin_web/screens/admin_login_screen.dart';
import 'package:finance_ai_app/admin_web/screens/admin_overview_view.dart';
import 'package:finance_ai_app/admin_web/screens/admin_support_center_view.dart';
import 'package:finance_ai_app/admin_web/screens/admin_users_view.dart';
import 'package:finance_ai_app/admin_web/screens/admin_web_shell_screen.dart';
import 'package:finance_ai_app/admin_web/services/admin_web_service.dart';
import 'package:finance_ai_app/models/category_model.dart';
import 'package:finance_ai_app/models/monthly_financial_plan.dart';
import 'package:finance_ai_app/models/support_ticket_model.dart';
import 'package:finance_ai_app/models/user_model.dart';
import 'package:finance_ai_app/screens/notification_screen.dart';
import 'package:finance_ai_app/screens/setup/category_setup_screen.dart';
import 'package:finance_ai_app/services/auth_service.dart';
import 'package:finance_ai_app/services/financial_analytics_service.dart';
import 'package:finance_ai_app/services/financial_chat_context_service.dart';
import 'package:finance_ai_app/services/firestore_service.dart';
import 'package:finance_ai_app/services/language_controller.dart';
import 'package:finance_ai_app/services/support_service.dart';
import 'package:finance_ai_app/widgets/locked_account_view.dart';
import 'package:finance_ai_app/widgets/main_navigation.dart';

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
          case 'adminListUsers':
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
    test(
        '2.1. Xác thực quyền Admin bắt buộc users/{uid}.role == admin & status == active (chặn ngay claim admin cũ sau khi hạ quyền)',
        () async {
      // 1. Admin active có cả Custom Claim và role='admin' -> hợp lệ
      final adminClaimRes = await adminService.verifyAdminAccess(
        uidOverride: 'admin_01',
        tokenClaimsOverride: const {'admin': true},
      );
      expect(adminClaimRes.isAuthorized, isTrue);
      expect(adminClaimRes.hasAdminCustomClaim, isTrue);
      expect(adminClaimRes.hasAdminFirestoreRole, isTrue);

      // 2. Admin active có role='admin' trong Firestore (chưa sync claim) -> hợp lệ
      final roleRes = await adminService.verifyAdminAccess(
        uidOverride: 'admin_01',
        tokenClaimsOverride: const {'admin': false},
      );
      expect(roleRes.isAuthorized, isTrue);
      expect(roleRes.hasAdminFirestoreRole, isTrue);

      // 3. Tài khoản User thường (hoặc Admin vừa bị hạ về user) DÙ CÒN claim admin=true -> BỊ TỪ CHỐI NGAY
      final staleClaimRes = await adminService.verifyAdminAccess(
        uidOverride: 'user_active_01',
        tokenClaimsOverride: const {'admin': true},
      );
      expect(staleClaimRes.isAuthorized, isFalse);
      expect(staleClaimRes.errorMessage, contains('Người dùng (User)'));

      // 4. Tài khoản User thường không có claim -> bị từ chối
      final normalUserRes = await adminService.verifyAdminAccess(
        uidOverride: 'user_active_01',
        tokenClaimsOverride: const {'admin': false},
      );
      expect(normalUserRes.isAuthorized, isFalse);
      expect(normalUserRes.errorMessage, contains('Người dùng (User)'));

      // 5. Tài khoản bị khóa (kể cả có claim admin) vẫn bị từ chối
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

    testWidgets(
        '2.4. AdminWebShellScreen lập tức thu hồi phiên realtime khi Admin bị hạ quyền về user dù JWT ban đầu có claim admin=true',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: AdminWebShellScreen(
            adminService: adminService,
            adminUidOverride: 'admin_01',
            tokenClaimsOverride: const {'admin': true},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('admin_unauthorized_guard_view')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('kpi_total_users')), findsOneWidget);

      // Giả lập một Admin khác hạ quyền `admin_01` xuống `user` trên Firestore
      await fakeFirestore
          .collection('users')
          .doc('admin_01')
          .update({'role': 'user'});
      await tester.pumpAndSettle();

      // Realtime Route Guard phải chặn ngay lập tức (không bị giữ phiên vì `hasClaim == true`)
      expect(
        find.byKey(const ValueKey('admin_unauthorized_guard_view')),
        findsOneWidget,
      );
      expect(find.text('Truy cập bị từ chối'), findsOneWidget);
    });
  });

  group('Giai đoạn 3: Quản lý tài khoản và Cơ chế Khóa / Mở khóa (Thuần Spark WriteBatch)', () {
    test(
        '3.1. Admin khóa và mở khóa tài khoản User -> Ghi nguyên tử WriteBatch (status, lockReason, lockedAt, lockedBy) và Audit Log bất biến',
        () async {
      final targetUser =
          (await firestoreService.getUserProfile('user_active_01'))!;
      expect(targetUser.isLocked, isFalse);

      // 1. Khóa tài khoản (100% Spark WriteBatch, không cần gọi Cloud Function)
      await adminService.setUserAccountStatus(
        adminUid: 'admin_01',
        adminEmail: 'admin@financeai.vn',
        targetUser: targetUser,
        lockAccount: true,
        reason: 'Vi phạm quy định sử dụng',
      );

      final statusCalls = cloudFunctionCalls
          .where((c) => c['functionName'] == 'adminSetUserStatus')
          .toList();
      expect(statusCalls, isEmpty);

      // Kiểm tra trạng thái & metadata khóa trên Firestore
      final updatedUser =
          (await firestoreService.getUserProfile('user_active_01'))!;
      expect(updatedUser.isLocked, isTrue);
      expect(updatedUser.lockReason, 'Vi phạm quy định sử dụng');
      expect(updatedUser.lockedAt, isNotNull);
      expect(updatedUser.lockedBy, 'admin@financeai.vn');

      // Kiểm tra Nhật ký quản trị (admin_logs)
      final logsAfterLock =
          await firestoreService.streamAdminAuditLogs().first;
      expect(logsAfterLock.length, 1);
      expect(logsAfterLock.first.action, 'LOCK_USER');
      expect(logsAfterLock.first.targetId, 'user_active_01');
      expect(logsAfterLock.first.source, 'admin_web');
      expect(logsAfterLock.first.details, contains('Vi phạm quy định sử dụng'));

      // 2. Mở khóa tài khoản -> xóa sạch lockReason, lockedAt, lockedBy
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
      expect(unlockedUser.lockReason, isNull);
      expect(unlockedUser.lockedAt, isNull);
      expect(unlockedUser.lockedBy, isNull);

      final logsAfterUnlock =
          await firestoreService.streamAdminAuditLogs().first;
      expect(logsAfterUnlock.length, 2);
      expect(
        logsAfterUnlock.any((l) => l.action == 'UNLOCK_USER'),
        isTrue,
      );
    });

    test('3.2. Ngăn Admin tự khóa chính mình, ngăn khóa Admin khác và ngăn User thường khóa người khác',
        () async {
      final adminProfile =
          (await firestoreService.getUserProfile('admin_01'))!;
      final targetUser =
          (await firestoreService.getUserProfile('user_active_01'))!;

      await firestoreService.createUserProfile(
        AppUser(
          uid: 'admin_02',
          name: 'Quản trị viên 2',
          email: 'admin2@financeai.vn',
          role: 'admin',
          status: 'active',
          createdAt: DateTime(2026, 9, 12),
        ),
      );
      final otherAdmin = (await firestoreService.getUserProfile('admin_02'))!;

      // Admin tự khóa chính mình -> Ném lỗi AdminPermissionException
      expect(
        () => adminService.setUserAccountStatus(
          adminUid: 'admin_01',
          adminEmail: 'admin@financeai.vn',
          targetUser: adminProfile,
          lockAccount: true,
          reason: 'Thử tự khóa',
        ),
        throwsA(isA<AdminPermissionException>()),
      );

      // Admin khóa Admin khác -> Ném lỗi AdminPermissionException
      expect(
        () => adminService.setUserAccountStatus(
          adminUid: 'admin_01',
          adminEmail: 'admin@financeai.vn',
          targetUser: otherAdmin,
          lockAccount: true,
          reason: 'Thử khóa Admin khác',
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
          reason: 'User tự gọi khóa',
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

    testWidgets(
        '4.5. AdminCategoriesManagementView báo lỗi validation khi tên rỗng, bắt lỗi Cloud Function không bị đơ nút và lưu thành công khi hợp lệ',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      bool shouldFailSave = true;
      final testAdminService = AdminWebService(
        firestoreService: firestoreService,
        cloudCaller: (fn, payload) async {
          if (fn == 'adminManageSystemCategory' && shouldFailSave) {
            return {
              'success': false,
              'statusCode': 404,
              'error': 'Cloud Function adminManageSystemCategory chưa được deploy.',
            };
          }
          if (fn == 'adminManageSystemCategory') {
            final tpl = Map<String, dynamic>.from(payload['template'] as Map);
            await fakeFirestore
                .collection('system_categories')
                .doc(tpl['id'].toString())
                .set(tpl);
            return {'success': true, 'categoryId': tpl['id']};
          }
          return {'success': true};
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminCategoriesManagementView(
              adminService: testAdminService,
              currentAdminUid: 'admin_01',
              currentAdminEmail: 'admin@financeai.vn',
              tokenClaimsOverride: const {'admin': true},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Mở dialog Thêm Danh mục Hệ thống
      await tester.tap(find.byKey(const ValueKey('admin_add_category_btn')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // 1. Bấm "Thêm danh mục" khi tên rỗng -> PHẢI hiện lỗi rõ ràng, không im lặng
      await tester.tap(find.byKey(const ValueKey('admin_cat_save_btn')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('admin_cat_form_error')), findsOneWidget);
      expect(
        find.textContaining('Vui lòng nhập tên danh mục'),
        findsOneWidget,
      );

      // 2. Nhập tên nhưng Cloud Function lỗi 404 -> PHẢI bắt lỗi gọn gàng & hiển thị thông báo (không văng Unhandled Exception)
      await tester.enterText(
        find.byKey(const ValueKey('admin_cat_name_input')),
        'Tiền thuê nhà',
      );
      await tester.tap(find.byKey(const ValueKey('admin_cat_save_btn')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('admin_cat_form_error')), findsOneWidget);
      expect(
        find.textContaining('adminManageSystemCategory chưa được deploy'),
        findsWidgets,
      );

      // 3. Khi Cloud Function hoạt động -> lưu thành công, đóng dialog và hiển thị danh mục mới
      shouldFailSave = false;
      await tester.tap(find.byKey(const ValueKey('admin_cat_save_btn')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('admin_cat_save_btn')), findsNothing);
      expect(find.text('Tiền thuê nhà'), findsOneWidget);
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

    testWidgets(
        '5.2. AdminAnnouncementsView yêu cầu hộp thoại xác nhận trước khi xóa và giới hạn nhập liệu 150/1000 ký tự',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await adminService.saveAnnouncement(
        adminUid: 'admin_01',
        adminEmail: 'admin@financeai.vn',
        announcement: SystemAnnouncement(
          id: 'ann_confirm_del',
          title: 'Thông báo cần xác nhận xóa',
          content: 'Nội dung thông báo quan trọng.',
          isActive: true,
          createdAt: DateTime(2026, 11, 14, 9, 0),
        ),
        isNew: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminAnnouncementsView(
              adminService: adminService,
              currentAdminUid: 'admin_01',
              currentAdminEmail: 'admin@financeai.vn',
              tokenClaimsOverride: const {'admin': true},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Kiểm tra giới hạn maxLength trên form tạo mới
      await tester.tap(
        find.byKey(const ValueKey('admin_create_announcement_btn')),
      );
      await tester.pumpAndSettle();
      final titleField = tester.widget<TextField>(
        find.byKey(const ValueKey('admin_ann_title_input')),
      );
      final contentField = tester.widget<TextField>(
        find.byKey(const ValueKey('admin_ann_content_input')),
      );
      expect(titleField.maxLength, 150);
      expect(contentField.maxLength, 1000);
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();

      // Bấm nút xóa -> CHƯA xóa ngay mà phải hiện hộp thoại xác nhận
      await tester.tap(find.byKey(const ValueKey('delete_ann_ann_confirm_del')));
      await tester.pumpAndSettle();
      expect(find.text('Xác nhận xóa thông báo hệ thống'), findsOneWidget);
      expect(
        (await fakeFirestore
                .collection('system_announcements')
                .doc('ann_confirm_del')
                .get())
            .exists,
        isTrue,
      );

      // Xác nhận xóa trong dialog -> mới thực hiện xóa
      await tester.tap(
        find.byKey(const ValueKey('confirm_delete_ann_ann_confirm_del')),
      );
      await tester.pumpAndSettle();
      expect(
        (await fakeFirestore
                .collection('system_announcements')
                .doc('ann_confirm_del')
                .get())
            .exists,
        isFalse,
      );
    });

    test(
        '6.1. Dashboard tính toán chính xác 100% số liệu thực tế qua listUsersViaBackend (Zero-Knowledge), System Categories, Audit Logs và khoảng chia trục Y động',
        () async {
      await adminService.seedInitialSystemCategories(
        adminUid: 'admin_01',
        adminEmail: 'admin@financeai.vn',
      );

      final users = await adminService.listUsersViaBackend(adminUid: 'admin_01');
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

      // Kiểm tra khoảng chia trục Y động tránh chồng chữ khi lượng đăng ký lớn
      expect(computeAdminChartYInterval(4), 1);
      expect(computeAdminChartYInterval(12), 3);
      expect(computeAdminChartYInterval(100), 25);
    });

    test(
        '6.2. listUsersViaBackend dự phòng an toàn (lọc sạch 7 trường) khi Cloud Functions chưa deploy (Spark/404/network), nhưng TUYỆT ĐỐI không fallback khi 401/403',
        () async {
      // Seed thêm dữ liệu tài chính nhạy cảm trên users/user_active_01
      await fakeFirestore.collection('users').doc('user_active_01').set({
        'monthlyIncome': 65000000,
        'savingGoal': 'Mua nhà 2 tỷ',
      }, SetOptions(merge: true));

      // 1. Khi Cloud Functions chưa deploy (404 / network) -> fallback đọc danh sách đã lọc sạch 7 trường phi tài chính
      final sparkService = AdminWebService(
        firestoreService: firestoreService,
        cloudCaller: (fn, payload) async => {
          'success': false,
          'statusCode': 404,
          'error': 'Function not found',
        },
      );
      final fallbackUsers = await sparkService.listUsersViaBackend(
        adminUid: 'admin_01',
        tokenClaimsOverride: const {'admin': true},
      );
      expect(fallbackUsers.length, 3);
      final sanitizedUser =
          fallbackUsers.firstWhere((u) => u.uid == 'user_active_01');
      expect(sanitizedUser.email, 'nguyenvana@gmail.com');
      expect(sanitizedUser.monthlyIncome, 0);
      expect(sanitizedUser.savingGoal, isNull);

      // 2. Khi Backend từ chối 403 Forbidden -> TUYỆT ĐỐI không fallback, phải ném lỗi
      final forbiddenService = AdminWebService(
        firestoreService: firestoreService,
        cloudCaller: (fn, payload) async => {
          'success': false,
          'statusCode': 403,
          'error': 'Không đủ quyền Admin.',
        },
      );
      await expectLater(
        () => forbiddenService.listUsersViaBackend(
          adminUid: 'admin_01',
          tokenClaimsOverride: const {'admin': true},
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('Giai đoạn 7: Chế độ Firebase Spark đồng bộ trực tiếp qua Firestore WriteBatch', () {
    test(
        '7.1. AdminWebService mặc định (Spark, useCloudFunctions=false) xác minh quyền, đọc danh sách lọc 7 trường, quản lý user + chống khóa/hạ quyền Admin cuối cùng và ghi admin_logs đồng bộ',
        () async {
      // Khởi tạo mặc định KHÔNG truyền cloudCaller -> chạy Spark-native trực tiếp trên Firestore
      final sparkAdmin = AdminWebService(
        firestoreService: firestoreService,
        useCloudFunctions: false,
      );
      expect(sparkAdmin.useCloudFunctions, isFalse);

      // 1. Xác minh quyền Admin trực tiếp qua Firestore (active admin ok, user thường & claim giả bị chặn)
      final okCheck = await sparkAdmin.verifyAdminAccess(uidOverride: 'admin_01');
      expect(okCheck.isAuthorized, isTrue);
      expect(okCheck.hasAdminFirestoreRole, isTrue);

      final demotedStaleClaim = await sparkAdmin.verifyAdminAccess(
        uidOverride: 'user_active_01',
        tokenClaimsOverride: const {'admin': true},
      );
      expect(demotedStaleClaim.isAuthorized, isFalse);

      // 2. listUsersViaBackend đọc trực tiếp Firestore nhưng lọc sạch dữ liệu tài chính nhạy cảm
      await fakeFirestore.collection('users').doc('user_active_01').set({
        'monthlyIncome': 88000000,
        'savingGoal': 'Bí mật tài chính',
      }, SetOptions(merge: true));
      final users = await sparkAdmin.listUsersViaBackend(adminUid: 'admin_01');
      expect(users.length, 3);
      final targetUser = users.firstWhere((u) => u.uid == 'user_active_01');
      expect(targetUser.monthlyIncome, 0);
      expect(targetUser.savingGoal, isNull);

      // 3. Khóa và mở khóa tài khoản user -> cập nhật users/{uid} (status, lockReason, lockedAt, lockedBy) + ghi admin_logs
      await sparkAdmin.setUserAccountStatus(
        adminUid: 'admin_01',
        adminEmail: 'admin@financeai.vn',
        targetUser: targetUser,
        lockAccount: true,
        reason: 'Kiểm thử khóa trên Spark',
      );
      final lockedSnap =
          (await fakeFirestore.collection('users').doc('user_active_01').get())
              .data()!;
      expect(lockedSnap['status'], 'locked');
      expect(lockedSnap['lockReason'], 'Kiểm thử khóa trên Spark');
      expect(lockedSnap['lockedAt'], isNotNull);
      expect(lockedSnap['lockedBy'], 'admin@financeai.vn');

      await sparkAdmin.setUserAccountStatus(
        adminUid: 'admin_01',
        adminEmail: 'admin@financeai.vn',
        targetUser: targetUser,
        lockAccount: false,
      );
      final unlockedSnap =
          (await fakeFirestore.collection('users').doc('user_active_01').get())
              .data()!;
      expect(unlockedSnap['status'], 'active');
      expect(unlockedSnap['lockReason'], isNull);
      expect(unlockedSnap['lockedAt'], isNull);
      expect(unlockedSnap['lockedBy'], isNull);

      // 4. Chặn khóa chính mình và chặn khóa tài khoản Admin khác
      await fakeFirestore.collection('users').doc('admin_02').set(
            AppUser(
              uid: 'admin_02',
              name: 'Admin 2',
              email: 'admin2@financeai.vn',
              role: 'admin',
              status: 'active',
              createdAt: DateTime(2026, 9, 2),
            ).toMap(),
          );
      await expectLater(
        () => sparkAdmin.setUserAccountStatus(
          adminUid: 'admin_01',
          adminEmail: 'admin@financeai.vn',
          targetUser: AppUser(
            uid: 'admin_01',
            name: 'Admin',
            email: 'admin@financeai.vn',
            role: 'admin',
            status: 'active',
            createdAt: DateTime(2026, 9, 1),
          ),
          lockAccount: true,
          reason: 'Thử tự khóa',
        ),
        throwsA(isA<AdminPermissionException>()),
      );
      await expectLater(
        () => sparkAdmin.setUserAccountStatus(
          adminUid: 'admin_01',
          adminEmail: 'admin@financeai.vn',
          targetUser: AppUser(
            uid: 'admin_02',
            name: 'Admin 2',
            email: 'admin2@financeai.vn',
            role: 'admin',
            status: 'active',
            createdAt: DateTime(2026, 9, 2),
          ),
          lockAccount: true,
          reason: 'Thử khóa Admin khác',
        ),
        throwsA(isA<AdminPermissionException>()),
      );

      // Kiểm tra nhật ký quản trị đã được ghi đầy đủ trong admin_logs với source='admin_web'
      final logsSnap = await fakeFirestore.collection('admin_logs').get();
      final actions = logsSnap.docs.map((d) => d.data()['action']).toList();
      expect(actions, containsAll(['LOCK_USER', 'UNLOCK_USER']));
      expect(
        logsSnap.docs.every((d) => d.data()['source'] == 'admin_web'),
        isTrue,
      );
    });

    test(
        '7.2. Chế độ Firebase Spark đồng bộ đầy đủ Danh mục Hệ thống & Thông báo Hệ thống (giữ nguyên createdBy khi sửa) kèm Audit Logs',
        () async {
      final sparkAdmin = AdminWebService(
        firestoreService: firestoreService,
        useCloudFunctions: false,
      );

      // 1. Khởi tạo bộ danh mục chuẩn, thêm mới, chỉnh sửa và ẩn/hiện danh mục hệ thống
      await sparkAdmin.seedInitialSystemCategories(
        adminUid: 'admin_01',
        adminEmail: 'admin@financeai.vn',
      );
      final seeded = await fakeFirestore.collection('system_categories').get();
      expect(seeded.docs.length, 10);

      final createdCatId = await sparkAdmin.saveSystemCategory(
        adminUid: 'admin_01',
        adminEmail: 'admin@financeai.vn',
        template: const SystemCategoryTemplate(
          id: '',
          name: 'Học phí đại học',
          type: 'expense',
          icon: 'school',
          color: 0xFF3B82F6,
          isEssential: true,
          isActive: true,
        ),
        isNew: true,
      );
      expect(createdCatId.isNotEmpty, isTrue);

      await sparkAdmin.toggleSystemCategoryActive(
        adminUid: 'admin_01',
        adminEmail: 'admin@financeai.vn',
        template: SystemCategoryTemplate(
          id: createdCatId,
          name: 'Học phí đại học',
          type: 'expense',
          icon: 'school',
          color: 0xFF3B82F6,
          isEssential: true,
          isActive: true,
        ),
        isActive: false,
      );
      expect(
        (await fakeFirestore
                .collection('system_categories')
                .doc(createdCatId)
                .get())
            .data()?['isActive'],
        isFalse,
      );

      // 2. Tạo thông báo bởi admin_01, chỉnh sửa bởi admin_02 -> giữ nguyên createdBy gốc & cập nhật updatedBy
      await fakeFirestore.collection('users').doc('admin_02').set(
            AppUser(
              uid: 'admin_02',
              name: 'Admin 2',
              email: 'admin2@financeai.vn',
              role: 'admin',
              status: 'active',
              createdAt: DateTime(2026, 9, 2),
            ).toMap(),
          );
      final annId = await sparkAdmin.saveAnnouncement(
        adminUid: 'admin_01',
        adminEmail: 'admin@financeai.vn',
        announcement: SystemAnnouncement(
          id: 'ann_spark_01',
          title: 'Thông báo bản cập nhật',
          content: 'Phiên bản mới đã sẵn sàng.',
          isActive: true,
          createdAt: DateTime(2026, 11, 22, 10, 0),
        ),
        isNew: true,
      );
      expect(annId, 'ann_spark_01');

      await sparkAdmin.saveAnnouncement(
        adminUid: 'admin_02',
        adminEmail: 'admin2@financeai.vn',
        announcement: SystemAnnouncement(
          id: 'ann_spark_01',
          title: 'Thông báo bản cập nhật v2',
          content: 'Đã bổ sung tính năng mới.',
          isActive: true,
          createdAt: DateTime(2026, 11, 22, 11, 0),
        ),
        isNew: false,
      );
      final updatedAnn = (await fakeFirestore
              .collection('system_announcements')
              .doc('ann_spark_01')
              .get())
          .data()!;
      expect(updatedAnn['title'], 'Thông báo bản cập nhật v2');
      expect(updatedAnn['createdBy'], 'admin@financeai.vn');
      expect(updatedAnn['updatedBy'], 'admin2@financeai.vn');

      // 3. Tắt hiển thị và xóa thông báo hệ thống
      await sparkAdmin.toggleAnnouncementActive(
        adminUid: 'admin_02',
        adminEmail: 'admin2@financeai.vn',
        announcement: SystemAnnouncement(
          id: 'ann_spark_01',
          title: 'Thông báo bản cập nhật v2',
          content: 'Đã bổ sung tính năng mới.',
          isActive: true,
          createdAt: DateTime(2026, 11, 22, 10, 0),
        ),
        isActive: false,
      );
      expect(
        (await fakeFirestore
                .collection('system_announcements')
                .doc('ann_spark_01')
                .get())
            .data()?['isActive'],
        isFalse,
      );

      await sparkAdmin.deleteAnnouncement(
        adminUid: 'admin_02',
        adminEmail: 'admin2@financeai.vn',
        announcement: SystemAnnouncement(
          id: 'ann_spark_01',
          title: 'Thông báo bản cập nhật v2',
          content: 'Đã bổ sung tính năng mới.',
          isActive: false,
          createdAt: DateTime(2026, 11, 22, 10, 0),
        ),
      );
      expect(
        (await fakeFirestore
                .collection('system_announcements')
                .doc('ann_spark_01')
                .get())
            .exists,
        isFalse,
      );

      final logsSnap = await fakeFirestore.collection('admin_logs').get();
      final actions = logsSnap.docs.map((d) => d.data()['action']).toList();
      expect(
        actions,
        containsAll([
          'SEED_SYSTEM_CATEGORIES',
          'CREATE_SYSTEM_CATEGORY',
          'HIDE_SYSTEM_CATEGORY',
          'CREATE_ANNOUNCEMENT',
          'UPDATE_ANNOUNCEMENT',
          'DEACTIVATE_ANNOUNCEMENT',
          'DELETE_ANNOUNCEMENT',
        ]),
      );
    });
  });

  group('Giai đoạn 8: Spark User Management Redesign, Zero-Knowledge Private Profile, Mobile Lock Sync & Self-Delete', () {
    test(
        '8.1. Zero-Knowledge: tách monthlyIncome/savingGoal sang users/{uid}/private/financial_profile, fallback dữ liệu cũ & AI Insight / AI Chat đọc trơn tru',
        () async {
      // 1. Tạo user mới có monthlyIncome -> root users/{uid} TUYỆT ĐỐI không chứa trường tài chính
      await firestoreService.createUserProfile(
        AppUser(
          uid: 'user_zk_new',
          name: 'Người dùng Mới',
          email: 'new@financeai.vn',
          monthlyIncome: 30000000,
          savingGoal: 'Quỹ dự phòng 100 triệu',
          authProvider: 'google',
          createdAt: DateTime(2026, 11, 20),
        ),
      );
      final rootNew =
          (await fakeFirestore.collection('users').doc('user_zk_new').get())
              .data()!;
      expect(rootNew.containsKey('monthlyIncome'), isFalse);
      expect(rootNew.containsKey('savingGoal'), isFalse);

      final privNew = (await fakeFirestore
              .collection('users')
              .doc('user_zk_new')
              .collection('private')
              .doc('financial_profile')
              .get())
          .data()!;
      expect(privNew['monthlyIncome'], 30000000.0);
      expect(privNew['savingGoal'], 'Quỹ dự phòng 100 triệu');

      // 2. Dữ liệu legacy nằm trên root users/{uid} -> Mobile vẫn đọc fallback trơn tru cho AI Insight & AI Chat
      await fakeFirestore.collection('users').doc('user_zk_legacy').set({
        'name': 'Người dùng Cũ',
        'email': 'legacy@financeai.vn',
        'role': 'user',
        'status': 'active',
        'monthlyIncome': 18000000.0,
        'savingGoal': 'Mua xe',
        'createdAt': DateTime(2026, 8, 1).toIso8601String(),
      });

      final legacyUser = await firestoreService.getUserProfile('user_zk_legacy');
      expect(legacyUser?.monthlyIncome, 18000000.0);
      expect(legacyUser?.savingGoal, 'Mua xe');

      // Kiểm chứng AI Chat Context & AI Analytics dùng đúng thu nhập khai báo từ profile đã tách
      final chatContext = await FinancialChatContextService(
        firestoreService: firestoreService,
      ).buildContext('user_zk_legacy');
      expect(chatContext.rawPromptContext, contains('18'));

      final analyticsAssessment =
          FinancialAnalyticsService().determineReferenceIncome(
        currentMonthTx: const [],
        historicalMonthsTx: const [[], [], []],
        currentBudgets: const [],
        declaredExpectedIncome: legacyUser?.monthlyIncome,
        isPartialMonth: true,
      );
      expect(analyticsAssessment.referenceIncome, 18000000.0);

      // 3. Khi cập nhật thu nhập dự kiến -> chỉ ghi vào private/financial_profile & xóa sạch trường cũ khỏi root users/{uid}
      await firestoreService.updatePrivateFinancialProfile(
        'user_zk_legacy',
        monthlyIncome: 24000000.0,
      );
      final cleanedRoot =
          (await fakeFirestore.collection('users').doc('user_zk_legacy').get())
              .data()!;
      expect(cleanedRoot.containsKey('monthlyIncome'), isFalse);
      expect(cleanedRoot.containsKey('savingGoal'), isFalse);

      final migratedUser =
          await firestoreService.getUserProfile('user_zk_legacy');
      expect(migratedUser?.monthlyIncome, 24000000.0);

      // AI Chat Context tự động đọc được giá trị 24.000.000 mới từ private/financial_profile
      final chatContextAfter = await FinancialChatContextService(
        firestoreService: firestoreService,
      ).buildContext('user_zk_legacy');
      expect(chatContextAfter.rawPromptContext, contains('24'));

      // Admin stream tuyệt đối không thấy dữ liệu tiền bạc
      final adminUsers =
          await firestoreService.streamUsersDirectoryForAdmin(limit: 25).first;
      for (final u in adminUsers) {
        expect(u.monthlyIncome, 0);
        expect(u.savingGoal, isNull);
      }
    });

    testWidgets(
        '8.2. AdminUsersManagementView: Ẩn nút Cấp/Hạ quyền & Xóa, bảo vệ mọi tài khoản Admin, hộp thoại khóa bắt buộc ghi chú khi chọn Lý do khác',
        (tester) async {
      tester.view.physicalSize = const Size(1440, 960);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await firestoreService.createUserProfile(
        AppUser(
          uid: 'admin_02',
          name: 'Admin Phụ',
          email: 'admin2@financeai.vn',
          role: 'admin',
          status: 'active',
          createdAt: DateTime(2026, 9, 12),
        ),
      );

      final sparkAdmin = AdminWebService(
        firestoreService: firestoreService,
        useCloudFunctions: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminUsersManagementView(
              adminService: sparkAdmin,
              currentAdminUid: 'admin_01',
              currentAdminEmail: 'admin@financeai.vn',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Không có nút đổi quyền, nút xóa, hay nút khóa trên admin_01 & admin_02
      expect(find.byKey(const ValueKey('toggle_role_user_active_01')), findsNothing);
      expect(find.byKey(const ValueKey('delete_user_user_active_01')), findsNothing);
      expect(find.byKey(const ValueKey('toggle_lock_admin_01')), findsNothing);
      expect(find.byKey(const ValueKey('toggle_lock_admin_02')), findsNothing);
      expect(find.byKey(const ValueKey('admin_readonly_badge_admin_01')), findsOneWidget);
      expect(find.byKey(const ValueKey('admin_readonly_badge_admin_02')), findsOneWidget);

      // Mở hộp thoại khóa user_active_01 -> chọn "Lý do khác" để trống ghi chú -> báo lỗi bắt buộc nhập
      await tester.tap(find.byKey(const ValueKey('toggle_lock_user_active_01')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('lock_reason_preset_other')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('admin_confirm_lock_btn')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Vui lòng nhập ghi chú chi tiết'), findsOneWidget);

      // Nhập ghi chú chi tiết -> xác nhận khóa thành công
      await tester.enterText(
        find.byKey(const ValueKey('admin_lock_reason_input')),
        'Phát hiện spam nhiều tài khoản ảo',
      );
      await tester.tap(find.byKey(const ValueKey('admin_confirm_lock_btn')));
      await tester.pumpAndSettle();

      final locked = (await firestoreService.getUserProfile('user_active_01'))!;
      expect(locked.isLocked, isTrue);
      expect(locked.lockReason, 'Phát hiện spam nhiều tài khoản ảo');
      expect(locked.lockedAt, isNotNull);
      expect(locked.lockedBy, 'admin@financeai.vn');
    });

    testWidgets(
        '8.3. Mobile LockedAccountView & MainNavigation hiển thị rõ Lý do khóa + Thời điểm khóa (Vi/En) và fallback dữ liệu cũ',
        (tester) async {
      await fakeFirestore.collection('users').doc('user_locked_detail').set({
        'name': 'User Bị Khóa',
        'email': 'locked@financeai.vn',
        'role': 'user',
        'status': 'locked',
        'lockReason': 'Gửi tin nhắn rác / Lạm dụng hệ thống hỗ trợ',
        'lockedAt': DateTime(2026, 11, 22, 10, 30).toIso8601String(),
        'lockedBy': 'admin@financeai.vn',
        'createdAt': DateTime(2026, 10, 1).toIso8601String(),
      });

      bool signedOut = false;
      await tester.pumpWidget(
        MaterialApp(
          home: MainNavigation(
            firestoreService: firestoreService,
            userIdOverride: 'user_locked_detail',
            customSignOutHandler: () async {
              signedOut = true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('mobile_locked_details_card')),
        findsOneWidget,
      );
      expect(
        find.text('Gửi tin nhắn rác / Lạm dụng hệ thống hỗ trợ'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('mobile_locked_time_text')),
        findsOneWidget,
      );

      // Kiểm tra helper thông báo đăng nhập cho cả trường hợp có lý do và dữ liệu cũ thiếu lý do (Vi & En)
      final withReason =
          (await firestoreService.getUserProfile('user_locked_detail'))!;
      expect(
        formatLockedAccountLoginError(withReason),
        contains('Gửi tin nhắn rác / Lạm dụng hệ thống hỗ trợ'),
      );

      final legacyLocked =
          (await firestoreService.getUserProfile('user_locked_02'))!;
      expect(
        formatLockedAccountLoginError(legacyLocked),
        contains('hạn chế theo chính sách'),
      );

      // Chuyển ngôn ngữ sang tiếng Anh -> thông báo fallback & nhãn hiển thị chuẩn En
      LanguageController.currentLocale.value = const Locale('en', 'US');
      addTearDown(
        () => LanguageController.currentLocale.value = const Locale('vi', 'VN'),
      );
      expect(
        formatLockedAccountLoginError(legacyLocked),
        contains('temporarily restricted'),
      );

      await tester.tap(find.byKey(const ValueKey('mobile_locked_logout_btn')));
      await tester.pumpAndSettle();
      expect(signedOut, isTrue);
    });

    testWidgets(
        '8.4. Hồ sơ chi tiết 3 khối hiển thị vé hỗ trợ + lịch sử log và bấm vào vé chuyển thẳng sang Tab Hỗ trợ chọn đúng vé',
        (tester) async {
      tester.view.physicalSize = const Size(1440, 960);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final sparkAdmin = AdminWebService(
        firestoreService: firestoreService,
        useCloudFunctions: false,
      );
      final supportService = SupportService(firestore: fakeFirestore);

      // Seed 1 vé hỗ trợ cho user_active_01
      final ticket = await supportService.createTicket(
        category: SupportCategory.bugReport,
        title: 'Không mở được báo cáo tháng 11',
        description: 'Nhờ Admin kiểm tra lỗi hiển thị biểu đồ báo cáo tháng.',
        userIdOverride: 'user_active_01',
        userNameOverride: 'Nguyễn Văn A',
        userEmailOverride: 'nguyenvana@gmail.com',
      );

      // Seed 1 lịch sử tác động quản trị trên user_active_01
      await sparkAdmin.setUserAccountStatus(
        adminUid: 'admin_01',
        adminEmail: 'admin@financeai.vn',
        targetUser: (await firestoreService.getUserProfile('user_active_01'))!,
        lockAccount: true,
        reason: 'Kiểm tra lịch sử khóa',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AdminWebShellScreen(
            adminService: sparkAdmin,
            supportService: supportService,
            adminUidOverride: 'admin_01',
            initialIndex: 1,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Mở dialog Hồ sơ vận hành chi tiết của user_active_01
      await tester.tap(find.byKey(const ValueKey('view_user_user_active_01')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('user_detail_identity_block')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('user_detail_lock_block')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('user_detail_tickets_block')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('user_detail_logs_block')),
        findsOneWidget,
      );
      expect(find.textContaining('Không mở được báo cáo tháng 11'), findsOneWidget);
      expect(find.textContaining('Kiểm tra lịch sử khóa'), findsWidgets);

      // Bấm vào vé hỗ trợ trong Khối 2 -> đóng dialog & chuyển thẳng sang Tab Tư vấn & Hỗ trợ với đúng vé đang mở
      final ticketRowFinder =
          find.byKey(ValueKey('user_detail_ticket_${ticket.ticketId}'));
      await tester.ensureVisible(ticketRowFinder);
      await tester.pumpAndSettle();
      await tester.tap(ticketRowFinder);
      await tester.pumpAndSettle();

      expect(find.byType(AdminSupportCenterView), findsOneWidget);
      expect(
        find.textContaining('Nhờ Admin kiểm tra lỗi hiển thị biểu đồ báo cáo tháng.'),
        findsWidgets,
      );
    });

    test(
        '8.5. Luồng User tự Xóa tài khoản trên Mobile (Spark): re-auth trước -> xóa batch >400 docs & 4 subcollections -> xóa users/{uid} -> giữ nguyên support_tickets & user khác -> xóa Auth',
        () async {
      const targetUid = 'user_self_del';
      const otherUid = 'user_other_safe';

      await fakeFirestore.collection('users').doc(targetUid).set({
        'name': 'User Tự Xóa',
        'email': 'selfdel@financeai.vn',
        'role': 'user',
        'status': 'active',
        'createdAt': DateTime(2026, 10, 1).toIso8601String(),
      });
      await fakeFirestore.collection('users').doc(otherUid).set({
        'name': 'User Khác',
        'email': 'other@financeai.vn',
        'role': 'user',
        'status': 'active',
        'createdAt': DateTime(2026, 10, 1).toIso8601String(),
      });

      // Seed 450 giao dịch (> batchSize 400) + các collection khác
      for (int i = 0; i < 450; i++) {
        await fakeFirestore.collection('transactions').doc('tx_$i').set({
          'userId': targetUid,
          'amount': 10000,
        });
      }
      await fakeFirestore.collection('transactions').doc('tx_other').set({
        'userId': otherUid,
        'amount': 99000,
      });

      for (final col in [
        'wallets',
        'budgets',
        'categories',
        'savingGoals',
        'monthly_plans',
        'notifications',
        'recurringTransactions',
        'recurringTransactionOccurrences',
      ]) {
        await fakeFirestore.collection(col).doc('${col}_1').set({
          'userId': targetUid,
        });
        await fakeFirestore.collection(col).doc('${col}_other').set({
          'userId': otherUid,
        });
      }

      for (final sub in [
        'private',
        'quickTemplates',
        'chat_sessions',
        'monthly_plans',
      ]) {
        await fakeFirestore
            .collection('users')
            .doc(targetUid)
            .collection(sub)
            .doc('doc_1')
            .set({'v': 1});
      }

      // support_tickets phải được bảo toàn (rules cấm xóa)
      await fakeFirestore.collection('support_tickets').doc('sup_keep_1').set({
        'userId': targetUid,
        'title': 'Vé đối soát giữ lại',
      });

      final callOrder = <String>[];
      final authService = AuthService(firestoreService: firestoreService);
      final deletedCount = await authService.executeSelfDeleteFlow(
        uid: targetUid,
        reauthenticate: () async {
          callOrder.add('reauthenticate');
        },
        deleteAuthAccount: () async {
          callOrder.add('deleteAuth');
          // Lúc xóa Auth thì users/{uid} đã được dọn sạch xong
          final stillExists =
              (await fakeFirestore.collection('users').doc(targetUid).get())
                  .exists;
          expect(stillExists, isFalse);
        },
      );

      expect(callOrder, ['reauthenticate', 'deleteAuth']);
      expect(deletedCount, 450 + 8 + 4 + 1);

      // Toàn bộ dữ liệu của targetUid đã sạch
      expect(
        (await fakeFirestore
                .collection('transactions')
                .where('userId', isEqualTo: targetUid)
                .get())
            .docs,
        isEmpty,
      );
      expect(
        (await fakeFirestore
                .collection('users')
                .doc(targetUid)
                .collection('private')
                .get())
            .docs,
        isEmpty,
      );
      expect(
        (await fakeFirestore.collection('users').doc(targetUid).get()).exists,
        isFalse,
      );

      // support_tickets và dữ liệu của user khác còn nguyên vẹn 100%
      expect(
        (await fakeFirestore
                .collection('support_tickets')
                .doc('sup_keep_1')
                .get())
            .exists,
        isTrue,
      );
      expect(
        (await fakeFirestore.collection('transactions').doc('tx_other').get())
            .exists,
        isTrue,
      );
    });

    test(
        '8.6. touchUserPresenceAndProvider ghi authProvider & lastActiveAt theo cơ chế throttle >= 6 giờ và bỏ qua user đang bị khóa',
        () async {
      final t0 = DateTime.utc(2026, 11, 22, 8, 0);
      final firstTouch = await firestoreService.touchUserPresenceAndProvider(
        uid: 'user_active_01',
        authProvider: 'password',
        nowOverride: t0,
      );
      expect(firstTouch, isTrue);

      // Sau 2 giờ (< 6 giờ) -> bỏ qua ghi để tiết kiệm lượt ghi Spark
      final throttledTouch =
          await firestoreService.touchUserPresenceAndProvider(
        uid: 'user_active_01',
        authProvider: 'password',
        nowOverride: t0.add(const Duration(hours: 2)),
      );
      expect(throttledTouch, isFalse);

      // Sau 7 giờ (>= 6 giờ) -> cập nhật lastActiveAt mới
      final laterTouch = await firestoreService.touchUserPresenceAndProvider(
        uid: 'user_active_01',
        authProvider: 'password',
        nowOverride: t0.add(const Duration(hours: 7)),
      );
      expect(laterTouch, isTrue);

      // User đang bị khóa -> tuyệt đối không ghi
      final lockedTouch = await firestoreService.touchUserPresenceAndProvider(
        uid: 'user_locked_02',
        authProvider: 'google',
        nowOverride: t0,
      );
      expect(lockedTouch, isFalse);
    });
  });
}

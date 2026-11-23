import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_ai_app/admin_web/screens/admin_web_shell_screen.dart';
import 'package:finance_ai_app/admin_web/services/admin_web_service.dart';
import 'package:finance_ai_app/models/admin_audit_log_model.dart';
import 'package:finance_ai_app/models/monthly_financial_plan.dart';
import 'package:finance_ai_app/models/user_model.dart';
import 'package:finance_ai_app/services/firestore_service.dart';

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late FirestoreService firestoreService;
  late List<Map<String, dynamic>> cloudCalls;
  late AdminWebService adminService;

  setUp(() async {
    fakeFirestore = FakeFirebaseFirestore();
    firestoreService = FirestoreService(firestore: fakeFirestore);
    cloudCalls = [];

    await fakeFirestore.collection('users').doc('admin_01').set(
          AppUser(
            uid: 'admin_01',
            name: 'Quản trị viên Hệ thống',
            email: 'admin@financeai.vn',
            role: 'admin',
            status: 'active',
            createdAt: DateTime(2026, 9, 1),
          ).toMap(),
        );
    await fakeFirestore.collection('users').doc('user_01').set(
          AppUser(
            uid: 'user_01',
            name: 'Nguyễn Văn An',
            email: 'an@gmail.com',
            role: 'user',
            status: 'active',
            createdAt: DateTime(2026, 10, 5),
          ).toMap(),
        );

    await fakeFirestore.collection('system_categories').doc('sys_1').set(
          const SystemCategoryTemplate(
            id: 'sys_1',
            name: 'Ăn uống',
            type: 'expense',
            icon: 'restaurant',
            color: 0xFFEF4444,
            isEssential: false,
            isActive: true,
          ).toMap(),
        );

    // Seed 1 bản ghi nhật ký cũ (legacy AI config) để xác nhận tab Nhật ký hiển thị an toàn
    await fakeFirestore.collection('admin_logs').doc('legacy_ai_log_1').set(
          AdminAuditLog(
            id: 'legacy_ai_log_1',
            adminId: 'admin_01',
            adminEmail: 'admin@financeai.vn',
            action: 'PUBLISH_CONFIG',
            targetType: 'config',
            targetId: 'ai_runtime',
            targetLabel: 'ai_runtime v1',
            details: 'Bản ghi lịch sử cũ trước khi tinh gọn phân hệ AI',
            source: 'cloud_function',
            createdAt: DateTime(2026, 11, 1, 8, 30),
          ).toMap(),
        );

    adminService = AdminWebService(
      firestoreService: firestoreService,
      cloudCaller: (functionName, payload) async {
        cloudCalls.add({'functionName': functionName, 'payload': payload});
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
          case 'adminSetUserRole':
            await fakeFirestore
                .collection('users')
                .doc(payload['targetUid'].toString())
                .set({'role': payload['role']}, SetOptions(merge: true));
            return {'success': true, 'role': payload['role']};
          default:
            return {'success': true};
        }
      },
    );
  });

  void setDesktopViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1440, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  group('Admin Web UI — 6-Tab Core Platform Ops Shell & Dashboard', () {
    testWidgets(
      '1. Shell hiển thị đúng 6 khu vực quản trị cốt lõi, không còn 4 phân hệ AI, giữ Guard, hiển thị an toàn log cũ & hỗ trợ Responsive hẹp',
      (tester) async {
        setDesktopViewport(tester);

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

        expect(find.text('Dashboard Tổng quan'), findsAtLeastNWidgets(1));
        expect(find.text('Quản lý Người dùng'), findsOneWidget);
        expect(find.text('Danh mục Hệ thống'), findsOneWidget);
        expect(find.text('Thông báo Hệ thống'), findsOneWidget);
        expect(find.text('Nhật ký Quản trị'), findsOneWidget);
        expect(find.text('Tư vấn & Hỗ trợ'), findsOneWidget);

        // Xác nhận hoàn toàn không còn các mục điều hướng AI Governance đã gỡ bỏ
        expect(find.text('AI Studio & Sandbox'), findsNothing);
        expect(find.text('Platform Ops'), findsNothing);
        expect(find.byKey(const ValueKey('kpi_ai_runtime')), findsNothing);

        // Kiểm tra 4 thẻ KPI Dashboard cốt lõi
        expect(find.byKey(const ValueKey('kpi_total_users')), findsOneWidget);
        expect(find.byKey(const ValueKey('kpi_active_users')), findsOneWidget);
        expect(find.byKey(const ValueKey('kpi_locked_users')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('kpi_system_categories')),
          findsOneWidget,
        );

        // Điều hướng qua tab Quản lý Người dùng (index 1) -> thuần Spark, gỡ nút Đổi vai trò & Xóa, chỉ còn Chi tiết + Khóa/Mở khóa
        await tester.tap(find.byKey(const ValueKey('admin_nav_tab_1')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('admin_users_refresh_btn')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('toggle_role_user_01')), findsNothing);
        expect(find.byKey(const ValueKey('delete_user_user_01')), findsNothing);
        expect(find.byKey(const ValueKey('toggle_lock_admin_01')), findsNothing);
        expect(
          find.byKey(const ValueKey('toggle_lock_user_01')),
          findsOneWidget,
        );

        // Khóa user_01 bằng hộp thoại nhóm lý do chuẩn hóa (ghi WriteBatch vào users + admin_logs)
        await tester.tap(find.byKey(const ValueKey('toggle_lock_user_01')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('lock_reason_preset_suspicious_access')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('admin_confirm_lock_btn')));
        await tester.pumpAndSettle();

        final updatedUser = await firestoreService.getUserProfile('user_01');
        expect(updatedUser?.isLocked, isTrue);
        expect(updatedUser?.lockReason, contains('Nghi vấn truy cập bất thường'));
        expect(updatedUser?.lockedAt, isNotNull);
        expect(updatedUser?.lockedBy, 'admin@financeai.vn');

        // Điều hướng sang Danh mục (2), Thông báo (3), Nhật ký (4)
        await tester.tap(find.byKey(const ValueKey('admin_nav_tab_2')));
        await tester.pumpAndSettle();
        expect(find.text('Ăn uống'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('admin_nav_tab_3')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('admin_nav_tab_4')));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Nhật ký Quản trị Bất biến'),
          findsOneWidget,
        );
        expect(find.text('Tài khoản User'), findsOneWidget);
        expect(find.text('Danh mục hệ thống'), findsOneWidget);
        expect(find.text('Thông báo hệ thống'), findsOneWidget);
        expect(find.text('Cấu hình AI'), findsNothing);
        // Log lịch sử cũ trong DB vẫn hiển thị an toàn
        expect(find.text('Xuất bản cấu hình AI / Tri thức'), findsOneWidget);

        // Kiểm tra responsive hẹp (< 860px) không crash
        tester.view.physicalSize = const Size(700, 900);
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.menu_rounded), findsOneWidget);
      },
    );
  });
}

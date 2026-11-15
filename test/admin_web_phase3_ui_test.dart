import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_ai_app/admin_web/screens/admin_ai_feedback_view.dart';
import 'package:finance_ai_app/admin_web/screens/admin_ai_studio_view.dart';
import 'package:finance_ai_app/admin_web/screens/admin_ocr_dictionary_view.dart';
import 'package:finance_ai_app/admin_web/screens/admin_rules_knowledge_view.dart';
import 'package:finance_ai_app/admin_web/screens/admin_web_shell_screen.dart';
import 'package:finance_ai_app/admin_web/services/admin_web_service.dart';
import 'package:finance_ai_app/models/ai_runtime_config_model.dart';
import 'package:finance_ai_app/models/monthly_financial_plan.dart';
import 'package:finance_ai_app/models/user_model.dart';
import 'package:finance_ai_app/services/firestore_service.dart';

class _PermissionDeniedFirestoreService extends FirestoreService {
  _PermissionDeniedFirestoreService({required super.firestore});

  @override
  Stream<List<AiFeedbackReport>> streamAiFeedbackReports({int limit = 200}) {
    return Stream<List<AiFeedbackReport>>.error(
      FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'Caller is not authorized to read ai_feedback_reports.',
      ),
    );
  }
}

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
            name: 'Quản trị viên AI',
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

    await fakeFirestore.collection('published_configs').doc('ai_runtime').set({
      'configType': 'ai_runtime',
      'version': 1,
      'payload': AiRuntimeConfig.defaults().toPayloadMap(),
      'payloadHash': AiRuntimeConfig.defaults().canonicalHash,
      'changeNote': 'Initial v1',
      'updatedAt': DateTime(2026, 11, 1).toIso8601String(),
      'updatedBy': 'admin_01',
      'updatedByEmail': 'admin@financeai.vn',
    });
    await fakeFirestore
        .collection('config_versions')
        .doc('ai_runtime_v1')
        .set({
      'versionId': 'ai_runtime_v1',
      'configType': 'ai_runtime',
      'versionNumber': 1,
      'payloadSnapshot': AiRuntimeConfig.defaults().toPayloadMap(),
      'payloadHash': AiRuntimeConfig.defaults().canonicalHash,
      'changeNote': 'Initial v1',
      'publishedBy': 'admin_01',
      'publishedByEmail': 'admin@financeai.vn',
      'publishedAt': DateTime(2026, 11, 1).toIso8601String(),
    });

    await fakeFirestore
        .collection('published_configs')
        .doc('financial_heuristics')
        .set({
      'configType': 'financial_heuristics',
      'version': 1,
      'payload': FinancialHeuristicsConfig.defaults().toPayloadMap(),
      'payloadHash': FinancialHeuristicsConfig.defaults().canonicalHash,
      'updatedAt': DateTime(2026, 11, 1).toIso8601String(),
    });

    await fakeFirestore
        .collection('published_configs')
        .doc('transaction_rules')
        .set({
      'configType': 'transaction_rules',
      'version': 1,
      'payload': TransactionIntelligenceConfig.defaults().toPayloadMap(),
      'payloadHash': TransactionIntelligenceConfig.defaults().canonicalHash,
      'updatedAt': DateTime(2026, 11, 1).toIso8601String(),
    });

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
              'name': 'Quản trị viên AI',
              'role': 'admin',
              'status': 'active',
              'hasAdminClaim': true,
              'hasFirestoreRole': true,
              'claimsSynced': false,
            };
          case 'adminVerifyDraftInSandbox':
            final cfgType = payload['configType'].toString();
            final draftSnap = await fakeFirestore
                .collection('draft_configs')
                .doc(cfgType)
                .get();
            final draftHash =
                (draftSnap.data()?['draftHash'] ?? '').toString();
            await fakeFirestore
                .collection('_sandbox_verifications')
                .doc(cfgType)
                .set({
              'configType': cfgType,
              'verifiedDraftHash': draftHash,
              'verificationSignature': 'hmac_sig_$draftHash',
              'simulationSummary': payload['simulationSummary'] ?? {},
              'verifiedBy': 'admin_01',
              'verifiedByEmail': 'admin@financeai.vn',
              'verifiedAt': DateTime(2026, 11, 15, 9).toIso8601String(),
            });
            return {'success': true, 'verifiedDraftHash': draftHash};
          case 'adminPublishConfig':
            final cfgType = payload['configType'].toString();
            final draftSnap = await fakeFirestore
                .collection('draft_configs')
                .doc(cfgType)
                .get();
            final draftData = draftSnap.data()!;
            final pubRef = fakeFirestore
                .collection('published_configs')
                .doc(cfgType);
            final curPub = await pubRef.get();
            final nextVer = ((curPub.data()?['version'] as num?)?.toInt() ?? 0) + 1;
            final draftPayload =
                Map<String, dynamic>.from(draftData['draftPayload'] as Map);
            final hash = draftData['draftHash'].toString();
            final changeNote = (payload['changeNote'] ?? '').toString();
            await pubRef.set({
              'configType': cfgType,
              'version': nextVer,
              'payload': draftPayload,
              'payloadHash': hash,
              'changeNote': changeNote,
              'updatedAt': DateTime(2026, 11, 15, 9, 5).toIso8601String(),
              'updatedBy': 'admin_01',
              'updatedByEmail': 'admin@financeai.vn',
            });
            await fakeFirestore
                .collection('config_versions')
                .doc('${cfgType}_v$nextVer')
                .set({
              'versionId': '${cfgType}_v$nextVer',
              'configType': cfgType,
              'versionNumber': nextVer,
              'payloadSnapshot': draftPayload,
              'payloadHash': hash,
              'changeNote': changeNote,
              'publishedBy': 'admin_01',
              'publishedByEmail': 'admin@financeai.vn',
              'publishedAt': DateTime(2026, 11, 15, 9, 5).toIso8601String(),
            });
            return {'success': true, 'version': nextVer};
          case 'adminRollbackConfig':
            final cfgType = payload['configType'].toString();
            final targetVer = (payload['targetVersionNumber'] as num).toInt();
            final targetSnap = await fakeFirestore
                .collection('config_versions')
                .doc('${cfgType}_v$targetVer')
                .get();
            final targetPayload = Map<String, dynamic>.from(
              targetSnap.data()!['payloadSnapshot'] as Map,
            );
            final pubRef = fakeFirestore
                .collection('published_configs')
                .doc(cfgType);
            final curPub = await pubRef.get();
            final nextVer = ((curPub.data()?['version'] as num?)?.toInt() ?? 0) + 1;
            final hash = computeCanonicalConfigHash(targetPayload);
            await pubRef.set({
              'configType': cfgType,
              'version': nextVer,
              'payload': targetPayload,
              'payloadHash': hash,
              'rollbackFromVersion': targetVer,
              'changeNote': payload['reason'] ?? '',
              'updatedAt': DateTime(2026, 11, 15, 9, 10).toIso8601String(),
              'updatedBy': 'admin_01',
              'updatedByEmail': 'admin@financeai.vn',
            });
            await fakeFirestore
                .collection('config_versions')
                .doc('${cfgType}_v$nextVer')
                .set({
              'versionId': '${cfgType}_v$nextVer',
              'configType': cfgType,
              'versionNumber': nextVer,
              'payloadSnapshot': targetPayload,
              'payloadHash': hash,
              'rollbackFromVersion': targetVer,
              'changeNote': payload['reason'] ?? '',
              'publishedBy': 'admin_01',
              'publishedByEmail': 'admin@financeai.vn',
              'publishedAt': DateTime(2026, 11, 15, 9, 10).toIso8601String(),
            });
            return {'success': true, 'version': nextVer};
          case 'adminPublishKnowledgeBase':
            final articleId = payload['articleId'].toString();
            final action = payload['action'].toString();
            final draftSnap = await fakeFirestore
                .collection('financial_knowledge_drafts')
                .doc(articleId)
                .get();
            final pubRef = fakeFirestore
                .collection('financial_knowledge_published')
                .doc(articleId);
            final prevPub = await pubRef.get();
            final baseData = action == 'publish' && draftSnap.exists
                ? Map<String, dynamic>.from(draftSnap.data()!)
                : Map<String, dynamic>.from(prevPub.data() ?? draftSnap.data()!);
            final nextVer =
                ((prevPub.data()?['publishedVersion'] as num?)?.toInt() ?? 0) + 1;
            final nextActive = payload['isActive'] is bool
                ? payload['isActive'] as bool
                : (baseData['isActive'] != false);
            await pubRef.set({
              ...baseData,
              'articleId': articleId,
              'isActive': nextActive,
              'publishedVersion': nextVer,
              'publishedAt': DateTime(2026, 11, 15, 9, 15).toIso8601String(),
              'publishedByEmail': 'admin@financeai.vn',
              'changeNote': payload['changeNote'] ?? '',
            });
            return {'success': true, 'publishedVersion': nextVer};
          case 'adminRunSandbox':
            return {
              'success': true,
              'modelUsed': payload['primaryModel'] ?? 'gemini-3.5-flash',
              'triedModels': [
                payload['primaryModel'] ?? 'gemini-3.5-flash',
              ],
              'responseText': 'Đề xuất cắt giảm 15% chi phí Ăn uống linh hoạt.',
              'latencyMs': 420,
              'draftVerificationNote':
                  'Thử nghiệm mô phỏng Live Sandbox hoàn tất (không thay thế bước ký HMAC Draft).',
            };
          case 'adminResolveAiFeedback':
            final reportId = payload['reportId'].toString();
            await fakeFirestore
                .collection('ai_feedback_reports')
                .doc(reportId)
                .set({
              'status': payload['status'],
              'adminResolutionNote': payload['adminResolutionNote'],
              'appliedAction': payload['appliedAction'],
              'resolvedBy': 'admin_01',
              'resolvedAt': DateTime(2026, 11, 15, 9, 20).toIso8601String(),
            }, SetOptions(merge: true));
            return {'success': true, 'status': payload['status']};
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

  Future<void> scrollAndTap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> scrollAndEnterText(
    WidgetTester tester,
    Finder finder,
    String text,
  ) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.enterText(finder, text);
    await tester.pumpAndSettle();
  }

  group('Phase 3 Admin Web UI — Shell & Dashboard', () {
    testWidgets(
      '1. Shell hiển thị đúng 6 khu vực quản trị, giữ Guard và hỗ trợ Responsive hẹp',
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

        expect(find.text('AI & Ops Dashboard'), findsAtLeastNWidgets(1));
        expect(find.text('AI Studio & Sandbox'), findsOneWidget);
        expect(find.text('Financial Rules & Knowledge'), findsOneWidget);
        expect(find.text('OCR Dictionary'), findsOneWidget);
        expect(find.text('AI Feedback'), findsOneWidget);
        expect(find.text('Platform Ops'), findsOneWidget);

        // Kiểm tra KPI trên Dashboard
        expect(find.byKey(const ValueKey('kpi_ai_runtime')), findsOneWidget);
        expect(find.byKey(const ValueKey('kpi_rules_status')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('kpi_knowledge_base')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('kpi_ai_feedback')), findsOneWidget);
        expect(find.byKey(const ValueKey('kpi_total_users')), findsOneWidget);

        // Điều hướng qua tab Platform Ops (index 5) -> kiểm tra 4 subtab
        await tester.tap(find.byKey(const ValueKey('admin_nav_tab_5')));
        await tester.pumpAndSettle();
        expect(find.text('Người dùng'), findsOneWidget);
        expect(find.text('Danh mục Hệ thống'), findsOneWidget);
        expect(find.text('Thông báo Hệ thống'), findsOneWidget);
        expect(find.text('Nhật ký Quản trị'), findsOneWidget);

        // Kiểm tra nút Cấp quyền Admin gọi Cloud Function adminSetUserRole
        await tester.tap(find.byKey(const ValueKey('toggle_role_user_01')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('confirm_role_user_01')));
        await tester.pumpAndSettle();
        expect(
          cloudCalls.any((c) => c['functionName'] == 'adminSetUserRole'),
          isTrue,
        );
        final updatedUser = await firestoreService.getUserProfile('user_01');
        expect(updatedUser?.role, 'admin');

        // Kiểm tra responsive hẹp (< 860px) không crash
        tester.view.physicalSize = const Size(700, 900);
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.menu_rounded), findsOneWidget);
      },
    );
  });

  group('Phase 3 Admin Web UI — Khu vực 2: AI Studio & Sandbox', () {
    testWidgets(
      '2. Lưu Draft -> Deterministic Sandbox -> Live Gemini Sandbox -> HMAC Verify -> Hash invalidated on edit -> Publish -> Rollback',
      (tester) async {
        setDesktopViewport(tester);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AdminAiStudioView(
                adminWebService: adminService,
                currentAdminUid: 'admin_01',
                currentAdminEmail: 'admin@financeai.vn',
                tokenClaimsOverride: const {'admin': true},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Trước khi lưu Draft & xác minh Sandbox, nút Publish bị disable
        final publishBtnFinder =
            find.byKey(const ValueKey('admin_publish_config_btn'));
        expect(
          tester.widget<ElevatedButton>(publishBtnFinder).onPressed,
          isNull,
        );

        // Chỉnh sửa System Instruction -> Lưu Draft
        await scrollAndEnterText(
          tester,
          find.byKey(const ValueKey('ai_studio_chat_instruction_input')),
          'Nguyên tắc CFP mới: luôn ưu tiên quỹ dự phòng trước mua sắm.',
        );
        await scrollAndTap(
          tester,
          find.byKey(const ValueKey('admin_save_draft_btn')),
        );

        final draftDoc = await fakeFirestore
            .collection('draft_configs')
            .doc('ai_runtime')
            .get();
        expect(draftDoc.exists, isTrue);
        expect(
          draftDoc.data()!.containsKey('verifiedSandboxHash'),
          isFalse,
        ); // Tuân thủ firestore.rules hasOnly

        // Chạy Deterministic Sandbox
        await scrollAndTap(
          tester,
          find.byKey(const ValueKey('ai_studio_run_deterministic_btn')),
        );
        expect(
          find.byKey(const ValueKey('ai_studio_system_prompt_preview')),
          findsOneWidget,
        );
        expect(
          find.textContaining('Nguyên tắc CFP mới'),
          findsWidgets,
        );

        // Chuyển sang tab Live Gemini Sandbox -> chạy thử nghiệm Cloud Function
        await scrollAndTap(tester, find.text('Live Gemini Sandbox'));
        await scrollAndTap(
          tester,
          find.byKey(const ValueKey('ai_studio_run_live_gemini_btn')),
        );
        expect(
          find.byKey(const ValueKey('ai_studio_live_response_text')),
          findsOneWidget,
        );
        expect(
          cloudCalls.any((c) => c['functionName'] == 'adminRunSandbox'),
          isTrue,
        );

        // Ký xác minh HMAC Sandbox
        await scrollAndTap(
          tester,
          find.byKey(const ValueKey('admin_verify_sandbox_btn')),
        );
        expect(find.textContaining('Sandbox Verified'), findsOneWidget);
        expect(
          tester.widget<ElevatedButton>(publishBtnFinder).onPressed,
          isNotNull,
        );

        // Sửa 1 ký tự sau khi verify -> Publish bị khóa ngay vì hash thay đổi
        await scrollAndEnterText(
          tester,
          find.byKey(const ValueKey('ai_studio_chat_instruction_input')),
          'Nguyên tắc CFP mới: luôn ưu tiên quỹ dự phòng trước mua sắm!',
        );
        expect(
          tester.widget<ElevatedButton>(publishBtnFinder).onPressed,
          isNull,
        );

        // Lưu Draft mới -> Re-verify -> Publish -> Rollback về v1
        await scrollAndTap(
          tester,
          find.byKey(const ValueKey('admin_save_draft_btn')),
        );
        await scrollAndTap(
          tester,
          find.byKey(const ValueKey('admin_verify_sandbox_btn')),
        );
        await scrollAndTap(tester, publishBtnFinder);

        await tester.enterText(
          find.byKey(const ValueKey('ai_studio_publish_note_input')),
          'Cập nhật prompt CFP v2',
        );
        await tester.tap(
          find.byKey(const ValueKey('ai_studio_confirm_publish_btn')),
        );
        await tester.pumpAndSettle();

        final pubV2 = await fakeFirestore
            .collection('published_configs')
            .doc('ai_runtime')
            .get();
        expect(pubV2.data()?['version'], 2);

        // Cuộn xuống lịch sử phiên bản và Rollback về v1
        final rollbackBtn = find.byKey(const ValueKey('admin_rollback_v_1'));
        await tester.ensureVisible(rollbackBtn);
        await tester.tap(rollbackBtn);
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('ai_studio_rollback_reason_input')),
          'Khôi phục prompt ổn định v1',
        );
        await tester.tap(
          find.byKey(const ValueKey('ai_studio_confirm_rollback_btn')),
        );
        await tester.pumpAndSettle();

        final pubV3 = await fakeFirestore
            .collection('published_configs')
            .doc('ai_runtime')
            .get();
        expect(pubV3.data()?['version'], 3);
        expect(pubV3.data()?['rollbackFromVersion'], 1);
      },
    );
  });

  group('Phase 3 Admin Web UI — Khu vực 3: Financial Rules & Knowledge', () {
    testWidgets(
      '3. Validation 18 tham số Heuristics + So sánh Persona + CRUD/Publish/Tạm ngưng Knowledge Base',
      (tester) async {
        setDesktopViewport(tester);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AdminRulesKnowledgeView(
                adminWebService: adminService,
                currentAdminUid: 'admin_01',
                currentAdminEmail: 'admin@financeai.vn',
                tokenClaimsOverride: const {'admin': true},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Nhập giá trị vi phạm ràng buộc chéo: defaultSavingRateNoGoal (0.35) > minRecommendedSavingRate (0.20)
        await scrollAndEnterText(
          tester,
          find.byKey(const ValueKey('heur_input_defaultSavingRateNoGoal')),
          '0.35',
        );

        final saveBtn = find.byKey(const ValueKey('admin_save_draft_btn'));
        await tester.ensureVisible(saveBtn);
        await tester.pumpAndSettle();
        expect(tester.widget<OutlinedButton>(saveBtn).onPressed, isNull);
        expect(
          find.textContaining('Lỗi hợp lệ cấu hình'),
          findsOneWidget,
        );

        // Sửa lại hợp lệ -> Chạy đối chiếu Synthetic Persona -> Lưu Draft
        await scrollAndEnterText(
          tester,
          find.byKey(const ValueKey('heur_input_defaultSavingRateNoGoal')),
          '0.18',
        );
        await tester.ensureVisible(saveBtn);
        await tester.pumpAndSettle();
        expect(tester.widget<OutlinedButton>(saveBtn).onPressed, isNotNull);

        await scrollAndTap(
          tester,
          find.byKey(const ValueKey('heuristics_run_comparison_btn')),
        );
        expect(find.text('Bản Published hiện tại'), findsOneWidget);
        expect(find.text('Bản Draft đang chỉnh sửa'), findsOneWidget);

        await scrollAndTap(tester, saveBtn);
        expect(
          (await fakeFirestore
                  .collection('draft_configs')
                  .doc('financial_heuristics')
                  .get())
              .exists,
          isTrue,
        );

        // Chuyển sang Sub-tab Kho Tri thức Tài chính
        await scrollAndTap(tester, find.text('Kho Tri thức Tài chính'));

        await scrollAndTap(
          tester,
          find.byKey(const ValueKey('kb_add_article_btn')),
        );

        await tester.enterText(
          find.byKey(const ValueKey('kb_dialog_id_input')),
          'kb_emergency_6m',
        );
        await tester.enterText(
          find.byKey(const ValueKey('kb_dialog_title_input')),
          'Quỹ dự phòng 6 tháng chi tiêu thiết yếu',
        );
        await tester.enterText(
          find.byKey(const ValueKey('kb_dialog_summary_input')),
          'Tích lũy quỹ dự phòng tối thiểu 6 tháng chi phí thiết yếu trước khi đầu tư.',
        );
        await tester.enterText(
          find.byKey(const ValueKey('kb_dialog_snippet_input')),
          'Ưu tiên xây quỹ dự phòng bằng 6 lần chi phí thiết yếu hàng tháng trước khi phân bổ vào các mục tiêu dài hạn.',
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('kb_dialog_save_draft_btn')));
        await tester.pumpAndSettle();

        expect(
          find.text('Quỹ dự phòng 6 tháng chi tiêu thiết yếu'),
          findsOneWidget,
        );

        // Publish bài viết -> Tạm ngưng giữ lịch sử (isActive = false)
        await scrollAndTap(
          tester,
          find.byKey(const ValueKey('kb_publish_kb_emergency_6m')),
        );
        await tester.tap(
          find.byKey(const ValueKey('kb_confirm_publish_kb_emergency_6m')),
        );
        await tester.pumpAndSettle();

        final pubKb1 = await fakeFirestore
            .collection('financial_knowledge_published')
            .doc('kb_emergency_6m')
            .get();
        expect(pubKb1.data()?['isActive'], isTrue);
        expect(pubKb1.data()?['publishedVersion'], 1);

        await scrollAndTap(
          tester,
          find.byKey(const ValueKey('kb_toggle_active_kb_emergency_6m')),
        );
        await tester.tap(
          find.byKey(const ValueKey('kb_confirm_toggle_kb_emergency_6m')),
        );
        await tester.pumpAndSettle();

        final pubKb2 = await fakeFirestore
            .collection('financial_knowledge_published')
            .doc('kb_emergency_6m')
            .get();
        expect(pubKb2.exists, isTrue);
        expect(pubKb2.data()?['isActive'], isFalse);
        expect(pubKb2.data()?['publishedVersion'], 2);
      },
    );
  });

  group('Phase 3 Admin Web UI — Khu vực 4 & 5: OCR Dictionary & AI Feedback', () {
    testWidgets(
      '4. OCR Dictionary chặn Built-in, hỗ trợ disabledAdminKeywords, Custom Provider, Local Match Test',
      (tester) async {
        setDesktopViewport(tester);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AdminOcrDictionaryView(
                adminWebService: adminService,
                currentAdminUid: 'admin_01',
                currentAdminEmail: 'admin@financeai.vn',
                tokenClaimsOverride: const {'admin': true},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Thử thêm từ khóa lõi được bảo vệ ('Highlands') vào nhóm khác -> Bị chặn
        await scrollAndEnterText(
          tester,
          find.byKey(const ValueKey('ocr_keyword_input')),
          'Highlands',
        );
        expect(
          find.byKey(const ValueKey('ocr_keyword_conflict_banner')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<ElevatedButton>(
                find.byKey(const ValueKey('ocr_add_keyword_btn')),
              )
              .onPressed,
          isNull,
        );

        // Thêm từ khóa mới hợp lệ ('Phúc Long') -> Chuẩn hóa & thêm thành công
        await scrollAndEnterText(
          tester,
          find.byKey(const ValueKey('ocr_keyword_input')),
          'Phúc Long',
        );
        await scrollAndTap(
          tester,
          find.byKey(const ValueKey('ocr_add_keyword_btn')),
        );
        expect(find.text('phuc long'), findsOneWidget);

        // Bật/tắt từ khóa Admin via disabledAdminKeywords
        await scrollAndTap(
          tester,
          find.byKey(const ValueKey('ocr_toggle_kw_phuc long')),
        );
        await scrollAndTap(
          tester,
          find.byKey(const ValueKey('ocr_toggle_kw_phuc long')),
        );

        // Thêm Custom Payment Provider & bật/tắt isActive
        await scrollAndTap(
          tester,
          find.byKey(const ValueKey('ocr_add_provider_btn')),
        );
        await tester.enterText(
          find.byKey(const ValueKey('ocr_provider_key_input')),
          'kredivo',
        );
        await tester.enterText(
          find.byKey(const ValueKey('ocr_provider_label_input')),
          'Kredivo PayLater',
        );
        await tester.enterText(
          find.byKey(const ValueKey('ocr_provider_keywords_input')),
          'kredivo',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('ocr_provider_save_btn')));
        await tester.pumpAndSettle();

        expect(find.text('Kredivo PayLater'), findsOneWidget);
        await scrollAndTap(
          tester,
          find.byKey(const ValueKey('ocr_provider_active_switch_kredivo')),
        );
        await scrollAndTap(
          tester,
          find.byKey(const ValueKey('ocr_provider_active_switch_kredivo')),
        );

        // Chạy kiểm thử cục bộ bằng TransactionIntelligenceService
        await scrollAndEnterText(
          tester,
          find.byKey(const ValueKey('ocr_local_test_input')),
          'Tra sua Phuc Long thanh toan qua Kredivo',
        );
        await scrollAndTap(
          tester,
          find.byKey(const ValueKey('ocr_run_local_test_btn')),
        );
        expect(find.textContaining('Ăn uống & Cà phê'), findsWidgets);

        // Lưu Draft -> Verify HMAC -> Publish
        await scrollAndTap(
          tester,
          find.byKey(const ValueKey('admin_save_draft_btn')),
        );
        await scrollAndTap(
          tester,
          find.byKey(const ValueKey('admin_verify_sandbox_btn')),
        );
        await scrollAndTap(
          tester,
          find.byKey(const ValueKey('admin_publish_config_btn')),
        );
        await tester.tap(find.byKey(const ValueKey('ocr_confirm_publish_btn')));
        await tester.pumpAndSettle();

        final pubRules = await fakeFirestore
            .collection('published_configs')
            .doc('transaction_rules')
            .get();
        expect(pubRules.data()?['version'], 2);
      },
    );

    testWidgets(
      '5. AI Feedback xử lý qua Cloud Function adminResolveAiFeedback & shortcut sang OCR Dictionary',
      (tester) async {
        setDesktopViewport(tester);

        await fakeFirestore
            .collection('ai_feedback_reports')
            .doc('fb_ocr_1')
            .set(
              AiFeedbackReport.createForSubmission(
                reportId: 'fb_ocr_1',
                targetFeature: 'ocr_suggestion',
                rating: 'negative',
                reasonCode: 'wrong_category',
                feedbackMode: 'pseudonymous',
                callerUid: 'user_01',
                userNote: 'Hóa đơn trà sữa chưa nhận diện được',
                suggestedKeywordOrMerchant: 'Katinat Saigon',
                createdAt: DateTime(2026, 11, 15, 8),
              ).toCreateMap(),
            );

        String? navigatedKeyword;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AdminAiFeedbackView(
                adminWebService: adminService,
                currentAdminUid: 'admin_01',
                currentAdminEmail: 'admin@financeai.vn',
                tokenClaimsOverride: const {'admin': true},
                onOpenOcrDictionary: (kw) => navigatedKeyword = kw,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Katinat Saigon'),
          findsAtLeastNWidgets(1),
        );
        expect(find.text('Giả danh (pseudonymous)'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('feedback_goto_ocr_fb_ocr_1')));
        await tester.pump();
        expect(navigatedKeyword, 'Katinat Saigon');

        await tester.tap(
          find.byKey(const ValueKey('feedback_resolve_btn_fb_ocr_1')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('feedback_resolve_note_input')),
          'Đã thêm từ khóa Katinat vào từ điển',
        );
        await tester.tap(
          find.byKey(const ValueKey('feedback_confirm_resolve_btn')),
        );
        await tester.pumpAndSettle();

        expect(
          cloudCalls.any((c) => c['functionName'] == 'adminResolveAiFeedback'),
          isTrue,
        );
        final fbDoc = await fakeFirestore
            .collection('ai_feedback_reports')
            .doc('fb_ocr_1')
            .get();
        expect(fbDoc.data()?['status'], 'resolved');
      },
    );

    testWidgets(
      '6. AI Feedback hiển thị rõ trạng thái Permission Denied khi Firestore từ chối quyền',
      (tester) async {
        setDesktopViewport(tester);
        final deniedService = AdminWebService(
          firestoreService:
              _PermissionDeniedFirestoreService(firestore: fakeFirestore),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AdminAiFeedbackView(
                adminWebService: deniedService,
                currentAdminUid: 'admin_01',
                currentAdminEmail: 'admin@financeai.vn',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('admin_permission_denied_card')),
          findsOneWidget,
        );
        expect(
          find.text('Không đủ quyền truy cập dữ liệu'),
          findsOneWidget,
        );
      },
    );
  });
}

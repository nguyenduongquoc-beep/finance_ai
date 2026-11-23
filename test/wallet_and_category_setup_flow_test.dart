import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_ai_app/models/category_model.dart';
import 'package:finance_ai_app/models/monthly_financial_plan.dart';
import 'package:finance_ai_app/models/wallet_model.dart';
import 'package:finance_ai_app/screens/setup/wallet_setup_screen.dart';
import 'package:finance_ai_app/services/firestore_service.dart';

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late FirestoreService firestoreService;

  setUp(() async {
    fakeFirestore = FakeFirebaseFirestore();
    firestoreService = FirestoreService(firestore: fakeFirestore);

    // Seed 1 danh mục chi tiêu & 1 danh mục thu nhập hệ thống cho Bước 2
    await firestoreService.saveSystemCategoryTemplate(
      const SystemCategoryTemplate(
        id: 'sys_exp_1',
        name: 'Ăn uống',
        type: 'expense',
        icon: 'restaurant',
        color: 0xFFE53935,
        isEssential: false,
        isActive: true,
      ),
    );
    await firestoreService.saveSystemCategoryTemplate(
      const SystemCategoryTemplate(
        id: 'sys_inc_1',
        name: 'Lương',
        type: 'income',
        icon: 'work',
        color: 0xFF10B981,
        isActive: true,
      ),
    );
  });

  group('Luồng Thiết lập tài khoản mới (WalletSetup -> CategorySetup)', () {
    test(
        '1. completeInitialSetup ghi nguyên tử và chống trùng lặp (idempotent) khi gọi lặp lại',
        () async {
      const uid = 'user_setup_idempotent';
      final wallets = [
        Wallet(
          walletId: '',
          userId: uid,
          walletName: 'Tiền mặt',
          balance: 500000,
          type: 'cash',
          createdAt: DateTime(2026, 11, 22),
        ),
        Wallet(
          walletId: '',
          userId: uid,
          walletName: 'Cash', // Trùng ví Tiền mặt hệ thống (EN/VI)
          balance: 500000,
          type: 'cash',
          createdAt: DateTime(2026, 11, 22),
        ),
        Wallet(
          walletId: '',
          userId: uid,
          walletName: 'MB Bank',
          balance: 1000000,
          type: 'bank',
          createdAt: DateTime(2026, 11, 22),
        ),
        Wallet(
          walletId: '',
          userId: uid,
          walletName: 'mb bank', // Trùng tên khác hoa thường
          balance: 1000000,
          type: 'bank',
          createdAt: DateTime(2026, 11, 22),
        ),
      ];
      final categories = [
        Category(
          categoryId: '',
          userId: uid,
          name: 'Ăn uống',
          type: 'expense',
          icon: 'restaurant',
          color: 0xFFE53935,
        ),
        Category(
          categoryId: '',
          userId: uid,
          name: 'Lương',
          type: 'income',
          icon: 'work',
          color: 0xFF10B981,
        ),
      ];

      // Gọi lần 1
      await firestoreService.completeInitialSetup(
        userId: uid,
        wallets: wallets,
        categories: categories,
      );
      // Gọi lặp lại lần 2 (mô phỏng retry)
      await firestoreService.completeInitialSetup(
        userId: uid,
        wallets: wallets,
        categories: categories,
      );

      final savedWallets = await fakeFirestore
          .collection('wallets')
          .where('userId', isEqualTo: uid)
          .get();
      final savedCategories = await fakeFirestore
          .collection('categories')
          .where('userId', isEqualTo: uid)
          .get();

      expect(savedWallets.docs.length, 2);
      expect(savedCategories.docs.length, 2);
    });

    testWidgets(
        '2. Quay lại từ Bước 2 về Bước 1 nhiều lần (3 lần) KHÔNG tạo trùng ví; chỉ ghi khi bấm Hoàn tất',
        (tester) async {
      const uid = 'user_back_3_times';
      bool setupCompleted = false;

      await tester.pumpWidget(
        MaterialApp(
          home: WalletSetupScreen(
            firestoreService: firestoreService,
            userIdOverride: uid,
            onSetupCompleted: () {
              setupCompleted = true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Lặp 3 lần: bấm Tiếp tục (Bước 1 -> Bước 2) rồi bấm Back quay lại Bước 1
      for (int attempt = 1; attempt <= 3; attempt++) {
        await tester.tap(find.text('Tiếp tục chọn danh mục (1/2)'));
        await tester.pumpAndSettle();

        // Đã sang Bước 2 (CategorySetupScreen)
        expect(find.text('Hoàn tất & Khám phá ngay (2/2)'), findsOneWidget);

        // Firestore vẫn CHƯA có ví hay danh mục nào trước khi bấm Hoàn tất
        final walletsMidway = await fakeFirestore
            .collection('wallets')
            .where('userId', isEqualTo: uid)
            .get();
        expect(
          walletsMidway.docs.length,
          0,
          reason: 'Lần thứ $attempt: chưa bấm Hoàn tất thì chưa được ghi ví vào Firestore',
        );

        // Quay lại Bước 1 bằng nút Back trên AppBar
        await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
        await tester.pumpAndSettle();

        expect(find.text('Tiếp tục chọn danh mục (1/2)'), findsOneWidget);
      }

      // Lần cuối (lần 4): đi sang Bước 2 và bấm Hoàn tất
      await tester.tap(find.text('Tiếp tục chọn danh mục (1/2)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hoàn tất & Khám phá ngay (2/2)'));
      await tester.pumpAndSettle();

      expect(setupCompleted, isTrue);

      final finalWalletsSnap = await fakeFirestore
          .collection('wallets')
          .where('userId', isEqualTo: uid)
          .get();
      final finalCategoriesSnap = await fakeFirestore
          .collection('categories')
          .where('userId', isEqualTo: uid)
          .get();

      final walletNames = finalWalletsSnap.docs
          .map((d) => d.data()['walletName'] as String)
          .toList();

      // Chỉ có đúng 2 ví mặc định: Tiền mặt và MB Bank (không lặp 3 lần)
      expect(finalWalletsSnap.docs.length, 2);
      expect(walletNames, containsAll(['Tiền mặt', 'MB Bank']));
      expect(finalCategoriesSnap.docs.length, 2);
    });

    testWidgets(
        '3. Quay lại Bước 1 để đổi số dư ví, hệ thống lưu đúng số dư mới nhất sau khi Hoàn tất',
        (tester) async {
      const uid = 'user_edit_balance_on_back';
      bool setupCompleted = false;

      await tester.pumpWidget(
        MaterialApp(
          home: WalletSetupScreen(
            firestoreService: firestoreService,
            userIdOverride: uid,
            onSetupCompleted: () {
              setupCompleted = true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Bước 1 -> Bước 2 với số dư mặc định 0
      await tester.tap(find.text('Tiếp tục chọn danh mục (1/2)'));
      await tester.pumpAndSettle();

      // Back về Bước 1 và chọn preset 500K cho ví đầu tiên (Tiền mặt)
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
      await tester.pumpAndSettle();

      await tester.tap(find.text('500K').first);
      await tester.pumpAndSettle();

      // Đi lại sang Bước 2 và Hoàn tất
      await tester.tap(find.text('Tiếp tục chọn danh mục (1/2)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hoàn tất & Khám phá ngay (2/2)'));
      await tester.pumpAndSettle();

      expect(setupCompleted, isTrue);

      final walletsSnap = await fakeFirestore
          .collection('wallets')
          .where('userId', isEqualTo: uid)
          .get();
      expect(walletsSnap.docs.length, 2);

      final cashDoc = walletsSnap.docs
          .firstWhere((d) => d.data()['walletName'] == 'Tiền mặt');
      expect((cashDoc.data()['balance'] as num).toDouble(), 500000.0);
      expect((cashDoc.data()['initialBalance'] as num).toDouble(), 500000.0);
    });
  });
}

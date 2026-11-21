import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_ai_app/models/quick_template.dart';
import 'package:finance_ai_app/screens/home/add_transaction_screen.dart';
import 'package:finance_ai_app/widgets/custom_numpad.dart';
import 'package:finance_ai_app/widgets/quick_template_chip.dart';

QuickTemplate _makeTemplate(
  String id,
  String title,
  double amount, {
  String type = 'expense',
}) {
  return QuickTemplate(
    id: id,
    title: title,
    amount: amount,
    type: type,
    walletId: 'w1',
    categoryId: 'c1',
    note: title,
    location: '',
    date: DateTime(2026, 10, 24),
  );
}

void main() {
  group('CustomNumpad Fintech UI/UX Tests', () {
    testWidgets('1. Hiển thị giá trị ban đầu và định dạng chuẩn tiền tệ VNĐ',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CustomNumpad(initialValue: '150000'),
          ),
        ),
      );

      expect(find.text('150.000 ₫'), findsOneWidget);
      expect(find.text('Xác nhận: 150.000 ₫'), findsOneWidget);
    });

    testWidgets('2. Nhập số với phím 000 tăng tốc độ nhập tiền',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CustomNumpad(initialValue: ''),
          ),
        ),
      );

      expect(find.text('0 ₫'), findsOneWidget);

      await tester.tap(find.text('5'));
      await tester.pump();
      expect(find.text('5 ₫'), findsOneWidget);

      await tester.tap(find.text('000'));
      await tester.pump();
      expect(find.text('5.000 ₫'), findsOneWidget);

      await tester.tap(find.text('000'));
      await tester.pump();
      expect(find.text('5.000.000 ₫'), findsOneWidget);
    });

    testWidgets('3. Phím C (Clear) xóa toàn bộ số tiền về 0', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CustomNumpad(initialValue: '2500000'),
          ),
        ),
      );

      expect(find.text('2.500.000 ₫'), findsOneWidget);

      await tester.tap(find.text('C'));
      await tester.pump();

      expect(find.text('0 ₫'), findsOneWidget);
    });

    testWidgets('4. Phím xóa lùi Backspace (DEL) xóa từng chữ số',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CustomNumpad(initialValue: '123'),
          ),
        ),
      );

      expect(find.text('123 ₫'), findsOneWidget);

      final delBtn = find.byIcon(Icons.backspace_outlined);
      await tester.ensureVisible(delBtn);
      await tester.tap(delBtn);
      await tester.pump();
      expect(find.text('12 ₫'), findsOneWidget);

      await tester.tap(delBtn);
      await tester.pump();
      expect(find.text('1 ₫'), findsOneWidget);
    });

    testWidgets(
        '5. Chip nạp tiền nhanh (+50.000, +100.000) trong CustomNumpad cộng dồn chính xác',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CustomNumpad(
              initialValue: '50000',
              title: 'Nhập số tiền chi tiêu',
            ),
          ),
        ),
      );

      expect(find.text('Nhập số tiền chi tiêu'), findsOneWidget);
      expect(find.text('50.000 ₫'), findsOneWidget);

      await tester.tap(find.text('+100.000'));
      await tester.pump();

      expect(find.text('150.000 ₫'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '6. Hiển thị đọc số tiền lớn (hàng triệu, hàng tỷ) và không tràn trên màn hình thấp',
        (tester) async {
      tester.view.physicalSize = const Size(360, 560);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CustomNumpad(
              initialValue: '1500000000000',
              title: 'Nhập số tiền chi tiêu',
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(FittedBox), findsWidgets);
    });

    testWidgets('7. Xác nhận trả về chuỗi tiền đã format', (tester) async {
      String? returnedResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  returnedResult = await showModalBottomSheet<String>(
                    context: ctx,
                    isScrollControlled: true,
                    builder: (_) => const CustomNumpad(initialValue: '750000'),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final confirmBtn = find.text('Xác nhận: 750.000 ₫');
      await tester.ensureVisible(confirmBtn);
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      expect(returnedResult, equals('750.000'));
    });
  });

  group('QuickTemplatePaginatedBar & Long-Press Delete Tests', () {
    testWidgets(
        '1. Chạm 1 lần áp dụng đúng mẫu; nhấn giữ mở hộp thoại xóa mà không kích hoạt chọn mẫu',
        (tester) async {
      QuickTemplate? selectedTemplate;
      QuickTemplate? deletedTemplate;
      final templates = [
        _makeTemplate('t1', 'cafe', 25000),
        _makeTemplate('t2', 'ăn sáng', 35000),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: QuickTemplatePaginatedBar(
                templates: templates,
                onSelect: (t) => selectedTemplate = t,
                onDelete: (t) async {
                  deletedTemplate = t;
                },
              ),
            ),
          ),
        ),
      );

      // Chạm 1 lần vào tag "cafe"
      await tester.tap(find.text('cafe'));
      await tester.pumpAndSettle();
      expect(selectedTemplate?.id, equals('t1'));
      expect(deletedTemplate, isNull);

      // Reset selectedTemplate rồi nhấn giữ vào tag "cafe"
      selectedTemplate = null;
      await tester.longPress(find.text('cafe'));
      await tester.pumpAndSettle();

      // Không được kích hoạt onSelect khi nhấn giữ
      expect(selectedTemplate, isNull);

      // Hiển thị hộp thoại xác nhận xóa rõ ràng
      expect(find.text('Xóa mẫu nhanh?'), findsOneWidget);
      expect(
        find.text('Bạn có chắc chắn muốn xóa mẫu "cafe" không?'),
        findsOneWidget,
      );
      expect(find.text('Hủy'), findsOneWidget);
      expect(find.text('Xóa'), findsOneWidget);

      // Bấm "Hủy" -> giữ nguyên mẫu "cafe"
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(deletedTemplate, isNull);
      expect(find.text('cafe'), findsOneWidget);

      // Nhấn giữ lại và bấm "Xóa" -> xóa đúng mẫu "cafe"
      await tester.longPress(find.text('cafe'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xóa'));
      await tester.pumpAndSettle();

      expect(deletedTemplate?.id, equals('t1'));
      expect(find.text('cafe'), findsNothing);
      expect(find.text('ăn sáng'), findsOneWidget);
    });

    testWidgets(
        '2. Phân trang nhiều tag: điều hướng nhóm đầu, nhóm giữa, nhóm cuối và tự lùi trang khi xóa hết mẫu ở trang cuối',
        (tester) async {
      tester.view.physicalSize = const Size(380, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final templates = [
        _makeTemplate('t1', 'cafe', 25000),
        _makeTemplate('t2', 'ăn sáng', 35000),
        _makeTemplate('t3', 'đổ xăng', 50000),
        _makeTemplate('t4', 'mua nước', 15000),
        _makeTemplate('t5', 'tiền trọ', 3500000),
        _makeTemplate('t6', 'internet', 220000),
        _makeTemplate('t7', 'mua sắm', 500000),
        _makeTemplate('t8', 'điện nước', 450000),
        _makeTemplate('t9', 'gửi xe tháng', 150000),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: QuickTemplatePaginatedBar(
                templates: templates,
                onSelect: (_) {},
                onDelete: (_) async {},
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);

      // Ở nhóm đầu (Nhóm 1): không có nút quay lại [←], chỉ có nút tiếp theo [→]
      expect(find.byKey(const ValueKey('template_nav_prev')), findsNothing);
      expect(find.byKey(const ValueKey('template_nav_next')), findsOneWidget);
      expect(find.text('cafe'), findsOneWidget);

      // Bấm nút [→] sang Nhóm 2 (nhóm giữa): có cả [←] và [→]
      await tester.tap(find.byKey(const ValueKey('template_nav_next')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('template_nav_prev')), findsOneWidget);
      expect(find.byKey(const ValueKey('template_nav_next')), findsOneWidget);

      // Bấm nút [→] sang Nhóm cuối: có nút [←], không còn nút [→]
      await tester.tap(find.byKey(const ValueKey('template_nav_next')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('template_nav_prev')), findsOneWidget);
      expect(find.byKey(const ValueKey('template_nav_next')), findsNothing);
      expect(find.text('gửi xe tháng'), findsOneWidget);

      // Xóa mẫu ở nhóm cuối -> nếu nhóm cuối trống, tự lùi về nhóm trước đó hợp lệ
      await tester.longPress(find.text('gửi xe tháng'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xóa'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '3. Các mẫu có tên rất dài và màn hình hẹp (320px) không bị RenderFlex overflow',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final longTemplates = [
        _makeTemplate(
            'long1', 'Ăn trưa văn phòng cùng đồng nghiệp công ty', 125000),
        _makeTemplate(
            'long2', 'Thanh toán hóa đơn dịch vụ internet cáp quang', 350000),
        _makeTemplate('long3', 'Đổ xăng xe máy đi làm hàng tuần', 80000),
        _makeTemplate('long4', 'Mua sắm nhu yếu phẩm siêu thị cuối tuần', 950000),
        _makeTemplate('long5', 'cafe', 25000),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: QuickTemplatePaginatedBar(
                templates: longTemplates,
                onSelect: (_) {},
                onDelete: (_) async {},
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);

      // Duyệt qua tất cả các nhóm trên màn hình 320px để đảm bảo không nhóm nào bị tràn
      while (find.byKey(const ValueKey('template_nav_next')).evaluate().isNotEmpty) {
        await tester.tap(find.byKey(const ValueKey('template_nav_next')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets(
        '4. Màn hình Thêm giao dịch: đã xóa hàng tag tiền (+50k, +100k...) ở SỐ TIỀN GIAO DỊCH và nút xóa chỉ hiển thị "Xóa" (không còn "(C)")',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AddTransactionScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Xác nhận hàng tag tiền (+50k, +100k, +200k, +500k, +1Tr) ở SỐ TIỀN GIAO DỊCH đã bị xóa
      expect(find.text('+50k'), findsNothing);
      expect(find.text('+100k'), findsNothing);
      expect(find.text('+200k'), findsNothing);
      expect(find.text('+500k'), findsNothing);
      expect(find.text('+1Tr'), findsNothing);

      // Ban đầu số tiền = 0 nên nút Xóa chưa hiện
      expect(find.text('Xóa (C)'), findsNothing);
      expect(find.text('Xóa'), findsNothing);

      // Chạm vào số tiền '0' ở SỐ TIỀN GIAO DỊCH để mở hộp thoại nhập số tiền (CustomNumpad)
      await tester.tap(find.text('0'));
      await tester.pumpAndSettle();

      // Trong hộp thoại nhập số tiền vẫn có các chip gợi ý (+50.000, +100.000...)
      expect(find.text('+50.000'), findsOneWidget);
      await tester.tap(find.text('+50.000'));
      await tester.pump();
      await tester.tap(find.text('Xác nhận: 50.000 ₫'));
      await tester.pumpAndSettle();

      expect(find.text('50.000'), findsOneWidget);
      // Nút xóa xuất hiện với nội dung "Xóa" và hoàn toàn không còn "Xóa (C)"
      expect(find.text('Xóa'), findsOneWidget);
      expect(find.text('Xóa (C)'), findsNothing);

      // Bấm nút "Xóa" -> số tiền quay về 0 và nút xóa ẩn đi
      await tester.tap(find.text('Xóa'));
      await tester.pumpAndSettle();

      expect(find.text('0'), findsOneWidget);
      expect(find.text('Xóa'), findsNothing);
    });

    testWidgets(
        '5. Kéo trườn ngang (swipe qua và trườn về) hoạt động mượt mà cả 2 chiều kết hợp nút < >',
        (tester) async {
      tester.view.physicalSize = const Size(380, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final templates = [
        _makeTemplate('t1', 'cafe', 25000),
        _makeTemplate('t2', 'ăn sáng', 35000),
        _makeTemplate('t3', 'đổ xăng', 50000),
        _makeTemplate('t4', 'mua nước', 15000),
        _makeTemplate('t5', 'tiền trọ', 3500000),
        _makeTemplate('t6', 'internet', 220000),
        _makeTemplate('t7', 'mua sắm', 500000),
        _makeTemplate('t8', 'điện nước', 450000),
        _makeTemplate('t9', 'gửi xe tháng', 150000),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: QuickTemplatePaginatedBar(
                templates: templates,
                onSelect: (_) {},
                onDelete: (_) async {},
              ),
            ),
          ),
        ),
      );

      final pageViewFinder = find.byType(PageView);
      expect(pageViewFinder, findsOneWidget);
      expect(find.text('cafe'), findsOneWidget);
      expect(find.byKey(const ValueKey('template_nav_prev')), findsNothing);

      // Kéo trườn sang trái (từ trang 1 -> trang 2)
      await tester.timedDrag(
        pageViewFinder,
        const Offset(-220, 0),
        const Duration(milliseconds: 300),
      );
      await tester.pumpAndSettle();

      expect(find.text('cafe'), findsNothing);
      expect(find.byKey(const ValueKey('template_nav_prev')), findsOneWidget);
      expect(find.byKey(const ValueKey('template_nav_next')), findsOneWidget);

      // Kéo trườn tiếp sang trái (từ trang 2 -> trang 3)
      await tester.timedDrag(
        pageViewFinder,
        const Offset(-220, 0),
        const Duration(milliseconds: 300),
      );
      await tester.pumpAndSettle();

      expect(find.text('gửi xe tháng'), findsOneWidget);
      expect(find.byKey(const ValueKey('template_nav_prev')), findsOneWidget);
      expect(find.byKey(const ValueKey('template_nav_next')), findsNothing);

      // Kéo trườn ngược về bên phải (từ trang 3 -> trang 2)
      await tester.timedDrag(
        pageViewFinder,
        const Offset(220, 0),
        const Duration(milliseconds: 300),
      );
      await tester.pumpAndSettle();

      expect(find.text('gửi xe tháng'), findsNothing);
      expect(find.byKey(const ValueKey('template_nav_prev')), findsOneWidget);
      expect(find.byKey(const ValueKey('template_nav_next')), findsOneWidget);

      // Kéo trườn ngược về bên phải lần nữa (từ trang 2 -> trang 1)
      await tester.timedDrag(
        pageViewFinder,
        const Offset(220, 0),
        const Duration(milliseconds: 300),
      );
      await tester.pumpAndSettle();

      expect(find.text('cafe'), findsOneWidget);
      expect(find.byKey(const ValueKey('template_nav_prev')), findsNothing);
      expect(find.byKey(const ValueKey('template_nav_next')), findsOneWidget);

      // Kiểm tra trường hợp chỉ có 2 trang (trang 2 chỉ có 1 tag nhỏ bên trái, phần bên phải trống):
      // Người dùng đặt tay ở vùng trống bên phải/giữa thanh rồi kéo trườn chậm (không vẩy nhanh) về trang 1
      final fiveTemplates = templates.sublist(0, 5);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: QuickTemplatePaginatedBar(
                templates: fiveTemplates,
                onSelect: (_) {},
                onDelete: (_) async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1/2'), findsOneWidget);

      // Kéo chậm (800ms) từ trang 1/2 sang 2/2
      await tester.timedDrag(
        pageViewFinder,
        const Offset(-190, 0),
        const Duration(milliseconds: 800),
      );
      await tester.pumpAndSettle();
      expect(find.text('2/2'), findsOneWidget);

      // Kéo chậm (800ms) từ vùng giữa/phải của trang 2/2 (nơi chỉ có 1 tag ở góc trái) trườn ngược về 1/2
      await tester.timedDragFrom(
        tester.getCenter(pageViewFinder) + const Offset(60, 0),
        const Offset(190, 0),
        const Duration(milliseconds: 800),
      );
      await tester.pumpAndSettle();
      expect(find.text('1/2'), findsOneWidget);
      expect(find.text('cafe'), findsOneWidget);
    });
  });
}

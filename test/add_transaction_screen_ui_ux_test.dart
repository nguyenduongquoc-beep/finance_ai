import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_ai_app/widgets/custom_numpad.dart';
import 'package:finance_ai_app/utils/formatters.dart';

void main() {
  group('CustomNumpad Fintech UI/UX Tests', () {
    testWidgets('1. Hiển thị giá trị ban đầu và định dạng chuẩn tiền tệ VNĐ', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CustomNumpad(initialValue: '150000'),
          ),
        ),
      );

      // 150.000 ₫
      expect(find.text('150.000 ₫'), findsOneWidget);
      expect(find.text('Xác nhận: 150.000 ₫'), findsOneWidget);
    });

    testWidgets('2. Nhập số với phím 000 tăng tốc độ nhập tiền', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CustomNumpad(initialValue: ''),
          ),
        ),
      );

      expect(find.text('0 ₫'), findsOneWidget);

      // Bấm số 5
      await tester.tap(find.text('5'));
      await tester.pump();
      expect(find.text('5 ₫'), findsOneWidget);

      // Bấm 000
      await tester.tap(find.text('000'));
      await tester.pump();
      expect(find.text('5.000 ₫'), findsOneWidget);

      // Bấm 000 tiếp
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

      // Bấm phím C
      await tester.tap(find.text('C'));
      await tester.pump();

      expect(find.text('0 ₫'), findsOneWidget);
    });

    testWidgets('4. Phím xóa lùi Backspace (DEL) xóa từng chữ số', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CustomNumpad(initialValue: '123'),
          ),
        ),
      );

      expect(find.text('123 ₫'), findsOneWidget);

      // Bấm phím Backspace icon
      final delBtn = find.byIcon(Icons.backspace_outlined);
      await tester.ensureVisible(delBtn);
      await tester.tap(delBtn);
      await tester.pump();
      expect(find.text('12 ₫'), findsOneWidget);

      await tester.tap(delBtn);
      await tester.pump();
      expect(find.text('1 ₫'), findsOneWidget);
    });

    testWidgets('5. Chip nạp tiền nhanh (+50.000, +100.000) cộng dồn chính xác', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CustomNumpad(initialValue: '50000'),
          ),
        ),
      );

      expect(find.text('50.000 ₫'), findsOneWidget);

      // Chạm chip +100.000
      await tester.tap(find.text('+100.000'));
      await tester.pump();

      expect(find.text('150.000 ₫'), findsOneWidget);
    });

    testWidgets('6. Hiển thị đọc số tiền lớn (hàng triệu, hàng tỷ) mà không bị tràn viền', (tester) async {
      // 1.500.000.000.000đ (1 nghìn 500 tỷ)
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CustomNumpad(initialValue: '1500000000000'),
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

      // Mở bottom sheet
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Bấm nút xác nhận
      final confirmBtn = find.text('Xác nhận: 750.000 ₫');
      await tester.ensureVisible(confirmBtn);
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      expect(returnedResult, equals('750.000'));
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_ai_app/widgets/spending_trend_bar_chart.dart';

Widget _buildTestApp({
  required List<double> amounts,
  required List<String> monthLabels,
  bool showLegend = true,
  ThemeMode themeMode = ThemeMode.light,
  double horizontalOuterPadding = 32,
}) {
  return MaterialApp(
    theme: ThemeData.light(useMaterial3: true),
    darkTheme: ThemeData.dark(useMaterial3: true),
    themeMode: themeMode,
    home: Scaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: horizontalOuterPadding / 2,
          vertical: 16,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
          decoration: BoxDecoration(
            color: themeMode == ThemeMode.dark
                ? const Color(0xFF1E293B)
                : Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
          child: SpendingTrendBarChart(
            amounts: amounts,
            monthLabels: monthLabels,
            showLegend: showLegend,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('SpendingTrendBarChart Widget Tests', () {
    testWidgets('renders reference dataset metrics and summary correctly',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestApp(
          amounts: const [0, 0, 4050000],
          monthLabels: const ['Tháng 9', 'Tháng 10', 'Tháng 11'],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Tháng 11 (Kỳ này)', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('4.050.000 ₫'), findsOneWidget);
      expect(find.text('+200%'), findsOneWidget);
      expect(find.text('Cao hơn trung bình 3T'), findsOneWidget);
      expect(find.text('Trung bình 3T'), findsOneWidget);
      expect(find.text('1.4M/tháng'), findsOneWidget);
      expect(find.text('Kỳ này'), findsOneWidget);
      expect(find.text('Đỉnh chi tiêu'), findsNWidgets(2));
      expect(find.text('Tháng 11 (4.0M)'), findsOneWidget);
      expect(find.text('Tháng 11 • Kỳ này'), findsOneWidget);
      expect(find.text('Tháng 9'), findsOneWidget);
      expect(find.text('Tháng 10'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping earlier month updates left summary panel interactively',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestApp(
          amounts: const [0, 0, 4050000],
          monthLabels: const ['Tháng 9', 'Tháng 10', 'Tháng 11'],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tháng 9'));
      await tester.pumpAndSettle();

      expect(
        find.text('Tháng 9', findRichText: true),
        findsWidgets,
      );
      expect(find.text('0 ₫'), findsOneWidget);
      expect(find.text('-100%'), findsOneWidget);
      expect(find.text('Thấp hơn trung bình 3T'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'highlights separate peak month while defaulting left summary to current month',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestApp(
          amounts: const [2000000, 5000000, 1500000],
          monthLabels: const ['Tháng 9', 'Tháng 10', 'Tháng 11'],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Tháng 11 (Kỳ này)', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('1.500.000 ₫'), findsOneWidget);
      expect(find.text('Tháng 10 (5M)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('handles all-zero dataset cleanly without division errors',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestApp(
          amounts: const [0, 0, 0],
          monthLabels: const ['Tháng 9', 'Tháng 10', 'Tháng 11'],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('0 ₫'), findsOneWidget);
      expect(find.text('0 ₫/tháng'), findsOneWidget);
      expect(find.text('Chưa có'), findsOneWidget);
      expect(find.text('Chưa có dữ liệu 3T'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('responsive without overflow at 320x640 dark, 360x800, 720x500',
        (tester) async {
      // Narrow 320x640 in dark mode (triggers 2-row fallback summary)
      await tester.binding.setSurfaceSize(const Size(320, 640));
      await tester.pumpWidget(
        _buildTestApp(
          amounts: const [250000000, 1500000000, 950000000],
          monthLabels: const ['Tháng 9', 'Tháng 10', 'Tháng 11'],
          showLegend: false,
          themeMode: ThemeMode.dark,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Trung bình 3T'), findsOneWidget);
      expect(find.text('Kỳ này'), findsNothing);
      expect(find.text('Đỉnh chi tiêu'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Standard mobile 360x800 in light mode
      await tester.binding.setSurfaceSize(const Size(360, 800));
      await tester.pumpWidget(
        _buildTestApp(
          amounts: const [250000000, 1500000000, 950000000],
          monthLabels: const ['Tháng 9', 'Tháng 10', 'Tháng 11'],
          showLegend: false,
          themeMode: ThemeMode.light,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Trung bình 3T'), findsOneWidget);
      expect(find.text('Kỳ này'), findsNothing);
      expect(find.text('Đỉnh chi tiêu'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Wide landscape / tablet 720x500 with billion-scale value
      await tester.binding.setSurfaceSize(const Size(720, 500));
      await tester.pumpWidget(
        _buildTestApp(
          amounts: const [250000000, 1500000000, 1500000000],
          monthLabels: const ['Tháng 9', 'Tháng 10', 'Tháng 11'],
          showLegend: true,
          themeMode: ThemeMode.light,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1,5 tỷ ₫'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.binding.setSurfaceSize(null);
    });
  });
}

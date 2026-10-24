import 'package:flutter_test/flutter_test.dart';
import 'package:finance_ai_app/utils/formatters.dart';

void main() {
  group('AppFormatters Tests', () {
    test('currency formatting', () {
      expect(AppFormatters.currency(1200000), contains('1.200.000'));
      expect(AppFormatters.currency(500), contains('500'));
    });

    test('number formatting', () {
      expect(AppFormatters.number(1200000), equals('1.200.000'));
      expect(AppFormatters.number(0), equals('0'));
    });

    test('date formatting', () {
      final date = DateTime(2026, 8, 1);
      expect(AppFormatters.date(date), equals('01/08/2026'));
    });

    test('month formatting', () {
      final date = DateTime(2026, 8, 1);
      expect(AppFormatters.month(date), equals('08/2026'));
    });

    test('parseCurrencyInput', () {
      expect(AppFormatters.parseCurrencyInput('1.200.000 đ'), equals(1200000.0));
      expect(AppFormatters.parseCurrencyInput('1,200,000'), equals(1200000.0));
      expect(AppFormatters.parseCurrencyInput('  1.200.000 '), equals(1200000.0));
      expect(AppFormatters.parseCurrencyInput('abc'), equals(0.0));
    });

    test('compactCurrency formatting for large amounts', () {
      expect(AppFormatters.compactCurrency(500000), equals('500.000 ₫'));
      expect(AppFormatters.compactCurrency(1500000000), equals('1,5 tỷ ₫'));
      expect(AppFormatters.compactCurrency(1000000000000), equals('1.000 tỷ ₫'));
      expect(AppFormatters.compactCurrency(-1000000000000), equals('-1.000 tỷ ₫'));
      expect(AppFormatters.compactCurrency(2500000000000), equals('2.500 tỷ ₫'));
    });
  });
}

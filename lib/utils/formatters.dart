import 'package:intl/intl.dart';

/// ============================================================
/// FORMATTERS
/// Các hàm định dạng tiền tệ, ngày tháng dùng chung
/// ============================================================
class AppFormatters {
  static final NumberFormat _currencyFormat = NumberFormat.decimalPattern('vi_VN');
  static final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');
  static final DateFormat _monthFormat = DateFormat('MM/yyyy');

  /// Format số tiền: 1200000 -> "1.200.000 VNĐ"
  static String currency(num amount) {
    return '${_currencyFormat.format(amount.round())} VNĐ';
  }

  /// Format số tiền không kèm đơn vị: 1200000 -> "1.200.000"
  static String number(num amount) {
    return _currencyFormat.format(amount.round());
  }

  /// Format số tiền thông minh cho UI fintech (tránh tràn viền khi lên tới hàng tỷ, nghìn tỷ):
  /// - Dưới 1 tỷ (< 1.000.000.000): "500.000 ₫", "15.000.000 ₫"
  /// - Từ 1 tỷ đến dưới 1.000 tỷ: "1,5 tỷ ₫", "120 tỷ ₫"
  /// - Từ 1.000 tỷ trở lên (1.000.000.000.000+): "1.000 tỷ ₫", "2.500 tỷ ₫"
  static String compactCurrency(num amount, {String unit = '₫'}) {
    final abs = amount.abs();
    final sign = amount < 0 ? '-' : '';
    final unitSuffix = unit.trim().isNotEmpty ? ' $unit' : '';

    if (abs < 1e9) {
      return '$sign${_currencyFormat.format(abs.round())}$unitSuffix';
    } else if (abs < 1e12) {
      final ty = abs / 1e9;
      String formatted;
      if (ty >= 100) {
        formatted = ty.toStringAsFixed(0);
      } else if (ty >= 10) {
        final with1 = ty.toStringAsFixed(1);
        formatted = with1.endsWith('.0') ? ty.toStringAsFixed(0) : with1;
      } else {
        final with2 = ty.toStringAsFixed(2);
        formatted = with2.endsWith('.00')
            ? ty.toStringAsFixed(0)
            : (with2.endsWith('0') ? ty.toStringAsFixed(1) : with2);
      }
      final clean = formatted.replaceAll('.', ',');
      return '$sign$clean tỷ$unitSuffix';
    } else {
      // Từ 1.000 tỷ trở lên
      final nghinTy = abs / 1e9;
      final formatted = _currencyFormat.format(nghinTy.round());
      return '$sign$formatted tỷ$unitSuffix';
    }
  }

  /// Format số tiền thông minh không kèm đơn vị
  static String compactNumber(num amount) {
    return compactCurrency(amount, unit: '').trim();
  }

  /// Format ngày: DateTime -> "10/07/2026"
  static String date(DateTime date) {
    return _dateFormat.format(date);
  }

  /// Format ngày giờ: DateTime -> "10/07/2026 21:30"
  static String dateTime(DateTime dt) {
    return DateFormat('dd/MM/yyyy HH:mm').format(dt);
  }

  /// Format tháng: DateTime -> "07/2026"
  static String month(DateTime date) {
    return _monthFormat.format(date);
  }

  /// Parse chuỗi tiền tệ nhập vào (loại bỏ dấu chấm) -> double
  static double parseCurrencyInput(String input) {
    final cleaned = input.replaceAll('.', '').replaceAll(',', '').replaceAll(' đ', '').trim();
    return double.tryParse(cleaned) ?? 0;
  }
}

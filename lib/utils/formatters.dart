import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/language_controller.dart';

/// ============================================================
/// FORMATTERS
/// Các hàm định dạng tiền tệ, ngày tháng và bộ định dạng nhập liệu dùng chung
/// ============================================================
class AppFormatters {
  static final NumberFormat _currencyFormat = NumberFormat.decimalPattern('vi_VN');
  static final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');
  static final DateFormat _monthFormat = DateFormat('MM/yyyy');

  /// Format số tiền: 1200000 -> "1.200.000 VNĐ" (hoặc "1.200.000 VND" khi EN)
  static String currency(num amount) {
    final unitLabel = LanguageController.isEnglish ? 'VND' : 'VNĐ';
    return '${_currencyFormat.format(amount.round())} $unitLabel';
  }

  /// Format số tiền không kèm đơn vị: 1200000 -> "1.200.000"
  static String number(num amount) {
    return _currencyFormat.format(amount.round());
  }

  /// Định dạng chuỗi chữ số thuần thành chuỗi có dấu chấm phân cách hàng nghìn.
  /// Ví dụ: "1000000" -> "1.000.000", "555855588" -> "555.855.588"
  static String formatDigitsWithDots(String digitsOnly) {
    final cleaned = digitsOnly.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleaned.isEmpty) return '';
    final normalized = cleaned.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    return normalized.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (match) => '.',
    );
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
      final isEn = LanguageController.isEnglish;
      final clean = isEn ? formatted : formatted.replaceAll('.', ',');
      final billSuffix = isEn ? 'B' : ' tỷ';
      return '$sign$clean$billSuffix$unitSuffix';
    } else {
      // Từ 1.000 tỷ trở lên
      final nghinTy = abs / 1e9;
      final formatted = _currencyFormat.format(nghinTy.round());
      final billSuffix = LanguageController.isEnglish ? 'B' : ' tỷ';
      return '$sign$formatted$billSuffix$unitSuffix';
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

  /// Parse chuỗi tiền tệ nhập vào (loại bỏ dấu chấm, phẩy, ký hiệu tiền tệ) -> double
  static double parseCurrencyInput(String input) {
    final cleaned = input
        .replaceAll('.', '')
        .replaceAll(',', '')
        .replaceAll('₫', '')
        .replaceAll('đ', '')
        .replaceAll(RegExp(r'[vV][nN][đĐdD]'), '')
        .replaceAll(RegExp(r'\s+'), '')
        .trim();
    return double.tryParse(cleaned) ?? 0;
  }
}

/// Bộ định dạng nhập liệu tiền tệ dùng chung trên toàn ứng dụng.
/// Tự động chèn dấu chấm phân cách hàng nghìn ngay khi nhập/xóa (VD: 1000000 -> 1.000.000)
/// và giữ vị trí con trỏ chính xác tuyệt đối.
class CurrencyInputFormatter extends TextInputFormatter {
  const CurrencyInputFormatter();

  static bool _isDigit(int codeUnit) => codeUnit >= 48 && codeUnit <= 57;

  static int _countDigits(String text, [int? endOffset]) {
    final limit = (endOffset ?? text.length).clamp(0, text.length);
    var count = 0;
    for (var i = 0; i < limit; i++) {
      if (_isDigit(text.codeUnitAt(i))) {
        count++;
      }
    }
    return count;
  }

  static String _extractDigits(String text) {
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final cu = text.codeUnitAt(i);
      if (_isDigit(cu)) {
        buffer.writeCharCode(cu);
      }
    }
    return buffer.toString();
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    final oldDigits = _extractDigits(oldValue.text);
    var workingDigits = _extractDigits(newValue.text);
    final selectionEnd =
        newValue.selection.end.clamp(0, newValue.text.length);
    var digitsBeforeCursor = _countDigits(newValue.text, selectionEnd);

    // Xử lý trường hợp người dùng nhấn Backspace ngay sau dấu chấm '.'
    if (oldValue.selection.isCollapsed &&
        newValue.selection.isCollapsed &&
        oldValue.text.length - newValue.text.length == 1 &&
        selectionEnd >= 0 &&
        selectionEnd < oldValue.text.length &&
        oldValue.text[selectionEnd] == '.' &&
        oldDigits == workingDigits) {
      final digitsBeforeDot = _countDigits(oldValue.text, selectionEnd);
      if (digitsBeforeDot > 0 && digitsBeforeDot <= workingDigits.length) {
        workingDigits = workingDigits.substring(0, digitsBeforeDot - 1) +
            workingDigits.substring(digitsBeforeDot);
        digitsBeforeCursor = digitsBeforeDot - 1;
      }
    }

    if (workingDigits.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    // Loại bỏ các số 0 đứng đầu không cần thiết (trừ khi chỉ có một chữ số '0')
    final normalizedDigits =
        workingDigits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final removedLeadingZeros =
        workingDigits.length - normalizedDigits.length;
    final targetDigitIndex = (digitsBeforeCursor - removedLeadingZeros)
        .clamp(0, normalizedDigits.length);

    final formattedText = AppFormatters.formatDigitsWithDots(normalizedDigits);

    // Tính vị trí con trỏ mới dựa trên số lượng chữ số đứng trước con trỏ
    var newCursorOffset = 0;
    if (targetDigitIndex > 0) {
      var seenDigits = 0;
      for (var i = 0; i < formattedText.length; i++) {
        if (_isDigit(formattedText.codeUnitAt(i))) {
          seenDigits++;
          if (seenDigits == targetDigitIndex) {
            newCursorOffset = i + 1;
            break;
          }
        }
      }
    }

    return TextEditingValue(
      text: formattedText,
      selection: TextSelection.collapsed(
        offset: newCursorOffset.clamp(0, formattedText.length),
      ),
    );
  }
}

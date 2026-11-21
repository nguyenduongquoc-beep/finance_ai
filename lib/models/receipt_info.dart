import '../utils/formatters.dart';

class ReceiptInfo {
  final String? address;
  final String merchant;
  final double total;
  final DateTime? date;
  final String? taxId;
  final List<ReceiptItem>? items;
  final String? paymentMethod;
  final String? rawText;

  /// Đánh dấu nếu tên cửa hàng hoặc địa chỉ có phần được AI suy luận từ chữ mờ
  final bool isLocationInferred;

  /// Danh sách ghi chú ngắn mô tả các trường được AI suy luận hoặc chữ mờ chưa chắc chắn
  final List<String> inferredFields;

  ReceiptInfo({
    required this.merchant,
    required this.total,
    this.date,
    this.taxId,
    this.address,
    this.items,
    this.paymentMethod,
    this.rawText,
    this.isLocationInferred = false,
    this.inferredFields = const [],
  });

  /// Kiểm tra hóa đơn có thông tin nào do AI suy luận từ chữ mờ cần người dùng lưu ý kiểm tra hay không
  bool get hasInferredData =>
      isLocationInferred ||
      inferredFields.isNotEmpty ||
      (items != null && items!.any((it) => it.isInferred));

  /// Bảng từ điển khôi phục các cụm từ tiếng Việt phổ biến trên hóa đơn thường bị OCR đọc nhầm dấu do mờ/nhòe chữ
  static const Map<String, String> _contextualPhrases = {
    'ca phe sua da may': 'Cà Phê Sữa Đá Máy',
    'cà phê sữa đa máy': 'Cà Phê Sữa Đá Máy',
    'ca phe sua đa may': 'Cà Phê Sữa Đá Máy',
    'cà phê sữa đa': 'Cà Phê Sữa Đá',
    'ca phe sua da': 'Cà Phê Sữa Đá',
    'cà phê đá': 'Cà Phê Đá',
    'ca phe da': 'Cà Phê Đá',
    'cà phê đen đa': 'Cà Phê Đen Đá',
    'ca phe den da': 'Cà Phê Đen Đá',
    'bạc xiu': 'Bạc Xỉu',
    'bac xiu': 'Bạc Xỉu',
    'trà đao': 'Trà Đào',
    'tra dao': 'Trà Đào',
    'trà vai': 'Trà Vải',
    'tra vai': 'Trà Vải',
    'trà sưa': 'Trà Sữa',
    'tra sua': 'Trà Sữa',
    'sữa đa': 'Sữa Đá',
    'sua da': 'Sữa Đá',
  };

  static const Map<String, String> _contextualLocationPhrases = {
    'bach dang': 'Bạch Đằng',
    'bạch đăng': 'Bạch Đằng',
    'phu cuong': 'Phú Cường',
    'phú cương': 'Phú Cường',
    'thu dau mot': 'Thủ Dầu Một',
    'thủ dầu môt': 'Thủ Dầu Một',
    'binh duong': 'Bình Dương',
    'bình dương': 'Bình Dương',
    'tp thu dau mot': 'Tp Thủ Dầu Một',
  };

  /// Khôi phục ngữ cảnh cho tên mặt hàng bị mờ/nhầm dấu tiếng Việt.
  /// Trả về bản ghi gồm text đã chuẩn hóa và cờ đánh dấu nếu có can thiệp suy luận.
  static ({String text, bool wasRestored}) restoreItemDescription(
      String input) {
    var cleaned = input
        .replaceAll(RegExp(r'\s*\n+\s*'), ' ')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
    if (cleaned.isEmpty) return (text: '', wasRestored: false);

    final lower = cleaned.toLowerCase();
    bool restored = false;

    // Khớp toàn cụm hoặc cụm con theo ngữ cảnh đồ uống / mặt hàng phổ biến
    for (final entry in _contextualPhrases.entries) {
      if (lower == entry.key) {
        if (cleaned != entry.value) {
          cleaned = entry.value;
          restored = true;
        }
        break;
      } else if (lower.contains(entry.key)) {
        final regex = RegExp(RegExp.escape(entry.key), caseSensitive: false);
        final next = cleaned.replaceAll(regex, entry.value);
        if (next != cleaned) {
          cleaned = next;
          restored = true;
        }
      }
    }

    return (text: cleaned, wasRestored: restored);
  }

  /// Làm sạch và khôi phục ngữ cảnh cho thông tin địa chỉ / cửa hàng,
  /// loại bỏ các mảnh ký tự rác vô nghĩa do ảnh mờ nhưng không tự bịa địa chỉ mới.
  static ({String text, bool wasRestored}) cleanAndRestoreLocationPart(
      String? input) {
    if (input == null) return (text: '', wasRestored: false);
    var cleaned = input
        .replaceAll(RegExp(r'\s*\n+\s*'), ', ')
        .replaceAll(RegExp(r',\s*,+'), ', ')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
    if (cleaned.isEmpty) return (text: '', wasRestored: false);

    // Loại bỏ tiền tố "Địa chỉ:" hoặc "ĐC:" nếu OCR lấy cả nhãn
    cleaned = cleaned
        .replaceFirst(
            RegExp(r'^(địa\s*chỉ|dia\s*chi|đ/c|đc)\s*[:\-]?\s*',
                caseSensitive: false),
            '')
        .trim();

    bool restored = false;
    final lower = cleaned.toLowerCase();
    for (final entry in _contextualLocationPhrases.entries) {
      if (lower.contains(entry.key)) {
        final regex = RegExp(RegExp.escape(entry.key), caseSensitive: false);
        final next = cleaned.replaceAll(regex, entry.value);
        if (next != cleaned) {
          cleaned = next;
          restored = true;
        }
      }
    }

    // Tách theo dấu phẩy để lọc bỏ các mảnh quá ngắn/vô nghĩa do nhòe ảnh (VD: "??", "---", "*")
    final segments = cleaned
        .split(',')
        .map((s) => s.trim())
        .where((s) =>
            s.isNotEmpty &&
            RegExp(r'[a-zA-ZÀ-ỹ0-9]').hasMatch(s) &&
            !RegExp(r'^[^a-zA-ZÀ-ỹ0-9]+$').hasMatch(s))
        .toList();

    return (text: segments.join(', '), wasRestored: restored);
  }

  /// Tạo chuỗi Địa điểm kết hợp hợp lý giữa tên cửa hàng (merchant) và địa chỉ (address).
  /// Nếu một phần bị mờ/thiếu, ưu tiên giữ lại phần đọc được rõ ràng.
  String get resolvedLocation {
    final cleanMerchant = merchant.trim();
    final cleanAddr = (address ?? '').trim();

    if (cleanMerchant.isNotEmpty && cleanAddr.isNotEmpty) {
      final normM = cleanMerchant.toLowerCase();
      final normA = cleanAddr.toLowerCase();
      if (normA.startsWith(normM) || normA.contains(normM)) {
        return cleanAddr;
      }
      if (normM.contains(normA)) {
        return cleanMerchant;
      }
      return '$cleanMerchant - $cleanAddr';
    }
    if (cleanMerchant.isNotEmpty) return cleanMerchant;
    if (cleanAddr.isNotEmpty) return cleanAddr;
    return '';
  }

  /// Tạo nội dung Ghi chú thông minh, linh hoạt theo dữ liệu thực tế của từng mặt hàng trên hóa đơn.
  String buildFormattedNote() {
    if (items != null && items!.isNotEmpty) {
      final validLines = items!
          .map((it) => it.formatNoteLine())
          .where((line) => line.trim().isNotEmpty)
          .toList();
      if (validLines.isNotEmpty) {
        return validLines.join('\n');
      }
    }
    if (merchant.trim().isNotEmpty) {
      return merchant.trim();
    }
    return '';
  }

  static DateTime? _parseFlexibleDate(dynamic raw) {
    if (raw == null) return null;
    final str = raw.toString().trim();
    if (str.isEmpty || str.toLowerCase() == 'null') return null;

    final isoParsed = DateTime.tryParse(str);
    if (isoParsed != null) return isoParsed;

    // Hỗ trợ dd/MM/yyyy hoặc dd-MM-yyyy
    final dmyMatch =
        RegExp(r'^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})').firstMatch(str);
    if (dmyMatch != null) {
      final day = int.tryParse(dmyMatch.group(1)!);
      final month = int.tryParse(dmyMatch.group(2)!);
      final year = int.tryParse(dmyMatch.group(3)!);
      if (day != null && month != null && year != null) {
        return DateTime(year, month, day);
      }
    }
    return null;
  }

  static double _parseFlexibleAmount(dynamic raw) {
    if (raw == null) return 0.0;
    if (raw is num) return raw.toDouble();
    final str = raw.toString().trim();
    if (str.isEmpty) return 0.0;
    final cleaned = str.replaceAll(RegExp(r'[^\d]'), '');
    return double.tryParse(cleaned) ?? 0.0;
  }

  static double? _parseNullableAmount(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) {
      final val = raw.toDouble();
      return val > 0 ? val : null;
    }
    final str = raw.toString().trim();
    if (str.isEmpty ||
        str.toLowerCase() == 'null' ||
        str.toLowerCase() == 'none') {
      return null;
    }
    final cleaned = str.replaceAll(RegExp(r'[^\d]'), '');
    if (cleaned.isEmpty) return null;
    final parsed = double.tryParse(cleaned);
    return (parsed != null && parsed > 0) ? parsed : null;
  }

  static double? _parseNullableQuantity(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) {
      final val = raw.toDouble();
      return val > 0 ? val : null;
    }
    final str = raw.toString().trim();
    if (str.isEmpty ||
        str.toLowerCase() == 'null' ||
        str.toLowerCase() == 'none') {
      return null;
    }
    final normalized = str.replaceAll(',', '.').replaceAll(RegExp(r'[^\d\.]'), '');
    if (normalized.isEmpty) return null;
    final parsed = double.tryParse(normalized);
    return (parsed != null && parsed > 0) ? parsed : null;
  }

  static String? _cleanNullableString(dynamic raw) {
    if (raw == null) return null;
    final str = raw.toString().trim();
    if (str.isEmpty ||
        str.toLowerCase() == 'null' ||
        str.toLowerCase() == 'none' ||
        str.toLowerCase() == 'n/a') {
      return null;
    }
    return str;
  }

  factory ReceiptInfo.fromJson(
    Map<String, dynamic> json, {
    String? rawText,
  }) {
    final paymentRaw =
        json['paymentMethod'] ?? json['payment_method'] ?? json['wallet'];

    final rawMerchant = (json['merchant'] ?? '').toString().trim();
    final restoredMerchant = cleanAndRestoreLocationPart(rawMerchant);

    final rawAddress = _cleanNullableString(json['address']);
    final restoredAddress = cleanAndRestoreLocationPart(rawAddress);

    final parsedItems = json['items'] is List
        ? (json['items'] as List)
            .whereType<Map>()
            .map((e) => ReceiptItem.fromJson(Map<String, dynamic>.from(e)))
            .where((it) => it.description.isNotEmpty)
            .toList()
        : null;

    final List<String> inferredList = [];
    if (json['inferredFields'] is List) {
      for (final entry in (json['inferredFields'] as List)) {
        final s = entry.toString().trim();
        if (s.isNotEmpty && s.toLowerCase() != 'null') {
          inferredList.add(s);
        }
      }
    }

    final bool locInferred = (json['isLocationInferred'] == true) ||
        restoredMerchant.wasRestored ||
        restoredAddress.wasRestored;

    if (parsedItems != null) {
      for (final item in parsedItems) {
        if (item.isInferred) {
          final msg = 'Mặt hàng "${item.description}" được khôi phục theo ngữ cảnh';
          if (!inferredList.contains(msg)) {
            inferredList.add(msg);
          }
        }
      }
    }

    double parsedTotal = _parseFlexibleAmount(json['total']);
    if (parsedTotal <= 0 && parsedItems != null && parsedItems.isNotEmpty) {
      parsedTotal = parsedItems.fold<double>(0.0, (sum, it) => sum + it.amount);
    }

    return ReceiptInfo(
      merchant: restoredMerchant.text,
      total: parsedTotal,
      date: _parseFlexibleDate(json['date']),
      taxId: _cleanNullableString(json['taxId']),
      address: restoredAddress.text.isNotEmpty ? restoredAddress.text : null,
      paymentMethod: _cleanNullableString(paymentRaw),
      rawText: _cleanNullableString(rawText ?? json['rawText']),
      items: parsedItems,
      isLocationInferred: locInferred,
      inferredFields: inferredList,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'merchant': merchant,
      'total': total,
      'date': date?.toIso8601String(),
      'taxId': taxId,
      'address': address,
      'paymentMethod': paymentMethod,
      'rawText': rawText,
      'isLocationInferred': isLocationInferred,
      'inferredFields': inferredFields,
      'items': items?.map((e) => e.toJson()).toList(),
    };
  }
}

class ReceiptItem {
  final String description;
  final double? quantity;
  final double? unitPrice;
  final double amount;
  final bool isInferred;

  ReceiptItem({
    required this.description,
    this.quantity,
    this.unitPrice,
    required this.amount,
    this.isInferred = false,
  });

  /// Kiểm tra tính nhất quán giữa Số lượng, Đơn giá và Thành tiền khi cả 3 trường đều có mặt
  bool get isPriceConsistent {
    if (quantity != null &&
        quantity! > 0 &&
        unitPrice != null &&
        unitPrice! > 0 &&
        amount > 0) {
      return ((quantity! * unitPrice!) - amount).abs() <= 1.0;
    }
    return true;
  }

  static String _formatQty(double q) {
    if (q == q.roundToDouble()) {
      return q.toInt().toString();
    }
    return q.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
  }

  /// Diễn giải dòng ghi chú linh hoạt dựa trên các trường thực tế có trên hóa đơn.
  /// Không ép buộc một mẫu cố định và không tự suy diễn trường bị thiếu.
  String formatNoteLine() {
    final desc = description.trim();
    if (desc.isEmpty) return '';

    final hasQty = quantity != null && quantity! > 0;
    final hasUnit = unitPrice != null && unitPrice! > 0;
    final hasAmt = amount > 0;

    // 1. Có đầy đủ Số lượng, Đơn giá và Thành tiền
    if (hasQty && hasUnit && hasAmt) {
      final qtyStr = _formatQty(quantity!);
      final unitStr = '${AppFormatters.number(unitPrice!)}₫';
      final amtStr = '${AppFormatters.number(amount)}₫';

      if (isPriceConsistent) {
        return '$desc: $qtyStr x $unitStr = $amtStr';
      }
      // Trường hợp thành tiền khác (SL * đơn giá) do giảm giá / phụ phí riêng
      return '$desc (SL: $qtyStr, đơn giá: $unitStr, tổng: $amtStr)';
    }

    // 2. Có Số lượng và Thành tiền (không có Đơn giá)
    if (hasQty && !hasUnit && hasAmt) {
      final qtyStr = _formatQty(quantity!);
      final amtStr = '${AppFormatters.number(amount)}₫';
      return '$desc (SL: $qtyStr, tổng: $amtStr)';
    }

    // 3. Có Số lượng và Đơn giá (chưa có Thành tiền)
    if (hasQty && hasUnit && !hasAmt) {
      final qtyStr = _formatQty(quantity!);
      final unitStr = '${AppFormatters.number(unitPrice!)}₫';
      final computedTotal = quantity! * unitPrice!;
      final amtStr = '${AppFormatters.number(computedTotal)}₫';
      return '$desc: $qtyStr x $unitStr = $amtStr';
    }

    // 4. Có Đơn giá và Thành tiền nhưng hóa đơn không ghi Số lượng
    if (!hasQty && hasUnit && hasAmt) {
      final amtStr = '${AppFormatters.number(amount)}₫';
      if ((unitPrice! - amount).abs() <= 1.0) {
        return '$desc: $amtStr';
      }
      final unitStr = '${AppFormatters.number(unitPrice!)}₫';
      return '$desc (đơn giá: $unitStr, tổng: $amtStr)';
    }

    // 5. Chỉ có Tên mặt hàng và Thành tiền
    if (!hasQty && !hasUnit && hasAmt) {
      return '$desc: ${AppFormatters.number(amount)}₫';
    }

    // 6. Chỉ có Tên mặt hàng và Số lượng (không có giá từng món)
    if (hasQty && !hasUnit && !hasAmt) {
      return '$desc (SL: ${_formatQty(quantity!)})';
    }

    // 7. Chỉ có Tên mặt hàng
    return desc;
  }

  factory ReceiptItem.fromJson(Map<String, dynamic> json) {
    final rawDesc = (json['description'] ?? json['name'] ?? '').toString();
    final restored = ReceiptInfo.restoreItemDescription(rawDesc);

    final qty = ReceiptInfo._parseNullableQuantity(
      json['quantity'] ?? json['qty'] ?? json['sl'],
    );
    final unitPrice = ReceiptInfo._parseNullableAmount(
      json['unitPrice'] ?? json['unit_price'] ?? json['price'],
    );
    var amount = ReceiptInfo._parseFlexibleAmount(
      json['amount'] ?? json['total'] ?? json['lineTotal'],
    );

    // Đảm bảo tính nhất quán khi có đủ Số lượng và Đơn giá:
    // - Nếu hóa đơn không đọc được amount nhưng có cả SL và Đơn giá -> tính amount = SL * Đơn giá.
    // - Nếu cả 3 đều có mặt nhưng amount bị lệch do nhầm chữ số OCR còn SL * Đơn giá hợp lý,
    //   giữ nguyên hoặc chuẩn hóa khi SL * Đơn giá khớp logic bảng.
    if (qty != null && qty > 0 && unitPrice != null && unitPrice > 0) {
      if (amount <= 0) {
        amount = qty * unitPrice;
      }
    }

    final inferredFlag = (json['isInferred'] == true) || restored.wasRestored;

    return ReceiptItem(
      description: restored.text,
      quantity: qty,
      unitPrice: unitPrice,
      amount: amount,
      isInferred: inferredFlag,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'description': description,
      if (quantity != null) 'quantity': quantity,
      if (unitPrice != null) 'unitPrice': unitPrice,
      'amount': amount,
      'isInferred': isInferred,
    };
  }
}

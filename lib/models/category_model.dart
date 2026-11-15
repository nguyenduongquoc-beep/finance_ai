/// ============================================================
/// CATEGORY MODEL
/// Firestore collection: categories/{categoryId}
/// ============================================================
class Category {
  final String categoryId;
  final String userId;
  final String name;
  final String type; // income | expense
  final String icon; // tên icon (map sang IconData ở UI layer)
  final int color; // giá trị màu ARGB
  final bool isEssential; // true: Thiết yếu (Cố định/Bắt buộc), false: Linh hoạt (Có thể điều chỉnh)
  final DateTime? updatedAt;

  Category({
    required this.categoryId,
    required this.userId,
    required this.name,
    required this.type,
    required this.icon,
    required this.color,
    bool? isEssential,
    this.updatedAt,
  }) : isEssential = isEssential ??
            (type == 'expense'
                ? inferDefaultEssential(name: name, icon: icon)
                : false);

  /// Suy luận giá trị mặc định cho dữ liệu danh mục cũ chưa có trường `isEssential` trên Firestore.
  /// Người dùng luôn có thể tùy chỉnh lại trường này cho từng danh mục.
  static bool inferDefaultEssential({
    required String name,
    required String icon,
  }) {
    final normalizedName = name.trim().toLowerCase();
    final normalizedIcon = icon.trim().toLowerCase();

    // Các icon mặc định mang tính thiết yếu
    const essentialIcons = {
      'local_hospital',
      'school',
      'receipt_long',
      'local_gas_station',
      'home',
      'house',
    };
    if (essentialIcons.contains(normalizedIcon)) {
      return true;
    }

    // Các từ khóa tên danh mục thiết yếu phổ biến
    const essentialKeywords = [
      'nhà ở',
      'thuê nhà',
      'tiền nhà',
      'điện',
      'nước',
      'internet',
      'hóa đơn',
      'y tế',
      'thuốc',
      'khám bệnh',
      'bảo hiểm',
      'học tập',
      'học phí',
      'giáo dục',
      'xăng xe',
      'di chuyển',
      'đi lại',
    ];
    for (final kw in essentialKeywords) {
      if (normalizedName.contains(kw)) {
        return true;
      }
    }

    return false;
  }

  factory Category.fromMap(Map<String, dynamic> map, String id) {
    final name = (map['name'] ?? '').toString();
    final type = (map['type'] ?? 'expense').toString();
    final icon = (map['icon'] ?? 'category').toString();
    final bool resolvedEssential = map['isEssential'] is bool
        ? map['isEssential'] as bool
        : (type == 'expense'
            ? inferDefaultEssential(name: name, icon: icon)
            : false);

    DateTime? parsedUpdatedAt;
    final rawUpdated = map['updatedAt'];
    if (rawUpdated is DateTime) {
      parsedUpdatedAt = rawUpdated;
    } else if (rawUpdated is String) {
      parsedUpdatedAt = DateTime.tryParse(rawUpdated);
    } else if (rawUpdated != null) {
      try {
        parsedUpdatedAt = (rawUpdated as dynamic).toDate() as DateTime;
      } catch (_) {}
    }

    return Category(
      categoryId: id,
      userId: (map['userId'] ?? '').toString(),
      name: name,
      type: type,
      icon: icon,
      color: map['color'] is int
          ? map['color'] as int
          : (map['color'] is num ? (map['color'] as num).toInt() : 0xFF9E9E9E),
      isEssential: resolvedEssential,
      updatedAt: parsedUpdatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'name': name,
      'type': type,
      'icon': icon,
      'color': color,
      'isEssential': isEssential,
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }

  Category copyWith({
    String? categoryId,
    String? userId,
    String? name,
    String? type,
    String? icon,
    int? color,
    bool? isEssential,
    DateTime? updatedAt,
  }) {
    return Category(
      categoryId: categoryId ?? this.categoryId,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      type: type ?? this.type,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      isEssential: isEssential ?? this.isEssential,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

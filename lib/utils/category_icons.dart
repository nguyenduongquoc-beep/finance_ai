import 'package:flutter/material.dart';

/// Danh sách các mã icon danh mục chuẩn hỗ trợ trên cả User App và Admin Web.
const List<Map<String, dynamic>> kSystemCategoryIconOptions = [
  {'key': 'restaurant', 'label': 'Ăn uống', 'icon': Icons.restaurant_rounded},
  {
    'key': 'shopping_bag',
    'label': 'Mua sắm',
    'icon': Icons.shopping_bag_outlined,
  },
  {
    'key': 'local_gas_station',
    'label': 'Xăng xe / Di chuyển',
    'icon': Icons.local_gas_station_rounded,
  },
  {'key': 'home', 'label': 'Nhà ở', 'icon': Icons.home_outlined},
  {
    'key': 'receipt_long',
    'label': 'Hóa đơn / Tiện ích',
    'icon': Icons.receipt_long_rounded,
  },
  {'key': 'school', 'label': 'Học tập / Giáo dục', 'icon': Icons.school_outlined},
  {
    'key': 'local_hospital',
    'label': 'Y tế / Sức khỏe',
    'icon': Icons.local_hospital_outlined,
  },
  {'key': 'movie', 'label': 'Giải trí', 'icon': Icons.movie_outlined},
  {'key': 'flight', 'label': 'Du lịch', 'icon': Icons.flight_takeoff_rounded},
  {'key': 'pets', 'label': 'Thú cưng', 'icon': Icons.pets_rounded},
  {
    'key': 'fitness_center',
    'label': 'Thể thao',
    'icon': Icons.fitness_center_rounded,
  },
  {'key': 'work', 'label': 'Lương / Công việc', 'icon': Icons.work_outline_rounded},
  {
    'key': 'card_giftcard',
    'label': 'Thưởng / Quà tặng',
    'icon': Icons.card_giftcard_rounded,
  },
  {
    'key': 'storefront',
    'label': 'Bán hàng / Kinh doanh',
    'icon': Icons.storefront_rounded,
  },
  {
    'key': 'trending_up',
    'label': 'Đầu tư / Lãi',
    'icon': Icons.trending_up_rounded,
  },
  {'key': 'category', 'label': 'Khác', 'icon': Icons.category_outlined},
];

/// Bảng màu chuẩn cho danh mục hệ thống.
const List<int> kSystemCategoryColorPalette = [
  0xFFEF4444, // Đỏ
  0xFFF97316, // Cam
  0xFFF59E0B, // Vàng hổ phách
  0xFF10B981, // Xanh ngọc lục bảo
  0xFF84CC16, // Xanh lá mạ
  0xFF06B6D4, // Xanh cổ vịt
  0xFF1F6F8B, // Xanh Petrol (Primary)
  0xFF3B82F6, // Xanh dương
  0xFF8B5CF6, // Tím
  0xFFEC4899, // Hồng
];

/// Ánh xạ tên icon danh mục (lưu trong Firestore) sang [IconData].
IconData categoryIconData(String? iconName) {
  switch (iconName) {
    case 'work':
      return Icons.work_outline_rounded;
    case 'card_giftcard':
      return Icons.card_giftcard_rounded;
    case 'storefront':
      return Icons.storefront_rounded;
    case 'restaurant':
      return Icons.restaurant_rounded;
    case 'shopping_bag':
      return Icons.shopping_bag_outlined;
    case 'local_gas_station':
      return Icons.local_gas_station_rounded;
    case 'school':
      return Icons.school_outlined;
    case 'movie':
      return Icons.movie_outlined;
    case 'flight':
      return Icons.flight_takeoff_rounded;
    case 'local_hospital':
      return Icons.local_hospital_outlined;
    case 'home':
    case 'house':
      return Icons.home_outlined;
    case 'receipt_long':
      return Icons.receipt_long_rounded;
    case 'pets':
      return Icons.pets_rounded;
    case 'fitness_center':
      return Icons.fitness_center_rounded;
    case 'trending_up':
      return Icons.trending_up_rounded;
    case 'category':
      return Icons.category_outlined;
    default:
      return Icons.receipt_long_rounded;
  }
}

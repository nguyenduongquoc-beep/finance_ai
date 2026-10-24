import 'package:flutter/material.dart';

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
    default:
      return Icons.receipt_long_rounded;
  }
}

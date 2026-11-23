import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

/// ============================================================
/// STORAGE SERVICE
/// Lưu và xóa ảnh hóa đơn giao dịch cục bộ trên thiết bị (thuần Spark)
/// ============================================================
class StorageService {
  /// Lưu ảnh hóa đơn giao dịch vào thư mục ứng dụng cục bộ
  /// Đường dẫn: {appDocumentsDir}/receipts/{userId}_{timestamp}.jpg
  Future<String> uploadReceiptImage(String userId, Uint8List imageBytes) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final receiptsDir = Directory('${docsDir.path}/receipts');
    if (!await receiptsDir.exists()) {
      await receiptsDir.create(recursive: true);
    }
    final fileName = '${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final file = File('${receiptsDir.path}/$fileName');
    await file.writeAsBytes(imageBytes);
    return file.path;
  }

  /// Xóa ảnh hóa đơn cục bộ theo đường dẫn đã lưu
  Future<void> deleteImageByUrl(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      // Ignored errors during deletion
    }
  }
}

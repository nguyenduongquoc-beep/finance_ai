import '../models/support_ticket_model.dart';
import '../utils/constants.dart';
import 'support_device_info_web.dart'
    if (dart.library.io) 'support_device_info_io.dart' as platform_info;

/// Thu thập thông tin kỹ thuật cơ bản, an toàn (chỉ dành cho yêu cầu báo lỗi).
/// Không thu thập dữ liệu tài chính, số dư, giao dịch, định danh thiết bị hay vị trí.
SupportTechnicalInfo collectBasicSupportTechnicalInfo({
  DateTime? capturedAtUtc,
  String? appVersionOverride,
}) {
  final nowUtc = (capturedAtUtc ?? DateTime.now()).toUtc();
  final rawPlatform = platform_info.detectSupportPlatformName();
  final rawOsVersion = platform_info.detectSupportOsVersion();

  final cleanVersion = (appVersionOverride ?? AppStrings.appVersion).trim();
  final safeVersion = cleanVersion.isEmpty
      ? AppStrings.appVersion
      : (cleanVersion.length <= 32
          ? cleanVersion
          : cleanVersion.substring(0, 32));

  final safePlatform = rawPlatform.trim().isEmpty
      ? 'Unknown'
      : (rawPlatform.trim().length <= 32
          ? rawPlatform.trim()
          : rawPlatform.trim().substring(0, 32));

  String? safeOs;
  if (rawOsVersion != null) {
    final normalized = rawOsVersion.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isNotEmpty) {
      safeOs = normalized.length <= 100
          ? normalized
          : normalized.substring(0, 100);
    }
  }

  return SupportTechnicalInfo(
    appVersion: safeVersion,
    platform: safePlatform,
    osVersion: safeOs,
    capturedAt: nowUtc,
  );
}

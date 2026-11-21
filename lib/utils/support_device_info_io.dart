import 'dart:io' show Platform;

String detectSupportPlatformName() {
  try {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    return Platform.operatingSystem;
  } catch (_) {
    return 'Unknown';
  }
}

String? detectSupportOsVersion() {
  try {
    final raw = Platform.operatingSystemVersion.trim();
    if (raw.isEmpty) return null;
    // Chỉ giữ chuỗi gọn, loại bỏ khoảng trắng thừa / ký tự xuống dòng
    final compact = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.isEmpty) return null;
    return compact.length <= 100 ? compact : compact.substring(0, 100);
  } catch (_) {
    return null;
  }
}

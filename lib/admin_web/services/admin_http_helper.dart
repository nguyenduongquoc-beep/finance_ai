import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Phân loại lỗi chuẩn hóa giữa Client (Flutter Web / Test) và Cloud Functions.
enum AdminCloudErrorKind {
  none,
  network,
  timeout,
  unauthenticated,
  forbidden,
  validation,
  notFound,
  rateLimited,
  server,
  unknown,
}

/// Ngoại lệ chuẩn hóa khi gọi Cloud Function Admin thất bại (HTTP 4xx/5xx hoặc lỗi mạng).
class AdminCloudCallException implements Exception {
  final int statusCode;
  final AdminCloudErrorKind kind;
  final String message;
  final List<String> validationErrors;

  const AdminCloudCallException({
    required this.statusCode,
    required this.kind,
    required this.message,
    this.validationErrors = const [],
  });

  bool get isAuthOrPermissionError =>
      kind == AdminCloudErrorKind.unauthenticated ||
      kind == AdminCloudErrorKind.forbidden;

  @override
  String toString() {
    if (validationErrors.isEmpty) return message;
    return '$message (${validationErrors.join('; ')})';
  }
}

/// Cấu trúc response chuẩn hóa dùng chung giữa Client và Server cho mọi Admin endpoint.
class AdminCloudResponse {
  final int statusCode;
  final Map<String, dynamic>? data;
  final String? error;
  final List<String> validationErrors;
  final AdminCloudErrorKind errorKind;

  const AdminCloudResponse({
    required this.statusCode,
    this.data,
    this.error,
    this.validationErrors = const [],
    this.errorKind = AdminCloudErrorKind.none,
  });

  bool get isSuccess =>
      statusCode >= 200 &&
      statusCode < 300 &&
      errorKind == AdminCloudErrorKind.none &&
      (error == null || error!.isEmpty);

  /// Giải phóng payload Map theo format chuẩn, đồng thời giữ các field top-level từ [data] để tương thích caller cũ.
  Map<String, dynamic> toNormalizedMap() => <String, dynamic>{
        if (data != null) ...data!,
        'statusCode': statusCode,
        'data': data,
        if (error != null) 'error': error,
        if (validationErrors.isNotEmpty) 'validationErrors': validationErrors,
        'errorKind': errorKind.name,
      };

  /// Ném [AdminCloudCallException] nếu HTTP 4xx/5xx hoặc lỗi kết nối.
  Map<String, dynamic> requireSuccessData() {
    if (!isSuccess) {
      throw AdminCloudCallException(
        statusCode: statusCode,
        kind: errorKind == AdminCloudErrorKind.none
            ? AdminCloudErrorKind.unknown
            : errorKind,
        message: error?.isNotEmpty == true
            ? error!
            : 'Yêu cầu tới máy chủ thất bại (HTTP $statusCode).',
        validationErrors: validationErrors,
      );
    }
    return data ?? <String, dynamic>{};
  }
}

AdminCloudErrorKind classifyAdminHttpStatus(int statusCode, {String? serverCode}) {
  if (statusCode >= 200 && statusCode < 300) {
    return AdminCloudErrorKind.none;
  }
  switch (statusCode) {
    case 401:
      return AdminCloudErrorKind.unauthenticated;
    case 403:
      return AdminCloudErrorKind.forbidden;
    case 400:
    case 409:
    case 422:
      return AdminCloudErrorKind.validation;
    case 404:
      return AdminCloudErrorKind.notFound;
    case 429:
      return AdminCloudErrorKind.rateLimited;
    default:
      if (statusCode >= 500) return AdminCloudErrorKind.server;
      if (serverCode == 'UNAUTHENTICATED') {
        return AdminCloudErrorKind.unauthenticated;
      }
      if (serverCode == 'PERMISSION_DENIED') {
        return AdminCloudErrorKind.forbidden;
      }
      return AdminCloudErrorKind.unknown;
  }
}

/// Gửi HTTP request (GET/POST) tới Firebase Cloud Functions HTTP endpoint,
/// hoạt động trên cả Flutter Web (Chrome), Emulator và VM test ([http.Client] injection).
/// Không bao giờ nuốt lỗi HTTP 4xx/5xx hay trả về null giả thành công.
Future<AdminCloudResponse> sendAdminCloudRequest({
  required String method,
  required String url,
  required String idToken,
  Map<String, dynamic>? body,
  Map<String, String>? queryParameters,
  http.Client? client,
  Duration timeout = const Duration(seconds: 25),
}) async {
  final http.Client effectiveClient = client ?? http.Client();
  final bool ownsClient = client == null;

  try {
    Uri uri = Uri.parse(url);
    if (queryParameters != null && queryParameters.isNotEmpty) {
      uri = uri.replace(
        queryParameters: <String, String>{
          ...uri.queryParameters,
          ...queryParameters,
        },
      );
    }

    final headers = <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer $idToken',
      if (method.toUpperCase() != 'GET') 'Content-Type': 'application/json',
    };

    late final http.Response response;
    final normalizedMethod = method.toUpperCase();
    if (normalizedMethod == 'GET') {
      response = await effectiveClient.get(uri, headers: headers).timeout(timeout);
    } else if (normalizedMethod == 'POST') {
      response = await effectiveClient
          .post(
            uri,
            headers: headers,
            body: jsonEncode(body ?? const <String, dynamic>{}),
          )
          .timeout(timeout);
    } else {
      throw ArgumentError('Unsupported HTTP method: $method');
    }

    Map<String, dynamic>? parsedBody;
    final rawText = response.body.trim();
    if (rawText.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawText);
        if (decoded is Map<String, dynamic>) {
          parsedBody = decoded;
        } else if (decoded is Map) {
          parsedBody = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        parsedBody = <String, dynamic>{'rawBody': rawText};
      }
    }

    final Map<String, dynamic>? dataPayload =
        parsedBody != null && parsedBody['data'] is Map
            ? Map<String, dynamic>.from(parsedBody['data'] as Map)
            : parsedBody;

    final validationErrors = <String>{
      if (parsedBody != null && parsedBody['validationErrors'] is List)
        ...(parsedBody['validationErrors'] as List)
            .map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty),
      if (parsedBody != null && parsedBody['details'] is List)
        ...(parsedBody['details'] as List)
            .map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty),
    }.toList();

    final String? rawError = parsedBody?['error']?.toString().trim();
    final String? serverCode = parsedBody?['code']?.toString().trim();

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (parsedBody != null && parsedBody['success'] == false) {
        return AdminCloudResponse(
          statusCode: response.statusCode,
          data: dataPayload,
          error: rawError?.isNotEmpty == true
              ? rawError
              : 'Thao tác phía máy chủ trả về trạng thái thất bại.',
          validationErrors: validationErrors,
          errorKind: AdminCloudErrorKind.validation,
        );
      }
      return AdminCloudResponse(
        statusCode: response.statusCode,
        data: dataPayload ?? <String, dynamic>{'success': true},
        validationErrors: validationErrors,
        errorKind: AdminCloudErrorKind.none,
      );
    }

    final kind = classifyAdminHttpStatus(
      response.statusCode,
      serverCode: serverCode,
    );
    final fallbackError = switch (kind) {
      AdminCloudErrorKind.unauthenticated =>
        'Phiên đăng nhập không hợp lệ hoặc đã hết hạn (HTTP 401).',
      AdminCloudErrorKind.forbidden =>
        'Bạn không có quyền Quản trị viên để thực hiện thao tác này (HTTP 403).',
      AdminCloudErrorKind.validation =>
        'Dữ liệu gửi lên không hợp lệ (HTTP ${response.statusCode}).',
      AdminCloudErrorKind.notFound =>
        'Không tìm thấy tài nguyên hoặc endpoint (HTTP 404).',
      AdminCloudErrorKind.rateLimited =>
        'Thao tác quá nhanh, vui lòng thử lại sau ít phút (HTTP 429).',
      AdminCloudErrorKind.server =>
        'Máy chủ xử lý gặp sự cố (HTTP ${response.statusCode}).',
      _ => 'Yêu cầu thất bại (HTTP ${response.statusCode}).',
    };

    return AdminCloudResponse(
      statusCode: response.statusCode,
      data: dataPayload,
      error: rawError?.isNotEmpty == true ? rawError : fallbackError,
      validationErrors: validationErrors,
      errorKind: kind,
    );
  } on TimeoutException {
    return const AdminCloudResponse(
      statusCode: 0,
      error: 'Kết nối tới Cloud Functions bị quá thời gian chờ (Timeout).',
      errorKind: AdminCloudErrorKind.timeout,
    );
  } on http.ClientException catch (e) {
    return AdminCloudResponse(
      statusCode: 0,
      error: 'Lỗi kết nối mạng tới Cloud Functions: ${e.message}',
      errorKind: AdminCloudErrorKind.network,
    );
  } catch (e) {
    return AdminCloudResponse(
      statusCode: 0,
      error: 'Không thể kết nối tới Cloud Functions: $e',
      errorKind: AdminCloudErrorKind.network,
    );
  } finally {
    if (ownsClient) {
      effectiveClient.close();
    }
  }
}

/// Helper POST tương thích cho Admin endpoints; luôn ném [AdminCloudCallException] nếu lỗi 4xx/5xx/mạng.
Future<AdminCloudResponse> postAdminCloudEndpoint({
  required String url,
  required String idToken,
  required Map<String, dynamic> body,
  http.Client? client,
  Duration timeout = const Duration(seconds: 25),
}) {
  return sendAdminCloudRequest(
    method: 'POST',
    url: url,
    idToken: idToken,
    body: body,
    client: client,
    timeout: timeout,
  );
}

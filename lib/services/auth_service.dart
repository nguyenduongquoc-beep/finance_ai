import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../l10n/app_localizations.dart';
import 'firestore_service.dart';

/// Ngoại lệ phát sinh khi người dùng chủ động hủy bước xác thực lại
/// (ví dụ bấm Hủy trên hộp thoại chọn tài khoản Google trước khi xóa tài khoản).
class ReauthCancelledException implements Exception {
  final String code;
  final String message;

  const ReauthCancelledException({
    this.code = 'reauth-cancelled',
    this.message = 'Re-authentication was cancelled by the user.',
  });

  @override
  String toString() => 'ReauthCancelledException($code): $message';
}

/// ============================================================
/// AUTH SERVICE
/// Xử lý đăng ký / đăng nhập qua Firebase Authentication
/// Hỗ trợ: Email/Password, Google Sign-In & Tự xóa tài khoản sạch dữ liệu (Spark)
/// ============================================================
class AuthService {
  final FirebaseAuth? _customAuth;
  final FirestoreService? _customFirestoreService;
  GoogleSignIn? _googleSignIn;

  AuthService({
    FirebaseAuth? firebaseAuth,
    FirestoreService? firestoreService,
    GoogleSignIn? googleSignIn,
  })  : _customAuth = firebaseAuth,
        _customFirestoreService = firestoreService,
        _googleSignIn = googleSignIn;

  FirebaseAuth get _auth => _customAuth ?? FirebaseAuth.instance;
  FirestoreService get _firestore =>
      _customFirestoreService ?? FirestoreService();

  /// Lazy-init để tránh crash trên Web khi chưa có clientId
  GoogleSignIn get _getGoogleSignIn => _googleSignIn ??= GoogleSignIn();

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Kiểm tra xem tài khoản có phương thức xác thực bằng email/mật khẩu hay không
  bool get isEmailPasswordUser {
    final user = _auth.currentUser;
    if (user == null) return false;
    return user.providerData.any((p) => p.providerId == 'password');
  }

  /// Kiểm tra xem tài khoản có đăng nhập bằng Google hay không
  bool get isGoogleUser {
    final user = _auth.currentUser;
    if (user == null) return false;
    return user.providerData.any((p) => p.providerId == 'google.com');
  }

  /// Mã phương thức đăng nhập chuẩn lưu lên `users/{uid}.authProvider` (phi tài chính)
  String get authProviderCode {
    if (isGoogleUser && isEmailPasswordUser) return 'google+password';
    if (isGoogleUser) return 'google';
    return 'password';
  }

  /// Nhãn hiển thị phương thức đăng nhập chính
  String get authProviderLabel {
    if (isGoogleUser && !isEmailPasswordUser) return 'Google';
    if (isEmailPasswordUser && !isGoogleUser) {
      return AppLocalizations.tr('auth_provider_email_pw');
    }
    if (isGoogleUser && isEmailPasswordUser) {
      return AppLocalizations.tr('auth_provider_google_email');
    }
    return 'Email';
  }

  /// Đăng ký bằng Email/Password
  Future<UserCredential> registerWithEmail({
    required String email,
    required String password,
    required String name,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    await credential.user?.updateDisplayName(name);
    return credential;
  }

  /// Đăng nhập bằng Email/Password
  Future<UserCredential> loginWithEmail({
    required String email,
    required String password,
  }) async {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  /// Đăng nhập bằng Google
  Future<UserCredential?> loginWithGoogle() async {
    final googleUser = await _getGoogleSignIn.signIn();
    if (googleUser == null) return null; // Người dùng hủy đăng nhập

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    return _auth.signInWithCredential(credential);
  }

  /// Gửi email đặt lại mật khẩu
  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  /// Đổi mật khẩu — yêu cầu xác thực lại (re-authenticate) trước khi đổi,
  /// theo đúng yêu cầu bảo mật của Firebase Auth.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw Exception(AppLocalizations.tr('auth_err_not_signed_in'));
    }
    final credential = EmailAuthProvider.credential(
      email: user.email!,
      password: currentPassword,
    );
    await user.reauthenticateWithCredential(credential);
    await user.updatePassword(newPassword);
  }

  /// Đăng xuất
  Future<void> signOut() async {
    try {
      await _getGoogleSignIn.signOut();
    } catch (_) {}
    await _auth.signOut();
  }

  /// Quy trình User tự Xóa tài khoản sạch dữ liệu ngay trên Mobile (100% thuần Firebase Spark):
  /// 1. Xác thực lại (re-authenticate) trước khi xóa dữ liệu để tránh trường hợp xóa dở dang rồi bị `requires-recent-login`.
  /// 2. Dùng quyền chính chủ xóa sạch theo batch (`<= 400` writes/batch) toàn bộ dữ liệu Firestore
  ///    (9 top-level collections + 4 subcollections dưới `users/{uid}` + document `users/{uid}`; giữ nguyên `support_tickets`).
  /// 3. Cuối cùng gọi `user.delete()` trên Firebase Authentication và đăng xuất Google (nếu có).
  Future<int> deleteCurrentUser({
    String? currentPassword,
    FirestoreService? firestoreService,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception(AppLocalizations.tr('auth_err_not_signed_in'));
    }

    final hasPassword = user.providerData.any((p) => p.providerId == 'password');
    final hasGoogle =
        user.providerData.any((p) => p.providerId == 'google.com');

    // Bước 1: Bắt buộc Re-authenticate thành công hoàn toàn trước khi đụng vào Firestore.
    bool reauthenticated = false;
    if (hasPassword && currentPassword != null && currentPassword.isNotEmpty) {
      if (user.email == null || user.email!.trim().isEmpty) {
        throw Exception(AppLocalizations.tr('auth_err_not_signed_in'));
      }
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);
      reauthenticated = true;
    } else if (hasGoogle) {
      final googleUser = await _getGoogleSignIn.signInSilently() ??
          await _getGoogleSignIn.signIn();
      if (googleUser == null) {
        throw const ReauthCancelledException();
      }
      final googleAuth = await googleUser.authentication;
      final hasIdToken =
          googleAuth.idToken != null && googleAuth.idToken!.isNotEmpty;
      final hasAccessToken =
          googleAuth.accessToken != null && googleAuth.accessToken!.isNotEmpty;
      if (!hasIdToken && !hasAccessToken) {
        throw const ReauthCancelledException(
          code: 'reauth-missing-token',
          message: 'Google authentication token is missing.',
        );
      }
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await user.reauthenticateWithCredential(credential);
      reauthenticated = true;
    } else if (hasPassword) {
      throw FirebaseAuthException(
        code: 'missing-password',
        message: AppLocalizations.tr('sec_del_err_pwd_required'),
      );
    }

    if (!reauthenticated) {
      throw FirebaseAuthException(
        code: 'requires-recent-login',
        message: AppLocalizations.tr('sec_del_err_recent_login'),
      );
    }

    // Bước 2: Dùng quyền chính chủ dọn sạch toàn bộ dữ liệu Firestore theo batch
    final fs = firestoreService ?? _firestore;
    final deletedCount = await fs.deleteAllUserDataForSelfDelete(user.uid);

    // Bước 3: Xóa tài khoản khỏi Firebase Authentication
    await user.delete();
    try {
      await _getGoogleSignIn.signOut();
    } catch (_) {}

    return deletedCount;
  }

  /// Helper tách biệt có thể kiểm thử trực tiếp trình tự: Re-auth -> Xóa batch Firestore -> Xóa Auth.
  Future<int> executeSelfDeleteFlow({
    required String uid,
    required Future<void> Function() reauthenticate,
    required Future<void> Function() deleteAuthAccount,
    FirestoreService? firestoreService,
  }) async {
    await reauthenticate();
    final fs = firestoreService ?? _firestore;
    final deletedCount = await fs.deleteAllUserDataForSelfDelete(uid);
    await deleteAuthAccount();
    return deletedCount;
  }
}

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// ============================================================
/// AUTH SERVICE
/// Xử lý đăng ký / đăng nhập qua Firebase Authentication
/// Hỗ trợ: Email/Password, Google Sign-In
/// ============================================================
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  GoogleSignIn? _googleSignIn;

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

  /// Nhãn hiển thị phương thức đăng nhập chính
  String get authProviderLabel {
    if (isGoogleUser && !isEmailPasswordUser) return 'Google';
    if (isEmailPasswordUser && !isGoogleUser) return 'Email & Mật khẩu';
    if (isGoogleUser && isEmailPasswordUser) return 'Google + Email/Mật khẩu';
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
      throw Exception('Người dùng chưa đăng nhập hoặc không có email');
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
    await _getGoogleSignIn.signOut();
    await _auth.signOut();
  }
}

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:finance_ai_app/l10n/app_localizations.dart';
import 'package:finance_ai_app/models/category_model.dart';
import 'package:finance_ai_app/models/saving_goal_model.dart';
import 'package:finance_ai_app/models/transaction_model.dart';
import 'package:finance_ai_app/models/user_model.dart';
import 'package:finance_ai_app/models/wallet_model.dart';
import 'package:finance_ai_app/screens/account_security_screen.dart';
import 'package:finance_ai_app/screens/auth/login_screen.dart';
import 'package:finance_ai_app/screens/auth/onboarding_screen.dart';
import 'package:finance_ai_app/screens/auth/register_screen.dart';
import 'package:finance_ai_app/screens/auth/splash_screen.dart';
import 'package:finance_ai_app/screens/home/transaction_list_screen.dart';
import 'package:finance_ai_app/services/auth_service.dart';
import 'package:finance_ai_app/services/financial_export_service.dart';
import 'package:finance_ai_app/services/firestore_service.dart';
import 'package:finance_ai_app/services/language_controller.dart';

// ============================================================
// LIGHTWEIGHT TEST FAKES (Zero platform channel dependency)
// ============================================================

class _FakeUserInfo implements UserInfo {
  @override
  final String providerId;

  _FakeUserInfo(this.providerId);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeUserCredential implements UserCredential {
  @override
  final User? user;

  _FakeUserCredential(this.user);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeUser implements User {
  @override
  final String uid;
  @override
  final String? email;
  @override
  final String? displayName;
  @override
  final bool emailVerified;
  @override
  final List<UserInfo> providerData;

  final Future<void> Function(AuthCredential credential)? onReauth;
  int reauthCallCount = 0;
  int deleteCallCount = 0;
  AuthCredential? lastCredential;

  _FakeUser({
    required this.uid,
    required this.email,
    this.displayName = 'Test User',
    this.emailVerified = true,
    required this.providerData,
    this.onReauth,
  });

  @override
  Future<UserCredential> reauthenticateWithCredential(
      AuthCredential credential) async {
    reauthCallCount++;
    lastCredential = credential;
    if (onReauth != null) {
      await onReauth!(credential);
    }
    return _FakeUserCredential(this);
  }

  @override
  Future<void> delete() async {
    deleteCallCount++;
  }

  @override
  Future<void> updateDisplayName(String? displayName) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeFirebaseAuth implements FirebaseAuth {
  final User? _currentUser;

  _FakeFirebaseAuth([this._currentUser]);

  @override
  User? get currentUser => _currentUser;

  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    return _FakeUserCredential(_currentUser);
  }

  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    return _FakeUserCredential(_currentUser);
  }

  @override
  Future<void> signOut() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeGoogleSignInAuthentication implements GoogleSignInAuthentication {
  @override
  final String? accessToken;
  @override
  final String? idToken;

  _FakeGoogleSignInAuthentication({this.accessToken, this.idToken});

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeGoogleSignInAccount implements GoogleSignInAccount {
  final GoogleSignInAuthentication _auth;

  _FakeGoogleSignInAccount(this._auth);

  @override
  Future<GoogleSignInAuthentication> get authentication async => _auth;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeGoogleSignIn implements GoogleSignIn {
  final GoogleSignInAccount? silentResult;
  final GoogleSignInAccount? interactiveResult;
  int signInSilentlyCalls = 0;
  int signInCalls = 0;
  int signOutCalls = 0;

  _FakeGoogleSignIn({this.silentResult, this.interactiveResult});

  @override
  Future<GoogleSignInAccount?> signInSilently({
    bool suppressErrors = true,
    bool reAuthenticate = false,
  }) async {
    signInSilentlyCalls++;
    return silentResult;
  }

  @override
  Future<GoogleSignInAccount?> signIn() async {
    signInCalls++;
    return interactiveResult;
  }

  @override
  Future<GoogleSignInAccount?> signOut() async {
    signOutCalls++;
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _CapturingExportService extends FinancialExportService {
  List<AppTransaction>? lastExportedTransactions;
  int exportCallCount = 0;
  int shareCallCount = 0;

  @override
  Future<File> exportTransactionsCsv({
    required List<AppTransaction> transactions,
    required List<Category> categories,
    required List<Wallet> wallets,
    required List<SavingGoal> savingGoals,
    required String filenamePrefix,
    Directory? outputDir,
  }) async {
    exportCallCount++;
    lastExportedTransactions = List<AppTransaction>.from(transactions);
    return File('$filenamePrefix.csv');
  }

  @override
  Future<void> shareFile(String filePath,
      {String? text, String? subject}) async {
    shareCallCount++;
  }
}

class _TrackingSplashFirestoreService extends FirestoreService {
  final bool throwOnProfile;
  int processDueCalls = 0;
  int syncRecurringCalls = 0;

  _TrackingSplashFirestoreService({
    required super.firestore,
    this.throwOnProfile = false,
  });

  @override
  Future<AppUser?> getUserProfile(
    String uid, {
    bool includePrivateFinancial = true,
  }) async {
    if (throwOnProfile) {
      throw Exception('Simulated offline error');
    }
    return super.getUserProfile(
      uid,
      includePrivateFinancial: includePrivateFinancial,
    );
  }

  @override
  Future<Map<String, dynamic>> processDueRecurringTransactions(
    String userId, {
    DateTime? referenceDate,
  }) async {
    processDueCalls++;
    return {'processed': 0, 'skippedInsufficientFunds': 0};
  }

  @override
  Future<void> syncRecurringNotifications(String userId) async {
    syncRecurringCalls++;
  }
}

class _CancellingDeleteAuthService extends AuthService {
  final User fakeUser;
  int deleteCalls = 0;

  _CancellingDeleteAuthService(this.fakeUser)
      : super(firebaseAuth: _FakeFirebaseAuth(fakeUser));

  @override
  Future<int> deleteCurrentUser({
    String? currentPassword,
    FirestoreService? firestoreService,
  }) async {
    deleteCalls++;
    throw const ReauthCancelledException();
  }
}

Widget _wrapLocalizedApp(Widget child, {Locale locale = const Locale('vi', 'VN')}) {
  return MaterialApp(
    key: UniqueKey(),
    locale: locale,
    supportedLocales: LanguageController.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: child,
  );
}

Future<void> _seedUserFinancialData(
  FakeFirebaseFirestore db,
  String uid,
) async {
  await db.collection('users').doc(uid).set({
    'name': 'User Test',
    'email': 'user@test.com',
    'role': 'user',
    'status': 'active',
    'createdAt': DateTime(2026, 1, 1).toIso8601String(),
  });
  await db
      .collection('users')
      .doc(uid)
      .collection('private')
      .doc('financial_profile')
      .set({'monthlyIncome': 20000000});
  await db.collection('wallets').doc('w_1').set({
    'userId': uid,
    'walletName': 'Tiền mặt',
    'balance': 1000000,
    'initialBalance': 1000000,
    'type': 'cash',
    'isActive': true,
    'createdAt': DateTime(2026, 1, 1).toIso8601String(),
  });
  await db.collection('transactions').doc('tx_1').set({
    'userId': uid,
    'walletId': 'w_1',
    'categoryId': 'cat_1',
    'amount': 50000,
    'type': 'expense',
    'note': 'Cà phê',
    'date': DateTime(2026, 11, 10).toIso8601String(),
  });
  await db.collection('support_tickets').doc('sup_1').set({
    'userId': uid,
    'title': 'Keep ticket',
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LanguageController.setLanguage('vi');
  });

  // =========================================================================
  // 1. CRITICAL BUG: RE-AUTH GUARD BEFORE SELF-DELETE
  // =========================================================================
  group('1. Critical Fix — AuthService.deleteCurrentUser Re-auth Guard', () {
    test(
        '1.1. Hủy chọn tài khoản Google (googleUser == null) -> ném ReauthCancelledException & KHÔNG xóa Firestore',
        () async {
      const uid = 'u_google_cancel';
      final fakeDb = FakeFirebaseFirestore();
      await _seedUserFinancialData(fakeDb, uid);
      final fs = FirestoreService(firestore: fakeDb);

      final fakeUser = _FakeUser(
        uid: uid,
        email: 'google@test.com',
        providerData: [_FakeUserInfo('google.com')],
      );
      final fakeGoogle = _FakeGoogleSignIn(
        silentResult: null,
        interactiveResult: null, // User pressed Cancel
      );
      final authService = AuthService(
        firebaseAuth: _FakeFirebaseAuth(fakeUser),
        firestoreService: fs,
        googleSignIn: fakeGoogle,
      );

      await expectLater(
        () => authService.deleteCurrentUser(),
        throwsA(isA<ReauthCancelledException>()
            .having((e) => e.code, 'code', 'reauth-cancelled')),
      );

      // Tuyệt đối không xóa dữ liệu Firestore hay tài khoản Auth
      expect((await fakeDb.collection('users').doc(uid).get()).exists, isTrue);
      expect((await fakeDb.collection('wallets').doc('w_1').get()).exists,
          isTrue);
      expect(
          (await fakeDb.collection('transactions').doc('tx_1').get()).exists,
          isTrue);
      expect(fakeUser.deleteCallCount, 0);
      expect(fakeGoogle.signInSilentlyCalls, 1);
      expect(fakeGoogle.signInCalls, 1);
    });

    test(
        '1.2. Google re-auth thiếu cả idToken và accessToken -> ném ReauthCancelledException & KHÔNG xóa Firestore',
        () async {
      const uid = 'u_google_no_token';
      final fakeDb = FakeFirebaseFirestore();
      await _seedUserFinancialData(fakeDb, uid);
      final fs = FirestoreService(firestore: fakeDb);

      final fakeUser = _FakeUser(
        uid: uid,
        email: 'google@test.com',
        providerData: [_FakeUserInfo('google.com')],
      );
      final fakeGoogle = _FakeGoogleSignIn(
        interactiveResult: _FakeGoogleSignInAccount(
          _FakeGoogleSignInAuthentication(accessToken: null, idToken: null),
        ),
      );
      final authService = AuthService(
        firebaseAuth: _FakeFirebaseAuth(fakeUser),
        firestoreService: fs,
        googleSignIn: fakeGoogle,
      );

      await expectLater(
        () => authService.deleteCurrentUser(),
        throwsA(isA<ReauthCancelledException>()),
      );

      expect((await fakeDb.collection('users').doc(uid).get()).exists, isTrue);
      expect((await fakeDb.collection('wallets').doc('w_1').get()).exists,
          isTrue);
      expect(fakeUser.deleteCallCount, 0);
    });

    test(
        '1.3. Tài khoản liên kết (google+password) không truyền mật khẩu -> fallback Google re-auth & hủy không xóa dữ liệu',
        () async {
      const uid = 'u_linked_cancel';
      final fakeDb = FakeFirebaseFirestore();
      await _seedUserFinancialData(fakeDb, uid);
      final fs = FirestoreService(firestore: fakeDb);

      final fakeUser = _FakeUser(
        uid: uid,
        email: 'linked@test.com',
        providerData: [
          _FakeUserInfo('password'),
          _FakeUserInfo('google.com'),
        ],
      );
      final fakeGoogle = _FakeGoogleSignIn(
        silentResult: null,
        interactiveResult: null,
      );
      final authService = AuthService(
        firebaseAuth: _FakeFirebaseAuth(fakeUser),
        firestoreService: fs,
        googleSignIn: fakeGoogle,
      );

      await expectLater(
        () => authService.deleteCurrentUser(currentPassword: ''),
        throwsA(isA<ReauthCancelledException>()),
      );

      expect((await fakeDb.collection('wallets').doc('w_1').get()).exists,
          isTrue);
      expect(fakeUser.deleteCallCount, 0);
      expect(fakeGoogle.signInCalls, 1);
    });

    test(
        '1.4. Tài khoản chỉ có Password mà thiếu currentPassword -> ném missing-password & KHÔNG xóa Firestore',
        () async {
      const uid = 'u_pwd_missing';
      final fakeDb = FakeFirebaseFirestore();
      await _seedUserFinancialData(fakeDb, uid);
      final fs = FirestoreService(firestore: fakeDb);

      final fakeUser = _FakeUser(
        uid: uid,
        email: 'pwd@test.com',
        providerData: [_FakeUserInfo('password')],
      );
      final authService = AuthService(
        firebaseAuth: _FakeFirebaseAuth(fakeUser),
        firestoreService: fs,
      );

      await expectLater(
        () => authService.deleteCurrentUser(currentPassword: ''),
        throwsA(isA<FirebaseAuthException>()
            .having((e) => e.code, 'code', 'missing-password')),
      );

      expect((await fakeDb.collection('users').doc(uid).get()).exists, isTrue);
      expect((await fakeDb.collection('wallets').doc('w_1').get()).exists,
          isTrue);
      expect(fakeUser.deleteCallCount, 0);
    });

    test(
        '1.5. Re-auth Google thành công -> xóa sạch dữ liệu tài chính (giữ support_tickets) và xóa Auth',
        () async {
      const uid = 'u_google_ok';
      final fakeDb = FakeFirebaseFirestore();
      await _seedUserFinancialData(fakeDb, uid);
      final fs = FirestoreService(firestore: fakeDb);

      final fakeUser = _FakeUser(
        uid: uid,
        email: 'google@test.com',
        providerData: [_FakeUserInfo('google.com')],
      );
      final fakeGoogle = _FakeGoogleSignIn(
        interactiveResult: _FakeGoogleSignInAccount(
          _FakeGoogleSignInAuthentication(
            accessToken: 'acc_tok',
            idToken: 'id_tok',
          ),
        ),
      );
      final authService = AuthService(
        firebaseAuth: _FakeFirebaseAuth(fakeUser),
        firestoreService: fs,
        googleSignIn: fakeGoogle,
      );

      final deleted = await authService.deleteCurrentUser();
      expect(deleted, greaterThanOrEqualTo(4));
      expect(fakeUser.reauthCallCount, 1);
      expect(fakeUser.deleteCallCount, 1);
      expect((await fakeDb.collection('users').doc(uid).get()).exists, isFalse);
      expect((await fakeDb.collection('wallets').doc('w_1').get()).exists,
          isFalse);
      expect(
          (await fakeDb.collection('support_tickets').doc('sup_1').get())
              .exists,
          isTrue);
    });

    test(
        '1.6. Mật khẩu hiện tại sai (wrong-password khi re-auth) -> dừng ngay & KHÔNG xóa Firestore',
        () async {
      const uid = 'u_wrong_pwd';
      final fakeDb = FakeFirebaseFirestore();
      await _seedUserFinancialData(fakeDb, uid);
      final fs = FirestoreService(firestore: fakeDb);

      final fakeUser = _FakeUser(
        uid: uid,
        email: 'pwd@test.com',
        providerData: [_FakeUserInfo('password')],
        onReauth: (_) async {
          throw FirebaseAuthException(code: 'wrong-password');
        },
      );
      final authService = AuthService(
        firebaseAuth: _FakeFirebaseAuth(fakeUser),
        firestoreService: fs,
      );

      await expectLater(
        () => authService.deleteCurrentUser(currentPassword: 'bad-pass'),
        throwsA(isA<FirebaseAuthException>()
            .having((e) => e.code, 'code', 'wrong-password')),
      );

      expect((await fakeDb.collection('users').doc(uid).get()).exists, isTrue);
      expect((await fakeDb.collection('wallets').doc('w_1').get()).exists,
          isTrue);
      expect(fakeUser.deleteCallCount, 0);
    });
  });

  // =========================================================================
  // 2. FILTERED CSV EXPORT IN TRANSACTION LIST SCREEN
  // =========================================================================
  group('2. Filtered CSV Export in TransactionListScreen', () {
    testWidgets(
        '2.1. Chỉ xuất đúng tập filteredTransactions đang lọc và cảnh báo khi danh sách lọc rỗng',
        (tester) async {
      const uid = 'u_csv';
      final fakeDb = FakeFirebaseFirestore();
      await fakeDb.collection('wallets').doc('w_cash').set({
        'userId': uid,
        'walletName': 'Tiền mặt',
        'balance': 500000,
        'type': 'cash',
        'isActive': true,
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
      });
      await fakeDb.collection('categories').doc('c_food').set({
        'userId': uid,
        'name': 'Ăn uống',
        'type': 'expense',
        'icon': 'restaurant',
        'color': 0xFFEF4444,
      });
      await fakeDb.collection('categories').doc('c_sal').set({
        'userId': uid,
        'name': 'Lương',
        'type': 'income',
        'icon': 'work',
        'color': 0xFF10B981,
      });
      await fakeDb.collection('transactions').doc('tx_coffee').set({
        'userId': uid,
        'walletId': 'w_cash',
        'categoryId': 'c_food',
        'amount': 45000,
        'type': 'expense',
        'note': 'Cà phê Highland sáng',
        'date': DateTime(2026, 11, 20).toIso8601String(),
      });
      await fakeDb.collection('transactions').doc('tx_salary').set({
        'userId': uid,
        'walletId': 'w_cash',
        'categoryId': 'c_sal',
        'amount': 15000000,
        'type': 'income',
        'note': 'Nhận lương tháng 11',
        'date': DateTime(2026, 11, 19).toIso8601String(),
      });

      final fs = FirestoreService(firestore: fakeDb);
      final exportSvc = _CapturingExportService();

      await tester.pumpWidget(
        _wrapLocalizedApp(
          TransactionListScreen(
            firestoreService: fs,
            exportService: exportSvc,
            userIdOverride: uid,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Nhập từ khóa lọc chỉ khớp 1 giao dịch cà phê
      await tester.enterText(find.byType(TextField).first, 'highland');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('tx_list_export_csv_btn')));
      await tester.pumpAndSettle();

      expect(exportSvc.exportCallCount, 1);
      expect(exportSvc.lastExportedTransactions, isNotNull);
      expect(exportSvc.lastExportedTransactions!.length, 1);
      expect(exportSvc.lastExportedTransactions!.first.transactionId,
          'tx_coffee');

      // Lọc ra danh sách rỗng -> không xuất file và hiện snackbar cảnh báo
      await tester.enterText(
          find.byType(TextField).first, 'khong_khop_bat_ky_giao_dich_nao');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('tx_list_export_csv_btn')));
      await tester.pumpAndSettle();

      expect(exportSvc.exportCallCount, 1);
      expect(
        find.text(AppLocalizations.tr('tx_list_export_empty')),
        findsOneWidget,
      );
    });
  });

  // =========================================================================
  // 3. ACCOUNT SECURITY: EN LOCALIZATION, EMAIL VERIFIED & RE-AUTH CANCEL UX
  // =========================================================================
  group('3. AccountSecurityScreen Localization, Verification Badge & Cancel UX',
      () {
    testWidgets(
        '3.1. Chuyển sang locale EN không còn chuỗi tiếng Việt & hiện đúng Email not verified khi emailVerified == false',
        (tester) async {
      await LanguageController.setLanguage('en');
      final unverifiedEmailUser = _FakeUser(
        uid: 'u_unverified',
        email: 'demo@finance.app',
        emailVerified: false,
        providerData: [_FakeUserInfo('password')],
      );

      await tester.pumpWidget(
        _wrapLocalizedApp(
          AccountSecurityScreen(
            authService: AuthService(
              firebaseAuth: _FakeFirebaseAuth(unverifiedEmailUser),
            ),
            currentUserOverride: unverifiedEmailUser,
          ),
          locale: const Locale('en', 'US'),
        ),
      );
      await tester.pumpAndSettle();

      // Badge phải hiện "Email not verified" chứ KHÔNG phải "Verified"
      expect(find.text('Email not verified'), findsOneWidget);
      expect(find.text('Verified'), findsNothing);

      // Vùng Xóa tài khoản hoàn toàn bằng tiếng Anh
      expect(find.text('Delete account'), findsOneWidget);
      expect(find.text('Permanently delete account'), findsOneWidget);
      expect(find.text('Xóa tài khoản'), findsNothing);
      expect(find.text('Xóa vĩnh viễn tài khoản'), findsNothing);

      // Mở hộp thoại xác nhận xóa tài khoản
      await tester.ensureVisible(
          find.byKey(const ValueKey('sec_delete_account_btn')));
      await tester.tap(find.byKey(const ValueKey('sec_delete_account_btn')));
      await tester.pumpAndSettle();

      expect(find.text('Confirm account deletion'), findsOneWidget);
      expect(find.text('Delete permanently'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Xác nhận Xóa tài khoản'), findsNothing);
      expect(find.text('Xóa Vĩnh Viễn'), findsNothing);

      // Đóng hộp thoại (kiểm tra dispose controller không lỗi)
      await tester.tap(find.byKey(const ValueKey('sec_delete_dlg_cancel')));
      await tester.pumpAndSettle();
    });

    testWidgets(
        '3.2. Tài khoản Google emailVerified == true hiện Verified & hủy Google re-auth kết thúc êm ái không crash',
        (tester) async {
      await LanguageController.setLanguage('en');
      final verifiedGoogleUser = _FakeUser(
        uid: 'u_verified_g',
        email: 'google@finance.app',
        emailVerified: true,
        providerData: [_FakeUserInfo('google.com')],
      );
      final cancellingAuth = _CancellingDeleteAuthService(verifiedGoogleUser);

      await tester.pumpWidget(
        _wrapLocalizedApp(
          AccountSecurityScreen(
            authService: cancellingAuth,
            currentUserOverride: verifiedGoogleUser,
          ),
          locale: const Locale('en', 'US'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Verified'), findsOneWidget);
      expect(find.text('Email not verified'), findsNothing);

      await tester.ensureVisible(
          find.byKey(const ValueKey('sec_delete_account_btn')));
      await tester.tap(find.byKey(const ValueKey('sec_delete_account_btn')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('sec_delete_dlg_confirm')));
      await tester.pumpAndSettle();

      expect(cancellingAuth.deleteCalls, 1);
      expect(
        find.text(
            'Account deletion verification cancelled. Your data remains safe.'),
        findsOneWidget,
      );
      // Vẫn ở màn hình AccountSecurityScreen, không crash / không đá ra Login
      expect(find.byType(AccountSecurityScreen), findsOneWidget);
    });
  });

  // =========================================================================
  // 4. ONBOARDING FLAG, REMEMBER ME, EMAIL LOGIN SETUP, REGISTER STACK & SPLASH
  // =========================================================================
  group('4. Auth Flows: Onboarding, Remember Me, Email Login, Register & Splash',
      () {
    testWidgets(
        '4.1. Onboarding lưu has_seen_onboarding = true & Splash bỏ qua Onboarding ở lần mở sau',
        (tester) async {
      await tester.pumpWidget(
        _wrapLocalizedApp(
          OnboardingScreen(
            loginRouteBuilder: (_) => const Scaffold(body: Text('LOGIN_DEST')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(AppLocalizations.tr('onb_skip')));
      await tester.pumpAndSettle();

      expect(find.text('LOGIN_DEST'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(OnboardingScreen.hasSeenOnboardingKey), isTrue);

      // Lần mở app sau chưa đăng nhập: Splash đi thẳng vào LoginScreen
      await tester.pumpWidget(
        _wrapLocalizedApp(
          SplashScreen(
            initialDelay: Duration.zero,
            currentUserResolver: () => null,
            loginRouteBuilder: (_) => const Scaffold(body: Text('DIRECT_LOGIN')),
            onboardingRouteBuilder: (_) =>
                const Scaffold(body: Text('ONBOARDING_SHOWN')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('DIRECT_LOGIN'), findsOneWidget);
      expect(find.text('ONBOARDING_SHOWN'), findsNothing);
    });

    testWidgets(
        '4.2. LoginScreen bật Ghi nhớ tôi lưu email, đăng nhập Email chưa có ví -> tạo profile Zero-Knowledge & vào WalletSetupScreen',
        (tester) async {
      const uid = 'u_email_new';
      final fakeDb = FakeFirebaseFirestore();
      final fs = FirestoreService(firestore: fakeDb);
      final fakeUser = _FakeUser(
        uid: uid,
        email: 'remember@finance.app',
        displayName: 'Nguyễn Văn A',
        providerData: [_FakeUserInfo('password')],
      );
      final authService = AuthService(
        firebaseAuth: _FakeFirebaseAuth(fakeUser),
        firestoreService: fs,
      );

      await tester.pumpWidget(
        _wrapLocalizedApp(
          LoginScreen(
            authService: authService,
            firestoreService: fs,
            walletSetupRouteBuilder: (_) =>
                const Scaffold(body: Text('WALLET_SETUP_DEST')),
            homeRouteBuilder: (_) => const Scaffold(body: Text('HOME_DEST')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'remember@finance.app');
      await tester.enterText(fields.at(1), 'secret123');

      // Bật Ghi nhớ tôi
      await tester
          .tap(find.byKey(const ValueKey('login_remember_me_checkbox')));
      await tester.pumpAndSettle();

      await tester.tap(find.text(AppLocalizations.tr('auth_login_btn')));
      await tester.pumpAndSettle();

      // Đã đi sang WalletSetupScreen vì chưa có ví
      expect(find.text('WALLET_SETUP_DEST'), findsOneWidget);

      // Hồ sơ Zero-Knowledge được tạo trên users/{uid} (không có trường tài chính)
      final profileSnap = await fakeDb.collection('users').doc(uid).get();
      expect(profileSnap.exists, isTrue);
      expect(profileSnap.data()!.containsKey('monthlyIncome'), isFalse);
      expect(profileSnap.data()!.containsKey('savingGoal'), isFalse);

      // SharedPreferences chỉ lưu email
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(LoginScreen.rememberedEmailKey),
          'remember@finance.app');

      // Mở lại LoginScreen -> tự khôi phục email & trạng thái tích Ghi nhớ tôi
      await tester.pumpWidget(
        _wrapLocalizedApp(
          LoginScreen(
            authService: authService,
            firestoreService: fs,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('remember@finance.app'), findsOneWidget);
      final checkbox = tester.widget<Checkbox>(
          find.byKey(const ValueKey('login_remember_me_checkbox')));
      expect(checkbox.value, isTrue);

      // Bỏ tích Ghi nhớ tôi -> xóa email đã lưu
      await tester
          .tap(find.byKey(const ValueKey('login_remember_me_checkbox')));
      await tester.pumpAndSettle();
      expect(prefs.getString(LoginScreen.rememberedEmailKey), isNull);
    });

    testWidgets(
        '4.3. RegisterScreen dùng pushAndRemoveUntil xóa sạch LoginScreen khỏi back-stack',
        (tester) async {
      const uid = 'u_reg_stack';
      final fakeDb = FakeFirebaseFirestore();
      final fs = FirestoreService(firestore: fakeDb);
      final fakeUser = _FakeUser(
        uid: uid,
        email: 'newuser@finance.app',
        providerData: [_FakeUserInfo('password')],
      );
      final authService = AuthService(
        firebaseAuth: _FakeFirebaseAuth(fakeUser),
        firestoreService: fs,
      );

      bool? canPopAtDestination;

      await tester.pumpWidget(
        _wrapLocalizedApp(
          Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  Navigator.of(ctx).push(
                    MaterialPageRoute(
                      builder: (_) => RegisterScreen(
                        authService: authService,
                        firestoreService: fs,
                        walletSetupRouteBuilder: (destCtx) {
                          canPopAtDestination = Navigator.of(destCtx).canPop();
                          return const Scaffold(
                            body: Text('WALLET_AFTER_REG'),
                          );
                        },
                      ),
                    ),
                  );
                },
                child: const Text('OPEN_REGISTER'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('OPEN_REGISTER'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Trần Văn B');
      await tester.enterText(fields.at(1), 'newuser@finance.app');
      await tester.enterText(fields.at(2), 'secret123');
      await tester.enterText(fields.at(3), 'secret123');

      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      final registerBtn = find.text(AppLocalizations.tr('auth_register_btn'));
      await tester.ensureVisible(registerBtn);
      await tester.tap(registerBtn);
      await tester.pumpAndSettle();

      expect(find.text('WALLET_AFTER_REG'), findsOneWidget);
      expect(canPopAtDestination, isFalse);
    });

    testWidgets(
        '4.4. SplashScreen không treo khi lỗi Firestore và chỉ gọi syncRecurringNotifications (không chạy lặp processDue)',
        (tester) async {
      const uid = 'u_splash';
      final fakeDb = FakeFirebaseFirestore();
      await _seedUserFinancialData(fakeDb, uid);
      final fakeUser = _FakeUser(
        uid: uid,
        email: 'splash@test.com',
        providerData: [_FakeUserInfo('password')],
      );

      // Case A: Online bình thường -> gọi syncRecurringNotifications 1 lần, processDue 0 lần trực tiếp
      final normalFs = _TrackingSplashFirestoreService(firestore: fakeDb);
      await tester.pumpWidget(
        _wrapLocalizedApp(
          SplashScreen(
            initialDelay: Duration.zero,
            currentUserResolver: () => fakeUser,
            firestoreService: normalFs,
            authService: AuthService(firebaseAuth: _FakeFirebaseAuth(fakeUser)),
            homeRouteBuilder: (_) => const Scaffold(body: Text('HOME_OK')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('HOME_OK'), findsOneWidget);
      expect(normalFs.syncRecurringCalls, 1);
      expect(normalFs.processDueCalls, 0);

      // Case B: Offline / lỗi Firestore -> không treo màn Splash, rơi mềm vào MainNavigation
      final offlineFs = _TrackingSplashFirestoreService(
        firestore: fakeDb,
        throwOnProfile: true,
      );
      await tester.pumpWidget(
        _wrapLocalizedApp(
          SplashScreen(
            initialDelay: Duration.zero,
            currentUserResolver: () => fakeUser,
            firestoreService: offlineFs,
            authService: AuthService(firebaseAuth: _FakeFirebaseAuth(fakeUser)),
            homeRouteBuilder: (_) =>
                const Scaffold(body: Text('HOME_OFFLINE_CACHE')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('HOME_OFFLINE_CACHE'), findsOneWidget);
    });

    test('4.5. Nhãn báo cáo ai_rep_ai_generated phản ánh đúng bản chất phân tích tự động',
        () async {
      await LanguageController.setLanguage('vi');
      expect(AppLocalizations.tr('ai_rep_ai_generated'), 'Phân tích tự động');

      await LanguageController.setLanguage('en');
      expect(AppLocalizations.tr('ai_rep_ai_generated'), 'Auto Analytics');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qurany_app/models/auth_result.dart';
import 'package:qurany_app/services/auth_api_service.dart';
import 'package:qurany_app/services/auth_service.dart';

class _FakeAuthApi extends AuthApiService {
  _FakeAuthApi({
    this.loginResult = const (
      result: AuthResult.failure(AuthFailure.invalidCredentials),
      token: null,
    ),
    this.registerResult = const (
      result: AuthResult.failure(AuthFailure.invalidCredentials),
      token: null,
    ),
    this.meProfile = const {
      'id': 'user-1',
      'email': 'student@qurany.app',
      'full_name': 'Student',
      'daily_streak': 0,
      'total_score': 0,
    },
  });

  final ({AuthResult result, String? token}) loginResult;
  final ({AuthResult result, String? token}) registerResult;
  final Map<String, dynamic> meProfile;

  int loginCalls = 0;
  int registerCalls = 0;

  @override
  Future<({AuthResult result, String? token})> login({
    required String email,
    required String password,
  }) async {
    loginCalls++;
    return loginResult;
  }

  @override
  Future<({AuthResult result, String? token})> register({
    required String fullName,
    required String email,
    required String password,
  }) async {
    registerCalls++;
    return registerResult;
  }

  @override
  Future<Map<String, dynamic>?> me({required String token}) async {
    return meProfile;
  }
}

void main() {
  test('login rejects invalid input without hitting the backend', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final api = _FakeAuthApi();
    final auth = AuthService(prefs, authApi: api);

    final result = await auth.login('student@qurany.app', '123');

    expect(result.success, isFalse);
    expect(result.failure, AuthFailure.invalidInput);
    expect(api.loginCalls, 0);
    expect(auth.isLoggedIn, isFalse);
  });

  test('login requires backend credentials and stores session on success', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final api = _FakeAuthApi(
      loginResult: (result: const AuthResult.success(), token: 'jwt-token'),
    );
    final auth = AuthService(prefs, authApi: api);

    final result = await auth.login('student@qurany.app', 'secret12');

    expect(result.success, isTrue);
    expect(api.loginCalls, 1);
    expect(auth.isLoggedIn, isTrue);
    expect(auth.isGuest, isFalse);
    expect(auth.accessToken, 'jwt-token');
    expect(auth.userEmail, 'student@qurany.app');
  });

  test('register does not fall back to guest mode on backend failure', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final api = _FakeAuthApi();
    final auth = AuthService(prefs, authApi: api);

    final result = await auth.register('Student', 'student@qurany.app', 'secret12');

    expect(result.success, isFalse);
    expect(result.failure, AuthFailure.invalidCredentials);
    expect(api.registerCalls, 1);
    expect(auth.isLoggedIn, isFalse);
    expect(auth.isGuest, isFalse);
  });
}

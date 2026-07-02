import 'package:flutter_test/flutter_test.dart';
import 'package:qurany_app/models/auth_result.dart';

void main() {
  test('success result has empty Arabic message', () {
    const result = AuthResult.success();
    expect(result.success, isTrue);
    expect(result.failure, isNull);
    expect(result.messageAr, isEmpty);
  });

  test('failure results expose Arabic messages', () {
    expect(
      const AuthResult.failure(AuthFailure.invalidCredentials).messageAr,
      contains('البريد الإلكتروني'),
    );
    expect(
      const AuthResult.failure(AuthFailure.backendUnavailable).messageAr,
      contains('docker compose'),
    );
    expect(
      const AuthResult.failure(AuthFailure.invalidInput).messageAr,
      isNotEmpty,
    );
  });
}

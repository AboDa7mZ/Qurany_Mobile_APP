enum AuthFailure {
  invalidInput,
  backendUnavailable,
  invalidCredentials,
}

class AuthResult {
  const AuthResult._({required this.success, this.failure});

  const AuthResult.success() : this._(success: true);

  const AuthResult.failure(AuthFailure failure)
      : this._(success: false, failure: failure);

  final bool success;
  final AuthFailure? failure;

  String get messageAr {
    switch (failure) {
      case AuthFailure.backendUnavailable:
        return 'تعذر الاتصال بالخادم. تأكد أن python main.py يعمل وعنوان الخادم في الإعدادات صحيح، ثم أعد المحاولة.';
      case AuthFailure.invalidCredentials:
        return 'البريد الإلكتروني أو كلمة المرور غير صحيحة.';
      case AuthFailure.invalidInput:
        return 'تحقق من البيانات المدخلة.';
      case null:
        return '';
    }
  }
}

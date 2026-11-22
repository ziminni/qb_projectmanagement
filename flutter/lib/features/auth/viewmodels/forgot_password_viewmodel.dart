import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/repositories/auth_repository.dart';

class ForgotPasswordViewModel extends ChangeNotifier with ActionRunner {
  ForgotPasswordViewModel({required AuthRepository auth}) : _auth = auth;

  final AuthRepository _auth;

  String? _sentTo;
  String? _error;

  /// The address a reset code was requested for, once sent.
  String? get sentTo => _sentTo;
  String? get error => _error;

  Future<String?> requestReset(String email) async {
    _error = null;
    final trimmed = email.trim();
    final error = await runAction(
      () => _auth.requestPasswordReset(trimmed),
    );
    _error = error;
    if (error == null) {
      _sentTo = trimmed;
    }
    notifyListeners();
    return error;
  }

  Future<bool> confirmReset({
    required String code,
    required String newPassword,
  }) async {
    final email = _sentTo;
    if (email == null) return false;
    _error = null;
    final error = await runAction(
      () => _auth.confirmPasswordReset(
        email: email,
        code: code.trim(),
        newPassword: newPassword,
      ),
    );
    _error = error;
    notifyListeners();
    return error == null;
  }

  void clear() {
    _sentTo = null;
    _error = null;
    notifyListeners();
  }
}

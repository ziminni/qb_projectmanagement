import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/repositories/auth_repository.dart';

class ForgotPasswordViewModel extends ChangeNotifier with ActionRunner {
  ForgotPasswordViewModel({required AuthRepository auth}) : _auth = auth;

  final AuthRepository _auth;

  String? _sentTo;

  /// The address a reset link was requested for, once sent.
  String? get sentTo => _sentTo;

  Future<String?> requestReset(String email) async {
    final error = await runAction(
      () => _auth.requestPasswordReset(email.trim()),
    );
    if (error == null) {
      _sentTo = email.trim();
      notifyListeners();
    }
    return error;
  }
}

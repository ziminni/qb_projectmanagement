import '../models/app_role.dart';
import '../models/user.dart';

class AuthResult {
  const AuthResult(this.user, this.roles);

  final User user;
  final List<AppRole> roles;
}

abstract interface class AuthRepository {
  /// Throws `BusinessRuleException` for a wrong email or password, or a
  /// deactivated account.
  Future<AuthResult> signIn(String email, String password);

  /// Always succeeds so the response does not reveal which emails exist.
  Future<void> requestPasswordReset(String email);

  Future<void> changePassword(
    int userId, {
    required String currentPassword,
    required String newPassword,
  });
}

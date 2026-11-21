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

  /// Verifies [password] for [email] without modifying or clearing the active
  /// session on failure. Returns true if valid, false otherwise.
  Future<bool> verifyPassword(String email, String password);

  /// Always succeeds so the response does not reveal which emails exist.
  Future<void> requestPasswordReset(String email);

  /// Admin action: replaces [userId]'s password with a temporary one and
  /// returns it so the admin can pass it on.
  Future<String> resetPassword(int userId);

  Future<void> changePassword(
    int userId, {
    required String currentPassword,
    required String newPassword,
  });
}

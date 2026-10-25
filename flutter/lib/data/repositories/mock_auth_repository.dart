import '../services/auth_rules.dart';
import '../services/business_rule_exception.dart';
import 'auth_repository.dart';
import 'mock_data.dart';
import 'user_repository.dart';

/// Checks credentials against the mock users. Every account starts with
/// [MockData.demoPassword].
class MockAuthRepository implements AuthRepository {
  MockAuthRepository({required UserRepository users}) : _users = users;

  final UserRepository _users;
  final _passwords = <int, String>{};

  String _passwordFor(int userId) =>
      _passwords[userId] ?? MockData.demoPassword;

  @override
  Future<AuthResult> signIn(String email, String password) async {
    final normalized = email.trim().toLowerCase();
    final users = await _users.getUsers();
    final matches = users.where((u) => u.email.toLowerCase() == normalized);
    final user = matches.isEmpty ? null : matches.first;
    if (user == null || _passwordFor(user.id) != password) {
      throw const BusinessRuleException('Incorrect email or password.');
    }
    if (!user.isActive) {
      throw const BusinessRuleException(
        'This account is deactivated. Contact your system admin.',
      );
    }
    final roles = await _users.getRoles(user.id);
    if (roles.isEmpty) {
      throw const BusinessRuleException(
        'This account has no role yet. Contact your system admin.',
      );
    }
    return AuthResult(user, roles);
  }

  @override
  Future<void> requestPasswordReset(String email) async {}

  @override
  Future<void> changePassword(
    int userId, {
    required String currentPassword,
    required String newPassword,
  }) async {
    if (_passwordFor(userId) != currentPassword) {
      throw const BusinessRuleException('Your current password is incorrect.');
    }
    final error = AuthRules.validateNewPassword(newPassword);
    if (error != null) throw BusinessRuleException(error);
    if (newPassword == currentPassword) {
      throw const BusinessRuleException(
        'Choose a password different from the current one.',
      );
    }
    _passwords[userId] = newPassword;
  }
}

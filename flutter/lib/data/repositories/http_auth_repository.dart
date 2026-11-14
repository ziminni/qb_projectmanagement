import '../../core/network/api_client.dart';
import '../models/user.dart';
import 'auth_repository.dart';

/// Sign-in, password reset and password change against the CPMS backend.
class HttpAuthRepository implements AuthRepository {
  HttpAuthRepository(this._client);

  final ApiClient _client;

  @override
  Future<AuthResult> signIn(String email, String password) async {
    try {
      final data = jsonObject(
        await _client.post(
          'auth/login/',
          body: {'email': email.trim().toLowerCase(), 'password': password},
        ),
      );
      await _client.storeTokens(
        access: data['access'] as String,
        refresh: data['refresh'] as String,
      );
      return AuthResult(User.fromJson(jsonObject(data['user'])), [
        for (final role in (data['roles'] as List<dynamic>? ?? const []))
          roleFrom(role),
      ]);
    } catch (_) {
      // A failed sign-in must not leave the previous session's tokens behind.
      await _client.clearTokens();
      rethrow;
    }
  }

  @override
  Future<void> requestPasswordReset(String email) async {
    // The server answers 204 whether or not the address exists.
    await _client.post(
      'auth/password-reset-request/',
      body: {'email': email.trim().toLowerCase()},
    );
  }

  @override
  Future<String> resetPassword(int userId) async {
    final data = jsonObject(
      await _client.post('users/$userId/reset-password/'),
    );
    return data['temporary_password'] as String;
  }

  @override
  Future<void> changePassword(
    int userId, {
    required String currentPassword,
    required String newPassword,
  }) async {
    // [userId] is ignored: the server changes the password of the account
    // behind the access token.
    await _client.post(
      'auth/change-password/',
      body: {'current_password': currentPassword, 'new_password': newPassword},
    );
  }
}

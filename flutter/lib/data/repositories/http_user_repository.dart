import '../../core/network/api_client.dart';
import '../models/app_role.dart';
import '../models/user.dart';
import '../models/user_role.dart';
import 'user_repository.dart';

/// Users and roles against the CPMS backend. Writes are admin-only on the
/// server; reads are scoped there too (a client can only read themself).
class HttpUserRepository implements UserRepository {
  HttpUserRepository(this._client);

  final ApiClient _client;
  String? _lastTemporaryPassword;
  bool _lastEmailSent = true;
  String? _lastEmailError;

  @override
  String? get lastTemporaryPassword => _lastTemporaryPassword;

  @override
  bool get lastEmailSent => _lastEmailSent;

  @override
  String? get lastEmailError => _lastEmailError;

  @override
  Future<List<User>> getUsers() async => [
    for (final row in await _client.getRows('users/')) User.fromJson(row),
  ];

  @override
  Future<User?> getUser(int id) async {
    final data = await _client.get('users/$id/', notFoundAsNull: true);
    return data == null ? null : User.fromJson(jsonObject(data));
  }

  @override
  Future<List<AppRole>> getRoles(int userId) async => [
    for (final row in await _client.getRows(
      'user-roles/',
      query: {'user': userId},
    ))
      roleFrom(row),
  ];

  @override
  Future<List<UserRole>> getAllUserRoles() async => [
    for (final row in await _client.getRows('user-roles/'))
      UserRole.fromJson(row),
  ];

  @override
  Future<User> saveUser(User user, List<AppRole> roles) async {
    final body = {
      'full_name': user.fullName.trim(),
      'email': user.email.trim().toLowerCase(),
      'phone': user.phone,
      'is_active': user.isActive,
      'roles': [for (final role in roles.toSet()) role.apiValue],
    };
    final data = await (user.id == 0
        ? _client.post('users/', body: body)
        : _client.patch('users/${user.id}/', body: body));
    return _saved(data);
  }

  @override
  Future<User> setActive(int userId, bool active) async => _saved(
    await _client.patch('users/$userId/', body: {'is_active': active}),
  );

  @override
  Future<List<User>> getUsersWithRole(AppRole role) async {
    final users = [
      for (final row in await _client.getRows(
        'users/',
        query: {'role': role.apiValue, 'is_active': 'true'},
      ))
        User.fromJson(row),
    ];
    // The server filters already; drop inactive rows anyway so an assignment
    // picker never offers a deactivated person.
    return [
      for (final user in users)
        if (user.isActive) user,
    ];
  }

  /// Creating answers `{user, roles, temporary_password}`, updating answers the
  /// bare user; accept both.
  User _saved(Object? data) {
    final body = jsonObject(data);
    _lastTemporaryPassword = body['temporary_password'] as String?;
    _lastEmailSent = body['email_sent'] as bool? ?? true;
    _lastEmailError = body['email_error'] as String?;
    return User.fromJson(jsonObject(body['user'] ?? body));
  }
}

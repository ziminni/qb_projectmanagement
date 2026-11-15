import '../models/app_role.dart';
import '../models/user.dart';
import '../models/user_role.dart';
import '../services/business_rule_exception.dart';
import 'mock_data.dart';
import 'user_repository.dart';

class MockUserRepository implements UserRepository {
  final _users = [...MockData.users];
  final _roles = [...MockData.userRoles];

  @override
  Future<List<User>> getUsers() async => List.unmodifiable(_users);

  @override
  Future<User?> getUser(int id) async {
    for (final u in _users) {
      if (u.id == id) return u;
    }
    return null;
  }

  @override
  Future<List<AppRole>> getRoles(int userId) async => [
    for (final r in _roles)
      if (r.userId == userId) r.role,
  ];

  @override
  Future<List<UserRole>> getAllUserRoles() async => List.unmodifiable(_roles);

  @override
  Future<List<User>> getUsersWithRole(AppRole role) async {
    final ids = {
      for (final r in _roles)
        if (r.role == role) r.userId,
    };
    return _users.where((u) => ids.contains(u.id) && u.isActive).toList();
  }

  @override
  Future<User> saveUser(User user, List<AppRole> roles) async {
    if (user.fullName.trim().isEmpty) {
      throw const BusinessRuleException('Enter the user\'s full name.');
    }
    if (roles.isEmpty) {
      throw const BusinessRuleException('Give the user at least one role.');
    }
    final email = user.email.trim().toLowerCase();
    if (_users.any((u) => u.id != user.id && u.email.toLowerCase() == email)) {
      throw const BusinessRuleException('Another user already has this email.');
    }
    final now = DateTime.now();
    late User saved;
    if (user.id == 0) {
      saved = User(
        id: _users.fold(0, (m, u) => u.id > m ? u.id : m) + 1,
        companyId: user.companyId,
        fullName: user.fullName.trim(),
        email: email,
        phone: user.phone,
        isActive: user.isActive,
        createdAt: now,
        updatedAt: now,
      );
      _users.add(saved);
    } else {
      final i = _indexOf(user.id);
      saved = User(
        id: user.id,
        companyId: user.companyId,
        fullName: user.fullName.trim(),
        email: email,
        phone: user.phone,
        isActive: user.isActive,
        createdAt: _users[i].createdAt,
        updatedAt: now,
      );
      _users[i] = saved;
    }
    _roles.removeWhere((r) => r.userId == saved.id);
    var nextId = _roles.fold(0, (m, r) => r.id > m ? r.id : m) + 1;
    for (final role in roles.toSet()) {
      _roles.add(UserRole(id: nextId++, userId: saved.id, role: role));
    }
    return saved;
  }

  @override
  Future<User> setActive(int userId, bool active) async {
    final i = _indexOf(userId);
    final u = _users[i];
    final updated = User(
      id: u.id,
      companyId: u.companyId,
      fullName: u.fullName,
      email: u.email,
      phone: u.phone,
      isActive: active,
      createdAt: u.createdAt,
      updatedAt: DateTime.now(),
    );
    _users[i] = updated;
    return updated;
  }

  int _indexOf(int id) {
    final i = _users.indexWhere((u) => u.id == id);
    if (i < 0) throw const BusinessRuleException('User not found.');
    return i;
  }
}

import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/user.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/session_service.dart';

class ProfileViewModel extends ChangeNotifier with ActionRunner {
  ProfileViewModel({
    required SessionService session,
    required UserRepository users,
    required AuthRepository auth,
  }) : _session = session,
       _users = users,
       _auth = auth;

  final SessionService _session;
  final UserRepository _users;
  final AuthRepository _auth;

  User get user => _session.user!;
  List<AppRole> get roles => _session.roles;

  Future<String?> saveProfile({
    required String fullName,
    required String phone,
  }) => runAction(() async {
    final updated = User(
      id: user.id,
      companyId: user.companyId,
      fullName: fullName,
      email: user.email,
      phone: phone.trim().isEmpty ? null : phone.trim(),
      isActive: user.isActive,
      createdAt: user.createdAt,
    );
    _session.updateUser(await _users.saveUser(updated, roles));
  });

  Future<String?> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => runAction(
    () => _auth.changePassword(
      user.id,
      currentPassword: currentPassword,
      newPassword: newPassword,
    ),
  );
}

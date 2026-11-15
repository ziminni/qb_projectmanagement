import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/network/api_config.dart';
import '../../../core/utils/action_runner.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/user.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/session_service.dart';

class DemoAccount {
  const DemoAccount(this.user, this.roles);

  final User user;
  final List<AppRole> roles;
}

class LoginViewModel extends ChangeNotifier with ActionRunner {
  LoginViewModel({
    required AuthRepository auth,
    required UserRepository users,
    required SessionService session,
    bool? usesApi,
  }) : _auth = auth,
       _users = users,
       _session = session,
       _usesApi = usesApi ?? useApi;

  final AuthRepository _auth;
  final UserRepository _users;
  final SessionService _session;
  final bool _usesApi;

  String? _error;
  List<DemoAccount> _demoAccounts = const [];

  /// Sign-in failure shown under the form.
  String? get error => _error;

  /// Mock accounts listed on the login screen until a real backend exists.
  List<DemoAccount> get demoAccounts => _demoAccounts;

  bool get usesApi => _usesApi;

  /// Real accounts in API mode: the demo list (which names users and prints
  /// the shared demo password) stays mock-only.
  Future<void> loadDemoAccounts() async {
    if (_usesApi) return;
    final users = await _users.getUsers();
    _demoAccounts = [
      for (final u in users)
        if (u.isActive) DemoAccount(u, await _users.getRoles(u.id)),
    ];
    notifyListeners();
  }

  /// Signs in and returns true on success.
  Future<bool> signIn(String email, String password) async {
    _error = null;
    final error = await runAction(() async {
      final result = await _auth.signIn(email, password);
      _session.signIn(result.user, result.roles);
    });
    _error = error;
    notifyListeners();
    return error == null;
  }

  bool get hasSeveralRoles => _session.roles.length > 1;

  AppRole get activeRole => _session.activeRole!;
}

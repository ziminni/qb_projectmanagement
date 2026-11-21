import 'package:flutter/foundation.dart' show ChangeNotifier, kReleaseMode;

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
    bool? showDemoLogins,
  }) : _auth = auth,
       _users = users,
       _session = session,
       _usesApi = usesApi ?? useApi,
       _showDemoLogins = showDemoLogins ?? defaultShowDemoLogins;

  /// Demo sign-in shortcuts show in debug and profile builds, and in a
  /// release build only with `--dart-define=SHOW_DEMO_LOGINS=true`, so a
  /// production build never prints the shared demo password.
  static const defaultShowDemoLogins =
      !kReleaseMode || bool.fromEnvironment('SHOW_DEMO_LOGINS');

  /// The accounts `seed_demo` creates on the backend
  /// (`django-backend/apps/users/demo_data.py`).
  static const _seededAccounts = [
    (1, 'Maria Santos', 'maria@example.ph', [AppRole.admin]),
    (2, 'Ramon Dela Cruz', 'ramon@example.ph', [AppRole.owner]),
    (3, 'Ana Bautista', 'ana@example.ph', [AppRole.siteEngineer]),
    (4, 'Liza Garcia', 'liza@example.ph', [AppRole.accountant]),
    (5, 'Mark Villanueva', 'mark@example.ph', [AppRole.client]),
    (
      6,
      'Elena Torres',
      'elena@example.ph',
      [AppRole.owner, AppRole.siteEngineer],
    ),
  ];

  final AuthRepository _auth;
  final UserRepository _users;
  final SessionService _session;
  final bool _usesApi;
  final bool _showDemoLogins;

  String? _error;
  List<DemoAccount> _demoAccounts = const [];

  /// Sign-in failure shown under the form.
  String? get error => _error;

  /// Mock accounts listed on the login screen until a real backend exists.
  List<DemoAccount> get demoAccounts => _demoAccounts;

  bool get usesApi => _usesApi;

  /// The demo accounts to offer: the mock users, or in API mode the
  /// accounts the backend seeds. None when demo logins are off.
  Future<void> loadDemoAccounts() async {
    if (!_showDemoLogins) return;
    if (_usesApi) {
      _demoAccounts = [
        for (final (id, name, email, roles) in _seededAccounts)
          DemoAccount(
            User(id: id, companyId: 0, fullName: name, email: email),
            roles,
          ),
      ];
      notifyListeners();
      return;
    }
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

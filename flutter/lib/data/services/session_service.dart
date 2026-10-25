import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../models/app_role.dart';
import '../models/user.dart';

/// Holds the signed-in user and the role whose app shell is showing.
class SessionService extends ChangeNotifier {
  User? _user;
  List<AppRole> _roles = const [];
  AppRole? _activeRole;

  User? get user => _user;
  List<AppRole> get roles => _roles;
  AppRole? get activeRole => _activeRole;
  bool get isSignedIn => _user != null && _activeRole != null;

  void signIn(User user, List<AppRole> roles, {AppRole? activeRole}) {
    assert(roles.isNotEmpty);
    _user = user;
    _roles = List.unmodifiable(roles);
    _activeRole = activeRole ?? roles.first;
    notifyListeners();
  }

  /// Refreshes the signed-in user after a profile edit.
  void updateUser(User user) {
    if (_user?.id != user.id) return;
    _user = user;
    notifyListeners();
  }

  void switchRole(AppRole role) {
    if (!_roles.contains(role) || role == _activeRole) return;
    _activeRole = role;
    notifyListeners();
  }

  void signOut() {
    _user = null;
    _roles = const [];
    _activeRole = null;
    notifyListeners();
  }
}

import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/user.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/business_rule_exception.dart';
import '../../../data/services/session_service.dart';

class UserListItem {
  const UserListItem(this.user, this.roles);

  final User user;
  final List<AppRole> roles;
}

class UsersViewModel extends ChangeNotifier with ActionRunner {
  UsersViewModel({
    required UserRepository users,
    required SessionService session,
  }) : _users = users,
       _session = session;

  final UserRepository _users;
  final SessionService _session;

  bool _loading = true;
  String? _error;
  List<UserListItem> _all = const [];
  String _query = '';
  AppRole? _roleFilter;
  bool _showInactive = true;

  bool get isLoading => _loading;
  String? get error => _error;
  AppRole? get roleFilter => _roleFilter;
  bool get showInactive => _showInactive;

  List<UserListItem> get items {
    final q = _query.trim().toLowerCase();
    return _all.where((i) {
      if (!_showInactive && !i.user.isActive) return false;
      if (_roleFilter != null && !i.roles.contains(_roleFilter)) return false;
      if (q.isEmpty) return true;
      return i.user.fullName.toLowerCase().contains(q) ||
          i.user.email.toLowerCase().contains(q);
    }).toList();
  }

  bool isSelf(User user) => user.id == _session.user?.id;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final users = await _users.getUsers();
      final roles = await _users.getAllUserRoles();
      _all = [
        for (final u in users)
          UserListItem(u, [
            for (final r in roles)
              if (r.userId == u.id) r.role,
          ]),
      ]..sort((a, b) => a.user.fullName.compareTo(b.user.fullName));
    } catch (e) {
      _error = 'Could not load users. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void setQuery(String value) {
    _query = value;
    notifyListeners();
  }

  void setRoleFilter(AppRole? role) {
    _roleFilter = role;
    notifyListeners();
  }

  void setShowInactive(bool value) {
    _showInactive = value;
    notifyListeners();
  }

  Future<String?> setActive(User user, bool active) => runAction(() async {
    if (isSelf(user) && !active) {
      throw const BusinessRuleException('You cannot deactivate yourself.');
    }
    await _users.setActive(user.id, active);
    await load();
  });
}

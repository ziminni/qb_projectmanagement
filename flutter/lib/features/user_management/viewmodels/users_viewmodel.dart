import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/user.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/business_rule_exception.dart';
import '../../../data/services/session_service.dart';
import 'admin_audit.dart';

class UserListItem {
  const UserListItem(this.user, this.roles);

  final User user;
  final List<AppRole> roles;
}

/// Columns the user list can be sorted by.
enum UserSort {
  name('Name'),
  role('Role'),
  status('Status'),
  added('Date added');

  const UserSort(this.label);
  final String label;
}

/// Which accounts the list shows.
enum UserStatusFilter {
  all('All'),
  active('Active'),
  inactive('Inactive');

  const UserStatusFilter(this.label);
  final String label;
}

class UsersViewModel extends ChangeNotifier with ActionRunner {
  UsersViewModel({
    required UserRepository users,
    required SessionService session,
    AdminAudit? audit,
  }) : _users = users,
       _session = session,
       _audit = audit;

  final UserRepository _users;
  final SessionService _session;
  final AdminAudit? _audit;

  bool _loading = true;
  String? _error;
  List<UserListItem> _all = const [];
  String _query = '';
  AppRole? _roleFilter;
  UserStatusFilter _status = UserStatusFilter.all;
  UserSort _sort = UserSort.name;
  bool _ascending = true;

  bool get isLoading => _loading;
  String? get error => _error;
  String get query => _query;
  AppRole? get roleFilter => _roleFilter;
  UserStatusFilter get statusFilter => _status;
  UserSort get sort => _sort;
  bool get ascending => _ascending;

  int get totalCount => _all.length;
  int get activeCount => _all.where((i) => i.user.isActive).length;
  int get inactiveCount => totalCount - activeCount;

  /// Whether any filter narrows the list.
  bool get isFiltered =>
      _query.trim().isNotEmpty ||
      _roleFilter != null ||
      _status != UserStatusFilter.all;

  List<UserListItem> get items {
    final q = _query.trim().toLowerCase();
    final out = _all.where((i) {
      if (_status == UserStatusFilter.active && !i.user.isActive) return false;
      if (_status == UserStatusFilter.inactive && i.user.isActive) return false;
      if (_roleFilter != null && !i.roles.contains(_roleFilter)) return false;
      if (q.isEmpty) return true;
      return i.user.fullName.toLowerCase().contains(q) ||
          i.user.email.toLowerCase().contains(q) ||
          (i.user.phone ?? '').toLowerCase().contains(q);
    }).toList();
    int byName(UserListItem a, UserListItem b) =>
        a.user.fullName.toLowerCase().compareTo(b.user.fullName.toLowerCase());
    int compare(UserListItem a, UserListItem b) {
      final c = switch (_sort) {
        UserSort.name => 0,
        UserSort.role => _roleRank(a).compareTo(_roleRank(b)),
        UserSort.status => (a.user.isActive ? 0 : 1).compareTo(
          b.user.isActive ? 0 : 1,
        ),
        UserSort.added => (a.user.createdAt ?? DateTime(0)).compareTo(
          b.user.createdAt ?? DateTime(0),
        ),
      };
      return c != 0 ? c : byName(a, b);
    }

    out.sort((a, b) => _ascending ? compare(a, b) : compare(b, a));
    return out;
  }

  /// Users with no role sort last.
  static int _roleRank(UserListItem i) => i.roles.isEmpty
      ? AppRole.values.length
      : i.roles.map((r) => r.index).reduce((a, b) => a < b ? a : b);

  bool isSelf(User user) => user.id == _session.user?.id;

  Future<void> load() async {
    _loading = _all.isEmpty;
    _error = null;
    notifyListeners();
    try {
      final (users, roles) = await (
        _users.getUsers(),
        _users.getAllUserRoles(),
      ).wait;
      _all = [
        for (final u in users)
          UserListItem(
            u,
            [
              for (final r in roles)
                if (r.userId == u.id) r.role,
            ]..sort((a, b) => a.index.compareTo(b.index)),
          ),
      ];
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

  void setStatusFilter(UserStatusFilter value) {
    _status = value;
    notifyListeners();
  }

  /// Sorts by [column]; choosing the current column flips the direction.
  void sortBy(UserSort column) {
    if (_sort == column) {
      _ascending = !_ascending;
    } else {
      _sort = column;
      // Newest first is the useful default for dates.
      _ascending = column != UserSort.added;
    }
    notifyListeners();
  }

  void clearFilters() {
    _query = '';
    _roleFilter = null;
    _status = UserStatusFilter.all;
    notifyListeners();
  }

  Future<String?> setActive(User user, bool active) => runAction(() async {
    if (isSelf(user) && !active) {
      throw const BusinessRuleException('You cannot deactivate yourself.');
    }
    final saved = await _users.setActive(user.id, active);
    await _audit?.record(
      active ? 'user_reactivated' : 'user_deactivated',
      entity: 'user',
      entityId: user.id,
      details: {'name': saved.fullName},
    );
    await load();
  });
}

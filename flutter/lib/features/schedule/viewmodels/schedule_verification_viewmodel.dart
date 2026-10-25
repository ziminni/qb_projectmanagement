import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../data/models/app_role.dart';
import '../../../data/models/category.dart';
import '../../../data/models/project.dart';
import '../../../data/models/todo.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/repositories/schedule_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/business_rule_exception.dart';
import '../../../data/services/session_service.dart';

class PendingTodo {
  const PendingTodo({
    required this.project,
    required this.category,
    required this.todo,
  });

  final Project project;
  final Category category;
  final Todo todo;
}

/// To-dos marked done on site and awaiting the PM's verification, across the
/// PM's own projects.
class ScheduleVerificationViewModel extends ChangeNotifier {
  ScheduleVerificationViewModel({
    required SessionService session,
    required ProjectRepository projects,
    required ScheduleRepository schedule,
    required UserRepository users,
  }) : _session = session,
       _projects = projects,
       _schedule = schedule,
       _users = users;

  final SessionService _session;
  final ProjectRepository _projects;
  final ScheduleRepository _schedule;
  final UserRepository _users;

  bool _loading = true;
  String? _error;
  List<PendingTodo> _pending = const [];
  final _userNames = <int, String>{};
  final _verifying = <int>{};

  bool get isLoading => _loading;
  String? get error => _error;
  List<PendingTodo> get pending => _pending;
  bool isVerifying(Todo todo) => _verifying.contains(todo.id);
  String? userName(int? id) => id == null ? null : _userNames[id];

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      if (_session.activeRole != AppRole.pm) {
        _error = 'Only project managers verify to-dos.';
        return;
      }
      for (final user in await _users.getUsers()) {
        _userNames[user.id] = user.fullName;
      }
      await _refresh();
    } catch (e) {
      _error = 'Could not load to-dos awaiting verification. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _refresh() async {
    final projects = await _projects.getProjectsFor(
      _session.user!.id,
      AppRole.pm,
    );
    final result = <PendingTodo>[];
    for (final project in projects) {
      final categories = {
        for (final c in await _schedule.getCategories(project.id)) c.id: c,
      };
      for (final todo in await _schedule.getTodos(project.id)) {
        if (todo.isAwaitingVerification) {
          result.add(
            PendingTodo(
              project: project,
              category: categories[todo.categoryId]!,
              todo: todo,
            ),
          );
        }
      }
    }
    result.sort(
      (a, b) => (a.todo.doneAt ?? a.todo.endDate).compareTo(
        b.todo.doneAt ?? b.todo.endDate,
      ),
    );
    _pending = result;
  }

  /// Returns an error message, or null on success.
  Future<String?> verify(Todo todo) async {
    _verifying.add(todo.id);
    notifyListeners();
    try {
      await _schedule.verify(todo.id, userId: _session.user!.id);
      await _refresh();
      return null;
    } on BusinessRuleException catch (e) {
      return e.message;
    } catch (e) {
      return 'Something went wrong. $e';
    } finally {
      _verifying.remove(todo.id);
      notifyListeners();
    }
  }
}

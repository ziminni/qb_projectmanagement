import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../models/app_role.dart';
import '../repositories/notification_repository.dart';
import '../repositories/project_repository.dart';

/// Sends in-app notifications and tells listeners (the app bar badge) when
/// they change. Repositories call it when a workflow hands work to someone.
class NotificationService extends ChangeNotifier {
  NotificationService({required NotificationRepository notifications})
    : _repo = notifications;

  final NotificationRepository _repo;
  ProjectRepository? _projects;

  /// Set after construction to avoid a dependency cycle with repositories
  /// that both notify and are needed to find recipients.
  set projects(ProjectRepository value) => _projects = value;

  Future<int> unreadCount(int userId) async =>
      (await _repo.getFor(userId)).where((n) => !n.isRead).length;

  Future<void> notify(
    Iterable<int> userIds, {
    required String type,
    required String message,
    String? link,
  }) async {
    for (final id in userIds.toSet()) {
      await _repo.create(userId: id, type: type, message: message, link: link);
    }
    notifyListeners();
  }

  /// Notifies everyone assigned to [projectId] in [role].
  Future<void> notifyProjectRole(
    int projectId,
    AppRole role, {
    required String type,
    required String message,
    String? link,
  }) async {
    final assignments = await _projects?.getAssignments(projectId) ?? const [];
    await notify(
      [
        for (final a in assignments)
          if (a.roleOnProject == role) a.userId,
      ],
      type: type,
      message: message,
      link: link,
    );
  }

  Future<void> markRead(int id) async {
    await _repo.markRead(id);
    notifyListeners();
  }

  Future<void> markAllRead(int userId) async {
    await _repo.markAllRead(userId);
    notifyListeners();
  }
}

import '../models/app_role.dart';
import '../models/project.dart';
import '../models/project_assignment.dart';

abstract interface class ProjectRepository {
  Future<Project?> getProject(int id);

  Future<List<Project>> getProjects();

  /// Projects visible to [userId] acting as [role]: owner and admin see all,
  /// accountant sees all for their work queues, everyone else
  /// sees only projects they are assigned to.
  Future<List<Project>> getProjectsFor(int userId, AppRole role);

  Future<bool> isAssigned(int projectId, int userId, AppRole role);

  Future<List<ProjectAssignment>> getAssignments(int projectId);

  Future<List<ProjectAssignment>> getAssignmentsForUser(int userId);

  /// Replaces all of [userId]'s assignments. Each assignment's role must be
  /// one the user holds.
  Future<void> setUserAssignments(
    int userId,
    List<({int projectId, AppRole role})> assignments,
  );

  Future<ProjectAssignment> assign(int projectId, int userId, AppRole role);

  Future<void> unassign(int assignmentId);

  /// Creates the project when its id is 0, otherwise updates its details.
  /// Status changes go through [changeStatus].
  Future<Project> saveProject(Project project);

  Future<Project> changeStatus(
    int projectId,
    ProjectStatus status, {
    required int userId,
    required AppRole role,
  });

  /// Applies an approved variation order: adjusts the contract amount and
  /// pushes the target end date by [daysImpact].
  Future<Project> applyVariation(
    int projectId, {
    required double amountDelta,
    required int daysImpact,
  });
}

import '../models/app_role.dart';
import '../models/project.dart';
import '../models/project_assignment.dart';

/// A project waiting for one person's answer to its request.
class ProjectRequest {
  const ProjectRequest(this.project, this.assignment);

  final Project project;
  final ProjectAssignment assignment;
}

abstract interface class ProjectRepository {
  Future<Project?> getProject(int id);

  Future<List<Project>> getProjects();

  /// Projects visible to [userId] acting as [role]: admin and accountant see
  /// all, everyone else only projects they have joined (accepted).
  Future<List<Project>> getProjectsFor(int userId, AppRole role);

  /// Whether [userId] has joined [projectId] as [role]. A request that is
  /// still waiting or was declined does not count.
  Future<bool> isAssigned(int projectId, int userId, AppRole role);

  /// Everyone on the project, including requests still waiting or declined.
  Future<List<ProjectAssignment>> getAssignments(int projectId);

  Future<List<ProjectAssignment>> getAssignmentsForUser(int userId);

  /// Replaces all of [userId]'s assignments. Each assignment's role must be
  /// one the user holds.
  Future<void> setUserAssignments(
    int userId,
    List<({int projectId, AppRole role})> assignments,
  );

  /// Adds [userId] to the project. Clients and site engineers get a request
  /// they must accept first; a site engineer's is held until the client has
  /// accepted. Owners join straight away.
  Future<ProjectAssignment> assign(int projectId, int userId, AppRole role);

  /// Requests still waiting for [userId]'s answer in [role].
  Future<List<ProjectRequest>> getRequestsFor(int userId, AppRole role);

  /// Answers a request with accepted, declined or (clients only)
  /// changesRequested; declining and asking for changes need a [note].
  ///
  /// When the client accepts, the site engineer's request is sent. When the
  /// site engineer then accepts, the project becomes Accepted. A client who
  /// asks for changes sends it back to the owner; a client who declines
  /// deletes the project. A site engineer who declines waits for the owner
  /// to choose another.
  Future<ProjectAssignment> respondToRequest(
    int assignmentId, {
    required int userId,
    required RequestResponse answer,
    String? note,
  });

  /// Owner sends a revised project back to the client after changes were
  /// requested.
  Future<Project> resendRequest(int projectId, {required int userId});

  Future<void> unassign(int assignmentId);

  /// Creates the project (Waiting for acceptance) when its id is 0,
  /// otherwise updates its details.
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

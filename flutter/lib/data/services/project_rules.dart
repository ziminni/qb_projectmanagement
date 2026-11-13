import '../models/app_role.dart';
import '../models/project.dart';
import 'business_rule_exception.dart';

/// Project rules from "Business rules and validations".
abstract final class ProjectRules {
  /// Roles that hold project assignments.
  static const assignableRoles = [
    AppRole.owner,
    AppRole.siteEngineer,
    AppRole.client,
  ];

  static String? validateContractAmount(double? amount) {
    if (amount == null) return 'Enter the contract amount.';
    if (amount <= 0) return 'Contract amount must be greater than 0.';
    return null;
  }

  static String? validateDates(DateTime? start, DateTime? targetEnd) {
    if (start == null || targetEnd == null) {
      return 'Choose the start and target end dates.';
    }
    if (!targetEnd.isAfter(start)) {
      return 'Target end date must be after the start date.';
    }
    return null;
  }

  static String? validatePercent(double? value, String label) {
    if (value == null) return 'Enter the $label.';
    if (value < 0 || value > 100) return 'The $label must be 0–100%.';
    return null;
  }

  /// Statuses the owner can move a project to from [from]. A request
  /// moves on its own as the client and then the site engineer answer, so
  /// the request statuses have no manual moves.
  static List<ProjectStatus> nextStatuses(ProjectStatus from) => switch (from) {
    ProjectStatus.accepted => const [ProjectStatus.ongoing],
    ProjectStatus.ongoing => const [
      ProjectStatus.completed,
      ProjectStatus.onHold,
    ],
    ProjectStatus.onHold => const [ProjectStatus.ongoing],
    ProjectStatus.completed => const [ProjectStatus.closed],
    ProjectStatus.requested ||
    ProjectStatus.changesRequested ||
    ProjectStatus.siteEngineerPending ||
    ProjectStatus.closed => const [],
  };

  /// Declining needs a reason, and asking for changes needs a note.
  static String? validateNote(String? note) =>
      (note == null || note.trim().isEmpty)
      ? 'Add a note so the owner knows why.'
      : null;

  /// Not yet past the request stage.
  static bool isRequest(ProjectStatus s) => const [
    ProjectStatus.requested,
    ProjectStatus.changesRequested,
    ProjectStatus.siteEngineerPending,
  ].contains(s);

  /// The owner running the project makes every status move.
  static bool canChangeStatus(AppRole role, ProjectStatus to) =>
      role == AppRole.owner;

  static String? validateTransition(
    ProjectStatus from,
    ProjectStatus to,
    AppRole role,
  ) {
    if (!nextStatuses(from).contains(to)) {
      return 'A project cannot move from ${from.label} to ${to.label}.';
    }
    if (!canChangeStatus(role, to)) {
      return 'Only the owner can move a project to ${to.label}.';
    }
    return null;
  }

  /// Daily reports, material requests and billings are allowed only once a
  /// project is Ongoing. Completed projects can still be billed.
  static String? requireOngoing(Project project, String what) =>
      project.status == ProjectStatus.ongoing
      ? null
      : '$what can be added only while the project is Ongoing '
            '(it is ${project.status.label}).';

  static void enforce(String? error) {
    if (error != null) throw BusinessRuleException(error);
  }
}

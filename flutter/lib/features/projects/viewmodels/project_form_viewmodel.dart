import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/category.dart';
import '../../../data/models/client.dart';
import '../../../data/models/company_settings.dart';
import '../../../data/models/project.dart';
import '../../../data/models/user.dart';
import '../../../data/repositories/client_repository.dart';
import '../../../data/repositories/company_repository.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/repositories/schedule_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/business_rule_exception.dart';
import '../../../data/services/schedule_rules.dart';
import '../../../data/services/session_service.dart';

/// Create or edit a project. Creating one assigns the owner to run it and
/// sends the request to the client and the chosen site engineer.
class ProjectFormViewModel extends ChangeNotifier with ActionRunner {
  ProjectFormViewModel({
    required this.projectId,
    required SessionService session,
    required ProjectRepository projects,
    required ClientRepository clients,
    required CompanyRepository company,
    required UserRepository users,
    required ScheduleRepository schedule,
  }) : _session = session,
       _projects = projects,
       _clients = clients,
       _company = company,
       _users = users,
       _schedule = schedule;

  final int? projectId;
  final SessionService _session;
  final ProjectRepository _projects;
  final ClientRepository _clients;
  final CompanyRepository _company;
  final UserRepository _users;
  final ScheduleRepository _schedule;

  bool _loading = true;
  String? _error;
  Project? _project;
  CompanySettings? _settings;
  List<Client> _clientList = const [];
  List<User> _siteEngineers = const [];
  int? _savedId;

  bool get isLoading => _loading;
  String? get error => _error;
  bool get isNew => projectId == null;
  Project? get project => _project;
  CompanySettings? get settings => _settings;
  List<Client> get clients => _clientList;
  List<User> get siteEngineers => _siteEngineers;

  String clientName(int? id) =>
      _clientList.where((c) => c.id == id).firstOrNull?.name ?? '—';

  String? siteEngineerName(int? id) =>
      _siteEngineers.where((u) => u.id == id).firstOrNull?.fullName;

  /// Category budgets together cannot exceed the contract amount.
  String? validateCategories(double contract, List<(String, double)> cats) =>
      ScheduleRules.validateBudgetTotal(
        budget: 0,
        otherBudgetsTotal: cats.fold(0.0, (s, c) => s + c.$2),
        contractAmount: contract,
      );

  /// The request goes to the client's app login, so a new project needs a
  /// client that has one.
  String? validateClient(int? clientId) {
    if (clientId == null) return 'Choose the client.';
    if (!isNew) return null;
    final c = _clientList.where((c) => c.id == clientId).firstOrNull;
    return c?.userId == null
        ? 'This client has no app login yet. Ask the admin to create one.'
        : null;
  }

  /// Id of the project after a successful save.
  int? get savedId => _savedId;

  /// Once work starts the contract amount changes only through approved
  /// variation orders.
  bool get contractLocked =>
      _project != null &&
      const [
        ProjectStatus.ongoing,
        ProjectStatus.onHold,
        ProjectStatus.completed,
        ProjectStatus.closed,
      ].contains(_project!.status);

  Future<void> load() async {
    try {
      _settings = await _company.getSettings();
      _clientList = await _clients.getClients();
      _siteEngineers = [
        for (final u in await _users.getUsersWithRole(AppRole.siteEngineer))
          if (u.isActive) u,
      ];
      if (projectId != null) {
        _project = await _projects.getProject(projectId!);
        if (_project == null) {
          _error = 'Project not found.';
        } else if (_session.activeRole == AppRole.owner &&
            !await _projects.isAssigned(
              projectId!,
              _session.user!.id,
              AppRole.owner,
            )) {
          _error = 'You can edit only projects assigned to you.';
        }
      }
    } catch (e) {
      _error = 'Could not load the form. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<String?> save({
    required String code,
    required String name,
    required String location,
    required int? clientId,
    required double contractAmount,
    required double downPaymentPct,
    required double retentionPct,
    required DateTime startDate,
    required DateTime targetEndDate,
    double? latitude,
    double? longitude,
    int? siteEngineerId,
    List<(String, double)> categories = const [],
  }) => runAction(() async {
    if (isNew) {
      final budgetError = validateCategories(contractAmount, categories);
      if (budgetError != null) throw BusinessRuleException(budgetError);
    }
    final clientError = validateClient(clientId);
    if (clientError != null) throw BusinessRuleException(clientError);
    if (isNew && siteEngineerId == null) {
      throw const BusinessRuleException('Choose the site engineer.');
    }
    final existing = _project;
    final saved = await _projects.saveProject(
      Project(
        id: projectId ?? 0,
        code: code,
        name: name,
        location: location,
        latitude: latitude,
        longitude: longitude,
        clientId: clientId!,
        contractAmount: contractLocked
            ? existing!.contractAmount
            : contractAmount,
        downPaymentPct: downPaymentPct,
        retentionPct: retentionPct,
        startDate: startDate,
        targetEndDate: targetEndDate,
        actualEndDate: existing?.actualEndDate,
        status: existing?.status ?? ProjectStatus.requested,
        createdAt: existing?.createdAt,
      ),
    );
    if (isNew) {
      // The owner who creates a project runs it. The client gets the
      // request now; the site engineer's is held until the client accepts.
      final clientUser = _clientList
          .firstWhere((c) => c.id == clientId)
          .userId!;
      // The server adds the creator as the project's owner inside the create
      // (decision 06, ruling 6), so that call is only needed offline.
      if (!await _projects.isAssigned(
        saved.id,
        _session.user!.id,
        AppRole.owner,
      )) {
        await _projects.assign(saved.id, _session.user!.id, AppRole.owner);
      }
      await _projects.assign(saved.id, clientUser, AppRole.client);
      await _projects.assign(saved.id, siteEngineerId!, AppRole.siteEngineer);
      for (final (i, (name, budget)) in categories.indexed) {
        await _schedule.saveCategory(
          Category(
            id: 0,
            projectId: saved.id,
            name: name.trim(),
            budget: budget > 0 ? budget : null,
            sortOrder: i + 1,
          ),
        );
      }
    }
    _savedId = saved.id;
  });
}

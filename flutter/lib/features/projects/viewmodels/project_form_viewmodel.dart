import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/client.dart';
import '../../../data/models/company_settings.dart';
import '../../../data/models/project.dart';
import '../../../data/models/user.dart';
import '../../../data/repositories/client_repository.dart';
import '../../../data/repositories/company_repository.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/business_rule_exception.dart';
import '../../../data/services/session_service.dart';

/// Create or edit a project. New projects start as Draft; the owner picks
/// the PM, and a PM creating a project is assigned to it.
class ProjectFormViewModel extends ChangeNotifier with ActionRunner {
  ProjectFormViewModel({
    required this.projectId,
    required SessionService session,
    required ProjectRepository projects,
    required ClientRepository clients,
    required CompanyRepository company,
    required UserRepository users,
  }) : _session = session,
       _projects = projects,
       _clients = clients,
       _company = company,
       _users = users;

  final int? projectId;
  final SessionService _session;
  final ProjectRepository _projects;
  final ClientRepository _clients;
  final CompanyRepository _company;
  final UserRepository _users;

  bool _loading = true;
  String? _error;
  Project? _project;
  CompanySettings? _settings;
  List<Client> _clientList = const [];
  List<User> _pms = const [];
  int? _savedId;

  bool get isLoading => _loading;
  String? get error => _error;
  bool get isNew => projectId == null;
  Project? get project => _project;
  CompanySettings? get settings => _settings;
  List<Client> get clients => _clientList;
  List<User> get projectManagers => _pms;
  bool get choosesPm => isNew && _session.activeRole == AppRole.owner;

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
      _pms = await _users.getUsersWithRole(AppRole.pm);
      if (projectId != null) {
        _project = await _projects.getProject(projectId!);
        if (_project == null) {
          _error = 'Project not found.';
        } else if (_session.activeRole == AppRole.pm &&
            !await _projects.isAssigned(
              projectId!,
              _session.user!.id,
              AppRole.pm,
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
    int? pmUserId,
  }) => runAction(() async {
    if (clientId == null) {
      throw const BusinessRuleException('Choose the client.');
    }
    if (choosesPm && pmUserId == null) {
      throw const BusinessRuleException('Choose the project manager.');
    }
    final existing = _project;
    final saved = await _projects.saveProject(
      Project(
        id: projectId ?? 0,
        code: code,
        name: name,
        location: location,
        clientId: clientId,
        contractAmount: contractLocked
            ? existing!.contractAmount
            : contractAmount,
        downPaymentPct: downPaymentPct,
        retentionPct: retentionPct,
        startDate: startDate,
        targetEndDate: targetEndDate,
        actualEndDate: existing?.actualEndDate,
        status: existing?.status ?? ProjectStatus.draft,
        createdAt: existing?.createdAt,
      ),
    );
    if (isNew) {
      final pm = choosesPm ? pmUserId! : _session.user!.id;
      await _projects.assign(saved.id, pm, AppRole.pm);
    }
    _savedId = saved.id;
  });
}

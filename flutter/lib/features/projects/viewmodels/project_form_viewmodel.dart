import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/client.dart';
import '../../../data/models/company_settings.dart';
import '../../../data/models/project.dart';
import '../../../data/repositories/client_repository.dart';
import '../../../data/repositories/company_repository.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/services/business_rule_exception.dart';
import '../../../data/services/session_service.dart';

/// Create or edit a project. New projects start as Draft, and the owner
/// who creates one is assigned to run it.
class ProjectFormViewModel extends ChangeNotifier with ActionRunner {
  ProjectFormViewModel({
    required this.projectId,
    required SessionService session,
    required ProjectRepository projects,
    required ClientRepository clients,
    required CompanyRepository company,
  }) : _session = session,
       _projects = projects,
       _clients = clients,
       _company = company;

  final int? projectId;
  final SessionService _session;
  final ProjectRepository _projects;
  final ClientRepository _clients;
  final CompanyRepository _company;

  bool _loading = true;
  String? _error;
  Project? _project;
  CompanySettings? _settings;
  List<Client> _clientList = const [];
  int? _savedId;

  bool get isLoading => _loading;
  String? get error => _error;
  bool get isNew => projectId == null;
  Project? get project => _project;
  CompanySettings? get settings => _settings;
  List<Client> get clients => _clientList;

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
  }) => runAction(() async {
    if (clientId == null) {
      throw const BusinessRuleException('Choose the client.');
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
      // The owner who creates a project runs it.
      await _projects.assign(saved.id, _session.user!.id, AppRole.owner);
    }
    _savedId = saved.id;
  });
}

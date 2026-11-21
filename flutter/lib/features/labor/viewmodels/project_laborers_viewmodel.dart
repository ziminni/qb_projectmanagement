import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/di/service_locator.dart';
import '../../../core/utils/action_runner.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/project_worker_request.dart';
import '../../../data/models/worker.dart';
import '../../../data/repositories/labor_repository.dart';
import '../../../data/services/notification_service.dart';
import '../../../data/services/session_service.dart';

/// Project "Laborers" tab:
/// - Foremen request to add laborers to the project (Full name, Address, Phone).
/// - Project Managers review (Approve / Reject) pending laborer requests.
/// - Approved laborers are listed and become active workers for attendance.
class ProjectLaborersViewModel extends ChangeNotifier with ActionRunner {
  ProjectLaborersViewModel({
    required this.projectId,
    required SessionService session,
    required LaborRepository labor,
  }) : _session = session,
       _labor = labor;

  final int projectId;
  final SessionService _session;
  final LaborRepository _labor;

  bool _loading = true;
  String? _error;
  List<ProjectWorkerRequest> _requests = const [];
  List<Worker> _workers = const [];
  List<Worker> _availableWorkers = const [];

  bool get isLoading => _loading;
  String? get error => _error;
  AppRole get role => _session.activeRole!;

  bool get canRequest =>
      role == AppRole.siteEngineer || role == AppRole.owner;
  bool get canReview => role == AppRole.owner;

  List<ProjectWorkerRequest> get pendingRequests => _requests
      .where((r) => r.status == ProjectWorkerRequestStatus.pending)
      .toList();

  List<ProjectWorkerRequest> get approvedRequests => _requests
      .where((r) => r.status == ProjectWorkerRequestStatus.approved)
      .toList();

  List<ProjectWorkerRequest> get rejectedRequests => _requests
      .where((r) => r.status == ProjectWorkerRequestStatus.rejected)
      .toList();

  /// Active laborers already on site (from attendance or approved requests).
  List<Worker> get projectWorkers => _workers;

  /// Active company workers not yet on this project or pending approval here.
  List<Worker> get availableWorkers => _availableWorkers;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _labor.getWorkerRequests(projectId: projectId),
        _labor.getWorkers(activeOnly: true),
        _labor.getAttendance(projectId: projectId),
      ]);
      _requests = results[0] as List<ProjectWorkerRequest>;
      final allWorkers = results[1] as List<Worker>;
      final attendance = results[2] as List;
      final projectWorkerIds = <int>{
        for (final r in _requests)
          if (r.status == ProjectWorkerRequestStatus.approved &&
              r.workerId != null)
            r.workerId!,
        for (final a in attendance) a.workerId as int,
      };
      final pendingWorkerIds = <int>{
        for (final r in _requests)
          if (r.status == ProjectWorkerRequestStatus.pending &&
              r.workerId != null)
            r.workerId!,
      };
      _workers = allWorkers
          .where((w) => projectWorkerIds.contains(w.id))
          .toList();
      _availableWorkers = allWorkers
          .where(
            (w) =>
                !projectWorkerIds.contains(w.id) &&
                !pendingWorkerIds.contains(w.id),
          )
          .toList();
    } catch (e) {
      _error = 'Could not load project laborers. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void _notifyBadges() {
    if (getIt.isRegistered<NotificationService>()) {
      getIt<NotificationService>().refresh();
    }
  }

  Future<String?> requestExistingWorkers(List<int> workerIds) =>
      runAction(() async {
        for (final id in workerIds) {
          await _labor.requestProjectWorker(
            projectId: projectId,
            workerId: id,
            userId: _session.user!.id,
          );
        }
        await load();
        _notifyBadges();
      });

  Future<String?> requestWorker({
    required String fullName,
    required String address,
    required String phone,
  }) => runAction(() async {
    await _labor.requestProjectWorker(
      projectId: projectId,
      fullName: fullName,
      address: address,
      phone: phone,
      userId: _session.user!.id,
    );
    await load();
    _notifyBadges();
  });

  Future<String?> approve(int requestId) => runAction(() async {
    await _labor.approveWorkerRequest(requestId, userId: _session.user!.id);
    await load();
    _notifyBadges();
  });

  Future<String?> reject(int requestId, String reason) => runAction(() async {
    await _labor.rejectWorkerRequest(
      requestId,
      userId: _session.user!.id,
      reason: reason,
    );
    await load();
    _notifyBadges();
  });
}

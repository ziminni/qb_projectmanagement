import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../data/models/app_role.dart';
import '../../../data/models/material_request.dart';
import '../../../data/models/project.dart';
import '../../../data/repositories/procurement_repository.dart';
import '../../../data/services/session_service.dart';
import 'procurement_lookups.dart';

/// Material requests the active role can see. In [queue] mode it is
/// purchasing's request queue: approved requests waiting for POs first.
class MaterialRequestsViewModel extends ChangeNotifier {
  MaterialRequestsViewModel({
    this.queue = false,
    required SessionService session,
    required ProcurementRepository procurement,
    required this.lookups,
  }) : _session = session,
       _procurement = procurement,
       _status = queue ? MaterialRequestStatus.approved : null;

  final bool queue;
  final SessionService _session;
  final ProcurementRepository _procurement;
  final ProcurementLookups lookups;

  bool _loading = true;
  String? _error;
  List<MaterialRequest> _items = const [];
  MaterialRequestStatus? _status;

  bool get isLoading => _loading;
  String? get error => _error;
  List<MaterialRequest> get items => _items;
  MaterialRequestStatus? get statusFilter => _status;
  AppRole get role => _session.activeRole!;

  bool get canCreate =>
      role == AppRole.siteEngineer &&
      lookups.projects.values.any((p) => p.status == ProjectStatus.ongoing);

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      await lookups.load(_session.user!.id, role);
      _items = await _procurement.getRequests(
        projectIds: lookups.projects.keys.toList(),
        statuses: _status == null ? null : [_status!],
      );
    } catch (e) {
      _error = 'Could not load material requests. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void setStatus(MaterialRequestStatus? status) {
    _status = status;
    load();
  }
}

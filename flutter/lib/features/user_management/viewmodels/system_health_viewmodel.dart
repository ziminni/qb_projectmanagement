import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/models/system_admin.dart';
import '../../../data/repositories/system_admin_repository.dart';

class SystemHealthViewModel extends ChangeNotifier with ActionRunner {
  SystemHealthViewModel(this._repo);

  final SystemAdminRepository _repo;

  bool _loading = true;
  String? _error;
  SystemHealthOverview? _overview;

  bool get isLoading => _loading;
  String? get error => _error;
  SystemHealthOverview? get overview => _overview;

  Future<void> load({bool probePos = false}) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _overview = await _repo.getSystemHealth(probePos: probePos);
    } catch (e) {
      _error = 'Could not load system health. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<String?> retryPosSync(int jobId) => runAction(() async {
    await _repo.retryPosSync(jobId);
    _overview = await _repo.getSystemHealth();
  });
}

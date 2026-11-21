import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/models/system_admin.dart';
import '../../../data/repositories/system_admin_repository.dart';

class SystemSecurityViewModel extends ChangeNotifier with ActionRunner {
  SystemSecurityViewModel(this._repo);

  final SystemAdminRepository _repo;

  bool _loading = true;
  String? _error;
  SecurityOverview? _overview;
  bool _requireManagerOverride = true;

  bool get isLoading => _loading;
  String? get error => _error;
  List<ActiveSession> get sessions => _overview?.sessions ?? const [];
  List<SecurityEvent> get events => _overview?.events ?? const [];
  SecurityPolicy? get policy => _overview?.policy;
  bool get requireManagerOverride => _requireManagerOverride;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _overview = await _repo.getSecurityOverview();
      _requireManagerOverride = _overview!.policy.requireManagerOverride;
    } catch (e) {
      _error = 'Could not load security settings. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void setRequireManagerOverride(bool value) {
    _requireManagerOverride = value;
    notifyListeners();
  }

  Future<String?> revokeSession(int sessionId) => runAction(() async {
    await _repo.revokeSession(sessionId);
    _overview = await _repo.getSecurityOverview();
  });

  Future<String?> revokeAllSessions({int? userId}) => runAction(() async {
    await _repo.revokeAllSessions(userId: userId);
    _overview = await _repo.getSecurityOverview();
  });

  Future<String?> savePolicy({
    required int minPasswordLength,
    required int idleTimeoutMinutes,
    required int maxFailedLogins,
  }) => runAction(() async {
    final updated = await _repo.updateSecurityPolicy(
      SecurityPolicy(
        minPasswordLength: minPasswordLength,
        idleTimeoutMinutes: idleTimeoutMinutes,
        maxFailedLogins: maxFailedLogins,
        requireManagerOverride: _requireManagerOverride,
      ),
    );
    _overview = SecurityOverview(
      sessions: sessions,
      events: events,
      policy: updated,
    );
  });
}

import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/models/company_settings.dart';
import '../../../data/repositories/company_repository.dart';
import 'admin_audit.dart';

class SettingsViewModel extends ChangeNotifier with ActionRunner {
  SettingsViewModel({required CompanyRepository company, AdminAudit? audit})
    : _repo = company,
      _audit = audit;

  final CompanyRepository _repo;
  final AdminAudit? _audit;

  bool _loading = true;
  String? _error;
  CompanySettings? _settings;

  bool get isLoading => _loading;
  String? get error => _error;
  CompanySettings? get settings => _settings;

  Future<void> load() async {
    try {
      _settings = await _repo.getSettings();
    } catch (e) {
      _error = 'Could not load settings. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<String?> save(CompanySettings settings) => runAction(() async {
    final saved = await _repo.saveSettings(settings);
    _settings = saved;
    await _audit?.record(
      'settings_updated',
      entity: 'company_settings',
      entityId: saved.id,
      details: {
        'retention_pct': saved.defaultRetentionPct,
        'down_payment_pct': saved.defaultDownPaymentPct,
        'behind_schedule_pct': saved.behindScheduleThresholdPct,
      },
    );
  });
}

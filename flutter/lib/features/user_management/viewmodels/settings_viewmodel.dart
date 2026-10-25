import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/models/company_settings.dart';
import '../../../data/repositories/company_repository.dart';

class SettingsViewModel extends ChangeNotifier with ActionRunner {
  SettingsViewModel({required CompanyRepository company}) : _repo = company;

  final CompanyRepository _repo;

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

  Future<String?> save(CompanySettings settings) =>
      runAction(() async => _settings = await _repo.saveSettings(settings));
}

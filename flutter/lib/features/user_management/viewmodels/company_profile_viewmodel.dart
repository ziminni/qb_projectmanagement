import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/models/company.dart';
import '../../../data/repositories/company_repository.dart';
import '../../../data/services/master_data_rules.dart';
import 'admin_audit.dart';

class CompanyProfileViewModel extends ChangeNotifier with ActionRunner {
  CompanyProfileViewModel({
    required CompanyRepository company,
    AdminAudit? audit,
  }) : _repo = company,
       _audit = audit;

  final CompanyRepository _repo;
  final AdminAudit? _audit;

  bool _loading = true;
  String? _error;
  Company? _company;

  bool get isLoading => _loading;
  String? get error => _error;
  Company? get company => _company;

  String? get pcabReminder => _company == null
      ? null
      : MasterDataRules.pcabReminder(
          _company!.pcabLicenseExpiry,
          DateTime.now(),
        );

  Future<void> load() async {
    try {
      _company = await _repo.getCompany();
    } catch (e) {
      _error = 'Could not load the company profile. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<String?> save(Company company) => runAction(() async {
    final saved = await _repo.saveCompany(company);
    _company = saved;
    await _audit?.record(
      'company_profile_updated',
      entity: 'company',
      entityId: saved.id,
      details: {'name': saved.name},
    );
  });
}

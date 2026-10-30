import '../models/company.dart';
import '../models/company_settings.dart';
import '../services/master_data_rules.dart';
import 'company_repository.dart';
import 'mock_company_data.dart';

class MockCompanyRepository implements CompanyRepository {
  Company _company = MockCompanyData.company;
  CompanySettings _settings = MockCompanyData.settings;

  @override
  Future<Company> getCompany() async => _company;

  @override
  Future<Company> saveCompany(Company company) async {
    MasterDataRules.enforce(
      MasterDataRules.required(company.name, 'company name'),
    );
    MasterDataRules.enforce(
      MasterDataRules.required(company.address, 'address'),
    );
    MasterDataRules.enforce(MasterDataRules.validateTin(company.tin));
    MasterDataRules.enforce(
      MasterDataRules.required(company.pcabLicenseNo, 'PCAB license number'),
    );
    return _company = company.copyWith(updatedAt: DateTime.now());
  }

  @override
  Future<CompanySettings> getSettings() async => _settings;

  @override
  Future<CompanySettings> saveSettings(CompanySettings settings) async {
    for (final (value, label) in [
      (settings.defaultRetentionPct, 'retention'),
      (settings.defaultDownPaymentPct, 'down payment'),
      (settings.behindScheduleThresholdPct, 'behind-schedule threshold'),
    ]) {
      MasterDataRules.enforce(MasterDataRules.validatePercent(value, label));
    }
    return _settings = settings.copyWith(updatedAt: DateTime.now());
  }
}

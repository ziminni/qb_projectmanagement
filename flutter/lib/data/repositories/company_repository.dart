import '../models/company.dart';
import '../models/company_settings.dart';

abstract interface class CompanyRepository {
  Future<Company> getCompany();

  Future<Company> saveCompany(Company company);

  Future<CompanySettings> getSettings();

  Future<CompanySettings> saveSettings(CompanySettings settings);
}

import '../../core/network/api_client.dart';
import '../models/company.dart';
import '../models/company_settings.dart';
import '../models/json_utils.dart';
import 'company_repository.dart';

/// The company profile and its settings, against the CPMS backend. Both are
/// singletons of `request.user.company` (no id in the path), so a lookup can
/// never read another company's row. Reads are open to staff roles, writes are
/// admin-only on the server; the screens show the server's own refusal text.
class HttpCompanyRepository implements CompanyRepository {
  HttpCompanyRepository(this._client);

  final ApiClient _client;

  @override
  Future<Company> getCompany() async =>
      Company.fromJson(jsonObject(await _client.get('company/')));

  @override
  Future<Company> saveCompany(Company company) async => Company.fromJson(
    jsonObject(
      await _client.patch(
        'company/',
        body: {
          'name': company.name,
          'address': company.address,
          'tin': company.tin,
          'pcab_license_no': company.pcabLicenseNo,
          // Always a `yyyy-MM-dd` date: the model parses it with the
          // non-null `JsonUtils.toDate`, so a null would break every read.
          'pcab_license_expiry': JsonUtils.fromDate(company.pcabLicenseExpiry),
          'logo_url': company.logoUrl,
        },
      ),
    ),
  );

  @override
  Future<CompanySettings> getSettings() async => CompanySettings.fromJson(
    jsonObject(await _client.get('company-settings/')),
  );

  @override
  Future<CompanySettings> saveSettings(CompanySettings settings) async =>
      CompanySettings.fromJson(
        jsonObject(
          await _client.patch(
            'company-settings/',
            body: {
              'default_retention_pct': settings.defaultRetentionPct,
              'default_down_payment_pct': settings.defaultDownPaymentPct,
              'behind_schedule_threshold_pct':
                  settings.behindScheduleThresholdPct,
            },
          ),
        ),
      );
}

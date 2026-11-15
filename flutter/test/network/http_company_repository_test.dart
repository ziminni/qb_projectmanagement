import 'package:buildpro_frontend/data/models/company.dart';
import 'package:buildpro_frontend/data/models/company_settings.dart';
import 'package:buildpro_frontend/data/repositories/http_company_repository.dart';
import 'package:buildpro_frontend/data/services/business_rule_exception.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_api.dart';

Map<String, dynamic> companyRow() => {
  'id': 1,
  'name': 'BuildPro Construction',
  'address': 'Cebu City',
  'tin': '123-456-789-000',
  'pcab_license_no': 'PCAB-1234',
  'pcab_license_expiry': '2026-12-15',
  'logo_url': null,
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-02T00:00:00Z',
};

Map<String, dynamic> settingsRow() => {
  'id': 3,
  'company_id': 1,
  'default_retention_pct': '10.00',
  'default_down_payment_pct': '15.00',
  'behind_schedule_threshold_pct': '7.50',
};

Company testCompany() => Company(
  id: 1,
  name: 'BuildPro Construction',
  address: 'Cebu City',
  tin: '123-456-789-000',
  pcabLicenseNo: 'PCAB-1234',
  pcabLicenseExpiry: DateTime(2027, 3, 1),
  logoUrl: 'https://cdn.example.ph/logo.png',
);

void main() {
  group('http company repository', () {
    test('reads the company from the singleton route', () async {
      final api = FakeApi((options) => json(companyRow()));
      final repo = HttpCompanyRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final company = await repo.getCompany();

      expect(api.last('company/').method, 'GET');
      expect(company.name, 'BuildPro Construction');
      expect(company.pcabLicenseNo, 'PCAB-1234');
      expect(company.pcabLicenseExpiry, DateTime(2026, 12, 15));
    });

    test(
      'saves the company with a patch and a date-only PCAB expiry',
      () async {
        final api = FakeApi((options) => json(companyRow()));
        final repo = HttpCompanyRepository(
          testClient(api: api, tokens: InMemoryTokenStore()),
        );

        final saved = await repo.saveCompany(testCompany());

        final request = api.last('company/');
        final sent = sentBody(request);
        expect(request.method, 'PATCH');
        expect(sent['name'], 'BuildPro Construction');
        expect(sent['address'], 'Cebu City');
        expect(sent['tin'], '123-456-789-000');
        expect(sent['pcab_license_no'], 'PCAB-1234');
        expect(sent['pcab_license_expiry'], '2027-03-01');
        expect(sent['logo_url'], 'https://cdn.example.ph/logo.png');
        // The singleton route carries no id and the server owns the timestamps.
        expect(sent.containsKey('id'), isFalse);
        expect(sent.containsKey('created_at'), isFalse);
        expect(saved.id, 1);
      },
    );

    test('reads the settings from the singleton route', () async {
      final api = FakeApi((options) => json(settingsRow()));
      final repo = HttpCompanyRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final settings = await repo.getSettings();

      expect(api.last('company-settings/').method, 'GET');
      expect(settings.companyId, 1);
      expect(settings.defaultRetentionPct, 10);
      expect(settings.defaultDownPaymentPct, 15);
      expect(settings.behindScheduleThresholdPct, 7.5);
    });

    test('saves the settings percentages with a patch', () async {
      final api = FakeApi((options) => json(settingsRow()));
      final repo = HttpCompanyRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final saved = await repo.saveSettings(
        const CompanySettings(
          id: 3,
          companyId: 1,
          defaultRetentionPct: 12,
          defaultDownPaymentPct: 20,
          behindScheduleThresholdPct: 5,
        ),
      );

      final request = api.last('company-settings/');
      final sent = sentBody(request);
      expect(request.method, 'PATCH');
      expect(sent['default_retention_pct'], 12);
      expect(sent['default_down_payment_pct'], 20);
      expect(sent['behind_schedule_threshold_pct'], 5);
      expect(saved.id, 3);
    });

    test('shows the server refusal text to the admin', () async {
      final api = FakeApi(
        (options) => json({'detail': 'Enter the TIN.'}, status: 400),
      );
      final repo = HttpCompanyRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      await expectLater(
        repo.saveCompany(testCompany()),
        throwsA(
          isA<BusinessRuleException>().having(
            (e) => e.message,
            'message',
            'Enter the TIN.',
          ),
        ),
      );
    });

    test(
      'shows the read-only refusal when the active role may not write',
      () async {
        final api = FakeApi(
          (options) => json({'detail': 'Admin role required.'}, status: 403),
        );
        final repo = HttpCompanyRepository(
          testClient(api: api, tokens: InMemoryTokenStore()),
        );

        await expectLater(
          repo.saveSettings(
            const CompanySettings(
              id: 3,
              companyId: 1,
              defaultRetentionPct: 10,
              defaultDownPaymentPct: 15,
              behindScheduleThresholdPct: 7.5,
            ),
          ),
          throwsA(
            isA<BusinessRuleException>().having(
              (e) => e.message,
              'message',
              'Admin role required.',
            ),
          ),
        );
      },
    );
  });
}

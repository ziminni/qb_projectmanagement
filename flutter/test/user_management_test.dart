import 'package:buildpro_frontend/data/models/app_role.dart';
import 'package:buildpro_frontend/data/models/user.dart';
import 'package:buildpro_frontend/data/repositories/mock_audit_log_repository.dart';
import 'package:buildpro_frontend/data/repositories/mock_client_repository.dart';
import 'package:buildpro_frontend/data/repositories/mock_company_repository.dart';
import 'package:buildpro_frontend/data/repositories/mock_project_repository.dart';
import 'package:buildpro_frontend/data/repositories/mock_user_repository.dart';
import 'package:buildpro_frontend/data/services/business_rule_exception.dart';
import 'package:buildpro_frontend/data/services/master_data_rules.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  setUp(resetServices);

  final throwsRule = throwsA(isA<BusinessRuleException>());

  group('users', () {
    late MockUserRepository users;
    setUp(() => users = MockUserRepository());

    test('email must be unique', () {
      expect(
        users.saveUser(
          const User(
            id: 0,
            companyId: 1,
            fullName: 'X',
            email: 'JOSE@example.ph',
          ),
          [AppRole.pm],
        ),
        throwsRule,
      );
    });

    test('a user needs at least one role', () {
      expect(
        users.saveUser(
          const User(id: 0, companyId: 1, fullName: 'X', email: 'x@example.ph'),
          [],
        ),
        throwsRule,
      );
    });

    test('assignments must use roles the user holds', () async {
      final projects = MockProjectRepository(
        users: users,
        auditLog: MockAuditLogRepository(),
      );
      // Ana is a site engineer only.
      expect(
        projects.setUserAssignments(4, [(projectId: 2, role: AppRole.pm)]),
        throwsRule,
      );
      await projects.setUserAssignments(4, [
        (projectId: 2, role: AppRole.siteEngineer),
      ]);
      final mine = await projects.getAssignmentsForUser(4);
      expect(mine.single.projectId, 2);
    });
  });

  test('a client can have only one portal login', () {
    final clients = MockClientRepository();
    // Client 1 is already linked to Mark (user 7).
    expect(clients.linkUser(3, 1), throwsRule);
  });

  test('settings percentages must be 0–100', () async {
    final company = MockCompanyRepository();
    final s = await company.getSettings();
    expect(
      company.saveSettings(s.copyWith(defaultRetentionPct: 120)),
      throwsRule,
    );
  });

  test('TIN format and PCAB reminder', () {
    expect(MasterDataRules.validateTin('123-456-789-000'), isNull);
    expect(MasterDataRules.validateTin('123456789'), isNotNull);
    final today = DateTime(2026, 10, 25);
    expect(
      MasterDataRules.pcabReminder(DateTime(2026, 12, 15), today),
      contains('51 days'),
    );
    expect(MasterDataRules.pcabReminder(DateTime(2027, 6, 1), today), isNull);
    expect(
      MasterDataRules.pcabReminder(DateTime(2026, 10, 20), today),
      contains('expired'),
    );
  });

  testWidgets('admin creates a site engineer assigned to a project', (
    tester,
  ) async {
    await pumpApp(tester);
    await signInAs(tester, 'maria@example.ph');
    expect(find.text('Ramon Dela Cruz'), findsOneWidget);

    await tester.tap(find.text('Add user'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Full name'),
      'Pedro Ramos',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'pedro@example.ph',
    );
    await tester.tap(
      find.widgetWithText(FilterChip, 'Site engineer / foreman'),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(DropdownButtonFormField<int>, 'Project'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Warehouse extension').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assign'));
    await tester.pumpAndSettle();
    expect(find.text('Warehouse extension'), findsOneWidget);

    await tester.ensureVisible(find.text('Create user'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create user'));
    await tester.pumpAndSettle();
    expect(find.text('Pedro Ramos'), findsOneWidget);
  });

  testWidgets('company profile shows the PCAB expiry reminder', (tester) async {
    await pumpApp(tester);
    await signInAs(tester, 'maria@example.ph');
    await goTo(tester, '/admin/company');
    expect(find.textContaining('PCAB license expires in'), findsOneWidget);
  });
}

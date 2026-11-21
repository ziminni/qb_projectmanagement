import 'package:buildpro_frontend/data/models/app_role.dart';
import 'package:buildpro_frontend/data/models/audit_log.dart';
import 'package:buildpro_frontend/data/models/user.dart';
import 'package:buildpro_frontend/data/repositories/audit_log_repository.dart';
import 'package:buildpro_frontend/data/repositories/mock_data.dart';
import 'package:buildpro_frontend/data/repositories/user_repository.dart';
import 'package:buildpro_frontend/core/di/service_locator.dart';
import 'package:buildpro_frontend/data/services/session_service.dart';
import 'package:buildpro_frontend/features/user_management/viewmodels/admin_audit.dart';
import 'package:buildpro_frontend/features/user_management/viewmodels/audit_log_viewmodel.dart';
import 'package:buildpro_frontend/features/user_management/viewmodels/settings_viewmodel.dart';
import 'package:buildpro_frontend/features/user_management/viewmodels/user_form_viewmodel.dart';
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
            email: 'RAMON@example.ph',
          ),
          [AppRole.owner],
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
        projects.setUserAssignments(4, [(projectId: 2, role: AppRole.owner)]),
        throwsRule,
      );
      await projects.setUserAssignments(4, [
        (projectId: 2, role: AppRole.siteEngineer),
      ]);
      final mine = await projects.getAssignmentsForUser(4);
      expect(mine.single.projectId, 2);
    });
  });

  group('user form company id', () {
    late _RecordingUserRepository users;
    late SessionService session;

    setUp(() {
      users = _RecordingUserRepository();
      session = SessionService()
        ..signIn(
          const User(
            id: 99,
            companyId: 42,
            fullName: 'Admin',
            email: 'admin@example.ph',
          ),
          const [AppRole.admin],
        );
    });

    UserFormViewModel form({required bool usesApi}) => UserFormViewModel(
      userId: null,
      users: users,
      projects: MockProjectRepository(
        users: users,
        auditLog: MockAuditLogRepository(),
      ),
      clients: MockClientRepository(),
      session: session,
      usesApi: usesApi,
    );

    Future<void> createNewUser(UserFormViewModel vm) async {
      await vm.load();
      vm.toggleRole(AppRole.owner, true);
      expect(
        await vm.save(
          fullName: 'New Owner',
          email: 'new@example.ph',
          phone: '',
        ),
        isNull,
      );
    }

    test('API mode saves the session company, never the mock one', () async {
      await createNewUser(form(usesApi: true));
      expect(users.lastSaved!.companyId, 42);
      expect(users.lastSaved!.companyId, isNot(MockData.companyId));
    });

    test('mock mode keeps the mock company id', () async {
      await createNewUser(form(usesApi: false));
      expect(users.lastSaved!.companyId, MockData.companyId);
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

  testWidgets('admin creates a site engineer without project assignments section', (
    tester,
  ) async {
    await pumpApp(tester);
    await signInAs(tester, 'maria@example.ph');
    // Admins land on the overview.
    expect(find.text('Needs attention'), findsOneWidget);
    await goTo(tester, '/admin/users');
    expect(find.text('Ramon Dela Cruz'), findsOneWidget);

    await tester.tap(find.text('Add user'));
    await tester.pumpAndSettle();
    expect(find.text('Project assignments'), findsNothing);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Full name'),
      'Pedro Ramos',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'pedro@example.ph',
    );
    await tester.tap(
      find.widgetWithText(FilterChip, 'Foreman'),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Create user'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create user'));
    await tester.pumpAndSettle();
    expect(find.text('Pedro Ramos'), findsOneWidget);

    // The admin's change is in the audit log.
    await goTo(tester, '/admin/audit-log');
    expect(find.text('User created'), findsOneWidget);
  });

  testWidgets('company profile shows the PCAB expiry reminder', (tester) async {
    await pumpApp(tester);
    await signInAs(tester, 'maria@example.ph');
    await goTo(tester, '/admin/settings?section=licenses');
    expect(find.textContaining('PCAB license expires in'), findsOneWidget);
  });

  testWidgets('admin reviews the audit log', (tester) async {
    await pumpApp(tester);
    await signInAs(tester, 'maria@example.ph');
    await goTo(tester, '/admin/audit-log');
    expect(find.text('Delivery confirmed'), findsOneWidget);
    // Money fields stay hidden from the admin.
    expect(find.textContaining('53650'), findsNothing);
    expect(find.textContaining('20000'), findsNothing);
    await tester.enterText(
      find.widgetWithText(TextField, 'Search action, person or detail'),
      'payment',
    );
    await tester.pumpAndSettle();
    expect(find.text('Supplier payment recorded'), findsOneWidget);
    expect(find.text('Delivery confirmed'), findsNothing);
  });

  group('admin module', () {
    Future<void> signInAdmin(WidgetTester tester) async {
      await pumpApp(tester);
      await signInAs(tester, 'maria@example.ph');
    }

    testWidgets('overview shows account health and recent activity', (
      tester,
    ) async {
      await signInAdmin(tester);
      expect(find.text('Dashboard'), findsWidgets);
      for (final tab in [
        'System',
        'Projects',
        'Finance',
        'Procurement',
        'People & Labor',
        'Activity',
      ]) {
        expect(find.text(tab), findsOneWidget, reason: tab);
      }
      expect(find.text('Active users'), findsOneWidget);
      expect(find.text('Active users by role'), findsOneWidget);
      expect(find.text('Latest changes'), findsOneWidget);
      // The System tab is about accounts: no money on it.
      expect(find.textContaining('₱'), findsNothing);
    });

    testWidgets('every dashboard tab opens without errors', (tester) async {
      await pumpApp(tester, size: const Size(1400, 2400));
      await signInAs(tester, 'maria@example.ph');
      for (final tab in [
        'projects',
        'finance',
        'procurement',
        'people',
        'activity',
      ]) {
        await goTo(tester, '/admin/overview?tab=$tab');
        expect(tester.takeException(), isNull, reason: tab);
        expect(
          find.textContaining('Could not load'),
          findsNothing,
          reason: tab,
        );
      }
    });

    testWidgets('finance tab shows figures read-only', (tester) async {
      await pumpApp(tester, size: const Size(1400, 2400));
      await signInAs(tester, 'maria@example.ph');
      await goTo(tester, '/admin/overview?tab=finance');
      expect(find.text('Billed to clients'), findsOneWidget);
      expect(find.textContaining('₱'), findsWidgets);
      expect(find.textContaining('Read-only'), findsOneWidget);
      expect(find.text('Record payment'), findsNothing);
      expect(find.text('Submit payment receipt'), findsNothing);
    });

    testWidgets('a client without a login opens a prefilled Add user', (
      tester,
    ) async {
      await signInAdmin(tester);
      await goTo(tester, '/admin/users/new?client=2');
      expect(
        find.widgetWithText(TextFormField, 'grace@tlc.example.ph'),
        findsOneWidget,
      );
    });

    testWidgets('users list sorts, filters by status and clears filters', (
      tester,
    ) async {
      await signInAdmin(tester);
      await goTo(tester, '/admin/users');
      expect(find.textContaining('accounts'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('status-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Inactive (').last);
      await tester.pumpAndSettle();
      expect(find.text('Clear filters'), findsWidgets);
      await tester.tap(find.text('Clear filters').first);
      await tester.pumpAndSettle();
      expect(find.text('Ramon Dela Cruz'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'liza');
      await tester.pumpAndSettle();
      expect(find.text('Liza Garcia'), findsOneWidget);
      expect(find.text('Ramon Dela Cruz'), findsNothing);
    });

    testWidgets('admin deactivates a user from the list row menu', (
      tester,
    ) async {
      await signInAdmin(tester);
      await goTo(tester, '/admin/users');
      await tester.enterText(find.byType(TextField).first, 'ana');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deactivate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deactivate').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('was deactivated'), findsOneWidget);
      final log = await getIt<AuditLogRepository>().getAll();
      expect(log.any((l) => l.action == 'user_deactivated'), isTrue);
    });

    testWidgets('a role link filters the users list', (tester) async {
      await signInAdmin(tester);
      await goTo(tester, '/admin/users?role=accountant');
      expect(find.text('Liza Garcia'), findsOneWidget);
      expect(find.text('Ramon Dela Cruz'), findsNothing);
    });

    testWidgets('admin deactivates and reactivates a user, and it is logged', (
      tester,
    ) async {
      await signInAdmin(tester);
      await goTo(tester, '/admin/users/4');
      expect(find.text('Ana Bautista'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Deactivate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deactivate').last);
      await tester.pumpAndSettle();
      expect(find.text('Inactive'), findsOneWidget);
      expect(find.text('User deactivated'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Reactivate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reactivate').last);
      await tester.pumpAndSettle();
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('User reactivated'), findsOneWidget);
    });

    testWidgets('admin resets a password and gets a temporary one', (
      tester,
    ) async {
      await signInAdmin(tester);
      await goTo(tester, '/admin/users/3');
      await tester.tap(find.widgetWithText(OutlinedButton, 'Reset password'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset password').last);
      await tester.pumpAndSettle();
      expect(find.text('Temporary password'), findsOneWidget);
      expect(find.text(MockData.demoPassword), findsOneWidget);
    });

    testWidgets('admin cannot deactivate their own account', (tester) async {
      await signInAdmin(tester);
      await goTo(tester, '/admin/users/1');
      final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Deactivate'),
      );
      expect(button.onPressed, isNull);
      expect(
        find.text('You cannot deactivate your own account.'),
        findsOneWidget,
      );
    });

    testWidgets('edit opens from the user page and returns to it', (
      tester,
    ) async {
      await signInAdmin(tester);
      await goTo(tester, '/admin/users/6');
      await tester.tap(find.text('Edit user'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Phone'),
        '0917 000 1111',
      );
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(find.text('0917 000 1111'), findsOneWidget);
      expect(find.text('User updated'), findsOneWidget);
    });

    testWidgets('roles page lists each role and its access', (tester) async {
      await signInAdmin(tester);
      await goTo(tester, '/admin/users');
      await tester.tap(find.byTooltip('Roles and permissions'));
      await tester.pumpAndSettle();
      expect(find.text('Roles and permissions'), findsWidgets);
      expect(find.text('Project manager'), findsWidgets);
      // The dialog opens on the admin role: finances, read-only.
      expect(find.text('Sees company finances (read-only)'), findsOneWidget);
    });

    test('settings changes are recorded in the audit log', () async {
      final session = getIt<SessionService>();
      final admin = (await getIt<UserRepository>().getUser(1))!;
      session.signIn(admin, [AppRole.admin]);
      final vm = SettingsViewModel(
        company: MockCompanyRepository(),
        audit: AdminAudit.fromLocator(),
      );
      await vm.load();
      expect(
        await vm.save(vm.settings!.copyWith(defaultRetentionPct: 5)),
        isNull,
      );
      final log = await getIt<AuditLogRepository>().getAll();
      expect(log.first.action, 'settings_updated');
      expect(log.first.userId, 1);
    });

    test('audit log filters by period and exports CSV', () async {
      final now = DateTime(2026, 10, 25, 12);
      final vm = AuditLogViewModel(
        auditLog: _FixedAuditLog([
          AuditLog(
            id: 1,
            userId: 1,
            action: 'user_updated',
            entity: 'user',
            entityId: 3,
            details: const {'name': 'Dela Cruz, Ramon'},
            createdAt: DateTime(2026, 10, 25, 9),
          ),
          AuditLog(
            id: 2,
            userId: 1,
            action: 'trade_created',
            entity: 'trade',
            entityId: 9,
            createdAt: DateTime(2026, 9, 1),
          ),
        ]),
        users: MockUserRepository(),
        now: () => now,
      );
      await vm.load();
      expect(vm.items, hasLength(2));
      vm.setPeriod(AuditPeriod.week);
      expect(vm.items.single.action, 'user_updated');
      expect(vm.itemsByDay.single.$1, DateTime(2026, 10, 25));
      final csv = vm.toCsv().split('\n');
      expect(csv.first, 'Date,Person,Action,Record,Record ID,Details');
      // Commas are quoted so the row stays intact in a spreadsheet.
      expect(csv[1], contains('"name=Dela Cruz, Ramon"'));
      vm.clearFilters();
      expect(vm.items, hasLength(2));
      expect(
        AuditLogViewModel.visibleDetails({'total': 53650, 'request_id': 2}),
        {'request_id': 2},
      );
    });
  });
}

/// Captures the user the form hands to the repository.
class _RecordingUserRepository extends MockUserRepository {
  User? lastSaved;

  @override
  Future<User> saveUser(User user, List<AppRole> roles) {
    lastSaved = user;
    return super.saveUser(user, roles);
  }
}

class _FixedAuditLog implements AuditLogRepository {
  _FixedAuditLog(this.logs);
  final List<AuditLog> logs;

  @override
  Future<List<AuditLog>> getAll() async => logs;

  @override
  Future<List<AuditLog>> getFor(String entity, int entityId) async => [];

  @override
  Future<AuditLog> record({
    required int userId,
    required String action,
    required String entity,
    required int entityId,
    Map<String, dynamic> details = const {},
  }) => throw UnimplementedError();
}

import 'package:buildpro_frontend/core/di/service_locator.dart';
import 'package:buildpro_frontend/data/models/app_role.dart';
import 'package:buildpro_frontend/data/models/audit_log.dart';
import 'package:buildpro_frontend/data/models/project.dart';
import 'package:buildpro_frontend/data/repositories/audit_log_repository.dart';
import 'package:buildpro_frontend/data/repositories/project_repository.dart';
import 'package:buildpro_frontend/data/repositories/user_repository.dart';
import 'package:buildpro_frontend/data/services/session_service.dart';
import 'package:buildpro_frontend/features/user_management/viewmodels/admin_dashboard/admin_activity_viewmodel.dart';
import 'package:buildpro_frontend/features/user_management/viewmodels/admin_dashboard/admin_finance_viewmodel.dart';
import 'package:buildpro_frontend/features/user_management/viewmodels/admin_dashboard/admin_people_viewmodel.dart';
import 'package:buildpro_frontend/features/user_management/viewmodels/admin_dashboard/admin_procurement_viewmodel.dart';
import 'package:buildpro_frontend/features/user_management/viewmodels/admin_dashboard/admin_projects_viewmodel.dart';
import 'package:buildpro_frontend/features/user_management/viewmodels/admin_dashboard/admin_system_viewmodel.dart';
import 'package:buildpro_frontend/features/user_management/viewmodels/users_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  setUp(() async {
    await resetServices();
    final admin = (await getIt<UserRepository>().getUser(1))!;
    getIt<SessionService>().signIn(admin, [AppRole.admin]);
  });

  test('admin sees finance but cannot manage it', () {
    expect(AppRole.admin.seesFinance, isTrue);
    expect(AppRole.admin.managesFinance, isFalse);
    expect(AppRole.owner.managesFinance, isTrue);
    expect(AppRole.accountant.managesFinance, isTrue);
    expect(AppRole.siteEngineer.seesFinance, isFalse);
    expect(AppRole.client.seesFinance, isFalse);
  });

  test(
    'system tab lists clients without a login with a prefill link',
    () async {
      final vm = AdminSystemViewModel(
        users: getIt(),
        clients: getIt(),
        projects: getIt(),
        auditLog: getIt(),
        company: getIt(),
      );
      await vm.load();
      expect(vm.error, isNull);
      expect(vm.activeUsers + vm.inactiveUsers, vm.totalUsers);
      final clientItems = vm.attention.where((a) => a.title.contains('portal'));
      expect(clientItems, isNotEmpty);
      expect(
        clientItems.every(
          (a) => a.path!.startsWith('/admin/users/new?client='),
        ),
        isTrue,
      );
      // Urgent items come first.
      final levels = vm.attention.map((a) => a.level.index).toList();
      expect(levels, [...levels]..sort());
    },
  );

  test('projects tab: stages add up and overdue means past target', () async {
    final vm = AdminProjectsViewModel(
      projects: getIt(),
      reports: getIt(),
      users: getIt(),
    );
    await vm.load();
    expect(vm.error, isNull);
    final total = ProjectStage.values.fold(0, (s, st) => s + vm.countIn(st));
    expect(total, vm.rows.length);
    expect(total, (await getIt<ProjectRepository>().getProjects()).length);
    for (final r in vm.overdue) {
      expect(r.daysLeft, lessThan(0));
      expect(r.project.status, ProjectStatus.ongoing);
    }
    expect(vm.openProjects.every((r) => r.stage != ProjectStage.done), isTrue);
  });

  test(
    'projects tab: a far-future clock makes every ongoing job overdue',
    () async {
      final vm = AdminProjectsViewModel(
        projects: getIt(),
        reports: getIt(),
        users: getIt(),
        now: () => DateTime(2100),
      );
      await vm.load();
      expect(vm.overdue.length, vm.countIn(ProjectStage.active));
      expect(vm.quietSites.length, vm.countIn(ProjectStage.active));
    },
  );

  test('finance tab: receivable is billed less collected', () async {
    final vm = AdminFinanceViewModel(
      projects: getIt(),
      billing: getIt(),
      procurement: getIt(),
      labor: getIt(),
    );
    await vm.load();
    expect(vm.error, isNull);
    expect(vm.billed, greaterThanOrEqualTo(0));
    expect(
      vm.receivable,
      closeTo((vm.billed - vm.collected).clamp(0, double.infinity), 0.01),
    );
    final perProject = vm.projectRows.fold<double>(0, (s, r) => s + r.billed);
    expect(perProject, closeTo(vm.billed, 0.01));
    final counted = vm.billingsByStatus.values.fold<int>(
      0,
      (s, v) => s + v.count,
    );
    expect(counted, greaterThanOrEqualTo(vm.disputed.length));
  });

  test('procurement tab loads and pending requests sort by need', () async {
    final vm = AdminProcurementViewModel(
      procurement: getIt(),
      projects: getIt(),
      users: getIt(),
    );
    await vm.load();
    expect(vm.error, isNull);
    final pending = vm.pendingRequests;
    for (var i = 1; i < pending.length; i++) {
      expect(pending[i - 1].neededBy.isAfter(pending[i].neededBy), isFalse);
    }
  });

  test('people tab: compliance is a share and sites are ongoing', () async {
    final vm = AdminPeopleViewModel(
      labor: getIt(),
      reports: getIt(),
      projects: getIt(),
      users: getIt(),
    );
    await vm.load();
    expect(vm.error, isNull);
    expect(vm.reportCompliance, inInclusiveRange(0, 1));
    for (final s in vm.sites) {
      expect(s.project.status, ProjectStatus.ongoing);
      expect(s.reportDays, lessThanOrEqualTo(s.workDays));
    }
  });

  test('activity tab buckets entries by day', () async {
    final now = DateTime(2026, 11, 17, 15);
    final vm = AdminActivityViewModel(
      auditLog: _Fixed([
        AuditLog(
          id: 1,
          userId: 1,
          action: 'a',
          entity: 'user',
          entityId: 1,
          details: const {},
          createdAt: DateTime(2026, 11, 17, 9),
        ),
        AuditLog(
          id: 2,
          userId: 3,
          action: 'a',
          entity: 'project',
          entityId: 1,
          details: const {},
          createdAt: DateTime(2026, 11, 15, 9),
        ),
        AuditLog(
          id: 3,
          userId: 3,
          action: 'b',
          entity: 'project',
          entityId: 2,
          details: const {},
          createdAt: DateTime(2026, 9, 1),
        ),
      ]),
      users: getIt(),
      now: () => now,
    );
    await vm.load();
    expect(vm.daily.length, AdminActivityViewModel.chartDays);
    expect(vm.daily.last.count, 1);
    expect(vm.todayCount, 1);
    expect(vm.weekCount, 2);
    expect(vm.monthCount, 2);
    expect(vm.byEntity.map((e) => e.key), containsAll(['user', 'project']));
    expect(vm.activeUsersThisWeek, 2);
  });

  test('users list sorts by column and flips direction', () async {
    final vm = UsersViewModel(users: getIt(), session: getIt());
    await vm.load();
    final names = vm.items.map((i) => i.user.fullName.toLowerCase()).toList();
    expect(names, [...names]..sort());
    vm.sortBy(UserSort.name);
    expect(vm.ascending, isFalse);
    final reversed = vm.items
        .map((i) => i.user.fullName.toLowerCase())
        .toList();
    expect(reversed, [...names.reversed]);
    vm.setStatusFilter(UserStatusFilter.inactive);
    expect(vm.items.every((i) => !i.user.isActive), isTrue);
    expect(vm.isFiltered, isTrue);
    vm.clearFilters();
    expect(vm.isFiltered, isFalse);
  });
}

class _Fixed implements AuditLogRepository {
  _Fixed(this.rows);
  final List<AuditLog> rows;

  @override
  Future<List<AuditLog>> getAll() async => rows;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

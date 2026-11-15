import 'package:buildpro_frontend/core/di/service_locator.dart';
import 'package:buildpro_frontend/core/network/api_config.dart';
import 'package:buildpro_frontend/data/models/app_role.dart';
import 'package:buildpro_frontend/data/models/attendance.dart';
import 'package:buildpro_frontend/data/models/worker.dart';
import 'package:buildpro_frontend/data/repositories/http_labor_repository.dart';
import 'package:buildpro_frontend/data/repositories/labor_repository.dart';
import 'package:buildpro_frontend/data/repositories/mock_labor_repository.dart';
import 'package:buildpro_frontend/data/services/business_rule_exception.dart';
import 'package:buildpro_frontend/features/labor/viewmodels/project_labor_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_api.dart';

// Wire shapes from the 4.1a build: a non-finance role gets the worker row
// without `daily_rate` or any government identifier — omitted, never zero.

Map<String, dynamic> workerRow({
  int id = 1,
  String name = 'Nilo Aguilar',
  bool finance = true,
  bool active = true,
}) => {
  'id': id,
  'full_name': name,
  'trade': 'Mason',
  if (finance) 'daily_rate': '750.00',
  if (finance) 'sss_no': '34-1234567-8',
  if (finance) 'philhealth_no': '12-345678901-2',
  if (finance) 'pagibig_no': '1234-5678-9012',
  'is_active': active,
  'created_at': '2026-10-01T09:00:00Z',
  'updated_at': '2026-10-01T09:00:00Z',
};

Map<String, dynamic> attendanceRow({
  int id = 1,
  int workerId = 1,
  String date = '2026-10-20',
  String status = 'present',
  String overtime = '0.00',
}) => {
  'id': id,
  'project_id': 1,
  'worker_id': workerId,
  'work_date': date,
  'status': status,
  'overtime_hours': overtime,
  'recorded_by': 4,
  'created_at': '2026-10-20T09:00:00Z',
  'updated_at': '2026-10-20T09:00:00Z',
};

HttpLaborRepository laborRepoFor(
  FakeApi api, {
  AppRole active = AppRole.owner,
}) => HttpLaborRepository(
  testClient(
    api: api,
    tokens: InMemoryTokenStore(access: testAccess, refresh: testRefresh),
    session: signedInSession(active: active),
  ),
);

void main() {
  group('workers', () {
    test('reads the staff picker and follows DRF pages', () async {
      final nextPageUrl = '$apiBaseUrl/workers/?page=2&active_only=true';
      final api = FakeApi((options) {
        final second = options.uri.queryParameters['page'] == '2';
        return json({
          'count': 2,
          'next': second ? null : nextPageUrl,
          'previous': null,
          'results': [workerRow(id: second ? 2 : 1)],
        });
      });

      final workers = await laborRepoFor(api).getWorkers(activeOnly: true);

      expect(api.last('workers/').method, 'GET');
      expect(api.last('workers/').uri.queryParameters['active_only'], 'true');
      expect(workers.map((w) => w.id), [1, 2]);
      expect(workers.first.dailyRate, 750);
      expect(workers.first.sssNo, '34-1234567-8');
      expect(workers.first.dailyRateHidden, isFalse);
    });

    test('asks for the full history when active_only is off', () async {
      final api = FakeApi((options) => json([workerRow(active: false)]));

      final workers = await laborRepoFor(api).getWorkers();

      expect(
        api.last('workers/').uri.queryParameters.containsKey('active_only'),
        isFalse,
      );
      expect(workers.single.isActive, isFalse);
    });

    test('a redacted answer has no wage, not a zero wage', () async {
      final api = FakeApi(
        (options) => json([workerRow(finance: false, name: 'Nilo Aguilar')]),
      );

      final worker = (await laborRepoFor(
        api,
        active: AppRole.siteEngineer,
      ).getWorkers()).single;

      expect(worker.fullName, 'Nilo Aguilar');
      expect(worker.trade, 'Mason');
      // The server withheld the money: zero would be a wage nobody quoted.
      expect(worker.dailyRateHidden, isTrue);
      expect(worker.dailyRate, 0);
      expect(worker.sssNo, isNull);
      expect(worker.philhealthNo, isNull);
      expect(worker.pagibigNo, isNull);
      // Sending it back must not invent a rate the server never gave.
      final sent = worker.toJson();
      expect(sent.containsKey('daily_rate'), isFalse);
      expect(sent.containsKey('sss_no'), isFalse);
    });

    test('a finance answer without the wage key is a parse error', () async {
      final row = workerRow()..remove('daily_rate');
      final api = FakeApi((options) => json([row]));

      // A finance role is always sent the rate; its absence is a broken
      // response, not a zero the screens may show.
      expect(
        laborRepoFor(api, active: AppRole.accountant).getWorkers(),
        throwsA(isA<FormatException>()),
      );
    });

    test('creates a worker with a trimmed name and the rate', () async {
      final api = FakeApi((options) => json(workerRow(), status: 201));

      final saved = await laborRepoFor(api).saveWorker(
        const Worker(
          id: 0,
          fullName: '  Nilo Aguilar ',
          trade: 'Mason',
          dailyRate: 750,
          sssNo: '34-1234567-8',
        ),
      );

      final request = api.last('workers/');
      expect(request.method, 'POST');
      final body = sentBody(request);
      expect(body['full_name'], 'Nilo Aguilar');
      expect(body['trade'], 'Mason');
      expect(body['daily_rate'], 750.0);
      expect(body['is_active'], isTrue);
      expect(body['sss_no'], '34-1234567-8');
      expect(body.containsKey('id'), isFalse);
      expect(saved.id, 1);
    });

    test('updates by PATCH, never PUT', () async {
      final api = FakeApi((options) => json(workerRow(id: 5)));

      await laborRepoFor(api).saveWorker(
        const Worker(
          id: 5,
          fullName: 'Nilo Aguilar',
          trade: 'Mason',
          dailyRate: 800,
        ),
      );

      final request = api.last('workers/5/');
      expect(request.method, 'PATCH');
      expect(sentBody(request)['daily_rate'], 800.0);
      expect(api.paths.where((p) => p == 'workers/5/').single, 'workers/5/');
    });

    test('keeps the server refusal text on a 400', () async {
      final api = FakeApi(
        (options) =>
            json({'detail': 'Choose the worker\'s trade.'}, status: 400),
      );

      expect(
        laborRepoFor(api, active: AppRole.accountant).saveWorker(
          const Worker(
            id: 0,
            fullName: 'Nilo Aguilar',
            trade: 'Carpenter',
            dailyRate: 750,
          ),
        ),
        throwsA(
          isA<BusinessRuleException>().having(
            (e) => e.message,
            'message',
            'Choose the worker\'s trade.',
          ),
        ),
      );
    });
  });

  group('attendance', () {
    test('reads one project over an inclusive date range', () async {
      // Attendance answers with a plain list, not a DRF page.
      final api = FakeApi(
        (options) => json([
          attendanceRow(id: 1, workerId: 1),
          attendanceRow(
            id: 2,
            workerId: 2,
            status: 'half_day',
            overtime: '2.50',
          ),
        ]),
      );

      final rows = await laborRepoFor(api, active: AppRole.siteEngineer)
          .getAttendance(
            projectId: 3,
            from: DateTime(2026, 10, 19),
            to: DateTime(2026, 10, 25),
          );

      final request = api.last('attendance/');
      expect(request.method, 'GET');
      expect(request.uri.queryParameters['project'], '3');
      expect(request.uri.queryParameters['from'], '2026-10-19');
      expect(request.uri.queryParameters['to'], '2026-10-25');
      expect(rows.map((a) => a.status), [
        AttendanceStatus.present,
        AttendanceStatus.halfDay,
      ]);
      expect(rows.last.overtimeHours, 2.5);
      expect(rows.first.recordedBy, 4);
      expect(rows.first.workDate, DateTime(2026, 10, 20));
    });

    test('saves a day without claiming the actor', () async {
      final api = FakeApi((options) => json([attendanceRow()]));

      await laborRepoFor(
        api,
        active: AppRole.siteEngineer,
      ).saveAttendance(3, DateTime(2026, 10, 21), const [
        (workerId: 1, status: AttendanceStatus.present, overtimeHours: 0.0),
        (workerId: 2, status: AttendanceStatus.absent, overtimeHours: 0.0),
      ], userId: 4);

      final request = api.last('attendance/save-day/');
      expect(request.method, 'POST');
      final body = sentBody(request);
      expect(body['project_id'], 3);
      expect(body['work_date'], '2026-10-21');
      expect(body['entries'], [
        {'worker_id': 1, 'status': 'present', 'overtime_hours': 0.0},
        {'worker_id': 2, 'status': 'absent', 'overtime_hours': 0.0},
      ]);
      expect(body.containsKey('recorded_by'), isFalse);
      expect(body.containsKey('user_id'), isFalse);
    });

    test('a cross-project refusal reaches the user unchanged', () async {
      final api = FakeApi(
        (options) => json({
          'detail':
              'Nilo Aguilar is already marked present on another '
              'project that day.',
        }, status: 400),
      );

      expect(
        laborRepoFor(api, active: AppRole.siteEngineer).saveAttendance(
          3,
          DateTime(2026, 10, 21),
          const [
            (workerId: 1, status: AttendanceStatus.present, overtimeHours: 0.0),
          ],
          userId: 4,
        ),
        throwsA(
          isA<BusinessRuleException>().having(
            (e) => e.message,
            'message',
            contains('already marked present on another project'),
          ),
        ),
      );
    });
  });

  group('payroll not available yet', () {
    test('every payroll method refuses instead of faking a ledger', () async {
      final api = FakeApi((options) => json(const <Object>[]));
      final repo = laborRepoFor(api, active: AppRole.accountant);
      final matcher = throwsA(
        isA<UnsupportedError>().having(
          (e) => e.message,
          'message',
          contains('Payroll periods are not available yet'),
        ),
      );

      expect(repo.supportsPayroll, isFalse);
      expect(repo.getPeriods(), matcher);
      expect(repo.getPeriod(1), matcher);
      expect(
        repo.createPeriod(
          1,
          DateTime(2026, 10, 1),
          DateTime(2026, 10, 15),
          userId: 3,
        ),
        matcher,
      );
      expect(repo.verifyPeriod(1, userId: 3), matcher);
      expect(repo.getLines(1), matcher);
      expect(repo.setCashAdvance(1, 1, 100, userId: 3), matcher);
      expect(repo.processPeriod(1, userId: 3), matcher);
      // Cost needs a processed period, so it names that instead.
      expect(
        repo.laborCost(1),
        throwsA(
          isA<UnsupportedError>().having(
            (e) => e.message,
            'message',
            contains('processed payroll'),
          ),
        ),
      );
      // Nothing was sent: a refused method never guesses at a route.
      expect(api.requests, isEmpty);
    });
  });

  group('the project labor tab on an API backend', () {
    test(
      'loads the site without a payroll figure and without hanging',
      () async {
        final api = FakeApi((options) {
          if (options.path == 'workers/') {
            return json([workerRow(finance: false)]);
          }
          if (options.path == 'attendance/') return json([attendanceRow()]);
          return json({'detail': 'Not found.'}, status: 404);
        });
        final vm = ProjectLaborViewModel(
          projectId: 1,
          labor: laborRepoFor(api, active: AppRole.siteEngineer),
        );

        await vm.load();

        expect(vm.isLoading, isFalse);
        expect(vm.error, isNull);
        expect(vm.workers.single.fullName, 'Nilo Aguilar');
        expect(vm.recentDays.single.present, 1);
        expect(vm.periods, isEmpty);
        expect(vm.laborCost, 0);
        expect(api.paths, ['attendance/', 'workers/']);
      },
    );
  });

  group('repository switch', () {
    test('mocks stay the default until USE_API is set', () async {
      expect(useApi, isFalse);
      setupServiceLocator();
      expect(getIt<LaborRepository>(), isA<MockLaborRepository>());
      expect(getIt<LaborRepository>().supportsPayroll, isTrue);
    });
  });
}

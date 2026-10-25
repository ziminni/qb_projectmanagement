import '../models/attendance.dart';
import '../models/payroll_period.dart';
import '../models/worker.dart';

/// Seed workers, generated attendance and payroll periods.
abstract final class MockLaborData {
  static const workers = [
    Worker(
      id: 1,
      fullName: 'Rodel Macaraig',
      trade: 'Mason',
      dailyRate: 750,
      sssNo: '34-1234561-1',
      philhealthNo: '12-345678901-1',
      pagibigNo: '1211-0000-0001',
    ),
    Worker(
      id: 2,
      fullName: 'Arnel Dimaano',
      trade: 'Mason',
      dailyRate: 750,
      sssNo: '34-1234562-2',
      philhealthNo: '12-345678902-2',
      pagibigNo: '1211-0000-0002',
    ),
    Worker(
      id: 3,
      fullName: 'Jun Villanueva',
      trade: 'Steelman',
      dailyRate: 750,
      sssNo: '34-1234563-3',
      philhealthNo: '12-345678903-3',
      pagibigNo: '1211-0000-0003',
    ),
    Worker(
      id: 4,
      fullName: 'Bong Perez',
      trade: 'Carpenter',
      dailyRate: 750,
      sssNo: '34-1234564-4',
      philhealthNo: '12-345678904-4',
      pagibigNo: '1211-0000-0004',
    ),
    Worker(
      id: 5,
      fullName: 'Leo Mercado',
      trade: 'Laborer',
      dailyRate: 610,
      sssNo: '34-1234565-5',
    ),
    Worker(
      id: 6,
      fullName: 'Dodong Castillo',
      trade: 'Laborer',
      dailyRate: 610,
      sssNo: '34-1234566-6',
    ),
    Worker(id: 7, fullName: 'Nilo Aguilar', trade: 'Laborer', dailyRate: 610),
    Worker(
      id: 8,
      fullName: 'Ramil Cruz',
      trade: 'Welder',
      dailyRate: 850,
      sssNo: '34-1234568-8',
      philhealthNo: '12-345678908-8',
    ),
    Worker(
      id: 9,
      fullName: 'Ernesto Lopez',
      trade: 'Welder',
      dailyRate: 850,
      sssNo: '34-1234569-9',
    ),
    Worker(id: 10, fullName: 'Toto Ramos', trade: 'Laborer', dailyRate: 610),
    Worker(
      id: 11,
      fullName: 'Pablo Garcia',
      trade: 'Electrician',
      dailyRate: 800,
      isActive: false,
    ),
  ];

  static final periods = [
    PayrollPeriod(
      id: 1,
      projectId: 1,
      periodStart: DateTime(2026, 10, 1),
      periodEnd: DateTime(2026, 10, 15),
      status: PayrollStatus.processed,
    ),
    PayrollPeriod(
      id: 2,
      projectId: 1,
      periodStart: DateTime(2026, 10, 16),
      periodEnd: DateTime(2026, 10, 31),
      status: PayrollStatus.open,
    ),
    PayrollPeriod(
      id: 3,
      projectId: 2,
      periodStart: DateTime(2026, 10, 12),
      periodEnd: DateTime(2026, 10, 18),
      status: PayrollStatus.open,
    ),
  ];

  /// Six-day weeks from Oct 1 to Oct 24, 2026: workers 1–7 on project 1 and
  /// 8–10 on project 2, with occasional absences, a rained-out half day on
  /// Oct 22 and Saturday overtime.
  static List<Attendance> attendance() {
    final rows = <Attendance>[];
    var id = 1;
    for (
      var d = DateTime(2026, 10, 1);
      !d.isAfter(DateTime(2026, 10, 24));
      d = d.add(const Duration(days: 1))
    ) {
      if (d.weekday == DateTime.sunday) continue;
      for (final (projectId, workerIds, recorder) in [
        (1, [1, 2, 3, 4, 5, 6, 7], 4),
        (2, [8, 9, 10], 8),
      ]) {
        for (final w in workerIds) {
          final absent = (d.day + w) % 11 == 0;
          final rainedOut = projectId == 1 && d.day == 22;
          rows.add(
            Attendance(
              id: id++,
              projectId: projectId,
              workerId: w,
              workDate: d,
              status: absent
                  ? AttendanceStatus.absent
                  : rainedOut
                  ? AttendanceStatus.halfDay
                  : AttendanceStatus.present,
              overtimeHours: !absent && d.weekday == DateTime.saturday && w <= 4
                  ? 2
                  : 0,
              recordedBy: recorder,
            ),
          );
        }
      }
    }
    return rows;
  }
}

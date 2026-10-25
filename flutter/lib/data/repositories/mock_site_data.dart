import '../models/daily_report.dart';
import '../models/equipment_log.dart';
import '../models/issue.dart';
import '../models/report_manpower.dart';
import '../models/report_material_usage.dart';
import '../models/report_photo.dart';

/// Seed daily reports for the last week on projects 1 and 2.
abstract final class MockSiteData {
  static final reports = [
    DailyReport(
      id: 1,
      projectId: 1,
      reportDate: DateTime(2026, 10, 19),
      weather: Weather.cloudy,
      status: DailyReportStatus.returned,
      submittedBy: 4,
      reviewedBy: 3,
      remarks:
          'Add photos of the column formworks and correct the cement count.',
      toolboxMeetingHeld: true,
    ),
    DailyReport(
      id: 2,
      projectId: 1,
      reportDate: DateTime(2026, 10, 20),
      weather: Weather.sunny,
      status: DailyReportStatus.approved,
      submittedBy: 4,
      reviewedBy: 3,
      toolboxMeetingHeld: true,
    ),
    DailyReport(
      id: 3,
      projectId: 1,
      reportDate: DateTime(2026, 10, 21),
      weather: Weather.lightRain,
      status: DailyReportStatus.approved,
      submittedBy: 4,
      reviewedBy: 3,
      toolboxMeetingHeld: true,
    ),
    DailyReport(
      id: 4,
      projectId: 1,
      reportDate: DateTime(2026, 10, 22),
      weather: Weather.heavyRain,
      status: DailyReportStatus.approved,
      submittedBy: 4,
      reviewedBy: 3,
    ),
    DailyReport(
      id: 5,
      projectId: 1,
      reportDate: DateTime(2026, 10, 23),
      weather: Weather.sunny,
      status: DailyReportStatus.approved,
      submittedBy: 4,
      reviewedBy: 3,
      toolboxMeetingHeld: true,
    ),
    DailyReport(
      id: 6,
      projectId: 1,
      reportDate: DateTime(2026, 10, 24),
      weather: Weather.sunny,
      status: DailyReportStatus.submitted,
      submittedBy: 4,
      toolboxMeetingHeld: true,
    ),
    DailyReport(
      id: 7,
      projectId: 2,
      reportDate: DateTime(2026, 10, 23),
      weather: Weather.cloudy,
      status: DailyReportStatus.approved,
      submittedBy: 8,
      reviewedBy: 3,
      toolboxMeetingHeld: true,
    ),
  ];

  static const manpower = [
    ReportManpower(id: 1, dailyReportId: 1, trade: 'Mason', headcount: 3),
    ReportManpower(id: 2, dailyReportId: 1, trade: 'Laborer', headcount: 5),
    ReportManpower(id: 3, dailyReportId: 2, trade: 'Mason', headcount: 4),
    ReportManpower(id: 4, dailyReportId: 2, trade: 'Steelman', headcount: 3),
    ReportManpower(id: 5, dailyReportId: 2, trade: 'Laborer', headcount: 6),
    ReportManpower(id: 6, dailyReportId: 3, trade: 'Steelman', headcount: 3),
    ReportManpower(id: 7, dailyReportId: 3, trade: 'Laborer', headcount: 4),
    ReportManpower(id: 8, dailyReportId: 4, trade: 'Laborer', headcount: 2),
    ReportManpower(id: 9, dailyReportId: 5, trade: 'Steelman', headcount: 4),
    ReportManpower(id: 10, dailyReportId: 5, trade: 'Carpenter', headcount: 3),
    ReportManpower(id: 11, dailyReportId: 5, trade: 'Laborer', headcount: 6),
    ReportManpower(id: 12, dailyReportId: 6, trade: 'Carpenter', headcount: 4),
    ReportManpower(id: 13, dailyReportId: 6, trade: 'Laborer', headcount: 5),
    ReportManpower(id: 14, dailyReportId: 7, trade: 'Welder', headcount: 3),
    ReportManpower(id: 15, dailyReportId: 7, trade: 'Laborer', headcount: 4),
  ];

  static const materials = [
    ReportMaterialUsage(id: 1, dailyReportId: 2, materialId: 1, quantity: 30),
    ReportMaterialUsage(id: 2, dailyReportId: 2, materialId: 2, quantity: 40),
    ReportMaterialUsage(id: 3, dailyReportId: 3, materialId: 1, quantity: 20),
    ReportMaterialUsage(id: 4, dailyReportId: 5, materialId: 9, quantity: 15),
    ReportMaterialUsage(id: 5, dailyReportId: 5, materialId: 3, quantity: 60),
    ReportMaterialUsage(id: 6, dailyReportId: 6, materialId: 7, quantity: 12),
  ];

  static final equipmentLogs = [
    EquipmentLog(
      id: 1,
      equipmentId: 1,
      projectId: 1,
      logDate: DateTime(2026, 10, 20),
      hoursUsed: 8,
      dailyReportId: 2,
    ),
    EquipmentLog(
      id: 2,
      equipmentId: 3,
      projectId: 1,
      logDate: DateTime(2026, 10, 23),
      hoursUsed: 6,
      dailyReportId: 5,
    ),
    EquipmentLog(
      id: 3,
      equipmentId: 4,
      projectId: 2,
      logDate: DateTime(2026, 10, 23),
      hoursUsed: 5,
      dailyReportId: 7,
    ),
  ];

  static const issues = [
    Issue(
      id: 1,
      projectId: 1,
      dailyReportId: 3,
      type: IssueType.delay,
      reason: IssueReason.rainTyphoon,
      description: 'Rain from 1 PM; stopped rebar work for the afternoon.',
      daysLost: 0.5,
    ),
    Issue(
      id: 2,
      projectId: 1,
      dailyReportId: 4,
      type: IssueType.delay,
      reason: IssueReason.rainTyphoon,
      description: 'Heavy rain all day under a typhoon signal; site secured.',
      daysLost: 1,
    ),
  ];

  static final photos = [
    ReportPhoto(
      id: 1,
      dailyReportId: 2,
      fileUrl: 'mock://photos/1',
      caption: 'Ground-floor columns stripped',
      takenAt: DateTime(2026, 10, 20, 15),
    ),
    ReportPhoto(
      id: 2,
      dailyReportId: 2,
      fileUrl: 'mock://photos/2',
      caption: 'Rebar delivery stacked on pallets',
      takenAt: DateTime(2026, 10, 20, 9),
    ),
    ReportPhoto(
      id: 3,
      dailyReportId: 5,
      fileUrl: 'mock://photos/3',
      caption: 'Second-floor column cages',
      takenAt: DateTime(2026, 10, 23, 14),
    ),
    ReportPhoto(
      id: 4,
      dailyReportId: 6,
      fileUrl: 'mock://photos/4',
      caption: 'Formworks for second-floor columns',
      takenAt: DateTime(2026, 10, 24, 16),
    ),
    ReportPhoto(
      id: 5,
      dailyReportId: 7,
      fileUrl: 'mock://photos/5',
      caption: 'Steel columns erected, grid A',
      takenAt: DateTime(2026, 10, 23, 11),
    ),
  ];
}

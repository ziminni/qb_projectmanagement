import 'dart:typed_data';

import '../models/daily_report.dart';
import '../models/equipment_log.dart';
import '../models/issue.dart';
import '../models/report_manpower.dart';
import '../models/report_material_usage.dart';
import '../models/report_photo.dart';
import '../models/todo.dart';
import '../services/business_rule_exception.dart';

/// A report with everything recorded on it.
class DailyReportDetail {
  const DailyReportDetail({
    required this.report,
    required this.manpower,
    required this.materials,
    required this.equipment,
    required this.issues,
    required this.photos,
    required this.todos,
  });

  final DailyReport report;
  final List<ReportManpower> manpower;
  final List<ReportMaterialUsage> materials;
  final List<EquipmentLog> equipment;
  final List<Issue> issues;
  final List<ReportPhoto> photos;

  /// To-dos accomplished on this report (linked by `daily_report_id`).
  final List<Todo> todos;

  int get totalHeadcount => manpower.fold(0, (s, m) => s + m.headcount);
}

/// The draft itself was stored but a photo upload failed; [saved] is that
/// report, so a retry updates it instead of creating a second one.
class DailyReportSaveException extends BusinessRuleException {
  const DailyReportSaveException(
    super.message,
    this.saved, {
    required this.photos,
    this.uncertain = false,
  });

  final DailyReport saved;

  /// The draft's photos carrying the id of every photo the save stored. A
  /// retry sends this list back: the server deletes the photos a draft omits.
  final List<PhotoDraft> photos;

  /// A photo upload failed in a way that may still have reached the server,
  /// so the report's photos must be read back before saving again.
  final bool uncertain;
}

/// A saved draft with its photos, each one the server confirmed carrying the
/// id the next save must send back.
typedef SavedDraft = ({DailyReport report, List<PhotoDraft> photos});

class IssueDraft {
  const IssueDraft({
    required this.type,
    required this.reason,
    required this.description,
    this.daysLost = 0,
  });

  final IssueType type;
  final IssueReason reason;
  final String description;
  final double daysLost;
}

class PhotoDraft {
  const PhotoDraft({
    this.id,
    this.fileUrl,
    this.caption,
    this.latitude,
    this.longitude,
    this.takenAt,
    this.bytes,
  });

  /// Set for a photo already stored on the server; a draft keeps it by id.
  final int? id;

  /// The stored photo's URL, when it has one.
  final String? fileUrl;
  final String? caption;
  final double? latitude;
  final double? longitude;
  final DateTime? takenAt;

  /// A new photo's content: the server stores bytes, not a file name.
  final Uint8List? bytes;
}

/// What the site engineer fills in. Saving replaces the report's child rows.
class DailyReportDraft {
  const DailyReportDraft({
    this.id,
    required this.projectId,
    required this.reportDate,
    required this.weather,
    this.toolboxMeetingHeld = false,
    this.manpower = const [],
    this.materials = const [],
    this.equipment = const [],
    this.issues = const [],
    this.photos = const [],
    this.todoIds = const [],
  });

  final int? id;
  final int projectId;
  final DateTime reportDate;
  final Weather weather;
  final bool toolboxMeetingHeld;
  final List<({String trade, int headcount})> manpower;
  final List<({int materialId, double quantity})> materials;
  final List<({int equipmentId, double hours})> equipment;
  final List<IssueDraft> issues;
  final List<PhotoDraft> photos;
  final List<int> todoIds;
}

abstract interface class DailyReportRepository {
  /// Newest first.
  Future<List<DailyReport>> getReports({
    List<int>? projectIds,
    DailyReportStatus? status,
    DateTime? from,
    DateTime? to,
  });

  Future<DailyReportDetail?> getDetail(int id);

  /// Creates or updates a Draft (or Returned) report.
  Future<SavedDraft> saveDraft(DailyReportDraft draft, {required int userId});

  /// Sends the report to the PM and marks its to-dos done.
  Future<DailyReport> submit(int id, {required int userId});

  /// PM approval: the report's to-dos become verified and its material use
  /// is deducted from site inventory.
  Future<DailyReport> approve(int id, {required int userId});

  Future<DailyReport> returnReport(
    int id, {
    required int userId,
    required String remarks,
  });

  /// Material used on approved reports; site inventory subtracts this.
  Future<List<ReportMaterialUsage>> getApprovedMaterialUsage(int projectId);

  /// Equipment used on approved reports.
  Future<List<EquipmentLog>> getApprovedEquipmentLogs(int projectId);

  /// Photos from approved reports, newest first.
  Future<List<({ReportPhoto photo, DailyReport report})>> getApprovedPhotos(
    List<int> projectIds,
  );
}

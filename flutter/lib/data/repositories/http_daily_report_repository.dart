import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../models/daily_report.dart';
import '../models/equipment_log.dart';
import '../models/issue.dart';
import '../models/json_utils.dart';
import '../models/report_manpower.dart';
import '../models/report_material_usage.dart';
import '../models/report_photo.dart';
import '../models/todo.dart';
import '../services/business_rule_exception.dart';
import 'daily_report_repository.dart';

/// Daily reports, against the CPMS backend.
///
/// Every rule (ongoing project, the assigned engineer, one report per date,
/// the author-only edit, to-do linking, the to-do side effects of submit and
/// approve) is enforced inside the server's save/submit/approve calls, so a
/// refusal arrives as the server's own `detail` text and surfaces unchanged.
/// The `userId`s in the interface are never sent as a claim: the server
/// answers for the caller.
class HttpDailyReportRepository implements DailyReportRepository {
  HttpDailyReportRepository(this._client);

  final ApiClient _client;

  static String _date(DateTime d) => JsonUtils.fromDate(d);

  @override
  Future<List<DailyReport>> getReports({
    List<int>? projectIds,
    DailyReportStatus? status,
    DateTime? from,
    DateTime? to,
  }) async => [
    for (final row in await _client.getRows(
      'daily-reports/',
      query: {
        if (projectIds != null && projectIds.isNotEmpty)
          'project': projectIds.join(','),
        if (status != null) 'status': status.apiValue,
        if (from != null) 'from': _date(from),
        if (to != null) 'to': _date(to),
      },
    ))
      DailyReport.fromJson(row),
  ];

  @override
  Future<DailyReportDetail?> getDetail(int id) async {
    final data = await _client.get('daily-reports/$id/', notFoundAsNull: true);
    if (data == null) return null;
    final detail = jsonObject(data);
    List<Map<String, dynamic>> rows(String key) => [
      for (final row in (detail[key] as List<dynamic>? ?? const []))
        (row as Map).cast<String, dynamic>(),
    ];
    return DailyReportDetail(
      report: DailyReport.fromJson(jsonObject(detail['report'])),
      manpower: [
        for (final row in rows('manpower')) ReportManpower.fromJson(row),
      ],
      materials: [
        for (final row in rows('materials')) ReportMaterialUsage.fromJson(row),
      ],
      equipment: [
        for (final row in rows('equipment')) EquipmentLog.fromJson(row),
      ],
      issues: [for (final row in rows('issues')) Issue.fromJson(row)],
      photos: [for (final row in rows('photos')) ReportPhoto.fromJson(row)],
      todos: [for (final row in rows('todos')) Todo.fromJson(row)],
    );
  }

  /// Saves the draft, then uploads any photo that has bytes and no id yet:
  /// the server's photo route needs the report, and a kept photo moves by id.
  /// The ids the uploads confirm come back with the report, so the next save
  /// sends them back — the server deletes every photo a draft's list omits.
  @override
  Future<SavedDraft> saveDraft(
    DailyReportDraft draft, {
    required int userId,
  }) async {
    final body = {
      'project_id': draft.projectId,
      'report_date': _date(draft.reportDate),
      'weather': draft.weather.apiValue,
      'toolbox_meeting_held': draft.toolboxMeetingHeld,
      'manpower': [
        for (final m in draft.manpower)
          {'trade': m.trade.trim(), 'headcount': m.headcount},
      ],
      'materials': [
        for (final m in draft.materials)
          {'material_id': m.materialId, 'quantity': m.quantity},
      ],
      'equipment': [
        for (final e in draft.equipment)
          {'equipment_id': e.equipmentId, 'hours_used': e.hours},
      ],
      'issues': [
        for (final x in draft.issues)
          {
            'type': x.type.apiValue,
            'reason': x.reason.apiValue,
            'description': x.description.trim(),
            'days_lost': x.daysLost,
          },
      ],
      'photos': [
        for (final p in draft.photos)
          if (p.id != null)
            {
              'id': p.id,
              'caption': p.caption,
              'latitude': p.latitude,
              'longitude': p.longitude,
              'taken_at': JsonUtils.fromDateTimeOrNull(p.takenAt),
            },
      ],
      'todo_ids': draft.todoIds,
    };
    final data = await (draft.id == null
        ? _client.post('daily-reports/', body: body)
        : _client.put('daily-reports/${draft.id}/', body: body));
    final report = DailyReport.fromJson(jsonObject(data));
    final photos = [...draft.photos];
    for (var i = 0; i < photos.length; i++) {
      final photo = photos[i];
      if (photo.id != null || photo.bytes == null) continue;
      try {
        photos[i] = _withServerId(
          photo,
          await _uploadPhoto(report.id, photo.bytes!, photo),
        );
      } catch (error) {
        // The draft itself is stored: a retry updates it, then resumes here.
        // The failed upload may still have landed, so say so and hand back the
        // ids already stored instead of letting a retry delete them.
        final reason = error is BusinessRuleException
            ? ' ${error.message}'
            : '';
        throw DailyReportSaveException(
          'The report was saved, but a photo did not finish uploading.$reason '
          "It may already be on the server, so check the report's photos "
          'before saving again.',
          report,
          photos: photos,
          uncertain: true,
        );
      }
    }
    return (report: report, photos: photos);
  }

  /// The draft photo after the server stored it: the id is what keeps it
  /// alive on the next save, the bytes are kept so a retry needs no re-read.
  static PhotoDraft _withServerId(PhotoDraft draft, ReportPhoto stored) =>
      PhotoDraft(
        id: stored.id,
        fileUrl: stored.fileUrl,
        caption: draft.caption,
        latitude: draft.latitude,
        longitude: draft.longitude,
        takenAt: draft.takenAt,
        bytes: draft.bytes,
      );

  Future<ReportPhoto> _uploadPhoto(
    int reportId,
    Uint8List bytes,
    PhotoDraft draft,
  ) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: _photoName(bytes)),
      if (draft.caption != null) 'caption': draft.caption,
      if (draft.latitude != null) 'latitude': draft.latitude,
      if (draft.longitude != null) 'longitude': draft.longitude,
      if (draft.takenAt != null)
        'taken_at': JsonUtils.fromDateTime(draft.takenAt!),
    });
    return ReportPhoto.fromJson(
      jsonObject(
        await _client.post('daily-reports/$reportId/photos/', body: form),
      ),
    );
  }

  /// The server checks jpg/jpeg/png/webp by content, so the name follows the
  /// bytes (a WebP named `.jpg` is refused as "does not look like a jpg file").
  static String _photoName(Uint8List bytes) {
    if (bytes.length > 3 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'photo.png';
    }
    // WebP is a RIFF container with `WEBP` at byte 8, exactly like the server.
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'photo.webp';
    }
    return 'photo.jpg';
  }

  @override
  Future<DailyReport> submit(int id, {required int userId}) async =>
      DailyReport.fromJson(
        jsonObject(await _client.post('daily-reports/$id/submit/')),
      );

  @override
  Future<DailyReport> approve(int id, {required int userId}) async =>
      DailyReport.fromJson(
        jsonObject(await _client.post('daily-reports/$id/approve/')),
      );

  @override
  Future<DailyReport> returnReport(
    int id, {
    required int userId,
    required String remarks,
  }) async => DailyReport.fromJson(
    jsonObject(
      await _client.post(
        'daily-reports/$id/return/',
        body: {'remarks': remarks.trim()},
      ),
    ),
  );

  @override
  Future<List<ReportMaterialUsage>> getApprovedMaterialUsage(
    int projectId,
  ) async => [
    for (final row in await _client.getRows(
      'projects/$projectId/approved-material-usage/',
    ))
      ReportMaterialUsage.fromJson(row),
  ];

  @override
  Future<List<EquipmentLog>> getApprovedEquipmentLogs(int projectId) async => [
    for (final row in await _client.getRows(
      'projects/$projectId/approved-equipment-logs/',
    ))
      EquipmentLog.fromJson(row),
  ];

  @override
  Future<List<({ReportPhoto photo, DailyReport report})>> getApprovedPhotos(
    List<int> projectIds,
  ) async => [
    for (final row in await _client.getRows(
      'report-photos/approved/',
      query: {if (projectIds.isNotEmpty) 'project': projectIds.join(',')},
    ))
      (
        photo: ReportPhoto.fromJson(jsonObject(row['photo'])),
        report: DailyReport.fromJson(jsonObject(row['report'])),
      ),
  ];
}

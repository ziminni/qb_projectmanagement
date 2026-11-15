import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../shared/widgets/app_quantity_rows_editor.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/daily_report.dart';
import '../../../data/models/equipment.dart';
import '../../../data/models/material_item.dart';
import '../../../data/models/project.dart';
import '../../../data/models/todo.dart';
import '../../../data/models/trade.dart';
import '../../../data/repositories/daily_report_repository.dart';
import '../../../data/repositories/master_data_repository.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/repositories/schedule_repository.dart';
import '../../../data/services/business_rule_exception.dart';
import '../../../data/services/session_service.dart';

class ManpowerRow {
  ManpowerRow({this.trade, this.headcount = 1});

  String? trade;
  int headcount;
}

/// New or edited daily report. Saving keeps it as a Draft; submitting sends
/// it to the PM and marks the chosen to-dos done.
class DailyReportFormViewModel extends ChangeNotifier with ActionRunner {
  DailyReportFormViewModel({
    this.reportId,
    this.initialProjectId,
    required SessionService session,
    required ProjectRepository projects,
    required DailyReportRepository reports,
    required ScheduleRepository schedule,
    required MasterDataRepository masterData,
  }) : _session = session,
       _projects = projects,
       _reports = reports,
       _schedule = schedule,
       _masterData = masterData;

  final int? reportId;
  final int? initialProjectId;
  final SessionService _session;
  final ProjectRepository _projects;
  final DailyReportRepository _reports;
  final ScheduleRepository _schedule;
  final MasterDataRepository _masterData;

  bool _loading = true;
  String? _error;
  List<Project> _projectOptions = const [];
  List<Trade> trades = const [];
  List<MaterialItem> materials = const [];
  List<Equipment> equipment = const [];
  List<Todo> _todoOptions = const [];
  int? _savedId;

  // Form state.
  int? projectId;
  DateTime reportDate = DateTime.now();
  Weather weather = Weather.sunny;
  bool toolboxMeetingHeld = false;
  final manpower = <ManpowerRow>[];
  final materialRows = <AppQuantityRow>[];
  final equipmentRows = <AppQuantityRow>[];
  final issues = <IssueDraft>[];
  final photos = <PhotoDraft>[];
  final todoIds = <int>{};
  String? remarks;

  /// A saved photo upload failed without telling the client whether it
  /// landed, so the report's photos must be read back before the next save.
  bool _photosUncertain = false;

  bool get isLoading => _loading;
  String? get error => _error;
  bool get isNew => reportId == null;
  List<Project> get projectOptions => _projectOptions;

  /// Open to-dos plus those already on this report.
  List<Todo> get todoOptions => _todoOptions;
  int? get savedId => _savedId;

  Future<void> load() async {
    try {
      trades = await _masterData.getTrades();
      materials = await _masterData.getMaterials();
      equipment = await _masterData.getEquipment();
      _projectOptions = (await _projects.getProjectsFor(
        _session.user!.id,
        AppRole.siteEngineer,
      )).where((p) => p.status == ProjectStatus.ongoing).toList();

      if (reportId != null) {
        final detail = await _reports.getDetail(reportId!);
        if (detail == null) {
          _error = 'Report not found.';
          return;
        }
        final r = detail.report;
        if (!r.status.isEditable) {
          _error = 'This report is ${r.status.label.toLowerCase()} and locked.';
          return;
        }
        projectId = r.projectId;
        reportDate = r.reportDate;
        weather = r.weather;
        toolboxMeetingHeld = r.toolboxMeetingHeld;
        remarks = r.remarks;
        manpower.addAll([
          for (final m in detail.manpower)
            ManpowerRow(trade: m.trade, headcount: m.headcount),
        ]);
        materialRows.addAll([
          for (final m in detail.materials)
            AppQuantityRow(itemId: m.materialId, quantity: m.quantity),
        ]);
        equipmentRows.addAll([
          for (final e in detail.equipment)
            AppQuantityRow(itemId: e.equipmentId, quantity: e.hoursUsed),
        ]);
        issues.addAll([
          for (final x in detail.issues)
            IssueDraft(
              type: x.type,
              reason: x.reason,
              description: x.description,
              daysLost: x.daysLost,
            ),
        ]);
        photos.addAll([
          for (final p in detail.photos)
            PhotoDraft(
              // A stored photo is kept by id; the server owns its file.
              id: p.id,
              fileUrl: p.fileUrl,
              caption: p.caption,
              latitude: p.latitude,
              longitude: p.longitude,
              takenAt: p.takenAt,
            ),
        ]);
        todoIds.addAll(detail.todos.map((t) => t.id));
      } else {
        projectId = _projectOptions.any((p) => p.id == initialProjectId)
            ? initialProjectId
            : (_projectOptions.length == 1 ? _projectOptions.first.id : null);
        if (_projectOptions.isEmpty) {
          _error = 'You have no ongoing site to report on.';
          return;
        }
        // Most reports list at least one trade; start with an empty row.
        manpower.add(ManpowerRow());
      }
      await _loadTodos();
    } catch (e) {
      _error = 'Could not load the form. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _loadTodos() async {
    if (projectId == null) {
      _todoOptions = const [];
      return;
    }
    final all = await _schedule.getTodos(projectId!);
    _todoOptions =
        all
            .where(
              (t) =>
                  !t.isDone ||
                  (reportId != null && t.dailyReportId == reportId),
            )
            .toList()
          ..sort((a, b) => a.startDate.compareTo(b.startDate));
  }

  Future<void> setProject(int? id) async {
    projectId = id;
    todoIds.clear();
    await _loadTodos();
    notifyListeners();
  }

  void setDate(DateTime date) {
    reportDate = date;
    notifyListeners();
  }

  void setWeather(Weather w) {
    weather = w;
    notifyListeners();
  }

  void setToolbox(bool v) {
    toolboxMeetingHeld = v;
    notifyListeners();
  }

  void toggleTodo(int id, bool selected) {
    selected ? todoIds.add(id) : todoIds.remove(id);
    notifyListeners();
  }

  /// Notifies after a row in one of the editable lists changed.
  void changed() => notifyListeners();

  Future<String?> save({required bool submit}) => runAction(() async {
    if (projectId == null) {
      throw const BusinessRuleException('Choose the project.');
    }
    if (manpower.any((m) => m.trade == null) ||
        materialRows.any((m) => m.itemId == null) ||
        equipmentRows.any((e) => e.itemId == null)) {
      throw const BusinessRuleException(
        'Complete or remove the empty rows before saving.',
      );
    }
    final userId = _session.user!.id;
    if (_photosUncertain) await _reconcilePhotos();
    final SavedDraft saved;
    try {
      saved = await _reports.saveDraft(
        DailyReportDraft(
          // After a save that failed on a photo, the draft is already stored:
          // the retry updates it instead of creating a second one.
          id: _savedId ?? reportId,
          projectId: projectId!,
          reportDate: reportDate,
          weather: weather,
          toolboxMeetingHeld: toolboxMeetingHeld,
          manpower: [
            for (final m in manpower) (trade: m.trade!, headcount: m.headcount),
          ],
          materials: [
            for (final m in materialRows)
              (materialId: m.itemId!, quantity: m.quantity),
          ],
          equipment: [
            for (final e in equipmentRows)
              (equipmentId: e.itemId!, hours: e.quantity),
          ],
          issues: issues,
          photos: photos,
          todoIds: todoIds.toList(),
        ),
        userId: userId,
      );
    } on DailyReportSaveException catch (error) {
      _savedId = error.saved.id;
      // Keep the ids the save confirmed: the next PUT deletes every photo it
      // does not carry, so a retry must send the stored ones back.
      photos
        ..clear()
        ..addAll(error.photos);
      _photosUncertain = error.uncertain;
      rethrow;
    }
    // A later save of this form sends these ids back instead of re-uploading
    // and, by omitting them, deleting the photos the server now holds.
    photos
      ..clear()
      ..addAll(saved.photos);
    _photosUncertain = false;
    _savedId = saved.report.id;
    if (submit) await _reports.submit(saved.report.id, userId: userId);
  });

  /// Adds the photos the server holds that this form has never seen, by id.
  /// Never by caption or capture time: two different photos share both.
  Future<void> _reconcilePhotos() async {
    final id = _savedId;
    if (id == null) return;
    final detail = await _reports.getDetail(id);
    if (detail == null) return;
    final known = {for (final p in photos) p.id};
    photos.addAll([
      for (final p in detail.photos)
        if (!known.contains(p.id))
          PhotoDraft(
            id: p.id,
            fileUrl: p.fileUrl,
            caption: p.caption,
            latitude: p.latitude,
            longitude: p.longitude,
            takenAt: p.takenAt,
          ),
    ]);
    _photosUncertain = false;
  }
}

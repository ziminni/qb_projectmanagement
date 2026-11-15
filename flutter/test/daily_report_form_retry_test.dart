import 'dart:typed_data';

import 'package:buildpro_frontend/core/di/service_locator.dart';
import 'package:buildpro_frontend/data/models/app_role.dart';
import 'package:buildpro_frontend/data/repositories/daily_report_repository.dart';
import 'package:buildpro_frontend/data/repositories/http_daily_report_repository.dart';
import 'package:buildpro_frontend/features/daily_reports/viewmodels/daily_report_form_viewmodel.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'network/fake_api.dart';
import 'test_helpers.dart';

/// The report backend's photo rules, the way `site_reports.services` has
/// them: a draft save deletes every stored photo its `photos` list omits, and
/// each upload stores a new row with a fresh id.
class _Backend {
  _Backend({
    Map<String, int> failures = const {},
    Map<String, int> lostAnswers = const {},
  }) : _failures = {...failures},
       _lostAnswers = {...lostAnswers};

  /// Caption → uploads refused before anything is stored.
  final Map<String, int> _failures;

  /// Caption → uploads stored and then answered 500: the client never learns
  /// the photo landed.
  final Map<String, int> _lostAnswers;

  static const reportId = 9;
  final stored = <Map<String, dynamic>>[];
  final uploads = <String>[];
  final deleted = <int>[];
  int _nextId = 20;

  static Map<String, dynamic> _photo(int id, String? caption) => {
    'id': id,
    'daily_report_id': reportId,
    'file_url': 'https://cpms.example.ph/api/v1/report-photos/$id/file/p.jpg',
    'caption': caption,
    'latitude': null,
    'longitude': null,
    'taken_at': '2026-10-20T09:30:00Z',
    'created_at': '2026-10-20T09:30:00Z',
    'updated_at': '2026-10-20T09:30:00Z',
  };

  static Map<String, dynamic> get _report => {
    'id': reportId,
    'project_id': 1,
    'report_date': '2026-10-20',
    'weather': 'sunny',
    'status': 'draft',
    'submitted_by': 7,
    'reviewed_by': null,
    'remarks': null,
    'toolbox_meeting_held': false,
    'created_at': '2026-10-20T09:00:00Z',
    'updated_at': '2026-10-20T09:00:00Z',
  };

  static ResponseBody get _serverError => json({
    'detail': 'The server could not complete the request. Try again.',
  }, status: 500);

  ResponseBody handle(RequestOptions options) {
    final path = options.path;
    if (path == 'daily-reports/$reportId/photos/') {
      final form = options.data as FormData;
      final caption = form.fields.firstWhere((f) => f.key == 'caption').value;
      uploads.add(caption);
      if ((_failures[caption] ?? 0) > 0) {
        _failures[caption] = _failures[caption]! - 1;
        return _serverError;
      }
      final row = _photo(_nextId++, caption);
      stored.add(row);
      if ((_lostAnswers[caption] ?? 0) > 0) {
        _lostAnswers[caption] = _lostAnswers[caption]! - 1;
        return _serverError;
      }
      return json(row, status: 201);
    }
    if (path == 'daily-reports/' && options.method == 'POST') {
      return json(_report, status: 201);
    }
    if (path == 'daily-reports/$reportId/' && options.method == 'GET') {
      return json({
        'report': _report,
        'manpower': <Object>[],
        'materials': <Object>[],
        'equipment': <Object>[],
        'issues': <Object>[],
        'photos': stored,
        'todos': <Object>[],
      });
    }
    if (path == 'daily-reports/$reportId/' && options.method == 'PUT') {
      final keep = [
        for (final row in (sentBody(options)['photos'] as List))
          ((row as Map)['id'] as num).toInt(),
      ];
      for (final row in [...stored]) {
        if (!keep.contains(row['id'])) {
          deleted.add(row['id'] as int);
          stored.remove(row);
        }
      }
      return json(_report);
    }
    throw StateError('unexpected ${options.method} $path');
  }
}

void main() {
  setUp(resetServices);

  final pngBytes = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  final webpBytes = [
    0x52, 0x49, 0x46, 0x46, // RIFF
    0x00, 0x00, 0x00, 0x00, // size
    0x57, 0x45, 0x42, 0x50, // WEBP
  ];

  DailyReportFormViewModel form(_Backend backend, FakeApi api) =>
      DailyReportFormViewModel(
        initialProjectId: 1,
        session: signedInSession(
          roles: const [AppRole.siteEngineer],
          active: AppRole.siteEngineer,
        ),
        projects: getIt(),
        reports: HttpDailyReportRepository(
          testClient(api: api, tokens: InMemoryTokenStore()),
        ),
        schedule: getIt(),
        masterData: getIt(),
      )..projectId = 1;

  List<PhotoDraft> photos() => [
    PhotoDraft(
      caption: 'First',
      takenAt: DateTime.utc(2026, 10, 20, 9, 30),
      bytes: Uint8List.fromList(pngBytes),
    ),
    PhotoDraft(
      caption: 'Second',
      takenAt: DateTime.utc(2026, 10, 20, 9, 30),
      bytes: Uint8List.fromList(webpBytes),
    ),
  ];

  test(
    'a failed submit retries the saved draft with confirmed photo ids',
    () async {
      final backend = _Backend();
      var submitAttempts = 0;
      final api = FakeApi((options) {
        if (options.path == 'daily-reports/9/submit/') {
          submitAttempts++;
          return submitAttempts == 1
              ? _Backend._serverError
              : json({..._Backend._report, 'status': 'submitted'});
        }
        return backend.handle(options);
      });
      final vm = form(backend, api)..photos.addAll(photos());

      expect(vm.savedId, isNull);
      expect(
        await vm.save(submit: true),
        contains('The server could not complete the request. Try again.'),
      );
      expect(vm.savedId, 9);
      expect(vm.photos.map((p) => p.id), [20, 21]);
      expect(backend.stored.map((r) => r['id']), [20, 21]);

      expect(await vm.save(submit: true), isNull);
      expect(vm.savedId, 9);
      expect(vm.photos.map((p) => p.id), [20, 21]);
      expect(api.paths, [
        'daily-reports/',
        'daily-reports/9/photos/',
        'daily-reports/9/photos/',
        'daily-reports/9/submit/',
        'daily-reports/9/',
        'daily-reports/9/submit/',
      ]);
      final retry = api.last('daily-reports/9/');
      expect(retry.method, 'PUT');
      expect((sentBody(retry)['photos'] as List).map((p) => (p as Map)['id']), [
        20,
        21,
      ]);
      expect(backend.uploads, ['First', 'Second']);
      expect(backend.deleted, isEmpty);
      expect(backend.stored.map((r) => r['id']), [20, 21]);
    },
  );

  test('the form keeps the ids a failed photo save confirmed', () async {
    final backend = _Backend(failures: {'Second': 1});
    final api = FakeApi(backend.handle);
    final vm = form(backend, api)..photos.addAll(photos());

    // Photo #1 is stored, #2 is refused: the form is told what it kept.
    expect(await vm.save(submit: false), contains('photo'));
    expect(vm.photos.map((p) => p.id), [20, null]);
    expect(backend.stored.map((r) => r['id']), [20]);

    // The retry sends photo #1's id back, so the server keeps it.
    expect(await vm.save(submit: false), isNull);
    expect(vm.photos.map((p) => p.id), [20, 21]);
    expect(backend.uploads.where((c) => c == 'First'), hasLength(1));
    expect(backend.deleted, isEmpty);
    expect(backend.stored.map((r) => r['id']), [20, 21]);
  });

  test('a lost upload answer is read back before the next save', () async {
    final backend = _Backend(lostAnswers: {'First': 1});
    final api = FakeApi(backend.handle);
    final vm = form(backend, api)
      ..photos.add(
        PhotoDraft(
          caption: 'First',
          takenAt: DateTime.utc(2026, 10, 20, 9, 30),
          bytes: Uint8List.fromList(pngBytes),
        ),
      );

    // The server stored the photo but the answer never arrived: the form says
    // so instead of keeping quiet about it.
    expect(
      await vm.save(submit: false),
      contains('may already be on the server'),
    );
    expect(vm.photos.single.id, isNull);
    expect(backend.stored.map((r) => r['id']), [20]);

    // The retry reads the report's photos first, so its save cannot delete
    // the photo it never saw. The local copy is uploaded again: one too many
    // beats losing the picture, and nothing is claimed to be exactly-once.
    expect(await vm.save(submit: false), isNull);
    expect(backend.deleted, isEmpty);
    expect(backend.stored.map((r) => r['id']), [20, 21]);
    expect(vm.photos.map((p) => p.id).toList()..sort(), [20, 21]);
  });
}

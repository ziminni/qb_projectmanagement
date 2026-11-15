import 'dart:typed_data';

import 'package:buildpro_frontend/data/models/daily_report.dart';
import 'package:buildpro_frontend/data/models/issue.dart';
import 'package:buildpro_frontend/data/repositories/daily_report_repository.dart';
import 'package:buildpro_frontend/data/repositories/http_daily_report_repository.dart';
import 'package:buildpro_frontend/data/services/business_rule_exception.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_api.dart';

Map<String, dynamic> reportRow({
  int id = 1,
  int projectId = 1,
  String date = '2026-10-20',
  String status = 'draft',
  int submittedBy = 4,
}) => {
  'id': id,
  'project_id': projectId,
  'report_date': date,
  'weather': 'sunny',
  'status': status,
  'submitted_by': submittedBy,
  'reviewed_by': null,
  'remarks': null,
  'toolbox_meeting_held': true,
  'created_at': '2026-10-20T09:00:00Z',
  'updated_at': '2026-10-20T09:00:00Z',
};

Map<String, dynamic> manpowerRow({int id = 1, int reportId = 1}) => {
  'id': id,
  'daily_report_id': reportId,
  'trade': 'Carpenter',
  'headcount': 6,
  'created_at': '2026-10-20T09:00:00Z',
  'updated_at': '2026-10-20T09:00:00Z',
};

Map<String, dynamic> materialRow({int id = 1, int reportId = 1}) => {
  'id': id,
  'daily_report_id': reportId,
  'material_id': 3,
  'quantity': '12.50',
  'created_at': '2026-10-20T09:00:00Z',
  'updated_at': '2026-10-20T09:00:00Z',
};

Map<String, dynamic> equipmentRow({int id = 1, int reportId = 1}) => {
  'id': id,
  'equipment_id': 2,
  'project_id': 1,
  'log_date': '2026-10-20',
  'hours_used': '4.00',
  'daily_report_id': reportId,
  'created_at': '2026-10-20T09:00:00Z',
  'updated_at': '2026-10-20T09:00:00Z',
};

Map<String, dynamic> issueRow({int id = 1, int reportId = 1}) => {
  'id': id,
  'project_id': 1,
  'daily_report_id': reportId,
  'type': 'delay',
  'reason': 'rain_typhoon',
  'description': 'Rain stopped the pour.',
  'days_lost': '1.00',
  'created_at': '2026-10-20T09:00:00Z',
  'updated_at': '2026-10-20T09:00:00Z',
};

Map<String, dynamic> photoRow({
  int id = 1,
  int reportId = 1,
  String? caption = 'Column pour',
  String? takenAt = '2026-10-20T09:30:00Z',
  String fileUrl =
      'https://cpms.example.ph/api/v1/report-photos/1/file/pour.jpg',
}) => {
  'id': id,
  'daily_report_id': reportId,
  'file_url': fileUrl,
  'caption': caption,
  'latitude': null,
  'longitude': null,
  'taken_at': takenAt,
  'created_at': '2026-10-20T09:30:00Z',
  'updated_at': '2026-10-20T09:30:00Z',
};

Map<String, dynamic> todoRow({int id = 1}) => {
  'id': id,
  'category_id': 1,
  'title': 'Excavation',
  'start_date': '2026-10-01',
  'end_date': '2026-10-05',
  'is_done': true,
  'done_by': 4,
  'done_at': '2026-10-20T09:00:00Z',
  'is_verified': false,
  'verified_by': null,
  'verified_at': null,
  'daily_report_id': 1,
  'created_at': '2026-10-01T09:00:00Z',
  'updated_at': '2026-10-20T09:00:00Z',
};

/// A PNG header, a real RIFF/WEBP header, a RIFF container that is not WebP
/// (a WAV) and a RIFF header cut short — the server's content gate.
final pngBytes = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
final webpBytes = [
  0x52, 0x49, 0x46, 0x46, // RIFF
  0x24, 0x00, 0x00, 0x00, // size
  0x57, 0x45, 0x42, 0x50, // WEBP
  0x56, 0x50, 0x38, 0x20,
];
final riffWaveBytes = [
  0x52, 0x49, 0x46, 0x46, //
  0x24, 0x00, 0x00, 0x00, //
  0x57, 0x41, 0x56, 0x45, // WAVE
  0x66, 0x6D, 0x74, 0x20,
];
final truncatedRiffBytes = [0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00];

String uploadedName(FakeApi api) =>
    (api.last('daily-reports/9/photos/').data as FormData)
        .files
        .single
        .value
        .filename!;

/// The report backend's photo rules, the way `site_reports.services` has
/// them: a draft save DELETES every stored photo its `photos` list omits, and
/// each upload stores a new row with a fresh id. A caption can be made to fail
/// a number of times, so a retry loop can be followed exactly.
class FakeReportPhotos {
  FakeReportPhotos({
    Map<String, int> failures = const {},
    Map<String, int> lostAnswers = const {},
    this.reportId = 9,
  }) : _failures = {...failures},
       _lostAnswers = {...lostAnswers};

  /// Caption → uploads refused before anything is stored.
  final Map<String, int> _failures;

  /// Caption → uploads stored and then answered 500: the client never learns
  /// the photo landed.
  final Map<String, int> _lostAnswers;

  final int reportId;

  /// The rows the server holds.
  final stored = <Map<String, dynamic>>[];

  /// Captions the client uploaded, in order.
  final uploads = <String>[];

  /// Ids the server deleted because a draft save omitted them.
  final deleted = <int>[];

  /// The photo ids each draft save carried.
  final saves = <List<int>>[];

  int _nextId = 20;

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
      final row = photoRow(id: _nextId++, reportId: reportId, caption: caption);
      stored.add(row);
      if ((_lostAnswers[caption] ?? 0) > 0) {
        _lostAnswers[caption] = _lostAnswers[caption]! - 1;
        return _serverError;
      }
      return json(row, status: 201);
    }
    if (path == 'daily-reports/' && options.method == 'POST') {
      return json(reportRow(id: reportId), status: 201);
    }
    if (path == 'daily-reports/$reportId/' && options.method == 'GET') {
      return json({...detail(reportRow(id: reportId)), 'photos': stored});
    }
    if (path == 'daily-reports/$reportId/' && options.method == 'PUT') {
      final keep = [
        for (final row in (sentBody(options)['photos'] as List))
          ((row as Map)['id'] as num).toInt(),
      ];
      saves.add(keep);
      for (final row in [...stored]) {
        if (!keep.contains(row['id'])) {
          deleted.add(row['id'] as int);
          stored.remove(row);
        }
      }
      return json(reportRow(id: reportId));
    }
    throw StateError('unexpected ${options.method} $path');
  }
}

Map<String, dynamic> detail(Map<String, dynamic> report) => {
  'report': report,
  'manpower': [manpowerRow()],
  'materials': [materialRow()],
  'equipment': [equipmentRow()],
  'issues': [issueRow()],
  'photos': [photoRow()],
  'todos': [todoRow()],
};

void main() {
  group('http daily report repository', () {
    test('lists the reports with the server filters', () async {
      final api = FakeApi(
        (options) =>
            json([reportRow(id: 2, date: '2026-10-21'), reportRow(id: 1)]),
      );
      final repo = HttpDailyReportRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final reports = await repo.getReports(
        projectIds: [1, 2],
        status: DailyReportStatus.draft,
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 10, 31),
      );

      final request = api.last('daily-reports/');
      expect(request.method, 'GET');
      expect(request.queryParameters, {
        'project': '1,2',
        'status': 'draft',
        'from': '2026-10-01',
        'to': '2026-10-31',
      });
      expect(reports.map((r) => r.id), [2, 1]);
      expect(reports.first.toolboxMeetingHeld, isTrue);
    });

    test('sends no filter keys when none are given', () async {
      final api = FakeApi((options) => json(<Map<String, dynamic>>[]));
      final repo = HttpDailyReportRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      expect(await repo.getReports(), isEmpty);
      expect(api.last('daily-reports/').queryParameters, isEmpty);
    });

    test('reads the full detail of one report', () async {
      final api = FakeApi((options) => json(detail(reportRow())));
      final repo = HttpDailyReportRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final found = await repo.getDetail(1);

      expect(api.last('daily-reports/1/').method, 'GET');
      expect(found!.report.status, DailyReportStatus.draft);
      expect(found.manpower.single.trade, 'Carpenter');
      expect(found.materials.single.quantity, 12.5);
      expect(found.equipment.single.hoursUsed, 4);
      expect(found.issues.single.reason, IssueReason.rainTyphoon);
      expect(found.photos.single.caption, 'Column pour');
      expect(found.todos.single.isDone, isTrue);
    });

    test('returns null for a report outside the caller scope', () async {
      final api = FakeApi(
        (options) => json({'detail': 'Not found.'}, status: 404),
      );
      final repo = HttpDailyReportRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      expect(await repo.getDetail(99), isNull);
    });

    test(
      'creates a draft with every child row and the chosen to-dos',
      () async {
        final api = FakeApi((options) => json(reportRow(id: 8), status: 201));
        final repo = HttpDailyReportRepository(
          testClient(api: api, tokens: InMemoryTokenStore()),
        );

        final saved = await repo.saveDraft(
          DailyReportDraft(
            projectId: 1,
            reportDate: DateTime(2026, 10, 20),
            weather: Weather.sunny,
            toolboxMeetingHeld: true,
            manpower: const [(trade: 'Carpenter', headcount: 6)],
            materials: const [(materialId: 3, quantity: 12.5)],
            equipment: const [(equipmentId: 2, hours: 4)],
            issues: const [
              IssueDraft(
                type: IssueType.delay,
                reason: IssueReason.rainTyphoon,
                description: 'Rain stopped the pour.',
                daysLost: 1,
              ),
            ],
            photos: const [PhotoDraft(id: 5, caption: 'Column pour')],
            todoIds: const [1, 2],
          ),
          userId: 4,
        );

        final request = api.last('daily-reports/');
        expect(request.method, 'POST');
        expect(sentBody(request), {
          'project_id': 1,
          'report_date': '2026-10-20',
          'weather': 'sunny',
          'toolbox_meeting_held': true,
          'manpower': [
            {'trade': 'Carpenter', 'headcount': 6},
          ],
          'materials': [
            {'material_id': 3, 'quantity': 12.5},
          ],
          'equipment': [
            {'equipment_id': 2, 'hours_used': 4.0},
          ],
          'issues': [
            {
              'type': 'delay',
              'reason': 'rain_typhoon',
              'description': 'Rain stopped the pour.',
              'days_lost': 1.0,
            },
          ],
          'photos': [
            {
              'id': 5,
              'caption': 'Column pour',
              'latitude': null,
              'longitude': null,
              'taken_at': null,
            },
          ],
          'todo_ids': [1, 2],
        });
        expect(saved.report.id, 8);
      },
    );

    test('updates an existing draft with PUT', () async {
      final api = FakeApi((options) => json(reportRow(id: 9)));
      final repo = HttpDailyReportRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      await repo.saveDraft(
        DailyReportDraft(
          id: 9,
          projectId: 1,
          reportDate: DateTime(2026, 10, 20),
          weather: Weather.cloudy,
        ),
        userId: 4,
      );

      expect(api.last('daily-reports/9/').method, 'PUT');
    });

    test('uploads a new photo after the draft exists', () async {
      final api = FakeApi((options) {
        if (options.path == 'daily-reports/9/photos/') {
          return json(photoRow(id: 12, caption: 'Fresh pour'), status: 201);
        }
        if (options.path == 'daily-reports/9/') {
          return json(reportRow(id: 9));
        }
        return json(reportRow(id: 9), status: 201);
      });
      final repo = HttpDailyReportRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      await repo.saveDraft(
        DailyReportDraft(
          id: 9,
          projectId: 1,
          reportDate: DateTime(2026, 10, 20),
          weather: Weather.sunny,
          photos: [
            PhotoDraft(
              caption: 'Fresh pour',
              latitude: 13.94,
              longitude: 121.16,
              takenAt: DateTime.utc(2026, 10, 20, 9, 30),
              bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF]),
            ),
          ],
        ),
        userId: 4,
      );

      final upload = api.last('daily-reports/9/photos/');
      expect(upload.method, 'POST');
      expect(
        upload.headers[Headers.contentTypeHeader],
        startsWith('multipart/form-data'),
      );
      final form = upload.data as FormData;
      expect(
        form.fields.firstWhere((f) => f.key == 'caption').value,
        'Fresh pour',
      );
      expect(
        form.fields.firstWhere((f) => f.key == 'latitude').value,
        startsWith('13.94'),
      );
      expect(form.files.single.key, 'file');
      expect(form.files.single.value.length, 3);
      // The kept-photo list of the draft save carries ids only.
      final draftSave = api.requests.lastWhere((r) => r.method == 'PUT');
      expect((sentBody(draftSave)['photos'] as List), isEmpty);
    });

    test('names each photo by its content for the server gate', () async {
      final cases = <(List<int>, String)>[
        (pngBytes, 'photo.png'),
        (webpBytes, 'photo.webp'),
        (riffWaveBytes, 'photo.jpg'), // RIFF, but a WAVE chunk
        (truncatedRiffBytes, 'photo.jpg'), // too short to carry `WEBP`
      ];

      for (final (bytes, expected) in cases) {
        final api = FakeApi((options) {
          if (options.path == 'daily-reports/9/photos/') {
            return json(photoRow(id: 12), status: 201);
          }
          return json(reportRow(id: 9), status: 201);
        });
        final repo = HttpDailyReportRepository(
          testClient(api: api, tokens: InMemoryTokenStore()),
        );

        await repo.saveDraft(
          DailyReportDraft(
            projectId: 1,
            reportDate: DateTime(2026, 10, 20),
            weather: Weather.sunny,
            photos: [
              PhotoDraft(
                caption: 'Pour',
                takenAt: DateTime.utc(2026, 10, 20, 9, 30),
                bytes: Uint8List.fromList(bytes),
              ),
            ],
          ),
          userId: 4,
        );

        expect(uploadedName(api), expected, reason: 'bytes: $bytes');
      }
    });

    test('a retry keeps the photo an earlier failed save uploaded', () async {
      // The draft save deletes the photos it omits, so a retry that forgets
      // the id of a photo it already stored destroys that photo.
      final backend = FakeReportPhotos(failures: {'Second': 2});
      final api = FakeApi(backend.handle);
      final repo = HttpDailyReportRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );
      List<PhotoDraft> photos() => [
        PhotoDraft(
          caption: 'First',
          takenAt: DateTime.utc(2026, 10, 20, 9, 30),
          bytes: Uint8List.fromList(pngBytes),
        ),
        PhotoDraft(
          caption: 'Second',
          takenAt: DateTime.utc(2026, 10, 20, 9, 31),
          bytes: Uint8List.fromList(webpBytes),
        ),
      ];

      // Attempt 1 creates the report and stores photo #1, then fails on #2.
      // The retry resumes on the same report and fails on #2 once more. The
      // ids a failed save confirmed are what the form keeps for the retry.
      var kept = photos();
      for (var attempt = 1; attempt <= 2; attempt++) {
        try {
          await repo.saveDraft(
            DailyReportDraft(
              id: attempt == 1 ? null : 9,
              projectId: 1,
              reportDate: DateTime(2026, 10, 20),
              weather: Weather.sunny,
              photos: kept,
            ),
            userId: 4,
          );
          fail('attempt $attempt: the failed photo must be reported');
        } on DailyReportSaveException catch (error) {
          expect(
            error.saved.id,
            9,
            reason: 'attempt $attempt: saved report id',
          );
          expect(error.uncertain, isTrue, reason: 'attempt $attempt');
          expect(
            error.photos.first.id,
            20,
            reason: 'attempt $attempt: the stored photo keeps its id',
          );
          expect(
            error.photos.last.id,
            isNull,
            reason: 'attempt $attempt: the failed photo is still pending',
          );
          kept = error.photos;
        }
        expect(
          api.paths.where((p) => p == 'daily-reports/').length,
          1,
          reason: 'attempt $attempt: no second report is created',
        );
        expect(
          backend.uploads.where((c) => c == 'First'),
          hasLength(1),
          reason: 'attempt $attempt: the stored photo is not uploaded again',
        );
        expect(
          backend.deleted,
          isEmpty,
          reason: 'attempt $attempt: the stored photo is not deleted',
        );
        expect(backend.stored.map((r) => r['id']), [
          20,
        ], reason: 'attempt $attempt: photo #1 is still on the server');
      }
      expect(backend.saves, [
        [20],
      ], reason: 'the retry PUT carries the id of the stored photo');

      // The last attempt uploads both photos and keeps both.
      final saved = await repo.saveDraft(
        DailyReportDraft(
          id: 9,
          projectId: 1,
          reportDate: DateTime(2026, 10, 20),
          weather: Weather.sunny,
          photos: kept,
        ),
        userId: 4,
      );

      expect(saved.report.id, 9);
      expect(saved.photos.map((p) => p.id), [20, 21]);
      expect(backend.stored.map((r) => r['id']), [20, 21]);
      expect(backend.deleted, isEmpty);
      expect(backend.uploads.where((c) => c == 'First'), hasLength(1));
      expect(backend.uploads.where((c) => c == 'Second'), hasLength(3));
    });

    test('an upload whose answer was lost is reported as uncertain', () async {
      // The server stores the photo and the answer never arrives. The client
      // cannot claim exactly-once, so it says so and keeps the report instead
      // of letting a retry wipe what it cannot see.
      final backend = FakeReportPhotos(lostAnswers: {'First': 1});
      final api = FakeApi(backend.handle);
      final repo = HttpDailyReportRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      try {
        await repo.saveDraft(
          DailyReportDraft(
            projectId: 1,
            reportDate: DateTime(2026, 10, 20),
            weather: Weather.sunny,
            photos: [
              PhotoDraft(
                caption: 'First',
                takenAt: DateTime.utc(2026, 10, 20, 9, 30),
                bytes: Uint8List.fromList(pngBytes),
              ),
            ],
          ),
          userId: 4,
        );
        fail('a lost answer must not pass as success');
      } on DailyReportSaveException catch (error) {
        expect(error.saved.id, 9, reason: 'the report it created is kept');
        expect(error.uncertain, isTrue);
        expect(
          error.photos.single.id,
          isNull,
          reason: 'the client cannot know the photo landed',
        );
        expect(error.message, contains('may already be on the server'));
      }
      expect(backend.stored, hasLength(1), reason: 'the server did store it');
    });

    test(
      'two photos with one caption and capture time stay distinct',
      () async {
        final backend = FakeReportPhotos();
        final api = FakeApi(backend.handle);
        final repo = HttpDailyReportRepository(
          testClient(api: api, tokens: InMemoryTokenStore()),
        );
        final taken = DateTime.utc(2026, 10, 20, 9, 30);
        List<PhotoDraft> photos() => [
          PhotoDraft(
            caption: 'Pour',
            takenAt: taken,
            bytes: Uint8List.fromList(pngBytes),
          ),
          PhotoDraft(
            caption: 'Pour',
            takenAt: taken,
            bytes: Uint8List.fromList(webpBytes),
          ),
        ];

        final saved = await repo.saveDraft(
          DailyReportDraft(
            id: 9,
            projectId: 1,
            reportDate: DateTime(2026, 10, 20),
            weather: Weather.sunny,
            photos: photos(),
          ),
          userId: 4,
        );

        // Identical captions and capture times are two photos, not one.
        expect(saved.report.id, 9);
        expect(saved.photos.map((p) => p.id), [20, 21]);
        expect(backend.stored.map((r) => r['id']), [20, 21]);

        // Saving again with the ids the save returned keeps both.
        await repo.saveDraft(
          DailyReportDraft(
            id: 9,
            projectId: 1,
            reportDate: DateTime(2026, 10, 20),
            weather: Weather.sunny,
            photos: saved.photos,
          ),
          userId: 4,
        );

        expect(backend.stored.map((r) => r['id']), [20, 21]);
        expect(backend.deleted, isEmpty);
        expect(backend.uploads, ['Pour', 'Pour']);
      },
    );

    test('submits, approves and returns a report', () async {
      final api = FakeApi((options) => json(reportRow(status: 'submitted')));
      final repo = HttpDailyReportRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      await repo.submit(4, userId: 7);
      await repo.approve(4, userId: 7);
      await repo.returnReport(4, userId: 7, remarks: ' Fix the dates ');

      expect(api.paths, [
        'daily-reports/4/submit/',
        'daily-reports/4/approve/',
        'daily-reports/4/return/',
      ]);
      expect(sentBody(api.last('daily-reports/4/return/')), {
        'remarks': 'Fix the dates',
      });
    });

    test('reads approved usage and equipment hours of a project', () async {
      final api = FakeApi((options) {
        if (options.path == 'projects/3/approved-material-usage/') {
          return json([materialRow()]);
        }
        return json([equipmentRow()]);
      });
      final repo = HttpDailyReportRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final usage = await repo.getApprovedMaterialUsage(3);
      final hours = await repo.getApprovedEquipmentLogs(3);

      expect(usage.single.materialId, 3);
      expect(hours.single.equipmentId, 2);
    });

    test('reads the approved photos with their reports', () async {
      final api = FakeApi(
        (options) => json([
          {'photo': photoRow(id: 4), 'report': reportRow(status: 'approved')},
        ]),
      );
      final repo = HttpDailyReportRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final photos = await repo.getApprovedPhotos([1, 2]);

      expect(api.last('report-photos/approved/').queryParameters, {
        'project': '1,2',
      });
      expect(photos.single.photo.id, 4);
      expect(photos.single.report.status, DailyReportStatus.approved);
    });

    test('rethrows the server refusal text unchanged', () async {
      final api = FakeApi(
        (options) => json({
          'detail': 'There is already a report for this project on this date.',
        }, status: 400),
      );
      final repo = HttpDailyReportRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      expect(
        repo.saveDraft(
          DailyReportDraft(
            projectId: 1,
            reportDate: DateTime(2026, 10, 20),
            weather: Weather.sunny,
          ),
          userId: 4,
        ),
        throwsA(
          isA<BusinessRuleException>().having(
            (e) => e.message,
            'message',
            'There is already a report for this project on this date.',
          ),
        ),
      );
    });
  });
}

import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../models/system_admin.dart';
import 'system_admin_repository.dart';

class HttpSystemAdminRepository implements SystemAdminRepository {
  HttpSystemAdminRepository(this._client);

  final ApiClient _client;

  @override
  Future<SecurityOverview> getSecurityOverview() async =>
      SecurityOverview.fromJson(jsonObject(await _client.get('system/security/')));

  @override
  Future<void> revokeSession(int sessionId) async {
    await _client.post('system/security/sessions/$sessionId/revoke/');
  }

  @override
  Future<int> revokeAllSessions({int? userId}) async {
    final data = jsonObject(
      await _client.post(
        'system/security/sessions/revoke-all/',
        body: {'user_id': ?userId},
      ),
    );
    return (data['count'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<SecurityPolicy> updateSecurityPolicy(SecurityPolicy policy) async =>
      SecurityPolicy.fromJson(
        jsonObject(
          await _client.patch('system/security/policy/', body: policy.toJson()),
        ),
      );

  @override
  Future<BackupOverview> getBackups() async =>
      BackupOverview.fromJson(jsonObject(await _client.get('system/backups/')));

  @override
  Future<BackupSnapshot> createBackup() async => BackupSnapshot.fromJson(
    jsonObject(await _client.post('system/backups/')),
  );

  @override
  Future<Uint8List> downloadBackup(String backupId) =>
      _client.getBytes('system/backups/$backupId/download/');

  @override
  Future<void> restoreBackup(String backupId) async {
    await _client.post('system/backups/restore/', body: {'id': backupId});
  }

  @override
  Future<void> uploadAndRestoreBackup(String filename, Uint8List bytes) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    await _client.post('system/backups/upload-restore/', body: form);
  }

  @override
  Future<BackupSchedule> updateBackupSchedule(BackupSchedule schedule) async =>
      BackupSchedule.fromJson(
        jsonObject(
          await _client.patch(
            'system/backups/schedule/',
            body: schedule.toJson(),
          ),
        ),
      );

  @override
  Future<SystemHealthOverview> getSystemHealth({bool probePos = false}) async =>
      SystemHealthOverview.fromJson(
        jsonObject(
          await _client.get(
            'system/health/',
            query: probePos ? const {'probe_pos': '1'} : null,
          ),
        ),
      );

  @override
  Future<void> retryPosSync(int jobId) async {
    await _client.post('system/pos-sync/$jobId/retry/');
  }
}

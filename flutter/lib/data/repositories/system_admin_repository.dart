import 'dart:typed_data';

import '../models/system_admin.dart';

abstract interface class SystemAdminRepository {
  Future<SecurityOverview> getSecurityOverview();
  Future<void> revokeSession(int sessionId);
  Future<int> revokeAllSessions({int? userId});
  Future<SecurityPolicy> updateSecurityPolicy(SecurityPolicy policy);

  Future<BackupOverview> getBackups();
  Future<BackupSnapshot> createBackup();
  Future<Uint8List> downloadBackup(String backupId);
  Future<void> restoreBackup(String backupId);
  Future<void> uploadAndRestoreBackup(String filename, Uint8List bytes);
  Future<BackupSchedule> updateBackupSchedule(BackupSchedule schedule);

  Future<SystemHealthOverview> getSystemHealth({bool probePos = false});
  Future<void> retryPosSync(int jobId);
}

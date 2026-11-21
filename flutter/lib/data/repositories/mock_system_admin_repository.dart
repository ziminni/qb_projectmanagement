import 'dart:convert';
import 'dart:typed_data';

import '../models/system_admin.dart';
import '../services/business_rule_exception.dart';
import 'system_admin_repository.dart';

class MockSystemAdminRepository implements SystemAdminRepository {
  SecurityPolicy _policy = const SecurityPolicy(
    minPasswordLength: 8,
    idleTimeoutMinutes: 30,
    maxFailedLogins: 5,
    requireManagerOverride: true,
  );

  BackupSchedule _schedule = BackupSchedule(
    frequency: 'daily',
    retentionCount: 7,
    lastBackupAt: DateTime.now().subtract(const Duration(hours: 6)),
  );

  final List<ActiveSession> _sessions = [
    ActiveSession(
      id: 101,
      userId: 1,
      userEmail: 'maria@example.ph',
      userName: 'Maria Santos',
      jti: 'mock-jti-admin-01',
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      expiresAt: DateTime.now().add(const Duration(days: 6)),
    ),
    ActiveSession(
      id: 102,
      userId: 2,
      userEmail: 'ramon@example.ph',
      userName: 'Ramon Dela Cruz',
      jti: 'mock-jti-owner-02',
      createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      expiresAt: DateTime.now().add(const Duration(days: 6)),
    ),
  ];

  final List<SecurityEvent> _events = [
    SecurityEvent(
      id: 1,
      userId: 1,
      userEmail: 'maria@example.ph',
      userName: 'Maria Santos',
      action: 'login',
      details: const {'roles': ['admin']},
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
    ),
    SecurityEvent(
      id: 2,
      userId: 3,
      userEmail: 'ana@example.ph',
      userName: 'Ana Reyes',
      action: 'login_failed',
      details: const {'reason': 'incorrect_password'},
      createdAt: DateTime.now().subtract(const Duration(hours: 4)),
    ),
  ];

  final List<BackupSnapshot> _backups = [
    BackupSnapshot(
      id: 'cpms_backup_20261120_020000_a1b2c3',
      filename: 'cpms_backup_20261120_020000_a1b2c3.json.gz',
      sizeBytes: 48210,
      sha256: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      createdAt: DateTime.now().subtract(const Duration(hours: 6)),
    ),
  ];

  final List<PosOutboxJobSummary> _posJobs = [
    PosOutboxJobSummary(
      id: 1,
      purchaseOrderId: 12,
      poNumber: 'PO-2026-0012',
      projectName: 'Warehouse extension',
      operation: 'import',
      state: 'failed',
      attempts: 3,
      lastError: 'Connection refused by store POS server',
      updatedAt: DateTime.now().subtract(const Duration(minutes: 25)),
    ),
  ];

  @override
  Future<SecurityOverview> getSecurityOverview() async => SecurityOverview(
    sessions: List.unmodifiable(_sessions),
    events: List.unmodifiable(_events),
    policy: _policy,
  );

  @override
  Future<void> revokeSession(int sessionId) async {
    final index = _sessions.indexWhere((s) => s.id == sessionId);
    if (index < 0) {
      throw const BusinessRuleException('Session not found.');
    }
    final removed = _sessions.removeAt(index);
    _events.insert(
      0,
      SecurityEvent(
        id: _events.length + 1,
        userId: removed.userId ?? 1,
        userEmail: removed.userEmail,
        userName: removed.userName,
        action: 'logout',
        details: const {'revoked_by_admin': true},
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<int> revokeAllSessions({int? userId}) async {
    final removed = userId == null
        ? _sessions.where((s) => s.userId != 1).toList()
        : _sessions.where((s) => s.userId == userId).toList();
    for (final s in removed) {
      _sessions.remove(s);
    }
    return removed.length;
  }

  @override
  Future<SecurityPolicy> updateSecurityPolicy(SecurityPolicy policy) async {
    _policy = policy.copyWith(updatedAt: DateTime.now());
    return _policy;
  }

  @override
  Future<BackupOverview> getBackups() async => BackupOverview(
    backups: List.unmodifiable(_backups),
    schedule: _schedule,
  );

  @override
  Future<BackupSnapshot> createBackup() async {
    final now = DateTime.now();
    final id = 'cpms_backup_${now.millisecondsSinceEpoch}';
    final snap = BackupSnapshot(
      id: id,
      filename: '$id.json.gz',
      sizeBytes: 51200,
      sha256: '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08',
      createdAt: now,
    );
    _backups.insert(0, snap);
    if (_backups.length > _schedule.retentionCount) {
      _backups.removeRange(_schedule.retentionCount, _backups.length);
    }
    _schedule = _schedule.copyWith(lastBackupAt: now);
    return snap;
  }

  @override
  Future<Uint8List> downloadBackup(String backupId) async {
    final exists = _backups.any((b) => b.id == backupId);
    if (!exists) {
      throw const BusinessRuleException('Backup not found.');
    }
    return Uint8List.fromList(utf8.encode('{"backup_id":"$backupId"}'));
  }

  @override
  Future<void> restoreBackup(String backupId) async {
    final exists = _backups.any((b) => b.id == backupId);
    if (!exists) {
      throw const BusinessRuleException('Backup not found.');
    }
  }

  @override
  Future<void> uploadAndRestoreBackup(String filename, Uint8List bytes) async {
    if (bytes.isEmpty) {
      throw const BusinessRuleException('Backup file is empty.');
    }
    final now = DateTime.now();
    _backups.insert(
      0,
      BackupSnapshot(
        id: 'upload_${now.millisecondsSinceEpoch}',
        filename: filename,
        sizeBytes: bytes.length,
        sha256: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        createdAt: now,
      ),
    );
  }

  @override
  Future<BackupSchedule> updateBackupSchedule(BackupSchedule schedule) async {
    _schedule = schedule.copyWith(updatedAt: DateTime.now());
    if (_backups.length > _schedule.retentionCount) {
      _backups.removeRange(_schedule.retentionCount, _backups.length);
    }
    return _schedule;
  }

  @override
  Future<SystemHealthOverview> getSystemHealth({bool probePos = false}) async =>
      SystemHealthOverview(
        database: 'ok',
        storage: const StorageStats(
          backupsBytes: 48210,
          reportsBytes: 1240500,
          documentsBytes: 3820000,
          totalBytes: 5108710,
        ),
        posBridge: PosBridgeStatus(
          baseUrl: 'http://127.0.0.1:8000',
          pendingCount: 0,
          failedCount: _posJobs.length,
          syncedCount: 14,
          posReachable: probePos ? true : null,
          jobs: List.unmodifiable(_posJobs),
        ),
      );

  @override
  Future<void> retryPosSync(int jobId) async {
    final i = _posJobs.indexWhere((j) => j.id == jobId);
    if (i < 0) {
      throw const BusinessRuleException('Outbox job not found.');
    }
    _posJobs.removeAt(i);
  }
}

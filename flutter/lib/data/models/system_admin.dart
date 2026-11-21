import 'json_utils.dart';

class ActiveSession {
  const ActiveSession({
    required this.id,
    required this.userId,
    required this.userEmail,
    required this.userName,
    required this.jti,
    this.createdAt,
    this.expiresAt,
  });

  final int id;
  final int? userId;
  final String userEmail;
  final String userName;
  final String jti;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  factory ActiveSession.fromJson(Map<String, dynamic> json) => ActiveSession(
    id: (json['id'] as num).toInt(),
    userId: (json['user_id'] as num?)?.toInt(),
    userEmail: json['user_email'] as String? ?? '',
    userName: json['user_name'] as String? ?? '',
    jti: json['jti'] as String? ?? '',
    createdAt: JsonUtils.toDateOrNull(json['created_at']),
    expiresAt: JsonUtils.toDateOrNull(json['expires_at']),
  );
}

class SecurityEvent {
  const SecurityEvent({
    required this.id,
    required this.userId,
    required this.userEmail,
    required this.userName,
    required this.action,
    required this.details,
    required this.createdAt,
  });

  final int id;
  final int userId;
  final String userEmail;
  final String userName;
  final String action;
  final Map<String, dynamic> details;
  final DateTime createdAt;

  factory SecurityEvent.fromJson(Map<String, dynamic> json) => SecurityEvent(
    id: (json['id'] as num).toInt(),
    userId: (json['user_id'] as num).toInt(),
    userEmail: json['user_email'] as String? ?? '',
    userName: json['user_name'] as String? ?? '',
    action: json['action'] as String? ?? '',
    details: Map<String, dynamic>.from(json['details'] as Map? ?? const {}),
    createdAt: JsonUtils.toDate(json['created_at']),
  );
}

class SecurityPolicy {
  const SecurityPolicy({
    required this.minPasswordLength,
    required this.idleTimeoutMinutes,
    required this.maxFailedLogins,
    required this.requireManagerOverride,
    this.updatedAt,
  });

  final int minPasswordLength;
  final int idleTimeoutMinutes;
  final int maxFailedLogins;
  final bool requireManagerOverride;
  final DateTime? updatedAt;

  SecurityPolicy copyWith({
    int? minPasswordLength,
    int? idleTimeoutMinutes,
    int? maxFailedLogins,
    bool? requireManagerOverride,
    DateTime? updatedAt,
  }) => SecurityPolicy(
    minPasswordLength: minPasswordLength ?? this.minPasswordLength,
    idleTimeoutMinutes: idleTimeoutMinutes ?? this.idleTimeoutMinutes,
    maxFailedLogins: maxFailedLogins ?? this.maxFailedLogins,
    requireManagerOverride:
        requireManagerOverride ?? this.requireManagerOverride,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  factory SecurityPolicy.fromJson(Map<String, dynamic> json) => SecurityPolicy(
    minPasswordLength: (json['min_password_length'] as num?)?.toInt() ?? 8,
    idleTimeoutMinutes: (json['idle_timeout_minutes'] as num?)?.toInt() ?? 30,
    maxFailedLogins: (json['max_failed_logins'] as num?)?.toInt() ?? 5,
    requireManagerOverride:
        json['require_manager_override'] as bool? ?? true,
    updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
  );

  Map<String, dynamic> toJson() => {
    'min_password_length': minPasswordLength,
    'idle_timeout_minutes': idleTimeoutMinutes,
    'max_failed_logins': maxFailedLogins,
    'require_manager_override': requireManagerOverride,
  };
}

class SecurityOverview {
  const SecurityOverview({
    required this.sessions,
    required this.events,
    required this.policy,
  });

  final List<ActiveSession> sessions;
  final List<SecurityEvent> events;
  final SecurityPolicy policy;

  factory SecurityOverview.fromJson(Map<String, dynamic> json) =>
      SecurityOverview(
        sessions: [
          for (final row in (json['sessions'] as List? ?? const []))
            ActiveSession.fromJson(Map<String, dynamic>.from(row as Map)),
        ],
        events: [
          for (final row in (json['events'] as List? ?? const []))
            SecurityEvent.fromJson(Map<String, dynamic>.from(row as Map)),
        ],
        policy: SecurityPolicy.fromJson(
          Map<String, dynamic>.from(json['policy'] as Map? ?? const {}),
        ),
      );
}

class BackupSnapshot {
  const BackupSnapshot({
    required this.id,
    required this.filename,
    required this.sizeBytes,
    required this.sha256,
    required this.createdAt,
  });

  final String id;
  final String filename;
  final int sizeBytes;
  final String sha256;
  final DateTime createdAt;

  factory BackupSnapshot.fromJson(Map<String, dynamic> json) => BackupSnapshot(
    id: json['id'] as String? ?? '',
    filename: json['filename'] as String? ?? '',
    sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
    sha256: json['sha256'] as String? ?? '',
    createdAt: JsonUtils.toDate(json['created_at']),
  );
}

class BackupSchedule {
  const BackupSchedule({
    required this.frequency,
    required this.retentionCount,
    this.lastBackupAt,
    this.updatedAt,
  });

  final String frequency;
  final int retentionCount;
  final DateTime? lastBackupAt;
  final DateTime? updatedAt;

  BackupSchedule copyWith({
    String? frequency,
    int? retentionCount,
    DateTime? lastBackupAt,
    DateTime? updatedAt,
  }) => BackupSchedule(
    frequency: frequency ?? this.frequency,
    retentionCount: retentionCount ?? this.retentionCount,
    lastBackupAt: lastBackupAt ?? this.lastBackupAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  factory BackupSchedule.fromJson(Map<String, dynamic> json) => BackupSchedule(
    frequency: json['frequency'] as String? ?? 'daily',
    retentionCount: (json['retention_count'] as num?)?.toInt() ?? 7,
    lastBackupAt: JsonUtils.toDateOrNull(json['last_backup_at']),
    updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
  );

  Map<String, dynamic> toJson() => {
    'frequency': frequency,
    'retention_count': retentionCount,
  };
}

class BackupOverview {
  const BackupOverview({required this.backups, required this.schedule});

  final List<BackupSnapshot> backups;
  final BackupSchedule schedule;

  factory BackupOverview.fromJson(Map<String, dynamic> json) => BackupOverview(
    backups: [
      for (final row in (json['backups'] as List? ?? const []))
        BackupSnapshot.fromJson(Map<String, dynamic>.from(row as Map)),
    ],
    schedule: BackupSchedule.fromJson(
      Map<String, dynamic>.from(json['schedule'] as Map? ?? const {}),
    ),
  );
}

class StorageStats {
  const StorageStats({
    required this.backupsBytes,
    required this.reportsBytes,
    required this.documentsBytes,
    required this.totalBytes,
  });

  final int backupsBytes;
  final int reportsBytes;
  final int documentsBytes;
  final int totalBytes;

  factory StorageStats.fromJson(Map<String, dynamic> json) => StorageStats(
    backupsBytes: (json['backups_bytes'] as num?)?.toInt() ?? 0,
    reportsBytes: (json['reports_bytes'] as num?)?.toInt() ?? 0,
    documentsBytes: (json['documents_bytes'] as num?)?.toInt() ?? 0,
    totalBytes: (json['total_bytes'] as num?)?.toInt() ?? 0,
  );
}

class PosOutboxJobSummary {
  const PosOutboxJobSummary({
    required this.id,
    required this.purchaseOrderId,
    required this.poNumber,
    required this.projectName,
    required this.operation,
    required this.state,
    required this.attempts,
    required this.lastError,
    required this.updatedAt,
  });

  final int id;
  final int purchaseOrderId;
  final String poNumber;
  final String projectName;
  final String operation;
  final String state;
  final int attempts;
  final String lastError;
  final DateTime updatedAt;

  factory PosOutboxJobSummary.fromJson(Map<String, dynamic> json) =>
      PosOutboxJobSummary(
        id: (json['id'] as num).toInt(),
        purchaseOrderId: (json['purchase_order_id'] as num).toInt(),
        poNumber: json['po_number'] as String? ?? '',
        projectName: json['project_name'] as String? ?? '',
        operation: json['operation'] as String? ?? '',
        state: json['state'] as String? ?? '',
        attempts: (json['attempts'] as num?)?.toInt() ?? 0,
        lastError: json['last_error'] as String? ?? '',
        updatedAt: JsonUtils.toDate(json['updated_at']),
      );
}

class PosBridgeStatus {
  const PosBridgeStatus({
    required this.baseUrl,
    required this.pendingCount,
    required this.failedCount,
    required this.syncedCount,
    this.posReachable,
    this.probeError,
    required this.jobs,
  });

  final String baseUrl;
  final int pendingCount;
  final int failedCount;
  final int syncedCount;
  final bool? posReachable;
  final String? probeError;
  final List<PosOutboxJobSummary> jobs;

  factory PosBridgeStatus.fromJson(Map<String, dynamic> json) =>
      PosBridgeStatus(
        baseUrl: json['base_url'] as String? ?? '',
        pendingCount: (json['pending_count'] as num?)?.toInt() ?? 0,
        failedCount: (json['failed_count'] as num?)?.toInt() ?? 0,
        syncedCount: (json['synced_count'] as num?)?.toInt() ?? 0,
        posReachable: json['pos_reachable'] as bool?,
        probeError: json['probe_error'] as String?,
        jobs: [
          for (final row in (json['jobs'] as List? ?? const []))
            PosOutboxJobSummary.fromJson(Map<String, dynamic>.from(row as Map)),
        ],
      );
}

class SystemHealthOverview {
  const SystemHealthOverview({
    required this.database,
    required this.storage,
    required this.posBridge,
  });

  final String database;
  final StorageStats storage;
  final PosBridgeStatus posBridge;

  factory SystemHealthOverview.fromJson(Map<String, dynamic> json) =>
      SystemHealthOverview(
        database: json['database'] as String? ?? 'unknown',
        storage: StorageStats.fromJson(
          Map<String, dynamic>.from(json['storage'] as Map? ?? const {}),
        ),
        posBridge: PosBridgeStatus.fromJson(
          Map<String, dynamic>.from(json['pos_bridge'] as Map? ?? const {}),
        ),
      );
}

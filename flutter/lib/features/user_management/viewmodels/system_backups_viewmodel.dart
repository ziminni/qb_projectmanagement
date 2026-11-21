import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/models/system_admin.dart';
import '../../../data/repositories/system_admin_repository.dart';

class SystemBackupsViewModel extends ChangeNotifier with ActionRunner {
  SystemBackupsViewModel(this._repo);

  final SystemAdminRepository _repo;

  bool _loading = true;
  String? _error;
  BackupOverview? _overview;
  String _frequency = 'daily';

  bool get isLoading => _loading;
  String? get error => _error;
  List<BackupSnapshot> get backups => _overview?.backups ?? const [];
  BackupSchedule? get schedule => _overview?.schedule;
  String get frequency => _frequency;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _overview = await _repo.getBackups();
      _frequency = _overview!.schedule.frequency;
    } catch (e) {
      _error = 'Could not load database backups. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void setFrequency(String value) {
    _frequency = value;
    notifyListeners();
  }

  Future<String?> createBackup() => runAction(() async {
    await _repo.createBackup();
    _overview = await _repo.getBackups();
  });

  Future<String?> restoreBackup(String backupId) => runAction(() async {
    await _repo.restoreBackup(backupId);
    _overview = await _repo.getBackups();
  });

  Future<String?> uploadAndRestoreBackup(String filename, Uint8List bytes) =>
      runAction(() async {
        await _repo.uploadAndRestoreBackup(filename, bytes);
        _overview = await _repo.getBackups();
      });

  Future<Uint8List> downloadBackupBytes(String backupId) =>
      _repo.downloadBackup(backupId);

  Future<String?> saveSchedule({required int retentionCount}) =>
      runAction(() async {
        await _repo.updateBackupSchedule(
          BackupSchedule(
            frequency: _frequency,
            retentionCount: retentionCount,
          ),
        );
        _overview = await _repo.getBackups();
      });
}

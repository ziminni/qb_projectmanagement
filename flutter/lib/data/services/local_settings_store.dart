import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

/// Local-only key-value JSON persistence on the device.
abstract interface class LocalSettingsStore {
  Future<Map<String, dynamic>?> read();
  Future<void> write(Map<String, dynamic> data);
}

/// In-memory store for tests and web fallback.
class MemoryLocalSettingsStore implements LocalSettingsStore {
  Map<String, dynamic>? _data;

  @override
  Future<Map<String, dynamic>?> read() async =>
      _data == null ? null : Map<String, dynamic>.from(_data!);

  @override
  Future<void> write(Map<String, dynamic> data) async {
    _data = Map<String, dynamic>.from(data);
  }
}

/// Stores local device preferences in a JSON file under the user's home/config
/// directory (no backend changes required).
class FileLocalSettingsStore implements LocalSettingsStore {
  FileLocalSettingsStore({File? file}) : _fileOverride = file;

  final File? _fileOverride;

  File? _resolveFile() {
    if (_fileOverride != null) return _fileOverride;
    if (kIsWeb) return null;
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'];
    final dir = home != null && home.isNotEmpty
        ? Directory(home)
        : Directory.systemTemp;
    return File(
      '${dir.path}${Platform.pathSeparator}.buildpro_cpms_local_settings.json',
    );
  }

  @override
  Future<Map<String, dynamic>?> read() async {
    try {
      final file = _resolveFile();
      if (file == null || !await file.exists()) return null;
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(Map<String, dynamic> data) async {
    try {
      final file = _resolveFile();
      if (file == null) return;
      await file.writeAsString(jsonEncode(data), flush: true);
    } catch (_) {
      // Ignore local filesystem write errors so UI never crashes.
    }
  }
}

LocalSettingsStore createDefaultLocalSettingsStore() {
  if (kIsWeb || Platform.environment.containsKey('FLUTTER_TEST')) {
    return MemoryLocalSettingsStore();
  }
  return FileLocalSettingsStore();
}

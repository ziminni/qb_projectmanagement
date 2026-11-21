import 'package:flutter/foundation.dart' show ChangeNotifier, protected;

/// Shared loading, error and refresh state for one admin dashboard tab.
///
/// Each tab loads on its own the first time it is opened, so a slow or
/// failing source (the store, payroll) never blocks the other tabs.
abstract class AdminTabViewModel extends ChangeNotifier {
  AdminTabViewModel({DateTime Function()? now}) : now = now ?? DateTime.now;

  /// Clock, injectable for tests.
  final DateTime Function() now;

  bool _loading = true;
  String? _error;
  DateTime? _loadedAt;
  bool _disposed = false;

  bool get isLoading => _loading;
  String? get error => _error;

  /// When the figures on screen were fetched.
  DateTime? get loadedAt => _loadedAt;

  /// What this tab is called in error messages, e.g. "the finance figures".
  String get subject;

  /// Fetches and computes everything the tab shows.
  @protected
  Future<void> fetch();

  Future<void> load() async {
    _loading = true;
    _error = null;
    _notify();
    try {
      await fetch();
      _loadedAt = now();
    } catch (e) {
      _error = 'Could not load $subject. $e';
    } finally {
      _loading = false;
      _notify();
    }
  }

  /// Today at midnight.
  DateTime get today {
    final n = now();
    return DateTime(n.year, n.month, n.day);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

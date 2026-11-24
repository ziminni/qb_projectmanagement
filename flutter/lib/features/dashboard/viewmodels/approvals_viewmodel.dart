import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/di/service_locator.dart';
import '../../../data/repositories/labor_repository.dart';
import '../../../data/repositories/schedule_repository.dart';
import '../../../data/services/approval_inbox.dart';
import '../../../data/services/business_rule_exception.dart';
import '../../../data/services/notification_service.dart';
import '../../../data/services/session_service.dart';

/// Owner / PM approvals workbench: groups incoming field items by kind,
/// supports search and project filtering, and allows quick or modal-driven
/// decisions without navigating away from the Approvals page.
class ApprovalsViewModel extends ChangeNotifier {
  ApprovalsViewModel({
    required SessionService session,
    required ApprovalInbox inbox,
    ApprovalKind? initialKind,
  }) : _session = session,
       _inbox = inbox,
       _filter = initialKind;

  final SessionService _session;
  final ApprovalInbox _inbox;

  bool _loading = true;
  String? _error;
  Map<ApprovalKind, List<ApprovalItem>> _groups = const {};
  ApprovalKind? _filter;
  int? _projectFilter;
  String _query = '';
  final Set<String> _busyKeys = {};

  bool get isLoading => _loading;
  String? get error => _error;
  ApprovalKind? get filter => _filter;
  int? get projectFilter => _projectFilter;
  String get query => _query;
  Map<ApprovalKind, List<ApprovalItem>> get groups => _groups;

  int get totalCount =>
      _groups.values.fold<int>(0, (sum, list) => sum + list.length);

  double get totalAmount => _groups.values
      .expand((list) => list)
      .fold<double>(0, (sum, item) => sum + (item.amount ?? 0));

  int countForKind(ApprovalKind kind) => _groups[kind]?.length ?? 0;

  bool get hasActiveFilters =>
      _filter != null || _projectFilter != null || _query.trim().isNotEmpty;

  /// Distinct `(projectId, label)` pairs represented in the current queue.
  List<({int id, String label})> get projectOptions {
    final map = <int, String>{};
    for (final item in _groups.values.expand((l) => l)) {
      final pid = item.projectId;
      if (pid == null || map.containsKey(pid)) continue;
      final code = item.projectCode;
      final name = item.projectName;
      map[pid] = [
        if (code != null && code.isNotEmpty) code,
        if (name != null && name.isNotEmpty) name,
      ].join(' · ');
    }
    final entries = [
      for (final e in map.entries) (id: e.key, label: e.value),
    ]..sort((a, b) => a.label.compareTo(b.label));
    return entries;
  }

  Map<ApprovalKind, List<ApprovalItem>> get visibleGroups {
    final q = _query.trim().toLowerCase();
    final out = <ApprovalKind, List<ApprovalItem>>{};
    for (final entry in _groups.entries) {
      if (_filter != null && entry.key != _filter) continue;
      final filtered = entry.value.where((item) {
        if (_projectFilter != null && item.projectId != _projectFilter) {
          return false;
        }
        if (q.isNotEmpty) {
          final haystack = [
            item.title,
            item.subtitle,
            item.projectCode ?? '',
            item.projectName ?? '',
            item.requesterName ?? '',
            item.badgeText ?? '',
          ].join(' ').toLowerCase();
          if (!haystack.contains(q)) return false;
        }
        return true;
      }).toList();
      if (filtered.isNotEmpty) {
        out[entry.key] = filtered;
      }
    }
    return out;
  }

  String _itemKey(ApprovalItem item) =>
      '${item.kind.name}:${item.entityId ?? item.title}';

  bool isItemBusy(ApprovalItem item) => _busyKeys.contains(_itemKey(item));

  Future<void> load({bool silent = false}) async {
    if (!silent) {
      _loading = true;
      _error = null;
      notifyListeners();
    }
    try {
      final items = await _inbox.pendingFor(
        _session.user!.id,
        _session.activeRole!,
      );
      final groups = <ApprovalKind, List<ApprovalItem>>{};
      for (final kind in ApprovalKind.values) {
        final ofKind = items.where((i) => i.kind == kind).toList();
        if (ofKind.isNotEmpty) groups[kind] = ofKind;
      }
      _groups = groups;
      if (_projectFilter != null &&
          !projectOptions.any((p) => p.id == _projectFilter)) {
        _projectFilter = null;
      }
      if (_filter != null &&
          !_groups.containsKey(_filter) &&
          _groups.isNotEmpty) {
        // Keep user's explicit filter if they selected one, unless all items in
        // it were just cleared — reset to All so remaining items stay visible.
        _filter = null;
      }
    } catch (e) {
      _error = 'Could not load approvals. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void setFilter(ApprovalKind? kind) {
    _filter = kind;
    notifyListeners();
  }

  void setProjectFilter(int? projectId) {
    _projectFilter = projectId;
    notifyListeners();
  }

  void setQuery(String value) {
    _query = value;
    notifyListeners();
  }

  void clearFilters() {
    _filter = null;
    _projectFilter = null;
    _query = '';
    notifyListeners();
  }

  void _refreshBadges() {
    if (getIt.isRegistered<NotificationService>()) {
      getIt<NotificationService>().refresh();
    }
  }

  /// Quick inline verification for a completed to-do.
  Future<String?> quickVerifyTodo(ApprovalItem item) async {
    final id = item.entityId;
    if (id == null || !getIt.isRegistered<ScheduleRepository>()) return null;
    final key = _itemKey(item);
    _busyKeys.add(key);
    notifyListeners();
    try {
      await getIt<ScheduleRepository>().verify(id, userId: _session.user!.id);
      _refreshBadges();
      await load(silent: true);
      return null;
    } on BusinessRuleException catch (e) {
      return e.message;
    } catch (e) {
      return 'Could not verify task. $e';
    } finally {
      _busyKeys.remove(key);
      notifyListeners();
    }
  }

  /// Quick inline approval for a single or bulked laborer request batch.
  Future<String?> quickApproveLaborer(ApprovalItem item) async {
    final ids = item.effectiveIds;
    if (ids.isEmpty || !getIt.isRegistered<LaborRepository>()) return null;
    final key = _itemKey(item);
    _busyKeys.add(key);
    notifyListeners();
    try {
      final labor = getIt<LaborRepository>();
      final uid = _session.user!.id;
      for (final id in ids) {
        await labor.approveWorkerRequest(id, userId: uid);
      }
      _refreshBadges();
      await load(silent: true);
      return null;
    } on BusinessRuleException catch (e) {
      return e.message;
    } catch (e) {
      return 'Could not approve laborer request. $e';
    } finally {
      _busyKeys.remove(key);
      notifyListeners();
    }
  }
}

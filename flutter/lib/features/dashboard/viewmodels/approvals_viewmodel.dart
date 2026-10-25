import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../data/services/approval_inbox.dart';
import '../../../data/services/session_service.dart';

/// Owner: bids, large POs, billings and VOs. PM: daily reports, to-do
/// verification, material requests and attendance.
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

  bool get isLoading => _loading;
  String? get error => _error;
  ApprovalKind? get filter => _filter;
  Map<ApprovalKind, List<ApprovalItem>> get groups => _groups;

  Map<ApprovalKind, List<ApprovalItem>> get visibleGroups => _filter == null
      ? _groups
      : {if (_groups[_filter] != null) _filter!: _groups[_filter]!};

  Future<void> load() async {
    _loading = true;
    notifyListeners();
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
}

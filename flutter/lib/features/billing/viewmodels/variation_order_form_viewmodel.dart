import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/models/json_utils.dart';
import '../../../data/models/project.dart';
import '../../../data/models/variation_order.dart';
import '../../../data/repositories/billing_repository.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/services/business_rule_exception.dart';
import '../../../data/services/session_service.dart';

/// Raise a VO (site engineer or PM) or edit a proposed one (PM).
///
/// Uploading a revised Bar Chart `.xlsx` auto-diffs every Item of Work and
/// computes both schedule impact (days) and net cost impact (additives vs.
/// deductives), with per-item DUPA (A–J) attachments for flagged items.
class VariationOrderFormViewModel extends ChangeNotifier with ActionRunner {
  VariationOrderFormViewModel({
    this.voId,
    this.initialProjectId,
    required SessionService session,
    required ProjectRepository projects,
    required BillingRepository billing,
  }) : _session = session,
       _projects = projects,
       _billing = billing;

  final int? voId;
  final int? initialProjectId;
  final SessionService _session;
  final ProjectRepository _projects;
  final BillingRepository _billing;

  bool _loading = true;
  String? _error;
  List<Project> _options = const [];
  VariationOrder? _existing;
  int? _savedId;
  String? _savedVoNo;

  int? projectId;
  VariationOrderType type = VariationOrderType.change;
  Map<String, dynamic>? revisedSchedule;
  List<String> primaryAttachments = [];
  List<String> secondaryAttachments = [];

  bool get isLoading => _loading;
  String? get error => _error;
  List<Project> get projectOptions => _options;
  VariationOrder? get existing => _existing;
  int? get savedId => _savedId;
  String? get savedVoNo => _savedVoNo;

  bool get hasRevisedSchedule {
    final items = revisedSchedule?['items'];
    return items is List && items.isNotEmpty;
  }

  Future<void> load() async {
    try {
      final role = _session.activeRole!;
      _options = (await _projects.getProjectsFor(
        _session.user!.id,
        role,
      )).where((p) =>
          p.status != ProjectStatus.completed &&
          p.status != ProjectStatus.closed).toList();
      if (voId != null) {
        _existing = (await _billing.getVariationOrder(voId!))?.order;
        if (_existing == null) {
          _error = 'Variation order not found.';
          return;
        }
        if (_existing!.status != VariationOrderStatus.proposed) {
          _error = 'Only proposed VOs can be edited.';
          return;
        }
        projectId = _existing!.projectId;
        type = _existing!.type;
        revisedSchedule = _existing!.revisedSchedule;
        primaryAttachments = List<String>.from(_existing!.primaryAttachments);
        secondaryAttachments = List<String>.from(
          _existing!.secondaryAttachments,
        );
      } else {
        if (_options.isEmpty) {
          _error = 'You have no ongoing project to raise a VO on.';
          return;
        }
        projectId = _options.any((p) => p.id == initialProjectId)
            ? initialProjectId
            : _options.first.id;
      }
    } catch (e) {
      _error = 'Could not load the form. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void setProject(int? id) {
    if (projectId == id) return;
    projectId = id;
    revisedSchedule = null;
    notifyListeners();
  }

  void setType(VariationOrderType t) {
    type = t;
    if (t != VariationOrderType.change) {
      secondaryAttachments = [];
    }
    notifyListeners();
  }

  void setRevisedSchedule(Map<String, dynamic>? schedule) {
    revisedSchedule = schedule;
    notifyListeners();
  }

  void addPrimaryAttachments(List<String> paths) {
    final added = paths.where((p) => !primaryAttachments.contains(p)).toList();
    if (added.isEmpty) return;
    primaryAttachments = [...primaryAttachments, ...added];
    notifyListeners();
  }

  void removePrimaryAttachment(int index) {
    if (index < 0 || index >= primaryAttachments.length) return;
    primaryAttachments = [
      ...primaryAttachments.sublist(0, index),
      ...primaryAttachments.sublist(index + 1),
    ];
    notifyListeners();
  }

  void addSecondaryAttachments(List<String> paths) {
    final added = paths
        .where((p) => !secondaryAttachments.contains(p))
        .toList();
    if (added.isEmpty) return;
    secondaryAttachments = [...secondaryAttachments, ...added];
    notifyListeners();
  }

  void removeSecondaryAttachment(int index) {
    if (index < 0 || index >= secondaryAttachments.length) return;
    secondaryAttachments = [
      ...secondaryAttachments.sublist(0, index),
      ...secondaryAttachments.sublist(index + 1),
    ];
    notifyListeners();
  }

  Future<String?> save({required String description}) => runAction(() async {
    if (projectId == null) {
      throw const BusinessRuleException('Choose the project.');
    }
    if (!hasRevisedSchedule) {
      throw const BusinessRuleException(
        'Upload the revised Bar Chart (.xlsx) before saving this variation order.',
      );
    }

    final derivedDays = (revisedSchedule?['days_impact'] as int?) ?? 0;
    final derivedAmount =
        JsonUtils.toDoubleOrNull(revisedSchedule?['net_cost_impact']) ?? 0;

    final base =
        _existing ??
        VariationOrder(
          id: 0,
          projectId: projectId!,
          voNo: '',
          type: type,
          description: '',
          amount: 0,
          daysImpact: 0,
          status: VariationOrderStatus.proposed,
          createdAt: DateTime.now(),
        );

    final saved = await _billing.saveVariationOrder(
      base.copyWith(
        type: type,
        description: description.trim(),
        amount: derivedAmount,
        daysImpact: derivedDays,
        revisedSchedule: () => revisedSchedule,
        primaryAttachments: List<String>.unmodifiable(primaryAttachments),
        secondaryAttachments: type == VariationOrderType.change
            ? List<String>.unmodifiable(secondaryAttachments)
            : const [],
      ),
      userId: _session.user!.id,
    );
    _savedId = saved.id;
    _savedVoNo = saved.voNo;
  });
}

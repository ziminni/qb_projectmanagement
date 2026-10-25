import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/models/project.dart';
import '../../../data/models/variation_order.dart';
import '../../../data/repositories/billing_repository.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/services/business_rule_exception.dart';
import '../../../data/services/session_service.dart';

/// Raise a VO (site engineer or PM) or edit a proposed one (PM).
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

  int? projectId;
  VariationOrderType type = VariationOrderType.additive;

  bool get isLoading => _loading;
  String? get error => _error;
  List<Project> get projectOptions => _options;
  VariationOrder? get existing => _existing;
  int? get savedId => _savedId;

  Future<void> load() async {
    try {
      final role = _session.activeRole!;
      _options = (await _projects.getProjectsFor(
        _session.user!.id,
        role,
      )).where((p) => p.status == ProjectStatus.ongoing).toList();
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
    projectId = id;
    notifyListeners();
  }

  void setType(VariationOrderType t) {
    type = t;
    notifyListeners();
  }

  Future<String?> save({
    required String description,
    required double amount,
    required int daysImpact,
  }) => runAction(() async {
    if (projectId == null) {
      throw const BusinessRuleException('Choose the project.');
    }
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
        description: description,
        amount: amount,
        daysImpact: daysImpact,
      ),
      userId: _session.user!.id,
    );
    _savedId = saved.id;
  });
}

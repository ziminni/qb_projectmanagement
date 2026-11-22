import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/models/category.dart';
import '../../../data/models/project.dart';
import '../../../data/models/todo.dart';
import '../../../data/models/variation_order.dart';
import '../../../data/repositories/billing_repository.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/repositories/schedule_repository.dart';
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
    required ScheduleRepository schedule,
  }) : _session = session,
       _projects = projects,
       _billing = billing,
       _schedule = schedule;

  /// Sentinel dropdown value indicating the user wants to type a custom task.
  static const int customTaskSentinel = -1;

  final int? voId;
  final int? initialProjectId;
  final SessionService _session;
  final ProjectRepository _projects;
  final BillingRepository _billing;
  final ScheduleRepository _schedule;

  bool _loading = true;
  bool _loadingWorkItems = false;
  String? _error;
  List<Project> _options = const [];
  List<Category> _categories = const [];
  List<Todo> _todos = const [];
  VariationOrder? _existing;
  int? _savedId;
  String? _savedVoNo;

  int? projectId;
  int? categoryId;
  int? todoSelection; // null = none, -1 = custom task, >0 = existing todo id
  VariationOrderType type = VariationOrderType.additive;
  DateTime? workStartDate;
  DateTime? workEndDate;
  List<String> primaryAttachments = [];
  List<String> secondaryAttachments = [];

  bool get isLoading => _loading;
  bool get isLoadingWorkItems => _loadingWorkItems;
  String? get error => _error;
  List<Project> get projectOptions => _options;
  List<Category> get categories => _categories;
  VariationOrder? get existing => _existing;
  int? get savedId => _savedId;
  String? get savedVoNo => _savedVoNo;

  bool get isCustomTask => todoSelection == customTaskSentinel;

  List<Todo> get todosForSelectedCategory {
    if (categoryId == null) return _todos;
    return _todos.where((t) => t.categoryId == categoryId).toList();
  }

  Category? get selectedCategory {
    if (categoryId == null) return null;
    for (final c in _categories) {
      if (c.id == categoryId) return c;
    }
    return null;
  }

  Todo? get selectedTodo {
    if (todoSelection == null || todoSelection == customTaskSentinel) {
      return null;
    }
    for (final t in _todos) {
      if (t.id == todoSelection) return t;
    }
    return null;
  }

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
        workStartDate = _existing!.workStartDate;
        workEndDate = _existing!.workEndDate;
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
      if (projectId != null) {
        await _loadWorkItems(projectId!);
      }
    } catch (e) {
      _error = 'Could not load the form. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _loadWorkItems(int id) async {
    _loadingWorkItems = true;
    notifyListeners();
    try {
      final results = await Future.wait([
        _schedule.getCategories(id),
        _schedule.getTodos(id),
      ]);
      _categories = results[0] as List<Category>;
      _todos = results[1] as List<Todo>;
    } catch (_) {
      _categories = const [];
      _todos = const [];
    } finally {
      _loadingWorkItems = false;
      notifyListeners();
    }
  }

  Future<void> setProject(int? id) async {
    if (projectId == id) return;
    projectId = id;
    categoryId = null;
    todoSelection = null;
    notifyListeners();
    if (id != null) {
      await _loadWorkItems(id);
    }
  }

  void setCategory(int? id) {
    if (categoryId == id) return;
    categoryId = id;
    // Reset selected to-do if it no longer belongs to the chosen item of work.
    if (todoSelection != null &&
        todoSelection != customTaskSentinel &&
        !todosForSelectedCategory.any((t) => t.id == todoSelection)) {
      todoSelection = null;
    }
    notifyListeners();
  }

  void setTodoSelection(int? value) {
    if (todoSelection == value) return;
    todoSelection = value;
    final todo = selectedTodo;
    if (todo != null && workStartDate == null && workEndDate == null) {
      workStartDate = todo.startDate;
      workEndDate = todo.endDate;
    }
    notifyListeners();
  }

  void setWorkStartDate(DateTime? date) {
    workStartDate = date;
    if (date != null && workEndDate != null && workEndDate!.isBefore(date)) {
      workEndDate = date;
    }
    notifyListeners();
  }

  void setWorkEndDate(DateTime? date) {
    workEndDate = date;
    notifyListeners();
  }

  void setType(VariationOrderType t) {
    type = t;
    if (t != VariationOrderType.change) {
      secondaryAttachments = [];
    }
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

  Future<String?> save({
    required String description,
    String? customTask,
    required double amount,
    required int daysImpact,
  }) => runAction(() async {
    if (projectId == null) {
      throw const BusinessRuleException('Choose the project.');
    }

    final itemName = selectedCategory?.name.trim();
    final taskName = isCustomTask
        ? customTask?.trim()
        : selectedTodo?.title.trim();
    final headerParts = <String>[
      if (itemName != null && itemName.isNotEmpty) itemName,
      if (taskName != null && taskName.isNotEmpty) taskName,
    ];
    final cleanDesc = description.trim();
    final prefix = headerParts.isEmpty ? '' : '[${headerParts.join(' · ')}]';
    final fullDescription = prefix.isEmpty || cleanDesc.startsWith(prefix)
        ? cleanDesc
        : '$prefix $cleanDesc';

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
    if (workStartDate != null &&
        workEndDate != null &&
        workEndDate!.isBefore(workStartDate!)) {
      throw const BusinessRuleException(
        'End date must be on or after the start date.',
      );
    }

    final saved = await _billing.saveVariationOrder(
      base.copyWith(
        type: type,
        description: fullDescription,
        amount: amount,
        daysImpact: daysImpact,
        workStartDate: () => workStartDate,
        workEndDate: () => workEndDate,
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

import 'dart:typed_data';

import '../../routes/routes.dart';
import '../models/app_role.dart';
import '../models/category.dart';
import '../models/planned_material.dart';
import '../models/project.dart';
import '../models/todo.dart';
import '../services/notification_service.dart';
import '../services/schedule_rules.dart';
import 'audit_log_repository.dart';
import 'mock_data.dart';
import 'project_repository.dart';
import 'schedule_repository.dart';

/// In-memory schedule data. Enforces the same rules the backend will.
class MockScheduleRepository implements ScheduleRepository {
  MockScheduleRepository({
    required ProjectRepository projects,
    required AuditLogRepository auditLog,
    NotificationService? notifications,
  }) : _projects = projects,
       _auditLog = auditLog,
       _notifications = notifications;

  final ProjectRepository _projects;
  final AuditLogRepository _auditLog;
  final NotificationService? _notifications;
  final _categories = [...MockData.categories];
  final _todos = [...MockData.todos];
  final _plannedMaterials = <PlannedMaterial>[
    const PlannedMaterial(
      id: 1,
      projectId: 1,
      categoryId: 1,
      categoryName: 'Site preparation & foundation',
      name: 'Portland Cement (40kg)',
      unit: 'bags',
      plannedQty: 250,
      unitCost: 245,
      requestedQty: 180,
      deliveredQty: 150,
    ),
    const PlannedMaterial(
      id: 2,
      projectId: 1,
      categoryId: 1,
      categoryName: 'Site preparation & foundation',
      name: '12mm Deformed Rebar',
      unit: 'pcs',
      plannedQty: 180,
      unitCost: 265,
      requestedQty: 120,
      deliveredQty: 120,
    ),
  ];

  int get _nextCategoryId =>
      _categories.fold(0, (m, c) => c.id > m ? c.id : m) + 1;

  int get _nextTodoId => _todos.fold(0, (m, t) => t.id > m ? t.id : m) + 1;

  @override
  Future<List<Category>> getCategories(int projectId) async =>
      _categories.where((c) => c.projectId == projectId).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  @override
  Future<List<Todo>> getTodos(int projectId) async {
    final ids = {
      for (final c in _categories)
        if (c.projectId == projectId) c.id,
    };
    return _todos.where((t) => ids.contains(t.categoryId)).toList();
  }

  @override
  Future<Category> saveCategory(Category category) async {
    final project = await _projects.getProject(category.projectId);
    if (project == null) {
      throw const ScheduleRuleException('Project not found.');
    }
    ScheduleRules.enforce(ScheduleRules.validateCategoryName(category.name));
    ScheduleRules.enforce(ScheduleRules.validateBudget(category.budget));
    final others = _categories
        .where((c) => c.projectId == category.projectId && c.id != category.id)
        .fold<double>(0, (s, c) => s + (c.budget ?? 0));
    ScheduleRules.enforce(
      ScheduleRules.validateBudgetTotal(
        budget: category.budget,
        otherBudgetsTotal: others,
        contractAmount: project.contractAmount,
      ),
    );

    final now = DateTime.now();
    if (category.id == 0) {
      final created = Category(
        id: _nextCategoryId,
        projectId: category.projectId,
        name: category.name.trim(),
        budget: category.budget,
        sortOrder: category.sortOrder,
        createdAt: now,
        updatedAt: now,
      );
      _categories.add(created);
      return created;
    }
    final index = _indexOfCategory(category.id);
    final updated = category.copyWith(
      name: category.name.trim(),
      updatedAt: now,
    );
    _categories[index] = updated;
    return updated;
  }

  @override
  Future<void> deleteCategory(int categoryId) async {
    final index = _indexOfCategory(categoryId);
    final categoryTodos = _todos.where((t) => t.categoryId == categoryId);
    ScheduleRules.enforce(
      ScheduleRules.canDeleteCategory(categoryTodos.toList()),
    );
    _todos.removeWhere((t) => t.categoryId == categoryId);
    _categories.removeAt(index);
  }

  @override
  Future<Todo> saveTodo(Todo todo) async {
    final category = _categories[_indexOfCategory(todo.categoryId)];
    final project = await _projects.getProject(category.projectId);
    if (project == null) {
      throw const ScheduleRuleException('Project not found.');
    }
    ScheduleRules.enforce(ScheduleRules.validateTodoTitle(todo.title));
    ScheduleRules.enforce(
      ScheduleRules.validateTodoDates(
        start: todo.startDate,
        end: todo.endDate,
        project: project,
        category: category,
      ),
    );

    final now = DateTime.now();
    if (todo.id == 0) {
      final created = Todo(
        id: _nextTodoId,
        categoryId: todo.categoryId,
        title: todo.title.trim(),
        startDate: todo.startDate,
        endDate: todo.endDate,
        createdAt: now,
        updatedAt: now,
      );
      _todos.add(created);
      return created;
    }
    // Completion and verification change only through setDone / verify.
    final index = _indexOfTodo(todo.id);
    final updated = _todos[index].copyWith(
      categoryId: todo.categoryId,
      title: todo.title.trim(),
      startDate: todo.startDate,
      endDate: todo.endDate,
      updatedAt: now,
    );
    _todos[index] = updated;
    return updated;
  }

  @override
  Future<void> deleteTodo(int todoId) async {
    final index = _indexOfTodo(todoId);
    ScheduleRules.enforce(ScheduleRules.canDeleteTodo(_todos[index]));
    _todos.removeAt(index);
  }

  @override
  Future<Todo> setDone(
    int todoId, {
    required bool done,
    required int userId,
    int? dailyReportId,
  }) async {
    final index = _indexOfTodo(todoId);
    final todo = _todos[index];
    ScheduleRules.enforce(ScheduleRules.canSetDone(todo, done));
    if (todo.isDone == done) return todo;

    final now = DateTime.now();
    final updated = todo.copyWith(
      isDone: done,
      doneBy: () => done ? userId : null,
      doneAt: () => done ? now : null,
      dailyReportId: dailyReportId == null ? null : () => dailyReportId,
      updatedAt: now,
    );
    _todos[index] = updated;
    await _auditLog.record(
      userId: userId,
      action: done ? 'todo_marked_done' : 'todo_marked_not_done',
      entity: 'todo',
      entityId: todoId,
    );
    if (done) {
      final category = _categories[_indexOfCategory(todo.categoryId)];
      final project = await _projects.getProject(category.projectId);
      await _notifications?.notifyProjectRole(
        category.projectId,
        AppRole.owner,
        type: 'todo_done',
        message:
            '"${todo.title}" was marked done on ${project?.code ?? 'a project'}. '
            'Verify it.',
        link: AppRoutes.todoVerification,
      );
    }
    return updated;
  }

  @override
  Future<Todo> setReportLink(int todoId, int? dailyReportId) async {
    final index = _indexOfTodo(todoId);
    final updated = _todos[index].copyWith(
      dailyReportId: () => dailyReportId,
      updatedAt: DateTime.now(),
    );
    _todos[index] = updated;
    return updated;
  }

  @override
  Future<Todo> verify(int todoId, {required int userId}) async {
    final index = _indexOfTodo(todoId);
    ScheduleRules.enforce(ScheduleRules.canVerify(_todos[index]));

    final now = DateTime.now();
    final updated = _todos[index].copyWith(
      isVerified: true,
      verifiedBy: () => userId,
      verifiedAt: () => now,
      updatedAt: now,
    );
    _todos[index] = updated;
    await _auditLog.record(
      userId: userId,
      action: 'todo_verified',
      entity: 'todo',
      entityId: todoId,
    );
    return updated;
  }

  @override
  Future<Todo> unverify(
    int todoId, {
    required int userId,
    required String reason,
  }) async {
    final index = _indexOfTodo(todoId);
    ScheduleRules.enforce(ScheduleRules.canUnverify(_todos[index], reason));

    final updated = _todos[index].copyWith(
      isVerified: false,
      verifiedBy: () => null,
      verifiedAt: () => null,
      updatedAt: DateTime.now(),
    );
    _todos[index] = updated;
    await _auditLog.record(
      userId: userId,
      action: 'todo_unverified',
      entity: 'todo',
      entityId: todoId,
      details: {'reason': reason.trim()},
    );
    return updated;
  }

  int _indexOfCategory(int id) {
    final index = _categories.indexWhere((c) => c.id == id);
    if (index < 0) throw const ScheduleRuleException('Category not found.');
    return index;
  }

  int _indexOfTodo(int id) {
    final index = _todos.indexWhere((t) => t.id == id);
    if (index < 0) throw const ScheduleRuleException('To-do not found.');
    return index;
  }

  @override
  Future<List<PlannedMaterial>> getPlannedMaterials(int projectId) async => [
    for (final m in _plannedMaterials)
      if (m.projectId == projectId) m,
  ];

  @override
  Future<PlannedMaterial> savePlannedMaterial(PlannedMaterial item) async {
    final catName = _categories
        .where((c) => c.id == item.categoryId)
        .firstOrNull
        ?.name;
    if (item.id == 0) {
      final nextId = _plannedMaterials.isEmpty
          ? 1
          : _plannedMaterials.map((e) => e.id).reduce((a, b) => a > b ? a : b) +
                1;
      final created = item.copyWith(
        id: nextId,
        categoryName: () => catName,
      );
      _plannedMaterials.add(created);
      return created;
    }
    final idx = _plannedMaterials.indexWhere((e) => e.id == item.id);
    if (idx < 0) {
      throw const ScheduleRuleException('Planned material not found.');
    }
    final updated = item.copyWith(categoryName: () => catName);
    _plannedMaterials[idx] = updated;
    return updated;
  }

  @override
  Future<void> deletePlannedMaterial(int id) async {
    _plannedMaterials.removeWhere((e) => e.id == id);
  }

  @override
  Future<ItemsExcelPreview> previewBarChartForNewProject({
    required String fileName,
    required Uint8List bytes,
    required DateTime startDate,
    String? sheetName,
  }) async {
    final end = startDate.add(const Duration(days: 18));
    return ItemsExcelPreview(
      sheet: sheetName ?? 'REVISED',
      sheets: const ['REVISED', 'REVISED +23cd'],
      format: 'bar_chart',
      targetEndDate: end,
      totalDays: 19,
      totalBudget: 250000,
      items: [
        ItemsExcelRow(
          itemNo: 'B3',
          name: 'B3 — Permits and Clearances',
          budget: 100000,
          plannedWeeks: 'Week 1',
          plannedDays: 7,
          dayToStart: 1,
          startDate: startDate,
          endDate: startDate.add(const Duration(days: 6)),
        ),
        ItemsExcelRow(
          itemNo: '803(1)',
          name: '803(1) — Structure Excavation',
          budget: 150000,
          plannedWeeks: 'Week 2-3',
          plannedDays: 12,
          dayToStart: 8,
          startDate: startDate.add(const Duration(days: 7)),
          endDate: end,
        ),
      ],
    );
  }

  @override
  Future<ItemsExcelPreview> previewItemsExcel(
    int projectId, {
    required String fileName,
    required Uint8List bytes,
    String? sheetName,
  }) async {
    final project = await _projects.getProject(projectId);
    final base = project?.startDate ?? DateTime.now();
    return ItemsExcelPreview(
      sheet: sheetName ?? 'Sheet1',
      sheets: const ['Sheet1'],
      format: 'simple',
      items: [
        ItemsExcelRow(
          name: 'Mobilization & Site Clearing',
          plannedWeeks: 'Week 1',
          plannedDays: 7,
          startDate: base,
          endDate: base.add(const Duration(days: 6)),
        ),
        ItemsExcelRow(
          name: 'Excavation & Earthworks',
          plannedWeeks: '2-3',
          plannedDays: 12,
          startDate: base.add(const Duration(days: 7)),
          endDate: base.add(const Duration(days: 18)),
        ),
      ],
    );
  }

  @override
  Future<int> importItemsExcel(
    int projectId, {
    required String fileName,
    required Uint8List bytes,
    String? sheetName,
    bool replaceExisting = false,
  }) async {
    final preview = await previewItemsExcel(
      projectId,
      fileName: fileName,
      bytes: bytes,
      sheetName: sheetName,
    );
    if (replaceExisting) {
      _categories.removeWhere((c) => c.projectId == projectId);
    }
    final rows = preview.items;
    for (final r in rows) {
      await saveCategory(
        Category(
          id: 0,
          projectId: projectId,
          name: r.name,
          plannedWeeks: r.plannedWeeks,
          plannedDays: r.plannedDays,
          startDate: r.startDate,
          endDate: r.endDate,
          sortOrder: _categories.length + 1,
        ),
      );
    }
    return rows.length;
  }

  @override
  Future<Project> startTimeline(int projectId, DateTime startDate) async {
    final project = (await _projects.getProject(projectId))!;
    final prevBase = project.timelineStartDate ?? project.startDate;
    for (var i = 0; i < _categories.length; i++) {
      final c = _categories[i];
      if (c.projectId != projectId) continue;
      final offset =
          c.dayToStart ??
          (c.startDate != null
              ? (c.startDate!.difference(prevBase).inDays + 1).clamp(1, 9999)
              : null);
      final dur =
          c.plannedDays ??
          (c.startDate != null && c.endDate != null
              ? (c.endDate!.difference(c.startDate!).inDays + 1).clamp(1, 9999)
              : null);
      if (offset != null && dur != null) {
        final ns = startDate.add(Duration(days: offset - 1));
        final ne = ns.add(Duration(days: dur - 1));
        _categories[i] = c.copyWith(
          dayToStart: () => offset,
          plannedDays: () => dur,
          startDate: () => ns,
          endDate: () => ne,
        );
      }
    }
    return Project(
      id: project.id,
      code: project.code,
      name: project.name,
      location: project.location,
      latitude: project.latitude,
      longitude: project.longitude,
      clientId: project.clientId,
      contractAmount: project.contractAmount,
      downPaymentPct: project.downPaymentPct,
      retentionPct: project.retentionPct,
      startDate: project.startDate,
      timelineStartDate: startDate,
      targetEndDate: project.targetEndDate,
      actualEndDate: project.actualEndDate,
      status: project.status,
      createdAt: project.createdAt,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<DupaImportPreview> previewDupaExcel(
    int projectId, {
    required String fileName,
    required Uint8List bytes,
    int? categoryId,
    String? sheetName,
  }) async => const DupaImportPreview(
    items: [
      DupaPreviewItem(
        sheet: 'B.7(2)',
        itemNo: 'B.7(2)',
        name: 'B.7(2) — Occupational Safety & Health Program',
        budget: 100913.40,
        laborBudget: 60000,
        equipmentBudget: 0,
        materialBudget: 20090,
        materials: [
          DupaPreviewMaterial(
            name: 'Reflectorized Vest',
            unit: 'pcs',
            plannedQty: 10,
            unitCost: 200,
            amount: 2000,
          ),
          DupaPreviewMaterial(
            name: 'Safety Shoes',
            unit: 'pairs',
            plannedQty: 2,
            unitCost: 1300,
            amount: 2600,
          ),
        ],
      ),
    ],
    totalItems: 1,
    totalMaterials: 2,
    totalBudget: 100913.40,
  );

  @override
  Future<DupaImportResult> importDupaExcel(
    int projectId, {
    required String fileName,
    required Uint8List bytes,
    int? categoryId,
    String? sheetName,
    List<String>? selectedSheets,
    Map<String, int>? sheetCategoryMap,
  }) async {
    final preview = await previewDupaExcel(
      projectId,
      fileName: fileName,
      bytes: bytes,
      categoryId: categoryId,
      sheetName: sheetName,
    );
    var matCount = 0;
    for (final item in preview.items) {
      final cat = await saveCategory(
        Category(
          id: 0,
          projectId: projectId,
          name: item.name,
          budget: item.budget,
          sortOrder: _categories.length + 1,
        ),
      );
      for (final m in item.materials) {
        await savePlannedMaterial(
          PlannedMaterial(
            id: 0,
            projectId: projectId,
            categoryId: cat.id,
            categoryName: cat.name,
            name: m.name,
            unit: m.unit,
            plannedQty: m.plannedQty,
            unitCost: m.unitCost,
          ),
        );
        matCount++;
      }
    }
    return DupaImportResult(
      itemsImported: preview.items.length,
      materialsImported: matCount,
      totalBudget: preview.totalBudget,
    );
  }

  @override
  Future<Uint8List> downloadBarChartTemplate({
    String variant = 'combined',
  }) async => Uint8List(0);
}

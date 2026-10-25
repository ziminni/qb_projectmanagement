import '../models/category.dart';
import '../models/project.dart';
import '../models/todo.dart';

/// The single place project and category progress are computed. The progress
/// bar, Financials and the Gantt chart all read from [computeProjectProgress]
/// so their numbers never disagree. Nothing here is stored.

enum CategoryStatus {
  notStarted('Not started'),
  inProgress('In progress'),
  completed('Completed');

  const CategoryStatus(this.label);

  final String label;
}

class CategoryProgress {
  const CategoryProgress({
    required this.category,
    required this.todos,
    required this.totalTodos,
    required this.verifiedTodos,
    required this.awaitingVerification,
    required this.progress,
    required this.plannedProgress,
    required this.weight,
    required this.status,
    required this.startDate,
    required this.endDate,
  });

  final Category category;

  /// The category's to-dos, ordered by start date.
  final List<Todo> todos;
  final int totalTodos;
  final int verifiedTodos;

  /// Marked done on site but not yet verified; does not count toward progress.
  final int awaitingVerification;

  /// Verified done to-dos ÷ total to-dos, 0–1.
  final double progress;

  /// Share of the category's scheduled work that should be finished by the
  /// reference date, 0–1.
  final double plannedProgress;

  /// Share of the project this category represents, 0–1.
  final double weight;
  final CategoryStatus status;

  /// Earliest to-do start and latest to-do end; null when there are no to-dos.
  final DateTime? startDate;
  final DateTime? endDate;
}

class ProjectProgress {
  const ProjectProgress({
    required this.categories,
    required this.progress,
    required this.plannedProgress,
    required this.usesBudgetWeights,
    required this.contractAmount,
    required this.totalBudget,
    required this.asOf,
  });

  /// Ordered by `sort_order`.
  final List<CategoryProgress> categories;

  /// Sum of category weight × category progress, 0–1.
  final double progress;

  /// Where the schedule says the project should be on [asOf], 0–1.
  final double plannedProgress;

  /// False when any category lacks a budget and equal weights are used.
  final bool usesBudgetWeights;
  final double contractAmount;

  /// Sum of category budgets that are set.
  final double totalBudget;
  final DateTime asOf;

  /// % accomplished × contract amount; feeds Financials and progress billing.
  double get earnedValue => progress * contractAmount;

  /// Positive when actual progress is behind plan, in percentage points (0–1).
  double get scheduleVariance => plannedProgress - progress;

  CategoryProgress? categoryById(int id) {
    for (final c in categories) {
      if (c.category.id == id) return c;
    }
    return null;
  }
}

/// Computes progress for one project.
///
/// [asOf] limits counting to to-dos verified on or before that date, which is
/// what a progress billing uses for its period end. It also sets the date the
/// planned progress is measured at. Defaults to today.
ProjectProgress computeProjectProgress({
  required Project project,
  required List<Category> categories,
  required List<Todo> todos,
  DateTime? asOf,
}) {
  final refDate = _dateOnly(asOf ?? DateTime.now());
  final sorted = [...categories]
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  final usesBudgetWeights =
      sorted.isNotEmpty && sorted.every((c) => c.hasBudget);
  final totalBudget = sorted.fold<double>(
    0,
    (sum, c) => sum + (c.hasBudget ? c.budget! : 0),
  );

  final results = <CategoryProgress>[];
  var progress = 0.0;
  var planned = 0.0;

  for (final category in sorted) {
    final categoryTodos =
        todos.where((t) => t.categoryId == category.id).toList()
          ..sort((a, b) => a.startDate.compareTo(b.startDate));
    final total = categoryTodos.length;
    final verified = categoryTodos
        .where((t) => _countsAsVerified(t, refDate))
        .length;
    final awaiting = categoryTodos
        .where((t) => t.isDone && !_countsAsVerified(t, refDate))
        .length;

    final categoryProgress = total == 0 ? 0.0 : verified / total;
    final categoryPlanned = total == 0
        ? 0.0
        : categoryTodos
                  .map((t) => _plannedFraction(t, refDate))
                  .fold<double>(0, (a, b) => a + b) /
              total;
    final weight = usesBudgetWeights
        ? category.budget! / totalBudget
        : 1 / sorted.length;

    progress += weight * categoryProgress;
    planned += weight * categoryPlanned;

    results.add(
      CategoryProgress(
        category: category,
        todos: categoryTodos,
        totalTodos: total,
        verifiedTodos: verified,
        awaitingVerification: awaiting,
        progress: categoryProgress,
        plannedProgress: categoryPlanned,
        weight: weight,
        status: _statusFor(verified, total),
        startDate: total == 0 ? null : categoryTodos.first.startDate,
        endDate: total == 0
            ? null
            : categoryTodos
                  .map((t) => t.endDate)
                  .reduce((a, b) => a.isAfter(b) ? a : b),
      ),
    );
  }

  return ProjectProgress(
    categories: results,
    progress: progress.clamp(0, 1),
    plannedProgress: planned.clamp(0, 1),
    usesBudgetWeights: usesBudgetWeights,
    contractAmount: project.contractAmount,
    totalBudget: totalBudget,
    asOf: refDate,
  );
}

CategoryStatus _statusFor(int verified, int total) {
  if (verified == 0) return CategoryStatus.notStarted;
  if (verified == total) return CategoryStatus.completed;
  return CategoryStatus.inProgress;
}

bool _countsAsVerified(Todo todo, DateTime refDate) {
  if (!todo.isVerified) return false;
  final verifiedAt = todo.verifiedAt;
  if (verifiedAt == null) return true;
  return !_dateOnly(verifiedAt.toLocal()).isAfter(refDate);
}

/// Linear share of a to-do's scheduled days that have elapsed by [date].
double _plannedFraction(Todo todo, DateTime date) {
  final start = _dateOnly(todo.startDate);
  final end = _dateOnly(todo.endDate);
  final duration = end.difference(start).inDays + 1;
  final elapsed = date.difference(start).inDays + 1;
  return (elapsed / duration).clamp(0, 1).toDouble();
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// One point on the S-curve: planned and actual cumulative progress (0–1)
/// at [date]. [actual] is null for dates after today.
class SCurvePoint {
  const SCurvePoint(this.date, this.planned, this.actual);

  final DateTime date;
  final double planned;
  final double? actual;
}

/// Planned vs. actual S-curve sampled every [stepDays] from the project start
/// to its target end, built from [computeProjectProgress] so it matches the
/// progress bar.
List<SCurvePoint> computeSCurve({
  required Project project,
  required List<Category> categories,
  required List<Todo> todos,
  DateTime? today,
  int stepDays = 7,
}) {
  final now = _dateOnly(today ?? DateTime.now());
  final start = _dateOnly(project.startDate);
  final end = _dateOnly(project.targetEndDate);
  final dates = <DateTime>[];
  for (var d = start; !d.isAfter(end); d = d.add(Duration(days: stepDays))) {
    dates.add(d);
  }
  if (dates.isEmpty || dates.last != end) dates.add(end);
  if (!now.isBefore(start) && !now.isAfter(end) && !dates.contains(now)) {
    dates
      ..add(now)
      ..sort();
  }
  return [
    for (final d in dates)
      () {
        final p = computeProjectProgress(
          project: project,
          categories: categories,
          todos: todos,
          asOf: d,
        );
        return SCurvePoint(
          d,
          p.plannedProgress,
          d.isAfter(now) ? null : p.progress,
        );
      }(),
  ];
}

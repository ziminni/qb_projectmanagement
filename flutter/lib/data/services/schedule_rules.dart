import '../models/category.dart';
import '../models/project.dart';
import '../models/todo.dart';
import 'business_rule_exception.dart';

/// Business rules for categories and to-dos. Shared by the repositories
/// (standing in for backend enforcement) and the schedule forms, so the same
/// messages show whether a form or a direct call breaks a rule.
class ScheduleRuleException extends BusinessRuleException {
  const ScheduleRuleException(super.message);
}

abstract final class ScheduleRules {
  static String? validateCategoryName(String? name) =>
      (name == null || name.trim().isEmpty) ? 'Enter a category name.' : null;

  static String? validateBudget(double? budget) =>
      (budget != null && budget < 0) ? 'Budget cannot be negative.' : null;

  /// Total category budgets cannot exceed the contract amount.
  /// [otherBudgetsTotal] excludes the category being saved.
  static String? validateBudgetTotal({
    required double? budget,
    required double otherBudgetsTotal,
    required double contractAmount,
  }) {
    final total = otherBudgetsTotal + (budget ?? 0);
    if (total > contractAmount) {
      return 'Total category budgets (₱${_amount(total)}) would exceed the '
          'contract amount (₱${_amount(contractAmount)}).';
    }
    return null;
  }

  /// Warning (not an error) when budgets fall short of the contract amount.
  static String? budgetShortfallWarning({
    required List<Category> categories,
    required double contractAmount,
  }) {
    if (categories.isEmpty) return null;
    final total = categories.fold<double>(0, (s, c) => s + (c.budget ?? 0));
    if (total < contractAmount) {
      return 'Category budgets total ₱${_amount(total)}, which is '
          '₱${_amount(contractAmount - total)} below the contract amount.';
    }
    return null;
  }

  static String? validateTodoTitle(String? title) =>
      (title == null || title.trim().isEmpty) ? 'Enter a to-do title.' : null;

  /// To-do dates must fall within the project's start and target end dates,
  /// with the end on or after the start.
  static String? validateTodoDates({
    required DateTime? start,
    required DateTime? end,
    required Project project,
  }) {
    if (start == null || end == null) return 'Choose start and end dates.';
    if (_day(end).isBefore(_day(start))) {
      return 'End date must be on or after the start date.';
    }
    if (_day(start).isBefore(_day(project.startDate)) ||
        _day(end).isAfter(_day(project.targetEndDate))) {
      return 'Dates must fall within the project schedule '
          '(${_d(project.startDate)} to ${_d(project.targetEndDate)}).';
    }
    return null;
  }

  /// A category with verified to-dos cannot be deleted.
  static String? canDeleteCategory(List<Todo> categoryTodos) =>
      categoryTodos.any((t) => t.isVerified)
      ? 'This category has verified to-dos and cannot be deleted.'
      : null;

  static String? canDeleteTodo(Todo todo) => todo.isVerified
      ? 'A verified to-do cannot be deleted. Un-verify it first.'
      : null;

  static String? canSetDone(Todo todo, bool done) => (!done && todo.isVerified)
      ? 'This to-do is verified. The PM must un-verify it first.'
      : null;

  static String? canVerify(Todo todo) {
    if (todo.isVerified) return 'This to-do is already verified.';
    if (!todo.isDone) return 'Only to-dos marked done can be verified.';
    return null;
  }

  static String? canUnverify(Todo todo, String? reason) {
    if (!todo.isVerified) return 'This to-do is not verified.';
    if (reason == null || reason.trim().isEmpty) {
      return 'Enter a reason for un-verifying.';
    }
    return null;
  }

  static void enforce(String? error) {
    if (error != null) throw ScheduleRuleException(error);
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _d(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String _amount(double v) {
    final whole = v.round().toString();
    return whole.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  }
}

import 'package:flutter/material.dart';

import '../../../data/services/schedule_rules.dart';

class ScheduleCategoryFormResult {
  const ScheduleCategoryFormResult(
    this.name,
    this.budget, {
    this.plannedWeeks,
    this.plannedDays,
  });

  final String name;
  final double? budget;
  final String? plannedWeeks;
  final int? plannedDays;
}

/// Add or edit an Item of Work (Name, Weeks, Days, and optional Budget).
class ScheduleCategoryFormDialog extends StatefulWidget {
  const ScheduleCategoryFormDialog({
    super.key,
    this.initialName,
    this.initialBudget,
    this.initialWeeks,
    this.initialDays,
    required this.validateBudgetTotal,
  });

  final String? initialName;
  final double? initialBudget;
  final String? initialWeeks;
  final int? initialDays;
  final String? Function(double? budget) validateBudgetTotal;

  static Future<ScheduleCategoryFormResult?> show(
    BuildContext context, {
    String? initialName,
    double? initialBudget,
    String? initialWeeks,
    int? initialDays,
    required String? Function(double? budget) validateBudgetTotal,
  }) => showDialog<ScheduleCategoryFormResult>(
    context: context,
    builder: (_) => ScheduleCategoryFormDialog(
      initialName: initialName,
      initialBudget: initialBudget,
      initialWeeks: initialWeeks,
      initialDays: initialDays,
      validateBudgetTotal: validateBudgetTotal,
    ),
  );

  @override
  State<ScheduleCategoryFormDialog> createState() =>
      _ScheduleCategoryFormDialogState();
}

class _ScheduleCategoryFormDialogState
    extends State<ScheduleCategoryFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initialName);
  late final _weeks = TextEditingController(text: widget.initialWeeks ?? '');
  late final _days = TextEditingController(
    text: widget.initialDays == null ? '' : '${widget.initialDays}',
  );
  late final _budget = TextEditingController(
    text: widget.initialBudget == null
        ? ''
        : widget.initialBudget!.toStringAsFixed(2),
  );

  @override
  void dispose() {
    _name.dispose();
    _weeks.dispose();
    _days.dispose();
    _budget.dispose();
    super.dispose();
  }

  double? _parseBudget(String text) {
    final cleaned = text.replaceAll(',', '').replaceAll('₱', '').trim();
    return cleaned.isEmpty ? null : double.tryParse(cleaned);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final weeks = _weeks.text.trim();
    final daysRaw = _days.text.trim();
    Navigator.of(context).pop(
      ScheduleCategoryFormResult(
        _name.text.trim(),
        _parseBudget(_budget.text),
        plannedWeeks: weeks.isEmpty ? null : weeks,
        plannedDays: daysRaw.isEmpty ? null : int.tryParse(daysRaw),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initialName != null;
    return AlertDialog(
      title: Text(editing ? 'Edit item of work' : 'Add item of work'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Item of work',
                  hintText: 'e.g. Mobilization & Site Clearing',
                ),
                textInputAction: TextInputAction.next,
                validator: ScheduleRules.validateCategoryName,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _weeks,
                      decoration: const InputDecoration(
                        labelText: 'Weeks',
                        hintText: 'e.g. Week 1 or 2-3',
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _days,
                      decoration: const InputDecoration(
                        labelText: 'Days',
                        hintText: 'e.g. 14',
                      ),
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      validator: (text) {
                        final raw = text?.trim() ?? '';
                        if (raw.isEmpty) return null;
                        final n = int.tryParse(raw);
                        if (n == null || n <= 0) return 'Enter days > 0.';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _budget,
                decoration: const InputDecoration(
                  labelText: 'Budget (optional)',
                  prefixText: '₱ ',
                  helperText: 'Used to weight this item in progress.',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onFieldSubmitted: (_) => _submit(),
                validator: (text) {
                  final raw = text?.trim() ?? '';
                  final budget = _parseBudget(raw);
                  if (raw.isNotEmpty && budget == null) {
                    return 'Enter an amount, e.g. 500000.';
                  }
                  return ScheduleRules.validateBudget(budget) ??
                      widget.validateBudgetTotal(budget);
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(editing ? 'Save' : 'Add')),
      ],
    );
  }
}

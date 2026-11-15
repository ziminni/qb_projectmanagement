import 'package:flutter/material.dart';

import '../../../data/services/schedule_rules.dart';

class ScheduleCategoryFormResult {
  const ScheduleCategoryFormResult(this.name, this.budget);

  final String name;
  final double? budget;
}

/// Add or edit a category. [validateBudgetTotal] checks the budget against
/// the contract amount together with the other categories.
class ScheduleCategoryFormDialog extends StatefulWidget {
  const ScheduleCategoryFormDialog({
    super.key,
    this.initialName,
    this.initialBudget,
    required this.validateBudgetTotal,
  });

  final String? initialName;
  final double? initialBudget;
  final String? Function(double? budget) validateBudgetTotal;

  static Future<ScheduleCategoryFormResult?> show(
    BuildContext context, {
    String? initialName,
    double? initialBudget,
    required String? Function(double? budget) validateBudgetTotal,
  }) => showDialog<ScheduleCategoryFormResult>(
    context: context,
    builder: (_) => ScheduleCategoryFormDialog(
      initialName: initialName,
      initialBudget: initialBudget,
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
  late final _budget = TextEditingController(
    text: widget.initialBudget == null
        ? ''
        : widget.initialBudget!.toStringAsFixed(2),
  );

  @override
  void dispose() {
    _name.dispose();
    _budget.dispose();
    super.dispose();
  }

  double? _parseBudget(String text) {
    final cleaned = text.replaceAll(',', '').replaceAll('₱', '').trim();
    return cleaned.isEmpty ? null : double.tryParse(cleaned);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      ScheduleCategoryFormResult(_name.text.trim(), _parseBudget(_budget.text)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initialName != null;
    return AlertDialog(
      title: Text(editing ? 'Edit category' : 'Add category'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. Foundation',
                ),
                textInputAction: TextInputAction.next,
                validator: ScheduleRules.validateCategoryName,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _budget,
                decoration: const InputDecoration(
                  labelText: 'Budget (optional)',
                  prefixText: '₱ ',
                  helperText: 'Used to weight this category in progress.',
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

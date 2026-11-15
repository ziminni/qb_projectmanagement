import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../data/services/schedule_rules.dart';
import '../../../shared/widgets/app_date_field.dart';

class ScheduleTodoFormResult {
  const ScheduleTodoFormResult(this.title, this.start, this.end);

  final String title;
  final DateTime start;
  final DateTime end;
}

/// Add or edit a to-do. Date pickers are limited to the project schedule and
/// [validateDates] applies the same rule the repository enforces.
class ScheduleTodoFormDialog extends StatefulWidget {
  const ScheduleTodoFormDialog({
    super.key,
    required this.categoryName,
    required this.firstDate,
    required this.lastDate,
    required this.validateDates,
    this.initialTitle,
    this.initialStart,
    this.initialEnd,
  });

  final String categoryName;
  final DateTime firstDate;
  final DateTime lastDate;
  final String? Function(DateTime? start, DateTime? end) validateDates;
  final String? initialTitle;
  final DateTime? initialStart;
  final DateTime? initialEnd;

  static Future<ScheduleTodoFormResult?> show(
    BuildContext context, {
    required String categoryName,
    required DateTime firstDate,
    required DateTime lastDate,
    required String? Function(DateTime? start, DateTime? end) validateDates,
    String? initialTitle,
    DateTime? initialStart,
    DateTime? initialEnd,
  }) => showDialog<ScheduleTodoFormResult>(
    context: context,
    builder: (_) => ScheduleTodoFormDialog(
      categoryName: categoryName,
      firstDate: firstDate,
      lastDate: lastDate,
      validateDates: validateDates,
      initialTitle: initialTitle,
      initialStart: initialStart,
      initialEnd: initialEnd,
    ),
  );

  @override
  State<ScheduleTodoFormDialog> createState() => _ScheduleTodoFormDialogState();
}

class _ScheduleTodoFormDialogState extends State<ScheduleTodoFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.initialTitle);
  late DateTime? _start = widget.initialStart;
  late DateTime? _end = widget.initialEnd;
  String? _dateError;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pick({required bool start}) async {
    final current = start ? _start : _end;
    final fallback = start ? widget.firstDate : (_start ?? widget.firstDate);
    final picked = await showDatePicker(
      context: context,
      firstDate: widget.firstDate,
      lastDate: widget.lastDate,
      initialDate: _clamp(current ?? fallback),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = picked;
        if (_end != null && _end!.isBefore(picked)) _end = picked;
      } else {
        _end = picked;
      }
      _dateError = null;
    });
  }

  DateTime _clamp(DateTime d) {
    if (d.isBefore(widget.firstDate)) return widget.firstDate;
    if (d.isAfter(widget.lastDate)) return widget.lastDate;
    return d;
  }

  void _submit() {
    final titleOk = _formKey.currentState!.validate();
    final dateError = widget.validateDates(_start, _end);
    setState(() => _dateError = dateError);
    if (!titleOk || dateError != null) return;
    Navigator.of(
      context,
    ).pop(ScheduleTodoFormResult(_title.text.trim(), _start!, _end!));
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initialTitle != null;
    return AlertDialog(
      title: Text(editing ? 'Edit to-do' : 'Add to-do'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.categoryName,
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _title,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'e.g. Rebar installation',
                ),
                validator: ScheduleRules.validateTodoTitle,
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: AppDateField(
                      label: 'Start',
                      value: _start,
                      hasError: _dateError != null,
                      onTap: () => _pick(start: true),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: AppDateField(
                      label: 'End',
                      value: _end,
                      hasError: _dateError != null,
                      onTap: () => _pick(start: false),
                    ),
                  ),
                ],
              ),
              if (_dateError != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _dateError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ],
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

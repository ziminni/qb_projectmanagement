import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../data/models/project.dart';
import '../../../data/services/labor_rules.dart';
import '../../../shared/widgets/app_date_field.dart';

class LaborPeriodInput {
  const LaborPeriodInput(this.projectId, this.start, this.end);

  final int projectId;
  final DateTime start;
  final DateTime end;
}

/// New payroll period: project plus a weekly or 15-day range.
class LaborPeriodDialog extends StatefulWidget {
  const LaborPeriodDialog({super.key, required this.projects});

  final List<Project> projects;

  static Future<LaborPeriodInput?> show(
    BuildContext context, {
    required List<Project> projects,
  }) => showDialog<LaborPeriodInput>(
    context: context,
    builder: (_) => LaborPeriodDialog(projects: projects),
  );

  @override
  State<LaborPeriodDialog> createState() => _LaborPeriodDialogState();
}

class _LaborPeriodDialogState extends State<LaborPeriodDialog> {
  int? _projectId;
  DateTime? _start;
  DateTime? _end;
  String? _error;

  Future<void> _pick(bool start) async {
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
      initialDate: (start ? _start : _end) ?? _start ?? DateTime.now(),
    );
    if (d == null) return;
    setState(() {
      if (start) {
        _start = d;
        _end ??= d.add(const Duration(days: 14));
      } else {
        _end = d;
      }
      _error = null;
    });
  }

  void _submit() {
    final error = _projectId == null
        ? 'Choose the project.'
        : LaborRules.validatePeriod(_start, _end);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(LaborPeriodInput(_projectId!, _start!, _end!));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New payroll period'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<int>(
              initialValue: _projectId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Project'),
              items: [
                for (final p in widget.projects)
                  DropdownMenuItem(
                    value: p.id,
                    child: Text('${p.code} · ${p.name}'),
                  ),
              ],
              onChanged: (v) => setState(() => _projectId = v),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: AppDateField(
                    label: 'Start',
                    value: _start,
                    hasError: _error != null,
                    onTap: () => _pick(true),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: AppDateField(
                    label: 'Cut-off',
                    value: _end,
                    hasError: _error != null,
                    onTap: () => _pick(false),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Create')),
      ],
    );
  }
}

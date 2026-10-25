import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../../../data/models/todo.dart';

/// To-dos accomplished today. Checked items are marked done when the report
/// is submitted and verified when the PM approves it.
class DailyReportsTodoPicker extends StatelessWidget {
  const DailyReportsTodoPicker({
    super.key,
    required this.todos,
    required this.selected,
    required this.onChanged,
  });

  final List<Todo> todos;
  final Set<int> selected;
  final void Function(int id, bool selected) onChanged;

  @override
  Widget build(BuildContext context) {
    if (todos.isEmpty) {
      return Text(
        'No open to-dos on this project.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return Column(
      children: [
        for (final t in todos)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: selected.contains(t.id),
            onChanged: t.isVerified ? null : (v) => onChanged(t.id, v ?? false),
            title: Text(t.title),
            subtitle: Text(Formatters.dateRange(t.startDate, t.endDate)),
          ),
      ],
    );
  }
}

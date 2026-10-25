import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/project.dart';
import '../viewmodels/user_form_viewmodel.dart';

/// Lists a user's project assignments and adds new ones. Only roles the
/// user holds can be assigned.
class UserManagementAssignmentEditor extends StatefulWidget {
  const UserManagementAssignmentEditor({
    super.key,
    required this.assignments,
    required this.roles,
    required this.projectById,
    required this.projectsFor,
    required this.onAdd,
    required this.onRemove,
  });

  final List<AssignmentDraft> assignments;
  final List<AppRole> roles;
  final Project? Function(int id) projectById;
  final List<Project> Function(AppRole role) projectsFor;
  final void Function(int projectId, AppRole role) onAdd;
  final ValueChanged<AssignmentDraft> onRemove;

  @override
  State<UserManagementAssignmentEditor> createState() =>
      _UserManagementAssignmentEditorState();
}

class _UserManagementAssignmentEditorState
    extends State<UserManagementAssignmentEditor> {
  AppRole? _role;
  int? _projectId;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    if (widget.roles.isEmpty) {
      return Text(
        'Project assignments apply to PMs, site engineers and clients. '
        'Owners, purchasing and accountants see every project.',
        style: textTheme.bodySmall,
      );
    }
    final role = widget.roles.contains(_role) ? _role! : widget.roles.first;
    final options = widget.projectsFor(role);
    final projectId = options.any((p) => p.id == _projectId)
        ? _projectId
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.assignments.isEmpty)
          Text('Not assigned to any project.', style: textTheme.bodySmall),
        for (final a in widget.assignments)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(widget.projectById(a.projectId)?.name ?? 'Project'),
            subtitle: Text(a.role.label),
            trailing: IconButton(
              tooltip: 'Remove assignment',
              icon: const Icon(Icons.close),
              onPressed: () => widget.onRemove(a),
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<AppRole>(
                key: ValueKey('role-$role'),
                initialValue: role,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'As'),
                items: [
                  for (final r in widget.roles)
                    DropdownMenuItem(value: r, child: Text(r.label)),
                ],
                onChanged: (r) => setState(() => _role = r),
              ),
            ),
            SizedBox(
              width: 280,
              child: DropdownButtonFormField<int>(
                key: ValueKey('project-$role-${options.length}'),
                initialValue: projectId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Project'),
                items: [
                  for (final p in options)
                    DropdownMenuItem(value: p.id, child: Text(p.name)),
                ],
                onChanged: (id) => setState(() => _projectId = id),
              ),
            ),
            OutlinedButton.icon(
              onPressed: projectId == null
                  ? null
                  : () {
                      widget.onAdd(projectId, role);
                      setState(() => _projectId = null);
                    },
              icon: const Icon(Icons.add),
              label: const Text('Assign'),
            ),
          ],
        ),
      ],
    );
  }
}

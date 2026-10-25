import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/user.dart';
import '../../../data/services/project_rules.dart';

class ProjectsAddMemberResult {
  const ProjectsAddMemberResult(this.userId, this.role);

  final int userId;
  final AppRole role;
}

/// Adds a PM, site engineer or client login to the project team.
class ProjectsAddMemberDialog extends StatefulWidget {
  const ProjectsAddMemberDialog({super.key, required this.candidatesFor});

  final Future<List<User>> Function(AppRole role) candidatesFor;

  static Future<ProjectsAddMemberResult?> show(
    BuildContext context, {
    required Future<List<User>> Function(AppRole role) candidatesFor,
  }) => showDialog<ProjectsAddMemberResult>(
    context: context,
    builder: (_) => ProjectsAddMemberDialog(candidatesFor: candidatesFor),
  );

  @override
  State<ProjectsAddMemberDialog> createState() =>
      _ProjectsAddMemberDialogState();
}

class _ProjectsAddMemberDialogState extends State<ProjectsAddMemberDialog> {
  AppRole _role = AppRole.siteEngineer;
  int? _userId;
  late Future<List<User>> _candidates = widget.candidatesFor(_role);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add to team'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<AppRole>(
              initialValue: _role,
              decoration: const InputDecoration(labelText: 'Role'),
              items: [
                for (final r in ProjectRules.assignableRoles)
                  DropdownMenuItem(value: r, child: Text(r.label)),
              ],
              onChanged: (r) => setState(() {
                _role = r!;
                _userId = null;
                _candidates = widget.candidatesFor(_role);
              }),
            ),
            const SizedBox(height: AppSpacing.md),
            FutureBuilder(
              future: _candidates,
              builder: (context, snapshot) {
                final users = snapshot.data ?? const <User>[];
                if (snapshot.hasData && users.isEmpty) {
                  return const Text('Nobody else holds this role.');
                }
                return DropdownButtonFormField<int>(
                  key: ValueKey(_role),
                  initialValue: _userId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Person'),
                  items: [
                    for (final u in users)
                      DropdownMenuItem(value: u.id, child: Text(u.fullName)),
                  ],
                  onChanged: (id) => setState(() => _userId = id),
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _userId == null
              ? null
              : () => Navigator.of(
                  context,
                ).pop(ProjectsAddMemberResult(_userId!, _role)),
          child: const Text('Add'),
        ),
      ],
    );
  }
}

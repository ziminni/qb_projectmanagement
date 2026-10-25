import 'package:flutter/material.dart';

import '../../../shared/widgets/app_section_card.dart';
import '../viewmodels/project_overview_viewmodel.dart';

class ProjectsTeamCard extends StatelessWidget {
  const ProjectsTeamCard({
    super.key,
    required this.team,
    this.onAdd,
    this.onRemove,
  });

  final List<TeamMember> team;
  final VoidCallback? onAdd;
  final ValueChanged<TeamMember>? onRemove;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      title: 'Team',
      padding: EdgeInsets.zero,
      trailing: onAdd == null
          ? null
          : TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Add'),
            ),
      child: Column(
        children: [
          if (team.isEmpty)
            const ListTile(title: Text('No one is assigned yet.')),
          for (final m in team)
            ListTile(
              leading: CircleAvatar(
                child: Text(m.user?.fullName.characters.first ?? '?'),
              ),
              title: Text(m.user?.fullName ?? 'Unknown user'),
              subtitle: Text(m.assignment.roleOnProject.label),
              trailing: onRemove == null
                  ? null
                  : IconButton(
                      tooltip: 'Remove from team',
                      icon: const Icon(Icons.person_remove_outlined),
                      onPressed: () => onRemove!(m),
                    ),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../data/models/project.dart';

/// Picks the next project status from the allowed transitions.
class ProjectsStatusDialog extends StatelessWidget {
  const ProjectsStatusDialog({
    super.key,
    required this.current,
    required this.options,
  });

  final ProjectStatus current;
  final List<ProjectStatus> options;

  static Future<ProjectStatus?> show(
    BuildContext context, {
    required ProjectStatus current,
    required List<ProjectStatus> options,
  }) => showDialog<ProjectStatus>(
    context: context,
    builder: (_) => ProjectsStatusDialog(current: current, options: options),
  );

  String _hint(ProjectStatus s) => switch (s) {
    ProjectStatus.bidding => 'Owner approves the bid for submission.',
    ProjectStatus.awarded => 'The BOQ locks in as the budget.',
    ProjectStatus.ongoing => 'Site reports, requests and billings open up.',
    ProjectStatus.onHold => 'Pause work; it can return to Ongoing.',
    ProjectStatus.completed => 'Work is done; retention can be released.',
    ProjectStatus.closed => 'Closeout finished. This cannot be undone.',
    ProjectStatus.lostBid => 'The bid was not awarded.',
    ProjectStatus.draft => '',
  };

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: Text('Move from ${current.label} to…'),
      children: [
        for (final s in options)
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(s),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.label),
              subtitle: Text(_hint(s)),
            ),
          ),
      ],
    );
  }
}

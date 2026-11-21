import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../data/models/client.dart';
import '../../../data/models/user.dart';
import '../../../shared/widgets/app_date_field.dart';

/// Wizard step 1: what the project is, who it is for, who runs the site and
/// when it happens.
class ProjectsDetailsStep extends StatelessWidget {
  const ProjectsDetailsStep({
    super.key,
    required this.code,
    required this.name,
    required this.isNew,
    required this.clients,
    required this.clientId,
    required this.onClient,
    required this.validateClient,
    required this.siteEngineers,
    required this.siteEngineerId,
    required this.onSiteEngineer,
    required this.start,
    required this.end,
    required this.dateError,
    required this.onPickStart,
    required this.onPickEnd,
  });

  final TextEditingController code;
  final TextEditingController name;
  final bool isNew;
  final List<Client> clients;
  final int? clientId;
  final ValueChanged<int?> onClient;
  final String? Function(int?) validateClient;
  final List<User> siteEngineers;
  final int? siteEngineerId;
  final ValueChanged<int?> onSiteEngineer;
  final DateTime? start;
  final DateTime? end;
  final String? dateError;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;

  String? _required(String? v, String label) =>
      (v == null || v.trim().isEmpty) ? 'Enter the $label.' : null;

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: AppSpacing.lg, width: AppSpacing.lg);
    Widget pair(Widget a, Widget b) => LayoutBuilder(
      builder: (context, c) => c.maxWidth < 520
          ? Column(children: [a, gap, b])
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: a),
                gap,
                Expanded(child: b),
              ],
            ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        pair(
          TextFormField(
            controller: code,
            decoration: const InputDecoration(
              labelText: 'Code',
              hintText: 'QB-2026-040',
              prefixIcon: Icon(Icons.tag_rounded),
            ),
            textCapitalization: TextCapitalization.characters,
            validator: (v) => _required(v, 'project code'),
          ),
          TextFormField(
            controller: name,
            decoration: const InputDecoration(
              labelText: 'Project name',
              hintText: 'Two-storey residence',
              prefixIcon: Icon(Icons.apartment_rounded),
            ),
            validator: (v) => _required(v, 'project name'),
          ),
        ),
        gap,
        pair(
          DropdownButtonFormField<int>(
            initialValue: clientId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Client',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
            items: [
              for (final c in clients)
                DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            validator: validateClient,
            onChanged: isNew ? onClient : null,
          ),
          isNew
              ? DropdownButtonFormField<int>(
                  initialValue: siteEngineerId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Foreman',
                    prefixIcon: Icon(Icons.engineering_outlined),
                  ),
                  items: [
                    for (final u in siteEngineers)
                      DropdownMenuItem(value: u.id, child: Text(u.fullName)),
                  ],
                  validator: (v) =>
                      v == null ? 'Choose the site engineer.' : null,
                  onChanged: onSiteEngineer,
                )
              : const SizedBox.shrink(),
        ),
        gap,
        pair(
          AppDateField(
            label: 'Start date',
            value: start,
            hasError: dateError != null,
            onTap: onPickStart,
          ),
          AppDateField(
            label: 'Target end date',
            value: end,
            hasError: dateError != null,
            onTap: onPickEnd,
          ),
        ),
        if (dateError != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              dateError!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }
}

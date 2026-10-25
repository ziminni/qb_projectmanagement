import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../data/models/app_role.dart';

/// Multi-select role chips; a user can hold several roles.
class UserManagementRoleSelector extends StatelessWidget {
  const UserManagementRoleSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final Set<AppRole> selected;
  final void Function(AppRole role, bool selected) onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final role in AppRole.values)
          FilterChip(
            label: Text(role.label),
            selected: selected.contains(role),
            onSelected: (v) => onChanged(role, v),
          ),
      ],
    );
  }
}

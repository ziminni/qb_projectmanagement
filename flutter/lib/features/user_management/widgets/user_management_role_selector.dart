import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/layout/role_navigation.dart';
import '../../../data/models/app_role.dart';
import '../../../shared/widgets/app_status_chip.dart';
import 'user_management_roles_dialog.dart';

/// Multi-select role cards with each role's permissions and accessible areas;
/// a user can hold several roles.
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
    final textTheme = Theme.of(context).textTheme;
    final chosen = [
      for (final role in AppRole.values)
        if (selected.contains(role)) role,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
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
        ),
        const SizedBox(height: AppSpacing.md),
        if (chosen.isEmpty)
          _AllRolesHint(textTheme: textTheme)
        else
          for (var i = 0; i < chosen.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            _SelectedRolePermissions(role: chosen[i], textTheme: textTheme),
          ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => showRolesPermissionsDialog(context),
            icon: const Icon(Icons.info_outline, size: 16),
            label: const Text('Compare all role permissions'),
          ),
        ),
      ],
    );
  }
}

class _AllRolesHint extends StatelessWidget {
  const _AllRolesHint({required this.textTheme});

  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.mdAll,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < AppRole.values.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.xs),
            RichText(
              text: TextSpan(
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
                children: [
                  TextSpan(
                    text: '${AppRole.values[i].label}: ',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  TextSpan(
                    text: [
                      for (final d in RoleNavigation.forRole(AppRole.values[i]))
                        d.label,
                    ].join(', '),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SelectedRolePermissions extends StatelessWidget {
  const _SelectedRolePermissions({
    required this.role,
    required this.textTheme,
  });

  final AppRole role;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final destinations = RoleNavigation.forRole(role);
    final accessSummary = [for (final d in destinations) d.label].join(' • ');
    final description = RolesPermissionsDialog.descriptions[role] ?? '';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: AppRadii.mdAll,
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                role.label,
                style: textTheme.titleSmall,
              ),
              role.seesFinance
                  ? AppStatusChip(
                      label: role.managesFinance
                          ? 'Sees company finances'
                          : 'Sees company finances (read-only)',
                      icon: Icons.visibility_outlined,
                      foreground: AppColors.warning,
                      background: AppColors.warningContainer,
                    )
                  : const AppStatusChip(
                      label: 'No company finances',
                      icon: Icons.visibility_off_outlined,
                      foreground: AppColors.success,
                      background: AppColors.successContainer,
                    ),
            ],
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              description,
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (accessSummary.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Access: $accessSummary',
              style: textTheme.labelSmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

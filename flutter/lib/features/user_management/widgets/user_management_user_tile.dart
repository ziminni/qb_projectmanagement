import 'package:flutter/material.dart';

import '../../../shared/widgets/app_avatar.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/user.dart';
import '../../../shared/widgets/app_status_chip.dart';

class UserManagementUserTile extends StatelessWidget {
  const UserManagementUserTile({
    super.key,
    required this.user,
    required this.roles,
    required this.onTap,
    this.showPermissions = false,
  });

  final User user;
  final List<AppRole> roles;
  final VoidCallback onTap;
  final bool showPermissions;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: AppAvatar(name: user.fullName, size: 40),
      title: Text(user.fullName),
      subtitle: Text('${user.email}\n${roles.map((r) => r.label).join(', ')}'),
      isThreeLine: true,
      trailing: user.isActive
          ? showPermissions
                ? _PermissionDisplay(roles: roles)
                : const Icon(Icons.chevron_right)
          : const AppStatusChip(
              label: 'Inactive',
              foreground: AppColors.textSecondary,
              background: AppColors.surfaceMuted,
            ),
    );
  }
}

class _PermissionDisplay extends StatefulWidget {
  const _PermissionDisplay({required this.roles});

  final List<AppRole> roles;

  @override
  State<_PermissionDisplay> createState() => _PermissionDisplayState();
}

class _PermissionDisplayState extends State<_PermissionDisplay> {
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final role in widget.roles)
          _PermissionDisplayChip(
            role: role,
            isSelected: widget.roles.contains(role),
          ),
      ],
    );
  }
}

class _PermissionDisplayChip extends StatelessWidget {
  const _PermissionDisplayChip({required this.role, required this.isSelected});

  final AppRole role;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final Color color = isSelected
        ? AppColors.brandGold
        : AppColors.surfaceMuted;
    return Chip(
      label: Text(role.label),
      backgroundColor: color,
      labelStyle: TextStyle(
        color: isSelected ? AppColors.brandBlack : AppColors.textSecondary,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

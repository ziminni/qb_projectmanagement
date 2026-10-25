import 'package:flutter/material.dart';

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
  });

  final User user;
  final List<AppRole> roles;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(child: Text(user.fullName.characters.first)),
      title: Text(user.fullName),
      subtitle: Text('${user.email}\n${roles.map((r) => r.label).join(', ')}'),
      isThreeLine: true,
      trailing: user.isActive
          ? const Icon(Icons.chevron_right)
          : const AppStatusChip(
              label: 'Inactive',
              foreground: AppColors.textSecondary,
              background: AppColors.surfaceMuted,
            ),
    );
  }
}

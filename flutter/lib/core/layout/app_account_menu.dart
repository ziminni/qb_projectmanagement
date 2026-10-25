import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/app_role.dart';
import '../../data/services/session_service.dart';
import '../../routes/routes.dart';
import 'role_navigation.dart';

/// Account menu in the shell's app bar: role switching for users with
/// several roles, profile, and signing out.
class AppAccountMenu extends StatelessWidget {
  const AppAccountMenu({super.key, required this.session});

  final SessionService session;

  @override
  Widget build(BuildContext context) {
    final user = session.user!;
    return PopupMenuButton<Object>(
      tooltip: 'Account',
      icon: CircleAvatar(
        radius: 16,
        child: Text(user.fullName.characters.first),
      ),
      onSelected: (value) {
        if (value is AppRole) {
          session.switchRole(value);
          context.go(RoleNavigation.homeFor(value));
        } else if (value == #profile) {
          context.go(AppRoutes.profile);
        } else if (value == #signOut) {
          session.signOut();
          context.go(AppRoutes.login);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<Object>(
          enabled: false,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(user.fullName),
            subtitle: Text(session.activeRole!.label),
          ),
        ),
        const PopupMenuDivider(),
        if (session.roles.length > 1) ...[
          for (final role in session.roles)
            CheckedPopupMenuItem<Object>(
              value: role,
              checked: role == session.activeRole,
              child: Text('Act as ${role.label}'),
            ),
          const PopupMenuDivider(),
        ],
        const PopupMenuItem<Object>(value: #profile, child: Text('My profile')),
        const PopupMenuItem<Object>(value: #signOut, child: Text('Sign out')),
      ],
    );
  }
}

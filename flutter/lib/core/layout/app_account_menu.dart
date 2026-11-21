import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/app_role.dart';
import '../../data/services/session_service.dart';
import '../../features/auth/widgets/profile_dialog.dart';
import '../../routes/routes.dart';
import '../../shared/widgets/app_avatar.dart';
import 'role_navigation.dart';

/// Account menu in the shell's app bar: role switching for users with
/// several roles, profile, and signing out.
class AppAccountMenu extends StatelessWidget {
  const AppAccountMenu({
    super.key,
    required this.session,
    this.compact = false,
  });

  final SessionService session;

  /// Avatar only, without the dropdown chevron (phones).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final user = session.user!;
    return PopupMenuButton<Object>(
      tooltip: 'Account',
      position: PopupMenuPosition.under,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppAvatar(name: user.fullName, size: 36),
            if (!compact) ...[
              const SizedBox(width: 2),
              const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
            ],
          ],
        ),
      ),
      onSelected: (value) {
        if (value is AppRole) {
          session.switchRole(value);
          context.go(RoleNavigation.homeFor(value));
        } else if (value == #profile) {
          showProfileDialog(context);
        } else if (value == #signOut) {
          session.signOut();
          context.go(AppRoutes.landing);
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

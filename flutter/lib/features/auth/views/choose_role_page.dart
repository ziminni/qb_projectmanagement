import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/layout/role_navigation.dart';
import '../../../data/services/session_service.dart';
import '../../../routes/routes.dart';
import '../widgets/auth_card.dart';

/// Shown after sign-in to users who hold several roles.
class ChooseRolePage extends StatelessWidget {
  const ChooseRolePage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionService>();
    return AuthCard(
      title: 'Continue as',
      subtitle:
          'You hold several roles. You can switch later from the account menu.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final role in session.roles) ...[
            OutlinedButton(
              onPressed: () {
                session.switchRole(role);
                context.go(RoleNavigation.homeFor(role));
              },
              child: Text(role.label),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          TextButton(
            onPressed: () {
              session.signOut();
              context.go(AppRoutes.login);
            },
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

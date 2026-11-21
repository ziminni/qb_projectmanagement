import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/layout/role_navigation.dart';
import '../../../core/theme/app_motion.dart';
import '../../../data/models/app_role.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../../../shared/widgets/app_status_chip.dart';

/// Opens the roles and permissions guide over the current page.
Future<void> showRolesPermissionsDialog(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close roles and permissions',
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: AppMotion.medium,
    pageBuilder: (_, _, _) => const RolesPermissionsDialog(),
    transitionBuilder: (context, animation, _, child) =>
        AppMotion.dialog(animation, child),
  );
}

/// What each role can open, read straight from the app's access rules so it
/// always matches what users actually see.
class RolesPermissionsDialog extends StatefulWidget {
  const RolesPermissionsDialog({super.key});

  static const descriptions = {
    AppRole.admin:
        'Manages user accounts, company details, master lists and system '
        'settings, and reviews the audit log. Sees company finances on '
        'the dashboard but cannot record or change money.',
    AppRole.owner:
        'Creates and runs projects, approves reports, to-dos, payroll and '
        'purchases, and manages billings and variation orders.',
    AppRole.siteEngineer:
        'Works on assigned sites: daily reports, attendance, to-dos, '
        'material counts and requests, and delivery checks.',
    AppRole.accountant:
        'Processes payroll, billings, supplier payables and retention, and '
        'prepares expense reports.',
    AppRole.client:
        'Sees their own projects in the client portal: progress, photos, '
        'billings and variation orders to approve.',
  };

  @override
  State<RolesPermissionsDialog> createState() => _RolesPermissionsDialogState();
}

class _RolesPermissionsDialogState extends State<RolesPermissionsDialog> {
  Map<AppRole, int>? _counts;

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    try {
      final repo = getIt<UserRepository>();
      final active = {
        for (final u in await repo.getUsers())
          if (u.isActive) u.id,
      };
      final counts = {for (final r in AppRole.values) r: 0};
      for (final ur in await repo.getAllUserRoles()) {
        if (active.contains(ur.userId)) counts[ur.role] = counts[ur.role]! + 1;
      }
      if (mounted) setState(() => _counts = counts);
    } catch (_) {
      // Counts are a nicety; the permissions still show without them.
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final phone = MediaQuery.sizeOf(context).width < 600;
    return Dialog(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: phone ? AppSpacing.lg : AppSpacing.xxl,
        vertical: AppSpacing.xl,
      ),
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.xlAll),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: AppColors.surface,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Roles and permissions',
                          style: textTheme.titleLarge,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'What each role can open. Give a user several roles '
                          'to combine access; they pick which one to work as '
                          'after signing in.',
                          style: textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  for (final (i, role) in AppRole.values.indexed) ...[
                    if (i > 0) const SizedBox(height: AppSpacing.md),
                    _RoleCard(role: role, users: _counts?[role]),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({required this.role, required this.users});
  final AppRole role;
  final int? users;

  @override
  Widget build(BuildContext context) {
    final main = RoleNavigation.forRole(role);
    final linked = RoleNavigation.linkedFor(role);
    final textTheme = Theme.of(context).textTheme;
    return AppSectionCard(
      title: role.label,
      icon: Icons.admin_panel_settings_outlined,
      trailing: users == null
          ? null
          : TextButton(
              onPressed: () {
                final router = GoRouter.of(context);
                Navigator.of(context).pop();
                router.go('${AppRoutes.adminUsers}?role=${role.apiValue}');
              },
              child: Text(users == 1 ? '1 active user' : '$users active users'),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            RolesPermissionsDialog.descriptions[role]!,
            style: textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
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
          const SizedBox(height: AppSpacing.lg),
          Text('Navigation', style: textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          _ScreenChips(destinations: main),
          if (linked.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Text('Also opens from links', style: textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            _ScreenChips(destinations: linked),
          ],
        ],
      ),
    );
  }
}

class _ScreenChips extends StatelessWidget {
  const _ScreenChips({required this.destinations});
  final List<RoleDestination> destinations;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final d in destinations)
          Chip(
            avatar: Icon(d.icon, size: 16),
            label: Text(d.label),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }
}

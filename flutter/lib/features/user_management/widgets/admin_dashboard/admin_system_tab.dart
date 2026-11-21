import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../routes/routes.dart';
import '../../../../shared/widgets/app_section_card.dart';
import '../../../dashboard/widgets/dashboard_stat_tile.dart';
import '../../viewmodels/admin_dashboard/admin_system_viewmodel.dart';
import '../user_management_audit_tile.dart';
import '../user_management_roles_dialog.dart';
import 'admin_dashboard_kit.dart';

/// Accounts, access, open issues and the latest changes.
class AdminSystemTab extends StatelessWidget {
  const AdminSystemTab({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminTabHost<AdminSystemViewModel>(
      create: () => AdminSystemViewModel(
        users: getIt(),
        clients: getIt(),
        projects: getIt(),
        auditLog: getIt(),
        company: getIt(),
      ),
      build: (context, vm) => [
        AdminStatGrid(
          tiles: [
            DashboardStatTile(
              label: 'Active users',
              value: '${vm.activeUsers}',
              detail: vm.newUsersThisMonth > 0
                  ? '${vm.newUsersThisMonth} added in 30 days'
                  : 'of ${vm.totalUsers} accounts',
              icon: Icons.people_outline,
              progress: vm.totalUsers == 0
                  ? null
                  : vm.activeUsers / vm.totalUsers,
              onTap: () => context.go(AppRoutes.adminUsers),
            ),
            DashboardStatTile(
              label: 'Inactive users',
              value: '${vm.inactiveUsers}',
              detail: 'Cannot sign in',
              icon: Icons.person_off_outlined,
              color: vm.inactiveUsers > 0
                  ? AppColors.warning
                  : AppColors.textSecondary,
              onTap: () => context.go(AppRoutes.adminUsers),
            ),
            DashboardStatTile(
              label: 'Clients without login',
              value: '${vm.clientsWithoutLogin.length}',
              detail: vm.clientsWithoutLogin.isEmpty
                  ? 'Every client can sign in'
                  : 'Need a portal account',
              icon: Icons.badge_outlined,
              color: vm.clientsWithoutLogin.isNotEmpty
                  ? AppColors.warning
                  : AppColors.success,
              onTap: () => context.go(AppRoutes.adminUsers),
            ),
            DashboardStatTile(
              label: 'Changes this week',
              value: '${vm.activityThisWeek}',
              detail: 'Audit log entries',
              icon: Icons.history,
              onTap: () => context.go(AppRoutes.adminAuditLog),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AdminTwoColumn(
          main: [
            AppSectionCard(
              title: 'Needs attention',
              icon: Icons.flag_outlined,
              subtitle: vm.attention.isEmpty
                  ? null
                  : '${vm.attention.length} open '
                        '${vm.attention.length == 1 ? 'item' : 'items'}',
              padding: EdgeInsets.zero,
              child: AdminRowList(
                emptyTitle: 'All clear',
                emptySubtitle: 'No account or access issues right now.',
                rows: [
                  for (final a in vm.attention)
                    AdminListRow(
                      icon: a.level == AttentionLevel.urgent
                          ? Icons.error_outline
                          : Icons.warning_amber_rounded,
                      iconColor: a.level == AttentionLevel.urgent
                          ? AppColors.error
                          : AppColors.warning,
                      title: a.title,
                      subtitle: a.detail,
                      onTap: () {
                        if (a.userId != null) {
                          context.go(AppRoutes.adminUser(a.userId!));
                        } else if (a.path != null) {
                          context.go(a.path!);
                        }
                      },
                    ),
                ],
              ),
            ),
            AppSectionCard(
              title: 'Latest changes',
              icon: Icons.history,
              padding: EdgeInsets.zero,
              trailing: TextButton(
                onPressed: () => context.go(AppRoutes.adminAuditLog),
                child: const Text('Audit log'),
              ),
              child: vm.recentActivity.isEmpty
                  ? const ListTile(title: Text('Nothing recorded yet.'))
                  : Column(
                      children: [
                        for (final l in vm.recentActivity)
                          UserManagementAuditTile(
                            log: l,
                            userName: vm.userName(l.userId),
                            showDetails: false,
                          ),
                      ],
                    ),
            ),
          ],
          side: [
            AppSectionCard(
              title: 'Active users by role',
              icon: Icons.admin_panel_settings_outlined,
              trailing: TextButton(
                onPressed: () => showRolesPermissionsDialog(context),
                child: const Text('Permissions'),
              ),
              child: AdminBreakdownBars(
                items: [
                  for (final e in vm.usersByRole.entries)
                    AdminBreakdownItem(
                      e.key.label,
                      e.value.toDouble(),
                      onTap: () => context.go(
                        AppRoutes.adminUsersWithRole(e.key.apiValue),
                      ),
                    ),
                ],
              ),
            ),
            const _ShortcutsCard(),
          ],
        ),
      ],
    );
  }
}

class _ShortcutsCard extends StatelessWidget {
  const _ShortcutsCard();

  @override
  Widget build(BuildContext context) {
    const links = [
      (Icons.person_add_alt, 'Add a user', AppRoutes.adminUserNew),
      (Icons.business_outlined, 'Company profile', AppRoutes.adminCompany),
      (Icons.verified_outlined, 'Licenses', AppRoutes.adminLicenses),
      (Icons.security_outlined, 'Security & sessions', AppRoutes.adminSecurity),
      (Icons.backup_outlined, 'Database backups', AppRoutes.adminBackups),
      (Icons.settings_outlined, 'Settings', AppRoutes.adminSettings),
    ];
    return AppSectionCard(
      title: 'Shortcuts',
      icon: Icons.bolt_outlined,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (final (icon, label, path) in links)
            ListTile(
              leading: Icon(icon),
              title: Text(label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go(path),
            ),
        ],
      ),
    );
  }
}

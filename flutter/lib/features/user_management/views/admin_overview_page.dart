import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/models/app_role.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_page_header.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../../dashboard/widgets/dashboard_stat_tile.dart';
import '../viewmodels/admin_overview_viewmodel.dart';
import '../widgets/user_management_audit_tile.dart';
import '../widgets/user_management_roles_dialog.dart';

/// The system admin's landing screen.
class AdminOverviewPage extends StatelessWidget {
  const AdminOverviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AdminOverviewViewModel(
        users: getIt(),
        clients: getIt(),
        projects: getIt(),
        auditLog: getIt(),
        company: getIt(),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<AdminOverviewViewModel>();
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (vm.error != null) return AppEmptyState(message: vm.error!);
        final wide =
            MediaQuery.sizeOf(context).width >= AppSpacing.wideBreakpoint;

        final main = [
          _AttentionCard(items: vm.attention),
          const SizedBox(height: AppSpacing.lg),
          _ActivityCard(vm: vm),
        ];
        final side = [
          _RolesCard(counts: vm.usersByRole),
          const SizedBox(height: AppSpacing.lg),
          const _ShortcutsCard(),
        ];

        return ListView(
          padding: pagePadding(context),
          children: [
            AppPageHeader(
              title: 'Dashboard',
              subtitle:
                  'Accounts, access and recent activity across the '
                  'system.',
              actions: [
                OutlinedButton.icon(
                  onPressed: () => context.go(AppRoutes.adminAuditLog),
                  icon: const Icon(Icons.history),
                  label: const Text('Audit log'),
                ),
                FilledButton.icon(
                  onPressed: () => context.go(AppRoutes.adminUserNew),
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('Add user'),
                ),
              ],
            ),
            _StatGrid(
              tiles: [
                DashboardStatTile(
                  label: 'Active users',
                  value: '${vm.activeUsers}',
                  detail: 'of ${vm.totalUsers} accounts',
                  icon: Icons.people_outline,
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
                  detail: 'Need a portal account',
                  icon: Icons.badge_outlined,
                  color: vm.clientsWithoutLogin.isNotEmpty
                      ? AppColors.warning
                      : AppColors.success,
                  onTap: () => context.go(AppRoutes.adminMasterLists),
                ),
                DashboardStatTile(
                  label: 'Activity this week',
                  value: '${vm.activityThisWeek}',
                  detail: 'Audit log entries',
                  icon: Icons.history,
                  onTap: () => context.go(AppRoutes.adminAuditLog),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: Column(children: main)),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(flex: 2, child: Column(children: side)),
                ],
              )
            else ...[
              ...main,
              const SizedBox(height: AppSpacing.lg),
              ...side,
            ],
          ],
        );
      },
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.tiles});
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900 ? 4 : 2;
        const gap = AppSpacing.md;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final t in tiles) SizedBox(width: width, child: t)],
        );
      },
    );
  }
}

class _AttentionCard extends StatelessWidget {
  const _AttentionCard({required this.items});
  final List<AdminAttention> items;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      title: 'Needs attention',
      icon: Icons.flag_outlined,
      subtitle: items.isEmpty ? null : '${items.length} open items',
      padding: EdgeInsets.zero,
      child: items.isEmpty
          ? const ListTile(
              leading: Icon(
                Icons.check_circle_outline,
                color: AppColors.success,
              ),
              title: Text('All clear'),
              subtitle: Text('No account or access issues right now.'),
            )
          : Column(
              children: [
                for (final (i, a) in items.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    leading: const Icon(
                      Icons.error_outline,
                      color: AppColors.warning,
                    ),
                    title: Text(a.title),
                    subtitle: Text(a.detail),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      if (a.userId != null) {
                        context.go(AppRoutes.adminUser(a.userId!));
                      } else if (a.path != null) {
                        context.go(a.path!);
                      }
                    },
                  ),
                ],
              ],
            ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.vm});
  final AdminOverviewViewModel vm;

  @override
  Widget build(BuildContext context) {
    final items = vm.recentActivity;
    return AppSectionCard(
      title: 'Recent activity',
      icon: Icons.history,
      padding: EdgeInsets.zero,
      trailing: TextButton(
        onPressed: () => context.go(AppRoutes.adminAuditLog),
        child: const Text('View all'),
      ),
      child: items.isEmpty
          ? const ListTile(title: Text('Nothing recorded yet.'))
          : Column(
              children: [
                for (final l in items)
                  UserManagementAuditTile(
                    log: l,
                    userName: vm.userName(l.userId),
                    showDetails: false,
                  ),
              ],
            ),
    );
  }
}

class _RolesCard extends StatelessWidget {
  const _RolesCard({required this.counts});
  final Map<AppRole, int> counts;

  @override
  Widget build(BuildContext context) {
    final max = counts.values.fold(1, (m, v) => v > m ? v : m);
    final textTheme = Theme.of(context).textTheme;
    return AppSectionCard(
      title: 'Active users by role',
      icon: Icons.admin_panel_settings_outlined,
      trailing: TextButton(
        onPressed: () => showRolesPermissionsDialog(context),
        child: const Text('Permissions'),
      ),
      child: Column(
        children: [
          for (final e in counts.entries)
            InkWell(
              onTap: () =>
                  context.go('${AppRoutes.adminUsers}?role=${e.key.apiValue}'),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(e.key.label, style: textTheme.bodyMedium),
                        ),
                        Text('${e.value}', style: textTheme.titleSmall),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: e.value / max,
                        minHeight: 6,
                        backgroundColor: AppColors.surfaceMuted,
                        valueColor: const AlwaysStoppedAnimation(
                          AppColors.brandGold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ShortcutsCard extends StatelessWidget {
  const _ShortcutsCard();

  @override
  Widget build(BuildContext context) {
    const links = [
      (Icons.business_outlined, 'Company profile', AppRoutes.adminCompany),
      (Icons.list_alt_outlined, 'Master lists', AppRoutes.adminMasterLists),
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

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../routes/routes.dart';
import '../../../../shared/widgets/app_section_card.dart';
import '../../../dashboard/widgets/dashboard_stat_tile.dart';
import '../../viewmodels/admin_dashboard/admin_activity_viewmodel.dart';
import '../../viewmodels/audit_log_viewmodel.dart';
import '../user_management_audit_tile.dart';
import 'admin_dashboard_kit.dart';

/// Audit trends: how much changed, where, and by whom.
class AdminActivityTab extends StatelessWidget {
  const AdminActivityTab({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminTabHost<AdminActivityViewModel>(
      create: () => AdminActivityViewModel(auditLog: getIt(), users: getIt()),
      build: (context, vm) => [
        AdminStatGrid(
          tiles: [
            DashboardStatTile(
              label: 'Today',
              value: '${vm.todayCount}',
              detail: 'Changes recorded',
              icon: Icons.today_outlined,
            ),
            DashboardStatTile(
              label: 'Last 7 days',
              value: '${vm.weekCount}',
              detail: '${vm.activeUsersThisWeek} people made changes',
              icon: Icons.date_range_outlined,
            ),
            DashboardStatTile(
              label: 'Last ${AdminActivityViewModel.breakdownDays} days',
              value: '${vm.monthCount}',
              detail: 'Changes recorded',
              icon: Icons.calendar_month_outlined,
            ),
            DashboardStatTile(
              label: 'Busiest area',
              value: vm.byEntity.isEmpty
                  ? '—'
                  : AuditLogViewModel.entityLabel(vm.byEntity.first.key),
              detail: vm.byEntity.isEmpty
                  ? 'No changes yet'
                  : '${vm.byEntity.first.value} changes in 30 days',
              icon: Icons.local_fire_department_outlined,
              onTap: () => context.go(AppRoutes.adminAuditLog),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        AppSectionCard(
          title: 'Changes per day',
          icon: Icons.bar_chart_outlined,
          subtitle: 'Last ${AdminActivityViewModel.chartDays} days',
          child: _DailyBars(days: vm.daily),
        ),
        const SizedBox(height: AppSpacing.lg),
        AdminTwoColumn(
          main: [
            AppSectionCard(
              title: 'Latest changes',
              icon: Icons.history,
              padding: EdgeInsets.zero,
              trailing: TextButton(
                onPressed: () => context.go(AppRoutes.adminAuditLog),
                child: const Text('Full audit log'),
              ),
              child: vm.recent.isEmpty
                  ? const ListTile(title: Text('Nothing recorded yet.'))
                  : Column(
                      children: [
                        for (final l in vm.recent)
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
              title: 'By area',
              icon: Icons.category_outlined,
              subtitle: 'Last ${AdminActivityViewModel.breakdownDays} days',
              child: AdminBreakdownBars(
                emptyMessage: 'No changes in this period.',
                items: [
                  for (final e in vm.byEntity.take(8))
                    AdminBreakdownItem(
                      AuditLogViewModel.entityLabel(e.key),
                      e.value.toDouble(),
                    ),
                ],
              ),
            ),
            AppSectionCard(
              title: 'Most active people',
              icon: Icons.person_search_outlined,
              subtitle: 'Last ${AdminActivityViewModel.breakdownDays} days',
              child: AdminBreakdownBars(
                emptyMessage: 'No changes in this period.',
                items: [
                  for (final e in vm.byUser)
                    AdminBreakdownItem(
                      vm.userName(e.key),
                      e.value.toDouble(),
                      onTap: () => context.go(AppRoutes.adminUser(e.key)),
                    ),
                ],
              ),
            ),
            AppSectionCard(
              title: 'Top actions',
              icon: Icons.touch_app_outlined,
              child: AdminBreakdownBars(
                emptyMessage: 'No changes in this period.',
                items: [
                  for (final e in vm.byAction)
                    AdminBreakdownItem(
                      AuditLogViewModel.actionLabel(e.key),
                      e.value.toDouble(),
                      color: AppColors.brandGoldLight,
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A simple vertical bar per day, with the count on hover.
class _DailyBars extends StatelessWidget {
  const _DailyBars({required this.days});
  final List<({DateTime day, int count})> days;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final max = days.fold<int>(0, (m, d) => d.count > m ? d.count : m);
    const chartHeight = 140.0;
    return Column(
      children: [
        SizedBox(
          height: chartHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final d in days)
                Expanded(
                  child: Tooltip(
                    message:
                        '${Formatters.shortDate(d.day)}: ${d.count} '
                        '${d.count == 1 ? 'change' : 'changes'}',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (d.count > 0)
                            Text('${d.count}', style: textTheme.labelSmall),
                          const SizedBox(height: 2),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            height: max == 0
                                ? 2
                                : (d.count / max) * (chartHeight - 24) + 2,
                            decoration: BoxDecoration(
                              color: d.count == 0
                                  ? AppColors.surfaceMuted
                                  : AppColors.brandGold,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            for (final (i, d) in days.indexed)
              Expanded(
                child: Text(
                  i.isEven || days.length <= 7 ? '${d.day.day}' : '',
                  textAlign: TextAlign.center,
                  style: textTheme.labelSmall,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

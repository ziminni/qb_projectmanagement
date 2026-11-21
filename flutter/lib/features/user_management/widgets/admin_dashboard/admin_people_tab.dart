import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/widgets/app_progress_bar.dart';
import '../../../../shared/widgets/app_section_card.dart';
import '../../../dashboard/widgets/dashboard_stat_tile.dart';
import '../../viewmodels/admin_dashboard/admin_people_viewmodel.dart';
import 'admin_dashboard_kit.dart';

/// The workforce, daily reporting and attendance on ongoing sites.
class AdminPeopleTab extends StatelessWidget {
  const AdminPeopleTab({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminTabHost<AdminPeopleViewModel>(
      create: () => AdminPeopleViewModel(
        labor: getIt(),
        reports: getIt(),
        projects: getIt(),
        users: getIt(),
      ),
      build: (context, vm) {
        final compliance = vm.reportCompliance;
        final rate = vm.averageDailyRate;
        final review = vm.awaitingReview;
        return [
          AdminStatGrid(
            tiles: [
              DashboardStatTile(
                label: 'Active workers',
                value: '${vm.activeWorkers}',
                detail: rate == null
                    ? '${vm.inactiveWorkers} inactive'
                    : 'Avg. ${Formatters.peso(rate)} a day',
                icon: Icons.groups_outlined,
              ),
              DashboardStatTile(
                label: 'Man-days this week',
                value: vm.manDaysThisWeek.toStringAsFixed(
                  vm.manDaysThisWeek % 1 == 0 ? 0 : 1,
                ),
                detail: 'Across ${vm.sites.length} ongoing sites',
                icon: Icons.calendar_view_week_outlined,
              ),
              DashboardStatTile(
                label: 'Report compliance',
                value: Formatters.percent(compliance),
                detail: 'Work days with a daily report',
                progress: compliance,
                icon: Icons.fact_check_outlined,
                color: compliance >= 0.8
                    ? AppColors.success
                    : compliance >= 0.5
                    ? AppColors.warning
                    : AppColors.error,
              ),
              DashboardStatTile(
                label: 'Reports to review',
                value: '${review.length}',
                detail: vm.returnedReports > 0
                    ? '${vm.returnedReports} returned for fixes'
                    : '${vm.approvedThisWeek} approved this week',
                icon: Icons.rate_review_outlined,
                color: review.isNotEmpty ? AppColors.warning : null,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          AdminTwoColumn(
            main: [
              AppSectionCard(
                title: 'Sites this week',
                icon: Icons.location_city_outlined,
                subtitle:
                    'Last ${AdminPeopleViewModel.windowDays} days, lowest '
                    'reporting first.',
                padding: EdgeInsets.zero,
                child: vm.sites.isEmpty
                    ? const ListTile(title: Text('No ongoing sites.'))
                    : Column(
                        children: [
                          for (final (i, s) in vm.sites.indexed) ...[
                            if (i > 0) const Divider(height: 1),
                            _SiteRow(site: s),
                          ],
                        ],
                      ),
              ),
              AppSectionCard(
                title: 'Daily reports waiting for review',
                icon: Icons.rate_review_outlined,
                padding: EdgeInsets.zero,
                child: AdminRowList(
                  emptyTitle: 'Nothing waiting',
                  emptySubtitle: 'Every submitted report has been reviewed.',
                  rows: [
                    for (final r in review.take(8))
                      AdminListRow(
                        icon: Icons.edit_note_outlined,
                        iconColor: vm.today.difference(r.reportDate).inDays > 2
                            ? AppColors.warning
                            : null,
                        title: vm.projectLabel(r.projectId),
                        subtitle:
                            '${Formatters.date(r.reportDate)} · by '
                            '${vm.userName(r.submittedBy)}',
                      ),
                  ],
                ),
              ),
            ],
            side: [
              AppSectionCard(
                title: 'Workers by trade',
                icon: Icons.handyman_outlined,
                child: AdminBreakdownBars(
                  emptyMessage: 'No active workers.',
                  items: [
                    for (final e in vm.workersByTrade)
                      AdminBreakdownItem(e.key, e.value.toDouble()),
                  ],
                ),
              ),
            ],
          ),
        ];
      },
    );
  }
}

class _SiteRow extends StatelessWidget {
  const _SiteRow({required this.site});
  final AdminSiteActivity site;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final p = site.project;
    final color = site.reportRate >= 0.8
        ? AppColors.success
        : site.reportRate >= 0.5
        ? AppColors.warning
        : AppColors.error;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${p.code} · ${p.name}',
                  style: textTheme.titleSmall,
                ),
              ),
              AdminFigureText(
                '${site.reportDays}/${site.workDays} reports',
                color: color,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          AppProgressBar(value: site.reportRate, height: 6, color: color),
          const SizedBox(height: AppSpacing.xs),
          Text(
            site.attendanceError
                ? 'Attendance could not be loaded.'
                : '${site.workersSeen} workers · '
                      '${site.manDays.toStringAsFixed(site.manDays % 1 == 0 ? 0 : 1)} '
                      'man-days'
                      '${site.overtimeHours > 0 ? ' · ${site.overtimeHours.toStringAsFixed(1)} h overtime' : ''}',
            style: textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

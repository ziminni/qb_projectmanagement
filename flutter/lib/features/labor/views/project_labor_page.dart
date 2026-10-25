import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_padding.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_figure.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../viewmodels/project_labor_viewmodel.dart';
import '../widgets/labor_period_status_chip.dart';

/// Project "Labor" tab: workers, recent attendance and payroll.
class ProjectLaborPage extends StatelessWidget {
  const ProjectLaborPage({super.key, required this.projectId});

  final int projectId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      key: ValueKey(projectId),
      create: (_) =>
          ProjectLaborViewModel(projectId: projectId, labor: getIt())..load(),
      builder: (context, _) {
        final vm = context.watch<ProjectLaborViewModel>();
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        const gap = SizedBox(height: AppSpacing.lg);
        return ListView(
          padding: pagePadding(context),
          children: [
            AppSectionCard(
              title: 'Labor',
              child: Wrap(
                spacing: AppSpacing.xl,
                runSpacing: AppSpacing.md,
                children: [
                  AppFigure(
                    label: 'Workers on site',
                    value: '${vm.workers.length}',
                  ),
                  AppFigure(
                    label: 'Labor cost (processed payroll)',
                    value: Formatters.peso(vm.laborCost),
                  ),
                ],
              ),
            ),
            gap,
            AppSectionCard(
              title: 'Recent attendance',
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  if (vm.recentDays.isEmpty)
                    const ListTile(title: Text('No attendance recorded.')),
                  for (final d in vm.recentDays)
                    ListTile(
                      dense: true,
                      title: Text(Formatters.date(d.date)),
                      trailing: Text(
                        '${d.present} present · ${d.halfDay} half · '
                        '${d.absent} absent',
                      ),
                    ),
                ],
              ),
            ),
            gap,
            AppSectionCard(
              title: 'Payroll periods',
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  if (vm.periods.isEmpty)
                    const ListTile(title: Text('No payroll periods yet.')),
                  for (final p in vm.periods)
                    ListTile(
                      onTap: () => context.go(AppRoutes.payrollPeriod(p.id)),
                      title: Text(
                        Formatters.dateRange(p.periodStart, p.periodEnd),
                      ),
                      trailing: LaborPeriodStatusChip(status: p.status),
                    ),
                ],
              ),
            ),
            gap,
            AppSectionCard(
              title: 'Workers',
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final w in vm.workers)
                    ListTile(
                      dense: true,
                      title: Text(w.fullName),
                      subtitle: Text(w.trade),
                      trailing: Text('${Formatters.peso(w.dailyRate)}/day'),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_padding.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../viewmodels/payroll_periods_viewmodel.dart';
import '../widgets/labor_period_dialog.dart';
import '../widgets/labor_period_status_chip.dart';

/// Payroll periods (weekly or 15-day cut-offs).
class PayrollPeriodsPage extends StatelessWidget {
  const PayrollPeriodsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => PayrollPeriodsViewModel(
        session: getIt(),
        projects: getIt(),
        labor: getIt(),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<PayrollPeriodsViewModel>();
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: pagePadding(context),
          children: [
            if (vm.canCreate)
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: () async {
                    final input = await LaborPeriodDialog.show(
                      context,
                      projects: vm.projectsById.values.toList(),
                    );
                    if (input != null && context.mounted) {
                      await reportAction(
                        context,
                        vm.create(input.projectId, input.start, input.end),
                        success: 'Payroll period created.',
                      );
                    }
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('New payroll period'),
                ),
              ),
            const SizedBox(height: AppSpacing.lg),
            if (vm.items.isEmpty)
              const AppEmptyState(message: 'No payroll periods yet.')
            else
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final (i, p) in vm.items.indexed) ...[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        onTap: () => context.go(AppRoutes.payrollPeriod(p.id)),
                        title: Text(
                          Formatters.dateRange(p.periodStart, p.periodEnd),
                        ),
                        subtitle: Text(
                          vm.projectsById[p.projectId]?.code ?? 'Project',
                        ),
                        trailing: LaborPeriodStatusChip(status: p.status),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

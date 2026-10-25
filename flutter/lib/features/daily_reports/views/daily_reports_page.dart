import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/models/daily_report.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../viewmodels/daily_reports_viewmodel.dart';
import '../widgets/daily_reports_report_tile.dart';

/// Daily report history with status and date filters. Also the project
/// detail "Daily reports" tab when [projectId] is set.
class DailyReportsPage extends StatelessWidget {
  const DailyReportsPage({super.key, this.projectId});

  final int? projectId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => DailyReportsViewModel(
        projectId: projectId,
        session: getIt(),
        projects: getIt(),
        reports: getIt(),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<DailyReportsViewModel>();
        if (vm.error != null) return AppEmptyState(message: vm.error!);
        return ListView(
          padding: pagePadding(context),
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: vm.statusFilter == null,
                  onSelected: (_) => vm.setStatus(null),
                ),
                for (final s in DailyReportStatus.values)
                  ChoiceChip(
                    label: Text(s.label),
                    selected: vm.statusFilter == s,
                    onSelected: (_) => vm.setStatus(s),
                  ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final range = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2024),
                      lastDate: DateTime.now(),
                    );
                    if (range != null) vm.setRange(range.start, range.end);
                  },
                  icon: const Icon(Icons.date_range),
                  label: Text(
                    vm.from == null
                        ? 'Any date'
                        : Formatters.dateRange(vm.from!, vm.to!),
                  ),
                ),
                if (vm.from != null)
                  IconButton(
                    tooltip: 'Clear dates',
                    icon: const Icon(Icons.clear),
                    onPressed: () => vm.setRange(null, null),
                  ),
                if (vm.canCreate)
                  FilledButton.icon(
                    onPressed: () => context.go(
                      projectId == null
                          ? AppRoutes.dailyReportNew
                          : '${AppRoutes.dailyReportNew}?projectId=$projectId',
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('New report'),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            if (vm.isLoading)
              const Center(child: CircularProgressIndicator())
            else if (vm.items.isEmpty)
              const AppEmptyState(message: 'No daily reports match.')
            else
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final (i, r) in vm.items.indexed) ...[
                      if (i > 0) const Divider(height: 1),
                      DailyReportsReportTile(
                        report: r,
                        projectLabel: projectId == null
                            ? vm.projectFor(r)?.code
                            : null,
                        onTap: () => context.go(AppRoutes.dailyReport(r.id)),
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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_padding.dart';
import '../../../shared/widgets/app_status_chip.dart';
import '../viewmodels/workers_viewmodel.dart';
import '../widgets/labor_worker_dialog.dart';

class WorkersPage extends StatelessWidget {
  const WorkersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) =>
          WorkersViewModel(labor: getIt(), masterData: getIt())..load(),
      builder: (context, _) {
        final vm = context.watch<WorkersViewModel>();
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: pagePadding(context),
          children: [
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                SizedBox(
                  width: 300,
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search name or trade',
                    ),
                    onChanged: vm.setQuery,
                  ),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    final w = await LaborWorkerDialog.show(
                      context,
                      trades: vm.trades,
                    );
                    if (w != null && context.mounted) {
                      await reportAction(context, vm.save(w));
                    }
                  },
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('Add worker'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final (i, w) in vm.items.indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    ListTile(
                      title: Text(w.fullName),
                      subtitle: Text(
                        '${w.trade} · ${Formatters.peso(w.dailyRate)}/day'
                        '${w.sssNo == null ? ' · no SSS no.' : ''}',
                      ),
                      trailing: w.isActive
                          ? const Icon(Icons.edit_outlined)
                          : const AppStatusChip(
                              label: 'Inactive',
                              foreground: AppColors.textSecondary,
                              background: AppColors.surfaceMuted,
                            ),
                      onTap: () async {
                        final edited = await LaborWorkerDialog.show(
                          context,
                          initial: w,
                          trades: vm.trades,
                        );
                        if (edited != null && context.mounted) {
                          await reportAction(context, vm.save(edited));
                        }
                      },
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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/page_padding.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../viewmodels/procurement_lookups.dart';
import '../viewmodels/site_inventory_viewmodel.dart';
import '../widgets/procurement_inventory_table.dart';

/// Site inventory per project (purchasing).
class SiteInventoryPage extends StatelessWidget {
  const SiteInventoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SiteInventoryViewModel(
        session: getIt(),
        procurement: getIt(),
        lookups: ProcurementLookups.fromServices(),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<SiteInventoryViewModel>();
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        final l = vm.lookups;
        return ListView(
          padding: pagePadding(context),
          children: [
            SizedBox(
              width: 400,
              child: DropdownButtonFormField<int>(
                initialValue: vm.projectId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Project'),
                items: [
                  for (final p in l.projects.values)
                    DropdownMenuItem(
                      value: p.id,
                      child: Text('${p.code} · ${p.name}'),
                    ),
                ],
                onChanged: vm.setProject,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppSectionCard(
              title: 'Stock on site',
              padding: EdgeInsets.zero,
              child: ProcurementInventoryTable(
                lines: vm.lines,
                materialName: l.materialName,
                unit: l.unit,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'On hand = deliveries received − damaged − materials used on '
              'approved daily reports. Red means more was used than delivered.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/finance_access.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/models/equipment.dart';
import '../../../shared/widgets/app_page_header.dart';
import '../../../shared/widgets/app_status_chip.dart';
import '../viewmodels/admin_audit.dart';
import '../viewmodels/equipment_master_list_viewmodel.dart';
import '../widgets/admin_dashboard/admin_dashboard_kit.dart';
import '../widgets/user_management_equipment_dialog.dart';

/// System admin: the Queen Builders equipment master list. Every entry here
/// appears in the equipment dropdown when a site engineer or project manager
/// borrows or rents equipment on a project's Equipment tab.
class EquipmentMasterListPage extends StatefulWidget {
  const EquipmentMasterListPage({super.key});

  @override
  State<EquipmentMasterListPage> createState() =>
      _EquipmentMasterListPageState();
}

class _EquipmentMasterListPageState extends State<EquipmentMasterListPage> {
  final _search = TextEditingController();
  late final _vm = EquipmentMasterListViewModel(
    masterData: getIt(),
    audit: AdminAudit.fromLocator(),
  )..load();

  @override
  void dispose() {
    _search.dispose();
    _vm.dispose();
    super.dispose();
  }

  Future<void> _edit([Equipment? initial]) async {
    final result = await UserManagementEquipmentDialog.show(
      context,
      initial: initial,
    );
    if (result == null || !mounted) return;
    await reportAction(
      context,
      _vm.save(result),
      success: initial == null
          ? 'Added "${result.name}" to the equipment list.'
          : 'Saved "${result.name}".',
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Consumer<EquipmentMasterListViewModel>(
        builder: (context, vm, _) {
          if (vm.isLoading) return const AdminTabSkeleton();
          if (vm.error != null) {
            return AdminErrorState(message: vm.error!, onRetry: vm.load);
          }
          final items = vm.items;
          final textTheme = Theme.of(context).textTheme;
          return ListView(
            padding: pagePadding(context),
            children: [
              AppPageHeader(
                title: 'Equipment master list',
                subtitle:
                    'Queen Builders tools and machinery. Every entry shows in '
                    'the equipment dropdown when a project borrows or rents '
                    'equipment.',
                actions: [
                  FilledButton.icon(
                    onPressed: vm.isBusy ? null : () => _edit(),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add equipment'),
                  ),
                ],
              ),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 320,
                    child: TextField(
                      controller: _search,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search equipment',
                      ),
                      onChanged: vm.setQuery,
                    ),
                  ),
                  ChoiceChip(
                    label: Text('All (${vm.all.length})'),
                    selected: vm.ownershipFilter == null,
                    onSelected: (_) => vm.setOwnership(null),
                  ),
                  for (final o in EquipmentOwnership.values)
                    ChoiceChip(
                      label: Text('${_ownershipLabel(o)} (${vm.countOf(o)})'),
                      selected: vm.ownershipFilter == o,
                      onSelected: (_) => vm.setOwnership(o),
                    ),
                  if (vm.hasFilters)
                    TextButton.icon(
                      onPressed: () {
                        _search.clear();
                        vm.clearFilters();
                      },
                      icon: const Icon(Icons.filter_alt_off_outlined),
                      label: const Text('Clear filters'),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              if (!canManageFinance())
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Text(
                    'Rates are read-only for the admin role. New entries '
                    'start at ₱0.00.',
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              if (vm.all.isEmpty)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.construction_outlined),
                    title: const Text('No equipment yet.'),
                    subtitle: const Text(
                      'Add the company\'s tools and machinery so site teams '
                      'can pick them when borrowing.',
                    ),
                    trailing: TextButton(
                      onPressed: vm.isBusy ? null : () => _edit(),
                      child: const Text('Add equipment'),
                    ),
                  ),
                )
              else if (items.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.search_off),
                    title: Text('No equipment matches.'),
                    subtitle: Text('Try another search or clear filters.'),
                  ),
                )
              else
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (final (i, e) in items.indexed) ...[
                        if (i > 0) const Divider(height: 1),
                        _EquipmentTile(
                          equipment: e,
                          showRate: canSeeFinance(),
                          onEdit: vm.isBusy ? null : () => _edit(e),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

String _ownershipLabel(EquipmentOwnership o) => switch (o) {
  EquipmentOwnership.owned => 'QB owned',
  EquipmentOwnership.rented => 'Rented',
};

class _EquipmentTile extends StatelessWidget {
  const _EquipmentTile({
    required this.equipment,
    required this.showRate,
    required this.onEdit,
  });

  final Equipment equipment;
  final bool showRate;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final e = equipment;
    final owned = e.ownership == EquipmentOwnership.owned;
    final meta = [
      if (showRate) '${Formatters.peso(e.rate)} ${e.rateUnit.label}',
      if (e.updatedAt != null) 'Updated ${Formatters.date(e.updatedAt!)}',
    ].join(' · ');
    return ListTile(
      leading: Icon(
        owned ? Icons.handyman_outlined : Icons.local_shipping_outlined,
        color: owned ? AppColors.brandGold : AppColors.textSecondary,
      ),
      title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: meta.isEmpty ? null : Text(meta),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppStatusChip(
            label: _ownershipLabel(e.ownership),
            foreground: owned ? AppColors.brandGoldText : AppColors.info,
            background: owned
                ? AppColors.selected
                : AppColors.surfaceSunken,
          ),
          const SizedBox(width: AppSpacing.sm),
          IconButton(
            tooltip: 'Edit',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      onTap: onEdit,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/finance_access.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_padding.dart';
import '../../../shared/widgets/app_confirm_dialog.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_supplier_form_dialog.dart';
import '../viewmodels/master_lists_viewmodel.dart';
import '../widgets/user_management_client_dialog.dart';
import '../widgets/user_management_equipment_dialog.dart';
import '../widgets/user_management_material_dialog.dart';
import '../widgets/user_management_trade_dialog.dart';

/// Materials with unit costs, suppliers, trades, clients and equipment.
class MasterListsPage extends StatelessWidget {
  const MasterListsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) =>
          MasterListsViewModel(masterData: getIt(), clients: getIt())..load(),
      builder: (context, _) {
        final vm = context.watch<MasterListsViewModel>();
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (vm.error != null) return AppEmptyState(message: vm.error!);
        return DefaultTabController(
          length: 5,
          child: Column(
            children: [
              Material(
                color: Theme.of(context).colorScheme.surface,
                child: const TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    Tab(text: 'Materials and unit costs'),
                    Tab(text: 'Suppliers'),
                    Tab(text: 'Trades'),
                    Tab(text: 'Clients'),
                    Tab(text: 'Equipment'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _list(
                      context,
                      addLabel: 'Add material',
                      onAdd: () async {
                        final m = await UserManagementMaterialDialog.show(
                          context,
                        );
                        if (m != null && context.mounted) {
                          await reportAction(context, vm.saveMaterial(m));
                        }
                      },
                      tiles: [
                        for (final m in vm.materials)
                          ListTile(
                            title: Text(m.name),
                            subtitle: Text(
                              '${canSeeFinance() ? '${Formatters.peso(m.defaultUnitCost)} per ' : 'Unit: '}${m.unit}'
                              '${m.storeSku == null ? '' : ' · SKU ${m.storeSku}'}',
                            ),
                            trailing: const Icon(Icons.edit_outlined),
                            onTap: () async {
                              final edited =
                                  await UserManagementMaterialDialog.show(
                                    context,
                                    initial: m,
                                  );
                              if (edited != null && context.mounted) {
                                await reportAction(
                                  context,
                                  vm.saveMaterial(edited),
                                );
                              }
                            },
                          ),
                      ],
                    ),
                    _list(
                      context,
                      addLabel: 'Add supplier',
                      onAdd: () async {
                        final s = await AppSupplierFormDialog.show(context);
                        if (s != null && context.mounted) {
                          await reportAction(context, vm.saveSupplier(s));
                        }
                      },
                      tiles: [
                        for (final s in vm.suppliers)
                          ListTile(
                            title: Text(s.name),
                            subtitle: Text(
                              [
                                if (s.isOwnStore) 'Own store',
                                ?s.contactPerson,
                                ?s.phone,
                              ].join(' · '),
                            ),
                            trailing: const Icon(Icons.edit_outlined),
                            onTap: () async {
                              final edited = await AppSupplierFormDialog.show(
                                context,
                                initial: s,
                              );
                              if (edited != null && context.mounted) {
                                await reportAction(
                                  context,
                                  vm.saveSupplier(edited),
                                );
                              }
                            },
                          ),
                      ],
                    ),
                    _list(
                      context,
                      addLabel: 'Add trade',
                      onAdd: () async {
                        final t = await UserManagementTradeDialog.show(context);
                        if (t != null && context.mounted) {
                          await reportAction(context, vm.saveTrade(t));
                        }
                      },
                      tiles: [
                        for (final t in vm.trades)
                          ListTile(
                            title: Text(t.name),
                            onTap: () async {
                              final edited =
                                  await UserManagementTradeDialog.show(
                                    context,
                                    initial: t,
                                  );
                              if (edited != null && context.mounted) {
                                await reportAction(
                                  context,
                                  vm.saveTrade(edited),
                                );
                              }
                            },
                            trailing: IconButton(
                              tooltip: 'Delete trade',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                final ok = await showAppConfirmDialog(
                                  context,
                                  title: 'Delete ${t.name}?',
                                  message:
                                      'Existing reports and workers keep their '
                                      'trade text.',
                                  confirmLabel: 'Delete',
                                  destructive: true,
                                );
                                if (ok && context.mounted) {
                                  await reportAction(
                                    context,
                                    vm.deleteTrade(t),
                                  );
                                }
                              },
                            ),
                          ),
                      ],
                    ),
                    _list(
                      context,
                      addLabel: 'Add client',
                      onAdd: () async {
                        final c = await UserManagementClientDialog.show(
                          context,
                        );
                        if (c != null && context.mounted) {
                          await reportAction(context, vm.saveClient(c));
                        }
                      },
                      tiles: [
                        for (final c in vm.clients)
                          ListTile(
                            title: Text(c.name),
                            subtitle: Text(
                              [
                                ?c.contactPerson,
                                ?c.email,
                                c.userId == null
                                    ? 'No portal login'
                                    : 'Portal login linked',
                              ].join(' · '),
                            ),
                            trailing: const Icon(Icons.edit_outlined),
                            onTap: () async {
                              final edited =
                                  await UserManagementClientDialog.show(
                                    context,
                                    initial: c,
                                  );
                              if (edited != null && context.mounted) {
                                await reportAction(
                                  context,
                                  vm.saveClient(edited),
                                );
                              }
                            },
                          ),
                      ],
                    ),
                    _list(
                      context,
                      addLabel: 'Add equipment',
                      onAdd: () async {
                        final e = await UserManagementEquipmentDialog.show(
                          context,
                        );
                        if (e != null && context.mounted) {
                          await reportAction(context, vm.saveEquipment(e));
                        }
                      },
                      tiles: [
                        for (final e in vm.equipment)
                          ListTile(
                            title: Text(e.name),
                            subtitle: Text(
                              '${e.ownership.label}'
                              '${canSeeFinance() ? ' · ${Formatters.peso(e.rate)} ${e.rateUnit.label}' : ''}',
                            ),
                            trailing: const Icon(Icons.edit_outlined),
                            onTap: () async {
                              final edited =
                                  await UserManagementEquipmentDialog.show(
                                    context,
                                    initial: e,
                                  );
                              if (edited != null && context.mounted) {
                                await reportAction(
                                  context,
                                  vm.saveEquipment(edited),
                                );
                              }
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _list(
    BuildContext context, {
    required String addLabel,
    required VoidCallback onAdd,
    required List<Widget> tiles,
  }) => ListView(
    padding: pagePadding(context),
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: Text(addLabel),
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (final (i, t) in tiles.indexed) ...[
              if (i > 0) const Divider(height: 1),
              t,
            ],
          ],
        ),
      ),
    ],
  );
}

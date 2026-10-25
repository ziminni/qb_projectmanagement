import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/page_padding.dart';
import '../../../shared/widgets/app_supplier_form_dialog.dart';
import '../viewmodels/suppliers_viewmodel.dart';

/// Purchasing's supplier list. The own hardware store is listed first.
class SuppliersPage extends StatelessWidget {
  const SuppliersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SuppliersViewModel(masterData: getIt())..load(),
      builder: (context, _) {
        final vm = context.watch<SuppliersViewModel>();
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: pagePadding(context),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: () async {
                  final s = await AppSupplierFormDialog.show(context);
                  if (s != null && context.mounted) {
                    await reportAction(context, vm.save(s));
                  }
                },
                icon: const Icon(Icons.add),
                label: const Text('Add supplier'),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final (i, s) in vm.items.indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    ListTile(
                      leading: Icon(
                        s.isOwnStore
                            ? Icons.storefront_outlined
                            : Icons.local_shipping_outlined,
                      ),
                      title: Text(s.name),
                      subtitle: Text(
                        [
                          if (s.isOwnStore) 'Own store',
                          ?s.contactPerson,
                          ?s.phone,
                          ?s.address,
                        ].join(' · '),
                      ),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () async {
                        final edited = await AppSupplierFormDialog.show(
                          context,
                          initial: s,
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

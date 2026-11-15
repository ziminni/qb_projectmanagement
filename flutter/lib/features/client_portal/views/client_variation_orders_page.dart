import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/di/service_locator.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_padding.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_vo_status_chip.dart';
import '../viewmodels/client_variation_orders_viewmodel.dart';

class ClientVariationOrdersPage extends StatelessWidget {
  const ClientVariationOrdersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ClientVariationOrdersViewModel(
        session: getIt(),
        projects: getIt(),
        billing: getIt(),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<ClientVariationOrdersViewModel>();
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (vm.items.isEmpty) {
          return const AppEmptyState(message: 'No variation orders.');
        }
        return ListView(
          padding: pagePadding(context),
          children: [
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final (i, v) in vm.items.indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    ListTile(
                      onTap: () =>
                          context.go(AppRoutes.clientVariationOrder(v.id)),
                      title: Text(
                        '${v.voNo} · ${vm.projectsById[v.projectId]?.name}',
                      ),
                      subtitle: Text(
                        '${v.description}\n${v.amount >= 0 ? '+' : '−'}'
                        '${Formatters.peso(v.amount.abs())} · '
                        '${v.daysImpact} day(s)',
                      ),
                      isThreeLine: true,
                      trailing: AppVoStatusChip(status: v.status),
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

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/models/progress_billing.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_billing_status_chip.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../viewmodels/client_billings_viewmodel.dart';

class ClientBillingsPage extends StatelessWidget {
  const ClientBillingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ClientBillingsViewModel(
        session: getIt(),
        projects: getIt(),
        billing: getIt(),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<ClientBillingsViewModel>();
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (vm.items.isEmpty) {
          return const AppEmptyState(message: 'No billings yet.');
        }
        Widget tile(ProgressBilling b) => ListTile(
          onTap: () => context.go(AppRoutes.clientBilling(b.id)),
          title: Text(
            'Billing #${b.billingNo} · ${vm.projectsById[b.projectId]?.name}',
          ),
          subtitle: Text(
            'Period ending ${Formatters.date(b.periodEnd)} · '
            '${Formatters.peso(b.netDue)} due',
          ),
          trailing: AppBillingStatusChip(status: b.status),
        );
        return ListView(
          padding: pagePadding(context),
          children: [
            if (vm.waiting.isNotEmpty) ...[
              AppSectionCard(
                title: 'Waiting for your approval',
                padding: EdgeInsets.zero,
                child: Column(children: [for (final b in vm.waiting) tile(b)]),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            if (vm.others.isNotEmpty)
              AppSectionCard(
                title: 'All billings',
                padding: EdgeInsets.zero,
                child: Column(children: [for (final b in vm.others) tile(b)]),
              ),
          ],
        );
      },
    );
  }
}

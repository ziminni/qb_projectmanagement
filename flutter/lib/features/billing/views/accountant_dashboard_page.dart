import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/models/progress_billing.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_billing_status_chip.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_page_header.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../../../shared/widgets/app_status_chip.dart';
import '../../dashboard/widgets/dashboard_stat_tile.dart';
import '../viewmodels/accountant_dashboard_viewmodel.dart';

class AccountantDashboardPage extends StatefulWidget {
  const AccountantDashboardPage({super.key});

  @override
  State<AccountantDashboardPage> createState() =>
      _AccountantDashboardPageState();
}

class _AccountantDashboardPageState extends State<AccountantDashboardPage> {
  late final _vm = AccountantDashboardViewModel(
    projects: getIt(),
    billing: getIt(),
    labor: getIt(),
  )..load();

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Consumer<AccountantDashboardViewModel>(
        builder: (context, vm, _) {
          if (vm.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (vm.error != null) {
            return AppEmptyState(
              message: vm.error!,
              icon: Icons.error_outline,
              action: FilledButton.icon(
                onPressed: vm.load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            );
          }

          final wide =
              MediaQuery.sizeOf(context).width >= AppSpacing.wideBreakpoint;
          final kpis = [
            DashboardStatTile(
              label: 'Payroll to process',
              value: '${vm.verifiedPeriods.length}',
              detail: '${vm.openPeriodsCount} open periods',
              icon: Icons.payments_outlined,
              color: vm.verifiedPeriods.isNotEmpty
                  ? AppColors.warning
                  : AppColors.success,
              onTap: () => context.go(AppRoutes.payroll),
            ),
            DashboardStatTile(
              label: 'Receivables due',
              value: Formatters.peso(vm.outstandingReceivables),
              detail: '${vm.awaitingCollection.length} billings open',
              icon: Icons.receipt_long_outlined,
              color: AppColors.brandGoldText,
              onTap: () => context.go(AppRoutes.billings),
            ),
            DashboardStatTile(
              label: 'Collected to date',
              value: Formatters.peso(vm.totalCollected),
              detail: '${vm.recentPayments.length} recent receipts',
              icon: Icons.account_balance_wallet_outlined,
              color: AppColors.success,
              onTap: () => context.go(AppRoutes.billings),
            ),
            DashboardStatTile(
              label: 'Retention balance',
              value: Formatters.peso(vm.retentionBalance),
              detail: 'Across ${vm.projects.length} projects',
              icon: Icons.savings_outlined,
              onTap: () => context.go(AppRoutes.retention),
            ),
          ];

          final leftColumn = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppSectionCard(
                title: 'Payroll ready to process',
                icon: Icons.payments_outlined,
                subtitle: vm.verifiedPeriods.isEmpty
                    ? 'All verified periods are processed'
                    : '${vm.verifiedPeriods.length} verified by Project Manager',
                trailing: TextButton(
                  onPressed: () => context.go(AppRoutes.payroll),
                  child: const Text('All payroll'),
                ),
                padding: EdgeInsets.zero,
                child: vm.verifiedPeriods.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(AppSpacing.lg),
                        child: Text(
                          'No verified payroll periods waiting right now.',
                        ),
                      )
                    : Column(
                        children: [
                          for (final (i, p) in vm.verifiedPeriods.indexed) ...[
                            if (i > 0) const Divider(height: 1),
                            ListTile(
                              leading: Container(
                                width: 36,
                                height: 36,
                                decoration: const BoxDecoration(
                                  color: AppColors.warningContainer,
                                  borderRadius: AppRadii.mdAll,
                                ),
                                child: const Icon(
                                  Icons.schedule_send_outlined,
                                  size: 18,
                                  color: AppColors.warning,
                                ),
                              ),
                              title: Text(vm.projectName(p.projectId)),
                              subtitle: Text(
                                Formatters.dateRange(
                                  p.periodStart,
                                  p.periodEnd,
                                ),
                              ),
                              trailing: const AppStatusChip(
                                label: 'Ready to process',
                                foreground: AppColors.warning,
                                background: AppColors.warningContainer,
                              ),
                              onTap: () =>
                                  context.go(AppRoutes.payrollPeriod(p.id)),
                            ),
                          ],
                        ],
                      ),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppSectionCard(
                title: 'Billings awaiting collection',
                icon: Icons.receipt_long_outlined,
                subtitle: vm.awaitingCollection.isEmpty
                    ? 'No unpaid approved billings'
                    : '${vm.awaitingCollection.length} open progress billings',
                trailing: TextButton(
                  onPressed: () => context.go(AppRoutes.billings),
                  child: const Text('All billings'),
                ),
                padding: EdgeInsets.zero,
                child: vm.awaitingCollection.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(AppSpacing.lg),
                        child: Text('No billings awaiting payment right now.'),
                      )
                    : Column(
                        children: [
                          for (final (i, b)
                              in vm.awaitingCollection.take(8).indexed) ...[
                            if (i > 0) const Divider(height: 1),
                            ListTile(
                              title: Text(
                                '${b.billingNo} · ${vm.projectName(b.projectId)}',
                              ),
                              subtitle: Text(
                                'Net due ${Formatters.peso(b.netDue)}'
                                '${b.status == BillingStatus.disputed ? ' · Disputed by client' : ''}',
                              ),
                              trailing: AppBillingStatusChip(status: b.status),
                              onTap: () => context.go(AppRoutes.billing(b.id)),
                            ),
                          ],
                        ],
                      ),
              ),
            ],
          );

          final rightColumn = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppSectionCard(
                title: 'Recent client payments',
                icon: Icons.check_circle_outline,
                padding: EdgeInsets.zero,
                child: vm.recentPayments.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(AppSpacing.lg),
                        child: Text('No client payments recorded yet.'),
                      )
                    : Column(
                        children: [
                          for (final (i, pay) in vm.recentPayments.indexed) ...[
                            if (i > 0) const Divider(height: 1),
                            ListTile(
                              dense: true,
                              title: Text(Formatters.peso(pay.amount)),
                              subtitle: Text(
                                [
                                  Formatters.date(pay.paidOn),
                                  pay.method.label,
                                  if ((pay.referenceNo ?? '').isNotEmpty)
                                    pay.referenceNo!,
                                ].join(' · '),
                              ),
                              trailing: const Icon(
                                Icons.chevron_right_rounded,
                                size: 18,
                              ),
                              onTap: () => context.go(
                                AppRoutes.billing(pay.progressBillingId),
                              ),
                            ),
                          ],
                        ],
                      ),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppSectionCard(
                title: 'Accounting shortcuts',
                icon: Icons.bolt_outlined,
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.engineering_outlined, size: 20),
                      title: Text('Workers (${vm.activeWorkers} active)'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => context.go(AppRoutes.workers),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(
                        Icons.request_quote_outlined,
                        size: 20,
                      ),
                      title: const Text('Supplier payables'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => context.go(AppRoutes.payables),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.savings_outlined, size: 20),
                      title: const Text('Retention releases'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => context.go(AppRoutes.retention),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.summarize_outlined, size: 20),
                      title: const Text('Expense reports'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => context.go(AppRoutes.expenseReports),
                    ),
                  ],
                ),
              ),
            ],
          );

          return RefreshIndicator(
            onRefresh: vm.load,
            child: ListView(
              padding: pagePadding(context),
              children: [
                AppPageHeader(
                  title: 'Accountant dashboard',
                  subtitle:
                      'Payroll processing queue, client receivables, retention balances, and recent receipts.',
                  actions: [
                    OutlinedButton.icon(
                      onPressed: vm.load,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Refresh'),
                    ),
                  ],
                ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final cols = constraints.maxWidth >= 960
                        ? 4
                        : constraints.maxWidth >= 560
                        ? 2
                        : 1;
                    final tileWidth =
                        (constraints.maxWidth - (cols - 1) * AppSpacing.md) /
                        cols;
                    return Wrap(
                      spacing: AppSpacing.md,
                      runSpacing: AppSpacing.md,
                      children: [
                        for (final tile in kpis)
                          SizedBox(width: tileWidth, child: tile),
                      ],
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 7, child: leftColumn),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(flex: 5, child: rightColumn),
                    ],
                  )
                else ...[
                  leftColumn,
                  const SizedBox(height: AppSpacing.lg),
                  rightColumn,
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

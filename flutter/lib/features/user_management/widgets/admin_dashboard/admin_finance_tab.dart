import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../data/models/payroll_period.dart';
import '../../../../data/models/progress_billing.dart';
import '../../../../shared/widgets/app_progress_bar.dart';
import '../../../../shared/widgets/app_section_card.dart';
import '../../../dashboard/widgets/dashboard_stat_tile.dart';
import '../../viewmodels/admin_dashboard/admin_finance_viewmodel.dart';
import 'admin_dashboard_kit.dart';

/// Company-wide billing, collections, payables and retention. Read-only.
class AdminFinanceTab extends StatelessWidget {
  const AdminFinanceTab({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminTabHost<AdminFinanceViewModel>(
      create: () => AdminFinanceViewModel(
        projects: getIt(),
        billing: getIt(),
        procurement: getIt(),
        labor: getIt(),
      ),
      build: (context, vm) {
        final attention = <Widget>[
          for (final b in vm.disputed)
            AdminListRow(
              icon: Icons.gpp_maybe_outlined,
              iconColor: AppColors.error,
              title: 'Billing #${b.billingNo} disputed by the client',
              subtitle:
                  '${vm.projectName(b.projectId)} · '
                  '${Formatters.peso(b.netDue)}',
            ),
          for (final b in vm.slowClientReplies)
            AdminListRow(
              icon: Icons.schedule_outlined,
              iconColor: AppColors.warning,
              title: 'Billing #${b.billingNo} waiting on the client',
              subtitle:
                  '${vm.projectName(b.projectId)} · sent over two weeks ago',
            ),
          for (final b in vm.approvedUnpaid)
            AdminListRow(
              icon: Icons.payments_outlined,
              iconColor: AppColors.warning,
              title: 'Billing #${b.billingNo} approved, not yet paid',
              subtitle:
                  '${vm.projectName(b.projectId)} · '
                  '${Formatters.peso(b.netDue)}',
            ),
          if (vm.payrollIn(PayrollStatus.verified) > 0)
            AdminListRow(
              icon: Icons.badge_outlined,
              iconColor: AppColors.warning,
              title:
                  '${vm.payrollIn(PayrollStatus.verified)} payroll '
                  'period(s) verified, not processed',
              subtitle: 'The accountant still has to pay these out.',
            ),
          if (vm.storeFailures > 0)
            AdminListRow(
              icon: Icons.cloud_off_outlined,
              iconColor: AppColors.textSecondary,
              title: 'The store could not be reached',
              subtitle:
                  '${vm.storeFailures} project balance(s) are missing from '
                  'the store total.',
            ),
        ];
        return [
          const _ReadOnlyNote(),
          const SizedBox(height: AppSpacing.md),
          AdminStatGrid(
            tiles: [
              DashboardStatTile(
                label: 'Billed to clients',
                value: Formatters.pesoWhole(vm.billed),
                detail:
                    'Open contracts ${Formatters.pesoWhole(vm.openContractValue)}',
                icon: Icons.receipt_long_outlined,
              ),
              DashboardStatTile(
                label: 'Collected',
                value: Formatters.pesoWhole(vm.collected),
                detail:
                    '${Formatters.percent(vm.collectionRate)} of billed · '
                    '${Formatters.pesoWhole(vm.collectedLast30Days)} in 30 days',
                progress: vm.collectionRate.clamp(0, 1),
                icon: Icons.savings_outlined,
                color: AppColors.success,
              ),
              DashboardStatTile(
                label: 'Receivable',
                value: Formatters.pesoWhole(vm.receivable),
                detail: 'Billed, not yet collected',
                icon: Icons.account_balance_wallet_outlined,
                color: vm.receivable > 0 ? AppColors.warning : null,
              ),
              DashboardStatTile(
                label: 'Owed to the store',
                value: vm.hasStoreFigures || vm.storeFailures == 0
                    ? Formatters.pesoWhole(vm.storeOwed)
                    : '—',
                detail: vm.storeFailures > 0
                    ? 'Store offline for ${vm.storeFailures} project(s)'
                    : 'Own hardware store balance',
                icon: Icons.storefront_outlined,
                color: vm.storeOwed > 0 ? AppColors.warning : null,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          AdminTwoColumn(
            main: [
              AppSectionCard(
                title: 'Needs attention',
                icon: Icons.flag_outlined,
                subtitle: attention.isEmpty
                    ? null
                    : '${attention.length} open items',
                padding: EdgeInsets.zero,
                child: AdminRowList(
                  rows: attention,
                  emptyTitle: 'Nothing outstanding',
                  emptySubtitle: 'No disputes, slow replies or unpaid bills.',
                ),
              ),
              AppSectionCard(
                title: 'Recent client payments',
                icon: Icons.payments_outlined,
                padding: EdgeInsets.zero,
                child: AdminRowList(
                  emptyTitle: 'No payments recorded yet',
                  rows: [
                    for (final p in vm.recentPayments)
                      AdminListRow(
                        title: vm.projectName(
                          vm.projectOfBilling(p.progressBillingId) ?? -1,
                        ),
                        subtitle:
                            '${Formatters.date(p.paidOn)} · ${p.method.label}'
                            '${p.referenceNo == null ? '' : ' · ${p.referenceNo}'}',
                        trailing: AdminFigureText(
                          Formatters.peso(p.amount),
                          color: AppColors.success,
                        ),
                      ),
                  ],
                ),
              ),
            ],
            side: [
              AppSectionCard(
                title: 'Billings by status',
                icon: Icons.receipt_outlined,
                child: AdminBreakdownBars(
                  emptyMessage: 'No billings yet.',
                  items: [
                    for (final s in BillingStatus.values)
                      if (vm.billingsByStatus[s] case final v?)
                        AdminBreakdownItem(
                          '${s.label} (${v.count})',
                          v.amount,
                          display: Formatters.pesoWhole(v.amount),
                          color: switch (s) {
                            BillingStatus.paid => AppColors.success,
                            BillingStatus.disputed => AppColors.error,
                            BillingStatus.draft ||
                            BillingStatus.rejected => AppColors.disabled,
                            _ => AppColors.brandGold,
                          },
                        ),
                  ],
                ),
              ),
              AppSectionCard(
                title: 'Held and pending',
                icon: Icons.lock_clock_outlined,
                child: Column(
                  children: [
                    _Line('Retention held', Formatters.peso(vm.retentionHeld)),
                    _Line(
                      'Approved variation orders',
                      Formatters.peso(vm.approvedVoTotal),
                    ),
                    _Line(
                      'Pending variation orders (${vm.pendingVoCount})',
                      Formatters.peso(vm.pendingVoTotal),
                    ),
                    _Line(
                      'Payroll open / verified / processed',
                      '${vm.payrollIn(PayrollStatus.open)} / '
                          '${vm.payrollIn(PayrollStatus.verified)} / '
                          '${vm.payrollIn(PayrollStatus.processed)}',
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          AppSectionCard(
            title: 'By project',
            icon: Icons.table_rows_outlined,
            subtitle: 'Largest receivable first.',
            padding: EdgeInsets.zero,
            child: vm.projectRows.isEmpty
                ? const ListTile(title: Text('No projects yet.'))
                : Column(
                    children: [
                      for (final (i, r) in vm.projectRows.indexed) ...[
                        if (i > 0) const Divider(height: 1),
                        _ProjectMoneyRow(row: r),
                      ],
                    ],
                  ),
          ),
        ];
      },
    );
  }
}

class _ReadOnlyNote extends StatelessWidget {
  const _ReadOnlyNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.infoContainer,
        borderRadius: AppRadii.mdAll,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.visibility_outlined, color: AppColors.info),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Read-only. Billing, payments and payroll are recorded by the '
              'owner and the accountant.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          AdminFigureText(value),
        ],
      ),
    );
  }
}

class _ProjectMoneyRow extends StatelessWidget {
  const _ProjectMoneyRow({required this.row});
  final AdminProjectMoney row;

  @override
  Widget build(BuildContext context) {
    final p = row.project;
    final textTheme = Theme.of(context).textTheme;
    final figures = [
      ('Contract', Formatters.pesoWhole(p.contractAmount), null),
      ('Billed', Formatters.pesoWhole(row.billed), null),
      ('Collected', Formatters.pesoWhole(row.collected), AppColors.success),
      (
        'Receivable',
        Formatters.pesoWhole(row.receivable),
        row.receivable > 0 ? AppColors.warning : null,
      ),
      if (row.storeBalance != null && row.storeBalance! > 0)
        ('Store', Formatters.pesoWhole(row.storeBalance!), AppColors.warning),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${p.code} · ${p.name}', style: textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xl,
            runSpacing: AppSpacing.sm,
            children: [
              for (final (label, value, color) in figures)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: textTheme.labelSmall),
                    AdminFigureText(value, color: color),
                  ],
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: AppProgressBar(
                  value: row.billedShare.clamp(0, 1),
                  height: 6,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${Formatters.percent(row.billedShare.clamp(0, 1))} billed',
                style: textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

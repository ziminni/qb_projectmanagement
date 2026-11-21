import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/utils/finance_access.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../data/models/material_request.dart';
import '../../../../data/models/material_source.dart';
import '../../../../data/models/purchase_order.dart';
import '../../../../shared/widgets/app_section_card.dart';
import '../../../../shared/widgets/app_status_chip.dart';
import '../../../dashboard/widgets/dashboard_stat_tile.dart';
import '../../viewmodels/admin_dashboard/admin_procurement_viewmodel.dart';
import 'admin_dashboard_kit.dart';

/// Material requests, purchase orders and the own-store link.
class AdminProcurementTab extends StatelessWidget {
  const AdminProcurementTab({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminTabHost<AdminProcurementViewModel>(
      create: () => AdminProcurementViewModel(
        procurement: getIt(),
        projects: getIt(),
        users: getIt(),
      ),
      build: (context, vm) {
        final finance = canSeeFinance();
        final spend = vm.spendLast30Days;
        final spendTotal = spend.values.fold<double>(0, (s, v) => s + v);
        final pending = vm.pendingRequests;
        final storeIssues = <Widget>[
          for (final o in vm.declinedByStore)
            AdminListRow(
              icon: Icons.block_outlined,
              iconColor: AppColors.error,
              title: '${o.poNo} declined by the store',
              subtitle: vm.projectLabel(o.projectId),
            ),
          for (final o in vm.unansweredByStore)
            AdminListRow(
              icon: Icons.hourglass_bottom_outlined,
              iconColor: AppColors.warning,
              title: '${o.poNo} not answered by the store',
              subtitle:
                  '${vm.projectLabel(o.projectId)} · sent '
                  '${o.createdAt == null ? '' : Formatters.date(o.createdAt!)}',
            ),
        ];
        return [
          AdminStatGrid(
            tiles: [
              DashboardStatTile(
                label: 'Requests waiting',
                value: '${pending.length}',
                detail: vm.latePendingCount > 0
                    ? '${vm.latePendingCount} past their needed-by date'
                    : 'Waiting for the owner',
                icon: Icons.inventory_outlined,
                color: vm.latePendingCount > 0 ? AppColors.error : null,
              ),
              DashboardStatTile(
                label: 'Awaiting delivery',
                value: '${vm.awaitingDelivery}',
                detail: 'Orders not fully on site',
                icon: Icons.local_shipping_outlined,
              ),
              DashboardStatTile(
                label: 'Store issues',
                value: '${storeIssues.length}',
                detail: storeIssues.isEmpty
                    ? 'Store link healthy'
                    : 'Declined or unanswered orders',
                icon: Icons.storefront_outlined,
                color: storeIssues.isEmpty
                    ? AppColors.success
                    : AppColors.warning,
              ),
              DashboardStatTile(
                label: finance ? 'Ordered in 30 days' : 'Orders placed',
                value: finance
                    ? Formatters.pesoWhole(spendTotal)
                    : '${vm.ordersBySource.values.fold<int>(0, (s, v) => s + v)}',
                detail:
                    '${vm.ordersBySource[MaterialSource.ownStore] ?? 0} own store · '
                    '${vm.ordersBySource[MaterialSource.external] ?? 0} other',
                icon: Icons.shopping_cart_outlined,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          AdminTwoColumn(
            main: [
              AppSectionCard(
                title: 'Requests waiting for the owner',
                icon: Icons.pending_actions_outlined,
                subtitle: pending.isEmpty
                    ? null
                    : 'Most urgent needed-by date first',
                padding: EdgeInsets.zero,
                child: AdminRowList(
                  emptyTitle: 'No requests waiting',
                  rows: [
                    for (final r in pending.take(8))
                      AdminListRow(
                        icon: Icons.inventory_2_outlined,
                        iconColor: r.neededBy.isBefore(vm.today)
                            ? AppColors.error
                            : null,
                        title: vm.projectLabel(r.projectId),
                        subtitle:
                            'From ${vm.userName(r.requestedBy)} · needed by '
                            '${Formatters.date(r.neededBy)}',
                        trailing: r.neededBy.isBefore(vm.today)
                            ? const AppStatusChip(
                                label: 'Late',
                                foreground: AppColors.error,
                                background: AppColors.errorContainer,
                              )
                            : null,
                      ),
                  ],
                ),
              ),
              AppSectionCard(
                title: 'Store link',
                icon: Icons.sync_problem_outlined,
                subtitle:
                    'Own-store orders the store refused or never '
                    'answered (${AdminProcurementViewModel.stuckAfterDays}+ days).',
                padding: EdgeInsets.zero,
                child: AdminRowList(
                  rows: storeIssues,
                  emptyTitle: 'Every own-store order has an answer',
                ),
              ),
              AppSectionCard(
                title: 'Open orders',
                icon: Icons.local_shipping_outlined,
                subtitle: 'Oldest first',
                padding: EdgeInsets.zero,
                child: AdminRowList(
                  emptyTitle: 'Nothing waiting for delivery',
                  rows: [
                    for (final o in vm.openOrders.take(8))
                      AdminListRow(
                        title: '${o.poNo} · ${vm.projectLabel(o.projectId)}',
                        subtitle:
                            '${o.source.label} · ${o.statusLabel}'
                            '${o.createdAt == null ? '' : ' · ${Formatters.date(o.createdAt!)}'}',
                        trailing: finance && !o.financeKeysOmitted
                            ? AdminFigureText(Formatters.peso(o.totalAmount))
                            : null,
                      ),
                  ],
                ),
              ),
            ],
            side: [
              AppSectionCard(
                title: 'Requests',
                icon: Icons.inventory_outlined,
                child: AdminBreakdownBars(
                  items: [
                    for (final s in MaterialRequestStatus.values)
                      AdminBreakdownItem(
                        s.label,
                        vm.requestsIn(s).toDouble(),
                        color: switch (s) {
                          MaterialRequestStatus.pending => AppColors.warning,
                          MaterialRequestStatus.rejected => AppColors.disabled,
                          MaterialRequestStatus.ordered => AppColors.success,
                        },
                      ),
                  ],
                ),
              ),
              AppSectionCard(
                title: 'Orders by status',
                icon: Icons.receipt_outlined,
                child: AdminBreakdownBars(
                  emptyMessage: 'No orders yet.',
                  items: [
                    for (final e in vm.ordersByStatus.entries)
                      AdminBreakdownItem(
                        e.key.label,
                        e.value.toDouble(),
                        color: switch (e.key) {
                          PurchaseOrderStatus.delivered => AppColors.success,
                          PurchaseOrderStatus.cancelled => AppColors.disabled,
                          _ => AppColors.brandGold,
                        },
                      ),
                  ],
                ),
              ),
              if (finance)
                AppSectionCard(
                  title: 'Ordered in 30 days',
                  icon: Icons.pie_chart_outline,
                  child: AdminBreakdownBars(
                    emptyMessage: 'No orders in the last 30 days.',
                    items: [
                      for (final e in spend.entries)
                        AdminBreakdownItem(
                          e.key.label,
                          e.value,
                          display: Formatters.pesoWhole(e.value),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ];
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/services/approval_inbox.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../viewmodels/approvals_viewmodel.dart';
import '../widgets/dashboard_approval_tile.dart';
import '../widgets/dashboard_waiting_row.dart';

/// Everything waiting for the signed-in owner or PM, grouped by kind. Each
/// item opens the screen where it is approved.
class ApprovalsPage extends StatelessWidget {
  const ApprovalsPage({super.key, this.initialKind});

  /// Opens the inbox filtered to one kind, e.g. from the dashboard.
  final ApprovalKind? initialKind;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ApprovalsViewModel(
        session: getIt(),
        inbox: getIt(),
        initialKind: initialKind,
      )..load(),
      builder: (context, _) {
        final vm = context.watch<ApprovalsViewModel>();
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (vm.error != null) return AppEmptyState(message: vm.error!);
        if (vm.groups.isEmpty) {
          return const AppEmptyState(
            message: 'Nothing is waiting for your approval.',
            icon: Icons.task_alt,
          );
        }
        return RefreshIndicator(
          onRefresh: vm.load,
          child: ListView(
            padding: pagePadding(context),
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: vm.filter == null,
                    onSelected: (_) => vm.setFilter(null),
                  ),
                  for (final e in vm.groups.entries)
                    ChoiceChip(
                      label: Text('${e.key.label} (${e.value.length})'),
                      selected: vm.filter == e.key,
                      onSelected: (_) => vm.setFilter(e.key),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              for (final e in vm.visibleGroups.entries) ...[
                AppSectionCard(
                  title: '${e.key.label} (${e.value.length})',
                  trailing: Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: Icon(DashboardWaitingRow.iconFor(e.key)),
                  ),
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final item in e.value)
                        DashboardApprovalTile(
                          item: item,
                          onTap: () => context.go(item.route),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ],
          ),
        );
      },
    );
  }
}

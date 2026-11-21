import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_fonts.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/finance_access.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/services/approval_inbox.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_page_header.dart';
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
          return Center(
            child: Padding(
              padding: pagePadding(context),
              child: const AppEmptyState(
                message: 'Nothing is waiting for your approval.',
                icon: Icons.task_alt_rounded,
              ),
            ),
          );
        }

        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        final isDark = theme.brightness == Brightness.dark;
        final totalCount = vm.groups.values.fold<int>(
          0,
          (sum, list) => sum + list.length,
        );
        final totalAmount = vm.groups.values
            .expand((list) => list)
            .fold<double>(0, (sum, item) => sum + (item.amount ?? 0));
        final showFinance = canSeeFinance() && totalAmount > 0;

        return RefreshIndicator(
          onRefresh: vm.load,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: pagePadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              AppPageHeader(
                title: 'Approvals',
                actions: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: AppRadii.mdAll,
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: cs.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$totalCount pending',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                        if (showFinance) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Container(
                              width: 1,
                              height: 14,
                              color: cs.outlineVariant,
                            ),
                          ),
                          Text(
                            Formatters.pesoWhole(totalAmount),
                            style: theme.textTheme.bodySmall
                                ?.merge(AppTextStyles.numeric)
                                .copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? cs.secondary
                                      : cs.onPrimaryContainer,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh approvals',
                    onPressed: vm.load,
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    style: IconButton.styleFrom(
                      backgroundColor: cs.surface,
                      side: BorderSide(color: cs.outlineVariant),
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppRadii.mdAll,
                      ),
                    ),
                  ),
                ],
              ),

              // Filter bar.
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  _FilterTab(
                    label: 'All ($totalCount)',
                    selected: vm.filter == null,
                    onTap: () => vm.setFilter(null),
                  ),
                  for (final e in vm.groups.entries)
                    _FilterTab(
                      icon: DashboardWaitingRow.iconFor(e.key),
                      label: '${e.key.label} (${e.value.length})',
                      selected: vm.filter == e.key,
                      onTap: () => vm.setFilter(e.key),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),

              // Grouped decision ledgers.
              for (final e in vm.visibleGroups.entries) ...[
                _ApprovalGroupPanel(
                  kind: e.key,
                  items: e.value,
                  onSelect: (item) => context.go(item.route),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ],
            ),
          ),
        );
      },
    );
  }
}

class _FilterTab extends StatelessWidget {
  const _FilterTab({
    this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData? icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final selectedFg = isDark ? cs.secondary : cs.onPrimaryContainer;

    return Material(
      color: selected
          ? cs.primary.withValues(alpha: isDark ? 0.18 : 0.13)
          : cs.surface,
      borderRadius: AppRadii.mdAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.mdAll,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: AppRadii.mdAll,
            border: Border.all(
              color: selected
                  ? cs.primary.withValues(alpha: isDark ? 0.55 : 0.45)
                  : cs.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 16,
                  color: selected ? selectedFg : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 7),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppFonts.body,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? cs.onSurface : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ApprovalGroupPanel extends StatelessWidget {
  const _ApprovalGroupPanel({
    required this.kind,
    required this.items,
    required this.onSelect,
  });

  final ApprovalKind kind;
  final List<ApprovalItem> items;
  final ValueChanged<ApprovalItem> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final iconColor = isDark ? cs.secondary : cs.onPrimaryContainer;
    final groupTotal = items.fold<double>(
      0,
      (sum, item) => sum + (item.amount ?? 0),
    );
    final showSubtotal = canSeeFinance() && groupTotal > 0;

    return Material(
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.lgAll,
        side: BorderSide(color: cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: isDark
                  ? cs.surfaceContainer
                  : cs.surfaceContainerLow.withValues(alpha: 0.7),
              border: Border(bottom: BorderSide(color: cs.outlineVariant)),
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: isDark ? 0.2 : 0.13),
                    borderRadius: AppRadii.smAll,
                  ),
                  child: Icon(
                    DashboardWaitingRow.iconFor(kind),
                    size: 16,
                    color: iconColor,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    '${kind.label} (${items.length})',
                    style: TextStyle(
                      fontFamily: AppFonts.display,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                if (showSubtotal)
                  Text(
                    Formatters.pesoWhole(groupTotal),
                    style: theme.textTheme.bodySmall
                        ?.merge(AppTextStyles.numeric)
                        .copyWith(
                          fontWeight: FontWeight.w700,
                          color: cs.onSurfaceVariant,
                        ),
                  ),
              ],
            ),
          ),
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: 20,
                endIndent: 20,
                color: cs.outlineVariant,
              ),
            DashboardApprovalTile(
              item: items[i],
              onTap: () => onSelect(items[i]),
            ),
          ],
        ],
      ),
    );
  }
}

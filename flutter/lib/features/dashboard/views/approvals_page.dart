import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_fonts.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/finance_access.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/services/approval_inbox.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../viewmodels/approvals_viewmodel.dart';
import '../widgets/approval_review_dialog.dart';
import '../widgets/dashboard_approval_tile.dart';
import '../widgets/dashboard_waiting_row.dart';

/// Project Manager / Owner Approvals workbench: inspects and decides every
/// incoming request (to-dos, daily site reports, DUPA material requests,
/// laborer requests, attendance cut-offs, and variation orders) via structured
/// in-place modals without redirecting out to project tabs.
class ApprovalsPage extends StatefulWidget {
  const ApprovalsPage({super.key, this.initialKind});

  /// Opens the inbox pre-filtered to one kind, e.g. from a dashboard tile.
  final ApprovalKind? initialKind;

  @override
  State<ApprovalsPage> createState() => _ApprovalsPageState();
}

class _ApprovalsPageState extends State<ApprovalsPage> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openReviewModal(
    BuildContext context,
    ApprovalsViewModel vm,
    ApprovalItem item,
  ) async {
    final changed = await ApprovalReviewDialog.show(
      context,
      item: item,
      onChanged: () => vm.load(silent: true),
    );
    if (changed && mounted) {
      await vm.load(silent: true);
    }
  }

  Future<void> _handleQuickAction(
    BuildContext context,
    ApprovalsViewModel vm,
    ApprovalItem item,
  ) async {
    if (item.kind == ApprovalKind.todoVerification) {
      final err = await vm.quickVerifyTodo(item);
      if (!context.mounted) return;
      if (err != null) {
        showAppMessage(context, err);
      } else {
        showSuccessAlert(context, 'Task verified.');
      }
      return;
    }
    if (item.kind == ApprovalKind.laborerRequest) {
      final count = item.effectiveIds.length;
      final err = await vm.quickApproveLaborer(item);
      if (!context.mounted) return;
      if (err != null) {
        showAppMessage(context, err);
      } else {
        showSuccessAlert(
          context,
          count > 1
              ? '$count laborers approved and added to project.'
              : 'Laborer approved and added to project.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ApprovalsViewModel(
        session: getIt(),
        inbox: getIt(),
        initialKind: widget.initialKind,
      )..load(),
      builder: (context, _) {
        final vm = context.watch<ApprovalsViewModel>();
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (vm.error != null) {
          return Center(
            child: Padding(
              padding: pagePadding(context),
              child: AppEmptyState(
                message: vm.error!,
                icon: Icons.error_outline_rounded,
                action: FilledButton.icon(
                  onPressed: vm.load,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Retry'),
                ),
              ),
            ),
          );
        }

        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        final isDark = theme.brightness == Brightness.dark;
        final totalCount = vm.totalCount;
        final totalAmount = vm.totalAmount;
        final showFinance = canSeeFinance() && totalAmount > 0;
        final projectOptions = vm.projectOptions;

        return RefreshIndicator(
          onRefresh: vm.load,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: pagePadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Unified top bar: workflow category tabs on the left, live
                // queue summary + refresh on the right (no empty top strip).
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          _FilterTab(
                            label: 'All ($totalCount)',
                            selected: vm.filter == null,
                            hasItems: totalCount > 0,
                            onTap: () => vm.setFilter(null),
                          ),
                          for (final kind in ApprovalKind.values)
                            _FilterTab(
                              icon: DashboardWaitingRow.iconFor(kind),
                              label: '${kind.label} (${vm.countForKind(kind)})',
                              selected: vm.filter == kind,
                              hasItems: vm.countForKind(kind) > 0,
                              onTap: () => vm.setFilter(kind),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _QueueSummaryBadge(
                          totalCount: totalCount,
                          totalAmount: totalAmount,
                          showFinance: showFinance,
                        ),
                        const SizedBox(width: AppSpacing.sm),
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
                  ],
                ),

                if (totalCount > 0 || vm.hasActiveFilters) ...[
                  const SizedBox(height: AppSpacing.md),
                  _FilterToolbar(
                    vm: vm,
                    searchController: _searchController,
                    projectOptions: projectOptions,
                    onClear: () {
                      _searchController.clear();
                      vm.clearFilters();
                    },
                  ),
                ],

                const SizedBox(height: AppSpacing.xl),

                if (totalCount == 0)
                  _EmptyApprovalsLedger(isDark: isDark)
                else if (vm.visibleGroups.isEmpty)
                  _FilteredEmptyLedger(
                    totalCount: totalCount,
                    onReset: () {
                      _searchController.clear();
                      vm.clearFilters();
                    },
                  )
                else
                  for (final e in vm.visibleGroups.entries) ...[
                    _ApprovalGroupPanel(
                      kind: e.key,
                      items: e.value,
                      vm: vm,
                      onSelect: (item) => _openReviewModal(context, vm, item),
                      onQuickAction: (item) =>
                          _handleQuickAction(context, vm, item),
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

class _QueueSummaryBadge extends StatelessWidget {
  const _QueueSummaryBadge({
    required this.totalCount,
    required this.totalAmount,
    required this.showFinance,
  });

  final int totalCount;
  final double totalAmount;
  final bool showFinance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final allClear = totalCount == 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: AppRadii.mdAll,
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: allClear ? AppColors.success : cs.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            allClear ? 'All caught up' : '$totalCount pending',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          if (showFinance) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Container(width: 1, height: 14, color: cs.outlineVariant),
            ),
            Text(
              Formatters.pesoWhole(totalAmount),
              style: theme.textTheme.bodySmall
                  ?.merge(AppTextStyles.numeric)
                  .copyWith(
                    fontWeight: FontWeight.w700,
                    color: isDark ? cs.secondary : AppColors.brandGoldText,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterToolbar extends StatelessWidget {
  const _FilterToolbar({
    required this.vm,
    required this.searchController,
    required this.projectOptions,
    required this.onClear,
  });

  final ApprovalsViewModel vm;
  final TextEditingController searchController;
  final List<({int id, String label})> projectOptions;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 260, maxWidth: 380),
          child: TextField(
            controller: searchController,
            onChanged: vm.setQuery,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search project, request, worker, or task…',
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              suffixIcon: vm.query.isNotEmpty
                  ? IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close_rounded, size: 16),
                      onPressed: () {
                        searchController.clear();
                        vm.setQuery('');
                      },
                    )
                  : null,
            ),
          ),
        ),
        if (projectOptions.length > 1 || vm.projectFilter != null)
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 220, maxWidth: 300),
            child: DropdownButtonFormField<int?>(
              key: ValueKey('approvals-project-${vm.projectFilter}'),
              initialValue: projectOptions.any((p) => p.id == vm.projectFilter)
                  ? vm.projectFilter
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Project',
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('All projects'),
                ),
                for (final p in projectOptions)
                  DropdownMenuItem<int?>(
                    value: p.id,
                    child: Text(p.label, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: vm.setProjectFilter,
            ),
          ),
        if (vm.hasActiveFilters)
          TextButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
            label: const Text('Reset filters'),
          ),
      ],
    );
  }
}

class _FilterTab extends StatelessWidget {
  const _FilterTab({
    this.icon,
    required this.label,
    required this.selected,
    required this.hasItems,
    required this.onTap,
  });

  final IconData? icon;
  final String label;
  final bool selected;
  final bool hasItems;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final selectedFg = isDark ? cs.secondary : AppColors.brandGoldText;
    final mutedFg = hasItems
        ? cs.onSurfaceVariant
        : cs.onSurfaceVariant.withValues(alpha: 0.65);

    return Material(
      color: selected
          ? cs.primary.withValues(alpha: isDark ? 0.18 : 0.14)
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
                  ? cs.primary.withValues(alpha: isDark ? 0.55 : 0.48)
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
                  color: selected ? selectedFg : mutedFg,
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
                    fontWeight: selected
                        ? FontWeight.w700
                        : (hasItems ? FontWeight.w600 : FontWeight.w500),
                    color: selected
                        ? cs.onSurface
                        : (hasItems ? cs.onSurface : mutedFg),
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
    required this.vm,
    required this.onSelect,
    required this.onQuickAction,
  });

  final ApprovalKind kind;
  final List<ApprovalItem> items;
  final ApprovalsViewModel vm;
  final ValueChanged<ApprovalItem> onSelect;
  final ValueChanged<ApprovalItem> onQuickAction;

  static String _descriptionFor(ApprovalKind kind) => switch (kind) {
    ApprovalKind.todoVerification =>
      'Tasks marked complete on site — verify to credit schedule & progress.',
    ApprovalKind.dailyReport =>
      'Submitted field logs — inspect weather, manpower, and photos to approve or return.',
    ApprovalKind.materialRequest =>
      'Site requisitions — inspect DUPA plan balance and fulfill from own store or external store.',
    ApprovalKind.payroll =>
      'Completed attendance cut-offs — verify days worked so Accounting can process pay.',
    ApprovalKind.laborerRequest =>
      'Foreman crew requests — approve to assign workers to the project and attendance sheet.',
    ApprovalKind.variationOrder =>
      'Proposed scope/schedule changes — review DUPA diff and forward to the client.',
  };

  static String? _quickLabelForItem(ApprovalItem item) => switch (item.kind) {
    ApprovalKind.todoVerification => 'Quick verify',
    ApprovalKind.laborerRequest =>
      item.isBulk
          ? 'Approve all (${item.effectiveIds.length})'
          : 'Quick approve',
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final iconColor = isDark ? cs.secondary : AppColors.brandGoldText;
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
              color: isDark ? cs.surfaceContainer : AppColors.tableHeader,
              border: Border(bottom: BorderSide(color: cs.outlineVariant)),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: isDark ? 0.2 : 0.14),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${kind.label} (${items.length})',
                        style: TextStyle(
                          fontFamily: AppFonts.display,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _descriptionFor(kind),
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (showSubtotal)
                  Text(
                    Formatters.pesoWhole(groupTotal),
                    style: theme.textTheme.bodySmall
                        ?.merge(AppTextStyles.numeric)
                        .copyWith(
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
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
            Builder(
              builder: (context) {
                final rowItem = items[i];
                final quickLabel = rowItem.effectiveIds.isNotEmpty
                    ? _quickLabelForItem(rowItem)
                    : null;
                return DashboardApprovalTile(
                  item: rowItem,
                  isBusy: vm.isItemBusy(rowItem),
                  quickActionLabel: quickLabel,
                  onQuickAction: quickLabel != null
                      ? () => onQuickAction(rowItem)
                      : null,
                  onTap: () => onSelect(rowItem),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyApprovalsLedger extends StatelessWidget {
  const _EmptyApprovalsLedger({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: 48,
      ),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: AppRadii.lgAll,
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.successContainer,
              borderRadius: AppRadii.mdAll,
            ),
            child: const Icon(
              Icons.task_alt_rounded,
              size: 28,
              color: AppColors.success,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Nothing is waiting for your approval.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppFonts.display,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Text(
              'Incoming site tasks, daily reports, DUPA material requests, laborer additions, attendance cut-offs, and variation orders appear here and open in a review modal without leaving this page.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilteredEmptyLedger extends StatelessWidget {
  const _FilteredEmptyLedger({
    required this.totalCount,
    required this.onReset,
  });

  final int totalCount;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: 40,
      ),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: AppRadii.lgAll,
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 32,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'No pending items in this view.',
            style: TextStyle(
              fontFamily: AppFonts.display,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'You still have $totalCount pending item${totalCount == 1 ? '' : 's'} in other categories.',
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: onReset,
            icon: const Icon(Icons.layers_clear_outlined, size: 16),
            label: Text('Show all pending ($totalCount)'),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/models/variation_order.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_gantt_chart.dart';
import '../viewmodels/schedule_viewmodel.dart';

/// The Gantt project tab: categories as parent bars, to-dos as children, plus
/// a schedule version switcher (`Original` vs. `Variation Order 1 (+10d)`, ...).
class ScheduleGanttPage extends StatelessWidget {
  const ScheduleGanttPage({super.key, required this.projectId});

  final int projectId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      key: ValueKey(projectId),
      create: (_) => ScheduleViewModel(
        projectId: projectId,
        session: getIt(),
        projects: getIt(),
        schedule: getIt(),
        users: getIt(),
        company: getIt(),
        billing: getIt(),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<ScheduleViewModel>();
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (vm.error != null) return AppEmptyState(message: vm.error!);
        final project = vm.project!;
        final selectedVo = vm.selectedVariationOrder;

        return ListView(
          padding: pagePadding(context),
          children: [
            _ScheduleVersionBar(vm: vm),
            if (selectedVo != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _VoVersionBanner(
                originalEnd: project.targetEndDate,
                revisedEnd: vm.effectiveProjectEnd,
                cumulativeDays: vm.cumulativeVoDays,
                vo: selectedVo,
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            AppGanttChart(
              progress: vm.activeGanttProgress,
              projectStart: vm.effectiveProjectStart,
              projectEnd: vm.effectiveProjectEnd,
              variationOrders: vm.visibleVariationOrders,
              relativeMode: vm.isGanttRelativeMode,
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        );
      },
    );
  }
}

class _ScheduleVersionBar extends StatelessWidget {
  const _ScheduleVersionBar({required this.vm});

  final ScheduleViewModel vm;

  Future<void> _pickStartDate(BuildContext context) async {
    final initial = vm.project?.timelineStartDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      helpText: 'Select actual start date (Notice to Proceed)',
      confirmText: 'Start timeline',
    );
    if (picked == null || !context.mounted) return;
    final err = await vm.startTimeline(picked);
    if (!context.mounted) return;
    if (err == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Actual timeline created starting ${Formatters.date(picked)}.',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final vos = vm.variationOrders;
    final timelineStart = vm.project?.timelineStartDate;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: AppRadii.mdAll,
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.layers_outlined, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'Schedule version:',
            style: theme.textTheme.labelMedium?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    isDense: true,
                    isExpanded: true,
                    value: vm.selectedVersionKey,
                    items: [
                      const DropdownMenuItem<int>(
                        value: ScheduleViewModel.plannedVersionKey,
                        child: Text('Planned (W1, W2, …)'),
                      ),
                      if (timelineStart != null)
                        DropdownMenuItem<int>(
                          value: ScheduleViewModel.actualVersionKey,
                          child: Text(
                            'Actual timeline (${Formatters.date(timelineStart)})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      for (var i = 0; i < vos.length; i++)
                        DropdownMenuItem<int>(
                          value: i,
                          child: Text(
                            vm.voVersionLabel(i),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: vm.selectScheduleVersion,
                  ),
                ),
              ),
            ),
          ),
          if (vm.canEdit) ...[
            const SizedBox(width: AppSpacing.md),
            if (timelineStart == null)
              FilledButton.tonalIcon(
                onPressed: vm.isBusy ? null : () => _pickStartDate(context),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('Start timeline from date'),
              )
            else
              TextButton.icon(
                onPressed: vm.isBusy ? null : () => _pickStartDate(context),
                icon: const Icon(Icons.calendar_today_outlined, size: 16),
                label: const Text('Change start date'),
              ),
          ],
        ],
      ),
    );
  }
}

class _VoVersionBanner extends StatelessWidget {
  const _VoVersionBanner({
    required this.originalEnd,
    required this.revisedEnd,
    required this.cumulativeDays,
    required this.vo,
  });

  final DateTime originalEnd;
  final DateTime revisedEnd;
  final int cumulativeDays;
  final VariationOrder vo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final daysLabel = cumulativeDays > 0
        ? '+$cumulativeDays days'
        : cumulativeDays < 0
        ? '$cumulativeDays days'
        : 'No net day change';
    final taskDates = vo.workStartDate != null && vo.workEndDate != null
        ? ' · Task dates: ${Formatters.dateRange(vo.workStartDate!, vo.workEndDate!)}'
        : '';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer.withValues(alpha: 0.35),
        borderRadius: AppRadii.mdAll,
        border: Border.all(
          color: AppColors.brandGold.withValues(alpha: 0.45),
        ),
      ),
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.difference_outlined,
                size: 16,
                color: AppColors.primary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '${vo.voNo} · ${vo.type.label}',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          Text(
            'Target end: ${Formatters.date(originalEnd)} → ${Formatters.date(revisedEnd)} ($daysLabel)$taskDates',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

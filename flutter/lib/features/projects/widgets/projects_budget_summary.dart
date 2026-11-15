import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/formatters.dart';

/// How much of the contract the category budgets use: a bar with
/// allocated and remaining amounts, red when over.
class ProjectsBudgetSummary extends StatelessWidget {
  const ProjectsBudgetSummary({
    super.key,
    required this.contract,
    required this.allocated,
  });

  final double contract;
  final double allocated;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final over = allocated > contract;
    final share = contract <= 0 ? 0.0 : (allocated / contract).clamp(0.0, 1.0);
    final color = over
        ? AppColors.error
        : share >= 0.999
        ? AppColors.success
        : AppColors.primary;
    Widget figure(String label, String value, {Color? valueColor}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(
          value,
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: const BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: AppRadii.lgAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.xxl,
            runSpacing: AppSpacing.md,
            children: [
              figure('Contract amount', Formatters.peso(contract)),
              figure(
                'Allocated to categories',
                Formatters.peso(allocated),
                valueColor: color,
              ),
              figure(
                over ? 'Over by' : 'Unallocated',
                Formatters.peso((contract - allocated).abs()),
                valueColor: over ? AppColors.error : null,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: AppRadii.pillAll,
            child: LinearProgressIndicator(
              value: over ? 1 : share,
              minHeight: 10,
              color: color,
              backgroundColor: AppColors.border,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            over
                ? 'Category budgets cannot exceed the contract amount.'
                : '${Formatters.percent(share)} of the contract is allocated. '
                      'Budgets set each category\'s weight in progress.',
            style: textTheme.bodySmall?.copyWith(
              color: over ? AppColors.error : null,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_radii.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/di/service_locator.dart';
import '../../core/utils/finance_access.dart';
import '../../core/utils/formatters.dart';
import '../../data/services/session_service.dart';

/// Horizontal budget-vs-actual utilization bar built from plain Flutter
/// widgets, highlighting near-budget (amber) and over-budget (red) spend.
class AppBudgetBar extends StatelessWidget {
  const AppBudgetBar({
    super.key,
    required this.budget,
    required this.actual,
    this.label,
    this.showAmounts = false,
    this.height = 8,
    this.semanticsLabel,
  });

  final double? budget;
  final double actual;
  final String? label;
  final bool showAmounts;
  final double height;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    if (getIt.isRegistered<SessionService>() &&
        getIt<SessionService>().isSignedIn &&
        !canSeeFinance()) {
      return const SizedBox.shrink();
    }

    final textTheme = Theme.of(context).textTheme;
    final hasBudget = budget != null && budget! > 0;

    if (!hasBudget) {
      final mutedTrack = Container(
        height: height,
        decoration: const BoxDecoration(
          color: AppColors.progressTrack,
          borderRadius: AppRadii.pillAll,
        ),
      );
      if (showAmounts) {
        return Semantics(
          label: semanticsLabel ?? label,
          value: 'No budget set',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xxs,
                children: [
                  if (label != null)
                    Text(label!, style: textTheme.labelMedium),
                  Text(
                    'No budget set',
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              mutedTrack,
            ],
          ),
        );
      }
      return Semantics(
        label: semanticsLabel ?? label,
        value: 'No budget set',
        child: Row(
          children: [
            Expanded(child: mutedTrack),
            const SizedBox(width: AppSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 44),
              child: Text(
                '—',
                textAlign: TextAlign.end,
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final ratio = actual / budget!;
    final isOver = actual > budget!;
    final isNear = !isOver && ratio >= 0.85;
    final fillColor = isOver
        ? AppColors.error
        : isNear
        ? AppColors.warning
        : AppColors.progressFill;
    final trackColor = isOver
        ? AppColors.errorContainer
        : AppColors.progressTrack;
    final clamped = ratio.clamp(0.0, 1.0).toDouble();

    final bar = Semantics(
      label: semanticsLabel ?? label,
      value: Formatters.percent(ratio),
      child: ClipRRect(
        borderRadius: AppRadii.pillAll,
        child: Container(
          height: height,
          color: trackColor,
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: clamped,
            heightFactor: 1,
            child: Container(
              decoration: BoxDecoration(
                color: fillColor,
                borderRadius: AppRadii.pillAll,
              ),
            ),
          ),
        ),
      ),
    );

    if (showAmounts) {
      final summary = isOver
          ? 'Over by ${Formatters.pesoWhole(actual - budget!)} · '
                '${Formatters.percent(ratio)}'
          : '${Formatters.pesoWhole(actual)} of '
                '${Formatters.pesoWhole(budget!)} '
                '(${Formatters.percent(ratio)})';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xxs,
            children: [
              if (label != null) Text(label!, style: textTheme.labelMedium),
              Text(
                summary,
                style: textTheme.bodySmall
                    ?.merge(AppTextStyles.numeric)
                    .copyWith(
                      color: isOver
                          ? AppColors.error
                          : isNear
                          ? AppColors.warning
                          : AppColors.textSecondary,
                      fontWeight: isOver ? FontWeight.w600 : FontWeight.w500,
                    ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          bar,
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: bar),
        const SizedBox(width: AppSpacing.sm),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44),
          child: Text(
            Formatters.percent(ratio),
            textAlign: TextAlign.end,
            style: textTheme.bodySmall
                ?.merge(AppTextStyles.numeric)
                .copyWith(
                  color: isOver
                      ? AppColors.error
                      : isNear
                      ? AppColors.warning
                      : AppColors.textSecondary,
                  fontWeight: isOver ? FontWeight.w700 : FontWeight.w500,
                ),
          ),
        ),
      ],
    );
  }
}

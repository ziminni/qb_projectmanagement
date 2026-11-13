import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';

/// One step of the project wizard.
typedef WizardStep = ({String title, String subtitle, IconData icon});

/// The wizard's progress: a vertical list with descriptions on wide
/// screens, a compact row of numbered dots on phones. Finished steps can be
/// tapped to go back.
class ProjectsWizardSteps extends StatelessWidget {
  const ProjectsWizardSteps({
    super.key,
    required this.steps,
    required this.current,
    required this.onTap,
    this.vertical = true,
  });

  final List<WizardStep> steps;
  final int current;
  final ValueChanged<int> onTap;
  final bool vertical;

  Widget _dot(int i) {
    final done = i < current;
    final active = i == current;
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done
            ? AppColors.primary
            : active
            ? AppColors.primaryContainer
            : AppColors.surfaceMuted,
        border: Border.all(
          color: done || active ? AppColors.primary : AppColors.border,
          width: active ? 2 : 1,
        ),
      ),
      child: done
          ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
          : Text(
              '${i + 1}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: active ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    if (!vertical) {
      return Row(
        children: [
          for (final (i, _) in steps.indexed) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 2,
                  color: i <= current ? AppColors.primary : AppColors.border,
                ),
              ),
            InkWell(
              customBorder: const CircleBorder(),
              onTap: i < current ? () => onTap(i) : null,
              child: _dot(i),
            ),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, s) in steps.indexed)
          InkWell(
            borderRadius: AppRadii.mdAll,
            onTap: i < current ? () => onTap(i) : null,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                borderRadius: AppRadii.mdAll,
                color: i == current ? AppColors.primaryContainer : null,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _dot(i),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.title,
                          style: textTheme.titleSmall?.copyWith(
                            color: i > current
                                ? AppColors.textSecondary
                                : AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(s.subtitle, style: textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

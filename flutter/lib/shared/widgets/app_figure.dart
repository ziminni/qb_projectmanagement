import 'package:flutter/material.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_text_styles.dart';

/// A labelled figure with an optional one-line context, e.g. contract amount
/// or earned value.
class AppFigure extends StatelessWidget {
  const AppFigure({
    super.key,
    required this.label,
    required this.value,
    this.detail,
    this.valueColor,
  });

  final String label;
  final String value;
  final String? detail;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: textTheme.labelMedium),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          value,
          style:
              (textTheme.titleLarge ?? const TextStyle(fontSize: 18))
                  .merge(AppTextStyles.numeric)
                  .copyWith(fontWeight: FontWeight.w700, color: valueColor),
        ),
        if (detail != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(detail!, style: textTheme.bodySmall),
        ],
      ],
    );
  }
}

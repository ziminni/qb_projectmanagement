import 'package:flutter/material.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_text_styles.dart';

/// A labelled figure, e.g. contract amount or earned value.
class AppFigure extends StatelessWidget {
  const AppFigure({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: textTheme.labelMedium),
        const SizedBox(height: AppSpacing.xxs),
        Text(value, style: textTheme.titleMedium?.merge(AppTextStyles.numeric)),
      ],
    );
  }
}

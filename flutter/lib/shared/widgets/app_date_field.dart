import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/formatters.dart';

/// Tappable date field that opens a date picker through [onTap].
class AppDateField extends StatelessWidget {
  const AppDateField({
    super.key,
    required this.label,
    required this.value,
    required this.hasError,
    required this.onTap,
  });

  final String label;
  final DateTime? value;
  final bool hasError;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.event_outlined),
          suffixIcon: const Icon(Icons.expand_more_rounded),
          errorText: hasError ? '' : null,
          errorStyle: const TextStyle(height: 0, fontSize: 0),
        ),
        child: Text(
          value == null ? 'Choose' : Formatters.date(value!),
          style: value == null
              ? const TextStyle(color: AppColors.textDisabled)
              : null,
        ),
      ),
    );
  }
}

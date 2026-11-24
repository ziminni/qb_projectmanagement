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
    this.enabled = true,
    this.helperText,
  });

  final String label;
  final DateTime? value;
  final bool hasError;
  final VoidCallback? onTap;
  final bool enabled;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          enabled: enabled,
          filled: !enabled,
          fillColor: !enabled ? AppColors.surfaceMuted : null,
          helperText: helperText,
          prefixIcon: const Icon(Icons.event_outlined),
          suffixIcon: enabled
              ? const Icon(Icons.expand_more_rounded)
              : const Icon(
                  Icons.lock_outline_rounded,
                  size: 16,
                  color: AppColors.textDisabled,
                ),
          errorText: hasError ? '' : null,
          errorStyle: const TextStyle(height: 0, fontSize: 0),
        ),
        child: Text(
          value == null
              ? (enabled ? 'Choose' : 'Auto-filled')
              : Formatters.date(value!),
          style: (!enabled || value == null)
              ? const TextStyle(color: AppColors.textDisabled)
              : null,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../data/models/attendance.dart';
import '../viewmodels/attendance_viewmodel.dart';

/// One worker on the attendance sheet: Present (with hours input) or Absent.
class LaborAttendanceRow extends StatelessWidget {
  const LaborAttendanceRow({
    super.key,
    required this.row,
    required this.enabled,
    required this.onChanged,
  });

  final AttendanceRow row;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final uiStatus = row.uiStatus;
    final isPresent = uiStatus == AttendanceStatus.present;
    final (fg, bg) = switch (uiStatus) {
      AttendanceStatus.present => (
        AppColors.success,
        AppColors.successContainer,
      ),
      AttendanceStatus.absent => (AppColors.error, AppColors.errorContainer),
      _ => (AppColors.textSecondary, AppColors.surfaceMuted),
    };
    final initials = row.worker.fullName
        .split(' ')
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0])
        .join();

    final subtitleText = switch (uiStatus) {
      null => '${row.worker.trade} · not marked yet',
      AttendanceStatus.absent => '${row.worker.trade} · Absent',
      _ =>
        '${row.worker.trade} · Present (${InputParsers.amountText(row.hoursWorked)}h)',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: bg,
                child: Text(
                  initials,
                  style: textTheme.labelLarge?.copyWith(color: fg),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.worker.fullName, style: textTheme.titleSmall),
                    Text(
                      subtitleText,
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (isPresent) ...[
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: 112,
                  child: TextFormField(
                    key: ValueKey('hours-${row.worker.id}-$isPresent'),
                    initialValue: InputParsers.amountText(row.hoursWorked),
                    enabled: enabled,
                    textAlign: TextAlign.end,
                    decoration: const InputDecoration(
                      labelText: 'Hours',
                      suffixText: 'h',
                      isDense: true,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (v) {
                      final hrs = InputParsers.amount(v);
                      if (hrs == null || hrs <= 0 || hrs > 24) {
                        return '1–24 hrs';
                      }
                      return null;
                    },
                    onChanged: (v) {
                      row.hoursWorked = InputParsers.amount(v) ?? 0;
                      onChanged();
                    },
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SegmentedButton<AttendanceStatus>(
            emptySelectionAllowed: true,
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: AttendanceStatus.present,
                icon: Icon(Icons.check_circle_outline, size: 16),
                label: Text('Present'),
              ),
              ButtonSegment(
                value: AttendanceStatus.absent,
                icon: Icon(Icons.cancel_outlined, size: 16),
                label: Text('Absent'),
              ),
            ],
            selected: {?uiStatus},
            onSelectionChanged: enabled
                ? (s) {
                    row.setStatus(s.isEmpty ? null : s.first);
                    onChanged();
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

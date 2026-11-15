import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../data/models/attendance.dart';
import '../../../data/services/labor_rules.dart';
import '../viewmodels/attendance_viewmodel.dart';

/// One worker on the attendance sheet: who, status and overtime hours.
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
    final (fg, bg) = switch (row.status) {
      AttendanceStatus.present => (
        AppColors.success,
        AppColors.successContainer,
      ),
      AttendanceStatus.halfDay => (
        AppColors.warning,
        AppColors.warningContainer,
      ),
      AttendanceStatus.absent => (AppColors.error, AppColors.errorContainer),
      null => (AppColors.textSecondary, AppColors.surfaceMuted),
    };
    final initials = row.worker.fullName
        .split(' ')
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0])
        .join();
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
                      row.status == null
                          ? '${row.worker.trade} · not marked yet'
                          : '${row.worker.trade} · ${row.status!.label}',
                      style: textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 96,
                child: TextFormField(
                  key: ValueKey('ot-${row.worker.id}-${row.status}'),
                  initialValue: InputParsers.amountText(row.overtimeHours),
                  enabled: enabled && row.status != AttendanceStatus.absent,
                  textAlign: TextAlign.end,
                  decoration: const InputDecoration(
                    labelText: 'OT hrs',
                    isDense: true,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (v) =>
                      LaborRules.validateOvertime(InputParsers.amount(v) ?? 0),
                  onChanged: (v) =>
                      row.overtimeHours = InputParsers.amount(v) ?? 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SegmentedButton<AttendanceStatus>(
            emptySelectionAllowed: true,
            showSelectedIcon: false,
            segments: [
              for (final s in AttendanceStatus.values)
                ButtonSegment(value: s, label: Text(s.label)),
            ],
            selected: {?row.status},
            onSelectionChanged: enabled
                ? (s) {
                    row.status = s.isEmpty ? null : s.first;
                    onChanged();
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

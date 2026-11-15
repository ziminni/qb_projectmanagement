import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/app_info_row.dart';
import '../../../shared/widgets/app_location_map.dart';

/// Wizard step 4: everything entered, with a way back to each step, and
/// what happens when the request is sent.
class ProjectsReviewStep extends StatelessWidget {
  const ProjectsReviewStep({
    super.key,
    required this.isNew,
    required this.code,
    required this.name,
    required this.clientName,
    required this.siteEngineerName,
    required this.start,
    required this.end,
    required this.location,
    required this.pin,
    required this.contract,
    required this.downPaymentPct,
    required this.retentionPct,
    required this.categories,
    required this.onEdit,
  });

  final bool isNew;
  final String code;
  final String name;
  final String clientName;
  final String? siteEngineerName;
  final DateTime start;
  final DateTime end;
  final String location;
  final LatLng? pin;
  final double contract;
  final double downPaymentPct;
  final double retentionPct;
  final List<(String, double)> categories;
  final ValueChanged<int> onEdit;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    Widget section(String title, int step, List<Widget> children) => Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        borderRadius: AppRadii.lgAll,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: textTheme.titleSmall)),
              TextButton.icon(
                onPressed: () => onEdit(step),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit'),
              ),
            ],
          ),
          ...children,
        ],
      ),
    );
    final allocated = categories.fold(0.0, (s, c) => s + c.$2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        section('Project details', 0, [
          AppInfoRow(label: 'Code', value: code.trim().toUpperCase()),
          AppInfoRow(label: 'Name', value: name.trim()),
          AppInfoRow(label: 'Client', value: clientName),
          if (siteEngineerName != null)
            AppInfoRow(label: 'Site engineer', value: siteEngineerName!),
          AppInfoRow(
            label: 'Schedule',
            value:
                '${Formatters.dateRange(start, end)} · '
                '${end.difference(start).inDays} days',
          ),
        ]),
        const SizedBox(height: AppSpacing.lg),
        section('Site location', 1, [
          AppInfoRow(label: 'Location', value: location.trim()),
          if (pin != null) ...[
            const SizedBox(height: AppSpacing.sm),
            IgnorePointer(child: AppLocationMap(pin: pin, height: 180)),
          ] else
            const AppInfoRow(label: 'Map pin', value: 'Not placed'),
        ]),
        const SizedBox(height: AppSpacing.lg),
        section('Budget', 2, [
          AppInfoRow(
            label: 'Contract amount',
            value: Formatters.peso(contract),
          ),
          AppInfoRow(
            label: 'Down payment',
            value: '${downPaymentPct.toStringAsFixed(0)}%',
          ),
          AppInfoRow(
            label: 'Retention',
            value: '${retentionPct.toStringAsFixed(0)}%',
          ),
          if (isNew) ...[
            const Divider(height: AppSpacing.xl),
            if (categories.isEmpty)
              const AppInfoRow(label: 'Categories', value: 'None yet')
            else ...[
              for (final (n, a) in categories)
                AppInfoRow(label: n, value: Formatters.peso(a)),
              AppInfoRow(
                label: 'Allocated',
                value:
                    '${Formatters.peso(allocated)} of '
                    '${Formatters.peso(contract)}',
              ),
            ],
          ],
        ]),
        if (isNew) ...[
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: const BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: AppRadii.lgAll,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.send_rounded, color: AppColors.primary),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('What happens next', style: textTheme.titleSmall),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '1. $clientName gets the project request and can '
                        'accept, ask for changes or decline.\n'
                        '2. Once they accept, ${siteEngineerName ?? 'the site engineer'} '
                        'gets it.\n'
                        '3. When both accept, you can start the project.',
                        style: textTheme.bodyMedium?.copyWith(height: 1.6),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

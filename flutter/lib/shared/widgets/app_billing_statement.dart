import 'package:flutter/material.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/client.dart';
import '../../data/models/company.dart';
import '../../data/models/progress_billing.dart';
import '../../data/models/project.dart';

/// Progress billing statement laid out like a BIR-friendly billing document:
/// contractor and client details, then amount earned − previous billings −
/// down payment recoupment − retention = net amount due.
class AppBillingStatement extends StatelessWidget {
  const AppBillingStatement({
    super.key,
    required this.billing,
    required this.project,
    this.company,
    this.client,
  });

  final ProgressBilling billing;
  final Project project;
  final Company? company;
  final Client? client;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final b = billing;
    Widget line(
      String label,
      double amount, {
      bool bold = false,
      bool less = false,
    }) => Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: bold ? textTheme.titleSmall : textTheme.bodyMedium,
            ),
          ),
          Text(
            '${less ? '(' : ''}${Formatters.peso(amount)}${less ? ')' : ''}',
            style: (bold ? textTheme.titleSmall : textTheme.bodyMedium)
                ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (company != null) ...[
              Text(company!.name, style: textTheme.titleMedium),
              Text(company!.address, style: textTheme.bodySmall),
              Text(
                'TIN ${company!.tin} · ${company!.pcabLicenseNo}',
                style: textTheme.bodySmall,
              ),
              const Divider(height: AppSpacing.xl),
            ],
            Text(
              'PROGRESS BILLING NO. ${b.billingNo}',
              style: textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text('Project: ${project.code} · ${project.name}'),
            Text('Location: ${project.location}'),
            if (client != null) Text('Billed to: ${client!.name}'),
            Text('Period ending: ${Formatters.date(b.periodEnd)}'),
            const Divider(height: AppSpacing.xl),
            line('Contract amount', project.contractAmount),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  const Expanded(child: Text('Accomplishment to date')),
                  Text(
                    '${(b.pctAccomplished * 100).toStringAsFixed(2)}%',
                    style: textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const Divider(),
            line('Gross amount earned to date', b.grossEarned),
            line('Less: previous billings', b.lessPrevious, less: true),
            line('Amount earned this period', b.thisPeriod, bold: true),
            line(
              'Less: down payment recoupment (${project.downPaymentPct.toStringAsFixed(0)}%)',
              b.lessDpRecoupment,
              less: true,
            ),
            line(
              'Less: retention (${project.retentionPct.toStringAsFixed(0)}%)',
              b.lessRetention,
              less: true,
            ),
            const Divider(),
            line('NET AMOUNT DUE', b.netDue, bold: true),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Amounts are VAT-inclusive as contracted. Accomplishment counts '
              'only work verified on or before the period end.',
              style: textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

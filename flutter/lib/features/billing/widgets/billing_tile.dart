import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../../../data/models/progress_billing.dart';
import '../../../shared/widgets/app_billing_status_chip.dart';

class BillingTile extends StatelessWidget {
  const BillingTile({
    super.key,
    required this.billing,
    required this.projectCode,
    required this.onTap,
  });

  final ProgressBilling billing;
  final String projectCode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = billing;
    return ListTile(
      onTap: onTap,
      leading: const Icon(Icons.receipt_long_outlined),
      title: Text('Billing #${b.billingNo} · $projectCode'),
      subtitle: Text(
        'Period ending ${Formatters.date(b.periodEnd)} · '
        '${(b.pctAccomplished * 100).round()}% · net ${Formatters.peso(b.netDue)}',
      ),
      trailing: AppBillingStatusChip(status: b.status),
    );
  }
}

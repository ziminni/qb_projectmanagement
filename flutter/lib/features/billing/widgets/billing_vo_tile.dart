import 'package:flutter/material.dart';

import '../../../core/utils/finance_access.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/variation_order.dart';
import '../../../shared/widgets/app_vo_status_chip.dart';

class BillingVoTile extends StatelessWidget {
  const BillingVoTile({
    super.key,
    required this.vo,
    required this.projectCode,
    required this.onTap,
  });

  final VariationOrder vo;
  final String projectCode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: const Icon(Icons.difference_outlined),
      title: Text('${vo.voNo} · $projectCode · ${vo.type.label}'),
      subtitle: Text(
        '${vo.description}\n'
        '${canSeeFinance() ? '${vo.amount >= 0 ? '+' : '−'}${Formatters.peso(vo.amount.abs())} · ' : ''}'
        '${vo.daysImpact} day(s)',
      ),
      isThreeLine: true,
      trailing: AppVoStatusChip(status: vo.status),
    );
  }
}

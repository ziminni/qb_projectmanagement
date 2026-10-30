import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/services/procurement_rules.dart';
import '../../../shared/widgets/app_info_row.dart';
import '../../../shared/widgets/app_section_card.dart';

/// The request's estimated cost against the category's remaining budget.
class ProcurementBudgetCard extends StatelessWidget {
  const ProcurementBudgetCard({super.key, required this.check});

  final BudgetCheck check;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      title: 'Budget check',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppInfoRow(
            label: 'This request (est.)',
            value: Formatters.peso(check.requestCost),
          ),
          if (check.budget == null)
            const AppInfoRow(
              label: 'Category budget',
              value: 'Not set; no budget check',
            )
          else ...[
            AppInfoRow(
              label: 'Category budget',
              value: Formatters.peso(check.budget!),
            ),
            AppInfoRow(
              label: 'Already committed',
              value: Formatters.peso(check.committed),
            ),
            AppInfoRow(
              label: 'Remaining',
              value: Formatters.peso(check.remaining!),
            ),
          ],
          if (check.exceedsBudget)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(12),
              color: AppColors.warningContainer,
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: AppColors.warning),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This exceeds the remaining category budget. Check it '
                      'before approving.',
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../data/models/planned_material.dart';
import '../../../data/services/category_catalog_service.dart';
import '../../../data/services/project_rules.dart';
import 'projects_budget_summary.dart';

/// One budget category typed into the wizard before the project exists.
class ProjectsCategoryDraft {
  ProjectsCategoryDraft([String name = ''])
    : name = TextEditingController(text: name);

  final TextEditingController name;
  final amount = TextEditingController();

  double get value => InputParsers.amount(amount.text) ?? 0;

  void dispose() {
    name.dispose();
    amount.dispose();
  }
}

/// Wizard step 3: contract terms and, for a new project, the budget split
/// into categories (which weight progress).
class ProjectsBudgetStep extends StatelessWidget {
  const ProjectsBudgetStep({
    super.key,
    required this.contract,
    required this.downPayment,
    required this.retention,
    required this.contractLocked,
    required this.categories,
    this.barChartPreview,
    required this.onAddCategory,
    required this.onRemoveCategory,
    required this.onChanged,
  });

  final TextEditingController contract;
  final TextEditingController downPayment;
  final TextEditingController retention;
  final bool contractLocked;

  /// Null when editing: categories are then managed on the schedule tab.
  final List<ProjectsCategoryDraft>? categories;
  final ItemsExcelPreview? barChartPreview;
  final ValueChanged<String> onAddCategory;
  final ValueChanged<int> onRemoveCategory;
  final VoidCallback onChanged;

  static const suggestions = [
    'Site preparation',
    'Foundation',
    'Structural',
    'Masonry',
    'Roofing',
    'Electrical',
    'Plumbing',
    'Finishing',
  ];

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final contractValue = InputParsers.amount(contract.text) ?? 0;
    const gap = SizedBox(width: AppSpacing.lg, height: AppSpacing.lg);
    Widget percent(TextEditingController c, String label) => TextFormField(
      controller: c,
      decoration: InputDecoration(labelText: label, suffixText: '%'),
      keyboardType: TextInputType.number,
      validator: (v) => ProjectRules.validatePercent(
        InputParsers.amount(v),
        label.toLowerCase(),
      ),
    );
    final cats = categories;
    final used = {for (final c in cats ?? const []) c.name.text.trim()};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Contract terms', style: textTheme.titleSmall),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (context, c) {
            final amount = TextFormField(
              controller: contract,
              enabled: !contractLocked,
              decoration: InputDecoration(
                labelText: 'Contract amount',
                prefixText: '₱ ',
                helperText: contractLocked
                    ? 'Changes only through approved variation orders.'
                    : null,
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => onChanged(),
              validator: (v) =>
                  ProjectRules.validateContractAmount(InputParsers.amount(v)),
            );
            final dp = percent(downPayment, 'Down payment');
            final ret = percent(retention, 'Retention');
            return c.maxWidth < 560
                ? Column(children: [amount, gap, dp, gap, ret])
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 2, child: amount),
                      gap,
                      Expanded(child: dp),
                      gap,
                      Expanded(child: ret),
                    ],
                  );
          },
        ),
        const SizedBox(height: AppSpacing.xl),
        const Divider(),
        const SizedBox(height: AppSpacing.xl),
        if (barChartPreview != null && barChartPreview!.items.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: const BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: AppRadii.mdAll,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.table_chart_outlined,
                  color: AppColors.primary,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${barChartPreview!.items.length} Items of Work ready from Bar Chart'
                        '${barChartPreview!.sheet != null ? ' (${barChartPreview!.sheet})' : ''}',
                        style: textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        barChartPreview!.totalBudget != null
                            ? 'Total planned cost ${Formatters.peso(barChartPreview!.totalBudget!)} '
                                  'was auto-filled into Contract amount above (editable). '
                                  'All items and their Gantt bars will be created automatically.'
                            : 'All items and their Gantt bars will be created automatically.',
                        style: textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        else if (cats == null)
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: const BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: AppRadii.mdAll,
            ),
            child: Text(
              'Category budgets are managed on the project\'s Categories and '
              'to-dos tab.',
              style: textTheme.bodyMedium,
            ),
          )
        else ...[
          Text('Budget categories', style: textTheme.titleSmall),
          const SizedBox(height: 2),
          Text(
            'Split the contract into parts of the work. You can add to-dos '
            'and change budgets later.',
            style: textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          for (final (i, d) in cats.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: d.name,
                      decoration: InputDecoration(
                        labelText: 'Category ${i + 1}',
                      ),
                      onChanged: (_) => onChanged(),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Name the category.'
                          : null,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: d.amount,
                      decoration: const InputDecoration(
                        labelText: 'Budget',
                        prefixText: '₱ ',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => onChanged(),
                      validator: (v) {
                        final a = InputParsers.amount(v);
                        if (v != null && v.trim().isNotEmpty && a == null) {
                          return 'Enter an amount.';
                        }
                        return (a ?? 0) < 0 ? 'Cannot be negative.' : null;
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove category',
                    padding: const EdgeInsets.only(top: 12),
                    onPressed: () => onRemoveCategory(i),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
            ),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () => onAddCategory(''),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add category'),
              ),
              for (final s
                  in (getIt.isRegistered<CategoryCatalogService>()
                      ? getIt<CategoryCatalogService>().suggestions
                      : suggestions))
                if (!used.contains(s))
                  ActionChip(
                    avatar: const Icon(Icons.add_rounded, size: 16),
                    label: Text(s),
                    onPressed: () => onAddCategory(s),
                  ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          ProjectsBudgetSummary(
            contract: contractValue,
            allocated: cats.fold(0.0, (s, d) => s + d.value),
          ),
        ],
      ],
    );
  }
}

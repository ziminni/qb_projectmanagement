import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../data/models/material_item.dart';
import '../../../data/services/procurement_rules.dart';
import '../viewmodels/line_draft.dart';

/// One typed line: name, quantity, unit (unless hidden) and, when
/// [showPrice], unit price.
/// With [suggestions], typing offers price-list names; picking one fills
/// the unit and links the line to that material. [fixedName] shows the name
/// as text, for lines picked from the store catalog.
class ProcurementLineEditor extends StatelessWidget {
  const ProcurementLineEditor({
    super.key,
    required this.line,
    required this.nameLabel,
    required this.onChanged,
    required this.onRemove,
    this.showPrice = false,
    this.showUnit = true,
    this.fixedName = false,
    this.suggestions = const [],
  });

  final LineDraft line;
  final String nameLabel;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  final bool showPrice;
  final bool showUnit;
  final bool fixedName;
  final List<MaterialItem> suggestions;

  @override
  Widget build(BuildContext context) {
    final name = fixedName
        ? Text(line.description, style: Theme.of(context).textTheme.titleSmall)
        : suggestions.isEmpty
        ? TextFormField(
            initialValue: line.description,
            decoration: InputDecoration(labelText: nameLabel),
            validator: (v) => ProcurementRules.validateRequired(v, 'item'),
            onChanged: (v) {
              line.description = v;
              onChanged();
            },
          )
        : _SuggestingField(
            line: line,
            label: nameLabel,
            suggestions: suggestions,
            onChanged: onChanged,
          );
    final numbers = [
      Expanded(
        child: TextFormField(
          initialValue: InputParsers.amountText(line.quantity),
          decoration: const InputDecoration(labelText: 'Qty'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (v) =>
              ProcurementRules.validateQuantity(InputParsers.amount(v)),
          onChanged: (v) {
            line.quantity = InputParsers.amount(v) ?? 0;
            onChanged();
          },
        ),
      ),
      if (showUnit) ...[
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: fixedName
              ? InputDecorator(
                  decoration: const InputDecoration(labelText: 'Unit'),
                  child: Text(line.unit),
                )
              : TextFormField(
                  key: ValueKey('unit-${line.materialId}'),
                  initialValue: line.unit,
                  decoration: const InputDecoration(
                    labelText: 'Unit',
                    hintText: 'bag, pc, cu.m',
                  ),
                  onChanged: (v) => line.unit = v,
                ),
        ),
      ],
      if (showPrice) ...[
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: TextFormField(
            initialValue: line.priceHidden
                ? ''
                : InputParsers.amountText(line.unitPrice),
            decoration: const InputDecoration(
              labelText: 'Unit price',
              prefixText: '₱',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (v) =>
                ProcurementRules.validateUnitPrice(InputParsers.amount(v)),
            onChanged: (v) {
              line.unitPrice = InputParsers.amount(v) ?? 0;
              onChanged();
            },
          ),
        ),
      ],
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: name),
              IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: onRemove,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(children: numbers),
          if (showPrice && line.amount > 0)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  Formatters.peso(line.amount),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SuggestingField extends StatelessWidget {
  const _SuggestingField({
    required this.line,
    required this.label,
    required this.suggestions,
    required this.onChanged,
  });

  final LineDraft line;
  final String label;
  final List<MaterialItem> suggestions;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Autocomplete<MaterialItem>(
      initialValue: TextEditingValue(text: line.description),
      displayStringForOption: (m) => m.name,
      optionsBuilder: (value) {
        final q = value.text.trim().toLowerCase();
        if (q.isEmpty) return const [];
        return suggestions.where((m) => m.name.toLowerCase().contains(q));
      },
      onSelected: (m) {
        line
          ..description = m.name
          ..unit = m.unit
          ..materialId = m.id;
        onChanged();
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmit) =>
          TextFormField(
            controller: controller,
            focusNode: focusNode,
            decoration: InputDecoration(
              labelText: label,
              helperText: line.materialId != null ? 'On the price list' : null,
            ),
            validator: (v) => ProcurementRules.validateRequired(v, 'item'),
            onChanged: (v) {
              line
                ..description = v
                ..materialId = null;
              onChanged();
            },
          ),
    );
  }
}

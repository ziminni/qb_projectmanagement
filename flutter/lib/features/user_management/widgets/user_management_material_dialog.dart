import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../data/models/material_item.dart';
import '../../../data/services/master_data_rules.dart';

/// Add or edit a material and its default unit cost.
class UserManagementMaterialDialog extends StatefulWidget {
  const UserManagementMaterialDialog({super.key, this.initial});

  final MaterialItem? initial;

  static Future<MaterialItem?> show(
    BuildContext context, {
    MaterialItem? initial,
  }) => showDialog<MaterialItem>(
    context: context,
    builder: (_) => UserManagementMaterialDialog(initial: initial),
  );

  @override
  State<UserManagementMaterialDialog> createState() =>
      _UserManagementMaterialDialogState();
}

class _UserManagementMaterialDialogState
    extends State<UserManagementMaterialDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name);
  late final _unit = TextEditingController(text: widget.initial?.unit);
  late final _cost = TextEditingController(
    text: InputParsers.amountText(widget.initial?.defaultUnitCost),
  );
  late final _sku = TextEditingController(text: widget.initial?.storeSku);

  @override
  void dispose() {
    for (final c in [_name, _unit, _cost, _sku]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final base =
        widget.initial ??
        const MaterialItem(id: 0, name: '', unit: '', defaultUnitCost: 0);
    Navigator.of(context).pop(
      base.copyWith(
        name: _name.text.trim(),
        unit: _unit.text.trim(),
        defaultUnitCost: InputParsers.amount(_cost.text),
        storeSku: () => InputParsers.optional(_sku.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Add material' : 'Edit material'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) => MasterDataRules.required(v, 'material name'),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _unit,
                      decoration: const InputDecoration(
                        labelText: 'Unit',
                        hintText: 'bag, pc, cu.m',
                      ),
                      validator: (v) => MasterDataRules.required(v, 'unit'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: TextFormField(
                      controller: _cost,
                      decoration: const InputDecoration(
                        labelText: 'Unit cost',
                        prefixText: '₱ ',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (v) => MasterDataRules.validateAmount(
                        InputParsers.amount(v),
                        'unit cost',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _sku,
                decoration: const InputDecoration(
                  labelText: 'Store SKU (optional)',
                  helperText: 'For the future hardware store link.',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

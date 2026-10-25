import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../data/models/equipment.dart';
import '../../../data/services/master_data_rules.dart';

class UserManagementEquipmentDialog extends StatefulWidget {
  const UserManagementEquipmentDialog({super.key, this.initial});

  final Equipment? initial;

  static Future<Equipment?> show(BuildContext context, {Equipment? initial}) =>
      showDialog<Equipment>(
        context: context,
        builder: (_) => UserManagementEquipmentDialog(initial: initial),
      );

  @override
  State<UserManagementEquipmentDialog> createState() =>
      _UserManagementEquipmentDialogState();
}

class _UserManagementEquipmentDialogState
    extends State<UserManagementEquipmentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name);
  late final _rate = TextEditingController(
    text: InputParsers.amountText(widget.initial?.rate),
  );
  late EquipmentOwnership _ownership =
      widget.initial?.ownership ?? EquipmentOwnership.owned;
  late RateUnit _unit = widget.initial?.rateUnit ?? RateUnit.day;

  @override
  void dispose() {
    _name.dispose();
    _rate.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      Equipment(
        id: widget.initial?.id ?? 0,
        name: _name.text.trim(),
        ownership: _ownership,
        rate: InputParsers.amount(_rate.text)!,
        rateUnit: _unit,
        createdAt: widget.initial?.createdAt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Add equipment' : 'Edit equipment'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) => MasterDataRules.required(v, 'equipment name'),
              ),
              const SizedBox(height: AppSpacing.md),
              SegmentedButton<EquipmentOwnership>(
                segments: [
                  for (final o in EquipmentOwnership.values)
                    ButtonSegment(value: o, label: Text(o.label)),
                ],
                selected: {_ownership},
                onSelectionChanged: (s) => setState(() => _ownership = s.first),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _rate,
                      decoration: const InputDecoration(
                        labelText: 'Rate',
                        prefixText: '₱ ',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (v) => MasterDataRules.validateAmount(
                        InputParsers.amount(v),
                        'rate',
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: DropdownButtonFormField<RateUnit>(
                      initialValue: _unit,
                      decoration: const InputDecoration(labelText: 'Unit'),
                      items: [
                        for (final u in RateUnit.values)
                          DropdownMenuItem(value: u, child: Text(u.label)),
                      ],
                      onChanged: (u) => setState(() => _unit = u!),
                    ),
                  ),
                ],
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

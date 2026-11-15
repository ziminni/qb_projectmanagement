import 'package:flutter/material.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/utils/input_parsers.dart';
import '../../data/models/supplier.dart';
import '../../data/services/master_data_rules.dart';

/// Add or edit a supplier. Used by the admin master lists and by the owner.
class AppSupplierFormDialog extends StatefulWidget {
  const AppSupplierFormDialog({super.key, this.initial});

  final Supplier? initial;

  static Future<Supplier?> show(BuildContext context, {Supplier? initial}) =>
      showDialog<Supplier>(
        context: context,
        builder: (_) => AppSupplierFormDialog(initial: initial),
      );

  @override
  State<AppSupplierFormDialog> createState() => _AppSupplierFormDialogState();
}

class _AppSupplierFormDialogState extends State<AppSupplierFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name);
  late final _contact = TextEditingController(
    text: widget.initial?.contactPerson,
  );
  late final _phone = TextEditingController(text: widget.initial?.phone);
  late final _address = TextEditingController(text: widget.initial?.address);
  late bool _ownStore = widget.initial?.isOwnStore ?? false;

  @override
  void dispose() {
    for (final c in [_name, _contact, _phone, _address]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final base = widget.initial ?? const Supplier(id: 0, name: '');
    Navigator.of(context).pop(
      base.copyWith(
        name: _name.text.trim(),
        contactPerson: () => InputParsers.optional(_contact.text),
        phone: () => InputParsers.optional(_phone.text),
        address: () => InputParsers.optional(_address.text),
        isOwnStore: _ownStore,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Add supplier' : 'Edit supplier'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (v) =>
                      MasterDataRules.required(v, 'supplier name'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _contact,
                  decoration: const InputDecoration(
                    labelText: 'Contact person',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _phone,
                  decoration: const InputDecoration(labelText: 'Phone'),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _address,
                  decoration: const InputDecoration(labelText: 'Address'),
                ),
                const SizedBox(height: AppSpacing.sm),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Own hardware store'),
                  subtitle: const Text(
                    'Orders from this supplier are tagged Own store.',
                  ),
                  value: _ownStore,
                  onChanged: (v) => setState(() => _ownStore = v),
                ),
              ],
            ),
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

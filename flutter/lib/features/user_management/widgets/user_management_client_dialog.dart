import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../data/models/client.dart';
import '../../../data/services/master_data_rules.dart';

class UserManagementClientDialog extends StatefulWidget {
  const UserManagementClientDialog({super.key, this.initial});

  final Client? initial;

  static Future<Client?> show(BuildContext context, {Client? initial}) =>
      showDialog<Client>(
        context: context,
        builder: (_) => UserManagementClientDialog(initial: initial),
      );

  @override
  State<UserManagementClientDialog> createState() =>
      _UserManagementClientDialogState();
}

class _UserManagementClientDialogState
    extends State<UserManagementClientDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name);
  late final _contact = TextEditingController(
    text: widget.initial?.contactPerson,
  );
  late final _email = TextEditingController(text: widget.initial?.email);
  late final _phone = TextEditingController(text: widget.initial?.phone);
  late final _address = TextEditingController(text: widget.initial?.address);

  @override
  void dispose() {
    for (final c in [_name, _contact, _email, _phone, _address]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final base = widget.initial ?? const Client(id: 0, name: '');
    Navigator.of(context).pop(
      base.copyWith(
        name: _name.text.trim(),
        contactPerson: () => InputParsers.optional(_contact.text),
        email: () => InputParsers.optional(_email.text),
        phone: () => InputParsers.optional(_phone.text),
        address: () => InputParsers.optional(_address.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Add client' : 'Edit client'),
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
                  decoration: const InputDecoration(
                    labelText: 'Client name',
                    hintText: 'Person or company',
                  ),
                  validator: (v) => MasterDataRules.required(v, 'client name'),
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
                  controller: _email,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                  validator: MasterDataRules.validateOptionalEmail,
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

import 'package:flutter/material.dart';

import '../../../data/models/trade.dart';
import '../../../data/services/master_data_rules.dart';

class UserManagementTradeDialog extends StatefulWidget {
  const UserManagementTradeDialog({super.key, this.initial});

  final Trade? initial;

  static Future<Trade?> show(BuildContext context, {Trade? initial}) =>
      showDialog<Trade>(
        context: context,
        builder: (_) => UserManagementTradeDialog(initial: initial),
      );

  @override
  State<UserManagementTradeDialog> createState() =>
      _UserManagementTradeDialogState();
}

class _UserManagementTradeDialogState extends State<UserManagementTradeDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      Trade(
        id: widget.initial?.id ?? 0,
        name: _name.text.trim(),
        createdAt: widget.initial?.createdAt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Add trade' : 'Edit trade'),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _formKey,
          child: TextFormField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Trade',
              hintText: 'e.g. Mason',
            ),
            onFieldSubmitted: (_) => _submit(),
            validator: (v) => MasterDataRules.required(v, 'trade name'),
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

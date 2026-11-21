import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../data/models/trade.dart';
import '../../../data/models/worker.dart';
import '../../../data/services/labor_rules.dart';

/// Add a worker (Full name, Address, Phone number) or edit an existing worker.
class LaborWorkerDialog extends StatefulWidget {
  const LaborWorkerDialog({super.key, this.initial, required this.trades});

  final Worker? initial;
  final List<Trade> trades;

  static Future<Worker?> show(
    BuildContext context, {
    Worker? initial,
    required List<Trade> trades,
  }) => showDialog<Worker>(
    context: context,
    builder: (_) => LaborWorkerDialog(initial: initial, trades: trades),
  );

  @override
  State<LaborWorkerDialog> createState() => _LaborWorkerDialogState();
}

class _LaborWorkerDialogState extends State<LaborWorkerDialog> {
  static const double _defaultDailyRate = 500;

  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.fullName);
  late final _address = TextEditingController(text: widget.initial?.address);
  late final _phone = TextEditingController(text: widget.initial?.phone);
  late final _rate = TextEditingController(
    text: InputParsers.amountText(widget.initial?.dailyRate),
  );
  late String? _trade = widget.initial?.trade ?? _defaultTradeName();
  late bool _active = widget.initial?.isActive ?? true;

  bool get _isAdding => widget.initial == null;

  String _defaultTradeName() {
    for (final t in widget.trades) {
      if (t.name.toLowerCase() == 'laborer' ||
          t.name.toLowerCase() == 'helper') {
        return t.name;
      }
    }
    return widget.trades.isNotEmpty ? widget.trades.first.name : 'Laborer';
  }

  @override
  void dispose() {
    for (final c in [_name, _address, _phone, _rate]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final base =
        widget.initial ??
        Worker(
          id: 0,
          fullName: '',
          trade: _defaultTradeName(),
          dailyRate: _defaultDailyRate,
        );
    Navigator.of(context).pop(
      base.copyWith(
        fullName: _name.text.trim(),
        address: () => InputParsers.optional(_address.text),
        phone: () => InputParsers.optional(_phone.text),
        trade: _isAdding ? _defaultTradeName() : _trade,
        dailyRate: _isAdding
            ? _defaultDailyRate
            : InputParsers.amount(_rate.text),
        isActive: _isAdding ? true : _active,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final trades = {
      ...widget.trades.map((t) => t.name),
      ?widget.initial?.trade,
    }.toList();
    return AlertDialog(
      title: Text(_isAdding ? 'Add worker' : 'Edit worker'),
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
                  decoration: const InputDecoration(labelText: 'Full name'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Enter the worker\'s name.'
                      : null,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _address,
                  decoration: const InputDecoration(labelText: 'Address'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Enter the worker\'s address.'
                      : null,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _phone,
                  decoration: const InputDecoration(labelText: 'Phone number'),
                  keyboardType: TextInputType.phone,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Enter the worker\'s phone number.'
                      : null,
                ),
                if (!_isAdding) ...[
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _trade,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Trade'),
                          items: [
                            for (final t in trades)
                              DropdownMenuItem(value: t, child: Text(t)),
                          ],
                          validator: (v) =>
                              v == null ? 'Choose a trade.' : null,
                          onChanged: (v) => setState(() => _trade = v),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: TextFormField(
                          controller: _rate,
                          decoration: const InputDecoration(
                            labelText: 'Daily rate',
                            prefixText: '₱ ',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          validator: (v) => LaborRules.validateDailyRate(
                            InputParsers.amount(v),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Active'),
                    value: _active,
                    onChanged: (v) => setState(() => _active = v),
                  ),
                ],
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

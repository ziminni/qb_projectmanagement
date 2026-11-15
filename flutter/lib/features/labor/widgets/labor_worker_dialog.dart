import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../data/models/trade.dart';
import '../../../data/models/worker.dart';
import '../../../data/services/labor_rules.dart';

/// Add or edit a worker with daily rate and government numbers.
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
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.fullName);
  late final _rate = TextEditingController(
    text: InputParsers.amountText(widget.initial?.dailyRate),
  );
  late final _sss = TextEditingController(text: widget.initial?.sssNo);
  late final _philhealth = TextEditingController(
    text: widget.initial?.philhealthNo,
  );
  late final _pagibig = TextEditingController(text: widget.initial?.pagibigNo);
  late String? _trade = widget.initial?.trade;
  late bool _active = widget.initial?.isActive ?? true;

  @override
  void dispose() {
    for (final c in [_name, _rate, _sss, _philhealth, _pagibig]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final base =
        widget.initial ??
        const Worker(id: 0, fullName: '', trade: '', dailyRate: 0);
    Navigator.of(context).pop(
      base.copyWith(
        fullName: _name.text.trim(),
        trade: _trade,
        dailyRate: InputParsers.amount(_rate.text),
        sssNo: () => InputParsers.optional(_sss.text),
        philhealthNo: () => InputParsers.optional(_philhealth.text),
        pagibigNo: () => InputParsers.optional(_pagibig.text),
        isActive: _active,
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
      title: Text(widget.initial == null ? 'Add worker' : 'Edit worker'),
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
                        validator: (v) => v == null ? 'Choose a trade.' : null,
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
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _sss,
                  decoration: const InputDecoration(labelText: 'SSS no.'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _philhealth,
                  decoration: const InputDecoration(
                    labelText: 'PhilHealth no.',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _pagibig,
                  decoration: const InputDecoration(labelText: 'Pag-IBIG no.'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
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

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/widgets/app_action_bar.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/layout/project_tabs.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/services/project_rules.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_date_field.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../viewmodels/project_form_viewmodel.dart';

class ProjectFormPage extends StatefulWidget {
  const ProjectFormPage({super.key, this.projectId});

  final int? projectId;

  @override
  State<ProjectFormPage> createState() => _ProjectFormPageState();
}

class _ProjectFormPageState extends State<ProjectFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _location = TextEditingController();
  final _contract = TextEditingController();
  final _downPayment = TextEditingController();
  final _retention = TextEditingController();
  DateTime? _start;
  DateTime? _end;
  int? _clientId;
  String? _dateError;

  late final _vm = ProjectFormViewModel(
    projectId: widget.projectId,
    session: getIt(),
    projects: getIt(),
    clients: getIt(),
    company: getIt(),
  );

  @override
  void initState() {
    super.initState();
    _vm.load().then((_) {
      if (!mounted) return;
      final p = _vm.project;
      final s = _vm.settings;
      setState(() {
        if (p != null) {
          _code.text = p.code;
          _name.text = p.name;
          _location.text = p.location;
          _contract.text = InputParsers.amountText(p.contractAmount);
          _downPayment.text = InputParsers.amountText(p.downPaymentPct);
          _retention.text = InputParsers.amountText(p.retentionPct);
          _start = p.startDate;
          _end = p.targetEndDate;
          _clientId = p.clientId;
        } else if (s != null) {
          _downPayment.text = InputParsers.amountText(s.defaultDownPaymentPct);
          _retention.text = InputParsers.amountText(s.defaultRetentionPct);
        }
      });
    });
  }

  @override
  void dispose() {
    for (final c in [
      _code,
      _name,
      _location,
      _contract,
      _downPayment,
      _retention,
    ]) {
      c.dispose();
    }
    _vm.dispose();
    super.dispose();
  }

  Future<void> _pick(bool start) async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
      initialDate: (start ? _start : _end) ?? _start ?? DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = picked;
      } else {
        _end = picked;
      }
      _dateError = null;
    });
  }

  Future<void> _save() async {
    final dateError = ProjectRules.validateDates(_start, _end);
    setState(() => _dateError = dateError);
    if (!_formKey.currentState!.validate() || dateError != null) return;
    final ok = await reportAction(
      context,
      _vm.save(
        code: _code.text,
        name: _name.text,
        location: _location.text,
        clientId: _clientId,
        contractAmount: InputParsers.amount(_contract.text) ?? 0,
        downPaymentPct: InputParsers.amount(_downPayment.text) ?? 0,
        retentionPct: InputParsers.amount(_retention.text) ?? 0,
        startDate: _start!,
        targetEndDate: _end!,
      ),
      success: 'Project saved.',
    );
    if (ok && mounted) {
      context.go(AppRoutes.projectTab(_vm.savedId!, ProjectTab.overview));
    }
  }

  String? _required(String? v, String label) =>
      (v == null || v.trim().isEmpty) ? 'Enter the $label.' : null;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Consumer<ProjectFormViewModel>(
        builder: (context, vm, _) {
          if (vm.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (vm.error != null) return AppEmptyState(message: vm.error!);
          return Form(
            key: _formKey,
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: pagePadding(context),
                    children: [
                      AppSectionCard(
                        title: vm.isNew ? 'New project' : 'Edit project',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (vm.isNew)
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: AppSpacing.md,
                                ),
                                child: Text(
                                  'New projects start as Draft. Move it to Bidding '
                                  'when the bid is ready to submit.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            Row(
                              children: [
                                SizedBox(
                                  width: 160,
                                  child: TextFormField(
                                    controller: _code,
                                    decoration: const InputDecoration(
                                      labelText: 'Code',
                                      hintText: 'QB-2026-030',
                                    ),
                                    validator: (v) =>
                                        _required(v, 'project code'),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: TextFormField(
                                    controller: _name,
                                    decoration: const InputDecoration(
                                      labelText: 'Project name',
                                    ),
                                    validator: (v) =>
                                        _required(v, 'project name'),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.md),
                            TextFormField(
                              controller: _location,
                              decoration: const InputDecoration(
                                labelText: 'Location',
                              ),
                              validator: (v) => _required(v, 'location'),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            DropdownButtonFormField<int>(
                              initialValue: _clientId,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Client',
                              ),
                              items: [
                                for (final c in vm.clients)
                                  DropdownMenuItem(
                                    value: c.id,
                                    child: Text(c.name),
                                  ),
                              ],
                              validator: (v) =>
                                  v == null ? 'Choose the client.' : null,
                              onChanged: (v) => setState(() => _clientId = v),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      AppSectionCard(
                        title: 'Contract',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: _contract,
                              enabled: !vm.contractLocked,
                              decoration: InputDecoration(
                                labelText: 'Contract amount',
                                prefixText: '₱ ',
                                helperText: vm.contractLocked
                                    ? 'Change the contract amount with a variation '
                                          'order once work has started.'
                                    : null,
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              validator: (v) =>
                                  ProjectRules.validateContractAmount(
                                    InputParsers.amount(v),
                                  ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _downPayment,
                                    decoration: const InputDecoration(
                                      labelText: 'Down payment',
                                      suffixText: '%',
                                    ),
                                    keyboardType: TextInputType.number,
                                    validator: (v) =>
                                        ProjectRules.validatePercent(
                                          InputParsers.amount(v),
                                          'down payment',
                                        ),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: TextFormField(
                                    controller: _retention,
                                    decoration: const InputDecoration(
                                      labelText: 'Retention',
                                      suffixText: '%',
                                    ),
                                    keyboardType: TextInputType.number,
                                    validator: (v) =>
                                        ProjectRules.validatePercent(
                                          InputParsers.amount(v),
                                          'retention',
                                        ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Row(
                              children: [
                                Expanded(
                                  child: AppDateField(
                                    label: 'Start date',
                                    value: _start,
                                    hasError: _dateError != null,
                                    onTap: () => _pick(true),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: AppDateField(
                                    label: 'Target end date',
                                    value: _end,
                                    hasError: _dateError != null,
                                    onTap: () => _pick(false),
                                  ),
                                ),
                              ],
                            ),
                            if (_dateError != null)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: AppSpacing.sm,
                                ),
                                child: Text(
                                  _dateError!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                AppActionBar(
                  children: [
                    TextButton(
                      onPressed: () => context.go(
                        vm.isNew
                            ? AppRoutes.projects
                            : AppRoutes.projectTab(
                                widget.projectId!,
                                ProjectTab.overview,
                              ),
                      ),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: vm.isBusy ? null : _save,
                      child: Text(vm.isNew ? 'Create project' : 'Save'),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

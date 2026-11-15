import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/layout/project_tabs.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/services/project_rules.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_action_bar.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_page_header.dart';
import '../viewmodels/project_form_viewmodel.dart';
import '../widgets/projects_budget_step.dart';
import '../widgets/projects_details_step.dart';
import '../widgets/projects_location_step.dart';
import '../widgets/projects_review_step.dart';
import '../widgets/projects_wizard_steps.dart';

/// Creates or edits a project in four steps: details, location, budget and
/// review. Creating sends the request to the client.
class ProjectFormPage extends StatefulWidget {
  const ProjectFormPage({super.key, this.projectId});

  final int? projectId;

  @override
  State<ProjectFormPage> createState() => _ProjectFormPageState();
}

class _ProjectFormPageState extends State<ProjectFormPage> {
  static const _steps = <WizardStep>[
    (
      title: 'Project details',
      subtitle: 'Name, client, foreman and dates',
      icon: Icons.description_outlined,
    ),
    (
      title: 'Location',
      subtitle: 'Address and map pin',
      icon: Icons.place_outlined,
    ),
    (
      title: 'Budget',
      subtitle: 'Contract terms and categories',
      icon: Icons.payments_outlined,
    ),
    (
      title: 'Review',
      subtitle: 'Check and send',
      icon: Icons.fact_check_outlined,
    ),
  ];

  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _location = TextEditingController();
  final _contract = TextEditingController();
  final _downPayment = TextEditingController();
  final _retention = TextEditingController();
  final _categories = <ProjectsCategoryDraft>[];
  int _step = 0;
  DateTime? _start;
  DateTime? _end;
  int? _clientId;
  int? _siteEngineerId;
  LatLng? _pin;
  String? _dateError;

  late final _vm = ProjectFormViewModel(
    projectId: widget.projectId,
    session: getIt(),
    projects: getIt(),
    clients: getIt(),
    company: getIt(),
    users: getIt(),
    schedule: getIt(),
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
          if (p.hasPin) _pin = LatLng(p.latitude!, p.longitude!);
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
    for (final d in _categories) {
      d.dispose();
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

  List<(String, double)> get _categoryValues => [
    for (final d in _categories) (d.name.text.trim(), d.value),
  ];

  /// Checks the current step; returns false and shows why when it is not
  /// complete.
  bool _validateStep() {
    var ok = _formKey.currentState!.validate();
    if (_step == 0) {
      final dateError = ProjectRules.validateDates(_start, _end);
      setState(() => _dateError = dateError);
      ok = ok && dateError == null;
    }
    if (ok && _step == 2 && _vm.isNew) {
      final error = _vm.validateCategories(
        InputParsers.amount(_contract.text) ?? 0,
        _categoryValues,
      );
      if (error != null) {
        showAppMessage(context, error);
        return false;
      }
    }
    return ok;
  }

  void _next() {
    if (!_validateStep()) return;
    setState(() => _step++);
  }

  Future<void> _save() async {
    final ok = await reportAction(
      context,
      _vm.save(
        code: _code.text,
        name: _name.text,
        location: _location.text,
        latitude: _pin?.latitude,
        longitude: _pin?.longitude,
        clientId: _clientId,
        contractAmount: InputParsers.amount(_contract.text) ?? 0,
        downPaymentPct: InputParsers.amount(_downPayment.text) ?? 0,
        retentionPct: InputParsers.amount(_retention.text) ?? 0,
        startDate: _start!,
        targetEndDate: _end!,
        siteEngineerId: _siteEngineerId,
        categories: _vm.isNew ? _categoryValues : const [],
      ),
      success: _vm.isNew
          ? 'Project created and sent to the client.'
          : 'Project saved.',
    );
    if (ok && mounted) {
      context.go(AppRoutes.projectTab(_vm.savedId!, ProjectTab.overview));
    }
  }

  Widget _stepBody(ProjectFormViewModel vm) => switch (_step) {
    0 => ProjectsDetailsStep(
      code: _code,
      name: _name,
      isNew: vm.isNew,
      clients: vm.clients,
      clientId: _clientId,
      onClient: (v) => setState(() => _clientId = v),
      validateClient: vm.validateClient,
      siteEngineers: vm.siteEngineers,
      siteEngineerId: _siteEngineerId,
      onSiteEngineer: (v) => setState(() => _siteEngineerId = v),
      start: _start,
      end: _end,
      dateError: _dateError,
      onPickStart: () => _pick(true),
      onPickEnd: () => _pick(false),
    ),
    1 => ProjectsLocationStep(
      location: _location,
      pin: _pin,
      onPick: (p) => setState(() => _pin = p),
      onClear: () => setState(() => _pin = null),
    ),
    2 => ProjectsBudgetStep(
      contract: _contract,
      downPayment: _downPayment,
      retention: _retention,
      contractLocked: vm.contractLocked,
      categories: vm.isNew ? _categories : null,
      onAddCategory: (name) =>
          setState(() => _categories.add(ProjectsCategoryDraft(name))),
      onRemoveCategory: (i) =>
          setState(() => _categories.removeAt(i).dispose()),
      onChanged: () => setState(() {}),
    ),
    _ => ProjectsReviewStep(
      isNew: vm.isNew,
      code: _code.text,
      name: _name.text,
      clientName: vm.clientName(_clientId),
      siteEngineerName: vm.siteEngineerName(_siteEngineerId),
      start: _start!,
      end: _end!,
      location: _location.text,
      pin: _pin,
      contract: InputParsers.amount(_contract.text) ?? 0,
      downPaymentPct: InputParsers.amount(_downPayment.text) ?? 0,
      retentionPct: InputParsers.amount(_retention.text) ?? 0,
      categories: _categoryValues,
      onEdit: (i) => setState(() => _step = i),
    ),
  };

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
          final wide = MediaQuery.sizeOf(context).width >= 1000;
          final last = _step == _steps.length - 1;
          final step = _steps[_step];
          final content = Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        step.icon,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        step.title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    step.subtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _stepBody(vm),
                ],
              ),
            ),
          );
          return Form(
            key: _formKey,
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: pagePadding(context).copyWith(top: AppSpacing.xl),
                    children: [
                      AppPageHeader(
                        title: vm.isNew
                            ? 'New project'
                            : 'Edit ${vm.project!.code}',
                        subtitle:
                            'Step ${_step + 1} of ${_steps.length} · '
                            '${step.title}',
                      ),
                      if (wide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 280,
                              child: Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(AppSpacing.sm),
                                  child: ProjectsWizardSteps(
                                    steps: _steps,
                                    current: _step,
                                    onTap: (i) => setState(() => _step = i),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.lg),
                            Expanded(child: content),
                          ],
                        )
                      else ...[
                        ProjectsWizardSteps(
                          steps: _steps,
                          current: _step,
                          vertical: false,
                          onTap: (i) => setState(() => _step = i),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        content,
                      ],
                    ],
                  ),
                ),
                AppActionBar(
                  hint: last && vm.isNew
                      ? 'The client gets the request first.'
                      : null,
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
                    if (_step > 0)
                      OutlinedButton.icon(
                        onPressed: () => setState(() => _step--),
                        icon: const Icon(Icons.arrow_back_rounded, size: 18),
                        label: const Text('Back'),
                      ),
                    if (!last)
                      FilledButton.icon(
                        onPressed: _next,
                        icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                        label: Text('Next: ${_steps[_step + 1].title}'),
                      )
                    else
                      FilledButton.icon(
                        onPressed: vm.isBusy ? null : _save,
                        icon: Icon(
                          vm.isNew ? Icons.send_rounded : Icons.save_outlined,
                          size: 18,
                        ),
                        label: Text(
                          vm.isNew ? 'Create and send request' : 'Save changes',
                        ),
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

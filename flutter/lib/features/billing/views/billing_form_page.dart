import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/widgets/app_action_bar.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_padding.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_date_field.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_info_row.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../viewmodels/billing_form_viewmodel.dart';

/// PM generates a progress billing from verified progress.
class BillingFormPage extends StatefulWidget {
  const BillingFormPage({super.key, this.projectId});

  final int? projectId;

  @override
  State<BillingFormPage> createState() => _BillingFormPageState();
}

class _BillingFormPageState extends State<BillingFormPage> {
  late final _vm = BillingFormViewModel(
    initialProjectId: widget.projectId,
    session: getIt(),
    projects: getIt(),
    billing: getIt(),
  )..load();

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final ok = await reportAction(
      context,
      _vm.create(),
      success: 'Draft billing created.',
    );
    if (ok && mounted) context.go(AppRoutes.billing(_vm.savedId!));
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Consumer<BillingFormViewModel>(
        builder: (context, vm, _) {
          if (vm.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (vm.error != null) return AppEmptyState(message: vm.error!);
          final c = vm.preview;
          final p = vm.project;
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: pagePadding(context),
                  children: [
                    AppSectionCard(
                      title: 'New progress billing',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DropdownButtonFormField<int>(
                            initialValue: vm.projectId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Project',
                            ),
                            items: [
                              for (final p in vm.projectOptions)
                                DropdownMenuItem(
                                  value: p.id,
                                  child: Text('${p.code} · ${p.name}'),
                                ),
                            ],
                            onChanged: vm.setProject,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          AppDateField(
                            label: 'Period end',
                            value: vm.periodEnd,
                            hasError: false,
                            onTap: () async {
                              final d = await showDatePicker(
                                context: context,
                                firstDate: DateTime(2024),
                                lastDate: DateTime.now(),
                                initialDate: vm.periodEnd,
                              );
                              if (d != null) await vm.setPeriodEnd(d);
                            },
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'Only to-dos verified on or before the period end count.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (c != null && p != null) ...[
                      const SizedBox(height: AppSpacing.lg),
                      AppSectionCard(
                        title: 'Computation',
                        child: Column(
                          children: [
                            AppInfoRow(
                              label: 'Contract amount',
                              value: Formatters.peso(p.contractAmount),
                            ),
                            AppInfoRow(
                              label: 'Accomplishment',
                              value:
                                  '${(c.pctAccomplished * 100).toStringAsFixed(2)}%',
                            ),
                            AppInfoRow(
                              label: 'Gross earned to date',
                              value: Formatters.peso(c.grossEarned),
                            ),
                            AppInfoRow(
                              label: 'Less previous billings',
                              value: Formatters.peso(c.lessPrevious),
                            ),
                            AppInfoRow(
                              label: 'Less DP recoupment',
                              value: Formatters.peso(c.lessDpRecoupment),
                            ),
                            AppInfoRow(
                              label: 'Less retention',
                              value: Formatters.peso(c.lessRetention),
                            ),
                            const Divider(),
                            AppInfoRow(
                              label: 'Net amount due',
                              value: Formatters.peso(c.netDue),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (vm.previewError != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Card(
                        color: AppColors.warningContainer,
                        child: ListTile(
                          leading: const Icon(Icons.info_outline),
                          title: Text(vm.previewError!),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              AppActionBar(
                hint: vm.preview == null
                    ? null
                    : 'Net amount due: ${Formatters.peso(vm.preview!.netDue)}',
                children: [
                  FilledButton(
                    onPressed: vm.isBusy || vm.previewError != null
                        ? null
                        : _create,
                    child: const Text('Create draft billing'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/finance_access.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/models/variation_order.dart';
import '../../../data/services/billing_rules.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_action_bar.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../viewmodels/variation_order_form_viewmodel.dart';
import '../widgets/vo_photo_attachments.dart';
import '../widgets/vo_revised_schedule_section.dart';

/// Raise or edit a Variation Order by uploading the revised Bar Chart (`.xlsx`)
/// and attaching revised DUPA (Sections A–J) per flagged Item of Work.
class VariationOrderFormPage extends StatefulWidget {
  const VariationOrderFormPage({super.key, this.voId, this.projectId});

  final int? voId;
  final int? projectId;

  @override
  State<VariationOrderFormPage> createState() => _VariationOrderFormPageState();
}

class _VariationOrderFormPageState extends State<VariationOrderFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _description = TextEditingController();
  late final _vm = VariationOrderFormViewModel(
    voId: widget.voId,
    initialProjectId: widget.projectId,
    session: getIt(),
    projects: getIt(),
    billing: getIt(),
  );

  @override
  void initState() {
    super.initState();
    _vm.load().then((_) {
      final e = _vm.existing;
      if (e == null) return;
      _description.text = e.description;
    });
  }

  @override
  void dispose() {
    _description.dispose();
    _vm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final isNew = _vm.existing == null;
    final ok = await reportAction(
      context,
      _vm.save(description: _description.text),
    );
    if (ok && mounted) {
      final voLabel = _vm.savedVoNo ?? 'Variation order';
      showSuccessAlert(
        context,
        isNew
            ? '$voLabel saved as draft. Review the flagged changes and send to the client when ready.'
            : '$voLabel draft updated.',
      );
      context.go(AppRoutes.variationOrder(_vm.savedId!));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Consumer<VariationOrderFormViewModel>(
        builder: (context, vm, _) {
          final finance = canSeeFinance();
          if (vm.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (vm.error != null) return AppEmptyState(message: vm.error!);

          return ListView(
            padding: pagePadding(context),
            children: [
              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppSectionCard(
                      title: 'Variation order details',
                      subtitle:
                          'Select the project, change type, and describe the reason for the revision',
                      icon: Icons.difference_outlined,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DropdownButtonFormField<int>(
                            key: ValueKey('vo-project-${vm.projectId}'),
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
                            onChanged: vm.existing == null
                                ? vm.setProject
                                : null,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          SegmentedButton<VariationOrderType>(
                            segments: [
                              for (final t in VariationOrderType.values)
                                ButtonSegment(value: t, label: Text(t.label)),
                            ],
                            selected: {vm.type},
                            onSelectionChanged: (s) => vm.setType(s.first),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          TextFormField(
                            controller: _description,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: 'Description / justification',
                              hintText:
                                  'e.g. Realignment of masonry & concrete quantities with +23cd extension',
                            ),
                            validator: BillingRules.validateVoDescription,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (vm.projectId != null)
                      AppSectionCard(
                        title: 'Revised Bar Chart & DUPA (A–J)',
                        subtitle:
                            'Import the revised Bar Chart sheet — days impact, cost deltas, and changed items are flagged automatically',
                        icon: Icons.table_chart_outlined,
                        child: VoRevisedScheduleSection(
                          projectId: vm.projectId!,
                          revisedSchedule: vm.revisedSchedule,
                          showCosts: finance,
                          editable: true,
                          onChanged: vm.setRevisedSchedule,
                        ),
                      ),
                    const SizedBox(height: AppSpacing.lg),
                    AppSectionCard(
                      title: 'Supporting photos (optional)',
                      subtitle: 'Attach site evidence or revised plans',
                      icon: Icons.photo_library_outlined,
                      child: VoPhotoPickerSection(
                        type: vm.type,
                        primaryAttachments: vm.primaryAttachments,
                        secondaryAttachments: vm.secondaryAttachments,
                        onAddPrimary: vm.addPrimaryAttachments,
                        onRemovePrimary: vm.removePrimaryAttachment,
                        onAddSecondary: vm.addSecondaryAttachments,
                        onRemoveSecondary: vm.removeSecondaryAttachment,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    AppActionBar(
                      children: [
                        TextButton(
                          onPressed: vm.isBusy
                              ? null
                              : () => context.go(AppRoutes.variationOrders),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: vm.isBusy ? null : _save,
                          child: Text(
                            vm.existing == null
                                ? 'Save variation order'
                                : 'Save changes',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

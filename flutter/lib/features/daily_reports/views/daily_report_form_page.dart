import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/widgets/app_action_bar.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/models/daily_report.dart';
import '../../../data/services/daily_report_rules.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_date_field.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_photo_tile.dart';
import '../../../shared/widgets/app_quantity_rows_editor.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../viewmodels/daily_report_form_viewmodel.dart';
import '../widgets/daily_reports_issue_dialog.dart';
import '../widgets/daily_reports_manpower_editor.dart';
import '../widgets/daily_reports_photo_dialog.dart';
import '../widgets/daily_reports_todo_picker.dart';

/// Mobile-first daily report form for the site engineer.
class DailyReportFormPage extends StatefulWidget {
  const DailyReportFormPage({super.key, this.reportId, this.projectId});

  final int? reportId;
  final int? projectId;

  @override
  State<DailyReportFormPage> createState() => _DailyReportFormPageState();
}

class _DailyReportFormPageState extends State<DailyReportFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final _vm = DailyReportFormViewModel(
    reportId: widget.reportId,
    initialProjectId: widget.projectId,
    session: getIt(),
    projects: getIt(),
    reports: getIt(),
    schedule: getIt(),
    masterData: getIt(),
  )..load();

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  Future<void> _save({required bool submit}) async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await reportAction(
      context,
      _vm.save(submit: submit),
      success: submit ? 'Report submitted to the PM.' : 'Draft saved.',
    );
    if (ok && mounted) context.go(AppRoutes.dailyReport(_vm.savedId!));
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Consumer<DailyReportFormViewModel>(
        builder: (context, vm, _) {
          if (vm.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (vm.error != null) return AppEmptyState(message: vm.error!);
          final dateError = DailyReportRules.validateDate(
            vm.reportDate,
            DateTime.now(),
          );
          const gap = SizedBox(height: AppSpacing.lg);
          return Form(
            key: _formKey,
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: pagePadding(context),
                    children: [
                      if (vm.remarks != null) ...[
                        Card(
                          color: AppColors.warningContainer,
                          child: ListTile(
                            leading: const Icon(
                              Icons.undo,
                              color: AppColors.warning,
                            ),
                            title: const Text('Returned by the PM'),
                            subtitle: Text(vm.remarks!),
                          ),
                        ),
                        gap,
                      ],
                      AppSectionCard(
                        title: 'Site and date',
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
                              validator: (v) =>
                                  v == null ? 'Choose the project.' : null,
                              onChanged: vm.isNew ? vm.setProject : null,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            AppDateField(
                              label: 'Report date',
                              value: vm.reportDate,
                              hasError: dateError != null,
                              onTap: () async {
                                final d = await showDatePicker(
                                  context: context,
                                  firstDate: DateTime(2024),
                                  lastDate: DateTime.now(),
                                  initialDate: vm.reportDate,
                                );
                                if (d != null) vm.setDate(d);
                              },
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              'Weather',
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Wrap(
                              spacing: AppSpacing.sm,
                              runSpacing: AppSpacing.sm,
                              children: [
                                for (final w in Weather.values)
                                  ChoiceChip(
                                    label: Text(w.label),
                                    selected: vm.weather == w,
                                    onSelected: (_) => vm.setWeather(w),
                                  ),
                              ],
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Toolbox meeting held'),
                              subtitle: const Text(
                                'Daily safety briefing (DOLE OSH)',
                              ),
                              value: vm.toolboxMeetingHeld,
                              onChanged: vm.setToolbox,
                            ),
                          ],
                        ),
                      ),
                      gap,
                      AppSectionCard(
                        title: 'Manpower',
                        subtitle: 'Headcount per trade on site today.',
                        child: DailyReportsManpowerEditor(
                          rows: vm.manpower,
                          trades: vm.trades,
                          onChanged: vm.changed,
                        ),
                      ),
                      gap,
                      AppSectionCard(
                        title: 'To-dos accomplished',
                        subtitle:
                            'Tick what was finished today. It counts toward progress once the PM approves this report.',
                        child: DailyReportsTodoPicker(
                          todos: vm.todoOptions,
                          selected: vm.todoIds,
                          onChanged: vm.toggleTodo,
                        ),
                      ),
                      gap,
                      AppSectionCard(
                        title: 'Materials used',
                        subtitle:
                            'Deducted from site inventory when the report is approved.',
                        child: AppQuantityRowsEditor(
                          rows: vm.materialRows,
                          options: [
                            for (final m in vm.materials)
                              (m.id, '${m.name} (${m.unit})'),
                          ],
                          itemLabel: 'Material',
                          quantityLabel: 'Quantity',
                          addLabel: 'Add material',
                          validateQuantity: DailyReportRules.validateQuantity,
                          onChanged: vm.changed,
                        ),
                      ),
                      gap,
                      AppSectionCard(
                        title: 'Equipment',
                        subtitle: 'Hours each machine was used.',
                        child: AppQuantityRowsEditor(
                          rows: vm.equipmentRows,
                          options: [
                            for (final e in vm.equipment) (e.id, e.name),
                          ],
                          itemLabel: 'Equipment',
                          quantityLabel: 'Hours',
                          addLabel: 'Add equipment',
                          validateQuantity: DailyReportRules.validateHours,
                          onChanged: vm.changed,
                        ),
                      ),
                      gap,
                      AppSectionCard(
                        title: 'Issues and delays',
                        subtitle:
                            'Log rain or typhoon days lost to support time extensions.',
                        trailing: TextButton.icon(
                          onPressed: () async {
                            final issue = await DailyReportsIssueDialog.show(
                              context,
                            );
                            if (issue != null) {
                              vm.issues.add(issue);
                              vm.changed();
                            }
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Add'),
                        ),
                        child: vm.issues.isEmpty
                            ? Text(
                                'No issues today.',
                                style: Theme.of(context).textTheme.bodySmall,
                              )
                            : Column(
                                children: [
                                  for (final (i, x) in vm.issues.indexed)
                                    ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(
                                        '${x.type.label} · ${x.reason.label}',
                                      ),
                                      subtitle: Text(
                                        '${x.description}'
                                        '${x.daysLost > 0 ? ' · ${x.daysLost} day(s) lost' : ''}',
                                      ),
                                      trailing: IconButton(
                                        tooltip: 'Remove issue',
                                        icon: const Icon(
                                          Icons.remove_circle_outline,
                                        ),
                                        onPressed: () {
                                          vm.issues.removeAt(i);
                                          vm.changed();
                                        },
                                      ),
                                    ),
                                ],
                              ),
                      ),
                      gap,
                      AppSectionCard(
                        title: 'Photos',
                        subtitle:
                            'Visible to the client once the report is approved.',
                        trailing: TextButton.icon(
                          onPressed: () async {
                            final photo = await DailyReportsPhotoDialog.show(
                              context,
                            );
                            if (photo != null) {
                              vm.photos.add(photo);
                              vm.changed();
                            }
                          },
                          icon: const Icon(Icons.add_a_photo_outlined),
                          label: const Text('Add'),
                        ),
                        child: vm.photos.isEmpty
                            ? Text(
                                'No photos yet.',
                                style: Theme.of(context).textTheme.bodySmall,
                              )
                            : Wrap(
                                spacing: AppSpacing.sm,
                                runSpacing: AppSpacing.sm,
                                children: [
                                  for (final (i, p) in vm.photos.indexed)
                                    AppPhotoTile(
                                      fileUrl: p.fileUrl,
                                      caption: p.caption,
                                      onRemove: () {
                                        vm.photos.removeAt(i);
                                        vm.changed();
                                      },
                                    ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
                AppActionBar(
                  hint:
                      'Submitting marks the checked to-dos done and sends the report to the PM.',
                  children: [
                    OutlinedButton(
                      onPressed: vm.isBusy ? null : () => _save(submit: false),
                      child: const Text('Save draft'),
                    ),
                    FilledButton.icon(
                      onPressed: vm.isBusy ? null : () => _save(submit: true),
                      icon: const Icon(Icons.send),
                      label: const Text('Submit to PM'),
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

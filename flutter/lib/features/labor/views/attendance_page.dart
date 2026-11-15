import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/widgets/app_action_bar.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/models/attendance.dart';
import '../../../shared/widgets/app_date_field.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../viewmodels/attendance_viewmodel.dart';
import '../widgets/labor_attendance_row.dart';

/// Site engineer's daily attendance sheet.
class AttendancePage extends StatefulWidget {
  const AttendancePage({super.key, this.projectId});

  final int? projectId;

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  final _formKey = GlobalKey<FormState>();
  late final _vm = AttendanceViewModel(
    initialProjectId: widget.projectId,
    session: getIt(),
    projects: getIt(),
    labor: getIt(),
  )..load();

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Consumer<AttendanceViewModel>(
        builder: (context, vm, _) {
          if (vm.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (vm.error != null) return AppEmptyState(message: vm.error!);
          final locked = vm.lockedReason != null;
          return Form(
            key: _formKey,
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: pagePadding(context),
                    children: [
                      Wrap(
                        spacing: AppSpacing.md,
                        runSpacing: AppSpacing.md,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: 320,
                            child: DropdownButtonFormField<int>(
                              initialValue: vm.projectId,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Site',
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
                          ),
                          SizedBox(
                            width: 200,
                            child: AppDateField(
                              label: 'Date',
                              value: vm.date,
                              hasError: false,
                              onTap: () async {
                                final d = await showDatePicker(
                                  context: context,
                                  firstDate: DateTime(2024),
                                  lastDate: DateTime.now(),
                                  initialDate: vm.date,
                                );
                                if (d != null) await vm.setDate(d);
                              },
                            ),
                          ),
                          if (!locked) ...[
                            OutlinedButton.icon(
                              onPressed: () =>
                                  vm.markAll(AttendanceStatus.present),
                              icon: const Icon(Icons.done_all),
                              label: const Text('Mark all present'),
                            ),
                            TextButton(
                              onPressed: vm.clearAll,
                              child: const Text('Clear'),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (locked)
                        Card(
                          color: AppColors.surfaceMuted,
                          child: ListTile(
                            leading: const Icon(Icons.lock_outline),
                            title: Text(vm.lockedReason!),
                          ),
                        ),
                      Text(
                        '${vm.marked} of ${vm.rows.length} marked · '
                        '${InputParsers.amountText(vm.presentDays)} paid days',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            for (final (i, r) in vm.rows.indexed) ...[
                              if (i > 0) const Divider(height: 1),
                              LaborAttendanceRow(
                                row: r,
                                enabled: !locked,
                                onChanged: vm.changed,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (!locked)
                  AppActionBar(
                    hint: '${vm.marked} of ${vm.rows.length} workers marked',
                    children: [
                      FilledButton(
                        onPressed: vm.isBusy
                            ? null
                            : () async {
                                if (!_formKey.currentState!.validate()) return;
                                await reportAction(
                                  context,
                                  vm.save(),
                                  success: 'Attendance saved.',
                                );
                              },
                        child: const Text('Save attendance'),
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

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../core/utils/page_padding.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_info_row.dart';
import '../../../shared/widgets/app_photo_tile.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../../../shared/widgets/app_workflow_steps.dart';
import '../viewmodels/daily_report_detail_viewmodel.dart';
import '../widgets/daily_reports_return_dialog.dart';
import '../widgets/daily_reports_status_chip.dart';

/// A daily report with its review actions: the site engineer edits and
/// submits; the PM approves or returns it with remarks.
class DailyReportDetailPage extends StatelessWidget {
  const DailyReportDetailPage({super.key, required this.reportId});

  final int reportId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      key: ValueKey(reportId),
      create: (_) => DailyReportDetailViewModel(
        reportId: reportId,
        session: getIt(),
        projects: getIt(),
        reports: getIt(),
        masterData: getIt(),
        users: getIt(),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<DailyReportDetailViewModel>();
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (vm.error != null) return AppEmptyState(message: vm.error!);
        final d = vm.detail!;
        final r = d.report;
        final textTheme = Theme.of(context).textTheme;
        const gap = SizedBox(height: AppSpacing.lg);
        String none(String what) => 'No $what recorded.';

        return ListView(
          padding: pagePadding(context),
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Daily report · ${Formatters.date(r.reportDate)}',
                  style: textTheme.headlineSmall,
                ),
                DailyReportsStatusChip(status: r.status),
              ],
            ),
            Text(
              '${vm.project?.code} · ${vm.project?.name}',
              style: textTheme.bodySmall,
            ),
            gap,
            AppWorkflowSteps.dailyReport(r.status),
            gap,
            if (r.remarks != null) ...[
              Card(
                color: AppColors.warningContainer,
                child: ListTile(
                  leading: const Icon(Icons.undo, color: AppColors.warning),
                  title: Text(
                    'Returned by ${vm.userName(r.reviewedBy) ?? 'the PM'}',
                  ),
                  subtitle: Text(r.remarks!),
                ),
              ),
              gap,
            ],
            if (vm.canEdit || vm.canReview) ...[
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  if (vm.canEdit) ...[
                    FilledButton.icon(
                      onPressed: vm.isBusy
                          ? null
                          : () => reportAction(
                              context,
                              vm.submit(),
                              success: 'Report submitted to the PM.',
                            ),
                      icon: const Icon(Icons.send),
                      label: const Text('Submit to PM'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () =>
                          context.go(AppRoutes.dailyReportEdit(r.id)),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit'),
                    ),
                  ],
                  if (vm.canReview) ...[
                    FilledButton.icon(
                      onPressed: vm.isBusy
                          ? null
                          : () => reportAction(
                              context,
                              vm.approve(),
                              success:
                                  'Report approved. Its to-dos are verified.',
                            ),
                      icon: const Icon(Icons.check),
                      label: const Text('Approve'),
                    ),
                    OutlinedButton.icon(
                      onPressed: vm.isBusy
                          ? null
                          : () async {
                              final remarks =
                                  await DailyReportsReturnDialog.show(context);
                              if (remarks != null && context.mounted) {
                                await reportAction(
                                  context,
                                  vm.returnReport(remarks),
                                  success: 'Report returned.',
                                );
                              }
                            },
                      icon: const Icon(Icons.undo),
                      label: const Text('Return with remarks'),
                    ),
                  ],
                ],
              ),
              gap,
            ],
            AppSectionCard(
              title: 'Conditions',
              child: Column(
                children: [
                  AppInfoRow(label: 'Weather', value: r.weather.label),
                  AppInfoRow(
                    label: 'Toolbox meeting',
                    value: r.toolboxMeetingHeld ? 'Held' : 'Not held',
                  ),
                  AppInfoRow(
                    label: 'Submitted by',
                    value: vm.userName(r.submittedBy) ?? '—',
                  ),
                  if (r.reviewedBy != null)
                    AppInfoRow(
                      label: 'Reviewed by',
                      value: vm.userName(r.reviewedBy) ?? '—',
                    ),
                ],
              ),
            ),
            gap,
            AppSectionCard(
              title: 'Manpower (${d.totalHeadcount})',
              child: d.manpower.isEmpty
                  ? Text(none('manpower'))
                  : Column(
                      children: [
                        for (final m in d.manpower)
                          AppInfoRow(label: m.trade, value: '${m.headcount}'),
                      ],
                    ),
            ),
            gap,
            AppSectionCard(
              title: 'To-dos accomplished',
              child: d.todos.isEmpty
                  ? Text(none('to-dos'))
                  : Column(
                      children: [
                        for (final t in d.todos)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            leading: Icon(
                              t.isVerified
                                  ? Icons.verified
                                  : Icons.check_circle_outline,
                              color: t.isVerified ? AppColors.success : null,
                            ),
                            title: Text(t.title),
                            subtitle: Text(
                              t.isVerified
                                  ? 'Verified'
                                  : t.isDone
                                  ? 'Awaiting verification'
                                  : 'Marked done on submit',
                            ),
                          ),
                      ],
                    ),
            ),
            gap,
            AppSectionCard(
              title: 'Materials used',
              child: d.materials.isEmpty
                  ? Text(none('materials'))
                  : Column(
                      children: [
                        for (final m in d.materials)
                          AppInfoRow(
                            label: vm.materialName(m.materialId),
                            value: InputParsers.amountText(m.quantity),
                          ),
                      ],
                    ),
            ),
            gap,
            AppSectionCard(
              title: 'Equipment',
              child: d.equipment.isEmpty
                  ? Text(none('equipment'))
                  : Column(
                      children: [
                        for (final e in d.equipment)
                          AppInfoRow(
                            label: vm.equipmentName(e.equipmentId),
                            value: '${InputParsers.amountText(e.hoursUsed)} h',
                          ),
                      ],
                    ),
            ),
            gap,
            AppSectionCard(
              title: 'Issues and delays',
              child: d.issues.isEmpty
                  ? Text(none('issues'))
                  : Column(
                      children: [
                        for (final x in d.issues)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('${x.type.label} · ${x.reason.label}'),
                            subtitle: Text(
                              '${x.description}'
                              '${x.daysLost > 0 ? ' · ${InputParsers.amountText(x.daysLost)} day(s) lost' : ''}',
                            ),
                          ),
                      ],
                    ),
            ),
            gap,
            AppSectionCard(
              title: 'Photos',
              child: d.photos.isEmpty
                  ? Text(none('photos'))
                  : Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final p in d.photos)
                          AppPhotoTile(
                            fileUrl: p.fileUrl,
                            caption: p.caption,
                            subtitle: p.takenAt == null
                                ? null
                                : Formatters.dateTime(p.takenAt!.toLocal()),
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

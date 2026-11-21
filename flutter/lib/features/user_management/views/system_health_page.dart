import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_padding.dart';
import '../../../shared/widgets/app_info_row.dart';
import '../../../shared/widgets/app_page_header.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../../../shared/widgets/app_status_chip.dart';
import '../../dashboard/widgets/dashboard_stat_tile.dart';
import '../viewmodels/system_health_viewmodel.dart';
import '../widgets/admin_dashboard/admin_dashboard_kit.dart';

class SystemHealthPage extends StatefulWidget {
  const SystemHealthPage({super.key});

  @override
  State<SystemHealthPage> createState() => _SystemHealthPageState();
}

class _SystemHealthPageState extends State<SystemHealthPage> {
  late final _vm = SystemHealthViewModel(getIt());

  @override
  void initState() {
    super.initState();
    _vm.load();
  }

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Consumer<SystemHealthViewModel>(
        builder: (context, vm, _) {
          if (vm.isLoading) return const AdminTabSkeleton();
          if (vm.error != null) {
            return AdminErrorState(message: vm.error!, onRetry: vm.load);
          }
          final data = vm.overview!;
          final pos = data.posBridge;
          final storage = data.storage;
          final dbOk = data.database == 'ok';

          return RefreshIndicator(
            onRefresh: vm.load,
            child: ListView(
              padding: pagePadding(context),
              children: [
                AppPageHeader(
                  title: 'System health & POS bridge',
                  subtitle:
                      'Database status, private storage usage, and CPMS-to-POS sync outbox.',
                  actions: [
                    OutlinedButton.icon(
                      onPressed: vm.isBusy
                          ? null
                          : () => vm.load(probePos: true),
                      icon: const Icon(Icons.network_check_outlined, size: 18),
                      label: const Text('Test POS connection'),
                    ),
                  ],
                ),
                AdminStatGrid(
                  tiles: [
                    DashboardStatTile(
                      label: 'Database',
                      value: dbOk ? 'Healthy' : 'Error',
                      detail: dbOk
                          ? 'PostgreSQL connection OK'
                          : 'Connection check failed',
                      icon: Icons.dns_outlined,
                      color: dbOk ? AppColors.success : AppColors.error,
                    ),
                    DashboardStatTile(
                      label: 'Private storage',
                      value: _formatBytes(storage.totalBytes),
                      detail: 'Reports, docs, and backups',
                      icon: Icons.folder_outlined,
                    ),
                    DashboardStatTile(
                      label: 'POS synced',
                      value: '${pos.syncedCount}',
                      detail: 'Completed outbox jobs',
                      icon: Icons.cloud_done_outlined,
                      color: AppColors.success,
                    ),
                    DashboardStatTile(
                      label: 'POS attention',
                      value: '${pos.failedCount + pos.pendingCount}',
                      detail:
                          '${pos.failedCount} failed · ${pos.pendingCount} pending',
                      icon: Icons.sync_problem_outlined,
                      color: pos.failedCount > 0
                          ? AppColors.warning
                          : AppColors.textSecondary,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                AdminTwoColumn(
                  main: [
                    AppSectionCard(
                      title: 'POS outbox queue',
                      icon: Icons.sync_outlined,
                      subtitle: pos.jobs.isEmpty
                          ? 'All own-store orders are synced'
                          : '${pos.jobs.length} pending or failed '
                                '${pos.jobs.length == 1 ? 'job' : 'jobs'}',
                      padding: EdgeInsets.zero,
                      child: pos.jobs.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(AppSpacing.lg),
                              child: Text('No pending or failed POS syncs.'),
                            )
                          : Column(
                              children: [
                                for (final (i, job) in pos.jobs.indexed) ...[
                                  if (i > 0) const Divider(height: 1),
                                  ListTile(
                                    title: Text(
                                      '${job.poNumber} · ${job.projectName}',
                                    ),
                                    subtitle: Text(
                                      [
                                        '${job.operation.toUpperCase()} (${job.attempts} tries)',
                                        if (job.lastError.isNotEmpty)
                                          job.lastError,
                                        Formatters.dateTime(job.updatedAt),
                                      ].join(' · '),
                                    ),
                                    trailing: Wrap(
                                      spacing: AppSpacing.sm,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        AppStatusChip(
                                          label: job.state.toUpperCase(),
                                          foreground: job.state == 'failed'
                                              ? AppColors.error
                                              : AppColors.warning,
                                          background: job.state == 'failed'
                                              ? AppColors.errorContainer
                                              : AppColors.warningContainer,
                                        ),
                                        OutlinedButton(
                                          onPressed: vm.isBusy
                                              ? null
                                              : () => reportAction(
                                                  context,
                                                  vm.retryPosSync(job.id),
                                                  success:
                                                      'Re-queued ${job.poNumber} for sync.',
                                                ),
                                          child: const Text('Retry sync'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                    ),
                  ],
                  side: [
                    AppSectionCard(
                      title: 'POS bridge connection',
                      icon: Icons.storefront_outlined,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AppInfoRow(
                            label: 'Target URL',
                            value: pos.baseUrl.isEmpty
                                ? 'Not configured'
                                : pos.baseUrl,
                          ),
                          if (pos.posReachable != null) ...[
                            const SizedBox(height: AppSpacing.sm),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: AppStatusChip(
                                label: pos.posReachable!
                                    ? 'POS reachable'
                                    : 'POS unreachable',
                                foreground: pos.posReachable!
                                    ? AppColors.success
                                    : AppColors.error,
                                background: pos.posReachable!
                                    ? AppColors.successContainer
                                    : AppColors.errorContainer,
                              ),
                            ),
                          ],
                          if (pos.probeError != null &&
                              pos.probeError!.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              pos.probeError!,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppColors.error),
                            ),
                          ],
                        ],
                      ),
                    ),
                    AppSectionCard(
                      title: 'Storage breakdown',
                      icon: Icons.pie_chart_outline,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AppInfoRow(
                            label: 'Database backups',
                            value: _formatBytes(storage.backupsBytes),
                          ),
                          AppInfoRow(
                            label: 'Site report photos',
                            value: _formatBytes(storage.reportsBytes),
                          ),
                          AppInfoRow(
                            label: 'Project documents',
                            value: _formatBytes(storage.documentsBytes),
                          ),
                          AppInfoRow(
                            label: 'Total private_media',
                            value: _formatBytes(storage.totalBytes),
                          ),
                        ],
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

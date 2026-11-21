import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/platform/desktop_files.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_padding.dart';
import '../../../shared/widgets/app_confirm_dialog.dart';
import '../../../shared/widgets/app_info_row.dart';
import '../../../shared/widgets/app_page_header.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../../../shared/widgets/app_status_chip.dart';
import '../../dashboard/widgets/dashboard_stat_tile.dart';
import '../viewmodels/system_backups_viewmodel.dart';
import '../widgets/admin_dashboard/admin_dashboard_kit.dart';

class SystemBackupsPage extends StatefulWidget {
  const SystemBackupsPage({super.key});

  @override
  State<SystemBackupsPage> createState() => _SystemBackupsPageState();
}

class _SystemBackupsPageState extends State<SystemBackupsPage> {
  final _formKey = GlobalKey<FormState>();
  final _retention = TextEditingController();
  late final _vm = SystemBackupsViewModel(getIt());

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _vm.load();
    final s = _vm.schedule;
    if (s == null || !mounted) return;
    _retention.text = '${s.retentionCount}';
  }

  @override
  void dispose() {
    _retention.dispose();
    _vm.dispose();
    super.dispose();
  }

  Future<void> _saveSchedule() async {
    if (!_formKey.currentState!.validate()) return;
    await reportAction(
      context,
      _vm.saveSchedule(retentionCount: int.parse(_retention.text.trim())),
      success: 'Backup schedule saved.',
    );
  }

  Future<void> _createBackup() async {
    await reportAction(
      context,
      _vm.createBackup(),
      success: 'Database snapshot created.',
    );
  }

  Future<void> _downloadBackup(String id, String filename) async {
    try {
      final bytes = await _vm.downloadBackupBytes(id);
      await saveAndOpenFile(filename, bytes);
      if (!mounted) return;
      showAppMessage(context, 'Downloaded $filename.');
    } catch (e) {
      if (!mounted) return;
      showAppMessage(context, '$e');
    }
  }

  Future<void> _restoreBackup(String id, String filename) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Restore database snapshot?',
      message:
          'This verifies the SHA-256 checksum of $filename and loads its records inside an atomic transaction.',
      confirmLabel: 'Restore',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await reportAction(
      context,
      _vm.restoreBackup(id),
      success: 'Database restored from snapshot.',
    );
  }

  Future<void> _uploadAndRestore() async {
    final controller = TextEditingController();
    final path = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Upload & restore backup'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Backup archive path (.json.gz or .json)',
              hintText: '/path/to/cpms_backup.json.gz',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Upload & restore'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (path == null || path.isEmpty || !mounted) return;
    try {
      final bytes = await readFileBytes(path);
      if (!mounted) return;
      await reportAction(
        context,
        _vm.uploadAndRestoreBackup(safeFileName(path), bytes),
        success: 'Uploaded backup restored.',
      );
    } catch (e) {
      if (!mounted) return;
      showAppMessage(context, '$e');
    }
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
      child: Consumer<SystemBackupsViewModel>(
        builder: (context, vm, _) {
          if (vm.isLoading) return const AdminTabSkeleton();
          if (vm.error != null) {
            return AdminErrorState(message: vm.error!, onRetry: _load);
          }
          final totalBytes = vm.backups.fold<int>(
            0,
            (sum, b) => sum + b.sizeBytes,
          );
          final schedule = vm.schedule;
          final freqLabel = switch (schedule?.frequency ?? 'daily') {
            'daily' => 'Daily',
            'weekly' => 'Weekly',
            _ => 'Manual only',
          };

          return RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: pagePadding(context),
              children: [
                AppPageHeader(
                  title: 'Database backups',
                  subtitle:
                      'Create verified server snapshots, download archives, and manage retention.',
                  actions: [
                    OutlinedButton.icon(
                      onPressed: vm.isBusy ? null : _uploadAndRestore,
                      icon: const Icon(Icons.upload_file_outlined, size: 18),
                      label: const Text('Upload & restore'),
                    ),
                    FilledButton.icon(
                      onPressed: vm.isBusy ? null : _createBackup,
                      icon: const Icon(Icons.add),
                      label: const Text('Create backup'),
                    ),
                  ],
                ),
                AdminStatGrid(
                  tiles: [
                    DashboardStatTile(
                      label: 'Server snapshots',
                      value: '${vm.backups.length}',
                      detail: 'Stored in private backups',
                      icon: Icons.backup_outlined,
                      color: AppColors.brandGoldText,
                    ),
                    DashboardStatTile(
                      label: 'Total storage',
                      value: _formatBytes(totalBytes),
                      detail: 'Compressed JSON archives',
                      icon: Icons.storage_outlined,
                    ),
                    DashboardStatTile(
                      label: 'Schedule',
                      value: freqLabel,
                      detail: 'Keep last ${schedule?.retentionCount ?? 7}',
                      icon: Icons.schedule_outlined,
                    ),
                    DashboardStatTile(
                      label: 'Last backup',
                      value: schedule?.lastBackupAt != null
                          ? Formatters.date(schedule!.lastBackupAt!)
                          : 'None yet',
                      detail: schedule?.lastBackupAt != null
                          ? Formatters.dateTime(schedule!.lastBackupAt!)
                          : 'Create your first snapshot',
                      icon: Icons.verified_outlined,
                      color: schedule?.lastBackupAt != null
                          ? AppColors.success
                          : AppColors.warning,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                AdminTwoColumn(
                  main: [
                    AppSectionCard(
                      title: 'Server snapshots',
                      icon: Icons.inventory_2_outlined,
                      subtitle: vm.backups.isEmpty
                          ? 'No archives on disk'
                          : '${vm.backups.length} verified '
                                '${vm.backups.length == 1 ? 'snapshot' : 'snapshots'}',
                      padding: EdgeInsets.zero,
                      child: vm.backups.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(AppSpacing.lg),
                              child: Text(
                                'No backups created yet. Click "Create backup" above to take a snapshot.',
                              ),
                            )
                          : Column(
                              children: [
                                for (final (i, b) in vm.backups.indexed) ...[
                                  if (i > 0) const Divider(height: 1),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.lg,
                                      vertical: AppSpacing.md,
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 38,
                                          height: 38,
                                          decoration: const BoxDecoration(
                                            color: AppColors.selected,
                                            borderRadius: AppRadii.mdAll,
                                          ),
                                          child: const Icon(
                                            Icons.archive_outlined,
                                            size: 20,
                                            color: AppColors.brandGoldText,
                                          ),
                                        ),
                                        const SizedBox(width: AppSpacing.md),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                b.filename,
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.titleSmall,
                                              ),
                                              const SizedBox(
                                                height: AppSpacing.xs,
                                              ),
                                              Wrap(
                                                spacing: AppSpacing.sm,
                                                runSpacing: AppSpacing.xs,
                                                crossAxisAlignment:
                                                    WrapCrossAlignment.center,
                                                children: [
                                                  AppStatusChip(
                                                    label: _formatBytes(
                                                      b.sizeBytes,
                                                    ),
                                                    foreground:
                                                        AppColors.textPrimary,
                                                    background:
                                                        AppColors.surfaceMuted,
                                                  ),
                                                  AppStatusChip(
                                                    label:
                                                        'SHA-256 ${b.sha256.length > 10 ? b.sha256.substring(0, 10) : b.sha256}…',
                                                    icon: Icons
                                                        .verified_user_outlined,
                                                    foreground:
                                                        AppColors.success,
                                                    background: AppColors
                                                        .successContainer,
                                                  ),
                                                  Text(
                                                    Formatters.dateTime(
                                                      b.createdAt,
                                                    ),
                                                    style: Theme.of(
                                                      context,
                                                    ).textTheme.bodySmall,
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: AppSpacing.sm),
                                        Wrap(
                                          spacing: AppSpacing.xs,
                                          children: [
                                            IconButton(
                                              tooltip: 'Download snapshot',
                                              icon: const Icon(
                                                Icons.download_outlined,
                                              ),
                                              onPressed: vm.isBusy
                                                  ? null
                                                  : () => _downloadBackup(
                                                      b.id,
                                                      b.filename,
                                                    ),
                                            ),
                                            OutlinedButton(
                                              onPressed: vm.isBusy
                                                  ? null
                                                  : () => _restoreBackup(
                                                      b.id,
                                                      b.filename,
                                                    ),
                                              child: const Text('Restore'),
                                            ),
                                          ],
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
                    Form(
                      key: _formKey,
                      child: AppSectionCard(
                        title: 'Automated backup schedule',
                        icon: Icons.schedule_outlined,
                        subtitle: 'Controls automated runs and snapshot pruning',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            DropdownButtonFormField<String>(
                              key: ValueKey(vm.frequency),
                              initialValue: vm.frequency,
                              decoration: const InputDecoration(
                                labelText: 'Frequency',
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'daily',
                                  child: Text('Daily'),
                                ),
                                DropdownMenuItem(
                                  value: 'weekly',
                                  child: Text('Weekly'),
                                ),
                                DropdownMenuItem(
                                  value: 'manual',
                                  child: Text('Manual only'),
                                ),
                              ],
                              onChanged: (v) {
                                if (v != null) vm.setFrequency(v);
                              },
                            ),
                            const SizedBox(height: AppSpacing.md),
                            TextFormField(
                              controller: _retention,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Retention count',
                                suffixText: 'snapshots',
                                helperText:
                                    'Older snapshots are pruned automatically (1–90).',
                              ),
                              validator: (raw) {
                                final val = int.tryParse((raw ?? '').trim());
                                if (val == null || val < 1 || val > 90) {
                                  return 'Enter a retention count between 1 and 90.';
                                }
                                return null;
                              },
                            ),
                            if (schedule?.lastBackupAt != null) ...[
                              const SizedBox(height: AppSpacing.md),
                              AppInfoRow(
                                label: 'Last snapshot',
                                value: Formatters.dateTime(
                                  schedule!.lastBackupAt!,
                                ),
                              ),
                            ],
                            const SizedBox(height: AppSpacing.lg),
                            FilledButton(
                              onPressed: vm.isBusy ? null : _saveSchedule,
                              child: const Text('Save schedule'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    AppSectionCard(
                      title: 'Integrity & restore safety',
                      icon: Icons.verified_user_outlined,
                      child: Text(
                        'Every snapshot is checksummed with SHA-256 on creation. '
                        'Restoring verifies the archive hash first and runs inside '
                        'a database transaction so partial restores cannot happen.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
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

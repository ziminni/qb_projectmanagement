import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/platform/desktop_files.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/models/project.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/repositories/schedule_repository.dart';
import '../../../data/services/session_service.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../widgets/dupa_import_dialog.dart';
import '../widgets/items_import_dialog.dart';

/// Import & Export hub for DPWH SF-INFR-41 Bar Chart templates (Original &
/// Variation Order Revised) and quick project schedule / DUPA imports.
class ImportExportPage extends StatefulWidget {
  const ImportExportPage({super.key});

  @override
  State<ImportExportPage> createState() => _ImportExportPageState();
}

class _ImportExportPageState extends State<ImportExportPage> {
  final _schedule = getIt<ScheduleRepository>();
  final _projectsRepo = getIt<ProjectRepository>();
  final _session = getIt<SessionService>();

  List<Project> _projects = const [];
  int? _selectedProjectId;
  bool _loadingProjects = true;
  String? _downloadingVariant;

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    try {
      final list = await _projectsRepo.getProjectsFor(
        _session.user!.id,
        _session.activeRole!,
      );
      if (!mounted) return;
      setState(() {
        _projects = list;
        _selectedProjectId = list.isNotEmpty ? list.first.id : null;
        _loadingProjects = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingProjects = false);
    }
  }

  Future<void> _exportTemplate({
    required String variant,
    required String fileName,
  }) async {
    setState(() => _downloadingVariant = variant);
    try {
      final bytes = await _schedule.downloadBarChartTemplate(variant: variant);
      if (bytes.isEmpty) {
        if (!mounted) return;
        showAppMessage(
          context,
          'Template download requires API mode (connect to the backend server).',
        );
        return;
      }
      final file = await saveToDownloadsAndOpen(fileName, bytes);
      if (!mounted) return;
      showSuccessAlert(context, 'Saved to ${file.path}');
    } catch (e) {
      if (!mounted) return;
      showAppMessage(context, 'Could not export template. $e');
    } finally {
      if (mounted) setState(() => _downloadingVariant = null);
    }
  }

  Future<void> _importBarChartIntoProject() async {
    final pid = _selectedProjectId;
    if (pid == null) return;
    final count = await ItemsImportDialog.show(context, projectId: pid);
    if (count == null || !mounted) return;
    showSuccessAlert(
      context,
      'Imported $count item${count == 1 ? '' : 's'} of work.',
    );
  }

  Future<void> _importDupaIntoProject() async {
    final pid = _selectedProjectId;
    if (pid == null) return;
    final result = await DupaImportDialog.show(context, projectId: pid);
    if (result == null || !mounted) return;
    showSuccessAlert(
      context,
      'Imported DUPA (${result.itemsImported} item(s), '
      '${result.materialsImported} planned material(s)).',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final exportCard = AppSectionCard(
      title: 'Export Bar Chart Templates (.xlsx)',
      subtitle:
          'Exact DPWH SF-INFR-41 template with formulas, blue bar conditional formatting, and S-Curve',
      icon: Icons.file_download_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TemplateRow(
            title: 'Original Bar Chart Template',
            badge: 'Sheet: ORIGINAL',
            description:
                'First / baseline Gantt schedule (120 calendar days). Use this '
                'when creating a new project so Target End Date and Contract '
                'Amount auto-fill.',
            fileName: 'DPWH_Bar_Chart_Original_Template.xlsx',
            busy: _downloadingVariant == 'original',
            disabled: _downloadingVariant != null,
            onExport: () => _exportTemplate(
              variant: 'original',
              fileName: 'DPWH_Bar_Chart_Original_Template.xlsx',
            ),
          ),
          const Divider(height: AppSpacing.xl),
          _TemplateRow(
            title: 'Variation Order Revised Bar Chart Template',
            badge: 'Sheet: REVISED (VO)',
            description:
                'Revised Gantt schedule for raising a Variation Order (+23cd '
                'realignment example). Upload this in Variation Orders to '
                'auto-flag every changed item.',
            fileName: 'DPWH_Bar_Chart_VO_Revised_Template.xlsx',
            busy: _downloadingVariant == 'revised',
            disabled: _downloadingVariant != null,
            onExport: () => _exportTemplate(
              variant: 'revised',
              fileName: 'DPWH_Bar_Chart_VO_Revised_Template.xlsx',
            ),
          ),
          const Divider(height: AppSpacing.xl),
          _TemplateRow(
            title: 'Combined Bar Chart Workbook (Original + VO Revised)',
            badge: '2 Sheets: ORIGINAL & REVISED (VO)',
            description:
                'Both the Original baseline sheet and the Variation Order '
                'Revised sheet in a single Excel workbook — choose which sheet '
                'to import from the Sheet dropdown.',
            fileName: 'DPWH_Bar_Chart_Combined_Template.xlsx',
            busy: _downloadingVariant == 'combined',
            disabled: _downloadingVariant != null,
            onExport: () => _exportTemplate(
              variant: 'combined',
              fileName: 'DPWH_Bar_Chart_Combined_Template.xlsx',
            ),
          ),
        ],
      ),
    );

    final importCard = AppSectionCard(
      title: 'Import Schedules & DUPA',
      subtitle:
          'Start a new project or Variation Order from Excel, or import directly into an existing project',
      icon: Icons.file_upload_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton.icon(
                onPressed: () => context.go(AppRoutes.projectNew),
                icon: const Icon(Icons.add_business_outlined, size: 18),
                label: const Text('New project with Bar Chart'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => context.go(AppRoutes.variationOrderNew),
                icon: const Icon(Icons.difference_outlined, size: 18),
                label: const Text('New Variation Order (Revised Bar Chart)'),
              ),
            ],
          ),
          const Divider(height: AppSpacing.xl),
          Text(
            'Import into an existing project',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_loadingProjects)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: LinearProgressIndicator(),
            )
          else if (_projects.isEmpty)
            Text(
              'No projects yet. Create a project above first to import schedules or DUPA files into it.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: _selectedProjectId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Target project',
                    isDense: true,
                  ),
                  items: [
                    for (final p in _projects)
                      DropdownMenuItem(
                        value: p.id,
                        child: Text(
                          '${p.code} · ${p.name}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _selectedProjectId = v),
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _selectedProjectId == null
                          ? null
                          : _importBarChartIntoProject,
                      icon: const Icon(Icons.upload_file_rounded, size: 18),
                      label: const Text('Import Bar Chart'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _selectedProjectId == null
                          ? null
                          : _importDupaIntoProject,
                      icon: const Icon(Icons.table_chart_outlined, size: 18),
                      label: const Text('Import DUPA (A–J)'),
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );

    return ListView(
      padding: pagePadding(context),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 980) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: exportCard),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(flex: 5, child: importCard),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                exportCard,
                const SizedBox(height: AppSpacing.lg),
                importCard,
              ],
            );
          },
        ),
      ],
    );
  }
}

class _TemplateRow extends StatelessWidget {
  const _TemplateRow({
    required this.title,
    required this.badge,
    required this.description,
    required this.fileName,
    required this.busy,
    required this.disabled,
    required this.onExport,
  });

  final String title;
  final String badge;
  final String description;
  final String fileName;
  final bool busy;
  final bool disabled;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(title, style: theme.textTheme.titleSmall),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: const BoxDecoration(
                      color: AppColors.primaryContainer,
                      borderRadius: AppRadii.smAll,
                    ),
                    child: Text(
                      badge,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        FilledButton.tonalIcon(
          onPressed: disabled ? null : onExport,
          icon: busy
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download_rounded, size: 18),
          label: const Text('Export template'),
        ),
      ],
    );
  }
}

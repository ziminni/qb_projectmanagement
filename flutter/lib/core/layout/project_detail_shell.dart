import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../data/models/app_role.dart';
import '../../data/models/project.dart';
import '../../data/repositories/project_repository.dart';
import '../../data/services/session_service.dart';
import '../../routes/routes.dart';
import '../../shared/widgets/app_empty_state.dart';
import '../../shared/widgets/app_project_status_chip.dart';
import '../constants/app_colors.dart';
import '../constants/app_radii.dart';
import '../utils/formatters.dart';
import '../utils/page_padding.dart';
import '../constants/app_spacing.dart';
import '../di/service_locator.dart';
import 'project_tabs.dart';

/// Loads the project shown in the detail shell and checks the user may see
/// it. Tab pages call [reload] after changing the project's header data.
class ProjectDetailController extends ChangeNotifier {
  ProjectDetailController({
    required this.projectId,
    required ProjectRepository projects,
    required SessionService session,
  }) : _projects = projects,
       _session = session;

  final int projectId;
  final ProjectRepository _projects;
  final SessionService _session;

  Project? project;
  String? error;
  bool isLoading = true;

  Future<void> reload() async {
    try {
      project = await _projects.getProject(projectId);
      final role = _session.activeRole!;
      if (project == null) {
        error = 'Project not found.';
      } else if ((role == AppRole.owner || role == AppRole.siteEngineer) &&
          !await _projects.isAssigned(projectId, _session.user!.id, role)) {
        error = 'You are not assigned to this project.';
      } else {
        error = null;
      }
    } catch (e) {
      error = 'Could not load the project. $e';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}

/// Shell for a project's detail tabs: header plus the tabs the active role
/// may see.
class ProjectDetailShell extends StatefulWidget {
  const ProjectDetailShell({
    super.key,
    required this.projectId,
    required this.tab,
    required this.child,
  });

  final int projectId;
  final ProjectTab tab;
  final Widget child;

  @override
  State<ProjectDetailShell> createState() => _ProjectDetailShellState();
}

class _ProjectDetailShellState extends State<ProjectDetailShell> {
  late ProjectDetailController _controller = _create();

  ProjectDetailController _create() => ProjectDetailController(
    projectId: widget.projectId,
    projects: getIt(),
    session: getIt(),
  )..reload();

  @override
  void didUpdateWidget(ProjectDetailShell old) {
    super.didUpdateWidget(old);
    if (old.projectId != widget.projectId) {
      _controller.dispose();
      _controller = _create();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final role = context.watch<SessionService>().activeRole!;
    final tabs = ProjectTab.visibleTo(role);
    return ChangeNotifierProvider.value(
      value: _controller,
      child: Consumer<ProjectDetailController>(
        builder: (context, c, _) {
          if (c.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (c.error != null) {
            return AppEmptyState(message: c.error!, icon: Icons.lock_outline);
          }
          final project = c.project!;
          final textTheme = Theme.of(context).textTheme;
          final side = pagePadding(context).left;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Material(
                color: Theme.of(context).colorScheme.surface,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        side,
                        AppSpacing.xl,
                        side,
                        AppSpacing.sm,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: const BoxDecoration(
                              gradient: AppColors.brandGradient,
                              borderRadius: AppRadii.lgAll,
                            ),
                            child: const Icon(
                              Icons.apartment_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.lg),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: AppSpacing.sm,
                                  runSpacing: AppSpacing.xs,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      project.code,
                                      style: textTheme.labelMedium,
                                    ),
                                    AppProjectStatusChip(
                                      status: project.status,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  project.name,
                                  style: textTheme.headlineSmall,
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Wrap(
                                  spacing: AppSpacing.lg,
                                  runSpacing: AppSpacing.xs,
                                  children: [
                                    _meta(
                                      context,
                                      Icons.place_outlined,
                                      project.location,
                                    ),
                                    _meta(
                                      context,
                                      Icons.event_outlined,
                                      Formatters.dateRange(
                                        project.startDate,
                                        project.targetEndDate,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    DefaultTabController(
                      key: ValueKey(widget.tab),
                      length: tabs.length,
                      initialIndex: tabs
                          .indexOf(widget.tab)
                          .clamp(0, tabs.length - 1),
                      child: TabBar(
                        padding: EdgeInsets.symmetric(
                          horizontal: side - AppSpacing.lg,
                        ),
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        onTap: (i) => context.go(
                          AppRoutes.projectTab(widget.projectId, tabs[i]),
                        ),
                        tabs: [for (final t in tabs) Tab(text: t.label)],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: widget.child),
            ],
          );
        },
      ),
    );
  }

  Widget _meta(BuildContext context, IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: AppColors.textSecondary),
      const SizedBox(width: AppSpacing.xs),
      Flexible(
        child: Text(
          text,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
      ),
    ],
  );
}

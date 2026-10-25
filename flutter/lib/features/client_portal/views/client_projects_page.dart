import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/page_padding.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../viewmodels/client_projects_viewmodel.dart';
import '../widgets/client_portal_project_card.dart';

class ClientProjectsPage extends StatelessWidget {
  const ClientProjectsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ClientProjectsViewModel(
        session: getIt(),
        projects: getIt(),
        schedule: getIt(),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<ClientProjectsViewModel>();
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (vm.items.isEmpty) {
          return const AppEmptyState(
            message: 'No projects are linked to your account yet.',
          );
        }
        return ListView(
          padding: pagePadding(context),
          children: [
            for (final s in vm.items) ...[
              ClientPortalProjectCard(
                project: s.project,
                progress: s.progress,
                onTap: () =>
                    context.go(AppRoutes.clientProgressFor(s.project.id)),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ],
        );
      },
    );
  }
}

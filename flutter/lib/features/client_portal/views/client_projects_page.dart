import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/models/project_assignment.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_confirm_dialog.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_project_request_card.dart';
import '../../../shared/widgets/app_reason_dialog.dart';
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
        if (vm.items.isEmpty && vm.requests.isEmpty) {
          return const AppEmptyState(
            message: 'No projects are linked to your account yet.',
          );
        }
        return ListView(
          padding: pagePadding(context),
          children: [
            for (final r in vm.requests) ...[
              AppProjectRequestCard(
                project: r.project,
                showAmount: true,
                busy: vm.isBusy,
                onAccept: () => reportAction(
                  context,
                  vm.respond(r, answer: RequestResponse.accepted),
                  success: 'Request accepted.',
                ),
                onRequestChanges: () => _requestChanges(
                  context,
                  (note) => vm.respond(
                    r,
                    answer: RequestResponse.changesRequested,
                    note: note,
                  ),
                ),
                onDecline: () => _decline(
                  context,
                  r.project.name,
                  (reason) => vm.respond(
                    r,
                    answer: RequestResponse.declined,
                    note: reason,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
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

Future<void> _requestChanges(
  BuildContext context,
  Future<String?> Function(String note) respond,
) async {
  final note = await AppReasonDialog.show(
    context,
    title: 'Request changes',
    label: 'What needs to change?',
    confirmLabel: 'Send to owner',
    message:
        'The owner revises the project and sends it back to you for approval.',
  );
  if (note != null && context.mounted) {
    await reportAction(
      context,
      respond(note),
      success: 'Your requested changes were sent to the owner.',
    );
  }
}

/// Declining deletes the project, so it asks for a reason and then for
/// confirmation.
Future<void> _decline(
  BuildContext context,
  String projectName,
  Future<String?> Function(String reason) respond,
) async {
  final reason = await AppReasonDialog.show(
    context,
    title: 'Decline project',
    label: 'Reason for declining',
    confirmLabel: 'Continue',
    message: 'The owner sees your reason.',
  );
  if (reason == null || !context.mounted) return;
  final confirmed = await showAppConfirmDialog(
    context,
    title: 'Delete this project request?',
    message:
        'Declining deletes "$projectName". The owner is told your reason. '
        'This cannot be undone.',
    confirmLabel: 'Decline and delete',
    destructive: true,
  );
  if (confirmed && context.mounted) {
    await reportAction(
      context,
      respond(reason),
      success: 'Project declined and deleted.',
    );
  }
}

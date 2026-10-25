import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/page_padding.dart';
import '../../../shared/widgets/app_confirm_dialog.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../viewmodels/project_documents_viewmodel.dart';
import '../widgets/documents_tile.dart';
import '../widgets/documents_upload_dialog.dart';

/// Project "Documents" tab.
class ProjectDocumentsPage extends StatelessWidget {
  const ProjectDocumentsPage({super.key, required this.projectId});

  final int projectId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      key: ValueKey(projectId),
      create: (_) => ProjectDocumentsViewModel(
        projectId: projectId,
        session: getIt(),
        documents: getIt(),
        users: getIt(),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<ProjectDocumentsViewModel>();
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        final groups = vm.grouped;
        return ListView(
          padding: pagePadding(context),
          children: [
            if (vm.canUpload)
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: () async {
                    final input = await DocumentsUploadDialog.show(context);
                    if (input != null && context.mounted) {
                      await reportAction(
                        context,
                        vm.upload(
                          name: input.name,
                          type: input.type,
                          fileName: input.fileName,
                        ),
                        success: 'Document uploaded.',
                      );
                    }
                  },
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Upload document'),
                ),
              ),
            const SizedBox(height: AppSpacing.lg),
            if (groups.isEmpty)
              const AppEmptyState(
                message: 'No documents yet.',
                icon: Icons.folder_open,
              ),
            for (final e in groups.entries) ...[
              AppSectionCard(
                title: '${e.key.label} (${e.value.length})',
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final d in e.value)
                      DocumentsTile(
                        document: d,
                        uploadedBy: vm.userName(d.uploadedBy),
                        onOpen: () => showAppMessage(
                          context,
                          '${d.fileName}: file preview arrives with file storage.',
                        ),
                        onDelete: vm.canDelete(d)
                            ? () async {
                                final ok = await showAppConfirmDialog(
                                  context,
                                  title: 'Delete ${d.name}?',
                                  message:
                                      'The file is removed from the project.',
                                  confirmLabel: 'Delete',
                                  destructive: true,
                                );
                                if (ok && context.mounted) {
                                  await reportAction(context, vm.delete(d));
                                }
                              }
                            : null,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ],
        );
      },
    );
  }
}

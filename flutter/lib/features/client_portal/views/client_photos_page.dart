import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_padding.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_photo_tile.dart';
import '../viewmodels/client_photos_viewmodel.dart';

/// Photo gallery from approved daily reports.
class ClientPhotosPage extends StatelessWidget {
  const ClientPhotosPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ClientPhotosViewModel(
        session: getIt(),
        projects: getIt(),
        reports: getIt(),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<ClientPhotosViewModel>();
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: pagePadding(context),
          children: [
            if (vm.projectsById.length > 1) ...[
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  ChoiceChip(
                    label: const Text('All projects'),
                    selected: vm.projectFilter == null,
                    onSelected: (_) => vm.setProject(null),
                  ),
                  for (final p in vm.projectsById.values)
                    ChoiceChip(
                      label: Text(p.name),
                      selected: vm.projectFilter == p.id,
                      onSelected: (_) => vm.setProject(p.id),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            if (vm.photos.isEmpty)
              const AppEmptyState(
                message: 'No site photos yet.',
                icon: Icons.photo_library_outlined,
              )
            else
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final p in vm.photos)
                    AppPhotoTile(
                      fileUrl: p.photo.fileUrl,
                      caption: p.photo.caption,
                      subtitle: Formatters.date(p.report.reportDate),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}

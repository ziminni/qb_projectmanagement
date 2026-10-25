import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_padding.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_payment_dialog.dart';
import '../../../shared/widgets/app_project_status_chip.dart';
import '../viewmodels/retention_viewmodel.dart';

/// Retention tracker: withheld on approved billings, released after
/// completion.
class RetentionPage extends StatelessWidget {
  const RetentionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => RetentionViewModel(
        session: getIt(),
        projects: getIt(),
        billing: getIt(),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<RetentionViewModel>();
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: pagePadding(context),
          children: [
            Text(
              'Retention held: ${Formatters.peso(vm.totalBalance)}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (vm.rows.isEmpty)
              const AppEmptyState(message: 'No retention is held.')
            else
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final (i, r) in vm.rows.indexed) ...[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        title: Text('${r.project.code} · ${r.project.name}'),
                        subtitle: Text(
                          'Withheld ${Formatters.peso(r.held)} · released '
                          '${Formatters.peso(r.released)}'
                          '${r.releaseBlocker != null && r.balance > 0 ? '\n${r.releaseBlocker}' : ''}',
                        ),
                        isThreeLine: r.releaseBlocker != null && r.balance > 0,
                        trailing: Wrap(
                          spacing: AppSpacing.sm,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            AppProjectStatusChip(status: r.project.status),
                            Text(Formatters.peso(r.balance)),
                            if (vm.canRelease && r.balance > 0)
                              FilledButton.tonal(
                                onPressed: r.releaseBlocker != null
                                    ? null
                                    : () async {
                                        final input =
                                            await AppPaymentDialog.show(
                                              context,
                                              title: 'Release retention',
                                              balance: r.balance,
                                              validateAmount: (a) =>
                                                  vm.validateAmount(r, a),
                                            );
                                        if (input != null && context.mounted) {
                                          await reportAction(
                                            context,
                                            vm.release(r, input),
                                            success: 'Retention released.',
                                          );
                                        }
                                      },
                                child: const Text('Release'),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

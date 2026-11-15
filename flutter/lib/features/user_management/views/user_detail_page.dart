import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_padding.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/widgets/app_confirm_dialog.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_info_row.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../../../shared/widgets/app_status_chip.dart';
import '../viewmodels/admin_audit.dart';
import '../viewmodels/user_detail_viewmodel.dart';
import '../widgets/user_management_audit_tile.dart';

/// Read-only view of one user, with the admin's account actions.
class UserDetailPage extends StatelessWidget {
  const UserDetailPage({super.key, required this.userId});

  final int userId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => UserDetailViewModel(
        userId: userId,
        users: getIt(),
        projects: getIt(),
        clients: getIt(),
        auditLog: getIt(),
        auth: getIt(),
        session: getIt(),
        audit: AdminAudit.fromLocator(),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<UserDetailViewModel>();
        if (vm.isLoading && vm.user == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (vm.error != null) return AppEmptyState(message: vm.error!);
        final user = vm.user!;
        final wide =
            MediaQuery.sizeOf(context).width >= AppSpacing.wideBreakpoint;

        final account = AppSectionCard(
          title: 'Account',
          icon: Icons.person_outline,
          child: Column(
            children: [
              AppInfoRow(label: 'Email', value: user.email),
              AppInfoRow(label: 'Phone', value: user.phone ?? '—'),
              AppInfoRow(
                label: 'Roles',
                value: vm.roles.isEmpty
                    ? 'None'
                    : vm.roles.map((r) => r.label).join(', '),
              ),
              if (vm.client != null)
                AppInfoRow(label: 'Client account', value: vm.client!.name),
              AppInfoRow(
                label: 'Member since',
                value: user.createdAt == null
                    ? '—'
                    : Formatters.date(user.createdAt!),
              ),
            ],
          ),
        );

        final assignments = AppSectionCard(
          title: 'Project assignments',
          icon: Icons.apartment_outlined,
          padding: EdgeInsets.zero,
          child: vm.assignments.isEmpty
              ? const ListTile(title: Text('Not assigned to any project.'))
              : Column(
                  children: [
                    for (final (a, p) in vm.assignments)
                      ListTile(
                        leading: const Icon(Icons.apartment_outlined),
                        title: Text(p?.name ?? 'Project #${a.projectId}'),
                        subtitle: Text(
                          '${a.roleOnProject.label} · ${a.response.label}',
                        ),
                      ),
                  ],
                ),
        );

        final security = AppSectionCard(
          title: 'Access',
          icon: Icons.lock_outline,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                user.isActive
                    ? 'This user can sign in.'
                    : 'This account is deactivated and cannot sign in.',
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  OutlinedButton.icon(
                    onPressed: vm.isBusy ? null : () => _reset(context, vm),
                    icon: const Icon(Icons.key_outlined),
                    label: const Text('Reset password'),
                  ),
                  if (user.isActive)
                    OutlinedButton.icon(
                      onPressed: vm.isBusy || vm.isSelf
                          ? null
                          : () => _setActive(context, vm, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                      ),
                      icon: const Icon(Icons.person_off_outlined),
                      label: const Text('Deactivate'),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: vm.isBusy
                          ? null
                          : () => _setActive(context, vm, true),
                      icon: const Icon(Icons.person_outline),
                      label: const Text('Reactivate'),
                    ),
                ],
              ),
              if (vm.isSelf) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'You cannot deactivate your own account.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        );

        final activity = AppSectionCard(
          title: 'Activity',
          icon: Icons.history,
          subtitle: 'Actions by this user and changes to their account.',
          padding: EdgeInsets.zero,
          child: vm.activity.isEmpty
              ? const ListTile(title: Text('No recorded activity yet.'))
              : Column(
                  children: [
                    for (final l in vm.activity.take(15))
                      UserManagementAuditTile(
                        log: l,
                        userName: vm.nameOf(l.userId),
                      ),
                  ],
                ),
        );

        return ListView(
          padding: pagePadding(context),
          children: [
            _Header(vm: vm),
            const SizedBox(height: AppSpacing.xl),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      children: [
                        account,
                        const SizedBox(height: AppSpacing.lg),
                        assignments,
                        const SizedBox(height: AppSpacing.lg),
                        activity,
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(flex: 2, child: security),
                ],
              )
            else ...[
              account,
              const SizedBox(height: AppSpacing.lg),
              security,
              const SizedBox(height: AppSpacing.lg),
              assignments,
              const SizedBox(height: AppSpacing.lg),
              activity,
            ],
          ],
        );
      },
    );
  }

  Future<void> _setActive(
    BuildContext context,
    UserDetailViewModel vm,
    bool active,
  ) async {
    final name = vm.user!.fullName;
    final ok = await showAppConfirmDialog(
      context,
      title: active ? 'Reactivate $name?' : 'Deactivate $name?',
      message: active
          ? 'They will be able to sign in again with their current password.'
          : 'They will be signed out of new sessions and cannot sign in until '
                'reactivated. Their records and history are kept.',
      confirmLabel: active ? 'Reactivate' : 'Deactivate',
      destructive: !active,
    );
    if (!ok || !context.mounted) return;
    await reportAction(
      context,
      vm.setActive(active),
      success: active ? '$name reactivated.' : '$name deactivated.',
    );
  }

  Future<void> _reset(BuildContext context, UserDetailViewModel vm) async {
    final name = vm.user!.fullName;
    final ok = await showAppConfirmDialog(
      context,
      title: 'Reset password for $name?',
      message:
          'Their current password stops working. Give them the '
          'temporary password so they can sign in and change it.',
      confirmLabel: 'Reset password',
    );
    if (!ok || !context.mounted) return;
    final done = await reportAction(context, vm.resetPassword());
    if (!done || !context.mounted) return;
    final temp = vm.temporaryPassword!;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Temporary password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Share this with $name. They should change it after '
              'signing in.',
            ),
            const SizedBox(height: AppSpacing.md),
            SelectableText(temp, style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: temp));
              Navigator.of(context).pop();
              showAppMessage(context, 'Password copied.');
            },
            child: const Text('Copy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.vm});
  final UserDetailViewModel vm;

  @override
  Widget build(BuildContext context) {
    final user = vm.user!;
    final textTheme = Theme.of(context).textTheme;
    return Wrap(
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.md,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppAvatar(name: user.fullName, size: 56),
            const SizedBox(width: AppSpacing.lg),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.fullName, style: textTheme.headlineSmall),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      user.isActive
                          ? const AppStatusChip(
                              label: 'Active',
                              foreground: AppColors.success,
                              background: AppColors.successContainer,
                            )
                          : const AppStatusChip(
                              label: 'Inactive',
                              foreground: AppColors.textSecondary,
                              background: AppColors.surfaceMuted,
                            ),
                      for (final r in vm.roles)
                        AppStatusChip(
                          label: r.label,
                          foreground: AppColors.brandGoldText,
                          background: AppColors.selected,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        FilledButton.icon(
          onPressed: () => context.go(AppRoutes.adminUserEdit(user.id)),
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Edit user'),
        ),
      ],
    );
  }
}

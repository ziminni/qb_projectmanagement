import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/models/app_role.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../viewmodels/users_viewmodel.dart';
import '../widgets/user_management_user_tile.dart';

class UsersPage extends StatelessWidget {
  const UsersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => UsersViewModel(users: getIt(), session: getIt())..load(),
      builder: (context, _) {
        final vm = context.watch<UsersViewModel>();
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (vm.error != null) return AppEmptyState(message: vm.error!);
        final items = vm.items;
        return ListView(
          padding: pagePadding(context),
          children: [
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 320,
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search name or email',
                    ),
                    onChanged: vm.setQuery,
                  ),
                ),
                SizedBox(
                  width: 240,
                  child: DropdownButtonFormField<AppRole?>(
                    initialValue: vm.roleFilter,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All roles'),
                      ),
                      for (final r in AppRole.values)
                        DropdownMenuItem(value: r, child: Text(r.label)),
                    ],
                    onChanged: vm.setRoleFilter,
                  ),
                ),
                FilterChip(
                  label: const Text('Show inactive'),
                  selected: vm.showInactive,
                  onSelected: vm.setShowInactive,
                ),
                FilledButton.icon(
                  onPressed: () => context.go(AppRoutes.adminUserNew),
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('Add user'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            if (items.isEmpty)
              const AppEmptyState(message: 'No users match these filters.')
            else
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final (i, item) in items.indexed) ...[
                      if (i > 0) const Divider(height: 1),
                      UserManagementUserTile(
                        user: item.user,
                        roles: item.roles,
                        onTap: () =>
                            context.go(AppRoutes.adminUser(item.user.id)),
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

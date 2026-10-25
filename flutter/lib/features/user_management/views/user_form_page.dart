import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/widgets/app_action_bar.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/models/app_role.dart';
import '../../../data/services/auth_rules.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../viewmodels/user_form_viewmodel.dart';
import '../widgets/user_management_assignment_editor.dart';
import '../widgets/user_management_role_selector.dart';

class UserFormPage extends StatefulWidget {
  const UserFormPage({super.key, this.userId});

  /// Null to create a user.
  final int? userId;

  @override
  State<UserFormPage> createState() => _UserFormPageState();
}

class _UserFormPageState extends State<UserFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  late final _vm = UserFormViewModel(
    userId: widget.userId,
    users: getIt(),
    projects: getIt(),
    clients: getIt(),
    session: getIt(),
  );

  @override
  void initState() {
    super.initState();
    _vm.load().then((_) {
      final user = _vm.user;
      if (user == null) return;
      _name.text = user.fullName;
      _email.text = user.email;
      _phone.text = user.phone ?? '';
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _vm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await reportAction(
      context,
      _vm.save(fullName: _name.text, email: _email.text, phone: _phone.text),
      success: 'User saved.',
    );
    if (ok && mounted) context.go(AppRoutes.adminUsers);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Consumer<UserFormViewModel>(
        builder: (context, vm, _) {
          if (vm.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (vm.error != null) return AppEmptyState(message: vm.error!);
          return Form(
            key: _formKey,
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: pagePadding(context),
                    children: [
                      AppSectionCard(
                        title: vm.isNew ? 'New user' : 'Account',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: _name,
                              decoration: const InputDecoration(
                                labelText: 'Full name',
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Enter the full name.'
                                  : null,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            TextFormField(
                              controller: _email,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                              ),
                              keyboardType: TextInputType.emailAddress,
                              validator: AuthRules.validateEmail,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            TextFormField(
                              controller: _phone,
                              decoration: const InputDecoration(
                                labelText: 'Phone',
                              ),
                              keyboardType: TextInputType.phone,
                            ),
                            if (vm.isNew) ...[
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                'New users receive a temporary password by email. '
                                'In this mock build it is password123.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Active'),
                              subtitle: const Text(
                                'Inactive users cannot sign in.',
                              ),
                              value: vm.isActive,
                              onChanged: vm.isSelf ? null : vm.setActive,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      AppSectionCard(
                        title: 'Roles',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            UserManagementRoleSelector(
                              selected: vm.roles,
                              onChanged: vm.toggleRole,
                            ),
                            if (vm.roles.contains(AppRole.client)) ...[
                              const SizedBox(height: AppSpacing.lg),
                              DropdownButtonFormField<int>(
                                initialValue: vm.clientId,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Client this login belongs to',
                                ),
                                items: [
                                  for (final c in vm.clients)
                                    DropdownMenuItem(
                                      value: c.id,
                                      child: Text(c.name),
                                    ),
                                ],
                                onChanged: vm.setClient,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      AppSectionCard(
                        title: 'Project assignments',
                        child: UserManagementAssignmentEditor(
                          assignments: vm.assignments,
                          roles: vm.assignableRoles,
                          projectById: vm.projectById,
                          projectsFor: vm.projectsFor,
                          onAdd: vm.addAssignment,
                          onRemove: vm.removeAssignment,
                        ),
                      ),
                    ],
                  ),
                ),
                AppActionBar(
                  children: [
                    TextButton(
                      onPressed: () => context.go(AppRoutes.adminUsers),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: vm.isBusy ? null : _save,
                      child: Text(vm.isNew ? 'Create user' : 'Save changes'),
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

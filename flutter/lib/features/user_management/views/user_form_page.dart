import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/widgets/app_action_bar.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/services/auth_rules.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../viewmodels/admin_audit.dart';
import '../viewmodels/user_form_viewmodel.dart';
import '../widgets/user_management_role_selector.dart';
import '../widgets/admin_dashboard/admin_dashboard_kit.dart';

class UserFormPage extends StatefulWidget {
  const UserFormPage({super.key, this.userId, this.clientId});

  /// Null to create a user.
  final int? userId;

  /// New user only: a portal login for this client (from `?client=`).
  final int? clientId;

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
    prefillClientId: widget.clientId,
    users: getIt(),
    projects: getIt(),
    clients: getIt(),
    session: getIt(),
    audit: AdminAudit.fromLocator(),
  );

  @override
  void initState() {
    super.initState();
    _vm.load().then((_) {
      final client = _vm.prefillClient;
      if (client != null) {
        _name.text = client.contactPerson ?? client.name;
        _email.text = client.email ?? '';
        _phone.text = client.phone ?? '';
      }
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
    final isNew = widget.userId == null;
    final ok = await reportAction(
      context,
      _vm.save(fullName: _name.text, email: _email.text, phone: _phone.text),
      success: isNew ? null : 'User saved.',
    );
    if (!ok || !mounted) return;
    if (isNew) {
      final email = _email.text.trim().toLowerCase();
      final temp = _vm.temporaryPassword;
      if (temp != null && temp.isNotEmpty) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('User created'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'An email with these sign-in credentials has been sent to $email. They will be prompted to set a new password on their first login.',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        dialogContext,
                      ).colorScheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(
                          dialogContext,
                        ).colorScheme.outlineVariant,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Email',
                          style: Theme.of(dialogContext).textTheme.labelSmall,
                        ),
                        SelectableText(
                          email,
                          style: Theme.of(dialogContext).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Temporary password',
                          style: Theme.of(dialogContext).textTheme.labelSmall,
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: SelectableText(
                                temp,
                                style: Theme.of(dialogContext)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.6,
                                    ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Copy credentials',
                              icon: const Icon(Icons.copy_rounded, size: 18),
                              onPressed: () {
                                Clipboard.setData(
                                  ClipboardData(
                                    text: 'Email: $email\nPassword: $temp',
                                  ),
                                );
                                showSuccessAlert(
                                  dialogContext,
                                  'Email and temporary password copied.',
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Done'),
              ),
            ],
          ),
        );
      } else {
        showSuccessAlert(
          context,
          'User created and credentials email sent to $email.',
        );
      }
    }
    if (!mounted) return;
    context.go(
      widget.userId == null
          ? AppRoutes.adminUsers
          : AppRoutes.adminUser(widget.userId!),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Consumer<UserFormViewModel>(
        builder: (context, vm, _) {
          if (vm.isLoading) {
            return const AdminTabSkeleton();
          }
          if (vm.error != null) {
            return AdminErrorState(message: vm.error!, onRetry: vm.load);
          }
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
                            if (!vm.isNew)
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
                        child: UserManagementRoleSelector(
                          selected: vm.roles,
                          onChanged: vm.toggleRole,
                        ),
                      ),
                    ],
                  ),
                ),
                AppActionBar(
                  children: [
                    TextButton(
                      onPressed: () => context.go(
                        widget.userId == null
                            ? AppRoutes.adminUsers
                            : AppRoutes.adminUser(widget.userId!),
                      ),
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

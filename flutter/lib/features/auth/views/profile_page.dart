import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/page_padding.dart';
import '../../../shared/widgets/app_info_row.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../viewmodels/profile_viewmodel.dart';
import '../widgets/auth_change_password_dialog.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _formKey = GlobalKey<FormState>();
  late final _vm = ProfileViewModel(
    session: getIt(),
    users: getIt(),
    auth: getIt(),
  );
  late final _name = TextEditingController(text: _vm.user.fullName);
  late final _phone = TextEditingController(text: _vm.user.phone);

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _vm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    await reportAction(
      context,
      _vm.saveProfile(fullName: _name.text, phone: _phone.text),
      success: 'Profile saved.',
    );
  }

  Future<void> _changePassword() async {
    final result = await AuthChangePasswordDialog.show(context);
    if (result == null || !mounted) return;
    await reportAction(
      context,
      _vm.changePassword(
        currentPassword: result.currentPassword,
        newPassword: result.newPassword,
      ),
      success: 'Password changed.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Consumer<ProfileViewModel>(
        builder: (context, vm, _) => ListView(
          padding: pagePadding(context),
          children: [
            AppSectionCard(
              title: 'My profile',
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _name,
                      decoration: const InputDecoration(labelText: 'Full name'),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Enter your name.'
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    TextFormField(
                      controller: _phone,
                      decoration: const InputDecoration(labelText: 'Phone'),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    AppInfoRow(label: 'Email', value: vm.user.email),
                    AppInfoRow(
                      label: 'Roles',
                      value: vm.roles.map((r) => r.label).join(', '),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        FilledButton(
                          onPressed: vm.isBusy ? null : _save,
                          child: const Text('Save'),
                        ),
                        OutlinedButton(
                          onPressed: vm.isBusy ? null : _changePassword,
                          child: const Text('Change password'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

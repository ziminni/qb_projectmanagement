import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../data/services/auth_rules.dart';

class AuthChangePasswordResult {
  const AuthChangePasswordResult(this.currentPassword, this.newPassword);

  final String currentPassword;
  final String newPassword;
}

class AuthChangePasswordDialog extends StatefulWidget {
  const AuthChangePasswordDialog({super.key});

  static Future<AuthChangePasswordResult?> show(BuildContext context) =>
      showDialog<AuthChangePasswordResult>(
        context: context,
        builder: (_) => const AuthChangePasswordDialog(),
      );

  @override
  State<AuthChangePasswordDialog> createState() =>
      _AuthChangePasswordDialogState();
}

class _AuthChangePasswordDialogState extends State<AuthChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(
      context,
    ).pop(AuthChangePasswordResult(_current.text, _next.text));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change password'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _current,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Current password',
                ),
                validator: AuthRules.validatePasswordPresent,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _next,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'New password',
                  helperText:
                      'At least 8 characters, with a letter and a number.',
                ),
                validator: AuthRules.validateNewPassword,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _confirm,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm new password',
                ),
                onFieldSubmitted: (_) => _submit(),
                validator: (v) =>
                    v != _next.text ? 'The passwords do not match.' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Change password')),
      ],
    );
  }
}

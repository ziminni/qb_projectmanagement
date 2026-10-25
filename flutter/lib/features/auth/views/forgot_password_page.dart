import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../data/services/auth_rules.dart';
import '../../../routes/routes.dart';
import '../viewmodels/forgot_password_viewmodel.dart';
import '../widgets/auth_card.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  late final _vm = ForgotPasswordViewModel(auth: getIt());

  @override
  void dispose() {
    _email.dispose();
    _vm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await reportAction(context, _vm.requestReset(_email.text));
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Consumer<ForgotPasswordViewModel>(
        builder: (context, vm, _) => AuthCard(
          title: 'Reset your password',
          subtitle: vm.sentTo == null
              ? 'Enter your account email and we will send a reset link.'
              : null,
          child: vm.sentTo != null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'If ${vm.sentTo} belongs to an account, a reset link is '
                      'on its way. Check your inbox and spam folder.',
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton(
                      onPressed: () => context.go(AppRoutes.login),
                      child: const Text('Back to sign in'),
                    ),
                  ],
                )
              : Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _email,
                        autofocus: true,
                        decoration: const InputDecoration(labelText: 'Email'),
                        keyboardType: TextInputType.emailAddress,
                        onFieldSubmitted: (_) => _submit(),
                        validator: AuthRules.validateEmail,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      FilledButton(
                        onPressed: vm.isBusy ? null : _submit,
                        child: const Text('Send reset link'),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextButton(
                        onPressed: () => context.go(AppRoutes.login),
                        child: const Text('Back to sign in'),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

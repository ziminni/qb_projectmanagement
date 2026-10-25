import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/layout/role_navigation.dart';
import '../../../data/repositories/mock_data.dart';
import '../../../data/services/auth_rules.dart';
import '../../../routes/routes.dart';
import '../viewmodels/login_viewmodel.dart';
import '../widgets/auth_card.dart';
import '../widgets/auth_demo_accounts.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  late final _vm = LoginViewModel(
    auth: getIt(),
    users: getIt(),
    session: getIt(),
  )..loadDemoAccounts();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _vm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await _vm.signIn(_email.text, _password.text);
    if (!ok || !mounted) return;
    context.go(
      _vm.hasSeveralRoles
          ? AppRoutes.chooseRole
          : RoleNavigation.homeFor(_vm.activeRole),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Consumer<LoginViewModel>(
        builder: (context, vm, _) => AuthCard(
          title: 'Sign in',
          subtitle: 'Use your company account.',
          below: vm.demoAccounts.isEmpty
              ? null
              : AuthDemoAccounts(
                  accounts: vm.demoAccounts,
                  onSelected: (a) {
                    _email.text = a.user.email;
                    _password.text = MockData.demoPassword;
                  },
                ),
          child: AutofillGroup(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _email,
                    decoration: const InputDecoration(labelText: 'Email'),
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    validator: AuthRules.validateEmail,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: 'Password',
                      suffixIcon: IconButton(
                        tooltip: _obscure ? 'Show password' : 'Hide password',
                        icon: Icon(
                          _obscure ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    onFieldSubmitted: (_) => _submit(),
                    validator: AuthRules.validatePasswordPresent,
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => context.go(AppRoutes.forgotPassword),
                      child: const Text('Forgot password?'),
                    ),
                  ),
                  if (vm.error != null) ...[
                    Text(
                      vm.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  FilledButton(
                    onPressed: vm.isBusy ? null : _submit,
                    child: vm.isBusy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Sign in'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

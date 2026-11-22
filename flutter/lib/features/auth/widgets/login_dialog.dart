import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/layout/role_navigation.dart';
import '../../../data/repositories/mock_data.dart';
import '../../../data/services/auth_rules.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/qb_logo.dart';
import '../viewmodels/forgot_password_viewmodel.dart';
import '../viewmodels/login_viewmodel.dart';
import 'auth_demo_accounts.dart';

/// Opens the sign-in modal over the current (public) page.
Future<void> showLoginDialog(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close sign in',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: AppMotion.medium,
    pageBuilder: (_, _, _) => const LoginDialog(),
    transitionBuilder: (context, animation, _, child) =>
        AppMotion.dialog(animation, child),
  );
}

/// Sign-in form, with a "forgot password" step, shown as a modal.
class LoginDialog extends StatefulWidget {
  const LoginDialog({super.key, this.usesApi, this.showDemoLogins});

  /// Overrides the build-time [useApi] flag in tests.
  final bool? usesApi;

  /// Overrides whether the demo account dropdown shows (tests).
  final bool? showDemoLogins;

  @override
  State<LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<LoginDialog> {
  final _loginKey = GlobalKey<FormState>();
  final _resetKey = GlobalKey<FormState>();
  final _resetConfirmKey = GlobalKey<FormState>();
  final _firstPasswordKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _resetEmail = TextEditingController();
  final _resetCode = TextEditingController();
  final _resetNewPassword = TextEditingController();
  final _resetConfirmPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _obscure = true;
  bool _obscureNew = true;
  bool _obscureReset = true;
  bool _forgot = false;
  bool _mustSetPassword = false;
  String? _signInNotice;

  late final _login = LoginViewModel(
    auth: getIt(),
    users: getIt(),
    session: getIt(),
    usesApi: widget.usesApi,
    showDemoLogins: widget.showDemoLogins,
  )..loadDemoAccounts();
  late final _reset = ForgotPasswordViewModel(auth: getIt());

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _resetEmail.dispose();
    _resetCode.dispose();
    _resetNewPassword.dispose();
    _resetConfirmPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    _login.dispose();
    _reset.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_loginKey.currentState!.validate()) return;
    final navigator = Navigator.of(context);
    final router = GoRouter.of(context);
    final ok = await _login.signIn(_email.text, _password.text);
    if (!ok) return;
    if (_login.mustChangePassword) {
      setState(() {
        _mustSetPassword = true;
        _forgot = false;
      });
      return;
    }
    final target = _login.hasSeveralRoles
        ? AppRoutes.chooseRole
        : RoleNavigation.homeFor(_login.activeRole);
    if (navigator.canPop()) navigator.pop();
    router.go(target);
  }

  Future<void> _saveFirstPassword() async {
    if (!_firstPasswordKey.currentState!.validate()) return;
    final navigator = Navigator.of(context);
    final router = GoRouter.of(context);
    final ok = await _login.completeFirstLoginPasswordChange(
      _password.text,
      _newPassword.text,
    );
    if (!ok) return;
    final target = _login.hasSeveralRoles
        ? AppRoutes.chooseRole
        : RoleNavigation.homeFor(_login.activeRole);
    if (navigator.canPop()) navigator.pop();
    router.go(target);
  }

  void _closeDialog() {
    if (_mustSetPassword) {
      _login.cancelFirstLogin();
    }
    Navigator.of(context).pop();
  }

  Future<void> _sendReset() async {
    if (!_resetKey.currentState!.validate()) return;
    await _reset.requestReset(_resetEmail.text);
  }

  Future<void> _confirmReset() async {
    if (!_resetConfirmKey.currentState!.validate()) return;
    final sentEmail = _reset.sentTo ?? _resetEmail.text.trim();
    final ok = await _reset.confirmReset(
      code: _resetCode.text,
      newPassword: _resetNewPassword.text,
    );
    if (!ok || !mounted) return;
    _email.text = sentEmail;
    _password.clear();
    _resetCode.clear();
    _resetNewPassword.clear();
    _resetConfirmPassword.clear();
    _reset.clear();
    setState(() {
      _forgot = false;
      _signInNotice = 'Password updated. Sign in with your new password.';
    });
  }

  void _showForgot(bool value) {
    if (value) {
      if (_resetEmail.text.isEmpty) _resetEmail.text = _email.text;
    } else {
      _reset.clear();
      _resetCode.clear();
      _resetNewPassword.clear();
      _resetConfirmPassword.clear();
    }
    setState(() {
      _forgot = value;
      if (value) _signInNotice = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final phone = MediaQuery.sizeOf(context).width < 480;
    return Dialog(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: phone ? AppSpacing.lg : AppSpacing.xl,
        vertical: AppSpacing.xl,
      ),
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.xlAll),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: ListenableBuilder(
          listenable: Listenable.merge([_login, _reset]),
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(onClose: _closeDialog),
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    phone ? AppSpacing.xl : AppSpacing.xxl,
                    AppSpacing.xl,
                    phone ? AppSpacing.xl : AppSpacing.xxl,
                    AppSpacing.xl,
                  ),
                  // The card resizes smoothly as it swaps between sign-in
                  // and password reset.
                  child: AnimatedSize(
                    duration: AppMotion.medium,
                    curve: AppMotion.enter,
                    alignment: Alignment.topCenter,
                    child: AnimatedSwitcher(
                      duration: AppMotion.medium,
                      switchInCurve: AppMotion.switchIn,
                      switchOutCurve: AppMotion.switchOut,
                      layoutBuilder: (current, previous) => Stack(
                        alignment: Alignment.topCenter,
                        children: [...previous, ?current],
                      ),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween(
                            begin: const Offset(0.03, 0),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: _mustSetPassword
                          ? _buildFirstLoginPassword(context)
                          : _forgot
                          ? _buildReset(context)
                          : _buildLogin(context),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFirstLoginPassword(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('first-login-password'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Set your new password',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Since this is your first time signing in with a temporary password, please choose a new password to continue.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Form(
          key: _firstPasswordKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _newPassword,
                autofocus: true,
                obscureText: _obscureNew,
                decoration: InputDecoration(
                  labelText: 'New password',
                  helperText: 'At least 8 characters with a letter and a digit',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureNew
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () =>
                        setState(() => _obscureNew = !_obscureNew),
                  ),
                ),
                validator: AuthRules.validateNewPassword,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _confirmPassword,
                obscureText: _obscureNew,
                decoration: const InputDecoration(
                  labelText: 'Confirm new password',
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) {
                    return 'Confirm your new password.';
                  }
                  if (v != _newPassword.text) {
                    return 'Passwords do not match.';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _saveFirstPassword(),
              ),
              if (_login.error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  _login.error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.error,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              FilledButton(
                onPressed: _login.isBusy ? null : _saveFirstPassword,
                child: const Text('Confirm & continue'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: _login.isBusy ? null : _closeDialog,
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLogin(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('login'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Welcome back',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Sign in with your company account.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        AutofillGroup(
          child: Form(
            key: _loginKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_login.demoAccounts.isNotEmpty) ...[
                  AuthDemoAccounts(
                    accounts: _login.demoAccounts,
                    onSelected: (a) {
                      _email.text = a.user.email;
                      _password.text = MockData.demoPassword;
                    },
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                TextFormField(
                  controller: _email,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.mail_outline_rounded),
                  ),
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
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      tooltip: _obscure ? 'Show password' : 'Hide password',
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  onFieldSubmitted: (_) => _signIn(),
                  validator: AuthRules.validatePasswordPresent,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => _showForgot(true),
                    child: const Text('Forgot password?'),
                  ),
                ),
                if (_signInNotice != null) ...[
                  _SuccessBanner(message: _signInNotice!),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (_login.error != null) ...[
                  _ErrorBanner(message: _login.error!),
                  const SizedBox(height: AppSpacing.md),
                ],
                FilledButton(
                  onPressed: _login.isBusy ? null : _signIn,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: _login.isBusy
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
      ],
    );
  }

  Widget _buildReset(BuildContext context) {
    final theme = Theme.of(context);
    final sentTo = _reset.sentTo;
    return Column(
      key: const ValueKey('reset'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Reset your password',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          sentTo == null
              ? 'Enter your account email and we will send a 6-digit reset code.'
              : 'If $sentTo belongs to an account, a 6-digit reset code is on '
                    'its way. Check your inbox and spam folder, then enter the '
                    'code below.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        if (sentTo == null)
          Form(
            key: _resetKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _resetEmail,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.mail_outline_rounded),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  onFieldSubmitted: (_) => _sendReset(),
                  validator: AuthRules.validateEmail,
                ),
                if (_reset.error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  _ErrorBanner(message: _reset.error!),
                ],
                const SizedBox(height: AppSpacing.lg),
                FilledButton(
                  onPressed: _reset.isBusy ? null : _sendReset,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: _reset.isBusy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Send reset code'),
                ),
              ],
            ),
          )
        else
          Form(
            key: _resetConfirmKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _resetCode,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: '6-digit reset code',
                    prefixIcon: Icon(Icons.pin_outlined),
                  ),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    final s = v?.trim() ?? '';
                    if (s.length != 6 || int.tryParse(s) == null) {
                      return 'Enter the 6-digit code from your email.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _resetNewPassword,
                  obscureText: _obscureReset,
                  decoration: InputDecoration(
                    labelText: 'New password',
                    helperText: 'At least 8 characters with a letter and a digit',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureReset
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _obscureReset = !_obscureReset),
                    ),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: AuthRules.validateNewPassword,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _resetConfirmPassword,
                  obscureText: _obscureReset,
                  decoration: const InputDecoration(
                    labelText: 'Confirm new password',
                    prefixIcon: Icon(Icons.lock_outline_rounded),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) {
                      return 'Confirm your new password.';
                    }
                    if (v != _resetNewPassword.text) {
                      return 'Passwords do not match.';
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) => _confirmReset(),
                ),
                if (_reset.error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  _ErrorBanner(message: _reset.error!),
                ],
                const SizedBox(height: AppSpacing.lg),
                FilledButton(
                  onPressed: _reset.isBusy ? null : _confirmReset,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: _reset.isBusy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Reset password'),
                ),
                const SizedBox(height: AppSpacing.xs),
                TextButton(
                  onPressed: _reset.isBusy
                      ? null
                      : () => _reset.requestReset(sentTo),
                  child: const Text('Resend code'),
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        TextButton.icon(
          onPressed: () => _showForgot(false),
          icon: const Icon(Icons.arrow_back_rounded, size: 18),
          label: const Text('Back to sign in'),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
      ),
      decoration: const BoxDecoration(
        color: AppColors.chrome,
        border: Border(
          bottom: BorderSide(color: AppColors.brandGold, width: 2),
        ),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: QbLogo(size: 38, onDark: true),
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, color: AppColors.chromeText),
          ),
        ],
      ),
    );
  }
}

class _SuccessBanner extends StatelessWidget {
  const _SuccessBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: const BoxDecoration(
        color: AppColors.successContainer,
        borderRadius: AppRadii.mdAll,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_outline_rounded,
            size: 18,
            color: AppColors.success,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.success, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: const BoxDecoration(
        color: AppColors.errorContainer,
        borderRadius: AppRadii.mdAll,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: AppColors.error,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

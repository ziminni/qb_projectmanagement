import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_padding.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/widgets/app_confirm_dialog.dart';
import '../../../shared/widgets/app_page_header.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../../../shared/widgets/app_status_chip.dart';
import '../../dashboard/widgets/dashboard_stat_tile.dart';
import '../viewmodels/system_security_viewmodel.dart';
import '../widgets/admin_dashboard/admin_dashboard_kit.dart';

class SystemSecurityPage extends StatefulWidget {
  const SystemSecurityPage({super.key});

  @override
  State<SystemSecurityPage> createState() => _SystemSecurityPageState();
}

class _SystemSecurityPageState extends State<SystemSecurityPage> {
  final _formKey = GlobalKey<FormState>();
  final _minPw = TextEditingController();
  final _idleTimeout = TextEditingController();
  final _maxFailures = TextEditingController();
  late final _vm = SystemSecurityViewModel(getIt());

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _vm.load();
    final p = _vm.policy;
    if (p == null || !mounted) return;
    _minPw.text = '${p.minPasswordLength}';
    _idleTimeout.text = '${p.idleTimeoutMinutes}';
    _maxFailures.text = '${p.maxFailedLogins}';
  }

  @override
  void dispose() {
    _minPw.dispose();
    _idleTimeout.dispose();
    _maxFailures.dispose();
    _vm.dispose();
    super.dispose();
  }

  String? _intValidator(String? raw, String label, int min, int max) {
    final parsed = int.tryParse((raw ?? '').trim());
    if (parsed == null || parsed < min || parsed > max) {
      return '$label must be between $min and $max.';
    }
    return null;
  }

  Future<void> _savePolicy() async {
    if (!_formKey.currentState!.validate()) return;
    await reportAction(
      context,
      _vm.savePolicy(
        minPasswordLength: int.parse(_minPw.text.trim()),
        idleTimeoutMinutes: int.parse(_idleTimeout.text.trim()),
        maxFailedLogins: int.parse(_maxFailures.text.trim()),
      ),
      success: 'Security policy saved.',
    );
  }

  Future<void> _revokeSession(int sessionId, String email) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Revoke session?',
      message:
          'This blacklists the refresh token for $email so they must sign in again.',
      confirmLabel: 'Revoke',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await reportAction(
      context,
      _vm.revokeSession(sessionId),
      success: 'Session revoked.',
    );
  }

  Future<void> _revokeAllSessions() async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Revoke all other sessions?',
      message:
          'This blacklists every active refresh token except your current session.',
      confirmLabel: 'Revoke all',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await reportAction(
      context,
      _vm.revokeAllSessions(),
      success: 'Other active sessions revoked.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Consumer<SystemSecurityViewModel>(
        builder: (context, vm, _) {
          if (vm.isLoading) return const AdminTabSkeleton();
          if (vm.error != null) {
            return AdminErrorState(message: vm.error!, onRetry: _load);
          }
          final policy = vm.policy;
          final failedCount = vm.events
              .where((e) => e.action.toLowerCase().contains('failed'))
              .length;

          return RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: pagePadding(context),
              children: [
                AppPageHeader(
                  title: 'Security & sessions',
                  subtitle:
                      'Monitor live JWT sessions, review login attempts, and enforce password and lockout policies.',
                  actions: [
                    OutlinedButton.icon(
                      onPressed: vm.isBusy ? null : _load,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Refresh'),
                    ),
                  ],
                ),
                AdminStatGrid(
                  tiles: [
                    DashboardStatTile(
                      label: 'Active sessions',
                      value: '${vm.sessions.length}',
                      detail: 'Live JWT refresh tokens',
                      icon: Icons.devices_outlined,
                      color: AppColors.brandGoldText,
                    ),
                    DashboardStatTile(
                      label: 'Failed logins',
                      value: '$failedCount',
                      detail: 'In recent auth events',
                      icon: Icons.gpp_maybe_outlined,
                      color: failedCount > 0
                          ? AppColors.warning
                          : AppColors.success,
                    ),
                    DashboardStatTile(
                      label: 'Min password',
                      value: '${policy?.minPasswordLength ?? 8} chars',
                      detail:
                          'Lockout after ${policy?.maxFailedLogins ?? 5} tries',
                      icon: Icons.password_outlined,
                    ),
                    DashboardStatTile(
                      label: 'Idle timeout',
                      value: '${policy?.idleTimeoutMinutes ?? 30} min',
                      detail: (policy?.requireManagerOverride ?? true)
                          ? 'Manager override required'
                          : 'Manager override optional',
                      icon: Icons.timer_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                AdminTwoColumn(
                  main: [
                    AppSectionCard(
                      title: 'Active JWT sessions',
                      icon: Icons.devices_outlined,
                      subtitle: vm.sessions.isEmpty
                          ? 'No active tokens'
                          : '${vm.sessions.length} signed-in '
                                '${vm.sessions.length == 1 ? 'session' : 'sessions'}',
                      trailing: vm.sessions.length > 1
                          ? TextButton(
                              onPressed: vm.isBusy ? null : _revokeAllSessions,
                              child: const Text('Revoke all'),
                            )
                          : null,
                      padding: EdgeInsets.zero,
                      child: vm.sessions.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(AppSpacing.lg),
                              child: Text('No active sessions right now.'),
                            )
                          : Column(
                              children: [
                                for (final (i, s) in vm.sessions.indexed) ...[
                                  if (i > 0) const Divider(height: 1),
                                  ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.lg,
                                      vertical: AppSpacing.xs,
                                    ),
                                    leading: AppAvatar(
                                      name: s.userName.isNotEmpty
                                          ? s.userName
                                          : s.userEmail,
                                      size: 38,
                                    ),
                                    title: Text(
                                      s.userName.isNotEmpty
                                          ? s.userName
                                          : s.userEmail,
                                    ),
                                    subtitle: Text(
                                      [
                                        if (s.userName.isNotEmpty) s.userEmail,
                                        'Token ${s.jti.length > 10 ? s.jti.substring(0, 10) : s.jti}…',
                                        if (s.expiresAt != null)
                                          'Expires ${Formatters.dateTime(s.expiresAt!)}',
                                      ].join(' · '),
                                    ),
                                    trailing: OutlinedButton.icon(
                                      onPressed: vm.isBusy
                                          ? null
                                          : () => _revokeSession(
                                              s.id,
                                              s.userEmail,
                                            ),
                                      icon: const Icon(
                                        Icons.block_outlined,
                                        size: 16,
                                      ),
                                      label: const Text('Revoke'),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                    ),
                    AppSectionCard(
                      title: 'Recent authentication events',
                      icon: Icons.login_outlined,
                      subtitle: 'Latest login, logout, and failed attempts',
                      padding: EdgeInsets.zero,
                      child: vm.events.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(AppSpacing.lg),
                              child: Text('No login events recorded yet.'),
                            )
                          : Column(
                              children: [
                                for (final (i, e)
                                    in vm.events.take(15).indexed) ...[
                                  if (i > 0) const Divider(height: 1),
                                  _AuthEventTile(event: e),
                                ],
                              ],
                            ),
                    ),
                  ],
                  side: [
                    Form(
                      key: _formKey,
                      child: AppSectionCard(
                        title: 'Security policy',
                        icon: Icons.policy_outlined,
                        subtitle: 'Enforced on the server across all accounts',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: _minPw,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Minimum password length',
                                suffixText: 'chars',
                                helperText: 'Recommended: 8 to 16 characters.',
                              ),
                              validator: (v) => _intValidator(
                                v,
                                'Minimum password length',
                                6,
                                128,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            TextFormField(
                              controller: _idleTimeout,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Idle timeout',
                                suffixText: 'min',
                                helperText:
                                    'Inactive sessions expire after this window.',
                              ),
                              validator: (v) =>
                                  _intValidator(v, 'Idle timeout', 5, 1440),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            TextFormField(
                              controller: _maxFailures,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Failed-login lockout threshold',
                                suffixText: 'tries',
                                helperText:
                                    'Updates live server lockout limit.',
                              ),
                              validator: (v) => _intValidator(
                                v,
                                'Lockout threshold',
                                1,
                                20,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Material(
                              color: AppColors.surfaceSunken,
                              shape: RoundedRectangleBorder(
                                borderRadius: AppRadii.mdAll,
                                side: const BorderSide(color: AppColors.border),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.md,
                                  vertical: AppSpacing.xs,
                                ),
                                child: SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text('Require manager override'),
                                  subtitle: const Text(
                                    'Require owner/manager approval on sensitive overrides.',
                                  ),
                                  value: vm.requireManagerOverride,
                                  onChanged: vm.setRequireManagerOverride,
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            FilledButton(
                              onPressed: vm.isBusy ? null : _savePolicy,
                              child: const Text('Save policy'),
                            ),
                          ],
                        ),
                      ),
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

class _AuthEventTile extends StatelessWidget {
  const _AuthEventTile({required this.event});

  final dynamic event;

  @override
  Widget build(BuildContext context) {
    final action = (event.action as String).toLowerCase();
    final isFailed = action.contains('failed');
    final isLogout = action.contains('logout');
    final color = isFailed
        ? AppColors.error
        : isLogout
        ? AppColors.textSecondary
        : AppColors.success;
    final bg = isFailed
        ? AppColors.errorContainer
        : isLogout
        ? AppColors.surfaceMuted
        : AppColors.successContainer;
    final label = isFailed
        ? 'FAILED'
        : isLogout
        ? 'LOGOUT'
        : 'LOGIN';

    return ListTile(
      dense: true,
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(color: bg, borderRadius: AppRadii.mdAll),
        child: Icon(
          isFailed
              ? Icons.error_outline
              : isLogout
              ? Icons.logout_rounded
              : Icons.check_circle_outline,
          size: 18,
          color: color,
        ),
      ),
      title: Text(
        event.userName.isNotEmpty
            ? '${event.userName} (${event.userEmail})'
            : event.userEmail,
      ),
      subtitle: Text(Formatters.dateTime(event.createdAt)),
      trailing: AppStatusChip(label: label, foreground: color, background: bg),
    );
  }
}

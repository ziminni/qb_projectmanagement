import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../data/repositories/mock_data.dart';
import '../viewmodels/login_viewmodel.dart';

/// Lists the mock accounts; tapping one fills in the login form.
class AuthDemoAccounts extends StatelessWidget {
  const AuthDemoAccounts({
    super.key,
    required this.accounts,
    required this.onSelected,
  });

  final List<DemoAccount> accounts;
  final ValueChanged<DemoAccount> onSelected;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text('Demo accounts', style: textTheme.titleSmall),
        subtitle: Text(
          'Mock data only. Password: ${MockData.demoPassword}',
          style: textTheme.bodySmall,
        ),
        children: [
          for (final a in accounts)
            ListTile(
              dense: true,
              title: Text(a.user.fullName),
              subtitle: Text(
                '${a.user.email} · ${a.roles.map((r) => r.label).join(', ')}',
              ),
              onTap: () => onSelected(a),
            ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}

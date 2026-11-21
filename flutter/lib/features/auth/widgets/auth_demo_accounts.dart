import 'package:flutter/material.dart';

import '../../../data/repositories/mock_data.dart';
import '../viewmodels/login_viewmodel.dart';

/// A dropdown of the demo accounts; choosing one fills in the login form.
class AuthDemoAccounts extends StatefulWidget {
  const AuthDemoAccounts({
    super.key,
    required this.accounts,
    required this.onSelected,
  });

  final List<DemoAccount> accounts;
  final ValueChanged<DemoAccount> onSelected;

  @override
  State<AuthDemoAccounts> createState() => _AuthDemoAccountsState();
}

class _AuthDemoAccountsState extends State<AuthDemoAccounts> {
  DemoAccount? _selected;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<DemoAccount>(
      initialValue: _selected,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Demo account',
        helperText:
            'Fills in the email and password '
            '(${MockData.demoPassword}).',
        prefixIcon: Icon(Icons.people_alt_outlined),
      ),
      hint: const Text('Choose an account to sign in as'),
      items: [
        for (final a in widget.accounts)
          DropdownMenuItem(
            value: a,
            child: Text(
              '${a.user.fullName} · ${a.roles.map((r) => r.label).join(', ')}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (a) {
        if (a == null) return;
        setState(() => _selected = a);
        widget.onSelected(a);
      },
    );
  }
}

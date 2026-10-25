import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/audit_log.dart';

/// Approval history from the audit log, with any reason given.
class AppHistoryList extends StatelessWidget {
  const AppHistoryList({
    super.key,
    required this.entries,
    required this.userName,
  });

  final List<AuditLog> entries;
  final String Function(int userId) userName;

  static String _label(String action) => switch (action) {
    'billing_created' => 'Prepared',
    'billing_submitted' => 'Submitted to the owner',
    'billing_withdrawn' => 'Withdrawn',
    'billing_owner_approved' => 'Approved by the owner',
    'billing_owner_rejected' => 'Rejected by the owner',
    'billing_client_approved' => 'Approved by the client',
    'billing_client_disputed' => 'Disputed by the client',
    'billing_payment_recorded' => 'Payment recorded',
    'billing_paid' => 'Marked paid',
    'vo_proposed' => 'Proposed',
    'vo_submitted' => 'Submitted to the owner',
    'vo_owner_approved' => 'Approved by the owner',
    'vo_owner_rejected' => 'Rejected by the owner',
    'vo_client_approved' => 'Approved by the client',
    'vo_client_rejected' => 'Rejected by the client',
    _ => action.replaceAll('_', ' '),
  };

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const ListTile(title: Text('No activity recorded yet.'));
    }
    return Column(
      children: [
        for (final e in entries)
          ListTile(
            dense: true,
            leading: const Icon(Icons.history, size: 20),
            title: Text('${_label(e.action)} · ${userName(e.userId)}'),
            subtitle: Text(
              [
                Formatters.dateTime(e.createdAt.toLocal()),
                if (e.details['reason'] != null) '"${e.details['reason']}"',
              ].join('\n'),
            ),
          ),
      ],
    );
  }
}

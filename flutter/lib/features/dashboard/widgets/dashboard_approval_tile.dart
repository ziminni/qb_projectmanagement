import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../../../data/services/approval_inbox.dart';

class DashboardApprovalTile extends StatelessWidget {
  const DashboardApprovalTile({
    super.key,
    required this.item,
    required this.onTap,
  });

  final ApprovalItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      title: Text(item.title),
      subtitle: Text(
        [
          item.subtitle,
          if (item.date != null) Formatters.date(item.date!.toLocal()),
        ].join(' · '),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (item.amount != null) Text(Formatters.pesoWhole(item.amount!)),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}

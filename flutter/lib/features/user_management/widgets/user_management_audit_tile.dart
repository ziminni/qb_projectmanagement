import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/audit_log.dart';
import '../viewmodels/audit_log_viewmodel.dart';

/// One audit-log entry: what happened, to which record, by whom and when.
class UserManagementAuditTile extends StatelessWidget {
  const UserManagementAuditTile({
    super.key,
    required this.log,
    required this.userName,
    this.showDetails = true,
    this.dense = false,
  });

  final AuditLog log;
  final String userName;
  final bool showDetails;
  final bool dense;

  static IconData iconFor(String entity) => switch (entity) {
    'user' => Icons.person_outline,
    'company' => Icons.business_outlined,
    'company_settings' => Icons.tune,
    'material' => Icons.inventory_2_outlined,
    'supplier' => Icons.storefront_outlined,
    'trade' => Icons.handyman_outlined,
    'client' => Icons.badge_outlined,
    'equipment' => Icons.construction_outlined,
    'purchase_order' => Icons.shopping_cart_outlined,
    'material_request' => Icons.inventory_outlined,
    'project' => Icons.apartment_outlined,
    'daily_report' => Icons.edit_note_outlined,
    'payroll_period' => Icons.payments_outlined,
    'billing' => Icons.receipt_long_outlined,
    'variation_order' => Icons.difference_outlined,
    _ => Icons.history,
  };

  @override
  Widget build(BuildContext context) {
    final visible = AuditLogViewModel.visibleDetails(log.details);
    final details = showDetails && visible.isNotEmpty
        ? visible.entries
              .map((e) => '${AuditLogViewModel.actionLabel(e.key)}: ${e.value}')
              .join(' · ')
        : null;
    return ListTile(
      dense: dense,
      leading: Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(
          color: AppColors.selected,
          borderRadius: AppRadii.mdAll,
        ),
        child: Icon(
          iconFor(log.entity),
          size: 18,
          color: AppColors.brandGoldText,
        ),
      ),
      title: Text(AuditLogViewModel.actionLabel(log.action)),
      subtitle: Text(
        [
          '$userName · ${AuditLogViewModel.entityLabel(log.entity)} '
              '#${log.entityId} · ${Formatters.dateTime(log.createdAt)}',
          ?details,
        ].join('\n'),
      ),
      isThreeLine: details != null,
    );
  }
}

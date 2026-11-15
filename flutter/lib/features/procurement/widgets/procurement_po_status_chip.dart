import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/material_source.dart';
import '../../../data/models/purchase_order.dart';
import '../../../shared/widgets/app_status_chip.dart';

class ProcurementPoStatusChip extends StatelessWidget {
  const ProcurementPoStatusChip({super.key, required this.status, this.source});

  final PurchaseOrderStatus status;
  final MaterialSource? source;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = switch (status) {
      PurchaseOrderStatus.released || PurchaseOrderStatus.purchased => (
        AppColors.info,
        AppColors.infoContainer,
      ),
      PurchaseOrderStatus.partiallyDelivered => (
        AppColors.info,
        AppColors.infoContainer,
      ),
      PurchaseOrderStatus.delivered => (
        AppColors.success,
        AppColors.successContainer,
      ),
      PurchaseOrderStatus.cancelled => (
        AppColors.textSecondary,
        AppColors.surfaceMuted,
      ),
    };
    return AppStatusChip(
      label: status.labelFor(source),
      foreground: fg,
      background: bg,
    );
  }
}

import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../../../data/models/material_request.dart';
import 'procurement_request_status_chip.dart';

class ProcurementRequestTile extends StatelessWidget {
  const ProcurementRequestTile({
    super.key,
    required this.request,
    required this.projectCode,
    required this.categoryName,
    required this.onTap,
  });

  final MaterialRequest request;
  final String projectCode;
  final String categoryName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: const Icon(Icons.inventory_2_outlined),
      title: Text('${request.number} · $projectCode'),
      subtitle: Text(
        '$categoryName · needed by ${Formatters.date(request.neededBy)}',
      ),
      trailing: ProcurementRequestStatusChip(status: request.status),
    );
  }
}

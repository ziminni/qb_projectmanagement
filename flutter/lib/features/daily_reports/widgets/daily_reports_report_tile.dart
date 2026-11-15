import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../../../data/models/daily_report.dart';
import 'daily_reports_status_chip.dart';

class DailyReportsReportTile extends StatelessWidget {
  const DailyReportsReportTile({
    super.key,
    required this.report,
    required this.projectLabel,
    required this.onTap,
  });

  final DailyReport report;
  final String? projectLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: const Icon(Icons.edit_note_outlined),
      title: Text(Formatters.date(report.reportDate)),
      subtitle: Text([?projectLabel, report.weather.label].join(' · ')),
      trailing: DailyReportsStatusChip(status: report.status),
    );
  }
}

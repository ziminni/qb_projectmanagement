import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../data/models/material_request_item.dart';
import '../../../data/models/site_count.dart';
import '../../../shared/widgets/app_section_card.dart';

/// What the site engineer asked for, with DUPA plan badges (Planned / Over plan /
/// Unplanned) and the order that covers each item. With [selected], open items
/// get checkboxes so the owner can tick off what the order being prepared covers.
class ProcurementRequestedItems extends StatelessWidget {
  const ProcurementRequestedItems({
    super.key,
    required this.items,
    required this.orderNo,
    this.selected,
    this.onToggle,
  });

  final List<MaterialRequestItem> items;

  /// The PO number of the order covering an item.
  final String Function(int orderId) orderNo;
  final Set<int>? selected;
  final ValueChanged<int>? onToggle;

  Widget? _planBadge(MaterialRequestItem i) {
    if (i.isUnplanned) {
      return _chip('Unplanned', AppColors.warningContainer, AppColors.warning);
    }
    if (i.isOverPlan) {
      return _chip(
        'Over DUPA (${Formatters.number(i.plannedQty!)} ${i.unit})',
        AppColors.warningContainer,
        AppColors.warning,
      );
    }
    if (i.isPlanned) {
      return _chip(
        'DUPA planned',
        AppColors.successContainer,
        AppColors.success,
      );
    }
    return null;
  }

  Widget _chip(String label, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: bg, borderRadius: AppRadii.smAll),
    child: Text(
      label,
      style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700),
    ),
  );

  Widget _titleRow(MaterialRequestItem i) {
    final badge = _planBadge(i);
    if (badge == null) return Text(i.description);
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [Text(i.description), badge],
    );
  }

  String _subtitleText(MaterialRequestItem i) {
    final base = i.isCovered
        ? 'Covered by ${orderNo(i.purchaseOrderId!)}'
        : 'Not ordered yet';
    if (i.overPlanReason.trim().isNotEmpty) {
      return '$base · Reason: ${i.overPlanReason.trim()}';
    }
    return base;
  }

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    String qty(MaterialRequestItem i) =>
        '${InputParsers.amountText(i.quantity)} ${i.unit}'.trim();
    final open = items.where((i) => !i.isCovered).length;
    return AppSectionCard(
      title: 'Requested by the site engineer',
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              selected != null
                  ? 'Tick the items this order covers.'
                  : open == 0
                  ? 'Every item is covered by an order.'
                  : '$open of ${items.length} not ordered yet.',
              style: small,
            ),
          ),
          for (final i in items)
            if (selected != null && !i.isCovered)
              CheckboxListTile(
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: selected!.contains(i.id),
                onChanged: (_) => onToggle!(i.id),
                title: _titleRow(i),
                subtitle: i.overPlanReason.trim().isNotEmpty
                    ? Text('Reason: ${i.overPlanReason.trim()}')
                    : null,
                secondary: Text(qty(i)),
              )
            else
              ListTile(
                dense: true,
                leading: Icon(
                  i.isCovered
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: i.isCovered ? AppColors.success : null,
                ),
                title: _titleRow(i),
                subtitle: Text(_subtitleText(i)),
                trailing: Text(
                  qty(i),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
        ],
      ),
    );
  }
}

/// The site count taken before the request, with the gap from what the
/// system expected.
class ProcurementSiteCounts extends StatelessWidget {
  const ProcurementSiteCounts({super.key, required this.counts});

  final List<SiteCount> counts;

  @override
  Widget build(BuildContext context) {
    String q(double v) => InputParsers.amountText(v);
    return AppSectionCard(
      title: 'Site count before this request',
      padding: EdgeInsets.zero,
      child: counts.isEmpty
          ? const ListTile(title: Text('Nothing was on site to count.'))
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Material')),
                  DataColumn(label: Text('System'), numeric: true),
                  DataColumn(label: Text('Counted'), numeric: true),
                  DataColumn(label: Text('Difference'), numeric: true),
                ],
                rows: [
                  for (final c in counts)
                    DataRow(
                      cells: [
                        DataCell(Text(c.name)),
                        DataCell(Text('${q(c.expected)} ${c.unit}')),
                        DataCell(Text('${q(c.counted)} ${c.unit}')),
                        DataCell(
                          Text(
                            c.difference == 0
                                ? '—'
                                : '${c.difference > 0 ? '+' : ''}${q(c.difference)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: c.difference < 0 ? AppColors.error : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/finance_access.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/services/approval_inbox.dart';

class DashboardApprovalTile extends StatefulWidget {
  const DashboardApprovalTile({
    super.key,
    required this.item,
    required this.onTap,
  });

  final ApprovalItem item;
  final VoidCallback onTap;

  @override
  State<DashboardApprovalTile> createState() => _DashboardApprovalTileState();
}

class _DashboardApprovalTileState extends State<DashboardApprovalTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final accentFg = isDark ? cs.secondary : cs.onPrimaryContainer;
    final showAmount = item.amount != null && canSeeFinance();
    final wide = MediaQuery.sizeOf(context).width >= 520;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: _hovered
            ? cs.primary.withValues(alpha: isDark ? 0.08 : 0.05)
            : Colors.transparent,
        child: ListTile(
          onTap: widget.onTap,
          hoverColor: Colors.transparent,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 6,
          ),
          title: Text(
            item.title,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
              height: 1.3,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              [
                item.subtitle,
                if (item.date != null) Formatters.date(item.date!.toLocal()),
              ].join(' · '),
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showAmount) ...[
                Text(
                  Formatters.pesoWhole(item.amount!),
                  style: theme.textTheme.bodyMedium
                      ?.merge(AppTextStyles.numeric)
                      .copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              if (wide)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _hovered
                        ? cs.primary.withValues(alpha: isDark ? 0.2 : 0.14)
                        : cs.surfaceContainerHighest.withValues(alpha: 0.65),
                    borderRadius: AppRadii.smAll,
                    border: Border.all(
                      color: _hovered
                          ? cs.primary.withValues(alpha: 0.45)
                          : cs.outlineVariant,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Review',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _hovered ? accentFg : cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 14,
                        color: _hovered ? accentFg : cs.onSurfaceVariant,
                      ),
                    ],
                  ),
                )
              else
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

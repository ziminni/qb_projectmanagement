import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/finance_access.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/services/approval_inbox.dart';
import 'dashboard_waiting_row.dart';

class DashboardApprovalTile extends StatefulWidget {
  const DashboardApprovalTile({
    super.key,
    required this.item,
    required this.onTap,
    this.quickActionLabel,
    this.onQuickAction,
    this.isBusy = false,
  });

  final ApprovalItem item;
  final VoidCallback onTap;
  final String? quickActionLabel;
  final VoidCallback? onQuickAction;
  final bool isBusy;

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
    final accentFg = isDark ? cs.secondary : AppColors.brandGoldText;
    final showAmount = item.amount != null && canSeeFinance();
    final wide = MediaQuery.sizeOf(context).width >= 640;

    final metaParts = <String>[
      if (item.projectName != null &&
          item.projectName!.isNotEmpty &&
          item.subtitle != item.projectName)
        item.projectName!,
      item.subtitle,
      if (item.date != null) Formatters.date(item.date!.toLocal()),
    ];

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
            vertical: 8,
          ),
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _hovered
                  ? cs.primary.withValues(alpha: isDark ? 0.22 : 0.16)
                  : (isDark ? cs.surfaceContainerHighest : AppColors.surfaceSunken),
              borderRadius: AppRadii.mdAll,
              border: Border.all(
                color: _hovered
                    ? cs.primary.withValues(alpha: 0.4)
                    : cs.outlineVariant,
              ),
            ),
            child: Icon(
              DashboardWaitingRow.iconFor(item.kind),
              size: 18,
              color: accentFg,
            ),
          ),
          title: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                item.title,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                  height: 1.3,
                ),
              ),
              if (item.badgeText != null && item.badgeText!.trim().isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? cs.surfaceContainerHighest
                        : AppColors.surfaceSunken,
                    borderRadius: AppRadii.smAll,
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Text(
                    item.badgeText!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              metaParts.join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
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
                  '${item.amount! >= 0 ? '' : '−'}${Formatters.pesoWhole(item.amount!.abs())}',
                  style: theme.textTheme.bodyMedium
                      ?.merge(AppTextStyles.numeric)
                      .copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              if (wide &&
                  widget.quickActionLabel != null &&
                  widget.onQuickAction != null) ...[
                OutlinedButton(
                  onPressed: widget.isBusy ? null : widget.onQuickAction,
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: widget.isBusy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(widget.quickActionLabel!),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              if (wide)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _hovered
                        ? cs.primary.withValues(alpha: isDark ? 0.22 : 0.16)
                        : (isDark
                              ? cs.surfaceContainerHighest.withValues(
                                  alpha: 0.65,
                                )
                              : AppColors.surfaceSunken),
                    borderRadius: AppRadii.smAll,
                    border: Border.all(
                      color: _hovered
                          ? cs.primary.withValues(alpha: 0.5)
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
                          fontWeight: FontWeight.w700,
                          color: _hovered ? accentFg : cs.onSurface,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Icon(
                        Icons.open_in_full_rounded,
                        size: 13,
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

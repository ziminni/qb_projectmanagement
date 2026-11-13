import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_fonts.dart';
import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import '../theme/app_motion.dart';

/// One destination in [AppSidebar]: a full row with icon and label, or a
/// stacked icon over a small label when [compact].
class AppSidebarItem extends StatelessWidget {
  const AppSidebarItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : AppColors.sidebarText;
    final iconWidget = TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: selected ? const Color(0xFFE1C684) : fg),
      duration: AppMotion.fast,
      curve: AppMotion.enter,
      builder: (context, color, _) => Icon(icon, size: 20, color: color),
    );
    final text = AnimatedDefaultTextStyle(
      duration: AppMotion.fast,
      curve: AppMotion.enter,
      style: TextStyle(
        fontFamily: AppFonts.body,
        color: fg,
        fontSize: compact ? 10.5 : 14,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        height: 1.2,
      ),
      child: Text(
        label,
        maxLines: compact ? 2 : 1,
        overflow: TextOverflow.ellipsis,
        textAlign: compact ? TextAlign.center : TextAlign.start,
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 2,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadii.mdAll,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadii.mdAll,
          hoverColor: AppColors.sidebarRaised,
          // The highlight and gold edge fade between items instead of
          // jumping.
          child: AnimatedContainer(
            duration: AppMotion.medium,
            curve: AppMotion.enter,
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0x38AC934F)
                  : const Color(0x00AC934F),
              borderRadius: AppRadii.mdAll,
              border: Border(
                left: BorderSide(
                  color: selected
                      ? const Color(0xFFE1C684)
                      : const Color(0x00E1C684),
                  width: 3,
                ),
              ),
            ),
            padding: compact
                ? const EdgeInsets.symmetric(vertical: 10, horizontal: 4)
                : const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
            child: compact
                ? Column(
                    children: [iconWidget, const SizedBox(height: 4), text],
                  )
                : Row(
                    children: [
                      iconWidget,
                      const SizedBox(width: AppSpacing.md),
                      Expanded(child: text),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

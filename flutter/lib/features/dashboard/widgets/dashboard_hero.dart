import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';

/// The dashboard's greeting banner with today's summary and quick actions.
class DashboardHero extends StatelessWidget {
  const DashboardHero({
    super.key,
    required this.greeting,
    required this.summary,
    required this.actions,
  });

  final String greeting;
  final String summary;

  /// (icon, label, onTap); the first is the primary action.
  final List<(IconData, String, VoidCallback)> actions;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.chrome, AppColors.brandGold, AppColors.brandGold],
        ),
        borderRadius: AppRadii.xlAll,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -30,
            top: -40,
            child: Icon(
              Icons.apartment_rounded,
              size: 220,
              color: Colors.white.withValues(alpha: 0.06),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('EEEE, MMMM d').format(DateTime.now()),
                  style: textTheme.labelMedium?.copyWith(
                    color: AppColors.surfaceSunken,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  greeting,
                  style: textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontSize: 28,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  summary,
                  style: textTheme.bodyLarge?.copyWith(
                    color: AppColors.selected,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                LayoutBuilder(
                  builder: (context, c) {
                    final buttons = [
                      for (final (i, (icon, label, onTap)) in actions.indexed)
                        i == 0
                            ? FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: AppColors.primaryDark,
                                ),
                                onPressed: onTap,
                                icon: Icon(icon, size: 18),
                                label: Text(label),
                              )
                            : OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.35),
                                  ),
                                  backgroundColor: Colors.white.withValues(
                                    alpha: 0.06,
                                  ),
                                ),
                                onPressed: onTap,
                                icon: Icon(icon, size: 18),
                                label: Text(label),
                              ),
                    ];
                    // Phones swipe through the actions instead of stacking.
                    return c.maxWidth < 520
                        ? SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (final b in buttons) ...[
                                  b,
                                  const SizedBox(width: AppSpacing.sm),
                                ],
                              ],
                            ),
                          )
                        : Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.sm,
                            children: buttons,
                          );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

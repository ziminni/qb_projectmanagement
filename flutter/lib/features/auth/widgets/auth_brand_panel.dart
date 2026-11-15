import 'package:flutter/material.dart';

import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/app_brand_mark.dart';

/// The dark marketing panel beside the sign-in form on wide screens.
class AuthBrandPanel extends StatelessWidget {
  const AuthBrandPanel({super.key});

  static const _features = [
    (
      Icons.insights_rounded,
      'Live progress',
      'Verified work drives the S-curve, Gantt and billing.',
    ),
    (
      Icons.inbox_rounded,
      'One approvals inbox',
      'Reports, requests and payroll waiting in one place.',
    ),
    (
      Icons.lock_outline_rounded,
      'Finances stay private',
      'Only the owner and accountant ever see the money.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.chrome,
            AppColors.chromeRaised,
            AppColors.brandGold,
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -80,
            bottom: -60,
            child: Icon(
              Icons.location_city_rounded,
              size: 420,
              color: Colors.white.withValues(alpha: 0.05),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppBrandMark(size: 40, onDark: true),
                const Spacer(),
                Text(
                  'Run every site\nfrom one place.',
                  style: textTheme.displaySmall?.copyWith(
                    color: Colors.white,
                    fontSize: 40,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Construction project management for Philippine '
                  'contractors: schedules, site reports, materials, labor '
                  'and billing.',
                  style: textTheme.bodyLarge?.copyWith(
                    color: AppColors.surfaceSunken,
                  ),
                ),
                const SizedBox(height: 40),
                for (final (icon, title, body) in _features)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: AppRadii.mdAll,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                          ),
                          child: Icon(icon, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: textTheme.titleSmall?.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                body,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: AppColors.chromeText,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                const Spacer(),
                Text(
                  '© ${DateTime.now().year} BuildPro',
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.disabled,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

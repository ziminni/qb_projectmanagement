import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_fonts.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/services/session_service.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/widgets/app_status_chip.dart';

/// Opens a display-only executive profile card for the signed-in user.
Future<void> showProfileDialog(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close profile',
    barrierColor: Colors.black.withValues(alpha: 0.5),
    transitionDuration: AppMotion.medium,
    pageBuilder: (_, _, _) => const _ProfileDialog(),
    transitionBuilder: (context, animation, _, child) =>
        AppMotion.dialog(animation, child),
  );
}

class _ProfileDialog extends StatelessWidget {
  const _ProfileDialog();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionService>();
    final user = session.user;
    if (user == null) return const SizedBox.shrink();
    final activeRole = session.activeRole;
    final roles = session.roles;
    final textTheme = Theme.of(context).textTheme;
    final phone = MediaQuery.sizeOf(context).width < 600;

    return Dialog(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: phone ? AppSpacing.lg : AppSpacing.xxl,
        vertical: AppSpacing.xl,
      ),
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.xlAll),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Dark obsidian hero header with gold accent.
            Container(
              decoration: const BoxDecoration(
                color: AppColors.chrome,
                border: Border(
                  bottom: BorderSide(color: AppColors.brandGold, width: 2),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'MY PROFILE',
                        style: textTheme.labelSmall?.copyWith(
                          color: AppColors.brandGoldLight,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.6,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        icon: const Icon(
                          Icons.close_rounded,
                          color: AppColors.chromeText,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.brandGold,
                            width: 2,
                          ),
                        ),
                        child: AppAvatar(name: user.fullName, size: 60),
                      ),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.fullName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: AppFonts.display,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: AppColors.brandWhite,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              user.email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall?.copyWith(
                                color: AppColors.chromeText,
                              ),
                            ),
                            if (activeRole != null) ...[
                              const SizedBox(height: AppSpacing.sm),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.sm,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.brandGold.withValues(
                                    alpha: 0.18,
                                  ),
                                  borderRadius: AppRadii.pillAll,
                                  border: Border.all(
                                    color: AppColors.brandGold.withValues(
                                      alpha: 0.6,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  activeRole.label,
                                  style: textTheme.labelSmall?.copyWith(
                                    color: AppColors.brandGoldLight,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Display-only account details card.
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: AppColors.cardBackground,
                      borderRadius: AppRadii.lgAll,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _DetailRow(
                          icon: Icons.mail_outline_rounded,
                          label: 'Email',
                          value: user.email,
                        ),
                        const Divider(height: AppSpacing.lg),
                        _DetailRow(
                          icon: Icons.phone_outlined,
                          label: 'Phone',
                          value: (user.phone ?? '').trim().isNotEmpty
                              ? user.phone!.trim()
                              : 'Not provided',
                        ),
                        const Divider(height: AppSpacing.lg),
                        Row(
                          children: [
                            const Icon(
                              Icons.verified_user_outlined,
                              size: 18,
                              color: AppColors.brandGoldText,
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Text(
                              'Account status',
                              style: textTheme.bodySmall?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const Spacer(),
                            AppStatusChip(
                              label: user.isActive ? 'Active' : 'Inactive',
                              foreground: user.isActive
                                  ? AppColors.success
                                  : AppColors.error,
                              background: user.isActive
                                  ? AppColors.successContainer
                                  : AppColors.errorContainer,
                            ),
                          ],
                        ),
                        if (user.createdAt != null) ...[
                          const Divider(height: AppSpacing.lg),
                          _DetailRow(
                            icon: Icons.calendar_today_outlined,
                            label: 'Member since',
                            value: Formatters.date(user.createdAt!),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (roles.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'ASSIGNED ROLES',
                      style: textTheme.labelSmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      children: [
                        for (final r in roles)
                          AppStatusChip(
                            label: r.label,
                            icon: r == activeRole
                                ? Icons.check_circle_outline
                                : Icons.badge_outlined,
                            foreground: r == activeRole
                                ? AppColors.brandGoldText
                                : AppColors.textSecondary,
                            background: r == activeRole
                                ? AppColors.selected
                                : AppColors.surfaceMuted,
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Update profile or password in Settings.',
                          style: textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.brandGoldText),
        const SizedBox(width: AppSpacing.md),
        Text(
          label,
          style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

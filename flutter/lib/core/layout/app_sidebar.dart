import 'package:flutter/material.dart';

import '../../data/models/app_role.dart';
import '../../data/models/user.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/qb_logo.dart';
import '../constants/app_colors.dart';
import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import 'app_sidebar_item.dart';
import 'role_navigation.dart';

/// The dark navigation sidebar: brand, the role's destinations, and the
/// signed-in user. [compact] shows icons with small labels beneath.
class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.destinations,
    required this.selected,
    required this.onSelect,
    required this.user,
    required this.role,
    this.compact = false,
  });

  final List<RoleDestination> destinations;
  final int selected;
  final ValueChanged<int> onSelect;
  final User user;
  final AppRole role;
  final bool compact;

  static const fullWidth = 264.0;
  static const compactWidth = 92.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: compact ? compactWidth : fullWidth,
      color: AppColors.sidebar,
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 0 : AppSpacing.xl,
                AppSpacing.xl,
                compact ? 0 : AppSpacing.xl,
                AppSpacing.lg,
              ),
              child: compact
                  ? const Center(
                      child: QbLogo(size: 40, showName: false, onDark: true),
                    )
                  : QbLogo(size: 40, onDark: true, tagline: role.label),
            ),
            const Divider(color: AppColors.sidebarDivider, height: 1),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                children: [
                  for (final (i, d) in destinations.indexed) ...[
                    // A heading (or, when compact, a rule) wherever the
                    // group changes.
                    if (d.group != null &&
                        (i == 0 || destinations[i - 1].group != d.group))
                      compact
                          ? const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: AppSpacing.lg,
                                vertical: AppSpacing.sm,
                              ),
                              child: Divider(
                                color: AppColors.sidebarDivider,
                                height: 1,
                              ),
                            )
                          : _GroupHeading(d.group!, first: i == 0),
                    AppSidebarItem(
                      icon: d.icon,
                      label: d.label,
                      selected: i == selected,
                      compact: compact,
                      onTap: () => onSelect(i),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(color: AppColors.sidebarDivider, height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: const BoxDecoration(
                  color: AppColors.sidebarRaised,
                  borderRadius: AppRadii.mdAll,
                ),
                child: compact
                    ? Center(child: AppAvatar(name: user.fullName))
                    : Row(
                        children: [
                          AppAvatar(name: user.fullName),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user.fullName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  user.email,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.sidebarText,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupHeading extends StatelessWidget {
  const _GroupHeading(this.label, {required this.first});
  final String label;
  final bool first;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        first ? AppSpacing.xs : AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.xs,
      ),
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFF6B6558),
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

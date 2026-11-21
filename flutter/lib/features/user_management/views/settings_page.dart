import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/utils/page_padding.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_page_header.dart';
import '../widgets/settings_admin_system_section.dart';
import '../widgets/settings_categories_section.dart';
import '../widgets/settings_company_section.dart';
import '../widgets/settings_defaults_section.dart';
import '../widgets/settings_notifications_section.dart';
import '../widgets/settings_system_appearance_section.dart';

/// The sections of Settings, grouped under headings in the side tabs.
enum SettingsSection {
  profile('profile', 'Company profile', Icons.business_outlined, 'Company'),
  licenses(
    'licenses',
    'Licenses and compliance',
    Icons.verified_outlined,
    'Company',
  ),
  branding(
    'branding',
    'PDF & branding',
    Icons.picture_as_pdf_outlined,
    'Company',
  ),
  billing('billing', 'Billing defaults', Icons.percent_rounded, 'Projects'),
  schedule(
    'schedule',
    'Schedule monitoring',
    Icons.view_timeline_outlined,
    'Projects',
  ),
  categories(
    'categories',
    'Work categories',
    Icons.category_outlined,
    'Projects',
  ),
  system(
    'system',
    'System settings',
    Icons.palette_outlined,
    'System',
  ),
  notifications(
    'notifications',
    'Notifications',
    Icons.notifications_outlined,
    'System',
  ),
  documents(
    'documents',
    'Documents, audit & POS',
    Icons.upload_file_outlined,
    'System',
  );

  const SettingsSection(this.slug, this.label, this.icon, this.group);

  /// The `?section=` value.
  final String slug;
  final String label;
  final IconData icon;
  final String group;

  static SettingsSection fromSlug(String? slug) => values.firstWhere(
    (s) => s.slug == slug,
    orElse: () => SettingsSection.profile,
  );
}

/// Admin settings with GitHub-style side tabs: one section at a time, each
/// with its own save button. The section is in the URL so it can be linked.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, this.section});

  /// The `?section=` value; the company profile when missing.
  final String? section;

  @override
  Widget build(BuildContext context) {
    final current = SettingsSection.fromSlug(section);
    final wide = MediaQuery.sizeOf(context).width >= AppSpacing.wideBreakpoint;
    void open(SettingsSection s) =>
        context.go(AppRoutes.adminSettingsSection(s.slug));

    final content = AnimatedSwitcher(
      duration: AppMotion.medium,
      switchInCurve: AppMotion.switchIn,
      switchOutCurve: AppMotion.switchOut,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topLeft,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.01),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(
        key: ValueKey(current),
        child: switch (current) {
          SettingsSection.profile => const SettingsCompanySection(
            part: CompanySectionPart.profile,
          ),
          SettingsSection.licenses => const SettingsCompanySection(
            part: CompanySectionPart.licenses,
          ),
          SettingsSection.branding => const SettingsPdfBrandingSection(),
          SettingsSection.billing => const SettingsDefaultsSection(
            part: DefaultsSectionPart.billing,
          ),
          SettingsSection.schedule => const SettingsDefaultsSection(
            part: DefaultsSectionPart.schedule,
          ),
          SettingsSection.categories => const SettingsCategoriesSection(),
          SettingsSection.system => const SettingsSystemAppearanceSection(),
          SettingsSection.notifications => const SettingsNotificationsSection(),
          SettingsSection.documents => const SettingsDocumentsAuditSection(),
        },
      ),
    );

    return ListView(
      padding: pagePadding(context),
      children: [
        const AppPageHeader(
          title: 'Settings',
          subtitle: 'Company details and defaults for new projects.',
        ),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 248,
                child: _SideTabs(current: current, onSelect: open),
              ),
              const SizedBox(width: AppSpacing.xxl),
              Expanded(child: content),
            ],
          )
        else ...[
          _TopTabs(current: current, onSelect: open),
          const SizedBox(height: AppSpacing.xl),
          content,
        ],
      ],
    );
  }
}

/// Vertical section list with group headings, as on GitHub.
class _SideTabs extends StatelessWidget {
  const _SideTabs({required this.current, required this.onSelect});
  final SettingsSection current;
  final ValueChanged<SettingsSection> onSelect;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final children = <Widget>[];
    String? group;
    for (final s in SettingsSection.values) {
      if (s.group != group) {
        group = s.group;
        children.add(
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.md,
              children.isEmpty ? 0 : AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Text(
              s.group.toUpperCase(),
              style: textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
      children.add(
        _SideTab(section: s, selected: s == current, onTap: () => onSelect(s)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class _SideTab extends StatelessWidget {
  const _SideTab({
    required this.section,
    required this.selected,
    required this.onTap,
  });
  final SettingsSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final selectedBg = cs.primary.withValues(alpha: isDark ? 0.18 : 0.14);
    final selectedIconColor = isDark ? cs.secondary : cs.onPrimaryContainer;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadii.mdAll,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadii.mdAll,
          hoverColor: cs.surfaceContainerHighest,
          child: AnimatedContainer(
            duration: AppMotion.medium,
            curve: AppMotion.enter,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm + 2,
            ),
            decoration: BoxDecoration(
              color: selected ? selectedBg : selectedBg.withValues(alpha: 0),
              borderRadius: AppRadii.mdAll,
              border: Border(
                left: BorderSide(
                  color: selected
                      ? cs.primary
                      : cs.primary.withValues(alpha: 0),
                  width: 3,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  section.icon,
                  size: 18,
                  color: selected ? selectedIconColor : cs.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    section.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? cs.onSurface : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Phones: the same sections as a scrollable row of chips.
class _TopTabs extends StatelessWidget {
  const _TopTabs({required this.current, required this.onSelect});
  final SettingsSection current;
  final ValueChanged<SettingsSection> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final s in SettingsSection.values)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: ChoiceChip(
                avatar: Icon(s.icon, size: 16),
                label: Text(s.label),
                selected: s == current,
                onSelected: (_) => onSelect(s),
              ),
            ),
        ],
      ),
    );
  }
}

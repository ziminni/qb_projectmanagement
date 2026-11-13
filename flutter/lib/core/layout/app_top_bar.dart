import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/app_role.dart';
import '../../data/services/session_service.dart';
import '../../routes/routes.dart';
import '../constants/app_colors.dart';
import '../constants/app_fonts.dart';
import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import '../theme/app_motion.dart';
import 'app_account_menu.dart';
import 'app_notification_button.dart';
import 'role_navigation.dart';

/// The title the shell's header is showing, so a page's own header can
/// skip repeating it.
class AppShellTitle extends InheritedWidget {
  const AppShellTitle({super.key, required this.title, required super.child});

  final String title;

  static String? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppShellTitle>()?.title;

  @override
  bool updateShouldNotify(AppShellTitle old) => old.title != title;
}

/// The shell's header: a gold accent bar beside the section name and page
/// title, a page search in the middle, and bordered notification, settings
/// and account buttons on the right.
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({
    super.key,
    required this.session,
    required this.current,
    required this.eyebrow,
    required this.isNested,
    required this.wide,
  });

  final SessionService session;
  final RoleDestination current;

  /// Small label above the title: the page's sidebar group, or the role.
  final String eyebrow;
  final bool isNested;
  final bool wide;

  static const height = 76.0;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final role = session.activeRole!;
    final textTheme = Theme.of(context).textTheme;
    final title = AnimatedSwitcher(
      duration: AppMotion.medium,
      switchInCurve: AppMotion.switchIn,
      switchOutCurve: AppMotion.switchOut,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.centerLeft,
        children: [...previous, ?current],
      ),
      child: Column(
        key: ValueKey('${current.label}|$eyebrow'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelSmall?.copyWith(
              color: AppColors.brandGoldText,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            current.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppFonts.display,
              fontSize: wide ? 24 : 20,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              height: 1.15,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );

    return Material(
      color: AppColors.surface,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: height,
          padding: EdgeInsets.symmetric(
            horizontal: wide ? AppSpacing.xl : AppSpacing.sm,
          ),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              if (!wide)
                Builder(
                  builder: (context) => IconButton(
                    tooltip: 'Open navigation menu',
                    icon: const Icon(Icons.menu_rounded),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  ),
                ),
              if (isNested)
                IconButton(
                  tooltip: 'Back',
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => context.go(current.path),
                ),
              Container(
                width: 4,
                height: 44,
                margin: EdgeInsets.only(
                  left: isNested || !wide ? AppSpacing.xs : 0,
                  right: AppSpacing.md,
                ),
                decoration: const BoxDecoration(
                  color: AppColors.brandGold,
                  borderRadius: AppRadii.pillAll,
                ),
              ),
              Expanded(flex: 3, child: title),
              if (wide) ...[
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  flex: 4,
                  child: Align(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: _PageSearch(role: role),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
              ] else
                _SquareButton(
                  tooltip: 'Search pages',
                  icon: Icons.search_rounded,
                  onPressed: () => _showSearchSheet(context, role),
                ),
              const SizedBox(width: AppSpacing.sm),
              _Bordered(child: AppNotificationButton(userId: session.user!.id)),
              if (wide) ...[
                const SizedBox(width: AppSpacing.sm),
                _SquareButton(
                  tooltip: role == AppRole.admin ? 'Settings' : 'My profile',
                  icon: Icons.settings_outlined,
                  onPressed: () => context.go(
                    role == AppRole.admin
                        ? AppRoutes.adminSettings
                        : AppRoutes.profile,
                  ),
                ),
              ],
              const SizedBox(width: AppSpacing.sm),
              _Bordered(
                padding: EdgeInsets.only(left: 2, right: wide ? 6 : 2),
                child: AppAccountMenu(session: session, compact: !wide),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showSearchSheet(BuildContext context, AppRole role) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: _PageSearch(role: role, autofocus: true, inSheet: true),
      ),
    );
  }
}

/// Every page [role] can open, for the header search.
List<RoleDestination> _searchablePages(AppRole role) {
  final seen = <String>{};
  return [
    for (final d in [
      ...RoleNavigation.forRole(role),
      ...RoleNavigation.linkedFor(role),
      ...RoleNavigation.common,
    ])
      if (seen.add(d.path)) d,
  ];
}

class _PageSearch extends StatelessWidget {
  const _PageSearch({
    required this.role,
    this.autofocus = false,
    this.inSheet = false,
  });

  final AppRole role;
  final bool autofocus;
  final bool inSheet;

  @override
  Widget build(BuildContext context) {
    final pages = _searchablePages(role);
    void open(RoleDestination d) {
      if (inSheet) Navigator.of(context).pop();
      context.go(d.path);
    }

    return Autocomplete<RoleDestination>(
      displayStringForOption: (d) => d.label,
      optionsBuilder: (value) {
        final q = value.text.trim().toLowerCase();
        if (q.isEmpty) return inSheet ? pages : const [];
        return pages.where(
          (d) =>
              d.label.toLowerCase().contains(q) ||
              (d.group?.toLowerCase().contains(q) ?? false),
        );
      },
      onSelected: open,
      fieldViewBuilder: (context, controller, focus, onSubmit) => TextField(
        controller: controller,
        focusNode: focus,
        autofocus: autofocus,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => onSubmit(),
        decoration: InputDecoration(
          hintText: 'Search pages…',
          prefixIcon: const Icon(Icons.search_rounded),
          isDense: true,
          filled: true,
          fillColor: AppColors.background,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: const OutlineInputBorder(
            borderRadius: AppRadii.mdAll,
            borderSide: BorderSide(color: AppColors.border),
          ),
          enabledBorder: const OutlineInputBorder(
            borderRadius: AppRadii.mdAll,
            borderSide: BorderSide(color: AppColors.border),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: AppRadii.mdAll,
            borderSide: BorderSide(color: AppColors.brandGold, width: 1.5),
          ),
        ),
      ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 6,
          borderRadius: AppRadii.mdAll,
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320, maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              shrinkWrap: true,
              children: [
                for (final d in options)
                  ListTile(
                    dense: true,
                    leading: Icon(d.icon, size: 20),
                    title: Text(d.label),
                    subtitle: d.group == null ? null : Text(d.group!),
                    onTap: () => onSelected(d),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A rounded, bordered frame for header buttons.
class _Bordered extends StatelessWidget {
  const _Bordered({required this.child, this.padding = EdgeInsets.zero});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: AppRadii.mdAll,
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

class _SquareButton extends StatelessWidget {
  const _SquareButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _Bordered(
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon),
        onPressed: onPressed,
      ),
    );
  }
}

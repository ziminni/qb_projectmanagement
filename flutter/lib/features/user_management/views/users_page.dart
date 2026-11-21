import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_fonts.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/models/app_role.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/widgets/app_confirm_dialog.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_page_header.dart';
import '../viewmodels/admin_audit.dart';
import '../viewmodels/users_viewmodel.dart';
import '../widgets/admin_dashboard/admin_dashboard_kit.dart';
import '../widgets/user_management_roles_dialog.dart';

class UsersPage extends StatefulWidget {
  const UsersPage({super.key, this.initialRole});

  /// Role filter to start with, as its API value (from `?role=`).
  final String? initialRole;

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  final _search = TextEditingController();
  late final UsersViewModel _vm = () {
    final vm = UsersViewModel(
      users: getIt(),
      session: getIt(),
      audit: AdminAudit.fromLocator(),
    );
    for (final r in AppRole.values) {
      if (r.apiValue == widget.initialRole) vm.setRoleFilter(r);
    }
    return vm..load();
  }();

  @override
  void dispose() {
    _search.dispose();
    _vm.dispose();
    super.dispose();
  }

  void _clearFilters() {
    _search.clear();
    _vm.clearFilters();
  }

  Future<void> _toggleActive(UserListItem item) async {
    final user = item.user;
    final activate = !user.isActive;
    final ok = await showAppConfirmDialog(
      context,
      title: activate
          ? 'Reactivate ${user.fullName}?'
          : 'Deactivate ${user.fullName}?',
      message: activate
          ? 'They will be able to sign in again with their current roles.'
          : 'They will be signed out and cannot sign in until you '
                'reactivate them. Their records stay as they are.',
      confirmLabel: activate ? 'Reactivate' : 'Deactivate',
      destructive: !activate,
    );
    if (!ok || !mounted) return;
    await reportAction(
      context,
      _vm.setActive(user, activate),
      success: activate
          ? '${user.fullName} can sign in again.'
          : '${user.fullName} was deactivated.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Consumer<UsersViewModel>(
        builder: (context, vm, _) {
          if (vm.isLoading) return const AdminTabSkeleton();
          if (vm.error != null) {
            return AppEmptyState(
              message: vm.error!,
              action: OutlinedButton.icon(
                onPressed: vm.load,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            );
          }

          final items = vm.items;
          final wide =
              MediaQuery.sizeOf(context).width >= AppSpacing.wideBreakpoint;
          final theme = Theme.of(context);
          final cs = theme.colorScheme;
          final isDark = theme.brightness == Brightness.dark;

          return Stack(
            children: [
              ListView(
                padding: pagePadding(
                  context,
                ).add(const EdgeInsets.only(bottom: 76)),
                children: [
                  const AppPageHeader(
                    title: 'Team & access directory',
                    subtitle:
                        'Manage staff profiles, assigned roles, and sign-in status across Queen Builders.',
                  ),

                  // Summary stat tiles (click to filter by status).
                  _AccountSummaryTiles(
                    total: vm.totalCount,
                    active: vm.activeCount,
                    inactive: vm.inactiveCount,
                    selected: vm.statusFilter,
                    onSelect: vm.setStatusFilter,
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // Unified directory panel: toolbar + sortable ledger.
                  Material(
                    color: cs.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadii.lgAll,
                      side: BorderSide(color: cs.outlineVariant),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Toolbar strip.
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: wide ? 20 : AppSpacing.md,
                            vertical: AppSpacing.md + 2,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? cs.surfaceContainer
                                : cs.surfaceContainerLow.withValues(alpha: 0.65),
                            border: Border(
                              bottom: BorderSide(color: cs.outlineVariant),
                            ),
                          ),
                          child: _DirectoryToolbar(
                            vm: vm,
                            search: _search,
                            wide: wide,
                            onAddUser: () => context.go(AppRoutes.adminUserNew),
                          ),
                        ),

                        // Result meta strip (only when filtered or on narrow screens).
                        if (vm.isFiltered)
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: wide ? 20 : AppSpacing.md,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: cs.outlineVariant),
                              ),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  'Showing ${items.length} of ${vm.totalCount} users',
                                  style: TextStyle(
                                    fontFamily: AppFonts.body,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                const Spacer(),
                                TextButton.icon(
                                  onPressed: _clearFilters,
                                  style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.filter_alt_off_outlined,
                                    size: 15,
                                  ),
                                  label: const Text(
                                    'Clear filters',
                                    style: TextStyle(fontSize: 12.5),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        if (items.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.xxl,
                            ),
                            child: AppEmptyState(
                              message: 'No users match these filters.',
                              icon: Icons.person_search_outlined,
                              action: OutlinedButton(
                                onPressed: _clearFilters,
                                child: const Text('Clear filters'),
                              ),
                            ),
                          )
                        else ...[
                          if (wide) _TableHeader(vm: vm),
                          for (final (i, item) in items.indexed) ...[
                            if (i > 0)
                              Divider(
                                height: 1,
                                indent: wide ? 20 : 16,
                                endIndent: wide ? 20 : 16,
                                color: cs.outlineVariant,
                              ),
                            _UserRow(
                              item: item,
                              wide: wide,
                              isSelf: vm.isSelf(item.user),
                              onOpen: () =>
                                  context.go(AppRoutes.adminUser(item.user.id)),
                              onEdit: () => context.go(
                                AppRoutes.adminUserEdit(item.user.id),
                              ),
                              onToggleActive: () => _toggleActive(item),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ],
              ),

              // Floating circular "?" button for Roles & permissions modal.
              Positioned(
                right: AppSpacing.xl,
                bottom: AppSpacing.xl,
                child: Tooltip(
                  message: 'Roles and permissions',
                  child: FloatingActionButton(
                    key: const ValueKey('users-roles-help-fab'),
                    heroTag: 'users-roles-help-fab',
                    onPressed: () => showRolesPermissionsDialog(context),
                    shape: const CircleBorder(),
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    elevation: 4,
                    child: const Icon(Icons.question_mark_rounded, size: 22),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AccountSummaryTiles extends StatelessWidget {
  const _AccountSummaryTiles({
    required this.total,
    required this.active,
    required this.inactive,
    required this.selected,
    required this.onSelect,
  });

  final int total;
  final int active;
  final int inactive;
  final UserStatusFilter selected;
  final ValueChanged<UserStatusFilter> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final tiles = [
      _StatSquare(
        label: 'Total accounts',
        value: total,
        icon: Icons.groups_2_outlined,
        accentColor: isDark ? cs.secondary : cs.onPrimaryContainer,
        tintColor: cs.primary.withValues(alpha: isDark ? 0.2 : 0.13),
        selected: selected == UserStatusFilter.all,
        onTap: () => onSelect(UserStatusFilter.all),
      ),
      _StatSquare(
        label: 'Active users',
        value: active,
        icon: Icons.verified_user_outlined,
        accentColor: isDark ? const Color(0xFF6EE7B7) : AppColors.success,
        tintColor: isDark
            ? const Color(0x2210B981)
            : AppColors.successContainer,
        selected: selected == UserStatusFilter.active,
        onTap: () => onSelect(UserStatusFilter.active),
      ),
      _StatSquare(
        label: 'Inactive users',
        value: inactive,
        icon: Icons.person_off_outlined,
        accentColor: isDark ? const Color(0xFFB5AFA3) : AppColors.textSecondary,
        tintColor: isDark ? const Color(0x226B7280) : AppColors.surfaceMuted,
        selected: selected == UserStatusFilter.inactive,
        onTap: () => onSelect(UserStatusFilter.inactive),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 560) {
          return Row(
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.md),
                Expanded(child: tiles[i]),
              ],
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.sm),
              tiles[i],
            ],
          ],
        );
      },
    );
  }
}

class _StatSquare extends StatelessWidget {
  const _StatSquare({
    required this.label,
    required this.value,
    required this.icon,
    required this.accentColor,
    required this.tintColor,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color accentColor;
  final Color tintColor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.lgAll,
        side: BorderSide(
          color: selected
              ? cs.primary.withValues(alpha: isDark ? 0.65 : 0.55)
              : cs.outlineVariant,
          width: selected ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: tintColor,
                  borderRadius: AppRadii.mdAll,
                ),
                child: Icon(icon, size: 20, color: accentColor),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$value',
                      style: theme.textTheme.headlineSmall
                          ?.merge(AppTextStyles.numeric)
                          .copyWith(
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                            height: 1.1,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppFonts.body,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DirectoryToolbar extends StatelessWidget {
  const _DirectoryToolbar({
    required this.vm,
    required this.search,
    required this.wide,
    required this.onAddUser,
  });

  final UsersViewModel vm;
  final TextEditingController search;
  final bool wide;
  final VoidCallback onAddUser;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final searchField = SizedBox(
      width: wide ? 280 : double.infinity,
      child: TextField(
        controller: search,
        onChanged: vm.setQuery,
        style: TextStyle(fontSize: 13.5, color: cs.onSurface),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 11,
          ),
          filled: true,
          fillColor: cs.surface,
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 18,
            color: cs.onSurfaceVariant,
          ),
          hintText: 'Search name, email or phone',
          suffixIcon: vm.query.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close_rounded, size: 16),
                  onPressed: () {
                    search.clear();
                    vm.setQuery('');
                  },
                ),
          border: OutlineInputBorder(
            borderRadius: AppRadii.mdAll,
            borderSide: BorderSide(color: cs.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: AppRadii.mdAll,
            borderSide: BorderSide(color: cs.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: AppRadii.mdAll,
            borderSide: BorderSide(color: cs.primary, width: 1.4),
          ),
        ),
      ),
    );

    final roleDropdown = SizedBox(
      width: wide ? 190 : double.infinity,
      child: DropdownButtonFormField<AppRole?>(
        key: ValueKey(vm.roleFilter),
        initialValue: vm.roleFilter,
        isExpanded: true,
        style: TextStyle(
          fontFamily: AppFonts.body,
          fontSize: 13.5,
          color: cs.onSurface,
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          filled: true,
          fillColor: cs.surface,
          labelText: 'Role',
          border: OutlineInputBorder(
            borderRadius: AppRadii.mdAll,
            borderSide: BorderSide(color: cs.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: AppRadii.mdAll,
            borderSide: BorderSide(color: cs.outlineVariant),
          ),
        ),
        items: [
          const DropdownMenuItem(value: null, child: Text('All roles')),
          for (final r in AppRole.values)
            DropdownMenuItem(value: r, child: Text(r.label)),
        ],
        onChanged: vm.setRoleFilter,
      ),
    );

    final statusDropdown = SizedBox(
      width: wide ? 175 : double.infinity,
      child: DropdownButtonFormField<UserStatusFilter>(
        key: ValueKey('status-${vm.statusFilter.name}'),
        initialValue: vm.statusFilter,
        isExpanded: true,
        style: TextStyle(
          fontFamily: AppFonts.body,
          fontSize: 13.5,
          color: cs.onSurface,
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          filled: true,
          fillColor: cs.surface,
          labelText: 'Status',
          border: OutlineInputBorder(
            borderRadius: AppRadii.mdAll,
            borderSide: BorderSide(color: cs.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: AppRadii.mdAll,
            borderSide: BorderSide(color: cs.outlineVariant),
          ),
        ),
        items: [
          DropdownMenuItem(
            value: UserStatusFilter.all,
            child: Text('All (${vm.totalCount})'),
          ),
          DropdownMenuItem(
            value: UserStatusFilter.active,
            child: Text('Active (${vm.activeCount})'),
          ),
          DropdownMenuItem(
            value: UserStatusFilter.inactive,
            child: Text('Inactive (${vm.inactiveCount})'),
          ),
        ],
        onChanged: (v) {
          if (v != null) vm.setStatusFilter(v);
        },
      ),
    );

    final addUserButton = FilledButton.icon(
      onPressed: onAddUser,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
      icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
      label: const Text('Add user'),
    );

    if (wide) {
      return Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [searchField, roleDropdown, statusDropdown],
          ),
          addUserButton,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        searchField,
        const SizedBox(height: AppSpacing.sm),
        roleDropdown,
        const SizedBox(height: AppSpacing.sm),
        statusDropdown,
        const SizedBox(height: AppSpacing.md),
        addUserButton,
      ],
    );
  }
}

/// Column widths shared by the header and rows on wide screens.
const _nameFlex = 4;
const _rolesFlex = 3;
const _statusWidth = 132.0;
const _addedWidth = 132.0;
const _menuWidth = 44.0;

class _TableHeader extends StatelessWidget {
  const _TableHeader({required this.vm});
  final UsersViewModel vm;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget head(UserSort column) {
      final active = vm.sort == column;
      return InkWell(
        onTap: () => vm.sortBy(column),
        borderRadius: AppRadii.smAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  column.label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppFonts.body,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: active ? cs.onSurface : cs.onSurfaceVariant,
                  ),
                ),
              ),
              if (active) ...[
                const SizedBox(width: 4),
                Icon(
                  vm.ascending
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  size: 13,
                  color: cs.primary,
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 38 + AppSpacing.md),
          Expanded(
            flex: _nameFlex,
            child: Align(
              alignment: Alignment.centerLeft,
              child: head(UserSort.name),
            ),
          ),
          Expanded(
            flex: _rolesFlex,
            child: Align(
              alignment: Alignment.centerLeft,
              child: head(UserSort.role),
            ),
          ),
          SizedBox(
            width: _statusWidth,
            child: Align(
              alignment: Alignment.centerLeft,
              child: head(UserSort.status),
            ),
          ),
          SizedBox(
            width: _addedWidth,
            child: Align(
              alignment: Alignment.centerLeft,
              child: head(UserSort.added),
            ),
          ),
          const SizedBox(width: _menuWidth),
        ],
      ),
    );
  }
}

class _UserRow extends StatefulWidget {
  const _UserRow({
    required this.item,
    required this.wide,
    required this.isSelf,
    required this.onOpen,
    required this.onEdit,
    required this.onToggleActive,
  });

  final UserListItem item;
  final bool wide;
  final bool isSelf;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;

  @override
  State<_UserRow> createState() => _UserRowState();
}

class _UserRowState extends State<_UserRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final user = item.user;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final dim = !user.isActive;

    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                user.fullName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppFonts.body,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: dim ? cs.onSurfaceVariant : cs.onSurface,
                  height: 1.25,
                ),
              ),
            ),
            if (widget.isSelf) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: isDark ? 0.2 : 0.14),
                  borderRadius: AppRadii.pillAll,
                ),
                child: Text(
                  'you',
                  style: TextStyle(
                    fontFamily: AppFonts.body,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: isDark ? cs.secondary : cs.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          user.email,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: AppFonts.body,
            fontSize: 12.5,
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );

    final roles = item.roles.isEmpty
        ? _MiniPill(
            label: 'No role',
            foreground: isDark ? const Color(0xFFFCA5A5) : AppColors.error,
            background: isDark
                ? const Color(0x33EF4444)
                : AppColors.errorContainer,
          )
        : Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [for (final r in item.roles) _RoleChip(role: r)],
          );

    final status = _StatusBadge(active: user.isActive);

    final menu = SizedBox(
      width: _menuWidth,
      child: PopupMenuButton<String>(
        tooltip: 'Actions',
        icon: Icon(
          Icons.more_vert_rounded,
          size: 19,
          color: cs.onSurfaceVariant,
        ),
        onSelected: (v) => switch (v) {
          'open' => widget.onOpen(),
          'edit' => widget.onEdit(),
          _ => widget.onToggleActive(),
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'open', child: Text('View details')),
          const PopupMenuItem(value: 'edit', child: Text('Edit')),
          if (!widget.isSelf || !user.isActive)
            PopupMenuItem(
              value: 'toggle',
              child: Text(
                user.isActive ? 'Deactivate' : 'Reactivate',
                style: TextStyle(
                  color: user.isActive
                      ? (isDark ? const Color(0xFFFCA5A5) : AppColors.error)
                      : null,
                ),
              ),
            ),
        ],
      ),
    );

    final rowBg = _hovered
        ? cs.primary.withValues(alpha: isDark ? 0.07 : 0.045)
        : Colors.transparent;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: rowBg,
        child: InkWell(
          onTap: widget.onOpen,
          hoverColor: Colors.transparent,
          child: widget.wide
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 13,
                  ),
                  child: Row(
                    children: [
                      Opacity(
                        opacity: dim ? 0.5 : 1,
                        child: AppAvatar(name: user.fullName, size: 38),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(flex: _nameFlex, child: identity),
                      Expanded(
                        flex: _rolesFlex,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: roles,
                        ),
                      ),
                      SizedBox(
                        width: _statusWidth,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: status,
                        ),
                      ),
                      SizedBox(
                        width: _addedWidth,
                        child: Text(
                          user.createdAt == null
                              ? '—'
                              : Formatters.date(user.createdAt!),
                          style: theme.textTheme.bodySmall
                              ?.merge(AppTextStyles.numeric)
                              .copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                      menu,
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Opacity(
                        opacity: dim ? 0.5 : 1,
                        child: AppAvatar(name: user.fullName, size: 38),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            identity,
                            const SizedBox(height: AppSpacing.sm),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [roles, status],
                            ),
                          ],
                        ),
                      ),
                      menu,
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dotColor = active
        ? (isDark ? const Color(0xFF34D399) : AppColors.success)
        : (isDark ? const Color(0xFF9CA3AF) : AppColors.textSecondary);
    final fg = active
        ? (isDark ? const Color(0xFF6EE7B7) : AppColors.success)
        : (isDark ? const Color(0xFFB5AFA3) : AppColors.textSecondary);
    final bg = active
        ? (isDark ? const Color(0x2210B981) : AppColors.successContainer)
        : (isDark ? const Color(0x226B7280) : AppColors.surfaceMuted);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadii.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            active ? 'Active' : 'Inactive',
            style: TextStyle(
              fontFamily: AppFonts.body,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: fg,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role});
  final AppRole role;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final (fg, bg) = switch (role) {
      AppRole.admin => isDark
          ? (const Color(0xFFF3DFA6), const Color(0x2EAC934F))
          : (AppColors.brandBlack, AppColors.brandGoldLight),
      AppRole.owner => isDark
          ? (const Color(0xFFE1C684), const Color(0x24AC934F))
          : (AppColors.brandGoldText, AppColors.selected),
      AppRole.accountant => isDark
          ? (const Color(0xFF6EE7B7), const Color(0x2210B981))
          : (AppColors.success, AppColors.successContainer),
      AppRole.siteEngineer => isDark
          ? (const Color(0xFFFDBA74), const Color(0x26EA580C))
          : (AppColors.warning, AppColors.warningContainer),
      AppRole.client => isDark
          ? (const Color(0xFFD6D3D1), const Color(0x2678716C))
          : (AppColors.textSecondary, AppColors.surfaceMuted),
    };
    return _MiniPill(label: role.label, foreground: fg, background: bg);
  }
}

class _MiniPill extends StatelessWidget {
  const _MiniPill({
    required this.label,
    required this.foreground,
    required this.background,
  });

  final String label;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadii.pillAll,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppFonts.body,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: foreground,
          height: 1.2,
        ),
      ),
    );
  }
}

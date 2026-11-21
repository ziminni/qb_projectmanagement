import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../data/models/app_role.dart';
import '../../data/services/local_settings_service.dart';
import '../../data/services/session_service.dart';
import '../../routes/routes.dart';
import '../constants/app_colors.dart';
import '../constants/app_spacing.dart';
import '../di/service_locator.dart';
import 'app_sidebar.dart';
import 'app_top_bar.dart';
import 'role_navigation.dart';

class AppShellBack extends InheritedWidget {
  const AppShellBack({super.key, required this.onBack, required super.child});

  final VoidCallback onBack;

  static void goBack(BuildContext context) {
    final inherited = context
        .dependOnInheritedWidgetOfExactType<AppShellBack>();
    if (inherited != null) {
      inherited.onBack();
      return;
    }
    final router = GoRouter.of(context);
    if (router.canPop()) router.pop();
  }

  @override
  bool updateShouldNotify(AppShellBack oldWidget) => false;
}

class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      style: ButtonStyle(
        backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
        side: const WidgetStatePropertyAll(BorderSide.none),
        elevation: const WidgetStatePropertyAll(0),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.xs,
          ),
        ),
        overlayColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.hovered)
              ? AppColors.surfaceMuted
              : Colors.transparent,
        ),
      ),
      icon: const Icon(Icons.arrow_back_rounded, size: 18),
      label: const Text('Back'),
    );
  }
}

/// The app shell for the active role: animated collapsible sidebar on desktop
/// (default collapsed icon rail) and drawer on phones.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final List<String> _history = [];
  String? _poppingTo;
  AppRole? _lastRole;
  late final LocalSettingsService _localSettings = getIt<LocalSettingsService>();

  @override
  void initState() {
    super.initState();
    _history.add(widget.location);
    _localSettings.addListener(_onLocalSettingsChanged);
  }

  @override
  void dispose() {
    _localSettings.removeListener(_onLocalSettingsChanged);
    super.dispose();
  }

  void _onLocalSettingsChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void didUpdateWidget(AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.location == oldWidget.location) return;
    if (_poppingTo != null && widget.location == _poppingTo) {
      _poppingTo = null;
      return;
    }
    _poppingTo = null;
    if (_history.isEmpty || _history.last != widget.location) {
      _history.add(widget.location);
    }
  }

  void _syncRoleAndRoot(
    AppRole role,
    List<RoleDestination> destinations,
    int selected,
  ) {
    if (_lastRole != role) {
      _lastRole = role;
      _history
        ..clear()
        ..add(widget.location);
      return;
    }
    if (selected >= 0 && widget.location == destinations[selected].path) {
      _history
        ..clear()
        ..add(widget.location);
    }
  }

  void _goBack(
    BuildContext context,
    RoleDestination current,
    List<RoleDestination> destinations,
  ) {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
      return;
    }
    if (_history.length >= 2) {
      _history.removeLast();
      final target = _history.last;
      _poppingTo = target;
      context.go(target);
      return;
    }
    context.go(
      current.path != widget.location ? current.path : destinations.first.path,
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionService>();
    final role = session.activeRole;
    if (role == null || session.user == null) return const SizedBox.shrink();

    final destinations = RoleNavigation.forRole(role);
    final selected = RoleNavigation.indexFor(role, widget.location);
    _syncRoleAndRoot(role, destinations, selected);
    final current = selected >= 0
        ? destinations[selected]
        : RoleNavigation.sectionFor(widget.location) ?? destinations.first;
    final isNested = selected < 0 || widget.location != current.path;
    final hasOwnBack = RegExp(r'^/projects/\d+').hasMatch(widget.location);
    final wide = MediaQuery.sizeOf(context).width >= AppSpacing.wideBreakpoint;
    final collapsed = _localSettings.sidebarCollapsed;
    final finish = _localSettings.sidebarFinish;
    final accent = _localSettings.accent;

    void select(int index) => context.go(destinations[index].path);

    void signOut() {
      session.signOut();
      if (context.mounted) context.go(AppRoutes.landing);
    }

    final appBar = AppTopBar(
      session: session,
      current: current,
      eyebrow: current.group ?? role.label,
      isNested: isNested,
      wide: wide,
    );

    final bodyContent = AppShellTitle(
      title: current.label,
      child: AppShellBack(
        onBack: () => _goBack(context, current, destinations),
        child: isNested && !hasOwnBack
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      wide ? AppSpacing.xl : AppSpacing.sm,
                      AppSpacing.sm,
                      wide ? AppSpacing.xl : AppSpacing.sm,
                      0,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: AppBackButton(
                        onPressed: () =>
                            _goBack(context, current, destinations),
                      ),
                    ),
                  ),
                  Expanded(child: widget.child),
                ],
              )
            : widget.child,
      ),
    );

    final Widget scaffold = wide
        ? Scaffold(
            body: Row(
              children: [
                AppSidebar(
                  destinations: destinations,
                  selected: selected,
                  onSelect: select,
                  user: session.user!,
                  role: role,
                  compact: collapsed,
                  finish: finish,
                  accent: accent,
                  onExpand: () => _localSettings.setSidebarCollapsed(false),
                  onCollapse: () => _localSettings.setSidebarCollapsed(true),
                  onSignOut: signOut,
                ),
                Expanded(
                  child: Scaffold(
                    appBar: appBar,
                    body: LayoutBuilder(
                      builder: (context, constraints) => MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                          size: Size(
                            constraints.maxWidth,
                            MediaQuery.sizeOf(context).height,
                          ),
                        ),
                        child: bodyContent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          )
        : Scaffold(
            appBar: appBar,
            drawer: Drawer(
              width: AppSidebar.fullWidth,
              backgroundColor: finish.background,
              shape: const RoundedRectangleBorder(),
              child: AppSidebar(
                destinations: destinations,
                selected: selected,
                onSelect: (index) {
                  Navigator.of(context).pop();
                  select(index);
                },
                user: session.user!,
                role: role,
                finish: finish,
                accent: accent,
                onSignOut: () {
                  Navigator.of(context).pop();
                  signOut();
                },
              ),
            ),
            body: bodyContent,
          );

    return scaffold;
  }
}

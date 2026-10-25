import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../data/services/session_service.dart';
import '../constants/app_spacing.dart';
import 'app_account_menu.dart';
import 'app_notification_button.dart';
import 'role_navigation.dart';

/// The app shell for the active role: a navigation rail on wide screens and
/// a drawer on phones. Each role gets its own navigation from
/// [RoleNavigation].
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionService>();
    final role = session.activeRole;
    // Signed out: drop the pages before the router redirects to login.
    if (role == null || session.user == null) return const SizedBox.shrink();

    final destinations = RoleNavigation.forRole(role);
    final selected = RoleNavigation.indexFor(role, location);
    final current = selected >= 0
        ? destinations[selected]
        : RoleNavigation.sectionFor(location) ?? destinations.first;
    final isNested = location != current.path;
    final wide = MediaQuery.sizeOf(context).width >= AppSpacing.wideBreakpoint;

    void select(int index) => context.go(destinations[index].path);

    final appBar = AppBar(
      title: Text(current.label),
      leading: isNested
          ? IconButton(
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go(current.path),
            )
          : null,
      actions: [
        AppNotificationButton(userId: session.user!.id),
        AppAccountMenu(session: session),
        const SizedBox(width: AppSpacing.sm),
      ],
    );

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              extended: MediaQuery.sizeOf(context).width >= 1200,
              selectedIndex: selected >= 0 ? selected : null,
              onDestinationSelected: select,
              labelType: MediaQuery.sizeOf(context).width >= 1200
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.all,
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Icon(Icons.construction, size: 32),
              ),
              destinations: [
                for (final d in destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Scaffold(
                appBar: appBar,
                // Report the content area's width, not the window's, so
                // pages centre and switch layouts beside the rail.
                body: LayoutBuilder(
                  builder: (context, constraints) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      size: Size(
                        constraints.maxWidth,
                        MediaQuery.sizeOf(context).height,
                      ),
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: appBar,
      drawer: NavigationDrawer(
        selectedIndex: selected >= 0 ? selected : null,
        onDestinationSelected: (index) {
          Navigator.of(context).pop();
          select(index);
        },
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 16, 16, 10),
            child: Text(
              role.label,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          for (final d in destinations)
            NavigationDrawerDestination(
              icon: Icon(d.icon),
              label: Text(d.label),
            ),
        ],
      ),
      body: child,
    );
  }
}

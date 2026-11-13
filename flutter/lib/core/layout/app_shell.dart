import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../data/services/session_service.dart';
import '../constants/app_colors.dart';
import '../constants/app_spacing.dart';
import 'app_sidebar.dart';
import 'app_top_bar.dart';
import 'role_navigation.dart';

/// The app shell for the active role: the dark sidebar on wide screens
/// (icons only below 1200 px) and the same sidebar in a drawer on phones. Each role gets its own navigation from
/// [RoleNavigation].
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionService>();
    final role = session.activeRole;
    // Signed out: drop the pages before the router redirects to the landing page.
    if (role == null || session.user == null) return const SizedBox.shrink();

    final destinations = RoleNavigation.forRole(role);
    final selected = RoleNavigation.indexFor(role, location);
    final current = selected >= 0
        ? destinations[selected]
        : RoleNavigation.sectionFor(location) ?? destinations.first;
    final isNested = location != current.path;
    final wide = MediaQuery.sizeOf(context).width >= AppSpacing.wideBreakpoint;

    void select(int index) => context.go(destinations[index].path);

    final appBar = AppTopBar(
      session: session,
      current: current,
      eyebrow: current.group ?? role.label,
      isNested: isNested,
      wide: wide,
    );

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            AppSidebar(
              destinations: destinations,
              selected: selected,
              onSelect: select,
              user: session.user!,
              role: role,
              compact: MediaQuery.sizeOf(context).width < 1200,
            ),
            Expanded(
              child: Scaffold(
                appBar: appBar,
                // Report the content area's width, not the window's, so
                // pages centre and switch layouts beside the sidebar.
                body: LayoutBuilder(
                  builder: (context, constraints) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      size: Size(
                        constraints.maxWidth,
                        MediaQuery.sizeOf(context).height,
                      ),
                    ),
                    child: AppShellTitle(title: current.label, child: child),
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
      drawer: Drawer(
        width: AppSidebar.fullWidth,
        backgroundColor: AppColors.sidebar,
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
        ),
      ),
      body: AppShellTitle(title: current.label, child: child),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/page_padding.dart';
import '../widgets/admin_dashboard/admin_activity_tab.dart';
import '../widgets/admin_dashboard/admin_finance_tab.dart';
import '../widgets/admin_dashboard/admin_people_tab.dart';
import '../widgets/admin_dashboard/admin_procurement_tab.dart';
import '../widgets/admin_dashboard/admin_projects_tab.dart';
import '../widgets/admin_dashboard/admin_system_tab.dart';

/// The tabs of the admin dashboard, in order. The slug is the `?tab=` value.
enum AdminDashboardTab {
  system('system', 'System', Icons.dns_outlined),
  projects('projects', 'Projects', Icons.apartment_outlined),
  finance('finance', 'Finance', Icons.account_balance_outlined),
  procurement('procurement', 'Procurement', Icons.shopping_cart_outlined),
  people('people', 'People & Labor', Icons.groups_outlined),
  activity('activity', 'Activity', Icons.insights_outlined);

  const AdminDashboardTab(this.slug, this.label, this.icon);

  final String slug;
  final String label;
  final IconData icon;

  static AdminDashboardTab fromSlug(String? slug) =>
      values.firstWhere((t) => t.slug == slug, orElse: () => system);
}

/// The system admin's landing screen: one tab per area of the company.
/// Each tab loads its own figures the first time it is opened.
class AdminOverviewPage extends StatelessWidget {
  const AdminOverviewPage({super.key, this.tab});

  /// The `?tab=` value; System when missing.
  final String? tab;

  @override
  Widget build(BuildContext context) {
    final initial = AdminDashboardTab.fromSlug(tab);
    final padding = pagePadding(context);
    return DefaultTabController(
      length: AdminDashboardTab.values.length,
      initialIndex: initial.index,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(
              padding.left - 12,
              AppSpacing.sm,
              padding.right - 12,
              0,
            ),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
              ),
              dividerColor: Colors.transparent,
              tabs: [
                for (final t in AdminDashboardTab.values)
                  Tab(
                    height: 44,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(t.icon, size: 18),
                        const SizedBox(width: AppSpacing.sm),
                        Text(t.label),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [
                AdminSystemTab(),
                AdminProjectsTab(),
                AdminFinanceTab(),
                AdminProcurementTab(),
                AdminPeopleTab(),
                AdminActivityTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_padding.dart';
import '../../../shared/widgets/app_page_header.dart';
import '../viewmodels/audit_log_viewmodel.dart';
import '../widgets/user_management_audit_tile.dart';
import '../widgets/admin_dashboard/admin_dashboard_kit.dart';

class AuditLogPage extends StatefulWidget {
  const AuditLogPage({super.key});

  @override
  State<AuditLogPage> createState() => _AuditLogPageState();
}

class _AuditLogPageState extends State<AuditLogPage> {
  final _search = TextEditingController();
  late final _vm = AuditLogViewModel(auditLog: getIt(), users: getIt())..load();

  @override
  void dispose() {
    _search.dispose();
    _vm.dispose();
    super.dispose();
  }

  Future<void> _copyCsv() async {
    await Clipboard.setData(ClipboardData(text: _vm.toCsv()));
    if (!mounted) return;
    showAppMessage(
      context,
      'Copied ${_vm.items.length} entries as CSV. Paste them into a '
      'spreadsheet.',
    );
  }

  String _dayLabel(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return Formatters.date(day);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Consumer<AuditLogViewModel>(
        builder: (context, vm, _) {
          if (vm.isLoading) {
            return const AdminTabSkeleton();
          }
          if (vm.error != null) {
            return AdminErrorState(message: vm.error!, onRetry: vm.load);
          }
          final groups = vm.itemsByDay;
          final textTheme = Theme.of(context).textTheme;
          return ListView(
            padding: pagePadding(context),
            children: [
              AppPageHeader(
                title: 'Activity & audit trail',
                subtitle:
                    'Every approval, order, delivery, payment and admin '
                    'change, with who did it and when.',
                actions: [
                  OutlinedButton.icon(
                    onPressed: vm.items.isEmpty ? null : _copyCsv,
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Copy as CSV'),
                  ),
                ],
              ),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 320,
                    child: TextField(
                      controller: _search,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search action, person or detail',
                      ),
                      onChanged: vm.setQuery,
                    ),
                  ),
                  SizedBox(
                    width: 240,
                    child: DropdownButtonFormField<int?>(
                      key: ValueKey('user-${vm.userFilter}'),
                      initialValue: vm.userFilter,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Person'),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Everyone'),
                        ),
                        for (final e in vm.userNames.entries)
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                      ],
                      onChanged: vm.setUser,
                    ),
                  ),
                  SizedBox(
                    width: 240,
                    child: DropdownButtonFormField<String?>(
                      key: ValueKey('entity-${vm.entityFilter}'),
                      initialValue: vm.entityFilter,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Record'),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('All records'),
                        ),
                        for (final e in vm.entities)
                          DropdownMenuItem(
                            value: e,
                            child: Text(AuditLogViewModel.entityLabel(e)),
                          ),
                      ],
                      onChanged: vm.setEntity,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final p in AuditPeriod.values)
                    ChoiceChip(
                      label: Text(p.label),
                      selected: vm.period == p,
                      onSelected: (_) => vm.setPeriod(p),
                    ),
                  if (vm.hasFilters)
                    TextButton.icon(
                      onPressed: () {
                        _search.clear();
                        vm.clearFilters();
                      },
                      icon: const Icon(Icons.filter_alt_off_outlined),
                      label: const Text('Clear filters'),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                vm.items.length == 1 ? '1 entry' : '${vm.items.length} entries',
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (groups.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.search_off),
                    title: Text('No entries match.'),
                    subtitle: Text('Try a longer period or clear filters.'),
                  ),
                ),
              for (final (day, logs) in groups) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xs,
                    AppSpacing.md,
                    AppSpacing.xs,
                    AppSpacing.sm,
                  ),
                  child: Text(_dayLabel(day), style: textTheme.titleSmall),
                ),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (final (i, l) in logs.indexed) ...[
                        if (i > 0) const Divider(height: 1),
                        UserManagementAuditTile(
                          log: l,
                          userName: vm.userName(l.userId),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

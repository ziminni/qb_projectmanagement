import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/page_padding.dart';
import '../../../../shared/widgets/app_empty_state.dart';
import '../../viewmodels/admin_dashboard/admin_tab_viewmodel.dart';

/// Hosts one dashboard tab: creates its view model once, keeps it alive
/// while the admin switches tabs, and handles loading, errors and refresh.
class AdminTabHost<T extends AdminTabViewModel> extends StatefulWidget {
  const AdminTabHost({super.key, required this.create, required this.build});

  final T Function() create;

  /// The tab's content, as children of a scrolling list.
  final List<Widget> Function(BuildContext context, T vm) build;

  @override
  State<AdminTabHost<T>> createState() => _AdminTabHostState<T>();
}

class _AdminTabHostState<T extends AdminTabViewModel>
    extends State<AdminTabHost<T>>
    with AutomaticKeepAliveClientMixin {
  late final T _vm = widget.create()..load();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ChangeNotifierProvider<T>.value(
      value: _vm,
      child: Consumer<T>(
        builder: (context, vm, _) {
          if (vm.isLoading && vm.loadedAt == null) {
            return const AdminTabSkeleton();
          }
          if (vm.error != null) {
            return AdminErrorState(message: vm.error!, onRetry: vm.load);
          }
          return RefreshIndicator(
            onRefresh: vm.load,
            child: ListView(
              padding: pagePadding(context).copyWith(top: AppSpacing.lg),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                _UpdatedLine(vm: vm),
                const SizedBox(height: AppSpacing.md),
                ...widget.build(context, vm),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _UpdatedLine extends StatelessWidget {
  const _UpdatedLine({required this.vm});
  final AdminTabViewModel vm;

  @override
  Widget build(BuildContext context) {
    final at = vm.loadedAt;
    return Row(
      children: [
        Expanded(
          child: Text(
            at == null ? '' : 'Updated ${Formatters.dateTime(at)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (vm.isLoading)
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          TextButton.icon(
            onPressed: vm.load,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Refresh'),
          ),
      ],
    );
  }
}

/// A load failure with a way to try again.
class AdminErrorState extends StatelessWidget {
  const AdminErrorState({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => AppEmptyState(
    message: message,
    icon: Icons.cloud_off_outlined,
    action: onRetry == null
        ? null
        : OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
  );
}

/// Grey placeholder blocks shown while a page or tab loads for the first
/// time.
class AdminTabSkeleton extends StatelessWidget {
  const AdminTabSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    Widget block(double height) => Container(
      height: height,
      decoration: const BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: AppRadii.lgAll,
      ),
    );
    return ListView(
      padding: pagePadding(context).copyWith(top: AppSpacing.xl + 28),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        AdminStatGrid(tiles: [for (var i = 0; i < 4; i++) block(112)]),
        const SizedBox(height: AppSpacing.lg),
        block(220),
        const SizedBox(height: AppSpacing.lg),
        block(180),
      ],
    );
  }
}

/// Stat tiles in 4, 2 or 1 columns depending on the width.
class AdminStatGrid extends StatelessWidget {
  const AdminStatGrid({super.key, required this.tiles});
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= 480
            ? 2
            : 1;
        const gap = AppSpacing.md;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final t in tiles) SizedBox(width: width, child: t)],
        );
      },
    );
  }
}

/// Main column and side column on wide screens; stacked on narrow ones.
class AdminTwoColumn extends StatelessWidget {
  const AdminTwoColumn({super.key, required this.main, required this.side});

  final List<Widget> main;
  final List<Widget> side;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= AppSpacing.wideBreakpoint;
    List<Widget> spaced(List<Widget> items) => [
      for (final (i, w) in items.indexed) ...[
        if (i > 0) const SizedBox(height: AppSpacing.lg),
        w,
      ],
    ];
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: spaced([...main, ...side]),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: spaced(main),
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: spaced(side),
          ),
        ),
      ],
    );
  }
}

/// One row of a breakdown: a label, its value and a bar sized against the
/// largest row.
class AdminBreakdownItem {
  const AdminBreakdownItem(
    this.label,
    this.value, {
    this.display,
    this.color,
    this.onTap,
  });

  final String label;
  final double value;

  /// Shown instead of the raw value, e.g. a peso amount.
  final String? display;
  final Color? color;
  final VoidCallback? onTap;
}

/// Labelled horizontal bars, used for "by status" and "by role" breakdowns.
class AdminBreakdownBars extends StatelessWidget {
  const AdminBreakdownBars({
    super.key,
    required this.items,
    this.emptyMessage = 'Nothing to show yet.',
  });

  final List<AdminBreakdownItem> items;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Text(emptyMessage, style: textTheme.bodyMedium),
      );
    }
    final max = items.fold<double>(0, (m, i) => i.value > m ? i.value : m);
    return Column(
      children: [
        for (final item in items)
          InkWell(
            onTap: item.onTap,
            borderRadius: AppRadii.smAll,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(item.label, style: textTheme.bodyMedium),
                      ),
                      Text(
                        item.display ?? _count(item.value),
                        style: textTheme.titleSmall?.merge(
                          AppTextStyles.numeric,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  ClipRRect(
                    borderRadius: AppRadii.pillAll,
                    child: LinearProgressIndicator(
                      value: max <= 0 ? 0 : item.value / max,
                      minHeight: 6,
                      backgroundColor: AppColors.surfaceMuted,
                      valueColor: AlwaysStoppedAnimation(
                        item.color ?? AppColors.brandGold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  static String _count(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}

/// A compact list row: leading icon, title, subtitle and a trailing figure
/// or chip. Used by every tab's "needs attention" and top-N lists.
class AdminListRow extends StatelessWidget {
  const AdminListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: icon == null
          ? null
          : Icon(icon, color: iconColor ?? AppColors.textSecondary),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing:
          trailing ?? (onTap == null ? null : const Icon(Icons.chevron_right)),
    );
  }
}

/// Rows separated by dividers, or a single "all clear" line when empty.
class AdminRowList extends StatelessWidget {
  const AdminRowList({
    super.key,
    required this.rows,
    required this.emptyTitle,
    this.emptySubtitle,
  });

  final List<Widget> rows;
  final String emptyTitle;
  final String? emptySubtitle;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return ListTile(
        leading: const Icon(
          Icons.check_circle_outline,
          color: AppColors.success,
        ),
        title: Text(emptyTitle),
        subtitle: emptySubtitle == null ? null : Text(emptySubtitle!),
      );
    }
    return Column(
      children: [
        for (final (i, r) in rows.indexed) ...[
          if (i > 0) const Divider(height: 1),
          r,
        ],
      ],
    );
  }
}

/// A right-aligned numeric label for list rows.
class AdminFigureText extends StatelessWidget {
  const AdminFigureText(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(
      context,
    ).textTheme.titleSmall?.merge(AppTextStyles.numeric).copyWith(color: color),
  );
}

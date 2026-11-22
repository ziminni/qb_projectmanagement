import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_radii.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/todo.dart';
import '../../data/models/variation_order.dart';
import '../../data/services/progress_calculator.dart';

/// Gantt chart: categories as parent rows spanning their earliest to-do start
/// to latest to-do end, filled to their % complete; to-dos as child rows.
/// All figures come from [ProjectProgress].
class AppGanttChart extends StatefulWidget {
  const AppGanttChart({
    super.key,
    required this.progress,
    required this.projectStart,
    required this.projectEnd,
    this.variationOrders = const [],
    this.today,
  });

  final ProjectProgress progress;
  final DateTime projectStart;
  final DateTime projectEnd;
  final List<VariationOrder> variationOrders;
  final DateTime? today;

  @override
  State<AppGanttChart> createState() => _AppGanttChartState();
}

class _AppGanttChartState extends State<AppGanttChart> {
  /// Zoom levels: pixels per day.
  static const _zoomLevels = {'Weeks': 14.0, 'Months': 6.0, 'Quarters': 3.0};

  double _dayWidth = 6.0;
  static const _rowHeight = 36.0;
  static const _headerHeight = 32.0;

  late DateTime _rangeStart;
  late DateTime _rangeEnd;
  late final DateTime _today;
  late final ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    _computeRange();
    _today = _day(widget.today ?? DateTime.now());
    _scroll = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToToday());
  }

  @override
  void didUpdateWidget(covariant AppGanttChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectStart != widget.projectStart ||
        oldWidget.projectEnd != widget.projectEnd ||
        oldWidget.progress != widget.progress ||
        oldWidget.variationOrders != widget.variationOrders) {
      _computeRange();
    }
  }

  (DateTime, DateTime) _voSpan(VariationOrder vo) {
    if (vo.workStartDate != null && vo.workEndDate != null) {
      final s = _day(vo.workStartDate!);
      final e = _day(vo.workEndDate!);
      return e.isBefore(s) ? (s, s) : (s, e);
    }
    if (vo.workStartDate != null) {
      final s = _day(vo.workStartDate!);
      final days = vo.daysImpact.abs() > 0 ? vo.daysImpact.abs() - 1 : 0;
      return (s, s.add(Duration(days: days)));
    }
    if (vo.workEndDate != null) {
      final e = _day(vo.workEndDate!);
      final days = vo.daysImpact.abs() > 0 ? vo.daysImpact.abs() - 1 : 0;
      return (e.subtract(Duration(days: days)), e);
    }
    // Legacy VO without explicit task dates: anchor near project end.
    final end = _day(widget.projectEnd);
    final span = vo.daysImpact.abs() > 0 ? vo.daysImpact.abs() - 1 : 0;
    return (end.subtract(Duration(days: span)), end);
  }

  void _computeRange() {
    var start = _day(widget.projectStart);
    var end = _day(widget.projectEnd);
    for (final c in widget.progress.categories) {
      if (c.startDate case final s? when s.isBefore(start)) start = s;
      if (c.endDate case final e? when e.isAfter(end)) end = e;
    }
    for (final vo in widget.variationOrders) {
      final (s, e) = _voSpan(vo);
      if (s.isBefore(start)) start = s;
      if (e.isAfter(end)) end = e;
    }
    _rangeStart = DateTime(start.year, start.month, 1);
    _rangeEnd = DateTime(end.year, end.month + 1, 0);
  }

  /// Scrolls so today sits about two-thirds across, keeping recent and
  /// finished work in view.
  void _jumpToToday() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final target = _x(_today) - position.viewportDimension * 0.66;
    _scroll.jumpTo(target.clamp(0, position.maxScrollExtent));
  }

  void _setZoom(double dayWidth) {
    setState(() => _dayWidth = dayWidth);
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToToday());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  double _x(DateTime date) =>
      _day(date).difference(_rangeStart).inDays * _dayWidth;

  double _w(DateTime start, DateTime end) =>
      (_day(end).difference(_day(start)).inDays + 1) * _dayWidth;

  @override
  Widget build(BuildContext context) {
    final categories = widget.progress.categories;
    final vos = widget.variationOrders;
    if (categories.isEmpty && vos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Center(
          child: Text(
            'Add categories and to-dos to see the Gantt chart.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }

    final narrow = MediaQuery.sizeOf(context).width < 600;
    final labelWidth = narrow ? 140.0 : 240.0;
    final timelineWidth = _x(_rangeEnd) + _dayWidth;

    final labels = <Widget>[];
    final bars = <Widget>[];
    for (final c in categories) {
      labels.add(_categoryLabel(context, c));
      bars.add(_categoryBar(c));
      for (final t in c.todos) {
        labels.add(_todoLabel(context, t));
        bars.add(_todoBar(t));
      }
    }
    if (vos.isNotEmpty) {
      labels.add(_voGroupLabel(context, vos));
      bars.add(_voGroupBar(vos));
      for (final vo in vos) {
        labels.add(_voLabel(context, vo));
        bars.add(_voBar(vo));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<double>(
              showSelectedIcon: false,
              segments: [
                for (final e in _zoomLevels.entries)
                  ButtonSegment(value: e.value, label: Text(e.key)),
              ],
              selected: {_dayWidth},
              onSelectionChanged: (s) => _setZoom(s.first),
            ),
            TextButton.icon(
              onPressed: _jumpToToday,
              icon: const Icon(Icons.today, size: 18),
              label: const Text('Jump to today'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _legend(context),
        const SizedBox(height: AppSpacing.md),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: labelWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      height: _headerHeight,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                      ),
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Item of work',
                              style: Theme.of(context).textTheme.labelSmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            'Weight',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    ...labels,
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: Scrollbar(
                  controller: _scroll,
                  child: SingleChildScrollView(
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: timelineWidth,
                      child: Stack(
                        children: [
                          ..._monthLines(),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _monthHeader(context),
                              const Divider(height: 1),
                              ...bars,
                            ],
                          ),
                          if (!_today.isBefore(_rangeStart) &&
                              !_today.isAfter(_rangeEnd))
                            Positioned(
                              left: _x(_today) + _dayWidth / 2 - 1,
                              top: 0,
                              bottom: 0,
                              child: Container(
                                width: 2,
                                color: AppColors.plannedMarker,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<DateTime> get _monthStarts {
    final result = <DateTime>[];
    var m = _rangeStart;
    while (!m.isAfter(_rangeEnd)) {
      result.add(m);
      m = DateTime(m.year, m.month + 1, 1);
    }
    return result;
  }

  List<Widget> _monthLines() => [
    for (final m in _monthStarts)
      Positioned(
        left: _x(m),
        top: 0,
        bottom: 0,
        child: Container(width: 1, color: AppColors.border),
      ),
  ];

  Widget _monthHeader(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;
    final format = DateFormat('MMM yyyy');
    return SizedBox(
      height: _headerHeight,
      child: Stack(
        children: [
          for (final m in _monthStarts)
            Positioned(
              left: _x(m) + AppSpacing.sm,
              top: 0,
              bottom: 0,
              child: Center(child: Text(format.format(m), style: style)),
            ),
        ],
      ),
    );
  }

  Widget _categoryLabel(BuildContext context, CategoryProgress c) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      height: _rowHeight,
      color: AppColors.surfaceMuted,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Expanded(
            child: Text(
              c.category.name,
              style: textTheme.titleSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Tooltip(
            message:
                'Percent weight: ${Formatters.percent(c.weight)} · '
                '${Formatters.percent(c.progress)} complete',
            child: Text(
              Formatters.percent(c.weight),
              style: textTheme.labelMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _todoLabel(BuildContext context, Todo t) => Container(
    height: _rowHeight,
    padding: const EdgeInsets.only(left: AppSpacing.xl, right: AppSpacing.sm),
    alignment: Alignment.centerLeft,
    child: Text(
      t.title,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: AppColors.textPrimary),
      overflow: TextOverflow.ellipsis,
    ),
  );

  Widget _categoryBar(CategoryProgress c) {
    final start = c.startDate;
    final end = c.endDate;
    return Container(
      height: _rowHeight,
      color: AppColors.surfaceMuted.withValues(alpha: 0.6),
      child: start == null || end == null
          ? null
          : Stack(
              children: [
                Positioned(
                  left: _x(start),
                  top: 10,
                  width: _w(start, end),
                  height: 16,
                  child: Tooltip(
                    message:
                        '${c.category.name}: ${Formatters.percent(c.progress)} complete '
                        '(${Formatters.percent(c.weight)} weight)\n'
                        '${Formatters.dateRange(start, end)}',
                    child: ClipRRect(
                      borderRadius: AppRadii.smAll,
                      child: Stack(
                        children: [
                          Container(color: AppColors.primaryContainer),
                          FractionallySizedBox(
                            widthFactor: c.progress,
                            child: Container(color: AppColors.primary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _todoBar(Todo t) {
    final (fill, border) = t.isVerified
        ? (AppColors.success, AppColors.success)
        : t.isDone
        ? (AppColors.progressPending, AppColors.info)
        : (AppColors.surface, AppColors.textDisabled);
    final status = t.isVerified
        ? 'Verified'
        : t.isDone
        ? 'Awaiting verification'
        : 'Not done';
    return SizedBox(
      height: _rowHeight,
      child: Stack(
        children: [
          Positioned(
            left: _x(t.startDate),
            top: 12,
            width: _w(t.startDate, t.endDate),
            height: 12,
            child: Tooltip(
              message:
                  '${t.title} · $status\n'
                  '${Formatters.dateRange(t.startDate, t.endDate)}',
              child: Container(
                decoration: BoxDecoration(
                  color: fill,
                  border: Border.all(color: border),
                  borderRadius: AppRadii.smAll,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  (Color, Color) _voColors(VariationOrderType type) => switch (type) {
    VariationOrderType.additive => (
      const Color(0xFFD1FAE5),
      const Color(0xFF059669),
    ),
    VariationOrderType.change => (
      const Color(0xFFE0E7FF),
      const Color(0xFF4F46E5),
    ),
    VariationOrderType.deductive => (
      const Color(0xFFFEE2E2),
      const Color(0xFFDC2626),
    ),
  };

  Widget _voGroupLabel(BuildContext context, List<VariationOrder> vos) {
    final textTheme = Theme.of(context).textTheme;
    final totalDays = vos.fold<int>(0, (s, v) => s + v.daysImpact);
    final daysText = totalDays > 0
        ? '+${totalDays}d'
        : totalDays < 0
        ? '${totalDays}d'
        : '0d';
    return Container(
      height: _rowHeight,
      color: AppColors.primaryContainer.withValues(alpha: 0.45),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Variation orders',
              style: textTheme.titleSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            daysText,
            style: textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _voGroupBar(List<VariationOrder> vos) {
    DateTime? start;
    DateTime? end;
    for (final vo in vos) {
      final (s, e) = _voSpan(vo);
      if (start == null || s.isBefore(start)) start = s;
      if (end == null || e.isAfter(end)) end = e;
    }
    return Container(
      height: _rowHeight,
      color: AppColors.primaryContainer.withValues(alpha: 0.25),
      child: start == null || end == null
          ? null
          : Stack(
              children: [
                Positioned(
                  left: _x(start),
                  top: 10,
                  width: _w(start, end),
                  height: 16,
                  child: Tooltip(
                    message:
                        'Variation orders (${vos.length})\n'
                        '${Formatters.dateRange(start, end)}',
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.brandGold.withValues(alpha: 0.85),
                        borderRadius: AppRadii.smAll,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _voLabel(BuildContext context, VariationOrder vo) {
    final (_, accent) = _voColors(vo.type);
    final sign = vo.daysImpact > 0
        ? '+${vo.daysImpact}d'
        : vo.daysImpact < 0
        ? '${vo.daysImpact}d'
        : '0d';
    return Container(
      height: _rowHeight,
      padding: const EdgeInsets.only(left: AppSpacing.xl, right: AppSpacing.sm),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(right: AppSpacing.xs),
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          Expanded(
            child: Tooltip(
              message: '${vo.voNo} · ${vo.type.label}\n${vo.description}',
              child: Text(
                '${vo.voNo}: ${vo.description}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.textPrimary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            sign,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _voBar(VariationOrder vo) {
    final (start, end) = _voSpan(vo);
    final (fill, border) = _voColors(vo.type);
    final sign = vo.daysImpact > 0
        ? '+${vo.daysImpact} days'
        : vo.daysImpact < 0
        ? '${vo.daysImpact} days'
        : '0 days';
    return SizedBox(
      height: _rowHeight,
      child: Stack(
        children: [
          Positioned(
            left: _x(start),
            top: 11,
            width: _w(start, end),
            height: 14,
            child: Tooltip(
              message:
                  '${vo.voNo} · ${vo.type.label} ($sign)\n'
                  '${vo.description}\n'
                  '${Formatters.dateRange(start, end)}',
              child: Container(
                decoration: BoxDecoration(
                  color: fill,
                  border: Border.all(color: border, width: 1.5),
                  borderRadius: AppRadii.smAll,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legend(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    Widget swatch(Color fill, Color border, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 10,
          decoration: BoxDecoration(
            color: fill,
            border: Border.all(color: border),
            borderRadius: AppRadii.smAll,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(label, style: style),
      ],
    );
    return Wrap(
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.sm,
      children: [
        swatch(AppColors.primary, AppColors.primary, 'Category % complete'),
        swatch(AppColors.success, AppColors.success, 'Verified'),
        swatch(
          AppColors.progressPending,
          AppColors.info,
          'Awaiting verification',
        ),
        swatch(AppColors.surface, AppColors.textDisabled, 'Not done'),
        swatch(AppColors.plannedMarker, AppColors.plannedMarker, 'Today'),
        if (widget.variationOrders.isNotEmpty) ...[
          swatch(
            const Color(0xFFD1FAE5),
            const Color(0xFF059669),
            'VO · Added work',
          ),
          swatch(
            const Color(0xFFE0E7FF),
            const Color(0xFF4F46E5),
            'VO · Design change',
          ),
          swatch(
            const Color(0xFFFEE2E2),
            const Color(0xFFDC2626),
            'VO · Removed work',
          ),
        ],
      ],
    );
  }
}

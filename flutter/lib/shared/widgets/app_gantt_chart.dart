import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_radii.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/todo.dart';
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
    this.today,
  });

  final ProjectProgress progress;
  final DateTime projectStart;
  final DateTime projectEnd;
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

  late final DateTime _rangeStart;
  late final DateTime _rangeEnd;
  late final DateTime _today;
  late final ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    var start = _day(widget.projectStart);
    var end = _day(widget.projectEnd);
    for (final c in widget.progress.categories) {
      if (c.startDate case final s? when s.isBefore(start)) start = s;
      if (c.endDate case final e? when e.isAfter(end)) end = e;
    }
    _rangeStart = DateTime(start.year, start.month, 1);
    _rangeEnd = DateTime(end.year, end.month + 1, 0);
    _today = _day(widget.today ?? DateTime.now());
    _scroll = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToToday());
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
    if (categories.isEmpty) {
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
                    const SizedBox(height: _headerHeight),
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
          Text(Formatters.percent(c.progress), style: textTheme.labelMedium),
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
                        '${c.category.name}: ${Formatters.percent(c.progress)}\n'
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
      ],
    );
  }
}

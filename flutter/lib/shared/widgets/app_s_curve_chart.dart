import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../data/services/progress_calculator.dart';

/// Planned vs. actual cumulative progress. Points come from
/// `computeSCurve`, so the curve agrees with the progress bar.
class AppSCurveChart extends StatelessWidget {
  const AppSCurveChart({super.key, required this.points, this.height = 220});

  final List<SCurvePoint> points;
  final double height;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    if (points.length < 2) {
      return SizedBox(
        height: 80,
        child: Center(
          child: Text(
            'Not enough schedule data yet.',
            style: textTheme.bodySmall,
          ),
        ),
      );
    }
    final latest = points.lastWhere(
      (p) => p.actual != null,
      orElse: () => points.first,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label:
              'S-curve. Planned ${(latest.planned * 100).round()}%, actual '
              '${((latest.actual ?? 0) * 100).round()}% as of the latest point.',
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: CustomPaint(
              painter: _SCurvePainter(
                points: points,
                labelStyle: textTheme.labelSmall!,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.lg,
          children: [
            _legend(context, AppColors.plannedMarker, 'Planned'),
            _legend(context, AppColors.primary, 'Actual (verified)'),
          ],
        ),
      ],
    );
  }

  Widget _legend(BuildContext context, Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 16, height: 3, color: color),
      const SizedBox(width: AppSpacing.xs),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _SCurvePainter extends CustomPainter {
  _SCurvePainter({required this.points, required this.labelStyle});

  final List<SCurvePoint> points;
  final TextStyle labelStyle;

  static const _left = 36.0;
  static const _bottom = 22.0;
  static const _top = 6.0;
  static const _right = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    final chart = Rect.fromLTRB(
      _left,
      _top,
      size.width - _right,
      size.height - _bottom,
    );
    final first = points.first.date;
    final spanDays = points.last.date.difference(first).inDays.clamp(1, 100000);

    double x(DateTime d) =>
        chart.left + chart.width * d.difference(first).inDays / spanDays;
    double y(double v) => chart.bottom - chart.height * v;

    final grid = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    for (final v in [0.0, 0.25, 0.5, 0.75, 1.0]) {
      canvas.drawLine(
        Offset(chart.left, y(v)),
        Offset(chart.right, y(v)),
        grid,
      );
      _text(canvas, '${(v * 100).round()}%', Offset(0, y(v) - 7));
    }

    final months = DateFormat('MMM');
    var m = DateTime(first.year, first.month + 1, 1);
    while (!m.isAfter(points.last.date)) {
      _text(canvas, months.format(m), Offset(x(m) - 10, chart.bottom + 6));
      m = DateTime(m.year, m.month + 1, 1);
    }

    _line(canvas, [
      for (final p in points) Offset(x(p.date), y(p.planned)),
    ], AppColors.plannedMarker);
    _line(canvas, [
      for (final p in points)
        if (p.actual != null) Offset(x(p.date), y(p.actual!)),
    ], AppColors.primary);
  }

  void _line(Canvas canvas, List<Offset> offsets, Color color) {
    if (offsets.length < 2) return;
    final path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    for (final o in offsets.skip(1)) {
      path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _text(Canvas canvas, String text, Offset at) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_SCurvePainter old) => old.points != points;
}

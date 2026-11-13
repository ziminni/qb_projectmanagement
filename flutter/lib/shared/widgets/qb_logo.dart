import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_fonts.dart';

/// The Queen Builders "QB" logo, with the company wordmark beside it when
/// [showName] is set. The mark itself is black, so on dark backgrounds
/// ([onDark]) it sits on a white tile to stay legible.
class QbLogo extends StatelessWidget {
  const QbLogo({
    super.key,
    this.size = 40,
    this.showName = true,
    this.onDark = false,
    this.tagline = 'Construction PMS',
  });

  static const asset = 'assets/images/qb_logo.png';

  final double size;
  final bool showName;
  final bool onDark;

  /// Small line under the name; null hides it.
  final String? tagline;

  @override
  Widget build(BuildContext context) {
    Widget mark = Image.asset(
      asset,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      semanticLabel: 'Queen Builders logo',
    );
    if (onDark) {
      mark = Container(
        padding: EdgeInsets.all(size * 0.14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(size * 0.22),
        ),
        child: Image.asset(
          asset,
          height: size * 0.72,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          semanticLabel: 'Queen Builders logo',
        ),
      );
    }
    if (!showName) return mark;
    final name = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'QUEEN BUILDERS',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: AppFonts.display,
            fontSize: size * 0.4,
            height: 1.1,
            fontWeight: FontWeight.w700,
            letterSpacing: size * 0.02,
            color: onDark ? Colors.white : AppColors.brandBlack,
          ),
        ),
        if (tagline != null)
          Text(
            tagline!.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppFonts.body,
              fontSize: size * 0.24,
              height: 1.3,
              fontWeight: FontWeight.w600,
              letterSpacing: size * 0.04,
              color: onDark
                  ? AppColors.brandGoldLight
                  : AppColors.brandGoldText,
            ),
          ),
      ],
    );
    // In a bounded space (the sidebar) the name shrinks with an ellipsis;
    // unbounded (inside a FittedBox) it takes its natural width.
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          mark,
          SizedBox(width: size * 0.28),
          if (constraints.hasBoundedWidth) Flexible(child: name) else name,
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

/// The BuildPro logo: a gradient tile with a hard-hat glyph, and the
/// wordmark beside it when [showName] is set.
class AppBrandMark extends StatelessWidget {
  const AppBrandMark({
    super.key,
    this.size = 36,
    this.showName = true,
    this.onDark = false,
  });

  final double size;
  final bool showName;

  /// Light wordmark for dark backgrounds.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final tile = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x553B6CFF),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Icon(
        Icons.construction_rounded,
        color: Colors.white,
        size: size * 0.6,
      ),
    );
    if (!showName) return tile;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        tile,
        SizedBox(width: size * 0.33),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Build'),
              TextSpan(
                text: 'Pro',
                style: TextStyle(
                  color: onDark ? AppColors.brandGoldLight : AppColors.primary,
                ),
              ),
            ],
          ),
          style: TextStyle(
            fontSize: size * 0.56,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: onDark ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

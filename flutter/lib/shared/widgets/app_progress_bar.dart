import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_radii.dart';

/// Horizontal progress bar with an optional planned-progress marker. Values
/// are 0–1 and should come from `computeProjectProgress`.
class AppProgressBar extends StatelessWidget {
  const AppProgressBar({
    super.key,
    required this.value,
    this.planned,
    this.height = 10,
    this.color = AppColors.progressFill,
    this.semanticsLabel,
  });

  final double value;
  final double? planned;
  final double height;
  final Color color;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(0.0, 1.0);
    return Semantics(
      label: semanticsLabel,
      value: '${(clamped * 100).round()}%',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return SizedBox(
            height: height + (planned != null ? 6 : 0),
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: height,
                  decoration: const BoxDecoration(
                    color: AppColors.progressTrack,
                    borderRadius: AppRadii.pillAll,
                  ),
                ),
                Container(
                  height: height,
                  width: width * clamped,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: AppRadii.pillAll,
                  ),
                ),
                if (planned != null)
                  Positioned(
                    left: (width * planned!.clamp(0.0, 1.0) - 1.5).clamp(
                      0.0,
                      width - 3,
                    ),
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 3,
                      decoration: const BoxDecoration(
                        color: AppColors.plannedMarker,
                        borderRadius: AppRadii.pillAll,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

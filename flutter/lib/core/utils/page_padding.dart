import 'package:flutter/widgets.dart';

import '../constants/app_spacing.dart';

/// List padding that centres content at [AppSpacing.maxContentWidth] on wide
/// screens and keeps a 16px gutter on phones.
EdgeInsets pagePadding(BuildContext context, {double bottom = AppSpacing.xxl}) {
  final width = MediaQuery.sizeOf(context).width;
  final side = width > AppSpacing.maxContentWidth + 2 * AppSpacing.xl
      ? (width - AppSpacing.maxContentWidth) / 2
      : AppSpacing.lg;
  return EdgeInsets.fromLTRB(side, AppSpacing.lg, side, bottom);
}

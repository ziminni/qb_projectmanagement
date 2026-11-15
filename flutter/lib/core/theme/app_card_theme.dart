import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_radii.dart';

abstract final class AppCardTheme {
  static const light = CardThemeData(
    color: AppColors.cardBackground,
    surfaceTintColor: Colors.transparent,
    shadowColor: Color(0x2A050505),
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: AppRadii.lgAll,
      side: BorderSide(color: AppColors.border),
    ),
  );
}

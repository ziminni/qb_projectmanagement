import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

/// A round avatar with a person's initials on the brand gradient.
class AppAvatar extends StatelessWidget {
  const AppAvatar({super.key, required this.name, this.size = 34});

  final String name;
  final double size;

  static String initialsOf(String name) => name
      .split(' ')
      .where((p) => p.isNotEmpty)
      .take(2)
      .map((p) => p[0].toUpperCase())
      .join();

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      gradient: AppColors.brandGradient,
      shape: BoxShape.circle,
    ),
    child: Text(
      initialsOf(name),
      style: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
        fontSize: size * 0.37,
      ),
    ),
  );
}

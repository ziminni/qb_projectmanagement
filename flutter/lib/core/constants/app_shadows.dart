import 'package:flutter/material.dart';

abstract final class AppShadows {
  static const sm = [
    BoxShadow(color: Color(0x14000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  static const md = [
    BoxShadow(color: Color(0x1A000000), blurRadius: 12, offset: Offset(0, 4)),
  ];
}

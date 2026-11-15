import 'package:flutter/material.dart';

abstract final class AppShadows {
  static const sm = [
    BoxShadow(color: Color(0x0A0F172A), blurRadius: 3, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x080F172A), blurRadius: 2, offset: Offset(0, 1)),
  ];

  static const md = [
    BoxShadow(color: Color(0x140F172A), blurRadius: 16, offset: Offset(0, 6)),
  ];

  static const lg = [
    BoxShadow(color: Color(0x1F0F172A), blurRadius: 32, offset: Offset(0, 12)),
  ];
}

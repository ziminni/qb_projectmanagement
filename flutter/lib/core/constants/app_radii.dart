import 'package:flutter/material.dart';

abstract final class AppRadii {
  static const double sm = 6;
  static const double md = 10;
  static const double lg = 16;
  static const double pill = 999;

  static const smAll = BorderRadius.all(Radius.circular(sm));
  static const mdAll = BorderRadius.all(Radius.circular(md));
  static const lgAll = BorderRadius.all(Radius.circular(lg));
  static const pillAll = BorderRadius.all(Radius.circular(pill));
}

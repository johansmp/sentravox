import 'package:flutter/material.dart';

class SentraVoxTheme {
  static const Color primary = Color(0xFF4A6CF7);
  static const Color danger = Color(0xFFE53935);
  static const Color success = Color(0xFF43A047);

  static ThemeData light = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
    ),
    fontFamily: 'Inter',
  );

  static ThemeData dark = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
    ),
    fontFamily: 'Inter',
  );
}

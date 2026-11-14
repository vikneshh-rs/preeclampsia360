import 'package:flutter/material.dart';

class AppColors {
  static const crimson = Color(0xFFA61932);
  static const crimsonDark = Color(0xFF781326);
  static const rose = Color(0xFFC7354D);
  static const coral = Color(0xFFE56B7B);
  static const blush = Color(0xFFF7DDE1);
  static const paleRose = Color(0xFFFCECEF);
  static const warmWhite = Color(0xFFFFF8F8);
  static const champagne = Color(0xFFE8CBAA);
  static const slate = Color(0xFF263746);
  static const ink = Color(0xFF35151D);
  static const muted = Color(0xFF75666B);
  static const border = Color(0xFFF0E2E5);
  static const success = Color(0xFF287A50);
  static const warning = Color(0xFFC47A16);
  static const critical = Color(0xFFB42318);
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.crimson, brightness: Brightness.light).copyWith(
    primary: AppColors.crimson, secondary: AppColors.rose, surface: Colors.white,
    error: AppColors.critical,
  );
  return ThemeData(
    useMaterial3: true, colorScheme: scheme, scaffoldBackgroundColor: AppColors.warmWhite,
    fontFamily: 'Roboto', visualDensity: VisualDensity.standard,
    appBarTheme: const AppBarTheme(backgroundColor: AppColors.warmWhite, foregroundColor: AppColors.ink, elevation: 0, centerTitle: false),
    cardTheme: CardThemeData(color: Colors.white, elevation: 1.5, shadowColor: AppColors.crimson.withValues(alpha: .07), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: const BorderSide(color: AppColors.border))),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: const Color(0xFFFFFBFB), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: AppColors.crimson, width: 1.5)),
    ),
  );
}

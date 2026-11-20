import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Editorial Healthcare Palette
  static const deepBurgundy = Color(0xFF7F1D3A);
  static const darkWine = Color(0xFF571329);
  static const warmIvory = Color(0xFFFAF9F6);
  static const softBlush = Color(0xFFF8EAED);
  static const champagne = Color(0xFFC6A46A);
  static const slate = Color(0xFF475569);
  static const mutedGrey = Color(0xFF94A3B8);
  static const alertAmber = Color(0xFFD97706);
  static const alertRed = Color(0xFFDC2626);

  // Semantic & Backward-Compatible Aliases
  static const crimson = deepBurgundy;
  static const crimsonDark = darkWine;
  static const rose = Color(0xFF9F1239);
  static const coral = Color(0xFFBE123C);
  static const blush = softBlush;
  static const paleRose = softBlush;
  static const warmWhite = warmIvory;
  static const ink = Color(0xFF1E293B);
  static const muted = slate;
  static const border = Color(0xFFF1E5E8);
  static const success = Color(0xFF15803D);
  static const warning = alertAmber;
  static const critical = alertRed;
}

class AppSpacing {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double xxl = 32.0;
  static const double xxxl = 40.0;
  static const double x4l = 48.0;
}

class AppMotion {
  static const Duration micro = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration modal = Duration(milliseconds: 280);
  static const Duration chart = Duration(milliseconds: 700);
  static const Curve standardCurve = Curves.easeOutCubic;
}

class AppTypography {
  // Editorial Headings (Playfair Display)
  static TextStyle displayLarge({Color color = AppColors.darkWine}) => GoogleFonts.playfairDisplay(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: color,
      );

  static TextStyle displayMedium({Color color = AppColors.darkWine}) => GoogleFonts.playfairDisplay(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: color,
      );

  static TextStyle displaySmall({Color color = AppColors.darkWine}) => GoogleFonts.playfairDisplay(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: color,
      );

  // Modern Interface Elements (Manrope)
  static TextStyle titleLarge({Color color = AppColors.ink}) => GoogleFonts.manrope(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: color,
      );

  static TextStyle titleMedium({Color color = AppColors.ink}) => GoogleFonts.manrope(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: color,
      );

  static TextStyle bodyLarge({Color color = AppColors.ink}) => GoogleFonts.manrope(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.45,
        color: color,
      );

  static TextStyle bodyMedium({Color color = AppColors.slate}) => GoogleFonts.manrope(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: color,
      );

  static TextStyle labelSmall({Color color = AppColors.slate}) => GoogleFonts.manrope(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: color,
      );

  // Tabular Numerals for Clinical Vital Signs
  static TextStyle clinicalNumerals({
    double fontSize = 22,
    FontWeight fontWeight = FontWeight.w700,
    Color color = AppColors.deepBurgundy,
  }) =>
      GoogleFonts.manrope(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}

ThemeData buildAppTheme() {
  final baseScheme = ColorScheme.fromSeed(
    seedColor: AppColors.deepBurgundy,
    brightness: Brightness.light,
  ).copyWith(
    primary: AppColors.deepBurgundy,
    secondary: AppColors.champagne,
    surface: Colors.white,
    error: AppColors.alertRed,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: baseScheme,
    scaffoldBackgroundColor: AppColors.warmIvory,
    visualDensity: VisualDensity.standard,
    textTheme: TextTheme(
      headlineLarge: AppTypography.displayLarge(),
      headlineMedium: AppTypography.displayMedium(),
      headlineSmall: AppTypography.displaySmall(),
      titleLarge: AppTypography.titleLarge(),
      titleMedium: AppTypography.titleMedium(),
      bodyLarge: AppTypography.bodyLarge(),
      bodyMedium: AppTypography.bodyMedium(),
      labelSmall: AppTypography.labelSmall(),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.warmIvory,
      foregroundColor: AppColors.darkWine,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: AppTypography.displaySmall(color: AppColors.darkWine),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.border, width: 1.0),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.deepBurgundy,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.deepBurgundy,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      labelStyle: GoogleFonts.manrope(fontSize: 13, color: AppColors.slate),
      hintStyle: GoogleFonts.manrope(fontSize: 13, color: AppColors.mutedGrey),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border, width: 1.0),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border, width: 1.0),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.deepBurgundy, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.alertRed, width: 1.2),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: AppColors.softBlush,
      elevation: 2,
      height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return GoogleFonts.manrope(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.deepBurgundy,
          );
        }
        return GoogleFonts.manrope(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.slate,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: AppColors.deepBurgundy);
        }
        return const IconThemeData(color: AppColors.slate);
      }),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
  );
}

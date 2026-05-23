import 'package:flutter/material.dart';
import 'package:calcwise_core/calcwise_core.dart';

class AppTheme {
  AppTheme._();

  // ── Core palette — deep navy (UK brand, matches MortgageUK) ───────────────
  static const Color primary = Color(0xFF003087);
  static const Color primaryDark = Color(0xFF002070);
  static const Color primaryLight = Color(0xFF1A4FAF);

  static const Color accent = Color(0xFFC8102E); // Union Jack red
  static const Color secondary = accent;

  // ── Semantic ───────────────────────────────────────────────────────────────
  static const Color accentGood = Color(0xFF34D399);
  static const Color errorRed = Color(0xFFF87171);
  static const Color warningOrange = Color(0xFFFB923C);
  static const Color successGreen = Color(0xFF34D399);
  static const Color success = successGreen;
  static const Color warning = warningOrange;

  // ── Gradients ─────────────────────────────────────────────────────────────
  static const LinearGradient ctaGradient = LinearGradient(
    colors: [Color(0xFF003087), Color(0xFF002070)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient heroGradient = LinearGradient(
    colors: [Color(0xFF002070), Color(0xFF001558)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── ThemeData ─────────────────────────────────────────────────────────────
  static ThemeData get theme => CalcwiseThemeFactory.buildLight(
        primary: primary,
        accent: accent,
        primaryDeep: primaryDark,
      );

  static ThemeData get dark => CalcwiseThemeFactory.buildDark(
        primary: primary,
        accent: accent,
        primaryDeep: primaryDark,
        secondaryDeep: const Color(0xFF001558),
      );
}

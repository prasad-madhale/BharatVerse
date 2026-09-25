import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Mirrors the BharatVerse Design System's tokens/typography.css -- an
/// editorial serif/sans pairing. Newsreader (serif) for headlines and
/// long-form reading; Work Sans (sans) for UI chrome.
///
/// These styles carry no color -- color is theme-dependent (see
/// [AppColorTokens] via `context.colors`), so callers apply it explicitly,
/// e.g. `AppTypography.headline.copyWith(color: context.colors.textPrimary)`.
abstract class AppTypography {
  static TextStyle get display1 => GoogleFonts.newsreader(
        fontSize: 40,
        height: 1.15,
        fontWeight: FontWeight.w700,
        letterSpacing: 40 * 0.03,
      );

  static TextStyle get display2 => GoogleFonts.newsreader(
        fontSize: 28,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: 28 * 0.03,
      );

  static TextStyle get headline => GoogleFonts.newsreader(
        fontSize: 22,
        height: 1.3,
        fontWeight: FontWeight.w700,
        letterSpacing: 22 * 0.02,
      );

  static TextStyle get bodyLg => GoogleFonts.newsreader(
        fontSize: 18,
        height: 1.65,
        fontWeight: FontWeight.w400,
      );

  // ---- UI (sans) ----
  static TextStyle get body => GoogleFonts.workSans(
        fontSize: 16,
        height: 1.55,
        fontWeight: FontWeight.w400,
      );

  static TextStyle get ui => GoogleFonts.workSans(
        fontSize: 15,
        height: 1.4,
        fontWeight: FontWeight.w400,
      );

  static TextStyle get label => GoogleFonts.workSans(
        fontSize: 13,
        height: 1.3,
        fontWeight: FontWeight.w700,
        letterSpacing: 13 * 0.06,
      );

  static TextStyle get caption => GoogleFonts.workSans(
        fontSize: 12,
        height: 1.45,
        fontWeight: FontWeight.w400,
      );
}

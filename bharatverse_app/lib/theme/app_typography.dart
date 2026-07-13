import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Mirrors the BharatVerse Design System's tokens/typography.css -- an
/// editorial serif/sans pairing. Newsreader (serif) for headlines and
/// long-form reading; Work Sans (sans) for UI chrome. Display/headline
/// styles are uppercase + letter-spaced for a broadsheet feel (apply
/// `.toUpperCase()` to the text, not baked into the TextStyle).
abstract class AppTypography {
  // ---- Display / editorial (serif, pair with uppercase text) ----
  static TextStyle get display1 => GoogleFonts.newsreader(
        fontSize: 40,
        height: 1.15,
        fontWeight: FontWeight.w700,
        letterSpacing: 40 * 0.03,
        color: AppColors.textPrimary,
      );

  static TextStyle get display2 => GoogleFonts.newsreader(
        fontSize: 28,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: 28 * 0.03,
        color: AppColors.textPrimary,
      );

  static TextStyle get headline => GoogleFonts.newsreader(
        fontSize: 22,
        height: 1.3,
        fontWeight: FontWeight.w700,
        letterSpacing: 22 * 0.02,
        color: AppColors.textPrimary,
      );

  static TextStyle get bodyLg => GoogleFonts.newsreader(
        fontSize: 18,
        height: 1.65,
        fontWeight: FontWeight.w400,
        color: AppColors.textBody,
      );

  // ---- UI (sans) ----
  static TextStyle get body => GoogleFonts.workSans(
        fontSize: 16,
        height: 1.55,
        fontWeight: FontWeight.w400,
        color: AppColors.textBody,
      );

  static TextStyle get ui => GoogleFonts.workSans(
        fontSize: 15,
        height: 1.4,
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimary,
      );

  static TextStyle get label => GoogleFonts.workSans(
        fontSize: 13,
        height: 1.3,
        fontWeight: FontWeight.w700,
        letterSpacing: 13 * 0.06,
        color: AppColors.textSecondary,
      );

  static TextStyle get caption => GoogleFonts.workSans(
        fontSize: 12,
        height: 1.45,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
      );
}

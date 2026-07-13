import 'package:flutter/material.dart';

/// Mirrors the BharatVerse Design System's tokens/colors.css -- keep values
/// in sync with that file (claude.ai/design project 1d724d26-356e-4774-8711-3d34c0e1124a).
abstract class AppColors {
  // Ink (text) -- warm near-black, never pure black.
  static const ink950 = Color(0xFF17140F);
  static const ink800 = Color(0xFF332C22);
  static const ink500 = Color(0xFF6B6152);
  static const ink300 = Color(0xFFA69C8C);
  static const ink200 = Color(0xFFCDC4B3);

  // Paper (surfaces) -- parchment, not stark white.
  static const paper0 = Color(0xFFFBF7EF);
  static const paper50 = Color(0xFFFFFDF8);
  static const paper100 = Color(0xFFEFE8D8);
  static const paper200 = Color(0xFFE3D9C4);

  // Saffron -- PRIMARY brand accent (CTAs, tabs, kickers, likes).
  static const saffron700 = Color(0xFFA55428);
  static const saffron600 = Color(0xFFC1652F);
  static const saffron500 = Color(0xFFD8783D);
  static const saffron100 = Color(0xFFF7E7D9);

  // India Green -- secondary accent (links, focus, supporting tags).
  static const green700 = Color(0xFF0D6B07);
  static const green600 = Color(0xFF138808);
  static const green500 = Color(0xFF1A9E10);
  static const green100 = Color(0xFFE0F0DC);

  // Semantic.
  static const colorSuccess = Color(0xFF3F7D58);
  static const colorError = Color(0xFFB23A3A);
  static const colorErrorBg = Color(0xFFF6E6E1);

  // Semantic aliases -- use these in widgets, not the raw scale above.
  static const textPrimary = ink950;
  static const textBody = ink800;
  static const textSecondary = ink500;
  static const textPlaceholder = ink300;
  static const textOnAccent = paper50;
  static const textLink = green600;

  static const surfacePage = paper0;
  static const surfaceCard = paper50;
  static const surfaceSunken = paper100;
  static const borderHairline = paper100;
  static const borderStrong = paper200;

  static const accentPrimary = saffron600;
  static const accentPrimaryHover = saffron700;
  static const accentPrimaryTint = saffron100;

  static const accentSecondary = green600;
  static const accentSecondaryHover = green700;
  static const accentSecondaryTint = green100;

  static const likeActive = saffron600;
}

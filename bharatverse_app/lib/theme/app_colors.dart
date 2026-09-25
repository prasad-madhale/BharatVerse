import 'package:flutter/material.dart';

/// Design tokens as a [ThemeExtension], so every color resolves per-theme
/// (Light vs. the "Night Edition" Dark) instead of being a fixed constant.
/// Read via `context.colors` (below) rather than `Theme.of(context).extension`
/// directly. Mirrors the BharatVerse Design System's tokens/colors.css, plus
/// the Milestone 1 redesign's `--bv-*` tokens (glass chrome, CTA, floating
/// shadows) -- see both themes' values in that mockup's own inline
/// `<style data-theme>` blocks (claude.ai/design project
/// 1d724d26-356e-4774-8711-3d34c0e1124a).
@immutable
class AppColorTokens extends ThemeExtension<AppColorTokens> {
  const AppColorTokens({
    required this.ink950,
    required this.ink800,
    required this.ink500,
    required this.ink300,
    required this.ink200,
    required this.paper0,
    required this.paper50,
    required this.paper100,
    required this.paper200,
    required this.saffron700,
    required this.saffron600,
    required this.saffron500,
    required this.saffron100,
    required this.green700,
    required this.green600,
    required this.green500,
    required this.green100,
    required this.colorSuccess,
    required this.colorError,
    required this.colorErrorBg,
    required this.textPrimary,
    required this.textBody,
    required this.textSecondary,
    required this.textPlaceholder,
    required this.textOnAccent,
    required this.textLink,
    required this.surfacePage,
    required this.surfaceCard,
    required this.surfaceSunken,
    required this.borderHairline,
    required this.borderStrong,
    required this.accentPrimary,
    required this.accentPrimaryHover,
    required this.accentPrimaryTint,
    required this.accentSecondary,
    required this.accentSecondaryHover,
    required this.accentSecondaryTint,
    required this.likeActive,
    required this.tint,
    required this.glass,
    required this.glassEdge,
    required this.onScrim,
    required this.cta,
    required this.ctaFg,
    required this.cell,
    required this.grouped,
    required this.sep,
    required this.tabActive,
    required this.appleBg,
    required this.appleFg,
    required this.shadowArt,
    required this.shadowFloat,
    required this.imageFilter,
  });

  // ---- Ink (text) ----
  final Color ink950;
  final Color ink800;
  final Color ink500;
  final Color ink300;
  final Color ink200;

  // ---- Paper (surfaces) ----
  final Color paper0;
  final Color paper50;
  final Color paper100;
  final Color paper200;

  // ---- Saffron -- PRIMARY brand accent ----
  final Color saffron700;
  final Color saffron600;
  final Color saffron500;
  final Color saffron100;

  // ---- India Green -- secondary accent ----
  final Color green700;
  final Color green600;
  final Color green500;
  final Color green100;

  // ---- Semantic ----
  final Color colorSuccess;
  final Color colorError;
  final Color colorErrorBg;

  // ---- Semantic aliases ----
  final Color textPrimary;
  final Color textBody;
  final Color textSecondary;
  final Color textPlaceholder;
  final Color textOnAccent;
  final Color textLink;

  final Color surfacePage;
  final Color surfaceCard;
  final Color surfaceSunken;
  final Color borderHairline;
  final Color borderStrong;

  final Color accentPrimary;
  final Color accentPrimaryHover;
  final Color accentPrimaryTint;

  final Color accentSecondary;
  final Color accentSecondaryHover;
  final Color accentSecondaryTint;

  final Color likeActive;

  /// `--bv-tint` -- the Milestone 1 UI's accent for icons/kickers/active tab
  /// state. Distinct from [accentPrimary] (saffron600): this is saffron700
  /// in both themes.
  final Color tint;

  // ---- Milestone 1 "glass chrome" tokens ----
  final Color glass;
  final Color glassEdge;
  final Color onScrim;
  final Color cta;
  final Color ctaFg;
  final Color cell;
  final Color grouped;
  final Color sep;
  final Color tabActive;
  final Color appleBg;
  final Color appleFg;

  /// `--bv-shadow-art` / `--bv-shadow-float` -- box-shadow is a color-bearing
  /// token (differs between Light and Dark), so it lives here, not in
  /// AppSpacing.
  final List<BoxShadow> shadowArt;
  final List<BoxShadow> shadowFloat;

  /// `--bv-img-filter` -- the warm sepia/saturate/contrast (+ a slight
  /// brightness cut in Dark) applied to every article thumbnail.
  final ColorFilter imageFilter;

  // final, not const: imageFilter's matrix is computed at runtime by
  // _sepiaMatrix (loops/map aren't const-evaluable). Still constructed once.
  static final light = AppColorTokens(
    ink950: Color(0xFF17140F),
    ink800: Color(0xFF332C22),
    ink500: Color(0xFF6B6152),
    ink300: Color(0xFFA69C8C),
    ink200: Color(0xFFCDC4B3),
    paper0: Color(0xFFFBF7EF),
    paper50: Color(0xFFFFFDF8),
    paper100: Color(0xFFEFE8D8),
    paper200: Color(0xFFE3D9C4),
    saffron700: Color(0xFFA55428),
    saffron600: Color(0xFFC1652F),
    saffron500: Color(0xFFD8783D),
    saffron100: Color(0xFFF7E7D9),
    green700: Color(0xFF0D6B07),
    green600: Color(0xFF138808),
    green500: Color(0xFF1A9E10),
    green100: Color(0xFFE0F0DC),
    colorSuccess: Color(0xFF3F7D58),
    colorError: Color(0xFFB23A3A),
    colorErrorBg: Color(0xFFF6E6E1),
    textPrimary: Color(0xFF17140F), // ink950
    textBody: Color(0xFF332C22), // ink800
    textSecondary: Color(0xFF6B6152), // ink500
    textPlaceholder: Color(0xFFA69C8C), // ink300
    textOnAccent: Color(0xFFFFFDF8), // paper50
    textLink: Color(0xFF138808), // green600
    surfacePage: Color(0xFFFBF7EF), // paper0
    surfaceCard: Color(0xFFFFFDF8), // paper50
    surfaceSunken: Color(0xFFEFE8D8), // paper100
    borderHairline: Color(0xFFEFE8D8), // paper100
    borderStrong: Color(0xFFE3D9C4), // paper200
    accentPrimary: Color(0xFFC1652F), // saffron600
    accentPrimaryHover: Color(0xFFA55428), // saffron700
    accentPrimaryTint: Color(0xFFF7E7D9), // saffron100
    accentSecondary: Color(0xFF138808), // green600
    accentSecondaryHover: Color(0xFF0D6B07), // green700
    accentSecondaryTint: Color(0xFFE0F0DC), // green100
    likeActive: Color(0xFFC1652F), // saffron600
    tint: Color(0xFFA55428), // saffron700
    glass: Color.fromRGBO(255, 253, 248, 0.72),
    glassEdge: Color.fromRGBO(23, 20, 15, 0.08),
    onScrim: Color(0xFFFFFDF8),
    cta: Color(0xFFA55428),
    ctaFg: Color(0xFFFFFDF8),
    cell: Color(0xFFFFFDF8),
    grouped: Color(0xFFEFE8D8),
    sep: Color.fromRGBO(23, 20, 15, 0.12),
    tabActive: Color.fromRGBO(23, 20, 15, 0.07),
    appleBg: Colors.black,
    appleFg: Colors.white,
    shadowArt: [
      BoxShadow(
        offset: Offset(0, 8),
        blurRadius: 22,
        color: Color.fromRGBO(23, 20, 15, 0.16),
      ),
    ],
    shadowFloat: [
      BoxShadow(
        offset: Offset(0, 10),
        blurRadius: 30,
        color: Color.fromRGBO(23, 20, 15, 0.18),
      ),
    ],
    imageFilter: ColorFilter.matrix(
        _sepiaMatrix(saturation: 0.85, contrast: 1.05, brightness: 1)),
  );

  static final dark = AppColorTokens(
    ink950: Color(0xFFF3ECDD),
    ink800: Color(0xFFD8CFBC),
    ink500: Color(0xFFA99F8C),
    ink300: Color(0xFF71685A),
    ink200: Color(0xFF3F382E),
    paper0: Color(0xFF15120D),
    paper50: Color(0xFF1F1B15),
    paper100: Color(0xFF2B261E),
    paper200: Color(0xFF3A3328),
    saffron700: Color(0xFFE98F52),
    saffron600: Color(0xFFD8783D),
    saffron500: Color(0xFFE0864A),
    saffron100: Color(0xFF3B2616),
    green700: Color(0xFF6FD067),
    green600: Color(0xFF55BF4C),
    green500: Color(0xFF4CB944),
    green100: Color(0xFF16301A),
    colorSuccess: Color(
        0xFF5CBF6A), // not spec'd explicitly in the mockup's dark block -- a dark-safe green consistent with green700
    colorError: Color(0xFFE2766C),
    colorErrorBg: Color(0xFF3A1F1C),
    textPrimary: Color(0xFFF3ECDD),
    textBody: Color(0xFFD8CFBC),
    textSecondary: Color(0xFFA99F8C),
    textPlaceholder: Color(0xFF71685A),
    textOnAccent: Color(0xFF15120D),
    textLink: Color(0xFF55BF4C),
    surfacePage: Color(0xFF15120D),
    surfaceCard: Color(0xFF1F1B15),
    surfaceSunken: Color(0xFF2B261E),
    borderHairline: Color(0xFF2B261E),
    borderStrong: Color(0xFF3A3328),
    accentPrimary: Color(0xFFD8783D),
    accentPrimaryHover: Color(0xFFE98F52),
    accentPrimaryTint: Color(0xFF3B2616),
    accentSecondary: Color(0xFF55BF4C),
    accentSecondaryHover: Color(0xFF6FD067),
    accentSecondaryTint: Color(0xFF16301A),
    likeActive: Color(0xFFE98F52),
    tint: Color(0xFFE98F52),
    glass: Color.fromRGBO(38, 33, 26, 0.72),
    glassEdge: Color.fromRGBO(255, 255, 255, 0.1),
    onScrim: Color(0xFFFFFDF8),
    cta: Color(0xFFD8783D),
    ctaFg: Color(0xFF15120D),
    cell: Color(0xFF1F1B15),
    grouped: Color(0xFF0F0D09),
    sep: Color.fromRGBO(255, 255, 255, 0.1),
    tabActive: Color.fromRGBO(255, 255, 255, 0.1),
    appleBg: Colors.white,
    appleFg: Colors.black,
    shadowArt: [
      BoxShadow(
        offset: Offset(0, 8),
        blurRadius: 22,
        color: Color.fromRGBO(0, 0, 0, 0.5),
      ),
    ],
    shadowFloat: [
      BoxShadow(
        offset: Offset(0, 10),
        blurRadius: 30,
        color: Color.fromRGBO(0, 0, 0, 0.55),
      ),
    ],
    imageFilter: ColorFilter.matrix(
        _sepiaMatrix(saturation: 0.8, contrast: 1.05, brightness: 0.86)),
  );

  /// A CSS `sepia(0.3) saturate(s) contrast(c) brightness(b)`-equivalent
  /// color matrix (sepia amount fixed at 0.3, matching both themes).
  static List<double> _sepiaMatrix({
    required double saturation,
    required double contrast,
    required double brightness,
  }) {
    const sepiaAmount = 0.3;
    // Standard sepia matrix, blended 30% with identity.
    const sr = [0.393, 0.769, 0.189];
    const sg = [0.349, 0.686, 0.168];
    const sb = [0.272, 0.534, 0.131];
    List<double> blend(List<double> sepiaRow, int identityIndex) => [
          for (var i = 0; i < 3; i++)
            sepiaRow[i] * sepiaAmount +
                (i == identityIndex ? 1 - sepiaAmount : 0),
        ];
    final m = [blend(sr, 0), blend(sg, 1), blend(sb, 2)];

    // Saturation (Rec. 601 luma weights), then contrast, then brightness --
    // applied as successive matrix multiplications collapsed by hand since
    // dart:ui only accepts a single 4x5 matrix.
    const lumaR = 0.2126, lumaG = 0.7152, lumaB = 0.0722;
    List<double> saturate(List<double> row, double base) => [
          for (var i = 0; i < 3; i++)
            row[i] * saturation +
                base *
                    (i == 0 ? lumaR : (i == 1 ? lumaG : lumaB)) *
                    (1 - saturation),
        ];
    final sat = [
      saturate(m[0], 1),
      saturate(m[1], 1),
      saturate(m[2], 1),
    ];

    final contrastOffset = (1 - contrast) * 128;
    final scaled =
        sat.map((row) => row.map((v) => v * contrast).toList()).toList();

    return [
      scaled[0][0] * brightness,
      scaled[0][1] * brightness,
      scaled[0][2] * brightness,
      0,
      contrastOffset * brightness,
      scaled[1][0] * brightness,
      scaled[1][1] * brightness,
      scaled[1][2] * brightness,
      0,
      contrastOffset * brightness,
      scaled[2][0] * brightness,
      scaled[2][1] * brightness,
      scaled[2][2] * brightness,
      0,
      contrastOffset * brightness,
      0,
      0,
      0,
      1,
      0,
    ];
  }

  /// No partial updates needed anywhere in the app -- the two static
  /// instances above are the only values that ever exist.
  @override
  AppColorTokens copyWith() => this;

  @override
  AppColorTokens lerp(ThemeExtension<AppColorTokens>? other, double t) {
    if (other is! AppColorTokens) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColorTokens(
      ink950: c(ink950, other.ink950),
      ink800: c(ink800, other.ink800),
      ink500: c(ink500, other.ink500),
      ink300: c(ink300, other.ink300),
      ink200: c(ink200, other.ink200),
      paper0: c(paper0, other.paper0),
      paper50: c(paper50, other.paper50),
      paper100: c(paper100, other.paper100),
      paper200: c(paper200, other.paper200),
      saffron700: c(saffron700, other.saffron700),
      saffron600: c(saffron600, other.saffron600),
      saffron500: c(saffron500, other.saffron500),
      saffron100: c(saffron100, other.saffron100),
      green700: c(green700, other.green700),
      green600: c(green600, other.green600),
      green500: c(green500, other.green500),
      green100: c(green100, other.green100),
      colorSuccess: c(colorSuccess, other.colorSuccess),
      colorError: c(colorError, other.colorError),
      colorErrorBg: c(colorErrorBg, other.colorErrorBg),
      textPrimary: c(textPrimary, other.textPrimary),
      textBody: c(textBody, other.textBody),
      textSecondary: c(textSecondary, other.textSecondary),
      textPlaceholder: c(textPlaceholder, other.textPlaceholder),
      textOnAccent: c(textOnAccent, other.textOnAccent),
      textLink: c(textLink, other.textLink),
      surfacePage: c(surfacePage, other.surfacePage),
      surfaceCard: c(surfaceCard, other.surfaceCard),
      surfaceSunken: c(surfaceSunken, other.surfaceSunken),
      borderHairline: c(borderHairline, other.borderHairline),
      borderStrong: c(borderStrong, other.borderStrong),
      accentPrimary: c(accentPrimary, other.accentPrimary),
      accentPrimaryHover: c(accentPrimaryHover, other.accentPrimaryHover),
      accentPrimaryTint: c(accentPrimaryTint, other.accentPrimaryTint),
      accentSecondary: c(accentSecondary, other.accentSecondary),
      accentSecondaryHover: c(accentSecondaryHover, other.accentSecondaryHover),
      accentSecondaryTint: c(accentSecondaryTint, other.accentSecondaryTint),
      likeActive: c(likeActive, other.likeActive),
      tint: c(tint, other.tint),
      glass: c(glass, other.glass),
      glassEdge: c(glassEdge, other.glassEdge),
      onScrim: c(onScrim, other.onScrim),
      cta: c(cta, other.cta),
      ctaFg: c(ctaFg, other.ctaFg),
      cell: c(cell, other.cell),
      grouped: c(grouped, other.grouped),
      sep: c(sep, other.sep),
      tabActive: c(tabActive, other.tabActive),
      appleBg: c(appleBg, other.appleBg),
      appleFg: c(appleFg, other.appleFg),
      // Shadows/filters don't lerp meaningfully mid-transition; theme swaps
      // are instant in this app (no AnimatedTheme), so this only matters if
      // that ever changes.
      shadowArt: t < 0.5 ? shadowArt : other.shadowArt,
      shadowFloat: t < 0.5 ? shadowFloat : other.shadowFloat,
      imageFilter: t < 0.5 ? imageFilter : other.imageFilter,
    );
  }
}

extension AppColorTokensContext on BuildContext {
  /// Shorthand for `Theme.of(context).extension<AppColorTokens>()`. Falls
  /// back to [AppColorTokens.light] when nothing registered the extension
  /// (e.g. a widget test that pumps a bare `MaterialApp` with no explicit
  /// `theme:`) -- every real app entry point (`main.dart`) always provides
  /// it via [AppTheme.light]/[AppTheme.dark].
  AppColorTokens get colors =>
      Theme.of(this).extension<AppColorTokens>() ?? AppColorTokens.light;
}

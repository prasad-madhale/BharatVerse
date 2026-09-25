import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../state/onboarding_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/app_button.dart';
import '../widgets/content_column.dart';
import '../widgets/glass_surface.dart';
import 'app_shell.dart';
import 'auth_screen.dart';

/// A dark scrim + near-white text, for a caption sitting over a photo --
/// stays this fixed pair in both themes (see [AppColorTokens.onScrim]).
const _scrimBg = Color.fromRGBO(23, 20, 15, 0.66);

class _Slide {
  final String kicker;
  final String headline;
  final String body;
  final String dateline;
  final String assetPath;

  const _Slide({
    required this.kicker,
    required this.headline,
    required this.body,
    required this.dateline,
    required this.assetPath,
  });
}

const _slides = [
  _Slide(
    kicker: 'Every morning',
    headline: 'Get smarter, one story at a time',
    body: 'Empires, uprisings, and the people who shaped India — one '
        'ten-minute story lands in your feed each day.',
    dateline: 'Delhi, c. 400 CE',
    assetPath: 'assets/onboarding/iron-pillar.jpg',
  ),
  _Slide(
    kicker: 'Know your roots',
    headline: "The India you didn't learn in school",
    body: 'From ancient dynasties to the freedom struggle — the moments '
        'that built modern India, told the way a good friend would tell '
        'them.',
    dateline: 'Vaishali, c. 250 BCE',
    assetPath: 'assets/onboarding/ashoka-pillar-vaishali.jpg',
  ),
  _Slide(
    kicker: 'Every single day',
    headline: 'History, made a habit',
    body: 'Ten minutes each morning is all it takes to know more about '
        "India's past than you did yesterday.",
    dateline: 'Delhi, Independence Day',
    assetPath: 'assets/onboarding/red-fort-independence.jpg',
  ),
];

/// First-run flow: a splash screen, then [_slides]' feature slides, ending at
/// [AuthScreen] in sign-up mode -- or the reader can skip straight there, or
/// reach sign-in directly via "I already have an account" on the splash.
/// Shown once per install; see [OnboardingState]. Feature slides use bundled
/// photos (`assets/onboarding/`, curated for each slide -- Wikimedia Commons,
/// CC BY-SA 4.0 / GODL-India) rather than the mockup's own stock art or a
/// live fetch, since onboarding runs before the reader has any articles to
/// draw a photo from.
class OnboardingScreen extends StatefulWidget {
  final ApiClient apiClient;
  final OnboardingState onboardingState;

  const OnboardingScreen({
    super.key,
    required this.apiClient,
    required this.onboardingState,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  /// 0 is the splash; 1.._slides.length is a feature slide.
  int _index = 0;

  void _finish(bool signUp) {
    widget.onboardingState.markSeen();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AuthScreen(
        initialSignUp: signUp,
        onContinue: () => Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
              builder: (_) => AppShell(apiClient: widget.apiClient)),
          (route) => false,
        ),
      ),
    ));
  }

  void _next() {
    if (_index < _slides.length) {
      setState(() => _index++);
    } else {
      _finish(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isSplash = _index == 0;
    return Scaffold(
      backgroundColor: colors.surfacePage,
      body: Stack(
        children: [
          isSplash
              ? _Splash(onGetStarted: _next, onSignIn: () => _finish(false))
              : _FeatureSlide(
                  slide: _slides[_index - 1],
                  dotCount: _slides.length + 1,
                  activeDot: _index,
                  ctaLabel:
                      _index == _slides.length ? 'Get started' : 'Continue',
                  onNext: _next,
                ),
          if (!isSplash)
            Positioned(
              top: 50,
              right: 14,
              child: GlassSurface(
                height: 44,
                child: TextButton(
                  onPressed: () => _finish(true),
                  child: Text('Skip',
                      style: AppTypography.ui.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  final VoidCallback onGetStarted;
  final VoidCallback onSignIn;

  const _Splash({required this.onGetStarted, required this.onSignIn});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: ContentColumn(
                maxWidth: AppSpacing.formWidth,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.space8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'BharatVerse',
                        textAlign: TextAlign.center,
                        style: AppTypography.display1.copyWith(
                          fontSize: 44,
                          letterSpacing: -0.88,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 14),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: SizedBox(
                          width: 40,
                          height: 4,
                          child: Row(
                            children: [
                              Expanded(
                                  child: Container(color: colors.saffron600)),
                              Expanded(
                                  child: Container(color: colors.paper200)),
                              Expanded(
                                  child: Container(color: colors.green600)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Indian history, one story a day.',
                        textAlign: TextAlign.center,
                        style: AppTypography.bodyLg.copyWith(
                          fontStyle: FontStyle.italic,
                          fontSize: 18.4,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 44),
            child: ContentColumn(
              maxWidth: AppSpacing.formWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppButton(
                    label: 'Get started',
                    variant: AppButtonVariant.cta,
                    pill: true,
                    wide: true,
                    onPressed: onGetStarted,
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: TextButton(
                      onPressed: onSignIn,
                      child: Text('I already have an account',
                          style: AppTypography.ui.copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: colors.tint)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureSlide extends StatelessWidget {
  final _Slide slide;
  final int dotCount;
  final int activeDot;
  final String ctaLabel;
  final VoidCallback onNext;

  const _FeatureSlide({
    required this.slide,
    required this.dotCount,
    required this.activeDot,
    required this.ctaLabel,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(color: colors.paper100),
              ColorFiltered(
                colorFilter: colors.imageFilter,
                child: Image.asset(
                  slide.assetPath,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
              Positioned(
                left: 16,
                bottom: 16,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _scrimBg,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                  ),
                  child: Text(slide.dateline,
                      style: AppTypography.caption.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colors.onScrim)),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 40),
          child: ContentColumn(
            maxWidth: AppSpacing.formWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(slide.kicker,
                    style: AppTypography.ui.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colors.tint)),
                const SizedBox(height: 6),
                Text(
                  slide.headline,
                  style: AppTypography.display2.copyWith(
                    fontSize: 29.6,
                    height: 1.15,
                    letterSpacing: -0.44,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  slide.body,
                  style:
                      AppTypography.body.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < dotCount; i++) ...[
                      if (i > 0) const SizedBox(width: 7),
                      AnimatedContainer(
                        duration: AppSpacing.durationBase,
                        height: 7,
                        width: i == activeDot ? 20 : 7,
                        decoration: BoxDecoration(
                          color: i == activeDot
                              ? colors.textPrimary
                              : colors.ink200,
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusFull),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 20),
                AppButton(
                  label: ctaLabel,
                  variant: AppButtonVariant.cta,
                  pill: true,
                  wide: true,
                  onPressed: onNext,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

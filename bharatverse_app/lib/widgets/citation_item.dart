import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/article.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// One row in the "Sources" list at the bottom of an article. Mirrors the
/// design system's CitationItem component. Tapping it opens [ArticleCitation.sourceUrl]
/// in the device's browser.
class CitationItem extends StatelessWidget {
  /// The smallest comfortable height to tap.
  static const _minTapHeight = 48.0;

  final ArticleCitation citation;

  const CitationItem({super.key, required this.citation});

  Future<void> _openSource(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.tryParse(citation.sourceUrl);
    final opened = uri != null &&
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't open that source")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      link: true,
      child: InkWell(
        onTap: () => _openSource(context),
        child: Container(
          constraints: const BoxConstraints(minHeight: _minTapHeight),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.borderHairline)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                citation.sourceName.toUpperCase(),
                style: AppTypography.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 12 * 0.02,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                citation.text,
                style: AppTypography.caption.copyWith(color: colors.textLink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

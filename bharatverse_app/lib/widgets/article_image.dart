import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/article.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// One image within an article: the picture itself, an optional caption, and a
/// tappable credit line (mirrors CitationItem's tappable-source-link pattern).
/// Falls back to the same flat parchment block the rest of the app uses
/// while loading or if the image fails to load, so a dead source URL is
/// never a broken-image icon.
///
/// Sized by the source photo's own aspect ratio (clamped to a sane band) rather than a fixed
/// height, so it scales correctly with the available width on any device instead of turning
/// into a heavily-cropped strip on a wide screen or an oddly tall column on a narrow one.
class ArticleImageView extends StatelessWidget {
  /// The smallest comfortable height to tap for the credit line.
  static const _minTapHeight = 44.0;

  /// Keeps an unusually tall or wide source photo within a sane band for an article image,
  /// rather than rendering a jarring sliver (very wide) or an overly tall column (very narrow).
  static const _minAspectRatio = 4 / 5;
  static const _maxAspectRatio = 2 / 1;

  final ArticleImage image;

  const ArticleImageView({super.key, required this.image});

  Future<void> _openSource(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.tryParse(image.sourceUrl);
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
    final aspectRatio =
        image.aspectRatio.clamp(_minAspectRatio, _maxAspectRatio);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: aspectRatio,
          child: CachedNetworkImage(
            imageUrl: image.url,
            width: double.infinity,
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(color: colors.paper200),
            errorWidget: (context, url, error) =>
                Container(color: colors.paper200),
          ),
        ),
        const SizedBox(height: AppSpacing.space2),
        if (image.caption != null && image.caption!.isNotEmpty) ...[
          Text(
            image.caption!,
            style: AppTypography.caption.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: 2),
        ],
        Semantics(
          button: true,
          link: true,
          child: InkWell(
            onTap: () => _openSource(context),
            child: Container(
              constraints: const BoxConstraints(minHeight: _minTapHeight),
              alignment: Alignment.centerLeft,
              child: Text(
                '${image.credit} · ${image.license}',
                style: AppTypography.caption.copyWith(color: colors.textLink),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

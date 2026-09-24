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
class ArticleImageView extends StatelessWidget {
  /// The smallest comfortable height to tap for the credit line.
  static const _minTapHeight = 44.0;

  final ArticleImage image;
  final double height;

  const ArticleImageView({super.key, required this.image, this.height = 200});

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CachedNetworkImage(
          imageUrl: image.url,
          height: height,
          width: double.infinity,
          fit: BoxFit.cover,
          placeholder: (context, url) =>
              Container(height: height, color: AppColors.paper200),
          errorWidget: (context, url, error) =>
              Container(height: height, color: AppColors.paper200),
        ),
        const SizedBox(height: AppSpacing.space2),
        if (image.caption != null && image.caption!.isNotEmpty) ...[
          Text(image.caption!, style: AppTypography.caption),
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
                style:
                    AppTypography.caption.copyWith(color: AppColors.textLink),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

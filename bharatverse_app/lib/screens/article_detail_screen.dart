import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../models/article.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/app_icon_button.dart';
import '../widgets/app_tag.dart';
import '../widgets/citation_item.dart';

class ArticleDetailScreen extends StatelessWidget {
  final Article article;

  const ArticleDetailScreen({super.key, required this.article});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.surfacePage,
            border: Border(
              top: BorderSide(color: AppColors.ink950, width: 2),
              bottom: BorderSide(color: AppColors.ink200),
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                AppIconButton(
                  icon: Icons.arrow_back,
                  label: 'Back',
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Text(
                    'ARTICLE',
                    textAlign: TextAlign.center,
                    style: AppTypography.ui.copyWith(
                      fontFamily: AppTypography.headline.fontFamily,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 15 * 0.08,
                    ),
                  ),
                ),
                const SizedBox(width: 40), // balances the back button
              ],
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.space5),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space4,
              vertical: AppSpacing.space5,
            ),
            decoration:
                BoxDecoration(border: Border.all(color: AppColors.ink200)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(article.title.toUpperCase(),
                    style: AppTypography.display1),
                const SizedBox(height: AppSpacing.space4),
                Text(
                  '${article.publicationDate.toLocal().toString().split(' ').first}'
                  ' · ${article.readingTimeMinutes} min read · ${article.author}',
                  style: AppTypography.caption,
                ),
                const SizedBox(height: AppSpacing.space5),
                Container(
                    height: 180,
                    width: double.infinity,
                    color: AppColors.paper200),
                const SizedBox(height: AppSpacing.space5),
                for (final section in article.sections)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.space5),
                    child: _Section(
                        section: section,
                        isFirst: section.order == article.sections.first.order),
                  ),
                if (article.tags.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.only(top: AppSpacing.space3),
                    decoration: const BoxDecoration(
                      border: Border(
                          top: BorderSide(color: AppColors.borderHairline)),
                    ),
                    child: Wrap(
                      spacing: AppSpacing.space2,
                      runSpacing: AppSpacing.space2,
                      children: article.tags.map((t) => AppTag(t)).toList(),
                    ),
                  ),
                if (article.citations.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.space4),
                  Text('SOURCES',
                      style: AppTypography.label
                          .copyWith(color: AppColors.textSecondary)),
                  for (final citation in article.citations)
                    CitationItem(citation: citation),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One article section: uppercase serif heading + body. The first section
/// gets a drop-cap treatment on its opening letter -- a large leading
/// character, not a true CSS-style float-wrap (Flutter has no built-in
/// equivalent; see plan notes).
class _Section extends StatelessWidget {
  final ArticleSection section;
  final bool isFirst;

  const _Section({required this.section, required this.isFirst});

  @override
  Widget build(BuildContext context) {
    final bodyStyleSheet = MarkdownStyleSheet(p: AppTypography.bodyLg);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(section.heading.toUpperCase(), style: AppTypography.headline),
        const SizedBox(height: AppSpacing.space2),
        if (isFirst && section.content.isNotEmpty)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                section.content.substring(0, 1),
                style: AppTypography.display1
                    .copyWith(fontSize: 40 * 1.4, height: 0.8),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: MarkdownBody(
                  data: section.content.substring(1),
                  styleSheet: bodyStyleSheet,
                ),
              ),
            ],
          )
        else
          MarkdownBody(data: section.content, styleSheet: bodyStyleSheet),
      ],
    );
  }
}

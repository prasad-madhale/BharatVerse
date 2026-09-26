import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/article.dart';
import '../services/api_client.dart';
import '../services/reading_history.dart';
import '../services/saves_client.dart';
import '../state/auth_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/account_avatar.dart';
import '../widgets/content_column.dart';
import '../widgets/empty_state.dart';
import '../widgets/save_button.dart';
import 'article_detail_screen.dart';
import 'auth_screen.dart';

/// The signed-in user's saved (bookmarked) articles, and this device's
/// recently read articles -- Library's two independent sections. Saved
/// needs a signed-in account (like Likes); recently read is device-local
/// and works while signed out too.
class LibraryScreen extends StatefulWidget {
  final ApiClient apiClient;

  const LibraryScreen({super.key, required this.apiClient});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late Future<List<Article>> _saved;
  late Future<List<Article>> _history;

  @override
  void initState() {
    super.initState();
    _start();
  }

  // The FutureBuilders show the error; ignore() keeps a fast failure from
  // also being reported as unhandled before the next frame subscribes.
  void _start() {
    _saved = _loadSaved()..ignore();
    _history = _loadHistory()..ignore();
  }

  Future<List<Article>> _loadSaved() async {
    final token = context.read<AuthState>().authToken;
    if (token == null) {
      return [];
    }
    final rows = await context
        .read<SavesClient>()
        .getSavedArticleRows(accessToken: token);
    return widget.apiClient.loadArticles(rows);
  }

  Future<List<Article>> _loadHistory() async {
    final ids = context.read<ReadingHistory>().articleIds;
    final articles = <Article>[];
    for (final id in ids) {
      try {
        articles.add(await widget.apiClient.getArticleById(id));
      } catch (_) {
        // An article that no longer loads (deleted, or offline with no
        // cached copy) is just left out, not treated as a page failure.
      }
    }
    return articles;
  }

  Future<void> _open(Article article) async {
    await openArticle(context, widget.apiClient, article);
    // Reading history and, if unsaved while reading, saved both may have
    // changed.
    if (mounted) setState(_start);
  }

  void _requireAuth() => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.surfacePage,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: columnPadding(context, vertical: AppSpacing.space2)
              .copyWith(bottom: 120),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    'Library',
                    style: AppTypography.display1.copyWith(
                      fontSize: 34.4,
                      height: 1.05,
                      letterSpacing: -0.688,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                const AccountAvatar(),
              ],
            ),
            const SizedBox(height: AppSpacing.space4),
            FutureBuilder<List<Article>>(
              future: _saved,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.space8),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return EmptyState(
                    icon: Icons.error_outline,
                    title: 'Could not load your saved articles',
                    description: describeError(snapshot.error),
                    actionLabel: 'Retry',
                    onAction: () => setState(_start),
                  );
                }
                final saved = snapshot.data!;
                if (saved.isEmpty) {
                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.space6),
                    child: Column(
                      children: [
                        Icon(Icons.bookmark_border,
                            size: 32, color: colors.ink300),
                        const SizedBox(height: AppSpacing.space2),
                        Text('Nothing saved yet',
                            style: AppTypography.headline
                                .copyWith(color: colors.textPrimary)),
                        const SizedBox(height: AppSpacing.space1),
                        Text(
                          'Tap the bookmark on any story to keep it here.',
                          textAlign: TextAlign.center,
                          style: AppTypography.body
                              .copyWith(color: colors.textBody),
                        ),
                      ],
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Saved · ${saved.length}',
                        style: AppTypography.headline.copyWith(
                            fontSize: 20.8,
                            letterSpacing: -0.208,
                            color: colors.textPrimary)),
                    for (final article in saved)
                      _LibraryRow(
                        article: article,
                        thumbnailSize: 64,
                        onTap: () => _open(article),
                        onRequireAuth: _requireAuth,
                      ),
                  ],
                );
              },
            ),
            FutureBuilder<List<Article>>(
              future: _history,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done ||
                    snapshot.hasError ||
                    (snapshot.data?.isEmpty ?? true)) {
                  return const SizedBox.shrink();
                }
                final history = snapshot.data!;
                return Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.space6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Recently read',
                          style: AppTypography.headline.copyWith(
                              fontSize: 20.8,
                              letterSpacing: -0.208,
                              color: colors.textPrimary)),
                      for (final article in history)
                        _LibraryRow(
                          article: article,
                          thumbnailSize: 52,
                          onTap: () => _open(article),
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact row for Library's Saved/Recently-read lists: thumbnail, title,
/// era, and (Saved only, via [onRequireAuth]) a bookmark button to remove it
/// without opening the article. Its own layout since neither Library
/// section matches [ArticleCard]'s compact row (no reading-time pill, and
/// only Saved rows get the bookmark).
class _LibraryRow extends StatelessWidget {
  final Article article;
  final double thumbnailSize;
  final VoidCallback onTap;

  /// Shows a [SaveButton] (Saved rows) when given; omitted for Recently
  /// read, which the mockup gives no action to.
  final VoidCallback? onRequireAuth;

  const _LibraryRow({
    required this.article,
    required this.thumbnailSize,
    required this.onTap,
    this.onRequireAuth,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final url = article.imageUrl;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.space2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              child: SizedBox(
                width: thumbnailSize,
                height: thumbnailSize,
                child: url == null
                    ? Container(color: colors.paper100)
                    : ColorFiltered(
                        colorFilter: colors.imageFilter,
                        child: CachedNetworkImage(
                          imageUrl: url,
                          fit: BoxFit.cover,
                          placeholder: (context, url) =>
                              Container(color: colors.paper100),
                          errorWidget: (context, url, error) =>
                              Container(color: colors.paper100),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: AppSpacing.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (article.era.isNotEmpty) ...[
                    Text(article.era,
                        style: AppTypography.caption.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colors.textSecondary)),
                    const SizedBox(height: 2),
                  ],
                  Text(
                    article.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.headline.copyWith(
                      fontSize: 15.2,
                      height: 1.28,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            if (onRequireAuth != null)
              SaveButton(articleId: article.id, onRequireAuth: onRequireAuth!),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/article.dart';
import '../services/api_client.dart';
import '../services/likes_client.dart';
import '../state/auth_state.dart';
import '../state/like_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_back_bar.dart';
import '../widgets/article_card.dart';
import '../widgets/content_column.dart';
import '../widgets/empty_state.dart';
import '../widgets/screen_heading.dart';
import 'article_detail_screen.dart';
import 'auth_screen.dart';

/// The signed-in user's liked articles, most recently liked first.
class LikedArticlesScreen extends StatefulWidget {
  final ApiClient apiClient;

  const LikedArticlesScreen({super.key, required this.apiClient});

  @override
  State<LikedArticlesScreen> createState() => _LikedArticlesScreenState();
}

class _LikedArticlesScreenState extends State<LikedArticlesScreen> {
  late Future<List<Article>> _articles;

  @override
  void initState() {
    super.initState();
    _start();
  }

  // The FutureBuilder shows the error; ignore() keeps a fast failure from also
  // being reported as unhandled before the next frame subscribes.
  void _start() {
    _articles = _load()..ignore();
  }

  Future<List<Article>> _load() async {
    final token = context.read<AuthState>().authToken;
    if (token == null) {
      return [];
    }
    final rows = await context
        .read<LikesClient>()
        .getLikedArticleRows(accessToken: token);
    return widget.apiClient.loadArticles(rows);
  }

  Future<void> _open(Article article) async {
    await openArticle(context, widget.apiClient, article);
    // Unliked while reading: refresh so it leaves the list.
    if (mounted && !context.read<LikeState>().isLiked(article.id)) {
      setState(_start);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppBackBar(),
      body: Column(
        children: [
          const ScreenHeading('Liked articles'),
          Expanded(
            child: FutureBuilder<List<Article>>(
              future: _articles,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: EmptyState(
                      icon: Icons.error_outline,
                      title: 'Could not load your likes',
                      description: describeError(snapshot.error),
                      actionLabel: 'Retry',
                      onAction: () => setState(_start),
                    ),
                  );
                }
                final articles = snapshot.data!;
                if (articles.isEmpty) {
                  return const Center(
                    child: EmptyState(
                      icon: Icons.favorite_border,
                      title: 'No liked articles',
                      description:
                          'Tap the heart on an article to keep it here.',
                    ),
                  );
                }
                return ListView.builder(
                  padding: columnPadding(context, vertical: AppSpacing.space2),
                  itemCount: articles.length,
                  itemBuilder: (context, index) => ArticleCard(
                    article: articles[index],
                    onTap: () => _open(articles[index]),
                    onRequireAuth: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AuthScreen()),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

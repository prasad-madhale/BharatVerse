import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/article.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_header.dart';
import '../widgets/arrow_link.dart';
import '../widgets/article_card.dart';
import '../widgets/content_column.dart';
import '../widgets/empty_state.dart';
import '../widgets/offline_banner.dart';
import 'archive_screen.dart';
import 'article_detail_screen.dart';
import 'auth_screen.dart';
import 'liked_articles_screen.dart';
import 'search_screen.dart';

class HomeScreen extends StatefulWidget {
  final ApiClient apiClient;

  const HomeScreen({super.key, required this.apiClient});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _recentLimit = 5;

  late Future<List<Article>> _recentArticles;

  @override
  void initState() {
    super.initState();
    _recentArticles = widget.apiClient.getRecentArticles(limit: _recentLimit);
  }

  void _retry() {
    setState(() {
      _recentArticles = widget.apiClient.getRecentArticles(limit: _recentLimit);
    });
  }

  void _openAuth(BuildContext context, AuthState authState) {
    if (authState.isAuthenticated) {
      authState.logout();
    } else {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const AuthScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthState>();
    return Scaffold(
      appBar: AppHeader(
        authenticated: authState.isAuthenticated,
        onAuthClick: () => _openAuth(context, authState),
        onSearchClick: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SearchScreen(apiClient: widget.apiClient),
          ),
        ),
        onLikedClick: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => LikedArticlesScreen(apiClient: widget.apiClient),
          ),
        ),
      ),
      body: Column(children: [
        OfflineBanner(offline: widget.apiClient.offline),
        Expanded(
            child: FutureBuilder<List<Article>>(
          future: _recentArticles,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: EmptyState(
                  icon: Icons.error_outline,
                  title: 'Could not load articles',
                  description: describeError(snapshot.error),
                  actionLabel: 'Retry',
                  onAction: _retry,
                ),
              );
            }

            final articles = snapshot.data!;
            if (articles.isEmpty) {
              return RefreshIndicator(
                onRefresh: () async => _retry(),
                child: ListView(
                  children: const [
                    EmptyState(
                      title: 'No articles yet',
                      description: 'Check back soon!',
                    ),
                  ],
                ),
              );
            }

            // Only a full page suggests there are older articles to browse.
            final showArchive = articles.length >= _recentLimit;
            return RefreshIndicator(
              onRefresh: () async => _retry(),
              child: ListView.builder(
                padding: columnPadding(context, vertical: AppSpacing.space2),
                itemCount: articles.length + (showArchive ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == articles.length) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: ArrowLink(
                        label: 'Browse the archive',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                ArchiveScreen(apiClient: widget.apiClient),
                          ),
                        ),
                      ),
                    );
                  }
                  final article = articles[index];
                  return ArticleCard(
                    article: article,
                    size: index == 0
                        ? ArticleCardSize.featured
                        : ArticleCardSize.compact,
                    onTap: () =>
                        openArticle(context, widget.apiClient, article),
                  );
                },
              ),
            );
          },
        ))
      ]),
    );
  }
}

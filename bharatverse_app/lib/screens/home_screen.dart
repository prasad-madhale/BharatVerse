import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/article.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_header.dart';
import '../widgets/article_card.dart';
import '../widgets/empty_state.dart';
import 'article_detail_screen.dart';
import 'auth_screen.dart';

class HomeScreen extends StatefulWidget {
  final ApiClient apiClient;

  const HomeScreen({super.key, required this.apiClient});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<Article>> _recentArticles;

  @override
  void initState() {
    super.initState();
    _recentArticles = widget.apiClient.getRecentArticles();
  }

  void _retry() {
    setState(() {
      _recentArticles = widget.apiClient.getRecentArticles();
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
      ),
      body: FutureBuilder<List<Article>>(
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
                description: '${snapshot.error}',
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

          return RefreshIndicator(
            onRefresh: () async => _retry(),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space4,
                vertical: AppSpacing.space2,
              ),
              itemCount: articles.length,
              itemBuilder: (context, index) {
                final article = articles[index];
                return ArticleCard(
                  article: article,
                  size: index == 0
                      ? ArticleCardSize.featured
                      : ArticleCardSize.compact,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ArticleDetailScreen(article: article),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/article.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BharatVerse'),
        actions: [
          Consumer<AuthState>(
            builder: (context, authState, _) => IconButton(
              icon: Icon(authState.isAuthenticated
                  ? Icons.account_circle
                  : Icons.login),
              tooltip: authState.isAuthenticated ? 'Sign out' : 'Sign in',
              onPressed: () => authState.isAuthenticated
                  ? authState.logout()
                  : Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AuthScreen()),
                    ),
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<Article>>(
        future: _recentArticles,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'Could not load articles.\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                        onPressed: _retry, child: const Text('Retry')),
                  ],
                ),
              ),
            );
          }

          final articles = snapshot.data!;
          if (articles.isEmpty) {
            return RefreshIndicator(
              onRefresh: () async => _retry(),
              child: ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                        child: Text('No articles yet. Check back soon!')),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _retry(),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: articles.length,
              itemBuilder: (context, index) {
                final article = articles[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Card(
                    child: InkWell(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ArticleDetailScreen(article: article),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (index == 0)
                              Text(
                                'TODAY\'S ARTICLE',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            if (index == 0) const SizedBox(height: 8),
                            Text(article.title,
                                style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: 8),
                            Text(article.summary),
                            const SizedBox(height: 8),
                            Text(
                              '${article.readingTimeMinutes} min read',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
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

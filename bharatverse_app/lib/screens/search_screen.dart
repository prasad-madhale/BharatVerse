import 'package:flutter/material.dart';

import '../models/article.dart';
import '../services/api_client.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/app_back_bar.dart';
import '../widgets/app_button.dart';
import '../widgets/app_input.dart';
import '../widgets/article_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/highlighted_text.dart';
import 'article_detail_screen.dart';

/// Full-text search over the archive. Searches on submit and highlights the
/// matched terms in the results.
class SearchScreen extends StatefulWidget {
  final ApiClient apiClient;

  const SearchScreen({super.key, required this.apiClient});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';
  Future<List<Article>>? _results;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _search([String? query]) {
    final text = (query ?? _controller.text).trim();
    if (text.isEmpty) {
      return;
    }
    setState(() {
      _query = text;
      // The FutureBuilder shows the error; without this a fast failure is also
      // reported as unhandled if it lands before the next frame subscribes.
      _results = widget.apiClient.searchArticles(text)..ignore();
    });
  }

  Widget _buildResults() {
    if (_results == null) {
      return const Center(
        child: EmptyState(
          icon: Icons.search,
          title: 'Search the archive',
          description: 'Try a name, a place, or a phrase in quotes.',
        ),
      );
    }
    return FutureBuilder<List<Article>>(
      future: _results,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: EmptyState(
              icon: Icons.error_outline,
              title: 'Search failed',
              description: '${snapshot.error}',
              actionLabel: 'Retry',
              onAction: () => _search(_query),
            ),
          );
        }
        final articles = snapshot.data!;
        if (articles.isEmpty) {
          return Center(
            child: EmptyState(
              icon: Icons.search_off,
              title: 'No results',
              description: 'Nothing matched "$_query". Try a different '
                  'spelling, fewer words, or a broader term.',
            ),
          );
        }
        final terms = searchTerms(_query);
        return ListView.builder(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.space4,
            vertical: AppSpacing.space2,
          ),
          itemCount: articles.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.space2),
                child: Text(
                  '${articles.length} ${articles.length == 1 ? 'result' : 'results'}',
                  style: AppTypography.caption,
                ),
              );
            }
            final article = articles[index - 1];
            return ArticleCard(
              article: article,
              highlight: terms,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ArticleDetailScreen(article: article),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppBackBar(),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppInput(
                  label: 'Search',
                  controller: _controller,
                  placeholder: 'Ashoka, Chola, "Bay of Bengal"',
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  autofocus: true,
                ),
                const SizedBox(height: AppSpacing.space3),
                AppButton(label: 'Search', wide: true, onPressed: _search),
              ],
            ),
          ),
          Expanded(child: _buildResults()),
        ],
      ),
    );
  }
}

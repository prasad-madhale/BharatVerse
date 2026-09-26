import 'dart:async';

import 'package:flutter/material.dart';

import '../models/article.dart';
import '../services/api_client.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/app_back_bar.dart';
import '../widgets/app_button.dart';
import '../widgets/app_input.dart';
import '../widgets/article_card.dart';
import '../widgets/content_column.dart';
import '../widgets/empty_state.dart';
import '../widgets/highlighted_text.dart';
import '../widgets/suggestion_tile.dart';
import 'article_detail_screen.dart';
import 'auth_screen.dart';

/// Full-text search over the archive. Searches on submit and highlights the
/// matched terms in the results. While the reader types, the titles and tags
/// that start with the text are suggested in place of the results.
class SearchScreen extends StatefulWidget {
  final ApiClient apiClient;

  const SearchScreen({super.key, required this.apiClient});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  /// How long typing must pause before suggestions are asked for.
  static const _suggestDelay = Duration(milliseconds: 200);

  final _controller = TextEditingController();
  Timer? _suggestTimer;
  int _suggestRequest = 0;
  List<String> _suggestions = [];
  String _suggestedFor = '';
  String _query = '';
  Future<List<Article>>? _results;

  @override
  void dispose() {
    _suggestTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Drops the suggestions, and any request for them that is waiting or in
  /// flight, so a late answer cannot bring them back.
  void _clearSuggestions() {
    _suggestTimer?.cancel();
    _suggestRequest++;
    _suggestions = [];
  }

  void _onChanged(String text) {
    _suggestTimer?.cancel();
    if (text.trim().isEmpty) {
      setState(_clearSuggestions);
      return;
    }
    _suggestTimer = Timer(_suggestDelay, () => _suggest(text));
  }

  Future<void> _suggest(String text) async {
    final request = ++_suggestRequest;
    List<String> found;
    try {
      found = await widget.apiClient.getAutocompleteSuggestions(text);
    } on Exception {
      // Suggestions are a convenience: when they cannot be had, show none.
      found = [];
    }
    if (mounted && request == _suggestRequest) {
      setState(() {
        _suggestions = found;
        _suggestedFor = text;
      });
    }
  }

  void _pickSuggestion(String term) {
    _controller.value = TextEditingValue(
      text: term,
      selection: TextSelection.collapsed(offset: term.length),
    );
    FocusScope.of(context).unfocus(); // the keyboard would cover the results
    _search(term);
  }

  void _search([String? query]) {
    final text = (query ?? _controller.text).trim();
    if (text.isEmpty) {
      return;
    }
    setState(() {
      _clearSuggestions();
      _query = text;
      // The FutureBuilder shows the error; without this a fast failure is also
      // reported as unhandled if it lands before the next frame subscribes.
      _results = widget.apiClient.searchArticles(text)..ignore();
    });
  }

  Widget _buildSuggestions() {
    final count = _suggestions.length;
    return Semantics(
      container: true,
      liveRegion: true, // a screen reader announces that suggestions appeared
      label: '${count == 1 ? '1 suggestion' : '$count suggestions'} '
          'for ${_suggestedFor.trim()}',
      child: ListView.builder(
        padding: columnPadding(context, vertical: AppSpacing.space1),
        itemCount: count,
        itemBuilder: (context, index) {
          final term = _suggestions[index];
          return SuggestionTile(
            term: term,
            typed: _suggestedFor,
            onTap: () => _pickSuggestion(term),
          );
        },
      ),
    );
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
              description: describeError(snapshot.error),
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
          padding: columnPadding(context, vertical: AppSpacing.space2),
          itemCount: articles.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.space2),
                child: Text(
                  '${articles.length} ${articles.length == 1 ? 'result' : 'results'}',
                  style: AppTypography.caption
                      .copyWith(color: context.colors.textSecondary),
                ),
              );
            }
            final article = articles[index - 1];
            return ArticleCard(
              article: article,
              highlight: terms,
              onTap: () => openArticle(context, widget.apiClient, article),
              onRequireAuth: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AuthScreen()),
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
          ContentColumn(
              child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.space4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppInput(
                        label: 'Search',
                        controller: _controller,
                        placeholder: 'Ashoka, Chola, "Bay of Bengal"',
                        textInputAction: TextInputAction.search,
                        onChanged: _onChanged,
                        onSubmitted: (_) => _search(),
                        autofocus: true,
                      ),
                      const SizedBox(height: AppSpacing.space3),
                      AppButton(
                          label: 'Search', wide: true, onPressed: _search),
                    ],
                  ))),
          // Both stay mounted, so the results keep their scroll position and
          // do not reload while suggestions come and go.
          Expanded(
            child: IndexedStack(
              sizing: StackFit.expand,
              index: _suggestions.isEmpty ? 0 : 1,
              children: [_buildResults(), _buildSuggestions()],
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/article.dart';
import '../services/api_client.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/app_button.dart';
import '../widgets/article_card.dart';
import '../widgets/content_column.dart';
import '../widgets/empty_state.dart';
import '../widgets/highlighted_text.dart';
import '../widgets/suggestion_tile.dart';
import 'article_detail_screen.dart';
import 'auth_screen.dart';

/// Full-text search over the archive. Searches on submit and highlights the
/// matched terms in the results. While the reader types, the titles and tags
/// that start with the text are suggested in place of the results. An empty
/// query instead browses by era.
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
  late final Future<List<EraSummary>> _eras;

  @override
  void initState() {
    super.initState();
    // Best-effort like ReadingHistory elsewhere: a failed fetch just leaves
    // the era grid empty rather than showing an error, so it is not awaited
    // or retried here.
    _eras = widget.apiClient.getEras()..ignore();
  }

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

  void _clear() {
    _controller.clear();
    setState(_clearSuggestions);
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

  /// Fills the field with [term] (a suggestion or an era label) and searches
  /// for it, as if the reader had typed and submitted it themselves.
  void _selectQuery(String term) {
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

  Widget _buildEraGrid() {
    return FutureBuilder<List<EraSummary>>(
      future: _eras,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final eras = snapshot.data ?? const [];
        if (eras.isEmpty) {
          return const Center(
            child: EmptyState(
              icon: Icons.search,
              title: 'Search the archive',
              description: 'Try a name, a place, or a phrase in quotes.',
            ),
          );
        }
        final colors = context.colors;
        return ListView(
          padding: columnPadding(context, vertical: AppSpacing.space2),
          children: [
            Text(
              'Browse by era',
              style: AppTypography.display2.copyWith(
                  fontSize: 21.6,
                  letterSpacing: -0.216,
                  color: colors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.space3),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: AppSpacing.space3,
              crossAxisSpacing: AppSpacing.space3,
              childAspectRatio: 4 / 3,
              children: [
                for (final era in eras)
                  _EraCard(era: era, onTap: () => _selectQuery(era.era)),
              ],
            ),
          ],
        );
      },
    );
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
            onTap: () => _selectQuery(term),
          );
        },
      ),
    );
  }

  Widget _buildResults() {
    if (_results == null) {
      // Nothing has been searched for yet -- browse by era instead of a
      // bare prompt (which _buildEraGrid falls back to when there are no
      // eras to browse yet).
      return _buildEraGrid();
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
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.surfacePage,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ContentColumn(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.space4,
                    AppSpacing.space2, AppSpacing.space4, AppSpacing.space3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.chevron_left,
                              color: colors.textPrimary),
                          tooltip: 'Back',
                          onPressed: () => Navigator.of(context).pop(),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Search',
                          style: AppTypography.display1.copyWith(
                              fontSize: 30,
                              height: 1.05,
                              letterSpacing: -0.6,
                              color: colors.textPrimary),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.space3),
                    _SearchField(
                      key: const Key('search-field'),
                      controller: _controller,
                      onChanged: _onChanged,
                      onSubmitted: (_) => _search(),
                      onClear: _clear,
                    ),
                    const SizedBox(height: AppSpacing.space3),
                    Align(
                      alignment: Alignment.centerRight,
                      child: AppButton(
                        label: 'Search',
                        pill: true,
                        size: AppButtonSize.sm,
                        onPressed: _search,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Both stay mounted, so the results (or the era grid, before
            // anything is searched for) keep their scroll position and do
            // not reload while suggestions come and go.
            Expanded(
              child: IndexedStack(
                sizing: StackFit.expand,
                index: _suggestions.isEmpty ? 0 : 1,
                children: [_buildResults(), _buildSuggestions()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The mockup's borderless rounded search field: a leading icon, the field
/// itself, and a clear button once there is text to clear.
class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  const _SearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3),
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 18, color: colors.textSecondary),
          const SizedBox(width: AppSpacing.space2),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              textInputAction: TextInputAction.search,
              autofocus: true,
              style: AppTypography.ui
                  .copyWith(fontSize: 17, color: colors.textPrimary),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: 'Rulers, places, eras',
                hintStyle: AppTypography.ui
                    .copyWith(fontSize: 17, color: colors.textPlaceholder),
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => value.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    icon: Icon(Icons.cancel,
                        size: 18, color: colors.textSecondary),
                    tooltip: 'Clear',
                    onPressed: onClear,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
          ),
        ],
      ),
    );
  }
}

/// One era card in the "Browse by era" grid: a real article's image (or a
/// plain dark tile when none of that era have one yet) with the era label
/// over it. Tapping it searches for that era's exact label.
class _EraCard extends StatelessWidget {
  final EraSummary era;
  final VoidCallback onTap;

  const _EraCard({required this.era, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final imageUrl = era.imageUrl;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: imageUrl == null ? colors.ink800 : colors.paper100,
          borderRadius: BorderRadius.circular(14),
          boxShadow: colors.shadowArt,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl != null) ...[
              ColorFiltered(
                colorFilter: colors.imageFilter,
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) =>
                      Container(color: colors.ink800),
                ),
              ),
              Container(color: const Color.fromRGBO(0, 0, 0, 0.35)),
            ],
            Positioned(
              left: 12,
              right: 12,
              bottom: 10,
              child: Text(
                era.era,
                style: AppTypography.headline.copyWith(
                    fontSize: 16.8, height: 1.2, color: colors.onScrim),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

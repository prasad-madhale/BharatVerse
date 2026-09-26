import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/article.dart';
import '../services/api_client.dart';
import '../services/reading_history.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/glass_surface.dart';
import 'article_detail_screen.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'search_screen.dart';

enum _AppTab { today, library }

/// Root shell for the signed-in app: an [IndexedStack] holding the Today and
/// Library tabs, under a floating glass-blur tab bar with a separate Search
/// button -- Milestone 1's navigation model (see docs/roadmap.md and the
/// design handoff's "Tab bar, now and later" section). Screens stay resident
/// in the stack, so switching tabs never loses scroll position.
class AppShell extends StatefulWidget {
  final ApiClient apiClient;

  const AppShell({super.key, required this.apiClient});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  _AppTab _tab = _AppTab.today;

  @override
  Widget build(BuildContext context) {
    // Watched, not read: a ChangeNotifier so this rebuilds the moment any
    // screen opens a new article, without AppShell needing its own signal
    // for every place that can open one (Home, Library, Search, era cards).
    final lastReadId = context.watch<ReadingHistory>().articleIds.firstOrNull;
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _tab.index,
            children: [
              HomeScreen(apiClient: widget.apiClient),
              LibraryScreen(apiClient: widget.apiClient),
            ],
          ),
          Positioned(
            left: AppSpacing.space4,
            right: AppSpacing.space4,
            bottom: 28,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (lastReadId != null) ...[
                    _ContinueReadingBar(
                      key: ValueKey(lastReadId),
                      apiClient: widget.apiClient,
                      articleId: lastReadId,
                    ),
                    const SizedBox(height: AppSpacing.space2),
                  ],
                  _TabBar(
                    tab: _tab,
                    onSelectTab: (t) => setState(() => _tab = t),
                    onSearch: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            SearchScreen(apiClient: widget.apiClient),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The most recently opened article, in a floating glass pill above the tab
/// bar -- tapping it re-opens that article. Shows the article's own reading
/// time rather than the design's "N min left": with no reading-progress
/// tracking, a time *remaining* would be fabricated, unlike its total length.
class _ContinueReadingBar extends StatelessWidget {
  final ApiClient apiClient;
  final String articleId;

  const _ContinueReadingBar({
    super.key,
    required this.apiClient,
    required this.articleId,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Article>(
      future: apiClient.getArticleById(articleId),
      builder: (context, snapshot) {
        final article = snapshot.data;
        if (article == null) {
          // Loading, or the article is gone (deleted, or offline with no
          // cached copy) -- either way there is nothing worth showing yet.
          return const SizedBox.shrink();
        }
        final colors = context.colors;
        final url = article.imageUrl;
        return GlassSurface(
          height: 56,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
            onTap: () => openArticle(context, apiClient, article),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, AppSpacing.space4, 0),
              child: Row(
                children: [
                  ClipOval(
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: url == null
                          ? Container(color: colors.paper100)
                          : ColorFiltered(
                              colorFilter: colors.imageFilter,
                              child: CachedNetworkImage(
                                imageUrl: url,
                                fit: BoxFit.cover,
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
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          article.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.ui.copyWith(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary),
                        ),
                        Text(
                          'Continue reading · ${article.readingTimeMinutes} min read',
                          style: AppTypography.caption.copyWith(
                              fontSize: 12, color: colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.menu_book_outlined, size: 20, color: colors.tint),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TabBar extends StatelessWidget {
  final _AppTab tab;
  final ValueChanged<_AppTab> onSelectTab;
  final VoidCallback onSearch;

  const _TabBar({
    required this.tab,
    required this.onSelectTab,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Expanded(
          child: GlassSurface(
            height: 62,
            child: Row(
              children: [
                Expanded(
                  child: _TabButton(
                    icon: Icons.article_outlined,
                    label: 'Today',
                    active: tab == _AppTab.today,
                    onTap: () => onSelectTab(_AppTab.today),
                  ),
                ),
                Expanded(
                  child: _TabButton(
                    icon: Icons.bookmark_border,
                    label: 'Library',
                    active: tab == _AppTab.library,
                    onTap: () => onSelectTab(_AppTab.library),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.space2),
        GlassSurface(
          height: 62,
          width: 62,
          child: IconButton(
            icon: Icon(Icons.search, color: colors.textPrimary),
            onPressed: onSearch,
            tooltip: 'Search',
          ),
        ),
      ],
    );
  }
}

class _TabButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _TabButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = active ? colors.tint : colors.textPrimary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      child: Container(
        margin: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: active ? colors.tabActive : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              style: AppTypography.label.copyWith(fontSize: 11, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

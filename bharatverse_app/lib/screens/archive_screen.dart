import 'package:flutter/material.dart';

import '../models/article.dart';
import '../services/api_client.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/app_back_bar.dart';
import '../widgets/app_button.dart';
import '../widgets/article_card.dart';
import '../widgets/content_column.dart';
import '../widgets/empty_state.dart';
import '../widgets/offline_banner.dart';
import '../widgets/screen_heading.dart';
import 'article_detail_screen.dart';
import 'auth_screen.dart';

/// Every past article, newest first, loaded a page at a time as the reader
/// scrolls.
class ArchiveScreen extends StatefulWidget {
  final ApiClient apiClient;

  const ArchiveScreen({super.key, required this.apiClient});

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  static const _pageSize = 20;

  final _scroll = ScrollController();
  final _articles = <Article>[];
  int _page = 0;
  bool _loading = false;
  bool _done = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_loadMoreIfNeeded);
    _loadMore();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _loadMoreIfNeeded() {
    // Not when an error is already showing: that must wait for an explicit
    // Retry tap, or staying scrolled to the bottom would retry it silently
    // on every frame without the reader ever seeing it failed.
    if (_scroll.hasClients &&
        _scroll.position.extentAfter < 300 &&
        _error == null) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _done) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page =
          await widget.apiClient.listArticles(page: _page, limit: _pageSize);
      if (!mounted) {
        return;
      }
      setState(() {
        // A newly published article shifts every later page by one, so never
        // list an article twice.
        final seen = _articles.map((article) => article.id).toSet();
        _articles.addAll(page.where((article) => !seen.contains(article.id)));
        _page++;
        _done = page.length < _pageSize;
        _loading = false;
      });
      // A tall window may not scroll at all, so keep loading until it is full.
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadMoreIfNeeded());
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Widget _footer() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.space4),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.space4),
        child: Column(
          children: [
            Text(
              describeError(_error),
              textAlign: TextAlign.center,
              style: AppTypography.caption
                  .copyWith(color: context.colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.space2),
            AppButton(
              label: 'Retry',
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.sm,
              onPressed: _loadMore,
            ),
          ],
        ),
      );
    }
    if (_done) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.space4),
        child: Center(
          child: Text(
            'That is every article so far.',
            style: AppTypography.caption
                .copyWith(color: context.colors.textSecondary),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildBody() {
    if (_articles.isEmpty) {
      if (_error != null) {
        return Center(
          child: EmptyState(
            icon: Icons.error_outline,
            title: 'Could not load articles',
            description: describeError(_error),
            actionLabel: 'Retry',
            onAction: _loadMore,
          ),
        );
      }
      if (_done) {
        return const Center(
          child: EmptyState(
            title: 'No articles yet',
            description: 'Check back soon!',
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    return ListView.builder(
      controller: _scroll,
      padding: columnPadding(context, vertical: AppSpacing.space2),
      itemCount: _articles.length + 1,
      itemBuilder: (context, index) {
        if (index == _articles.length) {
          return _footer();
        }
        final article = _articles[index];
        return ArticleCard(
          article: article,
          onTap: () => openArticle(context, widget.apiClient, article),
          onRequireAuth: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AuthScreen()),
          ),
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
          const ScreenHeading('Archive'),
          OfflineBanner(offline: widget.apiClient.offline),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }
}

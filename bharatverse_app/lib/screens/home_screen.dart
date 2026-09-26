import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/article.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/article_card.dart';
import '../widgets/content_column.dart';
import '../widgets/empty_state.dart';
import '../widgets/offline_banner.dart';
import 'archive_screen.dart';
import 'article_detail_screen.dart';
import 'auth_screen.dart';

const _categories = ['All', 'Empires', 'Culture', 'Trade', 'Science'];
const _weekdayNames = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', //
  'Friday', 'Saturday', 'Sunday',
];
const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];

class HomeScreen extends StatefulWidget {
  final ApiClient apiClient;

  const HomeScreen({super.key, required this.apiClient});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _recentLimit = 5;

  late Future<List<Article>> _recentArticles;
  String _activeCategory = 'All';

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

  void _requireAuth(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );

  /// [articles] whose tags or era match [_activeCategory], or all of them
  /// when "All" is selected.
  List<Article> _filtered(List<Article> articles) {
    if (_activeCategory == 'All') return articles;
    final query = _activeCategory.toLowerCase();
    return articles
        .where((a) =>
            a.era.toLowerCase().contains(query) ||
            a.tags.any((t) => t.toLowerCase().contains(query)))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final authState = context.watch<AuthState>();
    return Scaffold(
      backgroundColor: colors.surfacePage,
      body: Column(
        children: [
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

                final all = snapshot.data!;
                if (all.isEmpty) {
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

                final articles = _filtered(all);
                final featured = articles.isEmpty ? null : articles.first;
                final week = articles.length > 1
                    ? articles.sublist(1)
                    : const <Article>[];

                return RefreshIndicator(
                  onRefresh: () async => _retry(),
                  child: ListView(
                    padding: columnPadding(context, vertical: AppSpacing.space2)
                        .copyWith(bottom: 120),
                    children: [
                      _Masthead(
                        authenticated: authState.isAuthenticated,
                        email: authState.currentUser?.email,
                        onAvatarTap: () => _openAuth(context, authState),
                      ),
                      const SizedBox(height: AppSpacing.space2),
                      _CategoryRow(
                        active: _activeCategory,
                        onSelect: (c) => setState(() => _activeCategory = c),
                      ),
                      const SizedBox(height: AppSpacing.space5),
                      if (featured == null)
                        const Padding(
                          padding:
                              EdgeInsets.symmetric(vertical: AppSpacing.space8),
                          child: EmptyState(
                            title: 'No matches',
                            description: 'Try a different category.',
                          ),
                        )
                      else
                        ArticleCard(
                          article: featured,
                          size: ArticleCardSize.featured,
                          onTap: () =>
                              openArticle(context, widget.apiClient, featured),
                          onRequireAuth: () => _requireAuth(context),
                        ),
                      if (week.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.space6),
                        _SectionHeading(
                          title: 'Earlier this week',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ArchiveScreen(apiClient: widget.apiClient),
                            ),
                          ),
                        ),
                        for (final article in week)
                          ArticleCard(
                            article: article,
                            onTap: () =>
                                openArticle(context, widget.apiClient, article),
                            onRequireAuth: () => _requireAuth(context),
                          ),
                      ],
                    ],
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

class _Masthead extends StatelessWidget {
  final bool authenticated;
  final String? email;
  final VoidCallback onAvatarTap;

  const _Masthead({
    required this.authenticated,
    required this.email,
    required this.onAvatarTap,
  });

  String get _todayLabel {
    final now = DateTime.now();
    return '${_weekdayNames[now.weekday - 1]}, ${now.day} ${_monthNames[now.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final initial =
        (email != null && email!.isNotEmpty) ? email![0].toUpperCase() : null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _todayLabel,
                style: AppTypography.caption.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textSecondary),
              ),
              const SizedBox(height: 2),
              Text(
                'Today',
                style: AppTypography.display1.copyWith(
                  fontSize: 34.4,
                  height: 1.05,
                  letterSpacing: -0.688,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        Semantics(
          button: true,
          label: authenticated ? 'Account and sign out' : 'Sign in',
          child: InkWell(
            onTap: onAvatarTap,
            customBorder: const CircleBorder(),
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration:
                  BoxDecoration(color: colors.ink950, shape: BoxShape.circle),
              child: initial != null
                  ? Text(initial,
                      style: AppTypography.headline
                          .copyWith(fontSize: 17, color: colors.paper0))
                  : Icon(Icons.person_outline, color: colors.paper0, size: 22),
            ),
          ),
        ),
      ],
    );
  }
}

class _CategoryRow extends StatelessWidget {
  final String active;
  final ValueChanged<String> onSelect;

  const _CategoryRow({required this.active, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        separatorBuilder: (context, i) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final category = _categories[i];
          final selected = category == active;
          return _CategoryChip(
            label: category,
            selected: selected,
            onTap: () => onSelect(category),
          );
        },
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: selected ? colors.textPrimary : colors.surfaceSunken,
      borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Center(
            child: Text(
              label,
              style: AppTypography.ui.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: selected ? colors.surfacePage : colors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final String title;
  final VoidCallback onTap;

  const _SectionHeading({required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.space2),
        child: Row(
          children: [
            Text(
              title,
              style: AppTypography.display2.copyWith(
                fontSize: 21.6,
                letterSpacing: -0.216,
                color: colors.textPrimary,
              ),
            ),
            Icon(Icons.chevron_right, color: colors.textSecondary),
          ],
        ),
      ),
    );
  }
}

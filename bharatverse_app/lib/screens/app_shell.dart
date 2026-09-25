import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/glass_surface.dart';
import 'home_screen.dart';
import 'liked_articles_screen.dart';
import 'search_screen.dart';

enum _AppTab { today, library }

/// Root shell for the signed-in app: an [IndexedStack] holding the Today and
/// Library tabs, under a floating glass-blur tab bar with a separate Search
/// button -- Milestone 1's navigation model (see docs/roadmap.md and the
/// design handoff's "Tab bar, now and later" section). Screens stay resident
/// in the stack, so switching tabs never loses scroll position.
///
/// The Library tab is [LikedArticlesScreen] for now -- Phase 3 replaces it
/// with a real Library screen (Saved + Recently read); [HomeScreen] still
/// carries its own header with search/liked icons too, which will look
/// redundant next to the new tab bar until Phase 3's Home redesign removes
/// them. Both are known, temporary Phase 1 states, not final design.
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
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _tab.index,
            children: [
              HomeScreen(apiClient: widget.apiClient),
              LikedArticlesScreen(apiClient: widget.apiClient),
            ],
          ),
          Positioned(
            left: AppSpacing.space4,
            right: AppSpacing.space4,
            bottom: 28,
            child: SafeArea(
              top: false,
              child: _TabBar(
                tab: _tab,
                onSelectTab: (t) => setState(() => _tab = t),
                onSearch: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SearchScreen(apiClient: widget.apiClient),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
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

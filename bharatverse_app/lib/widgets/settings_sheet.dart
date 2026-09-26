import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/auth_state.dart';
import '../state/settings_state.dart';
import '../state/theme_mode_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

const double _topGap = 56;
const double _cellRadius = 12;

/// The account avatar's Settings sheet: account info, notification toggles,
/// text size, offline download, appearance, and sign out. Notification
/// toggles are local preference only -- there is no push integration (see
/// roadmap.md), so a toggle here can never mean a notification actually
/// arrives. Shows the real signed-in email rather than the mockup's fake
/// "Reader" display name, since this app has no real name concept.
class SettingsSheet extends StatelessWidget {
  const SettingsSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const SettingsSheet(),
      );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: _topGap),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        child: Container(
          color: colors.grouped,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: AppSpacing.space2),
                Container(
                  width: 36,
                  height: 5,
                  decoration: BoxDecoration(
                    color: colors.ink300,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                  ),
                ),
                const _Header(),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(AppSpacing.space4, 0,
                        AppSpacing.space4, AppSpacing.space8),
                    children: const [
                      _AccountCard(),
                      _SectionLabel('Notifications'),
                      _NotificationsCard(),
                      _SectionLabel('Reading'),
                      _ReadingCard(),
                      _SectionLabel('Appearance'),
                      _AppearanceCard(),
                      SizedBox(height: AppSpacing.space4),
                      _AboutCard(),
                      SizedBox(height: AppSpacing.space4),
                      _SignOutButton(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space4, vertical: AppSpacing.space3),
      child: Row(
        children: [
          const SizedBox(width: 44),
          Expanded(
            child: Text(
              'Account',
              textAlign: TextAlign.center,
              style: AppTypography.ui.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary),
            ),
          ),
          SizedBox(
            width: 44,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                alignment: Alignment.centerRight,
              ),
              child: Text(
                'Done',
                style: AppTypography.ui.copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: colors.tint),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A rounded-12px card, matching the mockup's `bv-cell` group container.
class _Cell extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _Cell({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.space4),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.space4),
      padding: padding,
      decoration: BoxDecoration(
        color: context.colors.cell,
        borderRadius: BorderRadius.circular(_cellRadius),
      ),
      child: child,
    );
  }
}

class _CellDivider extends StatelessWidget {
  const _CellDivider();

  @override
  Widget build(BuildContext context) =>
      Container(height: 0.5, color: context.colors.sep);
}

class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.space2, AppSpacing.space4,
          AppSpacing.space2, AppSpacing.space2),
      child: Text(
        label,
        style: AppTypography.caption
            .copyWith(fontSize: 13, color: context.colors.textSecondary),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final email = context.watch<AuthState>().currentUser?.email ?? '';
    final initial = email.isNotEmpty ? email[0].toUpperCase() : '?';
    return _Cell(
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration:
                BoxDecoration(color: colors.ink950, shape: BoxShape.circle),
            child: Text(initial,
                style: AppTypography.display1
                    .copyWith(fontSize: 22, color: colors.paper0)),
          ),
          const SizedBox(width: AppSpacing.space4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your account',
                    style: AppTypography.headline
                        .copyWith(fontSize: 17, color: colors.textPrimary)),
                const SizedBox(height: 2),
                Text(email,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.ui
                        .copyWith(fontSize: 14, color: colors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: AppTypography.ui
                      .copyWith(fontSize: 16, color: colors.textPrimary)),
              const SizedBox(height: 2),
              Text(description,
                  style: AppTypography.caption
                      .copyWith(fontSize: 13, color: colors.textSecondary)),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeTrackColor: colors.accentSecondary,
          inactiveTrackColor: colors.paper200,
        ),
      ],
    );
  }
}

class _NotificationsCard extends StatelessWidget {
  const _NotificationsCard();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsState>();
    return _Cell(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space4, vertical: AppSpacing.space3),
            child: _ToggleRow(
              label: 'Daily story',
              description: "When today's story is ready",
              value: settings.notifDaily,
              onChanged: (v) => context.read<SettingsState>().setNotifDaily(v),
            ),
          ),
          const _CellDivider(),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space4, vertical: AppSpacing.space3),
            child: _ToggleRow(
              label: 'Weekly digest',
              description: 'A Sunday recap by email',
              value: settings.notifWeekly,
              onChanged: (v) => context.read<SettingsState>().setNotifWeekly(v),
            ),
          ),
          const _CellDivider(),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space4, vertical: AppSpacing.space3),
            child: _ToggleRow(
              label: 'Product news',
              description: 'Occasional feature updates',
              value: settings.notifAnnounce,
              onChanged: (v) =>
                  context.read<SettingsState>().setNotifAnnounce(v),
            ),
          ),
        ],
      ),
    );
  }
}

class _TextSizeRow extends StatelessWidget {
  const _TextSizeRow();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final settings = context.watch<SettingsState>();
    return Row(
      children: [
        Expanded(
          child: Text('Text size',
              style: AppTypography.ui
                  .copyWith(fontSize: 16, color: colors.textPrimary)),
        ),
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: colors.surfaceSunken,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final size in TextSize.values)
                _TextSizeSegment(
                  size: size,
                  selected: settings.textSize == size,
                  onTap: () => context.read<SettingsState>().setTextSize(size),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TextSizeSegment extends StatelessWidget {
  final TextSize size;
  final bool selected;
  final VoidCallback onTap;

  const _TextSizeSegment({
    required this.size,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: selected ? colors.cell : Colors.transparent,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm - 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm - 2),
        child: Container(
          width: 36,
          height: 32,
          alignment: Alignment.center,
          child: Text('Aa',
              style: AppTypography.ui.copyWith(
                  fontSize: 10 + size.index * 3,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary)),
        ),
      ),
    );
  }
}

class _ReadingCard extends StatelessWidget {
  const _ReadingCard();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsState>();
    return _Cell(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.space4, vertical: AppSpacing.space3),
            child: _TextSizeRow(),
          ),
          const _CellDivider(),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space4, vertical: AppSpacing.space3),
            child: _ToggleRow(
              label: 'Download for offline',
              description: "Save today's story automatically",
              value: settings.offlineOn,
              onChanged: (v) => context.read<SettingsState>().setOfflineOn(v),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard();

  static const _options = [
    (ThemeMode.system, 'Automatic'),
    (ThemeMode.light, 'Light'),
    (ThemeMode.dark, 'Dark'),
  ];

  @override
  Widget build(BuildContext context) {
    final mode = context.watch<ThemeModeState>().mode;
    return _Cell(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (final (i, option) in _options.indexed) ...[
            if (i > 0) const _CellDivider(),
            _AppearanceRow(
              label: option.$2,
              selected: mode == option.$1,
              onTap: () => context.read<ThemeModeState>().setMode(option.$1),
            ),
          ],
        ],
      ),
    );
  }
}

class _AppearanceRow extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _AppearanceRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.space4, vertical: AppSpacing.space3),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: AppTypography.ui
                      .copyWith(fontSize: 16, color: colors.textPrimary)),
            ),
            Icon(Icons.check,
                size: 20, color: selected ? colors.tint : Colors.transparent),
          ],
        ),
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    return const _Cell(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _InfoRow(label: 'About BharatVerse'),
          _CellDivider(),
          _InfoRow(label: 'Help & feedback'),
        ],
      ),
    );
  }
}

/// A static informational row. Tapping is honest about doing nothing real
/// yet, rather than a dead chevron that implies it should navigate somewhere.
class _InfoRow extends StatelessWidget {
  final String label;

  const _InfoRow({required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: () => ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Coming soon'))),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.space4, vertical: AppSpacing.space3),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: AppTypography.ui
                      .copyWith(fontSize: 16, color: colors.textPrimary)),
            ),
            Icon(Icons.chevron_right, color: colors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _SignOutButton extends StatelessWidget {
  const _SignOutButton();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return _Cell(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: () async {
          final navigator = Navigator.of(context);
          await context.read<AuthState>().logout();
          navigator.pop();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.space3),
          child: Center(
            child: Text('Sign out',
                style: AppTypography.ui.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colors.colorError)),
          ),
        ),
      ),
    );
  }
}

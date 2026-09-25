import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// One search suggestion, ruled like an article row. The [typed] start of
/// [term] is set in bold saffron, as search results mark what matched.
class SuggestionTile extends StatelessWidget {
  /// The smallest comfortable height to tap.
  static const _minTapHeight = 48.0;

  final String term;
  final String typed;
  final VoidCallback onTap;

  const SuggestionTile({
    super.key,
    required this.term,
    required this.typed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // The database matches the typed text with its whitespace collapsed.
    final matched = typed.trim().replaceAll(RegExp(r'\s+'), ' ').length;
    final split = matched.clamp(0, term.length);
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: _minTapHeight),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.space3),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.borderHairline)),
          ),
          child: Row(
            children: [
              Icon(Icons.search, size: 18, color: colors.textPlaceholder),
              const SizedBox(width: AppSpacing.space3),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: AppTypography.ui.copyWith(color: colors.textPrimary),
                    children: [
                      TextSpan(
                        text: term.substring(0, split),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: colors.accentPrimary,
                        ),
                      ),
                      TextSpan(text: term.substring(split)),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// One search suggestion, ruled like an article row. The [typed] start of
/// [term] is set in bold saffron, as search results mark what matched.
class SuggestionTile extends StatelessWidget {
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
    // The database matches the typed text with its whitespace collapsed.
    final matched = typed.trim().replaceAll(RegExp(r'\s+'), ' ').length;
    final split = matched.clamp(0, term.length);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.space3),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.borderHairline)),
        ),
        child: Row(
          children: [
            const Icon(Icons.search,
                size: 18, color: AppColors.textPlaceholder),
            const SizedBox(width: AppSpacing.space3),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: AppTypography.ui,
                  children: [
                    TextSpan(
                      text: term.substring(0, split),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.accentPrimary,
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
    );
  }
}

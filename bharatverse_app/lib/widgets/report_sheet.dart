import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'app_button.dart';

/// The reasons a reader can give, as stored in `article_reports.reason`.
const reportReasons = {
  'factual': "Something's factually wrong",
  'image': 'An image is wrong or unrelated',
  'offensive': "It's offensive or inappropriate",
  'other': 'Something else',
};

/// "Report a problem" for an article: a reason, an optional note, and a
/// report the owner reads in the Supabase dashboard. Signed in, it carries
/// the reader's id; signed out, it is anonymous.
class ReportSheet extends StatefulWidget {
  final String articleId;
  final ApiClient? apiClient;

  const ReportSheet({super.key, required this.articleId, this.apiClient});

  static Future<void> show(BuildContext context,
          {required String articleId, ApiClient? apiClient}) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => ReportSheet(articleId: articleId, apiClient: apiClient),
      );

  @override
  State<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<ReportSheet> {
  final _note = TextEditingController();
  late final ApiClient _apiClient = widget.apiClient ?? ApiClient();
  String? _reason;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final auth = context.read<AuthState>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await _apiClient.reportArticle(
        articleId: widget.articleId,
        reason: _reason!,
        note: _note.text,
        userId: auth.currentUser?.id,
        accessToken: auth.authToken,
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = "Couldn't send your report. Check your connection and "
              'try again.';
        });
      }
      return;
    }
    navigator.pop();
    messenger.showSnackBar(const SnackBar(
        content: Text("Thanks for the report. We'll look into it.")));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      // Lifts the sheet above the keyboard while the note is being typed.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        child: Container(
          color: colors.grouped,
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.space4,
                  AppSpacing.space4, AppSpacing.space4, AppSpacing.space6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Report a problem',
                      textAlign: TextAlign.center,
                      style: AppTypography.ui.copyWith(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary)),
                  const SizedBox(height: AppSpacing.space2),
                  Text(
                    'Stories are written by AI from cited sources and can '
                    'still get things wrong. Tell us what needs fixing.',
                    textAlign: TextAlign.center,
                    style: AppTypography.caption
                        .copyWith(color: colors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.space4),
                  Container(
                    decoration: BoxDecoration(
                      color: colors.cell,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        for (final entry in reportReasons.entries)
                          _ReasonRow(
                            label: entry.value,
                            selected: _reason == entry.key,
                            onTap: _sending
                                ? null
                                : () => setState(() => _reason = entry.key),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space4),
                  TextField(
                    controller: _note,
                    enabled: !_sending,
                    maxLength: 1000,
                    minLines: 2,
                    maxLines: 5,
                    style: AppTypography.body
                        .copyWith(fontSize: 15, color: colors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Anything that helps us fix it (optional)',
                      filled: true,
                      fillColor: colors.cell,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: AppTypography.caption
                            .copyWith(color: colors.colorError)),
                    const SizedBox(height: AppSpacing.space3),
                  ],
                  AppButton(
                    label: _sending ? 'Sending…' : 'Send report',
                    variant: AppButtonVariant.cta,
                    pill: true,
                    wide: true,
                    onPressed: _reason == null || _sending ? null : _send,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReasonRow extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _ReasonRow(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
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
              if (selected) Icon(Icons.check, size: 20, color: colors.tint),
            ],
          ),
        ),
      ),
    );
  }
}

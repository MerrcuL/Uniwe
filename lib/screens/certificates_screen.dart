import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/grades.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/document_tile.dart';
import '../widgets/expressive.dart';

/// Every certificate LSF can generate (enrolment, transcripts), as PDFs.
class CertificatesScreen extends StatefulWidget {
  const CertificatesScreen({super.key});

  @override
  State<CertificatesScreen> createState() => _CertificatesScreenState();
}

class _CertificatesScreenState extends State<CertificatesScreen> {
  List<LsfDocument>? _documents;

  /// Per-semester records of achievement; optional (empty if they could not
  /// be loaded, the certificates are still useful without them).
  List<LsfDocument> _records = const [];
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final auth = context.read<AuthService>();
      final documents = await auth.fetchDocuments();
      // After the menu, so both share its session token.
      List<LsfDocument> records;
      try {
        records = (await auth.fetchAchievementDocuments()).records;
      } catch (_) {
        records = _records;
      }
      if (!mounted) return;
      setState(() {
        _documents = documents;
        _records = records;
        _hasError = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _hasError = true);
    }
  }

  void _retry() {
    setState(() => _hasError = false);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.get('certificates'))),
      body: AnimatedSwitcher(
        duration: AppMotion.effectsDefault,
        child: _buildBody(context, l10n),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n) {
    final documents = _documents;
    if (documents == null || (documents.isEmpty && _hasError)) {
      if (!_hasError) return const LoadingState();
      return StatusMessage(
        key: const ValueKey('error'),
        icon: Icons.cloud_off_outlined,
        shape: SoftShape.clover,
        title: l10n.get('errorDocuments'),
        action: FilledButton.tonalIcon(
          onPressed: _retry,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(l10n.get('retry')),
        ),
      );
    }

    final theme = Theme.of(context);
    final gutter = AppSpacing.gutter(context);
    final german = documents.where((d) => !d.isEnglish).toList();
    final english = documents.where((d) => d.isEnglish).toList();

    return RefreshIndicator(
      key: const ValueKey('content'),
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          gutter,
          0,
          gutter,
          AppSpacing.bottomInset(context),
        ),
        children: [
          if (_hasError)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InfoBanner(
                icon: Icons.cloud_off_outlined,
                text: l10n.get('errorDocuments'),
              ),
            ),
          if (documents.isEmpty)
            SizedBox(
              height: 360,
              child: StatusMessage(
                icon: Icons.workspace_premium_outlined,
                title: l10n.get('errorDocuments'),
              ),
            ),
          for (final (label, group) in [
            (l10n.get('documentsGerman'), german),
            (l10n.get('documentsEnglish'), english),
          ])
            if (group.isNotEmpty) ...[
              SectionHeader(label, icon: Icons.translate_rounded),
              ListGroup(
                children: [
                  for (final document in group)
                    DocumentTile(document: document),
                ],
              ),
            ],
          if (_records.isNotEmpty) ...[
            SectionHeader(
              l10n.get('recordsOfAchievement'),
              icon: Icons.description_outlined,
            ),
            ListGroup(
              children: [
                for (final record in _records) DocumentTile(document: record),
              ],
            ),
          ],
          if (documents.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                l10n.get('documentsHint'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

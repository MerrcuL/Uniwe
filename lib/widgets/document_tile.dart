import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/grades.dart';
import '../services/auth_service.dart';
import '../services/document_service.dart';
import '../services/haptic_service.dart';
import '../services/settings_service.dart';
import 'expressive.dart';

/// An LSF document in a [ListGroup]: tap opens it in the PDF viewer, the
/// trailing button shares it. Shows its own progress while LSF generates it.
class DocumentTile extends StatefulWidget {
  const DocumentTile({
    super.key,
    required this.document,
    this.title,
    this.subtitle,
  });

  final LsfDocument document;

  /// Overrides the title LSF gives the document.
  final String? title;
  final String? subtitle;

  @override
  State<DocumentTile> createState() => _DocumentTileState();
}

class _DocumentTileState extends State<DocumentTile> {
  bool _busy = false;

  Future<void> _handOver({required bool share}) async {
    if (_busy) return;
    HapticService.confirm(context.read<SettingsService>().hapticsEnabled);
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    final result = await DocumentService(context.read<AuthService>())
        .handOver(widget.document, share: share);
    if (!mounted) return;
    setState(() => _busy = false);

    final message = switch (result) {
      DocumentResult.opened => null,
      DocumentResult.noViewer => l10n.get('noPdfViewer'),
      DocumentResult.unavailable => l10n.get('documentUnavailable'),
      DocumentResult.failed => l10n.get('documentFailed'),
    };
    if (message != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  String _name(AppLocalizations l10n) {
    final key = widget.document.nameKey;
    return key == null ? widget.document.title : l10n.get(key);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final subtitle = widget.subtitle;

    return ListTile(
      leading: Icon(Icons.picture_as_pdf_outlined, color: scheme.primary),
      title: Text(widget.title ?? _name(l10n)),
      subtitle: subtitle == null ? null : Text(subtitle),
      onTap: _busy ? null : () => _handOver(share: false),
      trailing: AnimatedSwitcher(
        duration: Durations.short4,
        child: _busy
            ? const Padding(
                padding: EdgeInsets.all(8),
                child: ExpressiveLoadingIndicator(size: 32),
              )
            : IconButton(
                icon: const Icon(Icons.share_outlined),
                tooltip: l10n.get('share'),
                onPressed: () => _handOver(share: true),
              ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../services/update_service.dart';

/// Tells the user a newer release exists and offers to open its page.
Future<void> showUpdateDialog(BuildContext context, UpdateInfo updateInfo) {
  final l10n = AppLocalizations.of(context);

  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      return AlertDialog(
        icon: const Icon(Icons.system_update_rounded),
        title: Text(l10n.get('updateAvailable')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${l10n.get('newVersion')}: ${updateInfo.latestVersion}',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '${l10n.get('currentVersion')}: ${updateInfo.currentVersion}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (updateInfo.releaseBody.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: SingleChildScrollView(
                    child: Text(
                      updateInfo.releaseBody,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.get('later')),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              launchUrl(
                Uri.parse(updateInfo.releaseUrl),
                mode: LaunchMode.externalApplication,
              );
            },
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: Text(l10n.get('download')),
          ),
        ],
      );
    },
  );
}

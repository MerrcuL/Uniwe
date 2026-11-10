import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/log_service.dart';
import '../theme/app_theme.dart';
import '../widgets/expressive.dart';

class LogScreen extends StatelessWidget {
  const LogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final logService = context.watch<LogService>();
    final logs = logService.logs;

    void showMessage(String message) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(message)));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.get('logs')),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all_rounded),
            tooltip: l10n.get('copyAllLogs'),
            onPressed: logs.isEmpty
                ? null
                : () {
                    final allLogs = logs
                        .map((e) =>
                            '[${e.formattedTime}] [${e.level.name.toUpperCase()}] ${e.message}${e.details != null ? '\n${e.details}' : ''}')
                        .join('\n');
                    Clipboard.setData(ClipboardData(text: allLogs));
                    showMessage(l10n.get('logsCopied'));
                  },
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: l10n.get('clearLogs'),
            onPressed: logs.isEmpty ? null : logService.clear,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: logs.isEmpty
          ? StatusMessage(
              icon: Icons.receipt_long_outlined,
              title: l10n.get('noLogs'),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: logs.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final entry = logs[index];
                final details = entry.details;
                return ListTile(
                  dense: true,
                  title: Text(
                    entry.message,
                    style: TextStyle(
                      fontWeight: entry.level == LogLevel.error
                          ? FontWeight.w700
                          : FontWeight.w400,
                      color: _levelColor(entry.level, context),
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${entry.formattedTime} [${entry.level.name.toUpperCase()}]',
                        style: theme.textTheme.bodySmall,
                      ),
                      if (details != null)
                        Text(
                          details,
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall,
                        ),
                    ],
                  ),
                  onTap: details == null
                      ? null
                      : () => showDialog<void>(
                            context: context,
                            builder: (dialogContext) => AlertDialog(
                              title: Text(l10n.get('logDetails')),
                              content: SingleChildScrollView(
                                child: SelectableText(details),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(dialogContext).pop(),
                                  child: Text(l10n.get('close')),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Clipboard.setData(
                                      ClipboardData(text: details),
                                    );
                                    Navigator.of(dialogContext).pop();
                                    showMessage(l10n.get('detailsCopied'));
                                  },
                                  child: Text(l10n.get('copy')),
                                ),
                              ],
                            ),
                          ),
                );
              },
            ),
    );
  }

  Color _levelColor(LogLevel level, BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    switch (level) {
      case LogLevel.error:
        return scheme.error;
      case LogLevel.warning:
        return SemanticColors.of(context).warning;
      case LogLevel.debug:
        return scheme.onSurfaceVariant;
      case LogLevel.info:
        return scheme.onSurface;
    }
  }
}

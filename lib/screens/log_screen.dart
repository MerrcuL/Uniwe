import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/log_service.dart';

class LogScreen extends StatelessWidget {
  const LogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final logService = context.watch<LogService>();
    final logs = logService.logs;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Application Logs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all),
            tooltip: 'Copy all logs',
            onPressed: () {
              final allLogs = logs.map((e) => '[${e.formattedTime}] [${e.level.name.toUpperCase()}] ${e.message}${e.details != null ? '\n${e.details}' : ''}').join('\n');
              Clipboard.setData(ClipboardData(text: allLogs));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Logs copied to clipboard')));
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear logs',
            onPressed: () => logService.clear(),
          ),
        ],
      ),
      body: logs.isEmpty
          ? const Center(child: Text('No logs available'))
          : ListView.separated(
              padding: const EdgeInsets.all(8),
              itemCount: logs.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final log = logs[index];
                return ListTile(
                  dense: true,
                  title: Text(
                    log.message,
                    style: TextStyle(
                      fontWeight: log.level == LogLevel.error ? FontWeight.bold : FontWeight.normal,
                      color: _getLogColor(log.level, context),
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${log.formattedTime} [${log.level.name.toUpperCase()}]',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (log.details != null)
                        Text(
                          log.details!,
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                    ],
                  ),
                  onTap: log.details != null
                      ? () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Log Details'),
                              content: SingleChildScrollView(
                                child: SelectableText(log.details!),
                              ),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
                                TextButton(
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: log.details!));
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Details copied')));
                                  },
                                  child: const Text('Copy'),
                                ),
                              ],
                            ),
                          );
                        }
                      : null,
                );
              },
            ),
    );
  }

  Color _getLogColor(LogLevel level, BuildContext context) {
    switch (level) {
      case LogLevel.error:
        return Theme.of(context).colorScheme.error;
      case LogLevel.warning:
        return Colors.orange;
      case LogLevel.debug:
        return Colors.blueGrey;
      case LogLevel.info:
        return Theme.of(context).colorScheme.onSurface;
    }
  }
}

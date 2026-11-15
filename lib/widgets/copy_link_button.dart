import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../l10n/app_localizations.dart';

/// Query parameters that carry the user's session (LSF's `asi`, Moodle's
/// `sesskey`, the web mail's `_token`). They are left out of copied links:
/// they would not work for anyone else and should not be passed around.
const Set<String> _sessionParameters = {'asi', 'sesskey', '_token'};

/// [url] without its session parameters, ready to be shared.
String shareableUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasQuery) return url;
  final parameters = uri.queryParametersAll.entries
      .where((e) => !_sessionParameters.contains(e.key.toLowerCase()));
  if (parameters.length == uri.queryParametersAll.length) return url;
  final query = [
    for (final entry in parameters)
      for (final value in entry.value)
        '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(value)}',
  ].join('&');
  // An empty query would leave a bare '?' behind.
  final shared = uri.replace(query: query).toString();
  return query.isEmpty ? shared.replaceFirst('?', '') : shared;
}


/// App bar action that copies the address of the page shown in an embedded
/// browser.
class CopyLinkButton extends StatelessWidget {
  const CopyLinkButton({super.key, required this.controller});

  final WebViewController? controller;

  Future<void> _copy(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final url = await controller?.currentUrl();
    if (url == null || url.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: shareableUrl(url)));
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(l10n.get('linkCopied'))));
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.link_rounded),
      tooltip: AppLocalizations.of(context).get('copyLink'),
      onPressed: controller == null ? null : () => _copy(context),
    );
  }
}

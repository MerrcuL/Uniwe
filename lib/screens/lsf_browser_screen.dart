import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../l10n/app_localizations.dart';
import '../services/auth_service.dart';
import '../utils/webview_dark_mode.dart';
import '../widgets/expressive.dart';

/// LSF in a web view that shares the app's session.
///
/// With a [publishId] it opens that lecture's detail page, with a [personId]
/// the lecturer's person page, and without either the LSF start page.
class LsfBrowserScreen extends StatefulWidget {
  final String? publishId;
  final String? personId;

  const LsfBrowserScreen({super.key, this.publishId, this.personId});

  @override
  State<LsfBrowserScreen> createState() => _LsfBrowserScreenState();
}

class _LsfBrowserScreenState extends State<LsfBrowserScreen> {
  static const String _base = 'https://lsf.htw-berlin.de/qisserver/rds';

  WebViewController? _controller;
  bool _isLoading = true;
  bool _isDark = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _isDark = Theme.of(context).brightness == Brightness.dark;
    if (!_started) {
      _started = true;
      _initWebView();
    }
  }

  String get _url {
    final publishId = widget.publishId;
    if (publishId != null) {
      return '$_base?state=verpublish&status=init&vmfile=no&publishid=$publishId&moduleCall=webInfo&publishConfFile=webInfo&publishSubDir=veranstaltung';
    }
    final personId = widget.personId;
    if (personId != null) {
      return '$_base?state=verpublish&status=init&vmfile=no&moduleCall=webInfo&publishConfFile=webInfoPerson&publishSubDir=personal&keep=y&personal.pid=$personId';
    }
    return '$_base?state=user&type=0';
  }

  Future<void> _initWebView() async {
    final authService = context.read<AuthService>();
    // Signs in first if the session has not been established yet.
    final cookies = await authService.getLsfCookies();
    final cookieManager = WebViewCookieManager();

    for (final entry in cookies.entries) {
      await cookieManager.setCookie(
        WebViewCookie(
          name: entry.key,
          value: entry.value,
          domain: 'lsf.htw-berlin.de',
          path: '/',
        ),
      );
    }

    if (!mounted) return;

    late final WebViewController controller;
    controller = WebViewController()
      ..setUserAgent(desktopUserAgent)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (_isDark) controller.runJavaScript(webViewDarkModeJs);
            if (mounted && !_isLoading) setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            if (_isDark) controller.runJavaScript(webViewDarkModeJs);
            if (mounted) setState(() => _isLoading = false);
          },
        ),
      )
      ..setBackgroundColor(_isDark ? Colors.black : Colors.white);

    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setUseWideViewPort(true);
    }

    setState(() => _controller = controller);
    controller.loadRequest(Uri.parse(_url));
  }

  /// Back steps through the pages visited inside LSF before closing.
  Future<void> _onBack() async {
    final controller = _controller;
    if (controller != null && await controller.canGoBack()) {
      await controller.goBack();
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final materialL10n = MaterialLocalizations.of(context);

    // Predictive back is disabled on purpose: animating a hybrid-composition
    // web view under the back gesture glitches.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('LSF'),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: materialL10n.closeButtonTooltip,
            onPressed: () => Navigator.of(context).pop(),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: l10n.get('refresh'),
              onPressed: (_isLoading || _controller == null)
                  ? null
                  : () {
                      setState(() => _isLoading = true);
                      _controller!.reload();
                    },
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: Builder(
          builder: (context) {
            final animation = ModalRoute.of(context)?.animation;
            final controller = _controller;
            if (controller == null) return const LoadingState();

            final platform = controller.platform;
            final Widget webView = RepaintBoundary(
              child: platform is AndroidWebViewController
                  ? WebViewWidget.fromPlatformCreationParams(
                      params: AndroidWebViewWidgetCreationParams(
                        controller: platform,
                        displayWithHybridComposition: true,
                      ),
                    )
                  : WebViewWidget(controller: controller),
            );

            return Stack(
              children: [
                Positioned.fill(
                  child: animation != null
                      ? FadeTransition(opacity: animation, child: webView)
                      : webView,
                ),
                if (_isLoading)
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(minHeight: 3),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

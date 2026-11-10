import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../l10n/app_localizations.dart';
import '../services/auth_service.dart';
import '../utils/webview_dark_mode.dart';
import '../widgets/expressive.dart';

/// Moodle in a web view, signed in automatically with the stored HTW
/// credentials and following the app's light/dark theme.
class MoodleScreen extends StatefulWidget {
  const MoodleScreen({super.key});

  @override
  State<MoodleScreen> createState() => _MoodleScreenState();
}

class _MoodleScreenState extends State<MoodleScreen> {
  static const String _host = AuthService.moodleHost;
  static final Uri _startUrl = Uri.https(_host, '/my/');

  /// How often a lost session is restored by signing in again while the
  /// screen is open, before giving up (guards against a sign-in loop).
  static const int _maxSilentLogins = 2;

  late final AuthService _auth = context.read<AuthService>();
  WebViewController? _controller;
  bool _isLoading = true;
  bool _hasError = false;
  bool _isDark = false;
  bool _started = false;
  int _silentLogins = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (!_started) {
      _started = true;
      _isDark = isDark;
      _initWebView();
    } else if (isDark != _isDark) {
      // Follow theme changes without reloading the page.
      _isDark = isDark;
      final controller = _controller;
      if (controller != null) {
        controller.setBackgroundColor(_backgroundColor);
        controller
            .runJavaScript(isDark ? webViewDarkModeJs : webViewLightModeJs);
      }
    }
  }

  // Moodle is a light page that gets inverted in dark mode, so pure
  // black/white avoid a flash while it loads.
  Color get _backgroundColor => _isDark ? Colors.black : Colors.white;

  /// Hands the Moodle session to the web view's cookie store.
  Future<bool> _applySession({bool fresh = false}) async {
    final cookies = await _auth.getMoodleCookies(fresh: fresh);
    if (cookies == null || cookies.isEmpty) return false;
    final cookieManager = WebViewCookieManager();
    for (final entry in cookies.entries) {
      await cookieManager.setCookie(
        WebViewCookie(
          name: entry.key,
          value: entry.value,
          domain: _host,
          path: '/',
        ),
      );
    }
    return true;
  }

  Future<void> _initWebView() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });
    }
    final ok = await _applySession();
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
      return;
    }

    late final WebViewController controller;
    controller = WebViewController()
      ..setUserAgent(mobileUserAgent)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _onNavigationRequest,
          onPageStarted: (_) {
            if (_isDark) controller.runJavaScript(webViewDarkModeJs);
            if (mounted && !_isLoading) setState(() => _isLoading = true);
          },
          onPageFinished: (url) {
            if (_isDark) controller.runJavaScript(webViewDarkModeJs);
            if (mounted && _isLoading) setState(() => _isLoading = false);
            _restoreSessionIfLost(controller, url);
          },
        ),
      )
      ..setBackgroundColor(_backgroundColor);

    setState(() => _controller = controller);
    controller.loadRequest(_startUrl);
  }

  /// Moodle's session ended (timeout, or signed out elsewhere) and it shows
  /// its login form: sign in again silently and continue.
  Future<void> _restoreSessionIfLost(
    WebViewController controller,
    String url,
  ) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.host != _host ||
        !uri.path.startsWith('/login/index.php') ||
        _silentLogins >= _maxSilentLogins) {
      return;
    }
    _silentLogins++;
    if (mounted) setState(() => _isLoading = true);
    final ok = await _applySession(fresh: true);
    if (!mounted || !identical(_controller, controller)) return;
    if (ok) {
      await controller.loadRequest(_startUrl);
    } else {
      setState(() => _isLoading = false);
    }
  }

  /// Moodle pages stay in the app; everything else — other sites, mail and
  /// phone links, and course files, which a web view cannot display or
  /// download — goes to the system.
  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.prevent;
    final isMoodlePage = (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host == _host &&
        !uri.path.contains('/pluginfile.php');
    if (isMoodlePage || uri.scheme == 'about' || uri.scheme == 'data') {
      return NavigationDecision.navigate;
    }
    if (request.isMainFrame) {
      launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return NavigationDecision.prevent;
  }

  /// Back steps through the pages visited inside Moodle before closing.
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
          title: const Text('Moodle'),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: materialL10n.closeButtonTooltip,
            onPressed: () => Navigator.of(context).pop(),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: l10n.get('refresh'),
              onPressed: _isLoading
                  ? null
                  : () {
                      final controller = _controller;
                      if (controller == null) {
                        _initWebView();
                      } else {
                        setState(() => _isLoading = true);
                        controller.reload();
                      }
                    },
            ),
            const SizedBox(width: 4),
          ],
        ),
        backgroundColor: _controller == null ? null : _backgroundColor,
        body: _buildBody(context, l10n),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n) {
    if (_hasError) {
      return SafeArea(
        child: StatusMessage(
          icon: Icons.cloud_off_outlined,
          shape: SoftShape.clover,
          title: l10n.get('errorMoodle'),
          action: FilledButton.tonalIcon(
            onPressed: _initWebView,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(l10n.get('retry')),
          ),
        ),
      );
    }

    final controller = _controller;
    if (controller == null) return const LoadingState();

    final animation = ModalRoute.of(context)?.animation;
    final platform = controller.platform;
    final Widget webView = RepaintBoundary(
      child: platform is AndroidWebViewController
          ? WebViewWidget.fromPlatformCreationParams(
              key: ObjectKey(controller),
              params: AndroidWebViewWidgetCreationParams(
                controller: platform,
                displayWithHybridComposition: true,
              ),
            )
          : WebViewWidget(key: ObjectKey(controller), controller: controller),
    );

    return SafeArea(
      top: false,
      child: Stack(
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
      ),
    );
  }
}

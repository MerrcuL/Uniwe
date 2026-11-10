import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../app_events.dart';
import '../l10n/app_localizations.dart';
import '../services/auth_service.dart';
import '../services/haptic_service.dart';
import '../services/settings_service.dart';
import '../utils/webview_dark_mode.dart';
import '../widgets/expressive.dart';
import 'login_screen.dart';

class EmailScreen extends StatefulWidget {
  const EmailScreen({super.key, this.standalone = false});

  /// False when shown as a tab of the navigation bar; true when opened as a
  /// page of its own from the menu (then it brings its own app bar and back
  /// handling).
  final bool standalone;

  @override
  State<EmailScreen> createState() => _EmailScreenState();
}

class _EmailScreenState extends State<EmailScreen> {
  static const String _webmailHost = 'webmail.htw-berlin.de';

  late final AuthService _auth;
  WebViewController? _controller;
  bool _isLoading = true;
  bool _hasError = false;
  bool _isDark = false;
  bool _started = false;
  late bool _wasAuthenticated;

  /// Identifies the newest [_initWebView] run; older ones abandon their work.
  int _initTicket = 0;

  StreamSubscription<int>? _reselectSubscription;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthService>();
    _wasAuthenticated = _auth.isAuthenticated;
    _auth.addListener(_onAuthChanged);
    if (!widget.standalone) {
      AppEvents.registerBackHandler(AppTab.email, _handleBack);
    }

    _reselectSubscription = AppEvents.tabReselected.listen((index) {
      if (widget.standalone || index != AppTab.email || !mounted) return;
      HapticService.confirm(context.read<SettingsService>().hapticsEnabled);
      if (_controller != null) {
        _controller!.reload();
      } else {
        _initWebView();
      }
    });
  }

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

  @override
  void dispose() {
    AppEvents.unregisterBackHandler(AppTab.email, _handleBack);
    _auth.removeListener(_onAuthChanged);
    _reselectSubscription?.cancel();
    super.dispose();
  }

  // The page behind the web view is a light page that gets inverted in dark
  // mode, so pure black/white avoid a flash while it loads.
  Color get _backgroundColor => _isDark ? Colors.black : Colors.white;

  void _onAuthChanged() {
    final isAuthenticated = _auth.isAuthenticated;
    if (isAuthenticated == _wasAuthenticated) return;
    _wasAuthenticated = isAuthenticated;
    if (!mounted) return;

    if (isAuthenticated) {
      _initWebView();
    } else {
      // Signed out: drop the web session so the next account does not land
      // in the previous user's mailbox.
      _initTicket++;
      setState(() {
        _controller = null;
        _hasError = false;
        _isLoading = false;
      });
      unawaited(_clearWebViewCookies());
    }
  }

  Future<void> _clearWebViewCookies() async {
    try {
      await WebViewCookieManager().clearCookies();
    } catch (_) {
      // No web view implementation on this platform.
    }
  }

  /// System back navigates inside the web view before it leaves the app.
  Future<bool> _handleBack() async {
    final controller = _controller;
    if (controller != null && await controller.canGoBack()) {
      await controller.goBack();
      return true;
    }
    return false;
  }

  Future<void> _initWebView() async {
    final ticket = ++_initTicket;
    if (!_auth.isAuthenticated) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });
    }

    final cookies = await _auth.getWebmailCookies();
    if (!mounted || ticket != _initTicket) return;

    if (cookies == null || cookies.isEmpty) {
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
      return;
    }

    final cookieManager = WebViewCookieManager();
    for (final entry in cookies.entries) {
      await cookieManager.setCookie(
        WebViewCookie(
          name: entry.key,
          value: entry.value,
          domain: _webmailHost,
          path: '/',
        ),
      );
    }
    if (!mounted || ticket != _initTicket) return;

    const url = 'https://$_webmailHost/currentNG/?_task=mail';

    late final WebViewController controller;
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (_isDark) controller.runJavaScript(webViewDarkModeJs);
            if (mounted && identical(_controller, controller) && !_isLoading) {
              setState(() => _isLoading = true);
            }
          },
          onPageFinished: (_) {
            if (_isDark) controller.runJavaScript(webViewDarkModeJs);
            if (mounted && identical(_controller, controller) && _isLoading) {
              setState(() => _isLoading = false);
            }
          },
        ),
      )
      ..setBackgroundColor(_backgroundColor);

    setState(() => _controller = controller);
    controller.loadRequest(Uri.parse(url));
  }

  @override
  Widget build(BuildContext context) {
    final content = _buildContent(context);
    if (!widget.standalone) return content;

    final l10n = AppLocalizations.of(context);
    // Back steps through the web view's history before leaving the page.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _handleBack()) return;
        if (context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.get('email')),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: () => Navigator.of(context).pop(),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: l10n.get('refresh'),
              onPressed: () {
                final controller = _controller;
                controller == null ? _initWebView() : controller.reload();
              },
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: content,
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isAuthenticated =
        context.select<AuthService, bool>((a) => a.isAuthenticated);

    if (!isAuthenticated) {
      return Scaffold(
        body: SafeArea(
          child: StatusMessage(
            icon: Icons.mail_lock_outlined,
            title: l10n.get('webmail'),
            message: l10n.get('scheduleLoginPrompt'),
            action: FilledButton.icon(
              onPressed: () {
                HapticService.confirm(
                  context.read<SettingsService>().hapticsEnabled,
                );
                showLoginDialog(context);
              },
              icon: const Icon(Icons.login_rounded),
              label: Text(l10n.get('loginButton')),
            ),
          ),
        ),
      );
    }

    if (_hasError) {
      return Scaffold(
        body: SafeArea(
          child: StatusMessage(
            icon: Icons.cloud_off_outlined,
            shape: SoftShape.clover,
            title: l10n.get('errorWebmail'),
            action: FilledButton.tonalIcon(
              onPressed: _initWebView,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(l10n.get('retry')),
            ),
          ),
        ),
      );
    }

    final controller = _controller;
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: SafeArea(
        child: Stack(
          children: [
            if (controller != null)
              Positioned.fill(
                child: RepaintBoundary(
                  child: _buildWebView(controller),
                ),
              ),
            if (_isLoading && controller == null)
              const Positioned.fill(child: LoadingState())
            else if (_isLoading)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(minHeight: 3),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebView(WebViewController controller) {
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      return WebViewWidget.fromPlatformCreationParams(
        key: ObjectKey(controller),
        params: AndroidWebViewWidgetCreationParams(
          controller: platform,
          displayWithHybridComposition: true,
        ),
      );
    }
    return WebViewWidget(key: ObjectKey(controller), controller: controller);
  }
}

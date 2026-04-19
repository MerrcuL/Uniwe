import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../services/auth_service.dart';
import '../services/settings_service.dart';
import '../l10n/app_localizations.dart';
import 'dart:async';
import '../main.dart' as import_main;
import '../services/haptic_service.dart';

const _darkCss =
    "html{filter:invert(1) hue-rotate(180deg)!important}"
    "img,video,picture,canvas,svg,[style*=background-image]{filter:invert(1) hue-rotate(180deg)!important}";

const _darkJs = """
(function(){
  function d(){
    if(document.head&&!document.getElementById('_ud')){
      var s=document.createElement('style');
      s.id='_ud';
      s.textContent='$_darkCss';
      document.head.appendChild(s);
    }else if(!document.head){requestAnimationFrame(d);}
  }
  d();
})();
""";

class EmailScreen extends StatefulWidget {
  const EmailScreen({super.key});

  @override
  State<EmailScreen> createState() => _EmailScreenState();
}

class _EmailScreenState extends State<EmailScreen> {
  WebViewController? _controller;
  bool _isLoading = true;
  String? _errorMsg;
  bool _wasAuthenticated = false;
  StreamSubscription<int>? _tabRefreshSubscription;
  StreamSubscription<void>? _longPressSubscription;
  bool _showingLsf = false;

  @override
  void initState() {
    super.initState();
    _wasAuthenticated = context.read<AuthService>().isAuthenticated;
    _initWebView();
    
    _longPressSubscription = import_main.emailLongPressController.stream.listen((_) {
      if (mounted) {
        final settings = context.read<SettingsService>();
        if (settings.lsfOnEmailLongPress) {
          if (!_showingLsf) {
            final haptics = settings.hapticsEnabled;
            HapticService.confirm(haptics);
            setState(() {
              _showingLsf = true;
            });
            _initWebView();
          }
        }
      }
    });

    _tabRefreshSubscription = import_main.tabRefreshController.stream.listen((index) {
      if (index == 2 && mounted) {
        final haptics = context.read<SettingsService>().hapticsEnabled;
        HapticService.confirm(haptics);
        if (_showingLsf) {
          setState(() {
            _showingLsf = false;
          });
          _initWebView();
        } else {
          if (_controller != null) {
            _controller!.reload();
          } else {
            _initWebView();
          }
        }
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final authService = Provider.of<AuthService>(context);
    final isAuthenticated = authService.isAuthenticated;

    if (isAuthenticated && (_wasAuthenticated == false)) {
      if (_controller == null && !_isLoading) {
        _initWebView();
      }
    }
    _wasAuthenticated = isAuthenticated;
  }

  @override
  void dispose() {
    _tabRefreshSubscription?.cancel();
    _longPressSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initWebView() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMsg = null;
      });
    }
    final authService = context.read<AuthService>();
    
    if (!authService.isAuthenticated) {
      if (mounted) {
        setState(() {
          _errorMsg = AppLocalizations.of(context).get('scheduleLoginPrompt');
          _isLoading = false;
        });
      }
      return;
    }

    final cookieManager = WebViewCookieManager();
    String url;

    if (_showingLsf) {
      final cookies = authService.scraperService.cookies;
      for (var entry in cookies.entries) {
        await cookieManager.setCookie(
          WebViewCookie(
            name: entry.key,
            value: entry.value,
            domain: 'lsf.htw-berlin.de',
            path: '/',
          ),
        );
      }
      url = 'https://lsf.htw-berlin.de/qisserver/rds?state=user&type=0';
    } else {
      final cookies = await authService.getWebmailCookies();
      if (cookies == null || cookies.isEmpty) {
        if (mounted) {
          setState(() {
            _errorMsg = AppLocalizations.of(context).get('errorNetwork');
            _isLoading = false;
          });
        }
        return;
      }

      for (var entry in cookies.entries) {
        await cookieManager.setCookie(
          WebViewCookie(
            name: entry.key,
            value: entry.value,
            domain: 'webmail.htw-berlin.de',
            path: '/',
          ),
        );
      }
      url = 'https://webmail.htw-berlin.de/currentNG/?_task=mail';
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            if (isDark) {
              _controller?.runJavaScript(_darkJs);
            }
          },
          onPageFinished: (String url) {
            if (isDark) {
              _controller?.runJavaScript(_darkJs);
            }
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
          },
        ),
      )
      ..setBackgroundColor(isDark ? Colors.black : Colors.white)
      ..loadRequest(Uri.parse(url));

    if (_showingLsf) {
      controller.setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
      if (controller.platform is AndroidWebViewController) {
        final androidController = controller.platform as AndroidWebViewController;
        androidController.setUseWideViewPort(true);
      }
    }

    if (mounted) {
      setState(() {
        _controller = controller;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // If not authenticated, show a login prompt similar to timetable
    final authService = context.watch<AuthService>();
    if (!authService.isAuthenticated) {
      final l10n = AppLocalizations.of(context);
      return SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 64,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(height: 16),
                Text(
                  'Webmail',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.get('scheduleLoginPrompt'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_errorMsg != null) {
      return SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Theme.of(context).colorScheme.error),
                const SizedBox(height: 16),
                Text(_errorMsg!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _errorMsg = null;
                      _isLoading = true;
                    });
                    _initWebView();
                  },
                  child: const Text('Erneut versuchen'),
                )
              ],
            ),
          ),
        ),
      );
    }

    return SafeArea(
      child: Stack(
        children: [
          if (_controller != null) RepaintBoundary(
            child: _controller!.platform is AndroidWebViewController
              ? WebViewWidget.fromPlatformCreationParams(
                  params: AndroidWebViewWidgetCreationParams(
                    controller: _controller!.platform as AndroidWebViewController,
                    displayWithHybridComposition: true,
                  ),
                )
              : WebViewWidget(controller: _controller!),
          ),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../services/auth_service.dart';

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

class LsfBrowserScreen extends StatefulWidget {
  final String publishId;

  const LsfBrowserScreen({super.key, required this.publishId});

  @override
  State<LsfBrowserScreen> createState() => _LsfBrowserScreenState();
}

class _LsfBrowserScreenState extends State<LsfBrowserScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    final authService = context.read<AuthService>();
    final cookies = authService.scraperService.cookies;
    final cookieManager = WebViewCookieManager();

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

    final url = 'https://lsf.htw-berlin.de/qisserver/rds?state=verpublish&status=init&vmfile=no&publishid=${widget.publishId}&moduleCall=webInfo&publishConfFile=webInfo&publishSubDir=veranstaltung';

    if (!mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    _controller = WebViewController()
      ..setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            if (isDark) {
              _controller.runJavaScript(_darkJs);
            }
          },
          onPageFinished: (String url) {
            if (isDark) {
              _controller.runJavaScript(_darkJs);
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

    if (_controller.platform is AndroidWebViewController) {
      final androidController = _controller.platform as AndroidWebViewController;
      androidController.setUseWideViewPort(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('LSF'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                if (!_isLoading) {
                  setState(() {
                    _isLoading = true;
                  });
                  _controller.reload();
                }
              },
            ),
          ],
        ),
        body: Builder(
          builder: (context) {
            final animation = ModalRoute.of(context)?.animation;
            final webView = RepaintBoundary(
              child: _controller.platform is AndroidWebViewController
                ? WebViewWidget.fromPlatformCreationParams(
                    params: AndroidWebViewWidgetCreationParams(
                      controller: _controller.platform as AndroidWebViewController,
                      displayWithHybridComposition: true,
                    ),
                  )
                : WebViewWidget(controller: _controller),
            );

            return Stack(
              children: [
                if (animation != null)
                  FadeTransition(opacity: animation, child: webView)
                else
                  webView,
                if (_isLoading)
                  const Center(
                    child: CircularProgressIndicator(),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The animated logo shown over the app while it starts.
///
/// Android's own launch screen is a plain background (see
/// `android/app/src/main/res/values-v31/styles.xml`), so the first Flutter
/// frame, an empty surface, continues it without a visible jump. Then the
/// "U" springs up, the dot drops in and bounces into place, and the logo
/// fades into the app once [ready] is true.
class SplashOverlay extends StatefulWidget {
  const SplashOverlay({
    super.key,
    required this.ready,
    required this.onFinished,
  });

  /// Whether the app behind is ready to be shown.
  final bool ready;

  /// Called once the overlay has faded out and can be removed.
  final VoidCallback onFinished;

  static const String asset = 'assets/icons/icon_foreground.png';

  @override
  State<SplashOverlay> createState() => _SplashOverlayState();
}

class _SplashOverlayState extends State<SplashOverlay>
    with TickerProviderStateMixin {
  /// The longest the finished logo waits for [SplashOverlay.ready] before
  /// leaving anyway; the app then shows its own loading state.
  static const Duration _maxWait = Duration(seconds: 2);

  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  late final AnimationController _exit = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  ImageStream? _stream;
  ImageStreamListener? _listener;
  ui.Image? _image;
  Timer? _waitTimer;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _intro.addStatusListener((status) {
      if (status != AnimationStatus.completed) return;
      if (widget.ready) {
        _leave();
      } else {
        _waitTimer = Timer(_maxWait, _leave);
      }
    });
    _exit.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onFinished();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_stream != null) return;
    // Decode the logo first; the intro starts on a blank surface once it
    // can actually be drawn.
    final stream = const AssetImage(SplashOverlay.asset)
        .resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener(
      (info, _) {
        if (!mounted) return;
        setState(() => _image = info.image);
        _start();
      },
      onError: (error, stackTrace) => _leave(),
    );
    stream.addListener(listener);
    _stream = stream;
    _listener = listener;
  }

  @override
  void didUpdateWidget(SplashOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ready && !oldWidget.ready && _intro.isCompleted) _leave();
  }

  void _start() {
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _intro.value = 1;
      // The status listener is not called for a jump; trigger it by hand.
      widget.ready ? _leave() : _waitTimer = Timer(_maxWait, _leave);
    } else {
      _intro.forward();
    }
  }

  void _leave() {
    _waitTimer?.cancel();
    if (!mounted || _exit.isAnimating || _exit.isCompleted) return;
    _exit.forward();
  }

  @override
  void dispose() {
    _waitTimer?.cancel();
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
    _intro.dispose();
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shortest = MediaQuery.sizeOf(context).shortestSide;
    final size = math.min(shortest * 0.62, 288.0);
    final image = _image;

    return AnimatedBuilder(
      animation: Listenable.merge([_intro, _exit]),
      builder: (context, _) {
        final exit = _exit.value;
        return IgnorePointer(
          ignoring: exit > 0.5,
          child: Opacity(
            opacity: 1 - Curves.easeInCubic.transform(exit),
            child: ColoredBox(
              color: scheme.surface,
              child: Center(
                child: Transform.scale(
                  scale: 1 + 0.12 * Curves.easeInCubic.transform(exit),
                  child: SizedBox.square(
                    dimension: size,
                    child: image == null
                        ? null
                        : CustomPaint(
                            painter: _LogoPainter(image, _intro.value),
                          ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Paints the two pieces of the logo — the "U" and the dot — at progress [t]
/// of the intro.
class _LogoPainter extends CustomPainter {
  _LogoPainter(this.image, this.t);

  final ui.Image image;
  final double t;

  // Geometry of the 1024 px icon (assets/icons/icon_foreground.png): the U
  // occupies x 187–651, the dot x 691–838; both rest on y = 772.
  static const double _canvas = 1024;
  static const double _split = 670;
  static const double _baseline = 772;
  static const Offset _uPivot = Offset(419, _baseline);
  static const Offset _dotCenter = Offset(764, 705);

  static double _interval(double t, double begin, double end, Curve curve) =>
      curve.transform(((t - begin) / (end - begin)).clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / _canvas;
    canvas.scale(scale);
    final paint = Paint()..filterQuality = FilterQuality.medium;

    // The U springs up from its base, slightly overshooting.
    final uGrow = _interval(t, 0, 0.55, Curves.easeOutBack);
    final uFade = _interval(t, 0, 0.2, Curves.easeOut);
    if (uFade > 0) {
      canvas.save();
      canvas.translate(_uPivot.dx, _uPivot.dy);
      canvas.scale(0.35 + 0.65 * uGrow);
      canvas.translate(-_uPivot.dx, -_uPivot.dy);
      _drawPiece(
        canvas,
        const Rect.fromLTRB(0, 0, _split, _canvas),
        paint..color = Color.fromRGBO(0, 0, 0, uFade),
      );
      canvas.restore();
    }

    // The dot drops in, spinning a quarter turn, and bounces into place.
    final fall = _interval(t, 0.38, 1, Curves.bounceOut);
    final spin = _interval(t, 0.38, 0.72, Curves.easeOutCubic);
    final dotFade = _interval(t, 0.38, 0.5, Curves.easeOut);
    if (dotFade > 0) {
      canvas.save();
      canvas.translate(_dotCenter.dx, _dotCenter.dy - 560 * (1 - fall));
      canvas.rotate(-math.pi / 2 * (1 - spin));
      canvas.translate(-_dotCenter.dx, -_dotCenter.dy);
      _drawPiece(
        canvas,
        const Rect.fromLTRB(_split, 0, _canvas, _canvas),
        paint..color = Color.fromRGBO(0, 0, 0, dotFade),
      );
      canvas.restore();
    }
  }

  void _drawPiece(Canvas canvas, Rect source, Paint paint) {
    canvas.drawImageRect(image, source, source, paint);
  }

  @override
  bool shouldRepaint(_LogoPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.image != image;
}

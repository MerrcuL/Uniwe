import 'package:flutter/widgets.dart';

/// Shows [child] until its route starts to close, then nothing.
///
/// Web views use hybrid composition, which scrolls best but makes moving or
/// fading the native view expensive. Dropping the web view as soon as the
/// closing animation starts lets the (now plain) page slide out smoothly.
class HideOnRouteExit extends StatefulWidget {
  const HideOnRouteExit({super.key, required this.child});

  final Widget child;

  @override
  State<HideOnRouteExit> createState() => _HideOnRouteExitState();
}

class _HideOnRouteExitState extends State<HideOnRouteExit> {
  Animation<double>? _animation;
  bool _closing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (animation == _animation) return;
    _animation?.removeStatusListener(_onStatus);
    _animation = animation?..addStatusListener(_onStatus);
  }

  @override
  void dispose() {
    _animation?.removeStatusListener(_onStatus);
    super.dispose();
  }

  void _onStatus(AnimationStatus status) {
    final closing = status == AnimationStatus.reverse ||
        status == AnimationStatus.dismissed;
    if (closing != _closing) setState(() => _closing = closing);
  }

  @override
  Widget build(BuildContext context) =>
      _closing ? const SizedBox.expand() : widget.child;
}

import 'package:flutter/material.dart';

/// An [IndexedStack] for top-level destinations that
///
///  * builds a child only once its tab is first shown — the app no longer
///    pays for every tab (network requests, a web view …) at startup,
///  * keeps visited children alive so they retain their state,
///  * pauses the animations of hidden children, and
///  * fades the newly selected child in.
class FadeIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  final Duration duration;
  final bool animate;

  const FadeIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.duration = const Duration(milliseconds: 300),
    this.animate = true,
  });

  @override
  State<FadeIndexedStack> createState() => _FadeIndexedStackState();
}

class _FadeIndexedStackState extends State<FadeIndexedStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  late final Set<int> _activated;

  @override
  void initState() {
    super.initState();
    _activated = {widget.index};
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      value: 1,
    );
    _fade = CurvedAnimation(
      parent: _controller,
      curve: Easing.emphasizedDecelerate,
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.02), // Very subtle slide up
      end: Offset.zero,
    ).animate(_fade);
  }

  @override
  void didUpdateWidget(FadeIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.duration != oldWidget.duration) {
      _controller.duration = widget.duration;
    }
    if (widget.index != oldWidget.index) {
      _activated.add(widget.index);
      if (widget.animate) {
        _controller.forward(from: 0);
      } else {
        _controller.value = 1;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stack = IndexedStack(
      index: widget.index,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          _activated.contains(i)
              ? TickerMode(
                  enabled: i == widget.index,
                  child: widget.children[i],
                )
              : const SizedBox.shrink(),
      ],
    );

    // The transitions stay in the tree even when animations are off (the
    // controller then simply rests at 1): removing them would re-parent the
    // stack and throw away the state of every tab.
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: stack),
    );
  }
}

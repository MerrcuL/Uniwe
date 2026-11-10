import 'package:flutter/material.dart';

/// A [PageView] that is kept in sync with a date held in a [ValueNotifier].
///
/// Swiping updates [selected]; changing [selected] from outside (day chips,
/// "today", week arrows) moves the pager. Because every page maps to an
/// absolute date, paging is seamless across week and year boundaries — there
/// is no "last page" that needs special gesture handling.
class DatePager extends StatefulWidget {
  const DatePager({
    super.key,
    required this.selected,
    required this.pageOf,
    required this.dateOf,
    required this.pageBuilder,
    this.animate = true,
    this.onUserPaged,
  });

  final ValueNotifier<DateTime> selected;

  /// Page that shows [date].
  final int Function(DateTime date) pageOf;

  /// Date to select when the user lands on [page]; [current] is the previous
  /// selection (useful to keep the weekday when paging by week).
  final DateTime Function(int page, DateTime current) dateOf;

  final Widget Function(BuildContext context, int page) pageBuilder;

  /// Animate programmatic page changes.
  final bool animate;

  /// Called after a swipe changed the page (not for programmatic changes).
  final VoidCallback? onUserPaged;

  @override
  State<DatePager> createState() => _DatePagerState();
}

class _DatePagerState extends State<DatePager> {
  late final PageController _controller;
  bool _programmatic = false;
  int _ticket = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController(
      initialPage: widget.pageOf(widget.selected.value),
    );
    widget.selected.addListener(_syncToSelection);
  }

  @override
  void didUpdateWidget(DatePager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.selected, widget.selected)) {
      oldWidget.selected.removeListener(_syncToSelection);
      widget.selected.addListener(_syncToSelection);
    }
  }

  @override
  void dispose() {
    widget.selected.removeListener(_syncToSelection);
    _controller.dispose();
    super.dispose();
  }

  int get _currentPage {
    if (_controller.hasClients && _controller.position.hasContentDimensions) {
      return _controller.page?.round() ?? _controller.initialPage;
    }
    return _controller.initialPage;
  }

  Future<void> _syncToSelection() async {
    if (!mounted) return;
    if (!_controller.hasClients) {
      // Not laid out yet; try again once the pager is attached.
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncToSelection());
      return;
    }

    final target = widget.pageOf(widget.selected.value);
    final current = _currentPage;
    if (target == current) return;

    final ticket = ++_ticket;
    _programmatic = true;
    try {
      if (!widget.animate) {
        _controller.jumpToPage(target);
      } else {
        // For far jumps, start right next to the target so the transition is
        // always a single page slide in the correct direction.
        if ((target - current).abs() > 1) {
          _controller.jumpToPage(target > current ? target - 1 : target + 1);
        }
        await _controller.animateToPage(
          target,
          duration: Durations.medium4,
          curve: Easing.emphasizedDecelerate,
        );
      }
    } catch (_) {
      // The controller was detached mid-animation; nothing left to sync.
    } finally {
      if (ticket == _ticket) _programmatic = false;
    }

    if (!mounted || ticket != _ticket || !_controller.hasClients) return;

    // The user may have grabbed the pager mid-animation: adopt where it
    // actually ended up.
    final actual = _currentPage;
    if (actual != widget.pageOf(widget.selected.value)) {
      widget.selected.value = widget.dateOf(actual, widget.selected.value);
    }
  }

  void _onPageChanged(int page) {
    if (_programmatic) return;
    if (page == widget.pageOf(widget.selected.value)) return;
    widget.selected.value = widget.dateOf(page, widget.selected.value);
    widget.onUserPaged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: _controller,
      onPageChanged: _onPageChanged,
      itemBuilder: widget.pageBuilder,
    );
  }
}

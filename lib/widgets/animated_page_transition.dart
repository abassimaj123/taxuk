import 'package:flutter/material.dart';
import 'package:calcwise_core/calcwise_core.dart';

/// Smooth page transition with fade + scale effect.
/// Used for TabBar navigation between screens.
class AnimatedPageTransition extends StatefulWidget {
  final Widget child;
  final Duration duration;

  const AnimatedPageTransition({
    super.key,
    required this.child,
    this.duration = AppDuration.page,
  });

  @override
  State<AnimatedPageTransition> createState() => _AnimatedPageTransitionState();
}

class _AnimatedPageTransitionState extends State<AnimatedPageTransition>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    _controller.forward();
  }

  @override
  void didUpdateWidget(AnimatedPageTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.forward(from: 0.0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: widget.child,
      ),
    );
  }
}

/// Animated counter for numeric values (tick-up animation).
class AnimatedCounter extends StatefulWidget {
  final double value;
  final TextStyle style;
  final Duration duration;
  final String Function(double) formatter;

  const AnimatedCounter({
    super.key,
    required this.value,
    required this.style,
    this.duration = const Duration(milliseconds: 1000),
    this.formatter = _defaultFormatter,
  });

  static String _defaultFormatter(double value) => value.toStringAsFixed(2);

  @override
  State<AnimatedCounter> createState() => _AnimatedCounterState();
}

class _AnimatedCounterState extends State<AnimatedCounter>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  late double _previousValue;

  @override
  void initState() {
    super.initState();
    _previousValue = widget.value;
    _setupAnimation();
  }

  void _setupAnimation() {
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );

    _animation =
        Tween<double>(begin: _previousValue, end: widget.value).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    _controller.forward();
  }

  @override
  void didUpdateWidget(AnimatedCounter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _previousValue = _animation.value;
      _controller.dispose();
      _setupAnimation();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Text(
          widget.formatter(_animation.value),
          style: widget.style,
        );
      },
    );
  }
}

/// Staggered list animation for result cards.
/// Cards fade and slide in sequentially.
class StaggeredAnimationList extends StatefulWidget {
  final List<Widget> children;
  final Duration itemDelay;
  final Duration itemDuration;

  const StaggeredAnimationList({
    super.key,
    required this.children,
    this.itemDelay = const Duration(milliseconds: 100),
    this.itemDuration = AppDuration.slow,
  });

  @override
  State<StaggeredAnimationList> createState() => _StaggeredAnimationListState();
}

class _StaggeredAnimationListState extends State<StaggeredAnimationList>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: Duration(
        milliseconds:
            (widget.children.length * widget.itemDelay.inMilliseconds +
                widget.itemDuration.inMilliseconds),
      ),
      vsync: this,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(widget.children.length, (index) {
        final delayTime = widget.itemDelay.inMilliseconds * index;
        final totalDuration = widget.itemDelay.inMilliseconds * (index + 1) +
            widget.itemDuration.inMilliseconds;

        return _AnimatedListItem(
          animation: Tween<double>(begin: 0.0, end: 1.0).animate(
            CurvedAnimation(
              parent: _controller,
              curve: Interval(
                delayTime / totalDuration,
                (delayTime + widget.itemDuration.inMilliseconds) /
                    totalDuration,
                curve: Curves.easeOutCubic,
              ),
            ),
          ),
          child: widget.children[index],
        );
      }),
    );
  }
}

class _AnimatedListItem extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;

  const _AnimatedListItem({
    required this.animation,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.1),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }
}

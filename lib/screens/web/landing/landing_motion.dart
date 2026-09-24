import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerHoverEvent;
import 'package:flutter/material.dart';

// Motion primitives shared by the admin and org landing pages. Everything
// here animates with Transform/Opacity only and passes its subtree through
// as a prebuilt `child`, so scrolling and intro animations repaint a layer
// instead of rebuilding the widget tree underneath it.

/// Perspective used by every 3D transform on the landing pages, so tilts on
/// different widgets feel like they live in the same space.
Matrix4 perspective3d([double depth = 0.0011]) =>
    Matrix4.identity()..setEntry(3, 2, depth);

class LandingMotion {
  LandingMotion._();

  /// OS-level "reduce motion" — reveals snap in, nothing floats or tilts.
  static bool reduced(BuildContext context) =>
      MediaQuery.of(context).disableAnimations;

  /// Parallax, pinning, and pointer tilt only run on wide screens with
  /// motion allowed; phones and tablets get plain reveals.
  static bool rich(BuildContext context) =>
      !reduced(context) && MediaQuery.of(context).size.width >= 900;
}

/// Makes the landing page's ScrollController reachable by any descendant
/// (reveals, parallax, marquee, navbar) without threading it through every
/// constructor.
class LandingScrollScope extends InheritedWidget {
  final ScrollController controller;

  const LandingScrollScope({
    required this.controller,
    required super.child,
    super.key,
  });

  static ScrollController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<LandingScrollScope>()
      ?.controller;

  @override
  bool updateShouldNotify(LandingScrollScope old) =>
      old.controller != controller;
}

// ── Reveal ──────────────────────────────────────────────────────────────

/// Fades + lifts [child] in the first time it scrolls into view, then gets
/// out of the way (once finished it returns [child] with no wrappers).
/// Stagger groups by giving siblings increasing [delay]s.
class Reveal extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;

  /// Starting offset in logical pixels.
  final double dx;
  final double dy;

  /// Starting scale (1 = none).
  final double scaleFrom;

  /// Starting backward tilt around the X axis, in radians (0 = flat).
  final double tiltFrom;

  const Reveal({
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 750),
    this.dx = 0,
    this.dy = 36,
    this.scaleFrom = 1,
    this.tiltFrom = 0,
    super.key,
  });

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _ctrl,
    curve: Curves.easeOutCubic,
  );
  ScrollPosition? _position;
  bool _triggered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (LandingMotion.reduced(context)) {
      _triggered = true;
      _ctrl.value = 1;
      return;
    }
    // Listen to whichever scroll view this sits in, so reveals work on any
    // page (landing home, About, Help) without extra wiring.
    final p = Scrollable.maybeOf(context)?.position;
    if (p != _position) {
      _position?.removeListener(_check);
      _position = p;
      if (!_triggered) _position?.addListener(_check);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  void _check() {
    if (_triggered || !mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return;
    final top = box.localToGlobal(Offset.zero).dy;
    if (top < MediaQuery.of(context).size.height * 0.9) {
      _triggered = true;
      _position?.removeListener(_check);
      Future.delayed(widget.delay, () {
        if (mounted) _ctrl.forward();
      });
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_check);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (context, child) {
        final v = _t.value;
        if (v >= 1) return child!;
        final r = 1 - v;
        final s = widget.scaleFrom + (1 - widget.scaleFrom) * v;
        final m = perspective3d()
          ..translateByDouble(widget.dx * r, widget.dy * r, 0, 1)
          ..scaleByDouble(s, s, 1, 1);
        if (widget.tiltFrom != 0) m.rotateX(-widget.tiltFrom * r);
        return Opacity(
          opacity: v,
          child: Transform(
            alignment: Alignment.center,
            transform: m,
            child: child,
          ),
        );
      },
    );
  }
}

// ── Parallax ────────────────────────────────────────────────────────────

/// Shifts [child] vertically in proportion to its distance from the
/// viewport center: positive [factor] makes it move faster than the page
/// (feels closer), negative makes it lag behind (feels farther away). Only
/// active in [LandingMotion.rich] contexts.
class Parallax extends StatelessWidget {
  final Widget child;
  final double factor;

  /// Max drift in pixels either way.
  final double limit;

  const Parallax({
    required this.child,
    this.factor = 0.08,
    this.limit = 90,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final scroll = LandingScrollScope.maybeOf(context);
    if (scroll == null || !LandingMotion.rich(context)) return child;
    return AnimatedBuilder(
      animation: scroll,
      child: RepaintBoundary(child: child),
      builder: (context, child) {
        final box = context.findRenderObject();
        final viewport = Scrollable.maybeOf(
          context,
        )?.context.findRenderObject();
        var dy = 0.0;
        if (box is RenderBox &&
            box.hasSize &&
            box.attached &&
            viewport is RenderBox &&
            viewport.hasSize) {
          final center = box
              .localToGlobal(Offset(0, box.size.height / 2), ancestor: viewport)
              .dy;
          dy = ((center - viewport.size.height / 2) * factor).clamp(
            -limit,
            limit,
          );
        }
        return Transform.translate(offset: Offset(0, dy), child: child);
      },
    );
  }
}

// ── Scroll-progress builder ─────────────────────────────────────────────

/// Where a widget currently sits relative to the scroll viewport.
class ViewportMetrics {
  /// Widget's top edge, in pixels from the top of the viewport.
  final double top;
  final double height;
  final double viewport;

  const ViewportMetrics({
    required this.top,
    required this.height,
    required this.viewport,
  });

  static const zero = ViewportMetrics(top: 0, height: 1, viewport: 0);

  bool get known => viewport > 0;

  /// 0 while the widget's top is at/below the viewport top, 1 once the whole
  /// widget has scrolled out above it.
  double get exit => height <= 0 ? 0 : (-top / height).clamp(0.0, 1.0);

  /// For sections taller than the viewport: 0 when the section's top hits
  /// the viewport top, 1 when its bottom does.
  double get pin =>
      height <= viewport ? 0 : (-top / (height - viewport)).clamp(0.0, 1.0);

  @override
  bool operator ==(Object other) =>
      other is ViewportMetrics &&
      (other.top - top).abs() < 0.5 &&
      other.height == height &&
      other.viewport == viewport;

  @override
  int get hashCode => Object.hash(top.round(), height, viewport);
}

/// Rebuilds [builder] as the enclosing scrollable moves, handing it this
/// widget's live [ViewportMetrics]. Meant for small, self-contained sections
/// (e.g. a pinned timeline) — for layers that only move, use [Parallax].
class ScrollDriven extends StatefulWidget {
  final Widget Function(BuildContext context, ViewportMetrics m) builder;

  const ScrollDriven({required this.builder, super.key});

  @override
  State<ScrollDriven> createState() => _ScrollDrivenState();
}

class _ScrollDrivenState extends State<ScrollDriven> {
  ScrollPosition? _position;
  ViewportMetrics _m = ViewportMetrics.zero;
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final p = Scrollable.maybeOf(context)?.position;
    if (p != _position) {
      _position?.removeListener(_update);
      _position = p;
      _position?.addListener(_update);
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_update);
    super.dispose();
  }

  void _update() {
    if (!mounted) return;
    final box = context.findRenderObject();
    final scrollBox = Scrollable.maybeOf(context)?.context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return;
    if (scrollBox is! RenderBox || !scrollBox.hasSize) return;
    final next = ViewportMetrics(
      top: box.localToGlobal(Offset.zero, ancestor: scrollBox).dy,
      height: box.size.height,
      viewport: scrollBox.size.height,
    );
    if (next != _m) setState(() => _m = next);
  }

  @override
  Widget build(BuildContext context) {
    // Re-measure after layout so resizes are picked up without a scroll.
    if (!_scheduled) {
      _scheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scheduled = false;
        _update();
      });
    }
    return widget.builder(context, _m);
  }
}

// ── Pointer tilt ────────────────────────────────────────────────────────

/// Smoothed pointer position within the widget, each axis -1..1 (zero when
/// the pointer is outside). [builder] decides how to use it — rotation,
/// per-layer parallax, shadow shift. Inert under reduced motion.
class PointerTilt extends StatefulWidget {
  final Widget Function(BuildContext context, Offset tilt) builder;

  const PointerTilt({required this.builder, super.key});

  @override
  State<PointerTilt> createState() => _PointerTiltState();
}

class _PointerTiltState extends State<PointerTilt> {
  Offset _target = Offset.zero;

  void _hover(PointerHoverEvent e) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final s = box.size;
    setState(() {
      _target = Offset(
        (e.localPosition.dx / s.width * 2 - 1).clamp(-1.0, 1.0),
        (e.localPosition.dy / s.height * 2 - 1).clamp(-1.0, 1.0),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!LandingMotion.rich(context)) {
      return widget.builder(context, Offset.zero);
    }
    return MouseRegion(
      onHover: _hover,
      onExit: (_) => setState(() => _target = Offset.zero),
      child: TweenAnimationBuilder<Offset>(
        tween: Tween(end: _target),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => widget.builder(context, v),
      ),
    );
  }
}

// ── Floating ────────────────────────────────────────────────────────────

/// Slow continuous up/down drift for decorative layers.
class Floating extends StatefulWidget {
  final Widget child;
  final double amplitude;
  final Duration period;

  /// 0..1 — where in the cycle this instance starts, so neighbors don't bob
  /// in lockstep.
  final double phase;

  const Floating({
    required this.child,
    this.amplitude = 6,
    this.period = const Duration(milliseconds: 4200),
    this.phase = 0,
    super.key,
  });

  @override
  State<Floating> createState() => _FloatingState();
}

class _FloatingState extends State<Floating>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: widget.period,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (LandingMotion.reduced(context)) {
      _ctrl.stop();
    } else if (!_ctrl.isAnimating) {
      _ctrl
        ..value = widget.phase
        ..repeat();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      child: widget.child,
      builder: (context, child) => Transform.translate(
        offset: Offset(
          0,
          math.sin(_ctrl.value * 2 * math.pi) * widget.amplitude,
        ),
        child: child,
      ),
    );
  }
}

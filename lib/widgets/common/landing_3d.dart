import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerHoverEvent;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Scroll- and pointer-driven 3D building blocks shared by the admin and org
// marketing sites (admin_landing_page.dart / org_landing_page.dart). Each
// site passes in its own palette, so the motion language stays identical
// across both portals while the colors don't.

/// Perspective matrix used by every 3D transform on the landing pages —
/// one shared depth so tilts on different widgets feel like the same space.
Matrix4 perspective3d([double depth = 0.0011]) =>
    Matrix4.identity()..setEntry(3, 2, depth);

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

  /// 0 while the widget's top is at/below the viewport top, 1 once the
  /// whole widget has scrolled out above it.
  double get exit => height <= 0 ? 0 : (-top / height).clamp(0.0, 1.0);

  /// 0 while the widget is below the fold, 1 once its top has risen to
  /// ~45% of the viewport.
  double get enter =>
      !known ? 1 : ((viewport - top) / (viewport * 0.55)).clamp(0.0, 1.0);

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
/// widget's live [ViewportMetrics]. No ScrollController plumbing needed —
/// it listens to whatever Scrollable it sits inside.
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
    final top = box.localToGlobal(Offset.zero, ancestor: scrollBox).dy;
    final next = ViewportMetrics(
      top: top,
      height: box.size.height,
      viewport: scrollBox.size.height,
    );
    if (next != _m) setState(() => _m = next);
  }

  @override
  Widget build(BuildContext context) {
    // Re-measure after every layout, so size changes (window resize, a
    // pinned section settling its height) are picked up without a scroll.
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

/// Pointer-follow tilt. [builder] gets the smoothed pointer position within
/// the widget, each axis in -1..1 (0,0 = centered / pointer outside), and
/// decides itself how to turn that into rotation or parallax.
class Tilt3D extends StatefulWidget {
  final Widget Function(BuildContext context, Offset tilt) builder;

  const Tilt3D({required this.builder, super.key});

  @override
  State<Tilt3D> createState() => _Tilt3DState();
}

class _Tilt3DState extends State<Tilt3D> {
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
    if (MediaQuery.of(context).disableAnimations) {
      return widget.builder(context, Offset.zero);
    }
    return MouseRegion(
      onHover: _hover,
      onExit: (_) => setState(() => _target = Offset.zero),
      child: TweenAnimationBuilder<Offset>(
        tween: Tween(end: _target),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => widget.builder(context, v),
      ),
    );
  }
}

/// Convenience wrapper: a card that leans away from the pointer and lifts
/// slightly on hover. Used for small cards (steps, stats).
class HoverTiltCard extends StatelessWidget {
  final Widget child;
  final double maxAngle;

  const HoverTiltCard({required this.child, this.maxAngle = 0.12, super.key});

  @override
  Widget build(BuildContext context) {
    return Tilt3D(
      builder: (context, t) {
        final lift = (t.distance.clamp(0.0, 1.0)) * 6;
        return Transform(
          alignment: Alignment.center,
          transform: perspective3d()
            ..translateByDouble(0, -lift, 0, 1)
            ..rotateX(t.dy * maxAngle)
            ..rotateY(-t.dx * maxAngle),
          child: child,
        );
      },
    );
  }
}

/// One stop in a [ScrollStory3D].
class StoryItem {
  final IconData icon;
  final String title;
  final String body;
  final List<String> points;

  const StoryItem({
    required this.icon,
    required this.title,
    required this.body,
    required this.points,
  });
}

/// A pinned "scrollytelling" section: the stage stays fixed on screen while
/// the page scrolls through it, and a ring of 3D cards rotates one stop per
/// scroll step while the copy on the left swaps to match. Falls back to a
/// plain stacked list (with a 3D rise-in) on narrow screens, where pinning
/// a two-column stage doesn't fit.
class ScrollStory3D extends StatelessWidget {
  final String eyebrow;
  final String heading;
  final List<StoryItem> items;
  final Color accent;
  final List<Color> cardGradient;
  final Color background;
  final Color ink;
  final Color inkSoft;
  final Color border;
  final Widget? footer;

  const ScrollStory3D({
    required this.eyebrow,
    required this.heading,
    required this.items,
    required this.accent,
    required this.cardGradient,
    required this.background,
    required this.ink,
    required this.inkSoft,
    required this.border,
    this.footer,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 900;
        return wide ? _pinned(context) : _stacked(context);
      },
    );
  }

  // ── Wide: pinned stage ────────────────────────────────────────────
  Widget _pinned(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return ScrollDriven(
      builder: (context, m) {
        // Before the first measurement, estimate the viewport as the
        // window minus the site's fixed nav bar.
        final vh = m.known
            ? m.viewport
            : MediaQuery.of(context).size.height - 80;
        // Each extra card adds ~60% of a screen of scroll distance.
        final total = vh * (1 + 0.6 * (items.length - 1));
        final pinOffset = (-m.top)
            .clamp(0.0, math.max(0.0, total - vh))
            .toDouble();
        final raw = m.known ? m.pin * (items.length - 1) : 0.0;
        final pos = reduceMotion ? raw.roundToDouble() : _dwell(raw);
        final active = pos.round().clamp(0, items.length - 1);

        return Container(
          height: total,
          color: background,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                top: pinOffset,
                left: 0,
                right: 0,
                height: vh,
                child: _stage(pos, active),
              ),
            ],
          ),
        );
      },
    );
  }

  // Hold each card still for a stretch of scroll before easing to the
  // next one, so the carousel "settles" on every stop instead of drifting
  // continuously and never resting on anything readable.
  double _dwell(double raw) {
    final base = raw.floorToDouble();
    final f = raw - base;
    final t = ((f - 0.25) / 0.5).clamp(0.0, 1.0);
    return base + Curves.easeInOutCubic.transform(t);
  }

  Widget _stage(double pos, int active) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Row(
            children: [
              Expanded(flex: 5, child: _copy(pos, active)),
              const SizedBox(width: 32),
              Expanded(flex: 6, child: _carousel(pos)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _copy(double pos, int active) {
    final item = items[active];
    final n = items.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _eyebrow(),
        const SizedBox(height: 12),
        Text(
          heading,
          style: GoogleFonts.beVietnamPro(
            fontSize: 34,
            fontWeight: FontWeight.w800,
            color: ink,
            height: 1.15,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 36),
        SizedBox(
          height: 190,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 380),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeIn,
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.topLeft,
              children: [...previous, ?current],
            ),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.12),
                  end: Offset.zero,
                ).animate(anim),
                child: child,
              ),
            ),
            child: Column(
              key: ValueKey(active),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'STEP ${_two(active + 1)} / ${_two(n)}',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: accent,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  item.title,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: ink,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  item.body,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 15,
                    color: inkSoft,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        // Segmented progress — one segment per stop, filling as the ring
        // turns toward it.
        Row(
          children: [
            for (var i = 0; i < n; i++) ...[
              Expanded(
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: (pos - i + 1).clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
              if (i < n - 1) const SizedBox(width: 6),
            ],
          ],
        ),
        if (footer != null) ...[const SizedBox(height: 22), footer!],
      ],
    );
  }

  // Cover-flow layout: the focused card faces the viewer, neighbors swing
  // away to either side and recede. Cards stay fully opaque (translucent
  // cards let their text bleed through each other) and are dimmed with an
  // overlay instead.
  Widget _carousel(double pos) {
    final order = List.generate(items.length, (i) => i)
      // Paint farthest first so the front card is always on top.
      ..sort((a, b) => (b - pos).abs().compareTo((a - pos).abs()));

    return SizedBox(
      height: 440,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Soft floor glow under the front card.
          Positioned(
            bottom: 0,
            child: Container(
              width: 420,
              height: 60,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(200),
                gradient: RadialGradient(
                  colors: [accent.withAlpha(45), accent.withAlpha(0)],
                ),
              ),
            ),
          ),
          for (final i in order)
            if ((i - pos).abs() < 2.4) _flowCard(i, pos),
        ],
      ),
    );
  }

  Widget _flowCard(int i, double pos) {
    final d = i - pos;
    final near = d.abs().clamp(0.0, 1.0);
    final far = d.abs().clamp(0.0, 2.4);
    final side = d.sign;
    // First neighbor sits 200px out, anything further stacks 60px beyond.
    final x = side * (near * 200 + (far - near) * 60);
    final z = far * 170;
    final angle = -side * near * 0.8;
    return Opacity(
      // Only cards beyond the first neighbor fade, as they enter/leave.
      opacity: (2.4 - far).clamp(0.0, 1.0),
      child: Transform(
        alignment: Alignment.center,
        transform: perspective3d()
          ..translateByDouble(x, 0, z, 1)
          ..rotateY(angle),
        child: StoryCard(
          index: i,
          item: items[i],
          gradient: cardGradient,
          accent: accent,
          glow: 1 - near,
          dim: (far * 0.32).clamp(0.0, 0.6),
          width: 300,
          height: 380,
        ),
      ),
    );
  }

  // ── Narrow: stacked list ──────────────────────────────────────────
  Widget _stacked(BuildContext context) {
    return Container(
      color: background,
      padding: const EdgeInsets.fromLTRB(16, 56, 16, 56),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _eyebrow(),
          const SizedBox(height: 10),
          Text(
            heading,
            style: GoogleFonts.beVietnamPro(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: ink,
              height: 1.2,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 28),
          for (var i = 0; i < items.length; i++) ...[
            ScrollDriven(
              builder: (context, m) {
                final t = Curves.easeOutCubic.transform(m.enter);
                return Opacity(
                  opacity: t,
                  child: Transform(
                    alignment: Alignment.topCenter,
                    transform: perspective3d()
                      ..translateByDouble(0, (1 - t) * 40, 0, 1)
                      ..rotateX(-(1 - t) * 0.5),
                    child: StoryCard(
                      index: i,
                      item: items[i],
                      gradient: cardGradient,
                      accent: accent,
                      glow: t,
                      showBody: true,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
          ],
          if (footer != null) ...[const SizedBox(height: 8), footer!],
        ],
      ),
    );
  }

  Widget _eyebrow() => Text(
    eyebrow,
    style: GoogleFonts.beVietnamPro(
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
      color: accent,
      letterSpacing: 1.4,
    ),
  );

  static String _two(int n) => n.toString().padLeft(2, '0');
}

/// A single card face in [ScrollStory3D].
class StoryCard extends StatelessWidget {
  final int index;
  final StoryItem item;
  final List<Color> gradient;
  final Color accent;

  /// 0..1 — how "in focus" the card is; drives its glow.
  final double glow;
  final double? width;
  final double? height;

  /// Narrow layout has no side copy, so the card carries the body text.
  final bool showBody;

  /// 0..1 — dark overlay for cards pushed back in the carousel.
  final double dim;

  const StoryCard({
    required this.index,
    required this.item,
    required this.gradient,
    required this.accent,
    this.glow = 1,
    this.width,
    this.height,
    this.showBody = false,
    this.dim = 0,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(26),
      foregroundDecoration: dim <= 0
          ? null
          : BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: Colors.black.withAlpha((dim * 255).round()),
            ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
        border: Border.all(color: Colors.white.withAlpha(28)),
        boxShadow: [
          BoxShadow(
            color: accent.withAlpha((70 * glow).round()),
            blurRadius: 40,
            offset: const Offset(0, 22),
          ),
          BoxShadow(
            color: Colors.black.withAlpha(40),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(24),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.white.withAlpha(40)),
                ),
                child: Icon(item.icon, color: Colors.white, size: 26),
              ),
              const Spacer(),
              Text(
                (index + 1).toString().padLeft(2, '0'),
                style: GoogleFonts.beVietnamPro(
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  color: Colors.white.withAlpha(40),
                  height: 1,
                  letterSpacing: -1.5,
                ),
              ),
            ],
          ),
          if (height != null) const Spacer() else const SizedBox(height: 22),
          Text(
            item.title,
            style: GoogleFonts.beVietnamPro(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Container(width: 32, height: 2, color: Colors.white.withAlpha(150)),
          if (showBody) ...[
            const SizedBox(height: 12),
            Text(
              item.body,
              style: GoogleFonts.beVietnamPro(
                fontSize: 13.5,
                color: Colors.white.withAlpha(215),
                height: 1.55,
              ),
            ),
          ],
          const SizedBox(height: 16),
          for (final p in item.points)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 16,
                      color: Colors.white.withAlpha(210),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      p,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withAlpha(225),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

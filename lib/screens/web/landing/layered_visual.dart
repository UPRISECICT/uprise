import 'package:flutter/material.dart';

import 'landing_motion.dart';
import 'landing_palette.dart';

/// One floating layer in a [LayeredVisual], positioned in the visual's
/// design coordinates.
class StageLayer {
  final Widget child;
  final double? left;
  final double? top;
  final double? right;
  final double? bottom;

  /// 0..1 — how "close" the layer is. Closer layers drift more against the
  /// scroll and follow the pointer further, which is what sells the depth.
  final double depth;

  /// Entrance order; each step adds ~140ms to the layer's reveal.
  final int order;

  const StageLayer({
    required this.child,
    this.left,
    this.top,
    this.right,
    this.bottom,
    this.depth = 0.5,
    this.order = 1,
  });
}

/// A composed product visual: a base preview plus floating cards layered in
/// front of it, each moving at its own speed with the scroll and the
/// pointer (the reference's layered-parallax effect).
///
/// Everything is laid out at a fixed [designSize] and scaled to fit, so the
/// composition keeps its proportions at any width. Below 600px the stage is
/// swapped for [mobile] (one card at a readable size) rather than shrinking
/// a whole dashboard down to unreadable text.
class LayeredVisual extends StatelessWidget {
  final LandingPalette palette;
  final Widget base;
  final List<StageLayer> layers;
  final Size designSize;
  final Widget? mobile;

  /// Draw the pale tinted panel behind the composition.
  final bool panel;

  /// Delay before the whole composition starts revealing.
  final Duration delay;

  const LayeredVisual({
    required this.palette,
    required this.base,
    this.layers = const [],
    this.designSize = const Size(640, 500),
    this.mobile,
    this.panel = true,
    this.delay = Duration.zero,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.of(context).size.width < 600;
    if (narrow && mobile != null) {
      return Reveal(
        delay: delay,
        scaleFrom: 0.95,
        child: Center(child: mobile!),
      );
    }

    return PointerTilt(
      builder: (context, tilt) {
        return AspectRatio(
          aspectRatio: designSize.width / designSize.height,
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox.fromSize(
              size: designSize,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (panel) Positioned.fill(child: _Panel(palette: palette)),
                  Positioned.fill(
                    child: Center(
                      child: Reveal(
                        delay: delay,
                        dy: 40,
                        scaleFrom: 0.94,
                        tiltFrom: 0.25,
                        duration: const Duration(milliseconds: 900),
                        child: Transform(
                          alignment: Alignment.center,
                          transform: perspective3d()
                            ..rotateX(tilt.dy * 0.05)
                            ..rotateY(-tilt.dx * 0.07),
                          // Unconstrained so small card bases keep their natural
                          // height instead of stretching to fill the stage.
                          child: UnconstrainedBox(
                            child: RepaintBoundary(child: base),
                          ),
                        ),
                      ),
                    ),
                  ),
                  for (final l in layers)
                    Positioned(
                      left: l.left,
                      top: l.top,
                      right: l.right,
                      bottom: l.bottom,
                      child: Reveal(
                        delay:
                            delay + Duration(milliseconds: 260 + 140 * l.order),
                        dy: 30,
                        scaleFrom: 0.9,
                        child: Parallax(
                          factor: 0.03 + l.depth * 0.09,
                          limit: 60,
                          child: Floating(
                            amplitude: 3 + l.depth * 4,
                            phase: (l.order * 0.27) % 1,
                            period: Duration(
                              milliseconds: 3800 + l.order * 600,
                            ),
                            child: Transform.translate(
                              offset: tilt * (6 + l.depth * 16),
                              child: RepaintBoundary(child: l.child),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Panel extends StatelessWidget {
  final LandingPalette palette;

  const _Panel({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.tint, palette.tint.withAlpha(90)],
        ),
        border: Border.all(color: palette.border.withAlpha(160)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: Stack(
          children: [
            Positioned(
              right: -80,
              top: -80,
              child: _Glow(color: palette.primary.withAlpha(40), size: 320),
            ),
            Positioned(
              left: -60,
              bottom: -90,
              child: _Glow(color: palette.accent.withAlpha(30), size: 280),
            ),
          ],
        ),
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  final Color color;
  final double size;

  const _Glow({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withAlpha(0)]),
      ),
    );
  }
}

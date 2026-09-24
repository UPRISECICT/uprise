import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'landing_common.dart';
import 'landing_motion.dart';
import 'landing_palette.dart';

class WorkflowStep {
  final String label;
  final IconData icon;
  final String title;
  final String body;

  /// Small preview shown beside the step's detail on wide screens.
  final Widget? visual;

  const WorkflowStep({
    required this.label,
    required this.icon,
    required this.title,
    required this.body,
    this.visual,
  });
}

/// Step-by-step lifecycle that advances with the scroll. On wide screens the
/// stage pins under the navbar while the page scrolls through it: the track
/// fills node by node and the detail panel swaps to the active step. On
/// narrow screens / reduced motion it becomes a vertical list with reveals.
/// Meant to sit on a dark brand band.
class WorkflowTimeline extends StatelessWidget {
  final LandingPalette palette;
  final List<WorkflowStep> steps;

  const WorkflowTimeline({
    required this.palette,
    required this.steps,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (!LandingMotion.rich(context)) return _stacked();
    return ScrollDriven(
      builder: (context, m) {
        final vh = m.known ? m.viewport : MediaQuery.of(context).size.height;
        final stageH = math.max(440.0, vh - kLandingNavHeight);
        // Roughly 55% of a screen of scrolling per step.
        final total = stageH + vh * 0.55 * (steps.length - 1);
        final travel = total - stageH;
        final pinOffset = (kLandingNavHeight - m.top).clamp(0.0, travel);
        final raw = travel <= 0 ? 0.0 : pinOffset / travel * (steps.length - 1);
        final pos = _dwell(raw);
        final active = pos.round().clamp(0, steps.length - 1);
        return SizedBox(
          height: total,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                top: pinOffset.toDouble(),
                left: 0,
                right: 0,
                height: stageH,
                child: _stage(pos, active),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Rest on each step for part of the scroll before easing to the next,
  /// so every step is readable instead of constantly in motion.
  double _dwell(double raw) {
    final base = raw.floorToDouble();
    final t = ((raw - base - 0.3) / 0.4).clamp(0.0, 1.0);
    return base + Curves.easeInOutCubic.transform(t);
  }

  Widget _stage(double pos, int active) {
    final p = palette;
    final step = steps[active];
    return LandingContainer(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _Track(palette: p, steps: steps, pos: pos),
          const SizedBox(height: 44),
          SizedBox(
            height: 250,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 420),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, 0.08),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
              child: _Detail(
                key: ValueKey(active),
                palette: p,
                index: active,
                step: step,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stacked() {
    return LandingContainer(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          for (var i = 0; i < steps.length; i++)
            Reveal(
              delay: const Duration(milliseconds: 60),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _Detail(
                  palette: palette,
                  index: i,
                  step: steps[i],
                  compact: true,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Track extends StatelessWidget {
  final LandingPalette palette;
  final List<WorkflowStep> steps;
  final double pos;

  const _Track({required this.palette, required this.steps, required this.pos});

  @override
  Widget build(BuildContext context) {
    final n = steps.length;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final span = w / n;
        const node = 58.0;
        return SizedBox(
          height: 104,
          child: Stack(
            children: [
              // Rail + fill, running node center to node center.
              Positioned(
                left: span / 2,
                right: span / 2,
                top: node / 2 - 1.5,
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(30),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: (pos / (n - 1)).clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [palette.accent, palette.primary],
                        ),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ),
              for (var i = 0; i < n; i++)
                Positioned(
                  left: span * i,
                  width: span,
                  top: 0,
                  child: _Node(
                    palette: palette,
                    step: steps[i],
                    // 0 = upcoming, 1 = reached.
                    reached: (pos - i + 1).clamp(0.0, 1.0),
                    focus: (1 - (pos - i).abs()).clamp(0.0, 1.0),
                    size: node,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Node extends StatelessWidget {
  final LandingPalette palette;
  final WorkflowStep step;
  final double reached;
  final double focus;
  final double size;

  const _Node({
    required this.palette,
    required this.step,
    required this.reached,
    required this.focus,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final on = reached >= 1;
    return Column(
      children: [
        Transform.scale(
          scale: 1 + focus * 0.14,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? palette.accent : palette.bandTop,
              border: Border.all(
                color: on ? palette.accent : Colors.white.withAlpha(50),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: palette.accent.withAlpha((110 * focus).round()),
                  blurRadius: 28,
                ),
              ],
            ),
            child: Icon(
              step.icon,
              size: 24,
              color: on ? Colors.white : Colors.white.withAlpha(150),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          step.label,
          style: GoogleFonts.beVietnamPro(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.8,
            color: Colors.white.withAlpha(on ? 240 : 110),
          ),
        ),
      ],
    );
  }
}

class _Detail extends StatelessWidget {
  final LandingPalette palette;
  final int index;
  final WorkflowStep step;
  final bool compact;

  const _Detail({
    required this.palette,
    required this.index,
    required this.step,
    this.compact = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: palette.accent.withAlpha(40),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                'STEP ${index + 1} · ${step.label}',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: palette.accent,
                ),
              ),
            ),
            if (compact) ...[
              const Spacer(),
              Icon(step.icon, color: Colors.white.withAlpha(160), size: 22),
            ],
          ],
        ),
        const SizedBox(height: 14),
        Text(
          step.title,
          style: GoogleFonts.beVietnamPro(
            fontSize: compact ? 19 : 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          step.body,
          style: GoogleFonts.beVietnamPro(
            fontSize: compact ? 14 : 15.5,
            height: 1.65,
            color: Colors.white.withAlpha(190),
          ),
        ),
      ],
    );

    return Container(
      padding: EdgeInsets.all(compact ? 22 : 30),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(10),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withAlpha(26)),
      ),
      child: compact || step.visual == null
          ? text
          : Row(
              children: [
                Expanded(flex: 6, child: text),
                const SizedBox(width: 36),
                Expanded(
                  flex: 5,
                  child: Center(
                    child: FittedBox(fit: BoxFit.scaleDown, child: step.visual),
                  ),
                ),
              ],
            ),
    );
  }
}

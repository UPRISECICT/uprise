import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'landing_common.dart';
import 'landing_motion.dart';
import 'landing_palette.dart';

/// Landing hero: copy on the left, a [LayeredVisual] on the right.
///
/// Entrance is one choreographed sequence — label, then each headline line
/// rising out of its own clip, then description, CTAs, and finally the
/// visual (which runs its own layered reveal). On scroll the copy lags the
/// page slightly and the background glows drift slower still.
class LandingHero extends StatefulWidget {
  final LandingPalette palette;
  final String label;
  final List<String> titleLines;

  /// Index into [titleLines] to render in the brand color, or -1.
  final int highlightLine;
  final String description;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String secondaryLabel;
  final VoidCallback onSecondary;
  final Widget visual;

  /// Small line under the CTAs, e.g. "Bulacan State University · CICT".
  final String footnote;

  const LandingHero({
    required this.palette,
    required this.label,
    required this.titleLines,
    required this.description,
    required this.primaryLabel,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
    required this.visual,
    required this.footnote,
    this.highlightLine = -1,
    super.key,
  });

  @override
  State<LandingHero> createState() => _LandingHeroState();
}

class _LandingHeroState extends State<LandingHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (LandingMotion.reduced(context)) {
      _intro.value = 1;
    } else if (_intro.isDismissed) {
      // Let the navbar land first.
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) _intro.forward();
      });
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  /// Fade + lift for one piece of the intro, within [begin]..[end] of the
  /// intro timeline.
  Widget _step(double begin, double end, Widget child, {double dy = 22}) {
    final anim = CurvedAnimation(
      parent: _intro,
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: anim,
      child: child,
      builder: (context, child) => anim.value >= 1
          ? child!
          : Opacity(
              opacity: anim.value,
              child: Transform.translate(
                offset: Offset(0, dy * (1 - anim.value)),
                child: child,
              ),
            ),
    );
  }

  /// Headline line that rises from below its own baseline (masked).
  Widget _line(int i, String text, TextStyle style) {
    final begin = 0.12 + i * 0.1;
    final anim = CurvedAnimation(
      parent: _intro,
      curve: Interval(begin, begin + 0.4, curve: Curves.easeOutCubic),
    );
    return ClipRect(
      child: AnimatedBuilder(
        animation: anim,
        child: Text(text, style: style),
        builder: (context, child) => Transform.translate(
          offset: Offset(0, (style.fontSize ?? 40) * 1.2 * (1 - anim.value)),
          child: Opacity(opacity: anim.value, child: child),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final size = MediaQuery.of(context).size;
    final wide = size.width >= 980;
    final titleSize = size.width < 600 ? 36.0 : (wide ? 58.0 : 46.0);
    final titleStyle = GoogleFonts.beVietnamPro(
      fontSize: titleSize,
      fontWeight: FontWeight.w800,
      height: 1.08,
      letterSpacing: -1.6,
      color: p.ink,
    );

    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _step(0, 0.3, _Label(palette: p, text: widget.label), dy: 12),
        const SizedBox(height: 26),
        for (var i = 0; i < widget.titleLines.length; i++)
          _line(
            i,
            widget.titleLines[i],
            i == widget.highlightLine
                ? titleStyle.copyWith(color: p.primary)
                : titleStyle,
          ),
        const SizedBox(height: 24),
        _step(
          0.45,
          0.75,
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: Text(
              widget.description,
              style: GoogleFonts.beVietnamPro(
                fontSize: size.width < 600 ? 15.5 : 17,
                height: 1.65,
                color: p.inkSoft,
              ),
            ),
          ),
        ),
        const SizedBox(height: 34),
        _step(
          0.58,
          0.88,
          Wrap(
            spacing: 14,
            runSpacing: 12,
            children: [
              LandingButton(
                label: widget.primaryLabel,
                onPressed: widget.onPrimary,
                palette: p,
                arrow: true,
                large: true,
              ),
              LandingButton(
                label: widget.secondaryLabel,
                onPressed: widget.onSecondary,
                palette: p,
                style: LandingButtonStyle.secondary,
                large: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 30),
        _step(
          0.7,
          1,
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/cict_logo.png',
                width: 26,
                height: 26,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
              const SizedBox(width: 6),
              Image.asset(
                'assets/images/bsu_logo.png',
                width: 26,
                height: 26,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  widget.footnote,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: p.inkSoft,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return Container(
      constraints: BoxConstraints(minHeight: wide ? size.height : 0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, p.bg],
        ),
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(child: _DotField(color: p.ink.withAlpha(14))),
          Positioned(
            top: -160,
            right: -120,
            child: Parallax(
              factor: -0.25,
              limit: 200,
              child: _Glow(color: p.primary.withAlpha(34), size: 620),
            ),
          ),
          Positioned(
            bottom: -220,
            left: -200,
            child: Parallax(
              factor: -0.18,
              limit: 200,
              child: _Glow(color: p.accent.withAlpha(26), size: 560),
            ),
          ),
          LandingContainer(
            padding: EdgeInsets.only(
              top: kLandingNavHeight + (wide ? 40 : 28),
              bottom: wide ? 72 : 48,
            ),
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        flex: 5,
                        child: Parallax(factor: -0.12, child: copy),
                      ),
                      const SizedBox(width: 48),
                      Expanded(flex: 6, child: widget.visual),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [copy, const SizedBox(height: 44), widget.visual],
                  ),
          ),
          if (wide)
            Positioned(
              left: 0,
              right: 0,
              bottom: 22,
              child: _step(0.85, 1, _ScrollHint(palette: p), dy: 8),
            ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final LandingPalette palette;
  final String text;

  const _Label({required this.palette, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: palette.ink.withAlpha(10),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: palette.primary,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(
              'UPRISE',
              style: GoogleFonts.beVietnamPro(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              text,
              style: GoogleFonts.beVietnamPro(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
                color: palette.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScrollHint extends StatelessWidget {
  final LandingPalette palette;

  const _ScrollHint({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'SCROLL',
          style: GoogleFonts.beVietnamPro(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
            color: palette.inkFaint,
          ),
        ),
        const SizedBox(height: 6),
        Floating(
          amplitude: 4,
          period: const Duration(milliseconds: 1800),
          child: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: palette.inkSoft,
            size: 22,
          ),
        ),
      ],
    );
  }
}

class _Glow extends StatelessWidget {
  final Color color;
  final double size;

  const _Glow({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withAlpha(0)]),
        ),
      ),
    );
  }
}

/// Faint dot texture behind the hero.
class _DotField extends StatelessWidget {
  final Color color;

  const _DotField({required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(child: CustomPaint(painter: _DotPainter(color))),
    );
  }
}

class _DotPainter extends CustomPainter {
  final Color color;

  _DotPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 26.0;
    final paint = Paint()..color = color;
    for (var y = gap / 2; y < size.height; y += gap) {
      for (var x = gap / 2; x < size.width; x += gap) {
        canvas.drawCircle(Offset(x, y), 1.1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotPainter old) => old.color != color;
}

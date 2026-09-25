import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'landing_common.dart';
import 'landing_motion.dart';
import 'landing_palette.dart';

/// Dark brand band that wraps a section: gradient fill, two slow parallax
/// glows, and a faint grid. Used behind the overview/workflow sections and
/// the closing CTA.
class BrandBand extends StatelessWidget {
  final LandingPalette palette;
  final Widget child;
  final EdgeInsets padding;

  const BrandBand({
    required this.palette,
    required this.child,
    this.padding = const EdgeInsets.symmetric(vertical: 110),
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.of(context).size.width < 600;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.bandTop, palette.bandBottom],
        ),
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(painter: _GridPainter()),
              ),
            ),
          ),
          Positioned(
            top: -180,
            left: -160,
            child: Parallax(
              factor: -0.2,
              limit: 160,
              child: _Glow(color: palette.primary.withAlpha(60), size: 520),
            ),
          ),
          Positioned(
            bottom: -200,
            right: -140,
            child: Parallax(
              factor: -0.14,
              limit: 160,
              child: _Glow(color: palette.accent.withAlpha(40), size: 480),
            ),
          ),
          Padding(
            padding: narrow
                ? EdgeInsets.symmetric(vertical: padding.vertical / 2 * 0.65)
                : padding,
            child: child,
          ),
        ],
      ),
    );
  }
}

/// Closing call to action: one clear line, one sentence, one button that
/// goes to this portal's own login.
class PortalCta extends StatelessWidget {
  final LandingPalette palette;
  final String eyebrow;
  final String title;
  final String body;
  final String buttonLabel;
  final VoidCallback onPressed;

  const PortalCta({
    required this.palette,
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.buttonLabel,
    required this.onPressed,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return BrandBand(
      palette: palette,
      padding: const EdgeInsets.symmetric(vertical: 130),
      child: LandingContainer(
        child: Column(
          children: [
            // BulSU · UPRISE · CICT — the university and college flank
            // the product seal and slide in from their own sides.
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Reveal(
                  delay: const Duration(milliseconds: 120),
                  dx: -28,
                  dy: 0,
                  child: _Seal(
                    palette: palette,
                    asset: 'assets/images/bsu_logo.png',
                    size: w < 600 ? 50 : 58,
                  ),
                ),
                SizedBox(width: w < 600 ? 14 : 22),
                Reveal(
                  scaleFrom: 0.8,
                  child: _Seal(
                    palette: palette,
                    asset: 'assets/images/logo.png',
                    size: w < 600 ? 64 : 74,
                    glow: true,
                  ),
                ),
                SizedBox(width: w < 600 ? 14 : 22),
                Reveal(
                  delay: const Duration(milliseconds: 120),
                  dx: 28,
                  dy: 0,
                  child: _Seal(
                    palette: palette,
                    asset: 'assets/images/cict_logo.png',
                    size: w < 600 ? 50 : 58,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Reveal(
              delay: const Duration(milliseconds: 80),
              child: Eyebrow(palette: palette, text: eyebrow, dark: true),
            ),
            const SizedBox(height: 16),
            Reveal(
              delay: const Duration(milliseconds: 160),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: w < 600 ? 30 : 46,
                    fontWeight: FontWeight.w800,
                    height: 1.12,
                    letterSpacing: -1.2,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Reveal(
              delay: const Duration(milliseconds: 240),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Text(
                  body,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 16,
                    height: 1.65,
                    color: Colors.white.withAlpha(185),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 34),
            Reveal(
              delay: const Duration(milliseconds: 320),
              child: LandingButton(
                label: buttonLabel,
                onPressed: onPressed,
                palette: palette,
                style: LandingButtonStyle.onDark,
                arrow: true,
                large: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// White circular badge holding one logo.
class _Seal extends StatelessWidget {
  final LandingPalette palette;
  final String asset;
  final double size;
  final bool glow;

  const _Seal({
    required this.palette,
    required this.asset,
    required this.size,
    this.glow = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.16),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: glow
                ? palette.accent.withAlpha(80)
                : Colors.black.withAlpha(60),
            blurRadius: glow ? 40 : 18,
          ),
        ],
      ),
      child: Image.asset(
        asset,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) =>
            Icon(Icons.shield_rounded, color: palette.primary),
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

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const gap = 64.0;
    final paint = Paint()
      ..color = Colors.white.withAlpha(9)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => false;
}

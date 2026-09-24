import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'landing_common.dart';
import 'landing_motion.dart';
import 'landing_palette.dart';

/// One numbered feature story: copy on one side, a layered product visual
/// on the other. Alternate [reversed] between stories for the
/// Text | Visual → Visual | Text rhythm. Stacks vertically below 980px.
class FeatureStory extends StatelessWidget {
  final LandingPalette palette;
  final String number;
  final String eyebrow;
  final String title;
  final String body;
  final List<String> points;
  final Widget visual;
  final bool reversed;

  const FeatureStory({
    required this.palette,
    required this.number,
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.points,
    required this.visual,
    this.reversed = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final wide = w >= 980;
    final p = palette;

    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Reveal(
          dy: 24,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                number,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  height: 1,
                  letterSpacing: -2,
                  color: p.primary.withAlpha(46),
                ),
              ),
              const SizedBox(width: 14),
              Flexible(
                child: Eyebrow(palette: p, text: eyebrow),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Reveal(
          delay: const Duration(milliseconds: 90),
          child: Text(
            title,
            style: GoogleFonts.beVietnamPro(
              fontSize: w < 600 ? 26 : 34,
              fontWeight: FontWeight.w800,
              height: 1.18,
              letterSpacing: -0.7,
              color: p.ink,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Reveal(
          delay: const Duration(milliseconds: 170),
          child: Text(
            body,
            style: GoogleFonts.beVietnamPro(
              fontSize: 15.5,
              height: 1.7,
              color: p.inkSoft,
            ),
          ),
        ),
        const SizedBox(height: 22),
        for (var i = 0; i < points.length; i++)
          Reveal(
            delay: Duration(milliseconds: 240 + i * 80),
            dx: -18,
            dy: 0,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    margin: const EdgeInsets.only(top: 1),
                    decoration: BoxDecoration(
                      color: p.tint,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: p.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      points[i],
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        height: 1.5,
                        color: p.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );

    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [copy, const SizedBox(height: 36), visual],
      );
    }
    final children = <Widget>[
      Expanded(flex: 5, child: copy),
      const SizedBox(width: 72),
      Expanded(flex: 6, child: visual),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: reversed ? children.reversed.toList() : children,
    );
  }
}

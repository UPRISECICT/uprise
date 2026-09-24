import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'landing_motion.dart';
import 'landing_palette.dart';

class Capability {
  final IconData icon;
  final String title;
  final String body;

  const Capability(this.icon, this.title, this.body);
}

/// Responsive grid of [FeatureCard]s that reveal in a diagonal stagger
/// (left-to-right within a row, each row slightly after the previous).
class CapabilityGrid extends StatelessWidget {
  final LandingPalette palette;
  final List<Capability> items;
  final bool dark;

  const CapabilityGrid({
    required this.palette,
    required this.items,
    this.dark = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        const gap = 18.0;
        final w = c.maxWidth;
        final cols = w >= 1000 ? 4 : (w >= 700 ? 3 : (w >= 460 ? 2 : 1));
        final cardW = (w - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          alignment: WrapAlignment.center,
          children: [
            for (var i = 0; i < items.length; i++)
              SizedBox(
                width: cardW,
                child: Reveal(
                  delay: Duration(
                    milliseconds: (i % cols) * 90 + (i ~/ cols) * 70,
                  ),
                  dy: 44,
                  scaleFrom: 0.96,
                  child: FeatureCard(
                    palette: palette,
                    index: i + 1,
                    capability: items[i],
                    dark: dark,
                    // Equal heights only matter when cards sit side by side.
                    minHeight: cols > 1 ? 236 : 0,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Capability card with a hover lift, border tint, and icon fill.
class FeatureCard extends StatefulWidget {
  final LandingPalette palette;
  final int index;
  final Capability capability;
  final bool dark;
  final double minHeight;

  const FeatureCard({
    required this.palette,
    required this.index,
    required this.capability,
    this.dark = false,
    this.minHeight = 0,
    super.key,
  });

  @override
  State<FeatureCard> createState() => _FeatureCardState();
}

class _FeatureCardState extends State<FeatureCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final dark = widget.dark;
    final accent = dark ? p.accent : p.primary;
    final Color bg = dark
        ? Colors.white.withAlpha(_hover ? 18 : 10)
        : Colors.white;
    final Color line = dark
        ? Colors.white.withAlpha(_hover ? 60 : 24)
        : (_hover ? p.primary.withAlpha(110) : p.border);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
        constraints: BoxConstraints(minHeight: widget.minHeight),
        transform: Matrix4.translationValues(0, _hover ? -6 : 0, 0),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: line),
          boxShadow: dark
              ? null
              : [
                  BoxShadow(
                    color: _hover
                        ? p.primary.withAlpha(30)
                        : p.ink.withAlpha(8),
                    blurRadius: _hover ? 30 : 14,
                    offset: Offset(0, _hover ? 14 : 6),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: _hover
                        ? accent
                        : (dark ? Colors.white.withAlpha(16) : p.tint),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    widget.capability.icon,
                    size: 22,
                    color: _hover
                        ? Colors.white
                        : (dark ? Colors.white : p.primary),
                  ),
                ),
                const Spacer(),
                Text(
                  widget.index.toString().padLeft(2, '0'),
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: dark ? Colors.white.withAlpha(90) : p.inkFaint,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              widget.capability.title,
              style: GoogleFonts.beVietnamPro(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: dark ? Colors.white : p.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.capability.body,
              style: GoogleFonts.beVietnamPro(
                fontSize: 13,
                height: 1.6,
                color: dark ? Colors.white.withAlpha(170) : p.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

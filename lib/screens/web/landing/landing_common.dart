import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'landing_motion.dart';
import 'landing_palette.dart';

// Small building blocks every landing section uses: buttons, section
// headers, the logo lockup, page-width container, and anchor scrolling.

/// Height the fixed navbar occupies over the page.
const double kLandingNavHeight = 76;

/// Max content width shared by every section.
const double kLandingMaxWidth = 1180;

/// Smooth-scrolls [controller] so the widget with [key] lands just below the
/// fixed navbar. No-op if the key isn't mounted yet.
Future<void> scrollToKey(ScrollController controller, GlobalKey key) async {
  final ctx = key.currentContext;
  if (ctx == null || !controller.hasClients) return;
  final box = ctx.findRenderObject();
  final viewport = Scrollable.maybeOf(ctx)?.context.findRenderObject();
  if (box is! RenderBox || viewport is! RenderBox) return;
  final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
  final target = (controller.offset + top - kLandingNavHeight + 1).clamp(
    0.0,
    controller.position.maxScrollExtent,
  );
  final reduced = MediaQuery.of(ctx).disableAnimations;
  if (reduced) {
    controller.jumpTo(target);
  } else {
    await controller.animateTo(
      target,
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeInOutCubic,
    );
  }
}

/// Centers content at [kLandingMaxWidth] with responsive side gutters.
class LandingContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;

  const LandingContainer({
    required this.child,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final gutter = w < 600 ? 16.0 : (w < 1000 ? 28.0 : 40.0);
    return Padding(
      padding: padding.add(EdgeInsets.symmetric(horizontal: gutter)),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kLandingMaxWidth),
          child: child,
        ),
      ),
    );
  }
}

// ── Buttons ─────────────────────────────────────────────────────────────

enum LandingButtonStyle {
  /// Filled brand color — the one primary action per view.
  primary,

  /// Outlined, for light backgrounds.
  secondary,

  /// White fill, for dark bands.
  onDark,

  /// Outlined white, for dark bands.
  onDarkOutline,
}

/// Button with hover lift, press scale, and an arrow that nudges forward
/// on hover.
class LandingButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  final LandingPalette palette;
  final LandingButtonStyle style;
  final bool arrow;
  final bool large;

  const LandingButton({
    required this.label,
    required this.onPressed,
    required this.palette,
    this.style = LandingButtonStyle.primary,
    this.arrow = false,
    this.large = false,
    super.key,
  });

  @override
  State<LandingButton> createState() => _LandingButtonState();
}

class _LandingButtonState extends State<LandingButton> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final (Color bg, Color fg, Color? line) = switch (widget.style) {
      LandingButtonStyle.primary => (
        _hover ? p.primaryDeep : p.primary,
        Colors.white,
        null,
      ),
      LandingButtonStyle.secondary => (
        _hover ? p.ink.withAlpha(8) : Colors.white,
        p.ink,
        p.ink.withAlpha(_hover ? 90 : 45),
      ),
      LandingButtonStyle.onDark => (Colors.white, p.primaryDeep, null),
      LandingButtonStyle.onDarkOutline => (
        Colors.white.withAlpha(_hover ? 22 : 0),
        Colors.white,
        Colors.white.withAlpha(_hover ? 150 : 80),
      ),
    };
    final filled =
        widget.style == LandingButtonStyle.primary ||
        widget.style == LandingButtonStyle.onDark;
    final shadowColor = widget.style == LandingButtonStyle.primary
        ? p.primary
        : Colors.black;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _down = false;
      }),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onPressed,
        child: Semantics(
          button: true,
          label: widget.label,
          child: AnimatedScale(
            scale: _down ? 0.97 : 1,
            duration: const Duration(milliseconds: 120),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              transform: Matrix4.translationValues(0, _hover ? -2 : 0, 0),
              padding: EdgeInsets.symmetric(
                horizontal: widget.large ? 28 : 22,
                vertical: widget.large ? 18 : 14,
              ),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(12),
                border: line == null ? null : Border.all(color: line),
                boxShadow: filled
                    ? [
                        BoxShadow(
                          color: shadowColor.withAlpha(_hover ? 80 : 45),
                          blurRadius: _hover ? 26 : 16,
                          offset: Offset(0, _hover ? 12 : 7),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.label,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: widget.large ? 15 : 14,
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                  if (widget.arrow) ...[
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: _hover ? 12 : 8,
                    ),
                    Icon(Icons.arrow_forward_rounded, size: 17, color: fg),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Section header ──────────────────────────────────────────────────────

/// Eyebrow + title + optional subtitle, revealed in a short stagger.
class SectionHeader extends StatelessWidget {
  final LandingPalette palette;
  final String eyebrow;
  final String title;
  final String? subtitle;
  final bool center;
  final bool dark;

  const SectionHeader({
    required this.palette,
    required this.eyebrow,
    required this.title,
    this.subtitle,
    this.center = false,
    this.dark = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final align = center ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    final textAlign = center ? TextAlign.center : TextAlign.start;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Reveal(
            child: Eyebrow(palette: palette, text: eyebrow, dark: dark),
          ),
          const SizedBox(height: 14),
          Reveal(
            delay: const Duration(milliseconds: 90),
            child: Text(
              title,
              textAlign: textAlign,
              style: GoogleFonts.beVietnamPro(
                fontSize: w < 600 ? 28 : (w < 1000 ? 34 : 40),
                fontWeight: FontWeight.w800,
                height: 1.15,
                letterSpacing: -0.8,
                color: dark ? Colors.white : palette.ink,
              ),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 14),
            Reveal(
              delay: const Duration(milliseconds: 180),
              child: Text(
                subtitle!,
                textAlign: textAlign,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 16,
                  height: 1.65,
                  color: dark ? Colors.white.withAlpha(185) : palette.inkSoft,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Small uppercase label with a short accent rule in front of it.
class Eyebrow extends StatelessWidget {
  final LandingPalette palette;
  final String text;
  final bool dark;

  const Eyebrow({
    required this.palette,
    required this.text,
    this.dark = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final color = dark ? palette.accent : palette.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 18, height: 2, color: color),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            text,
            style: GoogleFonts.beVietnamPro(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.6,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Logo lockup ─────────────────────────────────────────────────────────

class LandingLogo extends StatelessWidget {
  final LandingPalette palette;
  final bool dark;
  final bool showPortal;

  const LandingLogo({
    required this.palette,
    this.dark = false,
    this.showPortal = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/images/logo.png',
          width: 34,
          height: 34,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) =>
              Icon(Icons.shield_rounded, color: palette.primary, size: 30),
        ),
        const SizedBox(width: 10),
        Text(
          'UPRISE',
          style: GoogleFonts.beVietnamPro(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.6,
            color: dark ? Colors.white : palette.ink,
          ),
        ),
        if (showPortal) ...[
          const SizedBox(width: 10),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: dark
                    ? Colors.white.withAlpha(20)
                    : palette.primary.withAlpha(16),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                palette.portalLabel,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                  color: dark ? Colors.white.withAlpha(210) : palette.primary,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

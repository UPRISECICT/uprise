import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'landing_common.dart';
import 'landing_motion.dart';
import 'landing_palette.dart';

class LandingNavItem {
  final String label;
  final VoidCallback onTap;
  final bool active;

  const LandingNavItem({
    required this.label,
    required this.onTap,
    this.active = false,
  });
}

/// Fixed top bar for both landing pages. Transparent over the hero, then
/// fades to a solid white bar once the page scrolls (a translucent fill,
/// not a BackdropFilter blur — blur is expensive on Flutter web). Pass a
/// null [controller] for pages that should always show the solid bar.
/// Slides in on first load. Below 860px the links collapse into a menu.
class LandingNavbar extends StatelessWidget {
  final LandingPalette palette;
  final List<LandingNavItem> items;
  final String loginLabel;
  final VoidCallback onLogin;
  final VoidCallback onLogoTap;
  final ScrollController? controller;

  const LandingNavbar({
    required this.palette,
    required this.items,
    required this.loginLabel,
    required this.onLogin,
    required this.onLogoTap,
    this.controller,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final bar = controller == null
        ? _bar(context, solid: true)
        : AnimatedBuilder(
            animation: controller!,
            builder: (context, _) => _bar(
              context,
              solid: controller!.hasClients && controller!.offset > 8,
            ),
          );
    if (LandingMotion.reduced(context)) return bar;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      child: bar,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, -18 * (1 - t)),
          child: child,
        ),
      ),
    );
  }

  Widget _bar(BuildContext context, {required bool solid}) {
    final narrow = MediaQuery.of(context).size.width < 860;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      height: kLandingNavHeight,
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(solid ? 255 : 0),
        border: Border(
          bottom: BorderSide(
            color: solid ? palette.border : Colors.transparent,
          ),
        ),
        boxShadow: solid
            ? [
                BoxShadow(
                  color: Colors.black.withAlpha(10),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: LandingContainer(
        child: Row(
          children: [
            Flexible(
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: onLogoTap,
                  child: LandingLogo(
                    palette: palette,
                    showPortal: MediaQuery.of(context).size.width >= 420,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            if (!narrow) ...[
              const Spacer(),
              for (final item in items) _NavLink(palette: palette, item: item),
              const SizedBox(width: 18),
              LandingButton(
                label: loginLabel,
                onPressed: onLogin,
                palette: palette,
              ),
            ] else ...[
              const Spacer(),
              LandingButton(
                label: 'Login',
                onPressed: onLogin,
                palette: palette,
              ),
              const SizedBox(width: 4),
              PopupMenuButton<int>(
                tooltip: 'Menu',
                icon: Icon(Icons.menu_rounded, color: palette.ink),
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                onSelected: (i) => items[i].onTap(),
                itemBuilder: (_) => [
                  for (var i = 0; i < items.length; i++)
                    PopupMenuItem(
                      value: i,
                      child: Text(
                        items[i].label,
                        style: GoogleFonts.beVietnamPro(
                          fontWeight: FontWeight.w600,
                          color: items[i].active
                              ? palette.primary
                              : palette.ink,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NavLink extends StatefulWidget {
  final LandingPalette palette;
  final LandingNavItem item;

  const _NavLink({required this.palette, required this.item});

  @override
  State<_NavLink> createState() => _NavLinkState();
}

class _NavLinkState extends State<_NavLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final on = _hover || widget.item.active;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.item.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                style: GoogleFonts.beVietnamPro(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: on ? p.ink : p.inkSoft,
                ),
                child: Text(widget.item.label),
              ),
              const SizedBox(height: 5),
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                height: 2,
                width: on ? 18 : 0,
                decoration: BoxDecoration(
                  color: p.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

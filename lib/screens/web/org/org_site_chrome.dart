import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Shared nav bar + footer + color palette for the org marketing site
// (Home / Features / About / Help) — the exact structural mirror of the
// admin portal's own marketing site (admin_site_chrome.dart), so the two
// feel like the same product family. Only the palette and the copy differ:
// org is warm/orange-forward (matches OrganizationLogin's cream page and
// the real UPRISE brand mark) instead of admin's cool slate/blue.
class OrgSiteColors {
  static const Color accent = Color(0xFFF97316);
  static const Color accentDeep = Color(0xFFEA580C);
  static const Color slateDark = Color(0xFF1E1B16); // structural, nav/ink
  static const Color slateMid = Color(0xFF6B7280);
  static const Color navy = Color(0xFF0B1120);
  static const Color ink = Color(0xFF1E1B16);
  static const Color inkSoft = Color(0xFF6B7280);
  static const Color inkFaint = Color(0xFFAEB4C4);
  static const Color bg = Color(0xFFFAFAF9);
  static const Color border = Color(0xFFE7E2DC);
  // Semantic — pulse dot only, not a design accent.
  static const Color success = Color(0xFF10B981);
}

enum OrgSiteSection { home, features, about, help }

// Faint dot-grid texture — reused behind every section for the same
// "abstract background" identity throughout the site.
class OrgDotGridBackground extends StatelessWidget {
  final Color dotColor;
  final double spacing;
  final double dotRadius;

  const OrgDotGridBackground({
    this.dotColor = OrgSiteColors.border,
    this.spacing = 26,
    this.dotRadius = 1.4,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _OrgDotGridPainter(
          color: dotColor,
          spacing: spacing,
          dotRadius: dotRadius,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _OrgDotGridPainter extends CustomPainter {
  final Color color;
  final double spacing;
  final double dotRadius;

  _OrgDotGridPainter({
    required this.color,
    required this.spacing,
    required this.dotRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (double y = spacing / 2; y < size.height; y += spacing) {
      for (double x = spacing / 2; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), dotRadius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _OrgDotGridPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.spacing != spacing ||
      oldDelegate.dotRadius != dotRadius;
}

// A single rotated, rounded-capsule gradient bar — the "abstract diagonal
// streak" motif, in org's own warm two-tone orange instead of admin's
// orange/blue pairing (org's design language has no blue in it).
class OrgDiagonalStreak extends StatelessWidget {
  final double width;
  final double height;
  final double angle;
  final List<Color> colors;

  const OrgDiagonalStreak({
    required this.width,
    required this.height,
    required this.angle,
    required this.colors,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Transform.rotate(
        angle: angle,
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(height / 2),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: colors,
            ),
          ),
        ),
      ),
    );
  }
}

// Drop-in background for any marketing-site section — dot-grid texture
// plus four diagonal streaks fanned across the corners. `dark` swaps to a
// higher-alpha mix appropriate for the navy footer / orange CTA bands.
class OrgAbstractBackdrop extends StatelessWidget {
  final Widget child;
  final bool dark;

  const OrgAbstractBackdrop({
    required this.child,
    this.dark = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final warm = dark
        ? const [Color(0x55F97316), Color(0x00F97316)]
        : const [Color(0x30F97316), Color(0x00F97316)];
    final deep = dark
        ? const [Color(0x55EA580C), Color(0x00EA580C)]
        : const [Color(0x22EA580C), Color(0x00EA580C)];
    return ClipRect(
      child: Stack(
        children: [
          Positioned.fill(
            child: OrgDotGridBackground(
              dotColor: dark
                  ? Colors.white.withAlpha(16)
                  : OrgSiteColors.border,
            ),
          ),
          Positioned(
            top: -30,
            right: 80,
            child: OrgDiagonalStreak(
              width: 240,
              height: 24,
              angle: -0.55,
              colors: warm,
            ),
          ),
          Positioned(
            top: 60,
            right: -70,
            child: OrgDiagonalStreak(
              width: 190,
              height: 18,
              angle: -0.55,
              colors: deep,
            ),
          ),
          Positioned(
            bottom: -20,
            left: -60,
            child: OrgDiagonalStreak(
              width: 220,
              height: 22,
              angle: -0.5,
              colors: warm,
            ),
          ),
          Positioned(
            bottom: 50,
            left: 100,
            child: OrgDiagonalStreak(
              width: 160,
              height: 16,
              angle: -0.5,
              colors: deep,
            ),
          ),
          child,
        ],
      ),
    );
  }
}

// A gradient blend between two adjacent sections' background colors — the
// "connected page" seam, same as admin's.
class OrgSectionSeam extends StatelessWidget {
  final Color from;
  final Color to;
  final double height;

  const OrgSectionSeam({
    required this.from,
    required this.to,
    this.height = 56,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [from, to],
          ),
        ),
      ),
    );
  }
}

// A glowing gradient thread running the full height of the page's
// scrollable content — same literal "this is all one page" spine as admin,
// in org's own orange.
class OrgPageSpine extends StatelessWidget {
  final double left;

  const OrgPageSpine({this.left = 10, super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: 0,
      bottom: 0,
      child: IgnorePointer(
        child: Container(
          width: 3,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                OrgSiteColors.accent,
                OrgSiteColors.accentDeep,
                OrgSiteColors.accent,
                OrgSiteColors.accentDeep,
                OrgSiteColors.accent,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: OrgSiteColors.accent.withAlpha(90),
                blurRadius: 14,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Pulsing "system online" indicator — matches admin's LiveStatusBadge.
class OrgLiveStatusBadge extends StatefulWidget {
  final String label;
  final bool dark;

  const OrgLiveStatusBadge({
    this.label = 'All Systems Operational',
    this.dark = false,
    super.key,
  });

  @override
  State<OrgLiveStatusBadge> createState() => _OrgLiveStatusBadgeState();
}

class _OrgLiveStatusBadgeState extends State<OrgLiveStatusBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: widget.dark ? Colors.white.withAlpha(14) : Colors.white,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: widget.dark
              ? Colors.white.withAlpha(30)
              : OrgSiteColors.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: OrgSiteColors.success,
                boxShadow: [
                  BoxShadow(
                    color: OrgSiteColors.success.withAlpha(
                      (90 * _ctrl.value).round() + 40,
                    ),
                    blurRadius: 5 + 5 * _ctrl.value,
                    spreadRadius: 1 + _ctrl.value,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            widget.label,
            style: GoogleFonts.beVietnamPro(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: widget.dark ? Colors.white : OrgSiteColors.ink,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

// Nav bar is persistent chrome — Home/Features/About/Help swap the content
// area below it in place (AnimatedSwitcher), never a page transition.
class OrgSiteNavBar extends StatelessWidget {
  final OrgSiteSection current;
  final ValueChanged<OrgSiteSection> onSelect;
  final VoidCallback onLogin;

  const OrgSiteNavBar({
    required this.current,
    required this.onSelect,
    required this.onLogin,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Same brand strip as admin's nav — a signature line identifying
        // the page even before the logo registers.
        Container(
          height: 3,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [OrgSiteColors.accent, OrgSiteColors.accentDeep],
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(10),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: LayoutBuilder(
                builder: (_, c) {
                  final showChip = c.maxWidth >= 640;
                  final showPill = c.maxWidth >= 860;
                  return Row(
                    children: [
                      _brand(showChip),
                      const Spacer(),
                      if (showPill) ...[_navPill(), const SizedBox(width: 14)],
                      _loginButton(),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _brand(bool showChip) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onSelect(OrgSiteSection.home),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/logo.png',
                width: 34,
                height: 34,
                errorBuilder: (_, __, ___) => Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [OrgSiteColors.accentDeep, OrgSiteColors.accent],
                    ),
                  ),
                  child: const Icon(
                    Icons.domain_rounded,
                    color: Colors.white,
                    size: 17,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'UPRISE',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: OrgSiteColors.ink,
                  letterSpacing: 1.0,
                ),
              ),
              if (showChip) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: OrgSiteColors.accentDeep.withAlpha(16),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    'ORGANIZATION PORTAL',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: OrgSiteColors.accentDeep,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _navPill() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: OrgSiteColors.bg,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: OrgSiteColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _NavPillItem(
            label: 'Home',
            icon: Icons.dashboard_rounded,
            active: current == OrgSiteSection.home,
            onTap: () => onSelect(OrgSiteSection.home),
          ),
          _NavPillItem(
            label: 'Features',
            icon: Icons.grid_view_rounded,
            active: current == OrgSiteSection.features,
            onTap: () => onSelect(OrgSiteSection.features),
          ),
          _NavPillItem(
            label: 'About',
            icon: Icons.info_outline_rounded,
            active: current == OrgSiteSection.about,
            onTap: () => onSelect(OrgSiteSection.about),
          ),
          _NavPillItem(
            label: 'Help',
            icon: Icons.help_outline_rounded,
            active: current == OrgSiteSection.help,
            onTap: () => onSelect(OrgSiteSection.help),
          ),
        ],
      ),
    );
  }

  Widget _loginButton() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: OrgSiteColors.accentDeep.withAlpha(60),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [OrgSiteColors.accentDeep, OrgSiteColors.accent],
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onLogin,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Text(
                'Org Login',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavPillItem extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _NavPillItem({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  State<_NavPillItem> createState() => _NavPillItemState();
}

class _NavPillItemState extends State<_NavPillItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
          decoration: BoxDecoration(
            color: widget.active
                ? null
                : (_hovering ? Colors.white : Colors.transparent),
            gradient: widget.active
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [OrgSiteColors.accentDeep, OrgSiteColors.accent],
                  )
                : null,
            borderRadius: BorderRadius.circular(100),
            boxShadow: widget.active
                ? [
                    BoxShadow(
                      color: OrgSiteColors.accentDeep.withAlpha(70),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : (_hovering
                      ? [
                          BoxShadow(
                            color: OrgSiteColors.ink.withAlpha(15),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 14,
                color: widget.active ? Colors.white : OrgSiteColors.inkSoft,
              ),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: widget.active ? Colors.white : OrgSiteColors.inkSoft,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OrgSiteFooter extends StatelessWidget {
  final ValueChanged<OrgSiteSection> onSelect;
  final VoidCallback onTerms;

  const OrgSiteFooter({
    required this.onSelect,
    required this.onTerms,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: OrgSiteColors.navy,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: LayoutBuilder(
            builder: (_, c) {
              final wide = c.maxWidth >= 640;
              final brand = MouseRegion(
                cursor: SystemMouseCursors.click,
                child: InkWell(
                  onTap: () => onSelect(OrgSiteSection.home),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/images/logo.png',
                        width: 26,
                        height: 26,
                        errorBuilder: (_, __, ___) => Container(
                          width: 26,
                          height: 26,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                OrgSiteColors.accentDeep,
                                OrgSiteColors.accent,
                              ],
                            ),
                          ),
                          child: const Icon(
                            Icons.domain_rounded,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'UPRISE',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
              );
              final links = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: onTerms,
                    style: TextButton.styleFrom(
                      foregroundColor: OrgSiteColors.inkFaint,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: Text(
                      'Terms & Privacy',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              );
              final copyright = Text(
                '© ${DateTime.now().year} UPRISE Organization Portal',
                textAlign: wide ? TextAlign.right : TextAlign.left,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 11.5,
                  color: OrgSiteColors.inkFaint,
                  height: 1.5,
                ),
              );
              return wide
                  ? Row(
                      children: [
                        brand,
                        const SizedBox(width: 16),
                        links,
                        const Spacer(),
                        Flexible(child: copyright),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        brand,
                        const SizedBox(height: 12),
                        links,
                        const SizedBox(height: 12),
                        copyright,
                      ],
                    );
            },
          ),
        ),
      ),
    );
  }
}

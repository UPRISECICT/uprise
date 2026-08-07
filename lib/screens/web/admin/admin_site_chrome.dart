import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Shared nav bar + footer + color palette for the admin marketing site
// (Home / Features / About / Help). Kept in one file so all sections can
// never visually drift apart.
//
// Palette mirrors the REAL admin portal scheme documented in
// lib/theme/admin_theme.dart and used verbatim in admin_login.dart: gray is
// the structural primary (backgrounds, icons, borders), blue carries
// interactive/actionable elements (links, CTAs), and orange is reserved as
// a single sparing accent — not spread across every icon/badge.
class AdminSiteColors {
  static const Color primary = Color(0xFF1E293B); // slate-800, structural
  static const Color primaryLight = Color(0xFF475569);
  static const Color blue = Color(0xFF2563EB); // interactive/CTA
  static const Color blueDeep = Color(0xFF1E40AF);
  static const Color orange = Color(0xFFF97316); // sparing accent only
  static const Color navy = Color(0xFF0F172A);
  static const Color ink = Color(0xFF111827);
  static const Color inkSoft = Color(0xFF6B7280);
  static const Color inkFaint = Color(0xFFAEB4C4);
  static const Color bg = Color(0xFFF8FAFC);
  static const Color border = Color(0xFFE2E8F0);
  // Semantic — matches AdminColors.success (admin_theme.dart) exactly, used
  // only for the live-status pulse, not as a design accent.
  static const Color success = Color(0xFF10B981);
}

enum AdminSiteSection { home, features, about, help }

// Faint dot-grid texture — the one "tech dashboard" motif reused behind the
// hero and the dark researcher band, always at low alpha so it reads as
// texture, not decoration.
class DotGridBackground extends StatelessWidget {
  final Color dotColor;
  final double spacing;
  final double dotRadius;

  const DotGridBackground({
    this.dotColor = AdminSiteColors.border,
    this.spacing = 26,
    this.dotRadius = 1.4,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _DotGridPainter(
          color: dotColor,
          spacing: spacing,
          dotRadius: dotRadius,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  final Color color;
  final double spacing;
  final double dotRadius;

  _DotGridPainter({
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
  bool shouldRepaint(covariant _DotGridPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.spacing != spacing ||
      oldDelegate.dotRadius != dotRadius;
}

// Pulsing "system online" indicator — genuinely on-theme for an admin
// console rather than arbitrary decoration.
class LiveStatusBadge extends StatefulWidget {
  final String label;
  final bool dark;

  const LiveStatusBadge({
    this.label = 'All Systems Operational',
    this.dark = false,
    super.key,
  });

  @override
  State<LiveStatusBadge> createState() => _LiveStatusBadgeState();
}

class _LiveStatusBadgeState extends State<LiveStatusBadge>
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
              : AdminSiteColors.border,
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
                color: AdminSiteColors.success,
                boxShadow: [
                  BoxShadow(
                    color: AdminSiteColors.success.withAlpha(
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
              color: widget.dark ? Colors.white : AdminSiteColors.ink,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

// Nav bar is persistent chrome — Home/Features/About/Help swap the content
// area below it in place (AnimatedSwitcher), never a page transition, so
// "clicking a link" always feels like toggling a tab on the same page.
class AdminSiteNavBar extends StatelessWidget {
  final AdminSiteSection current;
  final ValueChanged<AdminSiteSection> onSelect;
  final VoidCallback onLogin;

  const AdminSiteNavBar({
    required this.current,
    required this.onSelect,
    required this.onLogin,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
          // Decisions are driven by the width actually available to this
          // row (post-padding, post-1180-cap) rather than raw screen
          // width — that mismatch is exactly what let the pill claim more
          // room than existed and clip/overflow at mid-range widths.
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
    );
  }

  Widget _brand(bool showChip) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onSelect(AdminSiteSection.home),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _GlowLogo(
                child: Image.asset(
                  'assets/images/logo.png',
                  width: 34,
                  height: 34,
                  errorBuilder: (_, __, ___) => Container(
                    width: 34,
                    height: 34,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AdminSiteColors.primary,
                    ),
                    child: const Icon(
                      Icons.shield_rounded,
                      color: Colors.white,
                      size: 17,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'UPRISE',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AdminSiteColors.ink,
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
                    color: AdminSiteColors.primary.withAlpha(16),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    'ADMIN PORTAL',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: AdminSiteColors.primary,
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
        color: AdminSiteColors.bg,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: AdminSiteColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _NavPillItem(
            label: 'Home',
            icon: Icons.dashboard_rounded,
            active: current == AdminSiteSection.home,
            onTap: () => onSelect(AdminSiteSection.home),
          ),
          _NavPillItem(
            label: 'Features',
            icon: Icons.grid_view_rounded,
            active: current == AdminSiteSection.features,
            onTap: () => onSelect(AdminSiteSection.features),
          ),
          _NavPillItem(
            label: 'About',
            icon: Icons.info_outline_rounded,
            active: current == AdminSiteSection.about,
            onTap: () => onSelect(AdminSiteSection.about),
          ),
          _NavPillItem(
            label: 'Help',
            icon: Icons.help_outline_rounded,
            active: current == AdminSiteSection.help,
            onTap: () => onSelect(AdminSiteSection.help),
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
            color: AdminSiteColors.blue.withAlpha(60),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onLogin,
        style: ElevatedButton.styleFrom(
          backgroundColor: AdminSiteColors.blue,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(
          'Admin Login',
          style: GoogleFonts.beVietnamPro(
            fontSize: 13,
            fontWeight: FontWeight.w700,
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
                ? AdminSiteColors.primary
                : (_hovering ? Colors.white : Colors.transparent),
            borderRadius: BorderRadius.circular(100),
            boxShadow: widget.active
                ? [
                    BoxShadow(
                      color: AdminSiteColors.primary.withAlpha(70),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 14,
                color: widget.active ? Colors.white : AdminSiteColors.inkSoft,
              ),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: widget.active ? Colors.white : AdminSiteColors.inkSoft,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Subtle hover lift + glow on the wordmark logo — a small "alive" touch on
// the one element present on every page.
class _GlowLogo extends StatefulWidget {
  final Widget child;

  const _GlowLogo({required this.child});

  @override
  State<_GlowLogo> createState() => _GlowLogoState();
}

class _GlowLogoState extends State<_GlowLogo> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedScale(
        scale: _hovering ? 1.12 : 1.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: _hovering
                ? [
                    BoxShadow(
                      color: AdminSiteColors.blue.withAlpha(90),
                      blurRadius: 16,
                      spreadRadius: 1,
                    ),
                  ]
                : [],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class AdminSiteFooter extends StatelessWidget {
  final ValueChanged<AdminSiteSection> onSelect;
  final VoidCallback onTerms;

  const AdminSiteFooter({
    required this.onSelect,
    required this.onTerms,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AdminSiteColors.navy,
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
                  onTap: () => onSelect(AdminSiteSection.home),
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
                            color: AdminSiteColors.primaryLight,
                          ),
                          child: const Icon(
                            Icons.shield_rounded,
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
                  for (final l in [
                    ('About', () => onSelect(AdminSiteSection.about)),
                    ('Help', () => onSelect(AdminSiteSection.help)),
                    ('Terms & Privacy', onTerms),
                  ])
                    TextButton(
                      onPressed: l.$2,
                      style: TextButton.styleFrom(
                        foregroundColor: AdminSiteColors.inkFaint,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: Text(
                        l.$1,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              );
              final copyright = Text(
                '© ${DateTime.now().year} UPRISE · Bulacan State University',
                textAlign: wide ? TextAlign.right : TextAlign.left,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 11.5,
                  color: AdminSiteColors.inkFaint,
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

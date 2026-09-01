// lib/widgets/org_modal_shell.dart
//
// Shared modal shell for org web screens — colored icon-badge header with
// title/subtitle/close button, a light-gray scrollable body (so section
// cards inside read as distinct cards instead of blending into a flat white
// background), and an optional footer action bar. Every org modal was
// hand-rolling this same structure with small inconsistencies (some had a
// gray body, some didn't; some sectioned their fields into cards, some just
// had one flat list) — this is the one place that structure lives now, so
// fixing or restyling it updates every modal that uses it at once.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class OrgModalShell extends StatelessWidget {
  final Color accentColor;
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;
  final Widget body;
  final List<Widget>? footerActions;
  final double width;
  final double maxHeightFraction;
  /// Optional full-width header color for workflows that need a stronger
  /// visual identity than the default white modal header.
  final Color? headerColor;
  /// Uses a shorter, left-aligned icon/title header. Useful for multi-step
  /// workflows where preserving vertical room for the form matters.
  final bool compactHeader;
  final VoidCallback? onClose;
  final bool closeEnabled;

  const OrgModalShell({
    super.key,
    required this.accentColor,
    required this.icon,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    required this.body,
    this.footerActions,
    this.width = 540,
    this.maxHeightFraction = 0.85,
    this.headerColor,
    this.compactHeader = false,
    this.onClose,
    this.closeEnabled = true,
  });

  Widget _buildCompactHeader(BuildContext context) {
    final isColored = headerColor != null;
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: isColored
                ? Colors.white.withAlpha(34)
                : accentColor.withAlpha(24),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(
            icon,
            color: isColored ? Colors.white : accentColor,
            size: 24,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: isColored ? Colors.white : const Color(0xFF1A202C),
                ),
              ),
              if (subtitleWidget != null) ...[
                const SizedBox(height: 4),
                subtitleWidget!,
              ] else if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12,
                    color: isColored
                        ? Colors.white.withAlpha(210)
                        : const Color(0xFF64748B),
                  ),
                ),
              ],
            ],
          ),
        ),
        IconButton(
          tooltip: 'Close',
          icon: Icon(
            Icons.close_rounded,
            color: isColored ? Colors.white : const Color(0xFF64748B),
            size: 21,
          ),
          onPressed: closeEnabled
              ? (onClose ?? () => Navigator.pop(context))
              : null,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: width,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * maxHeightFraction,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Color(0x330F172A),
              blurRadius: 32,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(28, 14, 28, 24),
              decoration: BoxDecoration(
                color: headerColor ?? Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: compactHeader
                  ? _buildCompactHeader(context)
                  : Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 22),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: headerColor == null
                                ? accentColor.withAlpha(24)
                                : Colors.white.withAlpha(34),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                              color: headerColor == null
                                  ? accentColor.withAlpha(28)
                                  : Colors.black.withAlpha(22),
                                blurRadius: 20,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: Icon(
                            icon,
                            color: headerColor == null
                                ? accentColor
                                : Colors.white,
                            size: 30,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: headerColor == null
                                ? const Color(0xFF1A202C)
                                : Colors.white,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitleWidget != null) ...[
                          const SizedBox(height: 6),
                          subtitleWidget!,
                        ] else if (subtitle != null && subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            subtitle!,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 13,
                              height: 1.45,
                                color: headerColor == null
                                    ? const Color(0xFF64748B)
                                    : Colors.white.withAlpha(210),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: -8,
                    child: IconButton(
                      tooltip: 'Close',
                      icon: Icon(
                        Icons.close_rounded,
                        color: headerColor == null
                            ? const Color(0xFF64748B)
                            : Colors.white,
                        size: 20,
                      ),
                      onPressed: closeEnabled
                          ? (onClose ?? () => Navigator.pop(context))
                          : null,
                    ),
                  ),
                ],
              ),
            ),
            // Flexible (not Expanded) so a modal with short content — e.g.
            // a report with no attached transactions — shrinks to fit
            // instead of leaving a dead gray gap between the content and
            // the footer. Content taller than maxHeightFraction still gets
            // capped and scrolls exactly as before.
            Flexible(
              child: Container(color: Colors.white, child: body),
            ),
            if (footerActions != null && footerActions!.isNotEmpty)
              Container(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFFE8ECF0))),
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(20),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: footerActions!,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A section card used inside [OrgModalShell]'s body — white card with a
/// colored accent bar + title. Used to badge every icon in a boxed icon
/// container next to the title; with every modal having 3-4 sections plus
/// an [OrgDetailItem] icon badge on every row inside them, that added up to
/// a wall of near-identical icon badges. A colored left accent bar carries
/// the same "this section belongs to this color" signal without another
/// icon — the [icon] param is kept (existing call sites all still pass
/// one) but intentionally unused now.
class OrgModalSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accentColor;
  final Widget child;
  final bool required;

  const OrgModalSection({
    super.key,
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.child,
    this.required = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8ECF0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 15,
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Text.rich(
                  TextSpan(
                    text: title,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: accentColor,
                      letterSpacing: 0.3,
                    ),
                    children: required
                        ? [
                            TextSpan(
                              text: ' *',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFFDC2626),
                              ),
                            ),
                          ]
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Divider(color: const Color(0xFFE2E6EA), thickness: 1),
                ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// A label/value detail row for read-only "View Details"-style modals — a
/// faint uppercase label above a bold value, with a thin colored accent bar
/// standing in for what used to be a full icon-in-box badge on every single
/// row (a 6-row detail modal meant 6 near-identical badges — pure repeated
/// noise, not 6 pieces of new information). The accent bar still carries
/// [iconColor]'s meaning (e.g. red for an overdue amount) so rows stay
/// colorful without the icon clutter. [icon] is kept for existing call
/// sites but intentionally unused now.
class OrgDetailItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;
  final Color? valueColor;

  const OrgDetailItem({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.iconColor = const Color(0xFF9AA5B4),
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 3,
          height: 30,
          margin: const EdgeInsets.only(top: 1),
          decoration: BoxDecoration(
            color: iconColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF9AA5B4),
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: valueColor ?? const Color(0xFF1A202C),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

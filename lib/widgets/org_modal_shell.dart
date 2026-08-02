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
    this.onClose,
    this.closeEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Container(
        width: width,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * maxHeightFraction,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 20, 20),
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(18),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(38),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitleWidget != null)
                          subtitleWidget!
                        else if (subtitle != null && subtitle!.isNotEmpty)
                          Text(
                            subtitle!,
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 12,
                              color: Colors.white.withAlpha(179),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    onPressed: closeEnabled
                        ? (onClose ?? () => Navigator.pop(context))
                        : null,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(color: const Color(0xFFF8F9FB), child: body),
            ),
            if (footerActions != null && footerActions!.isNotEmpty)
              Container(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFFE8ECF0))),
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(18),
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
/// colored icon badge + title, matching the section-label pattern already
/// used across org screens.
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
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: accentColor.withAlpha(28),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(icon, size: 14, color: accentColor),
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
/// small colored icon badge, faint label, and bold value. Deliberately
/// avoids combining a non-uniform Border with a borderRadius on its own
/// decoration (that combination throws a paint-time FlutterError unless
/// every visible side is the same color — see org_letter_request.dart's
/// history for the exact bug this caused).
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
          width: 26,
          height: 26,
          margin: const EdgeInsets.only(top: 1),
          decoration: BoxDecoration(
            color: iconColor.withAlpha(28),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, size: 13, color: iconColor),
        ),
        const SizedBox(width: 10),
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

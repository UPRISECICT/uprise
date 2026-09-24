import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'landing_common.dart';
import 'landing_palette.dart';

class FooterLink {
  final String label;
  final VoidCallback onTap;

  const FooterLink(this.label, this.onTap);
}

class LandingFooter extends StatelessWidget {
  final LandingPalette palette;
  final String tagline;
  final List<FooterLink> links;

  const LandingFooter({
    required this.palette,
    required this.tagline,
    required this.links,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.of(context).size.width < 760;
    final brand = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LandingLogo(palette: palette, dark: true),
        const SizedBox(height: 14),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Text(
            tagline,
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              height: 1.6,
              color: Colors.white.withAlpha(150),
            ),
          ),
        ),
      ],
    );
    final linkRow = Wrap(
      spacing: 26,
      runSpacing: 12,
      children: [
        for (final l in links)
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: l.onTap,
              child: Text(
                l.label,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withAlpha(200),
                ),
              ),
            ),
          ),
      ],
    );

    return Container(
      color: palette.bandTop,
      child: LandingContainer(
        padding: const EdgeInsets.symmetric(vertical: 44),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            narrow
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [brand, const SizedBox(height: 26), linkRow],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: brand),
                      const SizedBox(width: 40),
                      linkRow,
                    ],
                  ),
            const SizedBox(height: 30),
            Divider(color: Colors.white.withAlpha(24), height: 1),
            const SizedBox(height: 20),
            Text(
              '© ${DateTime.now().year} UPRISE · College of Information and '
              'Communications Technology · Bulacan State University',
              style: GoogleFonts.beVietnamPro(
                fontSize: 12,
                color: Colors.white.withAlpha(120),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

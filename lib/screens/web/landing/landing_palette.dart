import 'package:flutter/material.dart';

import '../admin/admin_site_chrome.dart';
import '../org/org_site_chrome.dart';

// One palette shape for both portal landing pages, so every shared landing
// component (navbar, hero, cards, stories, CTA, footer) is written once and
// the admin and org pages differ only in the palette + copy they pass in.
// Values alias the portals' existing site colors (admin_site_chrome.dart /
// org_site_chrome.dart) rather than introducing new brand hexes.
class LandingPalette {
  /// Interactive / CTA color.
  final Color primary;
  final Color primaryDeep;

  /// Sparing warm accent (the UPRISE orange).
  final Color accent;
  final Color ink;
  final Color inkSoft;
  final Color inkFaint;

  /// Page background and the pale tint used behind preview visuals.
  final Color bg;
  final Color tint;
  final Color border;

  /// Dark brand band (overview / workflow / CTA / footer) gradient.
  final Color bandTop;
  final Color bandBottom;
  final Color success;

  /// Small pill next to the logo, e.g. "ADMINISTRATOR PORTAL".
  final String portalLabel;

  const LandingPalette({
    required this.primary,
    required this.primaryDeep,
    required this.accent,
    required this.ink,
    required this.inkSoft,
    required this.inkFaint,
    required this.bg,
    required this.tint,
    required this.border,
    required this.bandTop,
    required this.bandBottom,
    required this.success,
    required this.portalLabel,
  });

  static const admin = LandingPalette(
    primary: AdminSiteColors.blue,
    primaryDeep: AdminSiteColors.blueDeep,
    accent: AdminSiteColors.orange,
    ink: AdminSiteColors.ink,
    inkSoft: AdminSiteColors.inkSoft,
    inkFaint: AdminSiteColors.inkFaint,
    bg: AdminSiteColors.bg,
    tint: Color(0xFFEFF4FF),
    border: AdminSiteColors.border,
    bandTop: AdminSiteColors.navy,
    bandBottom: Color(0xFF172554),
    success: AdminSiteColors.success,
    portalLabel: 'ADMINISTRATOR PORTAL',
  );

  static const org = LandingPalette(
    primary: OrgSiteColors.accentDeep,
    primaryDeep: Color(0xFFC2410C),
    accent: OrgSiteColors.accent,
    ink: OrgSiteColors.ink,
    inkSoft: OrgSiteColors.inkSoft,
    inkFaint: OrgSiteColors.inkFaint,
    bg: OrgSiteColors.bg,
    tint: Color(0xFFFFF4EA),
    border: OrgSiteColors.border,
    bandTop: OrgSiteColors.slateDark,
    bandBottom: Color(0xFF3A1A08),
    success: OrgSiteColors.success,
    portalLabel: 'ORGANIZATION PORTAL',
  );
}

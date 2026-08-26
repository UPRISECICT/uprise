// lib/widgets/common/organization_card.dart
//
// The organization tiles a Home screen shows.
//
// Extracted from student_home_screen.dart so guest Home can render the same
// sections. Both were already presentation-only with plain parameters — the
// only change is that the private `_UiTokens` aliases they referenced are
// resolved to their AppColors sources here.
//
// MyOrgPreviewTile used to live here too, rendering a student's own org (and,
// for guests, the orgs they followed). Both Home screens dropped that section
// when following was removed — membership now shows up only in the Orgs tab,
// as a pill on the org's card and as the pinned block at the top of the feed.

import 'package:flutter/material.dart';

import '../student/app_colors.dart';
import '../student/app_image.dart';

const double _kOrgLogoSize = 68;
const double _kOrgLogoGap = 6;
const double _kOrgNameFontSize = 11.5;
const int _kOrgNameMaxLines = 2;

/// Horizontal rail of [OrgPreviewCard]s that sizes itself.
///
/// Deliberately a scrolling Row rather than a `SizedBox(height:) > ListView` —
/// the card is a fixed logo over a two-line name, so its height moves with the
/// system font size, and a fixed rail height cannot be right at every scale.
/// The flat 108 both Home screens used overflowed as soon as the font was
/// bumped, and two attempts at a scaled formula were still off by 2px, because
/// it depends on font metrics rather than a clean multiple. Letting the Row
/// take its intrinsic height removes the guess entirely.
///
/// Not lazy, unlike ListView.builder — fine here because the callers already
/// hold the whole org list in memory and it is a short list.
class OrgPreviewRail extends StatelessWidget {
  final List<Widget> children;

  const OrgPreviewRail({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

/// Square logo tile for the horizontal "Organizations for you" rail.
class OrgPreviewCard extends StatelessWidget {
  final String name;
  final String? logoUrl;
  final VoidCallback onTap;

  const OrgPreviewCard({
    super.key,
    required this.name,
    required this.logoUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final logoImage = AppImage.provider(logoUrl ?? '');
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 84,
        child: Column(
          children: [
            Container(
              width: _kOrgLogoSize,
              height: _kOrgLogoSize,
              decoration: BoxDecoration(
                color: AppColors.primaryDark.withAlpha(20),
                borderRadius: BorderRadius.circular(18),
                image: logoImage != null
                    ? DecorationImage(image: logoImage, fit: BoxFit.cover)
                    : null,
              ),
              child: logoImage == null
                  ? Center(
                      child: Text(
                        initial,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: _kOrgLogoGap),
            Text(
              name,
              style: const TextStyle(
                fontSize: _kOrgNameFontSize,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
              maxLines: _kOrgNameMaxLines,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

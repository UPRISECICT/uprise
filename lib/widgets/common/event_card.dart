// lib/widgets/common/event_card.dart
//
// The event card, in its full and compact forms.
//
// Extracted from student's _UpcomingEventCard / _CompactUpcomingCard. Guest had
// its own pair (_FeaturedCard / _CompactCard) built as a photo banner under a
// dark gradient scrim with white text on top — which read as a near-black card
// in practice, because guest's FirestoreEvent carries no image field at all and
// the banner always fell through to its placeholder. Both sides now render the
// student treatment: a white card, dark text, image banner above.
//
// Presentation-only, like feed_cards.dart: takes an EventCardData struct rather
// than student's EventModel or guest's FirestoreEvent, so neither side's domain
// model leaks in here. Callers map their own object at the call site.
//
// Banner images go through EventImage, which already resolves data: URIs, raw
// base64 and Firebase Storage URLs (with auth when a user is signed in) and
// falls back to its own placeholder on empty — so a caller with no image, which
// is every guest event, just passes ''.

import 'package:flutter/material.dart';

import '../student/app_colors.dart';
import '../student/event_image.dart';
import 'event_badges.dart';

/// What a card needs to render. All strings are pre-formatted for display —
/// this file does no date math.
class EventCardData {
  final String title;
  final String category;

  /// Empty is fine — EventImage renders its placeholder.
  final String imageUrl;

  final String dateLabel;
  final String timeLabel;
  final String location;

  /// Shown by the Home carousel card, ignored by the list/grid cards — those
  /// already sit under an org-scoped heading.
  final String orgName;

  const EventCardData({
    required this.title,
    required this.category,
    required this.dateLabel,
    this.timeLabel = '',
    this.imageUrl = '',
    this.location = '',
    this.orgName = '',
  });
}

/// Full-width event card: banner, badge row, title, date/time and location
/// meta, then a primary action button.
class EventCard extends StatelessWidget {
  final EventCardData data;
  final VoidCallback onTap;

  /// Swaps the action button to green and shows a "Registered" chip.
  final bool isRegistered;

  final bool showLiveBadge;
  final bool showSoonBadge;

  /// Pinned to the bottom of the banner. The student side passes its webinar
  /// code banner here; anything Firestore-backed stays out of this file and
  /// comes in through this slot.
  final Widget? bannerOverlay;

  /// Omit the action button entirely by passing null — guest's list cards use
  /// the whole card as the tap target and don't need one.
  final String? actionLabel;

  const EventCard({
    super.key,
    required this.data,
    required this.onTap,
    this.isRegistered = false,
    this.showLiveBadge = false,
    this.showSoonBadge = false,
    this.bannerOverlay,
    this.actionLabel = 'View Details',
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(20),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                EventImage(
                  imageUrl: data.imageUrl,
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  showLoadingIndicator: true,
                ),
                if (showLiveBadge)
                  const Positioned(top: 10, left: 10, child: LiveBadge()),
                if (bannerOverlay != null)
                  Positioned(
                    right: 10,
                    bottom: 10,
                    left: 10,
                    child: bannerOverlay!,
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CategoryBadge(category: data.category),
                      if (showSoonBadge) ...[
                        const SizedBox(width: 6),
                        const SoonBadge(),
                      ],
                      const Spacer(),
                      if (isRegistered) const _RegisteredChip(),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    data.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const _MetaIcon(Icons.calendar_today_outlined),
                      Text(
                        data.dateLabel,
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      if (data.timeLabel.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        const _MetaIcon(Icons.access_time),
                        Expanded(
                          child: Text(
                            data.timeLabel,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (data.location.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const _MetaIcon(Icons.location_on_outlined),
                        Expanded(
                          child: Text(
                            data.location,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (actionLabel != null) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: onTap,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isRegistered
                              ? Colors.green
                              : AppColors.primaryDark,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                        ),
                        child: Text(
                          isRegistered ? 'Registered ✓' : actionLabel!,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Grid variant: shorter banner, two-line title, no location row, small action.
///
/// Sized to fill its grid cell — give it a bounded height (the events grid uses
/// `childAspectRatio: 0.72`), since the content column ends in a Spacer.
class CompactEventCard extends StatelessWidget {
  final EventCardData data;
  final VoidCallback onTap;
  final bool isRegistered;
  final bool showLiveBadge;
  final String? actionLabel;

  const CompactEventCard({
    super.key,
    required this.data,
    required this.onTap,
    this.isRegistered = false,
    this.showLiveBadge = false,
    this.actionLabel = 'View',
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(20),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                EventImage(
                  imageUrl: data.imageUrl,
                  height: 90,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  showLoadingIndicator: true,
                ),
                if (showLiveBadge)
                  const Positioned(top: 6, left: 6, child: LiveBadge()),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _CompactMetaRow(
                      icon: Icons.calendar_today_outlined,
                      text: data.dateLabel,
                    ),
                    if (data.timeLabel.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      _CompactMetaRow(
                        icon: Icons.access_time,
                        text: data.timeLabel,
                      ),
                    ],
                    const Spacer(),
                    if (actionLabel != null)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: onTap,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isRegistered
                                ? Colors.green
                                : AppColors.primaryDark,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(
                            isRegistered ? 'Registered' : actionLabel!,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RegisteredChip extends StatelessWidget {
  const _RegisteredChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green.withAlpha(26),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 12, color: Colors.green),
          SizedBox(width: 4),
          Text(
            'Registered',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.green,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaIcon extends StatelessWidget {
  final IconData icon;
  const _MetaIcon(this.icon);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 4),
    child: Icon(icon, size: 12, color: Colors.grey),
  );
}

class _CompactMetaRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _CompactMetaRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 11, color: Colors.grey),
        const SizedBox(width: 3),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 10, color: Colors.grey),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

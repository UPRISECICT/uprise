// lib/widgets/common/home_sections.dart
//
// The Home dashboard's section widgets: the upcoming-events carousel, the
// quick-action shortcut, the merchandise rail card, and the card decoration
// they share.
//
// Extracted from student_home_screen.dart so guest Home renders the same
// dashboard instead of its own merged-feed layout. The private `_UiTokens`
// aliases these referenced are resolved to their AppColors sources here.
//
// UpcomingEventsCarousel takes EventCardData (from event_card.dart) rather
// than either side's domain model — the guest event type has no image field
// and a different audience gate, so keeping the model out of here is what lets
// both feed it. Note the struct's contract: every string is pre-formatted by
// the caller, so this file does no date math. The carousel wants a combined
// "Fri, Aug 30 · 4:00 PM" in `dateLabel`, where the events list passes
// "August 30, 2026" to the same field.

import 'package:flutter/material.dart';

import '../student/app_colors.dart';
import '../student/app_image.dart';
import 'event_card.dart';
import 'feed_cards.dart' show feedCategoryColor;

/// White card with a hairline border and a soft shadow — the Home surface.
///
/// Distinct from `kCardDecoration` in action_tile.dart, which has no border
/// and a tighter shadow; that one is for settings/profile rows.
BoxDecoration homeCardDecoration({double radius = 12}) => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: AppColors.divider, width: 1),
  boxShadow: [
    BoxShadow(
      color: Colors.black.withAlpha(13),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ],
);

/// Compact icon shortcut for the quick-actions sheet.
class HomeQuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const HomeQuickAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.primaryDark.withAlpha(20),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: AppColors.primaryDark, size: 21),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// One product in the horizontal merchandise rail.
class MerchPreviewCard extends StatelessWidget {
  final String name;
  final double price;
  final String imageBase64;
  final VoidCallback onTap;

  const MerchPreviewCard({
    super.key,
    required this.name,
    required this.price,
    required this.imageBase64,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 132,
        decoration: homeCardDecoration(),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            imageBase64.isNotEmpty
                ? AppImage(
                    source: imageBase64,
                    height: 90,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    placeholderBackgroundColor: AppColors.primaryDark.withAlpha(
                      26,
                    ),
                    placeholderIconColor: Colors.grey,
                    placeholderIconSize: 40,
                  )
                : Container(
                    height: 90,
                    width: double.infinity,
                    color: AppColors.primaryDark.withAlpha(20),
                    child: const Icon(
                      Icons.shopping_bag_outlined,
                      color: AppColors.primaryDark,
                      size: 28,
                    ),
                  ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isNotEmpty ? name : 'Product',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '₱${price.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Swipeable one-card-at-a-time carousel with arrow nav and a dot indicator.
class UpcomingEventsCarousel extends StatefulWidget {
  final List<EventCardData> events;
  final void Function(int index) onTap;

  const UpcomingEventsCarousel({
    super.key,
    required this.events,
    required this.onTap,
  });

  @override
  State<UpcomingEventsCarousel> createState() => _UpcomingEventsCarouselState();
}

class _UpcomingEventsCarouselState extends State<UpcomingEventsCarousel> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goToPage(int page) {
    _controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Widget _navArrow({required IconData icon, required VoidCallback? onTap}) {
    return Opacity(
      opacity: onTap != null ? 1 : 0.35,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 3,
        shadowColor: Colors.black26,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(icon, size: 18, color: AppColors.primaryDark),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.events.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              // Grows with the text scale so the banner isn't squeezed to make
              // room for larger meta lines. 350 at 1.0x — the original value —
              // rising to ~376 at the 1.6x cap. The card can't overflow either
              // way; this only decides how much is left for the image.
              height:
                  306 +
                  44 *
                      MediaQuery.textScalerOf(
                        context,
                      ).scale(1).clamp(1.0, 1.6),
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                itemCount: widget.events.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _CarouselEventCard(
                      data: widget.events[index],
                      onTap: () => widget.onTap(index),
                    ),
                  );
                },
              ),
            ),
            if (widget.events.length > 1) ...[
              Positioned(
                left: 6,
                child: _navArrow(
                  icon: Icons.chevron_left,
                  onTap: _page > 0 ? () => _goToPage(_page - 1) : null,
                ),
              ),
              Positioned(
                right: 6,
                child: _navArrow(
                  icon: Icons.chevron_right,
                  onTap: _page < widget.events.length - 1
                      ? () => _goToPage(_page + 1)
                      : null,
                ),
              ),
            ],
          ],
        ),
        // A single upcoming event needs no page indicator.
        if (widget.events.length > 1) ...[
          const SizedBox(height: 8),
          // Scrollable rather than a plain centered Row — the upcoming list
          // has no hard cap, so a long run of dots could overflow the width.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(widget.events.length, (i) {
                final active = i == _page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 18 : 6,
                  height: 10,
                  decoration: BoxDecoration(
                    color: active
                        ? AppColors.primaryDark
                        : AppColors.primaryDark.withAlpha(51),
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ),
        ],
      ],
    );
  }
}

/// One page of [UpcomingEventsCarousel]: a tall banner, then a category-tinted
/// date row, the title, and location/org meta lines.
class _CarouselEventCard extends StatelessWidget {
  final EventCardData data;
  final VoidCallback onTap;

  const _CarouselEventCard({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final catColor = feedCategoryColor(data.category);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(20),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The banner takes whatever the text leaves, instead of claiming a
            // fixed 200. PageView hands this card a tight height while the meta
            // lines below grow with the system font size, so a rigid banner
            // overflowed the card at 1.5x. Expanded (tight) rather than
            // Flexible (loose) — loose still lets a fixed-size child refuse to
            // shrink, which is why the first attempt at this didn't take.
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: double.infinity,
                  child: data.imageUrl.isNotEmpty
                      ? AppImage(
                          source: data.imageUrl,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          placeholderBackgroundColor: AppColors.primaryDark
                              .withAlpha(26),
                          placeholderIconColor: Colors.grey,
                          placeholderIconSize: 40,
                        )
                      : Container(
                          color: AppColors.primaryDark.withAlpha(31),
                          child: const Center(
                            child: Icon(
                              Icons.image_outlined,
                              color: AppColors.primaryDark,
                              size: 32,
                            ),
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.access_time_rounded, size: 13, color: catColor),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    data.dateLabel,
                    style: TextStyle(
                      fontSize: 12,
                      color: catColor,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: catColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              data.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
            if (data.location.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              _MetaLine(
                icon: Icons.location_on_outlined,
                text: data.location.trim(),
              ),
            ],
            if (data.orgName.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              _MetaLine(
                icon: Icons.groups_outlined,
                text: data.orgName.trim(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MetaLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 13, color: Colors.grey),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

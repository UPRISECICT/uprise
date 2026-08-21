// lib/widgets/common/feed_cards.dart
//
// Shared "content feed" presentation widgets used by both student and
// guest Home screens (originally built for guest's social-feed layout,
// extracted here so student's Home can render the same rich card style).
//
// Deliberately presentation-only: each card takes a small data struct
// (FeedEventCardData / FeedAnnouncementCardData) instead of either
// screen's own domain model, so this file has no dependency on
// guest-specific audience-filtering/query concepts or on student's
// EventModel/AnnouncementData — callers map their own objects into these
// structs right before building the card.

import 'package:flutter/material.dart';
import '../student/app_colors.dart';
import '../student/app_image.dart';

// ─────────────────────────────────────────────────────────────
//  CATEGORY COLOUR MAP
// ─────────────────────────────────────────────────────────────
const kFeedCategoryColors = <String, Color>{
  'Workshop': Color(0xFF8B5CF6),
  'Seminar': Color(0xFF3B82F6),
  'Competition': Color(0xFFEF4444),
  'General Assembly': Color(0xFFF97316),
  'Social': Color(0xFFEC4899),
  'Outreach': Color(0xFF10B981),
  'Sports': Color(0xFF14B8A6),
  'Academic': Color(0xFF6366F1),
  'Technical': Color(0xFF06B6D4),
  'Cultural': Color(0xFFD946EF),
};
Color feedCategoryColor(String cat) =>
    kFeedCategoryColors[cat] ?? const Color(0xFF6B7280);

const kFeedCategoryIcons = <String, IconData>{
  'Workshop': Icons.build_rounded,
  'Seminar': Icons.record_voice_over_rounded,
  'Competition': Icons.emoji_events_rounded,
  'General Assembly': Icons.groups_rounded,
  'Social': Icons.celebration_rounded,
  'Outreach': Icons.volunteer_activism_rounded,
  'Sports': Icons.sports_basketball_rounded,
  'Academic': Icons.school_rounded,
  'Technical': Icons.memory_rounded,
  'Cultural': Icons.theater_comedy_rounded,
};
IconData feedCategoryIcon(String cat) =>
    kFeedCategoryIcons[cat] ?? Icons.category_rounded;

// ─────────────────────────────────────────────────────────────
//  SHARED CARD IMAGE BANNER  (full-width, gradient placeholder)
// ─────────────────────────────────────────────────────────────
class CardImageBanner extends StatelessWidget {
  final String imageBase64; // may be empty — shows placeholder
  final String orgName; // used to pick placeholder gradient
  final String badgeLabel; // e.g. "NEW" / "POPULAR" / "UPCOMING"
  final Color badgeColor;
  final double height;

  const CardImageBanner({
    super.key,
    required this.imageBase64,
    required this.orgName,
    required this.badgeLabel,
    required this.badgeColor,
    this.height = 190,
  });

  // Deterministic gradient from the org name hash
  List<Color> get _gradientColors {
    final hash = orgName.hashCode.abs();
    const palettes = [
      [Color(0xFF1A237E), Color(0xFF283593)],
      [Color(0xFF4A148C), Color(0xFF6A1B9A)],
      [Color(0xFF880E4F), Color(0xFFC2185B)],
      [Color(0xFF1B5E20), Color(0xFF2E7D32)],
      [Color(0xFF0D47A1), Color(0xFF1565C0)],
      [Color(0xFF37474F), Color(0xFF546E7A)],
      [Color(0xFFBF360C), Color(0xFFE64A19)],
      [Color(0xFF006064), Color(0xFF00838F)],
    ];
    return palettes[hash % palettes.length];
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Background: real image or gradient placeholder ──
          // AppImage understands base64 (with or without a data: URI
          // prefix) and http(s) URLs alike — guest's imageBase64 is always
          // raw base64, but student's announcement images can be either.
          if (imageBase64.isNotEmpty)
            AppImage(
              source: imageBase64,
              width: double.infinity,
              height: height,
              fit: BoxFit.cover,
              showLoadingIndicator: false,
              placeholder: GradientPlaceholder(
                colors: _gradientColors,
                initial: orgName.isNotEmpty ? orgName[0].toUpperCase() : '?',
              ),
            )
          else
            GradientPlaceholder(
              colors: _gradientColors,
              initial: orgName.isNotEmpty ? orgName[0].toUpperCase() : '?',
            ),

          // ── Subtle bottom scrim so text below stays readable ──
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withAlpha(89), Colors.transparent],
                ),
              ),
            ),
          ),

          // ── Status badge top-left ──────────────────────────
          if (badgeLabel.isNotEmpty)
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(64),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  badgeLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

}

class GradientPlaceholder extends StatelessWidget {
  final List<Color> colors;
  final String initial;
  const GradientPlaceholder({super.key, required this.colors, required this.initial});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: 72,
            fontWeight: FontWeight.w900,
            color: Colors.white.withAlpha(31),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  MINI CHIP  (audience badge)
// ─────────────────────────────────────────────────────────────
class MiniChip extends StatelessWidget {
  final String label;
  final Color color;
  const MiniChip({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  EMPTY SECTION  (inline placeholder row)
// ─────────────────────────────────────────────────────────────
class EmptyFeedSection extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color accent;
  final Color accentBg;

  const EmptyFeedSection({
    super.key,
    required this.icon,
    required this.message,
    this.accent = AppColors.primaryDark,
    this.accentBg = AppColors.primarySoft,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDEDEF)),
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: accentBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, size: 24, color: accent),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.black54,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  EVENT FEED CARD
// ─────────────────────────────────────────────────────────────
class FeedEventCardData {
  final String title;
  final String orgName;
  final String imageBase64;
  final String category;
  final String location;
  final String audience;
  final DateTime? eventDate;
  final DateTime createdAt;

  const FeedEventCardData({
    required this.title,
    required this.orgName,
    this.imageBase64 = '',
    this.category = 'Other',
    this.location = '',
    this.audience = 'Public',
    this.eventDate,
    required this.createdAt,
  });
}

class FeedEventCard extends StatelessWidget {
  final FeedEventCardData data;
  final VoidCallback onTap;
  final VoidCallback? onShare;
  final Color accent;
  final Color accentBg;

  const FeedEventCard({
    super.key,
    required this.data,
    required this.onTap,
    this.onShare,
    this.accent = AppColors.primaryDark,
    this.accentBg = AppColors.primarySoft,
  });

  bool get _isSoon {
    final d = data.eventDate;
    if (d == null) return false;
    final now = DateTime.now();
    return d.difference(now).inDays <= 7 && d.isAfter(now);
  }

  String get _badgeLabel {
    if (_isSoon) return 'UPCOMING';
    final diff = DateTime.now().difference(data.createdAt);
    if (diff.inHours < 48) return 'NEW';
    if (['Competition', 'General Assembly', 'Sports'].contains(data.category)) {
      return 'POPULAR';
    }
    return '';
  }

  Color get _badgeColor {
    switch (_badgeLabel) {
      case 'UPCOMING':
        return const Color(0xFFF59E0B);
      case 'NEW':
        return const Color(0xFF059669);
      case 'POPULAR':
        return const Color(0xFF8B5CF6);
      default:
        return accent;
    }
  }

  String _formatEventDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    const wdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final min = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    return '${wdays[dt.weekday - 1]}, ${months[dt.month - 1]} ${dt.day}'
        ' · $h:$min $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final catColor = feedCategoryColor(data.category);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(23),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Full-width image / gradient placeholder ────
            CardImageBanner(
              imageBase64: data.imageBase64,
              orgName: data.orgName,
              badgeLabel: _badgeLabel,
              badgeColor: _badgeColor,
              height: 190,
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Date + time ──────────────────────────
                  Row(
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        size: 13,
                        color: catColor,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          data.eventDate != null
                              ? _formatEventDate(data.eventDate!)
                              : 'Date TBA',
                          style: TextStyle(
                            fontSize: 12,
                            color: catColor,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Category dot
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

                  // ── Title ────────────────────────────────
                  Text(
                    data.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const SizedBox(height: 6),

                  // ── Location ─────────────────────────────
                  if (data.location.isNotEmpty && data.location != 'TBA')
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 13,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            data.location,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),

                  const SizedBox(height: 14),

                  // ── Action row (full-width button + share) ─
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 44,
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            'View Details',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      if (onShare != null) ...[
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: onShare,
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: accentBg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: accent.withAlpha(64)),
                            ),
                            child: Icon(
                              Icons.share_outlined,
                              size: 18,
                              color: accent,
                            ),
                          ),
                        ),
                      ],
                    ],
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

// ─────────────────────────────────────────────────────────────
//  ANNOUNCEMENT FEED CARD  (Facebook-post style)
// ─────────────────────────────────────────────────────────────
class FeedAnnouncementCardData {
  final String title;
  final String body;
  final String orgName;
  final String imageBase64;
  final String audience;
  final bool isPinned;
  final DateTime timestamp;

  const FeedAnnouncementCardData({
    required this.title,
    this.body = '',
    required this.orgName,
    this.imageBase64 = '',
    this.audience = 'Public',
    this.isPinned = false,
    required this.timestamp,
  });
}

class FeedAnnouncementCard extends StatefulWidget {
  final FeedAnnouncementCardData data;
  final String timeAgo;
  final VoidCallback onTap;
  final VoidCallback? onShare;
  final Color accent;
  final Color accentBg;

  const FeedAnnouncementCard({
    super.key,
    required this.data,
    required this.timeAgo,
    required this.onTap,
    this.onShare,
    this.accent = AppColors.primaryDark,
    this.accentBg = AppColors.primarySoft,
  });

  @override
  State<FeedAnnouncementCard> createState() => _FeedAnnouncementCardState();
}

class _FeedAnnouncementCardState extends State<FeedAnnouncementCard> {
  bool _expanded = false;

  String get _badgeLabel {
    if (widget.data.isPinned) return 'PINNED';
    final diff = DateTime.now().difference(widget.data.timestamp);
    if (diff.inHours < 24) return 'NEW';
    return '';
  }

  Color get _badgeColor {
    if (widget.data.isPinned) return widget.accent;
    return const Color(0xFF059669);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.data;

    return Container(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Full-width image / placeholder ────────────────
          CardImageBanner(
            imageBase64: item.imageBase64,
            orgName: item.orgName,
            badgeLabel: _badgeLabel,
            badgeColor: _badgeColor,
            height: 200,
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Org row ────────────────────────────────
                Row(
                  children: [
                    const Icon(
                      Icons.campaign_outlined,
                      size: 13,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${item.orgName} · ${widget.timeAgo}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (item.audience
                        .split(',')
                        .map((s) => s.trim())
                        .contains('CICT Only'))
                      const MiniChip(label: 'CICT', color: Color(0xFF1565C0)),
                  ],
                ),

                const SizedBox(height: 8),

                // ── Title ──────────────────────────────────
                Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                    height: 1.25,
                  ),
                ),

                if (item.body.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    item.body,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF666666),
                      height: 1.5,
                    ),
                    maxLines: _expanded ? null : 3,
                    overflow: _expanded
                        ? TextOverflow.visible
                        : TextOverflow.ellipsis,
                  ),
                  if (!_expanded && item.body.length > 140)
                    GestureDetector(
                      onTap: () => setState(() => _expanded = true),
                      child: const Padding(
                        padding: EdgeInsets.only(top: 3),
                        child: Text(
                          'See more',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF1565C0),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],

                const SizedBox(height: 14),

                // ── Action row ─────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: widget.onTap,
                        child: Container(
                          height: 42,
                          decoration: BoxDecoration(
                            color: widget.accent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            'View Announcement',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (widget.onShare != null) ...[
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: widget.onShare,
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: widget.accentBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: widget.accent.withAlpha(64)),
                          ),
                          child: Icon(
                            Icons.share_outlined,
                            size: 18,
                            color: widget.accent,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFFE4E6EA)),
        ],
      ),
    );
  }
}

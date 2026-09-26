// lib/widgets/common/event_badges.dart
//
// The badge set that sits on an event card or detail header.
//
// Student and guest each grew their own copies of most of these — two
// `_CategoryBadge`s that disagreed on colour, an `_AudienceBadge` (guest) that
// showed the raw audience string next to an `_AudienceBadgeRow` (student) that
// parsed it. These are the student treatments, extracted so both sides render
// the same badge, plus SoonBadge which only guest had.
//
// One behavioural correction came with the move: CategoryBadge no longer picks
// its colour from a hand-written switch. Both switches covered only 4-6 of the
// 10 categories in kFeedCategoryColors and fell through to grey for the rest,
// so the same event could show an orange badge on the events list and a violet
// one on the home feed card. feedCategoryColor() is now the single source.

import 'package:flutter/material.dart';

import '../student/app_colors.dart';
import 'feed_cards.dart' show feedCategoryColor;

/// Solid category chip — "WORKSHOP", "SEMINAR", …
class CategoryBadge extends StatelessWidget {
  final String category;

  const CategoryBadge({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: feedCategoryColor(category),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        category.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// Yellow "SOON" flag for an event starting shortly.
class SoonBadge extends StatelessWidget {
  const SoonBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEB3B),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        'SOON',
        style: TextStyle(
          color: Colors.black87,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// Brand-colored "ONGOING" chip for an event that is happening right now,
/// styled to match the "● Ongoing" filter pill on the events screen.
class LiveBadge extends StatelessWidget {
  const LiveBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primaryDark,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(51),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          const Text(
            'ONGOING',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// Who an event is open to, as one pill per audience.
///
/// Splits the comma-separated `audience` field the same way
/// `EventModel.audienceAllowsMember` does, so the labels shown always match
/// what is actually being enforced — an event tagged "CICT Only, Bulsuan"
/// renders two pills rather than one chip containing the raw string.
class AudienceBadgeRow extends StatelessWidget {
  final String audience;

  const AudienceBadgeRow({super.key, required this.audience});

  @override
  Widget build(BuildContext context) {
    final values = audience
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final labels = values.isEmpty || values.contains('Public')
        ? const ['Public']
        : values;

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final label in labels)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: label == 'Public'
                  ? Colors.green.withAlpha(26)
                  : AppColors.primaryDark.withAlpha(20),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(
                color: label == 'Public'
                    ? Colors.green.withAlpha(77)
                    : AppColors.primaryDark.withAlpha(64),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  label == 'Public'
                      ? Icons.public
                      : Icons.verified_user_outlined,
                  size: 12,
                  color: label == 'Public'
                      ? Colors.green.shade700
                      : AppColors.primaryDark,
                ),
                const SizedBox(width: 5),
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: label == 'Public'
                        ? Colors.green.shade700
                        : AppColors.primaryDark,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// lib/widgets/common/empty_state.dart
//
// Whole-page / whole-tab empty state.
//
// Taken from guest's `_EmptyEvents` — one of the few places the guest side had
// a pattern and the student side didn't. Student's equivalent was a bare grey
// icon and a line of grey text inlined in _EventResultsList, repeated in
// slightly different form as _EmptyHint (merch), _EmptyState (notifications)
// and _EmptyEventsState (profile). This replaces all four.
//
// Use this when the whole viewport is empty. For a section that came up empty
// *inside* a populated scroll view, use EmptyFeedSection — it renders as a
// bordered card in the flow rather than a centred full-height block. It lives
// in feed_cards.dart and is re-exported here so both are found in one place.

import 'package:flutter/material.dart';

import '../student/app_colors.dart';

export 'feed_cards.dart' show EmptyFeedSection;

class EmptyStateView extends StatelessWidget {
  final IconData icon;

  /// Short bold line — what isn't here.
  final String title;

  /// Optional quieter second line — what to do about it.
  final String? message;

  final Color accent;
  final Color accentBg;

  const EmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.accent = AppColors.primaryDark,
    this.accentBg = AppColors.primarySoft,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: accentBg, shape: BoxShape.circle),
              child: Icon(icon, size: 48, color: accent),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                color: Colors.black54,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.black38),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

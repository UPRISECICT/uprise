// lib/widgets/common/review_identity.dart
//
// Who a review is attributed to, and the control that lets the reviewer decide.
//
// The `isAnonymous` flag has been written to feedback documents for a while but
// was read nowhere, and no feedback document stored a reviewer name at all — so
// the toggle changed nothing either way. These helpers are the display half of
// making that choice real: the submit paths now store `authorName` when the
// reviewer opts in to attribution, and every surface that shows a review runs
// the name through here.

import 'package:flutter/material.dart';

import '../student/app_colors.dart';

/// Whether a feedback document should be shown without its author's name.
///
/// A **missing** flag counts as anonymous. Documents in the legacy `feedback`
/// collection predate the toggle — their authors were never offered the choice,
/// and those documents carry no name to show anyway — so defaulting to private
/// is both the safe reading and the accurate one.
bool reviewIsAnonymous(Map<String, dynamic> data) {
  final flag = data['isAnonymous'];
  if (flag is bool) return flag;
  return true;
}

/// `carlos1` -> `c*****1`, the partial masking e-commerce review lists use:
/// enough for the reviewer to recognise their own entry, not enough to identify
/// them to a stranger.
String maskReviewerName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'Anonymous';
  if (trimmed.length <= 2) return '${trimmed[0]}*';
  // Capped so a long full name doesn't render as a wall of asterisks.
  final stars = '*' * (trimmed.length - 2).clamp(1, 6);
  return '${trimmed[0]}$stars${trimmed[trimmed.length - 1]}';
}

/// The name to print above a review.
///
/// [isOwnReview] is for a reader looking at their own history — masking someone
/// from themselves communicates nothing, so their own entries read in full.
String reviewerDisplayName(
  Map<String, dynamic> data, {
  bool isOwnReview = false,
}) {
  final name = (data['authorName'] ?? data['userName'] ?? '').toString().trim();
  if (reviewIsAnonymous(data)) {
    return isOwnReview ? 'Anonymous (you)' : 'Anonymous';
  }
  if (name.isEmpty) return 'Anonymous';
  return isOwnReview ? name : maskReviewerName(name);
}

/// The anonymity control on a feedback form.
///
/// One Switch for every submit path — the student event-details form already
/// used this treatment while the standalone form used a bare Checkbox and the
/// guest form offered nothing at all.
class AnonymityToggle extends StatelessWidget {
  final bool value;

  /// Null disables the control, for a review that has already been submitted.
  final ValueChanged<bool>? onChanged;

  const AnonymityToggle({super.key, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Anonymous Feedback',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value
                      ? 'The organization won\'t see your name.'
                      : 'The organization can see who submitted this.',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          // Colours set per state: only `activeColor` was given before, so the
          // off state fell back to the theme's black thumb and outline. The
          // "ON"/"OFF" text beside it only repeated what the switch shows.
          Switch(
            value: value,
            onChanged: onChanged,
            thumbColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? Colors.white
                  : Colors.grey.shade500,
            ),
            trackColor: WidgetStateProperty.resolveWith((states) {
              final on = states.contains(WidgetState.selected);
              final disabled = states.contains(WidgetState.disabled);
              if (on) {
                return disabled
                    ? AppColors.primaryDark.withAlpha(110)
                    : AppColors.primaryDark;
              }
              return Colors.grey.shade200;
            }),
            trackOutlineColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? Colors.transparent
                  : Colors.grey.shade300,
            ),
          ),
        ],
      ),
    );
  }
}

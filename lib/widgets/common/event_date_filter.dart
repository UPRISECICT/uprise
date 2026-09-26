// lib/widgets/common/event_date_filter.dart
//
// Date filter shared by every mobile events browse surface — student Discover,
// student My Events, the per-category screen, guest Discover and guest My
// Events. It used to live only inside the category screen, so the tabs a
// student lands on had no way to narrow by date at all.
//
// Presentation plus one predicate: each caller still filters its own domain
// objects, it just asks [EventDateFilter.matches] about each event's date.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../student/app_colors.dart';

enum EventDateBucket { today, thisWeek, thisMonth, custom }

/// One active date filter. A null filter (held by the caller) means any date.
@immutable
class EventDateFilter {
  final EventDateBucket bucket;

  /// The picked day — only meaningful for [EventDateBucket.custom].
  final DateTime? customDate;

  const EventDateFilter(this.bucket, {this.customDate});

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool matches(DateTime date) {
    final now = DateTime.now();
    switch (bucket) {
      case EventDateBucket.today:
        return _sameDay(date, now);
      case EventDateBucket.thisWeek:
        // Monday-start week. Built from calendar fields rather than adding a
        // 7-day Duration so a DST shift can't clip the last day.
        final start = DateTime(now.year, now.month, now.day - (now.weekday - 1));
        final end = DateTime(start.year, start.month, start.day + 7);
        return !date.isBefore(start) && date.isBefore(end);
      case EventDateBucket.thisMonth:
        return date.year == now.year && date.month == now.month;
      case EventDateBucket.custom:
        return customDate != null && _sameDay(date, customDate!);
    }
  }

  /// Chip text — "This Week", "Sep 26, 2026".
  String get label => switch (bucket) {
    EventDateBucket.today => 'Today',
    EventDateBucket.thisWeek => 'This Week',
    EventDateBucket.thisMonth => 'This Month',
    EventDateBucket.custom =>
      customDate == null
          ? 'Pick a Date'
          : DateFormat('MMM d, yyyy').format(customDate!),
  };

  /// Tail for an empty-state line — "No events this week".
  String get phrase => switch (bucket) {
    EventDateBucket.today => 'today',
    EventDateBucket.thisWeek => 'this week',
    EventDateBucket.thisMonth => 'this month',
    EventDateBucket.custom =>
      customDate == null
          ? 'on that date'
          : 'on ${DateFormat('MMM d, yyyy').format(customDate!)}',
  };
}

/// What the filter sheet hands back when "Apply" is tapped. `date` null means
/// any date; `sort` is only meaningful when the caller passed sort options.
typedef EventFilterResult<S> = ({EventDateFilter? date, S? sort});

/// Bottom sheet with the date options and, when [sortOptions] is non-empty, a
/// Sort By section under them.
///
/// Selections stay pending inside the sheet — nothing reaches the caller until
/// "Apply" is tapped, so dismissing the sheet resolves to null and discards
/// them.
Future<EventFilterResult<S>?> showEventFilterSheet<S>(
  BuildContext context, {
  EventDateFilter? date,
  S? sort,
  List<(S, String)> sortOptions = const [],
}) async {
  var pendingBucket = date?.bucket;
  var pendingCustom = date?.customDate;
  var pendingSort = sort;

  final applied = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          Widget optionRow({
            required String label,
            required bool selected,
            required VoidCallback onTap,
            IconData? trailing,
          }) {
            return InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(
                      selected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      color: selected
                          ? AppColors.primaryDark
                          : Colors.grey.shade400,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: selected
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                    if (trailing != null)
                      Icon(trailing, size: 18, color: AppColors.textMuted),
                  ],
                ),
              ),
            );
          }

          Widget sectionTitle(String text, {Widget? action}) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      text,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (action != null) action,
                ],
              ),
            );
          }

          void pickBucket(EventDateBucket bucket) {
            setSheetState(() {
              pendingBucket = bucket;
              pendingCustom = null;
            });
          }

          Future<void> pickCustomDate() async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: sheetContext,
              initialDate: pendingCustom ?? now,
              firstDate: DateTime(now.year - 2),
              lastDate: DateTime(now.year + 2, 12, 31),
            );
            if (picked == null) return;
            setSheetState(() {
              pendingBucket = EventDateBucket.custom;
              pendingCustom = picked;
            });
          }

          return SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 8),
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  sectionTitle(
                    'Date',
                    action: pendingBucket == null
                        ? null
                        : TextButton(
                            onPressed: () => setSheetState(() {
                              pendingBucket = null;
                              pendingCustom = null;
                            }),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.primaryDark,
                              visualDensity: VisualDensity.compact,
                            ),
                            child: const Text(
                              'Clear',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                  ),
                  optionRow(
                    label: 'Any Date',
                    selected: pendingBucket == null,
                    onTap: () => setSheetState(() {
                      pendingBucket = null;
                      pendingCustom = null;
                    }),
                  ),
                  optionRow(
                    label: 'Today',
                    selected: pendingBucket == EventDateBucket.today,
                    onTap: () => pickBucket(EventDateBucket.today),
                  ),
                  optionRow(
                    label: 'This Week',
                    selected: pendingBucket == EventDateBucket.thisWeek,
                    onTap: () => pickBucket(EventDateBucket.thisWeek),
                  ),
                  optionRow(
                    label: 'This Month',
                    selected: pendingBucket == EventDateBucket.thisMonth,
                    onTap: () => pickBucket(EventDateBucket.thisMonth),
                  ),
                  optionRow(
                    label:
                        pendingBucket == EventDateBucket.custom &&
                            pendingCustom != null
                        ? 'Pick a Date — ${DateFormat('MMM d, yyyy').format(pendingCustom!)}'
                        : 'Pick a Date',
                    selected: pendingBucket == EventDateBucket.custom,
                    trailing: Icons.calendar_month_rounded,
                    onTap: pickCustomDate,
                  ),
                  if (sortOptions.isNotEmpty) ...[
                    const Divider(height: 24),
                    sectionTitle('Sort By'),
                    for (final opt in sortOptions)
                      optionRow(
                        label: opt.$2,
                        selected: pendingSort == opt.$1,
                        onTap: () => setSheetState(() => pendingSort = opt.$1),
                      ),
                  ],
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(sheetContext, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryDark,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Apply',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );

  if (applied != true) return null;
  final bucket = pendingBucket;
  return (
    date: bucket == null
        ? null
        : EventDateFilter(bucket, customDate: pendingCustom),
    sort: pendingSort,
  );
}

/// Date-only form of [showEventFilterSheet]. Resolves to null when dismissed;
/// otherwise `date` is the new selection (null = any date).
Future<({EventDateFilter? date})?> showEventDateFilterSheet(
  BuildContext context,
  EventDateFilter? current,
) async {
  final result = await showEventFilterSheet<Never>(context, date: current);
  return result == null ? null : (date: result.date);
}

/// Square brand button that sits to the right of a search field and opens a
/// filter sheet, with a count badge while any of its filters are on.
class EventFilterButton extends StatelessWidget {
  final int activeCount;
  final VoidCallback onTap;
  final IconData icon;
  final String tooltip;

  const EventFilterButton({
    super.key,
    required this.activeCount,
    required this.onTap,
    this.icon = Icons.calendar_month_rounded,
    this.tooltip = 'Filter by date',
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Badge(
        isLabelVisible: activeCount > 0,
        label: Text('$activeCount'),
        child: Material(
          color: AppColors.primaryDark,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(11),
              child: Icon(icon, size: 18, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

/// The active date filter, shown above the results so a shorter list always
/// says why. Tap to change it, ✕ to clear it.
class EventDateFilterChip extends StatelessWidget {
  final EventDateFilter filter;
  final VoidCallback onTap;
  final VoidCallback onCleared;

  const EventDateFilterChip({
    super.key,
    required this.filter,
    required this.onTap,
    required this.onCleared,
  });

  @override
  Widget build(BuildContext context) {
    return InputChip(
      avatar: const Icon(
        Icons.event_rounded,
        size: 16,
        color: AppColors.primaryDark,
      ),
      label: Text(filter.label),
      labelStyle: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: AppColors.primaryDark,
      ),
      backgroundColor: AppColors.primarySoft,
      side: BorderSide(color: AppColors.primaryDark.withAlpha(77)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      deleteIcon: const Icon(Icons.close, size: 16),
      deleteIconColor: AppColors.primaryDark,
      deleteButtonTooltipMessage: 'Clear date filter',
      onDeleted: onCleared,
      onPressed: onTap,
    );
  }
}

// lib/widgets/common/calendar_month.dart
//
// Month navigator and month grid.
//
// Commit c3dd3b7 ported guest's calendar design onto the student Calendar tab
// by copying it, leaving _MonthNav / _CalendarGrid / _DayCell living in both
// student_events_screen.dart and guest_calendar_screen.dart as near-identical
// twins — right down to a `_catColors` map that each file declared separately
// and that both duplicated from kFeedCategoryColors. This is the student copy,
// which carries c3dd3b7's fix building the byDay map once in the parent rather
// than re-deriving it per cell.
//
// The grid is generic over the caller's event type instead of taking a data
// struct: a month can hold a lot of events, and converting all of them just to
// draw title chips would be wasted work. Callers pass their own list plus two
// accessors, and get their own objects back from onDayTap.
//
// Category chip colours come from feedCategoryColor() — the two local
// `_catColors` maps this replaces were byte-identical copies of it.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../student/app_colors.dart';
import 'feed_cards.dart' show feedCategoryColor;

/// "Today" pill + ‹ Month YYYY › stepper.
class MonthNav extends StatelessWidget {
  final DateTime currentMonth;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;

  const MonthNav({
    super.key,
    required this.currentMonth,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: onToday,
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.primaryDark,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                Icon(Icons.today_rounded, size: 15, color: Colors.white),
                SizedBox(width: 6),
                Text(
                  'Today',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E6EA)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(10),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                _NavBtn(icon: Icons.chevron_left_rounded, onTap: onPrev),
                Expanded(
                  child: Text(
                    DateFormat('MMMM yyyy').format(currentMonth),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                ),
                _NavBtn(icon: Icons.chevron_right_rounded, onTap: onNext),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Month grid with weekday header and 100px day cells.
///
/// [byDay] is keyed by day-of-month. Build it once in the parent — a builder
/// that filters the full event list per cell turns one month into 42 passes.
class MonthCalendarGrid<T> extends StatelessWidget {
  final DateTime currentMonth;
  final Map<int, List<T>> byDay;

  /// Chip label and chip colour for one event.
  final String Function(T) titleOf;
  final String Function(T) categoryOf;

  /// Fired only for days that actually have events.
  final void Function(int day, List<T> events) onDayTap;

  const MonthCalendarGrid({
    super.key,
    required this.currentMonth,
    required this.byDay,
    required this.titleOf,
    required this.categoryOf,
    required this.onDayTap,
  });

  int get _daysInMonth =>
      DateTime(currentMonth.year, currentMonth.month + 1, 0).day;
  int get _startWeekday =>
      DateTime(currentMonth.year, currentMonth.month, 1).weekday % 7;
  int get _totalRows => ((_startWeekday + _daysInMonth) / 7).ceil();

  @override
  Widget build(BuildContext context) {
    const weekdays = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8ECF0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFFFFF7ED),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(bottom: BorderSide(color: AppColors.primarySoft)),
            ),
            child: Row(
              children: weekdays
                  .map(
                    (d) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          d,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF64748B),
                            letterSpacing: 0.7,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisExtent: 100,
            ),
            itemCount: _totalRows * 7,
            itemBuilder: (_, index) {
              final dayNum = index - _startWeekday + 1;
              if (dayNum < 1 || dayNum > _daysInMonth) {
                return _emptyCell(index);
              }
              final events = byDay[dayNum] ?? const [];
              return _DayCell<T>(
                day: dayNum,
                events: events,
                currentMonth: currentMonth,
                totalRows: _totalRows,
                startWeekday: _startWeekday,
                titleOf: titleOf,
                categoryOf: categoryOf,
                onTap: events.isEmpty ? null : () => onDayTap(dayNum, events),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _emptyCell(int index) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFBFCFE),
        border: Border(
          right: (index % 7) < 6
              ? const BorderSide(color: Color(0xFFF1F5F9))
              : BorderSide.none,
          bottom: index < (_totalRows - 1) * 7
              ? const BorderSide(color: Color(0xFFF1F5F9))
              : BorderSide.none,
        ),
      ),
    );
  }
}

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _NavBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 36,
        height: 40,
        child: Icon(icon, size: 20, color: Colors.black45),
      ),
    );
  }
}

class _DayCell<T> extends StatelessWidget {
  final int day;
  final List<T> events;
  final DateTime currentMonth;
  final int totalRows;
  final int startWeekday;
  final String Function(T) titleOf;
  final String Function(T) categoryOf;
  final VoidCallback? onTap;

  const _DayCell({
    required this.day,
    required this.events,
    required this.currentMonth,
    required this.totalRows,
    required this.startWeekday,
    required this.titleOf,
    required this.categoryOf,
    required this.onTap,
  });

  bool get isToday {
    final now = DateTime.now();
    return day == now.day &&
        currentMonth.year == now.year &&
        currentMonth.month == now.month;
  }

  int get cellIndex => startWeekday + day - 1;
  int get colIndex => cellIndex % 7;
  bool get isLastRow => cellIndex >= (totalRows - 1) * 7;

  @override
  Widget build(BuildContext context) {
    // Three chips is what fits in a 100px cell; the rest collapse to "+N more".
    final display = events.take(3).toList();
    final extra = events.length - display.length;

    return InkWell(
      onTap: onTap,
      hoverColor: AppColors.primaryDark.withAlpha(10),
      child: Container(
        decoration: BoxDecoration(
          color: isToday ? AppColors.primaryDark.withAlpha(18) : null,
          border: Border(
            right: colIndex < 6
                ? const BorderSide(color: Color(0xFFF1F5F9))
                : BorderSide.none,
            bottom: !isLastRow
                ? const BorderSide(color: Color(0xFFF1F5F9))
                : BorderSide.none,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(7, 6, 7, 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: isToday
                      ? BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primaryDark,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primaryDark.withAlpha(89),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        )
                      : null,
                  alignment: Alignment.center,
                  child: Text(
                    '$day',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isToday ? FontWeight.w700 : FontWeight.w600,
                      color: isToday ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                if (events.length > 1)
                  Text(
                    '${events.length}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            ...display.map((e) {
              final color = feedCategoryColor(categoryOf(e));
              return Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: color.withAlpha(31),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 4,
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          titleOf(e),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            if (extra > 0)
              Text(
                '+$extra more',
                style: const TextStyle(
                  fontSize: 9,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

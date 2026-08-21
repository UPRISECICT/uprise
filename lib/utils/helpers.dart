/// Combines a date with a "7:00 AM" or "19:00"-style time string.
///
/// Tolerant of both 12-hour (with AM/PM) and 24-hour formats. Falls back to
/// midnight on [date] if [timeStr] is null, empty, or unparseable — this is
/// the single implementation shared by event upcoming/ongoing/past
/// classification (student tabs, event detail) and attendance lateness
/// checks (webinar + QR check-in), which previously each hand-rolled their
/// own copy of this parsing and could disagree on edge-case time strings.
DateTime combineDateAndTime(DateTime date, String? timeStr) {
  try {
    int hour = 0;
    int minute = 0;

    if (timeStr != null && timeStr.isNotEmpty) {
      if (timeStr.toLowerCase().contains('am') ||
          timeStr.toLowerCase().contains('pm')) {
        // Example: 7:30 PM
        final cleanTime = timeStr
            .replaceAll(RegExp(r'[AP]M', caseSensitive: false), '')
            .trim();

        final parts = cleanTime.split(':');
        hour = int.parse(parts[0]);
        minute = int.parse(parts[1]);

        if (timeStr.toLowerCase().contains('pm') && hour < 12) {
          hour += 12;
        }

        if (timeStr.toLowerCase().contains('am') && hour == 12) {
          hour = 0;
        }
      } else {
        // Example: 19:30
        final parts = timeStr.split(':');
        hour = int.parse(parts[0]);
        minute = int.parse(
          parts.length > 1 ? parts[1].replaceAll(RegExp(r'[^0-9]'), '') : '0',
        );
      }
    }

    return DateTime(date.year, date.month, date.day, hour, minute);
  } catch (_) {
    return date;
  }
}

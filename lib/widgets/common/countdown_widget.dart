import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uprise/models/event_model.dart';
import '../student/app_colors.dart';
import '../student/app_image.dart';

class CountdownWidget extends StatefulWidget {
  final EventModel? event;

  const CountdownWidget({Key? key, this.event}) : super(key: key);

  @override
  State<CountdownWidget> createState() => _CountdownWidgetState();
}

class _CountdownWidgetState extends State<CountdownWidget> {
  late Timer _timer;
  Duration _duration = Duration.zero;
  bool _isEventStarted = false;

  @override
  void initState() {
    super.initState();
    _updateDuration();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateDuration();
    });
  }

  void _updateDuration() {
    if (widget.event == null) {
      setState(() {
        _duration = Duration.zero;
        _isEventStarted = false;
      });
      return;
    }

    try {
      // ⭐ GAMITIN ANG date + startTime NG EVENT ⭐
      final eventDate = widget.event!.date;
      final timeStr = widget.event!.startTime;

      DateTime? eventDateTime;

      // Parse time string (e.g., "9:00 AM" or "14:30")
      if (timeStr.isNotEmpty) {
        try {
          final cleaned = timeStr.trim().toUpperCase();
          final match = RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)?$').firstMatch(cleaned);
          if (match != null) {
            int hour = int.parse(match.group(1)!);
            final minute = int.parse(match.group(2)!);
            final meridiem = match.group(3);

            if (meridiem == 'PM' && hour != 12) hour += 12;
            if (meridiem == 'AM' && hour == 12) hour = 0;

            eventDateTime = DateTime(
              eventDate.year,
              eventDate.month,
              eventDate.day,
              hour,
              minute,
            );
          }
        } catch (_) {
          // If time parsing fails, use midnight
          eventDateTime = DateTime(
            eventDate.year,
            eventDate.month,
            eventDate.day,
          );
        }
      } else {
        // If no time, use midnight
        eventDateTime = DateTime(
          eventDate.year,
          eventDate.month,
          eventDate.day,
        );
      }

      if (eventDateTime == null) {
        setState(() {
          _duration = Duration.zero;
          _isEventStarted = false;
        });
        return;
      }

      final now = DateTime.now();
      final difference = eventDateTime.difference(now);

      setState(() {
        if (difference.isNegative) {
          _duration = Duration.zero;
          _isEventStarted = true;
        } else {
          _duration = difference;
          _isEventStarted = false;
        }
      });
    } catch (e) {
      setState(() {
        _duration = Duration.zero;
        _isEventStarted = false;
      });
    }
  }

  @override
  void didUpdateWidget(CountdownWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.event != oldWidget.event) {
      _updateDuration();
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String _twoDigits(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    // ✅ If no event, don't show anything
    if (widget.event == null) {
      return const SizedBox.shrink();
    }

    final days = _duration.inDays;
    final hours = _duration.inHours.remainder(24);
    final minutes = _duration.inMinutes.remainder(60);
    final seconds = _duration.inSeconds.remainder(60);

    // ✅ If event has started, show different UI
    if (_isEventStarted) {
      final bannerUrl = widget.event!.bannerUrl ?? '';
      final hasBanner = bannerUrl.isNotEmpty;

      return Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.green.withAlpha(77),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: hasBanner
                  ? AppImage(source: bannerUrl, fit: BoxFit.cover)
                  : const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.green, Colors.greenAccent],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
            ),
            if (hasBanner)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.green.shade900.withAlpha(230),
                        Colors.green.shade700.withAlpha(150),
                      ],
                      begin: Alignment.bottomLeft,
                      end: Alignment.topRight,
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const Icon(
                    Icons.emoji_events,
                    color: Colors.white,
                    size: 32,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.event!.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Text(
                          '🎉 Event has started!',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // ✅ Show countdown
    final bannerUrl = widget.event!.bannerUrl ?? '';
    final hasBanner = bannerUrl.isNotEmpty;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withAlpha(77),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: hasBanner
                ? AppImage(source: bannerUrl, fit: BoxFit.cover)
                : const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.primaryDark, AppColors.primaryLight],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
          ),
          if (hasBanner)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primaryDark.withAlpha(235),
                      AppColors.primaryDark.withAlpha(150),
                    ],
                    begin: Alignment.bottomLeft,
                    end: Alignment.topRight,
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        widget.event!.orgName.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(51),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Event Starts',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  widget.event!.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _buildTimeBlock(_twoDigits(days), 'DAYS'),
                    const SizedBox(width: 8),
                    _buildTimeBlock(_twoDigits(hours), 'HOURS'),
                    const SizedBox(width: 8),
                    _buildTimeBlock(_twoDigits(minutes), 'MINUTES'),
                    const SizedBox(width: 8),
                    _buildTimeBlock(_twoDigits(seconds), 'SECONDS'),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.calendar_today, color: Colors.white, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      widget.event!.formattedDate,
                      style: TextStyle(
                        color: Colors.white.withAlpha(230),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Icon(Icons.access_time, color: Colors.white, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      widget.event!.formattedTime,
                      style: TextStyle(
                        color: Colors.white.withAlpha(230),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.white, size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.event!.location,
                        style: TextStyle(
                          color: Colors.white.withAlpha(230),
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeBlock(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(38),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withAlpha(51)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withAlpha(179),
                fontSize: 9,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

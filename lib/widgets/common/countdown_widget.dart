import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uprise/models/event_model.dart';
import '../student/app_colors.dart';
import '../student/app_image.dart';
import 'event_badges.dart';

class CountdownWidget extends StatefulWidget {
  final EventModel? event;

  const CountdownWidget({super.key, this.event});

  @override
  State<CountdownWidget> createState() => _CountdownWidgetState();
}

class _CountdownWidgetState extends State<CountdownWidget> {
  late Timer _timer;
  Duration _duration = Duration.zero;
  EventTimeStatus _status = EventTimeStatus.upcoming;

  @override
  void initState() {
    super.initState();
    _updateDuration();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateDuration();
    });
  }

  void _updateDuration() {
    final event = widget.event;
    if (event == null) {
      setState(() {
        _duration = Duration.zero;
        _status = EventTimeStatus.upcoming;
      });
      return;
    }

    // Was a local RegExp re-parse of date + startTime, which never looked at
    // the end time — so an event that had begun stuck on "started" forever
    // with no ended state. EventModel.timeStatus/fullDateTime/endDateTime are
    // the canonical classification (the same one the LIVE badge reads), and
    // handle the blank-endTime case for us.
    final status = event.timeStatus;
    final now = DateTime.now();

    // Upcoming counts down to the start; ongoing counts down to the end,
    // which is the number that's actually still meaningful mid-event.
    final target = status == EventTimeStatus.upcoming
        ? event.fullDateTime
        : event.endDateTime;
    final remaining = target.difference(now);

    setState(() {
      _status = status;
      _duration = remaining.isNegative ? Duration.zero : remaining;
    });
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
    final event = widget.event;
    // ✅ If no event, don't show anything
    if (event == null) return const SizedBox.shrink();

    final days = _duration.inDays;
    final hours = _duration.inHours.remainder(24);
    final minutes = _duration.inMinutes.remainder(60);
    final seconds = _duration.inSeconds.remainder(60);

    final ongoing = _status == EventTimeStatus.ongoing;
    final completed = _status == EventTimeStatus.completed;

    // One card shape for all three states. The ongoing state used to drop the
    // org name, the time blocks, the date and the location and render a lone
    // trophy icon instead, which collapsed the card to roughly half the height
    // its carousel slot reserves — it read as a placeholder rather than as the
    // most important event on the screen.
    final accent = ongoing
        ? AppColors.success
        : completed
        ? const Color(0xFF475569)
        : AppColors.primaryDark;
    final accentLight = ongoing
        ? const Color(0xFF34D399)
        : completed
        ? const Color(0xFF94A3B8)
        : AppColors.primaryLight;

    final bannerUrl = event.bannerUrl ?? '';
    final hasBanner = bannerUrl.isNotEmpty;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: accent.withAlpha(77),
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
                : DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [accent, accentLight],
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
                    colors: [accent.withAlpha(235), accent.withAlpha(150)],
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
                        event.orgName.toUpperCase(),
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
                    // The same LiveBadge the event cards use for this state,
                    // so an ongoing event is marked the same way everywhere
                    // instead of being green here and red there.
                    if (ongoing)
                      const LiveBadge()
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(51),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          completed ? 'Event Ended' : 'Event Starts',
                          style: const TextStyle(
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
                  event.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),
                if (completed)
                  // Nothing left to count down to, so the tiles would only
                  // show four zeroes.
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(38),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withAlpha(51)),
                    ),
                    child: const Text(
                      'This event has ended',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else ...[
                  Text(
                    ongoing ? 'ENDS IN' : 'STARTS IN',
                    style: TextStyle(
                      color: Colors.white.withAlpha(179),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
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
                ],
                const SizedBox(height: 12),
                // Both labels are Flexible: a long formatted date plus a long
                // time range has no room to grow on a narrow card, and an
                // unflexed Text in a Row overflows sideways rather than
                // clipping.
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_today,
                      color: Colors.white,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        event.formattedDate,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withAlpha(230),
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Icon(
                      Icons.access_time,
                      color: Colors.white,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        event.formattedTime,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withAlpha(230),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on,
                      color: Colors.white,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        event.location,
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
        // FittedBox scales the digits and label down together on narrow
        // cards (small phones, large text scale) instead of clipping them —
        // "SECONDS" is the widest label and was the first to get cut.
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: FittedBox(
            fit: BoxFit.scaleDown,
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
        ),
      ),
    );
  }
}

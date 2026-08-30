// lib/widgets/common/countdown_section.dart
//
// Shared countdown section for Home screens: shows a carousel of the
// signed-in user's own registered-event countdowns when a fetch callback
// is supplied, or falls back to a single countdown for the soonest public
// approved event when there's no session to fetch registrations for
// (e.g. a visitor guest). Deliberately takes a fetch *callback* rather
// than a bare uid — student's registrations are keyed by uid, but guest's
// are keyed by email+isGuest, so each caller supplies its own query.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:uprise/models/event_model.dart';
import '../common/loading_widget.dart';
import 'countdown_widget.dart';

class PersonalOrNextEventCountdown extends StatefulWidget {
  /// Non-null: fetches the events the current user personally registered
  /// for. Null: no session to check — falls back to the soonest public,
  /// approved, publicly-visible upcoming event instead.
  final Future<List<EventModel>> Function()? fetchMyRegisteredEvents;

  const PersonalOrNextEventCountdown({super.key, this.fetchMyRegisteredEvents});

  @override
  State<PersonalOrNextEventCountdown> createState() =>
      _PersonalOrNextEventCountdownState();
}

class _PersonalOrNextEventCountdownState
    extends State<PersonalOrNextEventCountdown> {
  late Future<List<EventModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant PersonalOrNextEventCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Auth/mode state can flip after this widget is already built (e.g. a
    // guest signs in) — re-fetch when the caller swaps the callback.
    if (oldWidget.fetchMyRegisteredEvents != widget.fetchMyRegisteredEvents) {
      setState(() => _future = _load());
    }
  }

  Future<List<EventModel>> _load() {
    final fetch = widget.fetchMyRegisteredEvents;
    if (fetch != null) return fetch();
    return _fetchNextPublicEvent();
  }

  Future<List<EventModel>> _fetchNextPublicEvent() async {
    try {
      // `date` is only the calendar day (local midnight), so comparing it to
      // `Timestamp.now()` would skip everything happening later today. Query
      // from the start of today and do the real start/end check client-side —
      // the times live in the `startTime`/`endTime` strings, which Firestore
      // can't compare against.
      final now = DateTime.now();
      final startOfToday = DateTime(now.year, now.month, now.day);

      final snap = await FirebaseFirestore.instance
          .collection('events')
          .where(
            'date',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday),
          )
          .orderBy('date')
          .limit(15) // buffered — status/audience filtered client-side below
          .get();

      for (final doc in snap.docs) {
        final event = EventModel.fromFirestore(doc);
        if (event.status != 'approved') continue;
        if (!EventModel.audienceAllowsPublic(event.audience)) continue;
        // An event that's already over shouldn't be counted down to — without
        // this it sticks on CountdownWidget's "Event has started!" state,
        // which has no ended variant.
        if (event.timeStatus == EventTimeStatus.completed) continue;
        return [event];
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<EventModel>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: SkeletonLoader(count: 1, height: 220),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return const SizedBox.shrink();
        }

        // Re-filter on every rebuild, not just at fetch: `_future` is built
        // once in initState, so without this a finished event would linger.
        final events = snapshot.data!
            .where((e) => e.timeStatus != EventTimeStatus.completed)
            .toList();
        if (events.isEmpty) return const SizedBox.shrink();

        final isPersonal = widget.fetchMyRegisteredEvents != null;

        if (isPersonal) {
          // CountdownWidget's content is all text (org name, title, the
          // DAYS/HOURS/MINUTES/SECONDS blocks, then three metadata rows), so
          // its natural height tracks the device font scale. A flat 240 left
          // the Column only ~5px of slack at 1.0x and overflowed as soon as
          // the system font size was bumped — scale the box with the text.
          final textScale = MediaQuery.textScalerOf(
            context,
          ).scale(1).clamp(1.0, 1.6);
          return SizedBox(
            height: 248 * textScale,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: events.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: SizedBox(
                    width: 400,
                    child: CountdownWidget(event: events[index]),
                  ),
                );
              },
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: CountdownWidget(event: events.first),
        );
      },
    );
  }
}

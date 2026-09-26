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
          // No fixed height. CountdownWidget's content is all text — org name,
          // title, the DAYS/HOURS/MINUTES/SECONDS blocks, then three metadata
          // rows — so its real height depends on the font's line metrics, the
          // device text scale and the locale. Every attempt to name that
          // number ahead of time (240, then 248 * textScale) has eventually
          // overflowed on some device, because the card is taller in
          // Be Vietnam Pro than the arithmetic assumed.
          //
          // IntrinsicHeight asks the tallest card what it actually needs and
          // sizes the row to that; stretch makes the shorter cards match it so
          // the carousel still reads as one band. The parent is a
          // SliverToBoxAdapter, so the vertical space is unbounded and this is
          // free to be as tall as it needs.
          //
          // Width follows the screen rather than a fixed 400, which ran past
          // the right edge on ~360dp phones. A lone card fills the row; with
          // several, each leaves a sliver of the next one peeking in so the
          // row reads as swipeable.
          final screenWidth = MediaQuery.sizeOf(context).width;
          final fullWidth = screenWidth - 40;
          final cardWidth = events.length == 1
              ? fullWidth
              : (screenWidth * 0.86).clamp(0.0, 400.0);
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < events.length; i++)
                    Padding(
                      padding: EdgeInsets.only(
                        right: i == events.length - 1 ? 0 : 12,
                      ),
                      child: SizedBox(
                        width: cardWidth,
                        child: CountdownWidget(event: events[i]),
                      ),
                    ),
                ],
              ),
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

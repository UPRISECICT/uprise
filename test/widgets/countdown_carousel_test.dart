// Verifies the countdown carousel takes its height from the card instead of a
// hard-coded number, and never overflows — at any text scale, and with cards
// of differing content length.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uprise/models/event_model.dart';
import 'package:uprise/widgets/common/countdown_widget.dart';

String _fmt(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ap = d.hour < 12 ? 'AM' : 'PM';
  return '$h:${d.minute.toString().padLeft(2, '0')} $ap';
}

EventModel _event({
  required bool ongoing,
  String title = 'Leadership Summit',
  String org = 'CICT',
  String location = 'AVR',
}) {
  final now = DateTime.now();
  final date = ongoing ? now : now.add(const Duration(days: 1));
  return EventModel(
    id: 'e-$title',
    title: title,
    description: 'd',
    location: location,
    category: 'Seminar',
    orgName: org,
    orgId: 'o1',
    date: DateTime(date.year, date.month, date.day),
    startTime: ongoing ? _fmt(now.subtract(const Duration(hours: 1))) : _fmt(date),
    endTime: ongoing ? _fmt(now.add(const Duration(hours: 1))) : _fmt(date),
    audience: 'CICT Only',
    status: 'approved',
    isPublic: true,
  );
}

/// The carousel exactly as countdown_section.dart builds it.
Widget _carousel(List<EventModel> events) => SingleChildScrollView(
  scrollDirection: Axis.horizontal,
  padding: const EdgeInsets.symmetric(horizontal: 20),
  child: IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < events.length; i++)
          Padding(
            padding: EdgeInsets.only(right: i == events.length - 1 ? 0 : 12),
            child: SizedBox(width: 400, child: CountdownWidget(event: events[i])),
          ),
      ],
    ),
  ),
);

Future<Size> _pump(
  WidgetTester tester,
  List<EventModel> events,
  double scale,
  GlobalKey key,
) async {
  tester.view.physicalSize = const Size(480, 1067);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          // A CustomScrollView mirrors the home screen: the carousel sits in a
          // SliverToBoxAdapter, so vertical space is unbounded.
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: KeyedSubtree(key: key, child: _carousel(events)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return tester.getSize(find.byKey(key));
}

void main() {
  for (final scale in [1.0, 1.15, 1.3, 1.6, 2.0]) {
    testWidgets('carousel does not overflow @ textScale $scale', (tester) async {
      final key = GlobalKey();
      await _pump(tester, [_event(ongoing: false), _event(ongoing: true)], scale, key);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('height tracks content, not a constant', (tester) async {
    final k1 = GlobalKey();
    final small = await _pump(tester, [_event(ongoing: false)], 1.0, k1);

    final k2 = GlobalKey();
    final big = await _pump(tester, [_event(ongoing: false)], 1.6, k2);

    expect(tester.takeException(), isNull);
    // Bigger text must produce a taller carousel — a fixed box would not.
    expect(big.height, greaterThan(small.height));
  });

  testWidgets('mixed-length cards share the tallest height', (tester) async {
    final key = GlobalKey();
    await _pump(
      tester,
      [
        _event(ongoing: false, title: 'A', org: 'B', location: 'C'),
        _event(
          ongoing: true,
          title: 'Leadership Summit 2026 Opening Ceremony And Induction',
          org: 'COLLEGE OF INFORMATION AND COMMUNICATIONS TECHNOLOGY',
          location: 'CICT Audio Visual Room, Bulacan State University Main',
        ),
      ],
      1.0,
      key,
    );
    expect(tester.takeException(), isNull);

    final cards = tester.widgetList(find.byType(CountdownWidget)).length;
    expect(cards, 2);
    final h0 = tester.getSize(find.byType(CountdownWidget).at(0)).height;
    final h1 = tester.getSize(find.byType(CountdownWidget).at(1)).height;
    expect(h0, h1);
  });
}

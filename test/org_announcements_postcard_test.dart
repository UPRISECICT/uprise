// Regression test for a real bug: _PostCard's decoration mixed a
// category-colored left border with a plain grey border on the other three
// sides while also setting a borderRadius. Flutter's BoxDecoration requires
// a uniform border color whenever borderRadius is set — the mismatch threw
// "A borderRadius can only be given on borders with uniform colors" during
// paint, which silently blanked the whole card (no title, content, or
// image) instead of showing a build-time error. Caught by pumping the
// exact category of real-world data (unusual custom category names, pinned
// posts) that triggered it in production.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uprise/screens/web/org/org_announcements.dart';

void main() {
  testWidgets('PostCard renders a pinned post with a custom category name', (
    tester,
  ) async {
    final announcement = AnnouncementModel(
      id: 'test1',
      title: 'asdadadd',
      content: 'sadsamsnmdsnmsandmasdmsad',
      authorId: 'author1',
      authorName: 'WAAAAAA',
      timestamp: Timestamp.now(),
      attachmentsBase64: const [],
      isPinned: true,
      targetAudience: 'CICT Only',
      category: 'sdsadadlklk',
      linkedProposalId: 'proposal123',
      linkedEventTitle: 'Hack4Change',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: debugPostCardForTest(announcement),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('asdadadd'), findsOneWidget);
    expect(find.text('sadsamsnmdsnmsandmasdmsad'), findsOneWidget);
  });

  testWidgets('PostCard renders a non-pinned post with the default category', (
    tester,
  ) async {
    final announcement = AnnouncementModel(
      id: 'test2',
      title: 'Application Extension',
      content: 'The deadline has been moved.',
      authorId: 'author2',
      authorName: 'Ay Ambot',
      timestamp: Timestamp.now(),
      attachmentsBase64: const [],
      isPinned: false,
      targetAudience: 'CICT Only',
      category: 'General',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: debugPostCardForTest(announcement),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Application Extension'), findsOneWidget);
  });

  testWidgets('PostCard renders a post with an attached image without overflowing', (
    tester,
  ) async {
    // A minimal 1x1 PNG — enough for Image.memory to actually decode and lay
    // out real pixels, which is what triggers the accent-bar sizing bug
    // (IntrinsicHeight's separate intrinsic-height pass for a Column
    // containing this image could compute a height a couple pixels short of
    // what the image actually rendered at, throwing "A RenderFlex overflowed
    // by 2.0 pixels" — invisible with no image attached, which is why the
    // other two tests above didn't catch it).
    const tinyPngBase64 =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
    final announcement = AnnouncementModel(
      id: 'test3',
      title: 'Crafthon',
      content: 'aaaaaaaaaaaaa',
      authorId: 'author3',
      authorName: 'WAAAAAA',
      timestamp: Timestamp.now(),
      attachmentsBase64: const [],
      isPinned: false,
      targetAudience: 'CICT Only',
      category: 'event',
      imageBase64: tinyPngBase64,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: debugPostCardForTest(announcement),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Crafthon'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });
}

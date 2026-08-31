// Regression test for the tap-to-expand hero images.
//
// The detail screens layer a gradient scrim and badge overlays above the image
// inside a Stack. Those overlays are Containers with a BoxDecoration, and
// BoxDecoration.hitTest returns true for a plain rectangle — so when the tap
// handler sat on the image alone, the overlays (painted above it, and therefore
// hit-tested first) swallowed every tap and the viewer never opened.
//
// The fix hangs the handler above the whole Stack, where it still receives what
// a child absorbs. These tests pin both halves of that: the overlay really does
// absorb, and wrapping the Stack really does fix it.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uprise/widgets/common/image_viewer.dart';

// Smallest valid PNG: a 1x1 transparent pixel, so AppImage.provider resolves a
// real MemoryImage without touching the network.
const _pngB64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
    'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';
final _source = 'data:image/png;base64,$_pngB64';

/// The scrim the detail screens paint over their hero.
Widget _scrim() => Container(
  decoration: const BoxDecoration(
    gradient: LinearGradient(colors: [Colors.transparent, Colors.black]),
  ),
);

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: SizedBox(width: 300, height: 200, child: child)));

void main() {
  testWidgets('overlay absorbs the tap when the handler is on the image only', (
    tester,
  ) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (c) {
            ctx = c;
            return Stack(
              fit: StackFit.expand,
              children: [
                // Handler on the image alone — the shape that was broken.
                expandableImage(
                  context: ctx,
                  source: _source,
                  child: const SizedBox.expand(),
                ),
                _scrim(),
              ],
            );
          },
        ),
      ),
    );

    await tester.tap(find.byType(Stack).first, warnIfMissed: false);
    await tester.pumpAndSettle();

    // No dialog: the scrim ate it. This is the bug, pinned.
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(InteractiveViewer), findsNothing);
  });

  testWidgets('wrapping the whole Stack opens the viewer through the overlay', (
    tester,
  ) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (c) {
            ctx = c;
            return expandableImage(
              context: ctx,
              source: _source,
              child: Stack(
                fit: StackFit.expand,
                children: [const SizedBox.expand(), _scrim()],
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.byType(Stack).first, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.byType(InteractiveViewer), findsOneWidget);
  });

  testWidgets('an empty source stays inert — no viewer, no gesture', (
    tester,
  ) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (c) {
            ctx = c;
            return expandableImage(
              context: ctx,
              source: '',
              child: const SizedBox.expand(),
            );
          },
        ),
      ),
    );

    expect(find.byType(GestureDetector), findsNothing);

    await tester.tap(find.byType(SizedBox).first, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
  });
}

// lib/widgets/common/image_viewer.dart
//
// One full-size, pinch-to-zoom image viewer for the mobile app. Promoted out
// of student_broadcast_screen.dart, whose local copy carried the note "tapping
// a photo message used to do nothing, the thumbnail was the only way to see
// it" — the same complaint applied to announcement images and event banners,
// so the viewer lives here now and every call site shares it.
//
// Sources go through AppImage.provider rather than a local base64 decode, so
// this understands everything the rest of the app stores: a `data:image` URI,
// the malformed `dataimage...` variant seen in some records, raw base64, and
// http(s) URLs.

import 'package:flutter/material.dart';

import '../student/app_image.dart';

/// Opens [source] full-screen over the current route.
///
/// Does nothing when [source] is empty or can't be resolved to an image, so
/// callers can wire this to a tap handler without first checking whether the
/// widget is showing a real picture or a placeholder — see [expandableImage].
void showFullscreenImage(BuildContext context, String source) {
  final provider = AppImage.provider(source);
  if (provider == null) return;

  showDialog(
    context: context,
    barrierColor: Colors.black87,
    builder: (ctx) => Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.pop(ctx),
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: Center(
                child: Image(
                  image: provider,
                  // A source that resolves but fails to decode would otherwise
                  // leave an empty black screen with no way to tell whether
                  // the tap registered.
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white54,
                    size: 64,
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 24,
          right: 24,
          child: IconButton(
            icon: const Icon(
              Icons.close_rounded,
              color: Colors.white,
              size: 28,
            ),
            onPressed: () => Navigator.pop(ctx),
          ),
        ),
      ],
    ),
  );
}

/// Wraps [child] so tapping it opens [source] full-screen.
///
/// Returns [child] untouched when there is no image to open, which keeps a
/// placeholder from looking interactive — no ripple, no cursor change, no
/// dialog that opens onto nothing.
Widget expandableImage({
  required BuildContext context,
  required String source,
  required Widget child,
}) {
  if (AppImage.provider(source) == null) return child;
  return GestureDetector(
    onTap: () => showFullscreenImage(context, source),
    child: child,
  );
}

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

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../utils/download_saver.dart';
import '../student/app_image.dart';

/// Opens [source] full-screen over the current route.
///
/// Does nothing when [source] is empty or can't be resolved to an image, so
/// callers can wire this to a tap handler without first checking whether the
/// widget is showing a real picture or a placeholder — see [expandableImage].
///
/// [downloadName], when given, adds a download button that saves the photo to
/// the phone's Downloads folder under that name (the extension is added from
/// the image itself). Message photos pass one; banners and announcement images
/// don't, so they stay view-only.
void showFullscreenImage(
  BuildContext context,
  String source, {
  String? downloadName,
}) {
  final provider = AppImage.provider(source);
  if (provider == null) return;

  showDialog(
    context: context,
    barrierColor: Colors.black87,
    builder: (_) => _FullscreenImage(
      source: source,
      provider: provider,
      downloadName: downloadName,
    ),
  );
}

/// A default [showFullscreenImage] download name: "UPRISE_photo_20260927_1301".
String timestampedPhotoName([String prefix = 'UPRISE_photo']) =>
    '${prefix}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}';

class _FullscreenImage extends StatefulWidget {
  final String source;
  final ImageProvider provider;
  final String? downloadName;

  const _FullscreenImage({
    required this.source,
    required this.provider,
    required this.downloadName,
  });

  @override
  State<_FullscreenImage> createState() => _FullscreenImageState();
}

class _FullscreenImageState extends State<_FullscreenImage> {
  bool _saving = false;

  /// Status shown over the photo. The dialog's barrier sits on top of the
  /// app's own Scaffold, so a normal SnackBar would render hidden behind it.
  String? _status;
  SavedDownload? _saved;

  Future<Uint8List> _bytes() async {
    final decoded = decodeAppImageBytes(widget.source);
    if (decoded != null) return decoded;
    final res = await http.get(Uri.parse(widget.source));
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}');
    }
    return res.bodyBytes;
  }

  Future<void> _download() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _status = null;
      _saved = null;
    });
    try {
      final bytes = await _bytes();
      final saved = await saveToDownloads(
        bytes,
        '${widget.downloadName}.${imageExtensionFor(bytes)}',
      );
      if (!mounted) return;
      setState(() {
        _saved = saved;
        _status = saved.inDownloads
            ? 'Saved to Downloads · ${saved.name}'
            : 'Saved · ${saved.name}';
      });
      if (!saved.inDownloads) await saved.open();
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Could not download photo');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved = _saved;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: Center(
                child: Image(
                  image: widget.provider,
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
          child: Row(
            children: [
              if (widget.downloadName != null)
                IconButton(
                  tooltip: 'Download',
                  onPressed: _saving ? null : _download,
                  icon: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.download_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 28,
                ),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        if (_status != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 32,
            child: SafeArea(
              top: false,
              child: Material(
                color: const Color(0xFF323232),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _status!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                      if (saved != null && saved.inDownloads)
                        TextButton(
                          onPressed: saved.open,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                          ),
                          child: const Text(
                            'Open',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        )
                      else
                        const SizedBox(height: 36),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
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

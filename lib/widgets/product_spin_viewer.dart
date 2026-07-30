import 'dart:convert';
import 'package:flutter/material.dart';

/// A drag-to-rotate product viewer — the classic e-commerce "360 view"
/// built from a sequence of angle photos rather than a real 3D model, so
/// orgs just need to take multiple photos of a product turntable-style
/// instead of authoring 3D assets.
///
/// Pass 1 photo for a plain static image, or several (8+ recommended) for
/// a smooth spin. Dragging horizontally scrubs through the frames.
class ProductSpinViewer extends StatefulWidget {
  final List<String> photosBase64;
  final double height;
  final BorderRadius? borderRadius;

  const ProductSpinViewer({
    super.key,
    required this.photosBase64,
    this.height = 280,
    this.borderRadius,
  });

  @override
  State<ProductSpinViewer> createState() => _ProductSpinViewerState();
}

class _ProductSpinViewerState extends State<ProductSpinViewer> {
  int _frame = 0;
  double _dragAccum = 0;
  bool _hasDragged = false;

  // Pixels of horizontal drag needed to advance one frame — smaller means
  // more sensitive spinning.
  static const double _pxPerFrame = 12;

  @override
  void didUpdateWidget(covariant ProductSpinViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.photosBase64.length != oldWidget.photosBase64.length) {
      _frame = 0;
    }
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final count = widget.photosBase64.length;
    if (count <= 1) return;
    _dragAccum += details.delta.dx;
    final step = (_dragAccum / _pxPerFrame).truncate();
    if (step == 0) return;
    _dragAccum -= step * _pxPerFrame;
    setState(() {
      _hasDragged = true;
      _frame = (_frame - step) % count;
      if (_frame < 0) _frame += count;
    });
  }

  ImageProvider? _decode(String b64) {
    try {
      var clean = b64;
      final comma = clean.indexOf(',');
      if (clean.startsWith('data:') && comma != -1) {
        clean = clean.substring(comma + 1);
      }
      return MemoryImage(base64Decode(clean));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? BorderRadius.circular(12);
    final photos = widget.photosBase64;

    if (photos.isEmpty) {
      return Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: radius,
        ),
        child: const Center(
          child: Icon(Icons.image_outlined, size: 40, color: Color(0xFFB0BAC8)),
        ),
      );
    }

    final canSpin = photos.length > 1;
    final image = _decode(photos[_frame.clamp(0, photos.length - 1)]);

    return ClipRRect(
      borderRadius: radius,
      child: MouseRegion(
        cursor: canSpin ? SystemMouseCursors.grab : SystemMouseCursors.basic,
        child: GestureDetector(
          onHorizontalDragUpdate: canSpin ? _onDragUpdate : null,
          child: Container(
            height: widget.height,
            width: double.infinity,
            color: const Color(0xFFF8F9FB),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (image != null)
                  Image(image: image, fit: BoxFit.contain)
                else
                  const Icon(
                    Icons.broken_image_outlined,
                    size: 40,
                    color: Color(0xFFB0BAC8),
                  ),
                if (canSpin && !_hasDragged)
                  Positioned(
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(140),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.threesixty_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Drag to rotate',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (canSpin)
                  Positioned(
                    bottom: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(140),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_frame + 1}/${photos.length}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
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

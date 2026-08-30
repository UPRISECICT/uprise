import 'student/app_image.dart';
import 'package:flutter/material.dart';

/// A swipeable product photo gallery — several angle photos (front, side,
/// back, sole, etc.) shown as plain static slides with a page indicator,
/// the way most e-commerce product pages present multi-angle shots instead
/// of an interactive 360° spin.
///
/// Pass 1 photo for a single static image, or several for a swipeable set.
class ProductPhotoGallery extends StatefulWidget {
  final List<String> photosBase64;
  final double height;
  final BorderRadius? borderRadius;

  const ProductPhotoGallery({
    super.key,
    required this.photosBase64,
    this.height = 280,
    this.borderRadius,
  });

  @override
  State<ProductPhotoGallery> createState() => _ProductPhotoGalleryState();
}

class _ProductPhotoGalleryState extends State<ProductPhotoGallery> {
  final _pageCtrl = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  // AppImage.provider over a local decoder: product photos aren't always
  // inline base64 — a Cloudinary/Storage URL used to fall through to null here
  // and render as a missing photo.
  ImageProvider? _decode(String b64) => AppImage.provider(b64);

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

    final multiple = photos.length > 1;
    // Clamp in case a previous photo set was longer and _index hasn't reset.
    final safeIndex = _index.clamp(0, photos.length - 1);

    return ClipRRect(
      borderRadius: radius,
      child: Container(
        height: widget.height,
        width: double.infinity,
        color: const Color(0xFFF8F9FB),
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            PageView.builder(
              controller: _pageCtrl,
              itemCount: photos.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) {
                final image = _decode(photos[i]);
                return image != null
                    ? Image(image: image, fit: BoxFit.contain)
                    : const Icon(
                        Icons.broken_image_outlined,
                        size: 40,
                        color: Color(0xFFB0BAC8),
                      );
              },
            ),
            if (multiple)
              Positioned(
                top: 10,
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
                    '${safeIndex + 1}/${photos.length}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            if (multiple)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(photos.length, (i) {
                    final active = i == safeIndex;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: active ? 16 : 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: active
                            ? Colors.white
                            : Colors.white.withAlpha(130),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

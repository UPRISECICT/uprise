// lib/widgets/student/app_image.dart
//
// Single shared image renderer for the student mobile app. Replaces the 9
// independently-reimplemented base64/network decoders that used to live in
// student_announcements_screen.dart, student_certificates_screen.dart,
// student_home_screen.dart, student_organizations_screen.dart,
// student_organization_details_screen.dart and student_profile_screen.dart.
//
// Source strings it understands: a `data:image...;base64,...` URI, the
// malformed `dataimage...base64,...` variant (no colon — seen in some
// already-stored records), raw base64 with no prefix at all, or an
// http(s) network URL. Firebase Storage URLs are fetched with the current
// user's ID token, matching EventImage's behavior for event banners.
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Decodes [source] to raw bytes if it's base64 in any of the formats this
/// app stores (data URI, malformed data URI missing its colon, or raw
/// base64). Returns null for network URLs, empty strings, or bad data.
Uint8List? decodeAppImageBytes(String source) {
  if (source.isEmpty) return null;
  String data = source;
  if (source.startsWith('dataimage')) {
    final idx = source.indexOf('base64,');
    if (idx == -1) return null;
    data = source.substring(idx + 'base64,'.length);
  } else if (source.startsWith('data:')) {
    final idx = source.indexOf(',');
    if (idx == -1) return null;
    data = source.substring(idx + 1);
  } else if (source.startsWith('http')) {
    return null;
  }
  try {
    return base64Decode(data);
  } catch (_) {
    return null;
  }
}

bool isNetworkImageSource(String source) =>
    source.startsWith('http://') || source.startsWith('https://');

/// First non-empty source out of [candidates], or `''` if there is none.
///
/// Call sites used to write `d['imageBase64'] ?? d['imageUrl'] ?? ''`, but `??`
/// only falls through on **null** and these documents store an explicit empty
/// string — org_merchandise.dart writes `data['imageBase64'] = ''` when a
/// product has no inline photo. A populated `imageUrl` therefore lost to an
/// empty `imageBase64` and the image silently vanished.
String firstNonEmptyImageSource(List<String?> candidates) {
  for (final c in candidates) {
    if (c != null && c.isNotEmpty) return c;
  }
  return '';
}

// Certificate templates uploaded to Cloudinary as a PDF are stored as-is —
// the URL points straight at the raw PDF document, which Flutter's Image
// widgets can't decode as pixels. Cloudinary renders a PDF's first page as
// an actual image when the same asset is requested with a raster extension
// instead, so swapping .pdf for .jpg is enough to get a real image back.
// Scoped to Cloudinary URLs specifically rather than every .pdf source, so
// this can't affect unrelated network images that happen to end in .pdf.
String _renderablePdfSafeUrl(String url) {
  if (url.contains('res.cloudinary.com') &&
      url.toLowerCase().endsWith('.pdf')) {
    return '${url.substring(0, url.length - 4)}.jpg';
  }
  return url;
}

class AppImage extends StatefulWidget {
  final String source;
  final double? width;
  final double? height;
  final BoxFit fit;
  final bool showLoadingIndicator;

  /// Full override for the empty/loading/error state. Takes priority over
  /// [placeholderIcon]/[placeholderIconSize]/[placeholderColor] when set.
  final Widget? placeholder;
  final IconData placeholderIcon;
  final double placeholderIconSize;
  final Color? placeholderBackgroundColor;
  final Color? placeholderIconColor;

  /// Escape hatch matching Image.errorBuilder, for callers that need full
  /// control (e.g. a different icon per call site). Takes priority over
  /// every other placeholder option.
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;

  const AppImage({
    super.key,
    required this.source,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.showLoadingIndicator = true,
    this.placeholder,
    this.placeholderIcon = Icons.image_not_supported,
    this.placeholderIconSize = 32,
    this.placeholderBackgroundColor,
    this.placeholderIconColor,
    this.errorBuilder,
  });

  /// Synchronous [ImageProvider] for CircleAvatar.backgroundImage /
  /// DecorationImage.image call sites. Cannot perform the authenticated
  /// Firebase Storage fetch [AppImage] does for network sources (those
  /// call sites never authenticated network fetches before either), so a
  /// plain NetworkImage is used for http(s) sources.
  static ImageProvider? provider(String source) {
    if (source.isEmpty) return null;
    final bytes = decodeAppImageBytes(source);
    if (bytes != null) return MemoryImage(bytes);
    if (isNetworkImageSource(source)) {
      return NetworkImage(_renderablePdfSafeUrl(source));
    }
    return null;
  }

  @override
  State<AppImage> createState() => _AppImageState();
}

class _AppImageState extends State<AppImage> {
  Future<ImageProvider?>? _futureProvider;

  @override
  void initState() {
    super.initState();
    _resolveProvider();
  }

  @override
  void didUpdateWidget(covariant AppImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _resolveProvider();
    }
  }

  void _resolveProvider() {
    final source = widget.source;
    if (source.isEmpty) {
      _futureProvider = null;
      return;
    }

    final bytes = decodeAppImageBytes(source);
    if (bytes != null) {
      _futureProvider = Future.value(MemoryImage(bytes));
      return;
    }

    if (isNetworkImageSource(source)) {
      _futureProvider = _fetchNetworkImage(_renderablePdfSafeUrl(source));
      return;
    }

    _futureProvider = null;
  }

  Future<ImageProvider> _fetchNetworkImage(String url) async {
    final isFirebaseStorage = url.contains('firebasestorage.googleapis.com');

    if (isFirebaseStorage) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        try {
          final token = await user.getIdToken();
          final resp = await http.get(
            Uri.parse(url),
            headers: {'Authorization': 'Bearer $token'},
          );
          if (resp.statusCode == 200) {
            return MemoryImage(resp.bodyBytes);
          }
        } catch (_) {}
      }
    }

    return NetworkImage(url);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.source.isEmpty || _futureProvider == null) {
      return _placeholder(context);
    }

    return FutureBuilder<ImageProvider?>(
      future: _futureProvider,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return widget.showLoadingIndicator
              ? Container(
                  height: widget.height,
                  width: widget.width,
                  color: Colors.grey.shade100,
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : _placeholder(context);
        }

        if (snapshot.hasData && snapshot.data != null) {
          return Image(
            image: snapshot.data!,
            height: widget.height,
            width: widget.width,
            fit: widget.fit,
            errorBuilder:
                widget.errorBuilder ?? (_, __, ___) => _placeholder(context),
          );
        }

        return _placeholder(context);
      },
    );
  }

  Widget _placeholder(BuildContext context) {
    if (widget.errorBuilder != null) {
      return widget.errorBuilder!(context, 'no image', null);
    }
    if (widget.placeholder != null) return widget.placeholder!;
    return Container(
      height: widget.height,
      width: widget.width,
      color: widget.placeholderBackgroundColor ?? Colors.grey.shade200,
      child: Center(
        child: Icon(
          widget.placeholderIcon,
          color: widget.placeholderIconColor ?? Colors.grey.shade400,
          size: widget.placeholderIconSize,
        ),
      ),
    );
  }
}

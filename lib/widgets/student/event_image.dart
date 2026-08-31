// lib/widgets/student/event_image.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../common/image_viewer.dart';

class EventImage extends StatefulWidget {
  final String imageUrl;
  final double? height;
  final double? width;
  final BoxFit fit;
  final bool showLoadingIndicator;

  /// Whether tapping the banner opens it full-screen.
  ///
  /// Off by default so the admin report screens, which render this inside
  /// their own layouts, keep behaving as they did. The mobile card and detail
  /// call sites opt in — they crop with BoxFit.cover, so the full picture is
  /// otherwise unreachable.
  final bool expandable;

  const EventImage({
    super.key,
    required this.imageUrl,
    this.height,
    this.width,
    this.fit = BoxFit.cover,
    this.showLoadingIndicator = true,
    this.expandable = false,
  });

  @override
  State<EventImage> createState() => _EventImageState();
}

class _EventImageState extends State<EventImage> {
  Future<ImageProvider?>? _futureProvider;

  @override
  void initState() {
    super.initState();
    _resolveProvider();
  }

  @override
  void didUpdateWidget(covariant EventImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _resolveProvider();
    }
  }

  void _resolveProvider() {
    final url = widget.imageUrl;
    if (url.isEmpty) {
      _futureProvider = null;
      return;
    }

    // 1. Base64 image (data:image...)
    if (url.startsWith('data:image')) {
      try {
        final b64 = url.contains(',') ? url.split(',').last : url;
        final bytes = base64Decode(b64);
        _futureProvider = Future.value(MemoryImage(bytes));
        return;
      } catch (_) {}
    }

    // 2. Raw base64 (no http prefix, not data:image)
    if (!url.startsWith('http')) {
      try {
        final bytes = base64Decode(url);
        _futureProvider = Future.value(MemoryImage(bytes));
        return;
      } catch (_) {}
    }

    // 3. Network URL – need to handle Firebase Storage auth
    _futureProvider = _fetchNetworkImage(url);
  }

  Future<ImageProvider> _fetchNetworkImage(String url) async {
    final isFirebaseStorage = url.contains('firebasestorage.googleapis.com');

    if (isFirebaseStorage) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final token = await user.getIdToken();
        try {
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

    // fallback: try as normal network image
    return NetworkImage(url);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.imageUrl.isEmpty || _futureProvider == null) {
      return _placeholder();
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
              : _placeholder();
        }

        if (snapshot.hasData && snapshot.data != null) {
          final image = Image(
            image: snapshot.data!,
            height: widget.height,
            width: widget.width,
            fit: widget.fit,
            errorBuilder: (_, __, ___) => _placeholder(),
          );
          // Only a resolved image is tappable — a placeholder has nothing to
          // open, so the gesture stays off in every other branch below.
          if (!widget.expandable) return image;
          return GestureDetector(
            onTap: () => showFullscreenImage(context, widget.imageUrl),
            child: image,
          );
        }

        return _placeholder();
      },
    );
  }

  Widget _placeholder() {
    return Container(
      height: widget.height,
      width: widget.width,
      color: Colors.grey.shade200,
      child: Center(
        child: Icon(
          Icons.image_not_supported,
          color: Colors.grey.shade400,
          size: 32,
        ),
      ),
    );
  }
}
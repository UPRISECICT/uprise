// lib/utils/download_saver.dart
//
// "Download" on mobile means the file lands in the phone's Downloads folder —
// not a share sheet, and not the app's private storage where the user can
// never find it again. Used by the Digital ID PDF and by message attachments
// (files and photos) in the org broadcast thread.
//
// The file I/O itself lives behind the project's stub/io conditional import:
// this file is reachable from the web build (image_viewer.dart ← event_image
// ← the web reports screens), which must never import dart:io directly. On
// web, saving throws UnsupportedError; nothing there offers a download.

import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'download_saver_stub.dart'
    if (dart.library.io) 'download_saver_io.dart'
    as platform;

/// Where a download ended up.
class SavedDownload {
  final String path;

  /// True when it went to the public Downloads folder; false when that wasn't
  /// writable and it was kept in the app's own storage instead.
  final bool inDownloads;

  const SavedDownload(this.path, {required this.inDownloads});

  String get name => Uri.file(path).pathSegments.last;

  Future<void> open() => platform.openPath(path);
}

/// Strips characters no filesystem accepts, so a sender's file name (or an
/// org name baked into one) can't break the write.
String _safeFileName(String name) {
  final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_').trim();
  return cleaned.isEmpty ? 'download' : cleaned;
}

/// Writes [bytes] straight to the phone's public Downloads folder. Android 11+
/// lets an app create files there without any permission; older Android (or
/// a denied write) falls back to the app's own documents folder. A name that
/// is already taken gets " (1)", " (2)", ... rather than overwriting.
Future<SavedDownload> saveToDownloads(Uint8List bytes, String fileName) async {
  final result = await platform.writeToDownloads(
    bytes,
    _safeFileName(fileName),
  );
  return SavedDownload(result.path, inDownloads: result.inDownloads);
}

/// Tells the user where [saved] went. In Downloads: a snackbar with an Open
/// action. Kept in app storage: the file is opened right away, since the user
/// has no other way to reach it.
Future<void> announceDownload(
  ScaffoldMessengerState messenger,
  SavedDownload saved,
) async {
  messenger.hideCurrentSnackBar();
  if (saved.inDownloads) {
    messenger.showSnackBar(
      SnackBar(
        content: Text('Saved to Downloads · ${saved.name}'),
        action: SnackBarAction(
          label: 'Open',
          textColor: Colors.white,
          onPressed: saved.open,
        ),
      ),
    );
    return;
  }
  messenger.showSnackBar(SnackBar(content: Text('Saved · ${saved.name}')));
  await saved.open();
}

/// File extension for raw image bytes, read from the header rather than
/// trusted from a data-URI prefix (some stored records have none).
String imageExtensionFor(Uint8List bytes) {
  if (bytes.length >= 4) {
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E) return 'png';
    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) return 'gif';
    if (bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46) {
      return 'webp';
    }
  }
  return 'jpg';
}

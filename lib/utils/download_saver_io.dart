// Mobile side of download_saver.dart.

import 'dart:io';
import 'dart:typed_data';

import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';

/// [dir]/[fileName], or "name (1).ext", "name (2).ext", ... when taken, so a
/// second download never overwrites (or fails on) the first.
Future<File> _uniqueFile(Directory dir, String fileName) async {
  final dot = fileName.lastIndexOf('.');
  final base = dot <= 0 ? fileName : fileName.substring(0, dot);
  final ext = dot <= 0 ? '' : fileName.substring(dot);
  var file = File('${dir.path}/$fileName');
  var n = 1;
  while (await file.exists()) {
    file = File('${dir.path}/$base ($n)$ext');
    n++;
  }
  return file;
}

Future<({String path, bool inDownloads})> writeToDownloads(
  Uint8List bytes,
  String fileName,
) async {
  if (Platform.isAndroid) {
    try {
      final downloads = Directory('/storage/emulated/0/Download');
      if (await downloads.exists()) {
        final file = await _uniqueFile(downloads, fileName);
        await file.writeAsBytes(bytes, flush: true);
        return (path: file.path, inDownloads: true);
      }
    } catch (_) {
      // Not writable (older Android without storage permission) — fall
      // through to the app's own storage.
    }
  }
  final dir = await getApplicationDocumentsDirectory();
  final file = await _uniqueFile(dir, fileName);
  await file.writeAsBytes(bytes, flush: true);
  return (path: file.path, inDownloads: false);
}

Future<void> openPath(String path) async {
  await OpenFile.open(path);
}

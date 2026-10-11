// Mobile side of download_saver.dart.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';

const _downloadChannel = MethodChannel('com.example.uprise/downloads');

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

Future<({String path, String name, bool inDownloads})> writeToDownloads(
  Uint8List bytes,
  String fileName,
) async {
  if (Platform.isAndroid) {
    final result = await _downloadChannel.invokeMapMethod<String, dynamic>(
      'saveToDownloads',
      {'bytes': bytes, 'fileName': fileName},
    );
    if (result == null || result['uri'] == null) {
      throw StateError('Android did not return a Downloads location.');
    }
    return (
      path: result['uri'] as String,
      name: (result['name'] as String?) ?? fileName,
      inDownloads: true,
    );
  }
  final dir = await getApplicationDocumentsDirectory();
  final file = await _uniqueFile(dir, fileName);
  await file.writeAsBytes(bytes, flush: true);
  return (path: file.path, name: fileName, inDownloads: false);
}

Future<void> openPath(String path) async {
  if (Platform.isAndroid && path.startsWith('content://')) {
    await _downloadChannel.invokeMethod<void>('openDownload', {'uri': path});
    return;
  }
  await OpenFile.open(path);
}

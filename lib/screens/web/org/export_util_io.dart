import 'dart:convert';
import 'dart:io';
import 'package:share_plus/share_plus.dart';

class OrgExportUtil {
  static Future<void> saveText(
    String content,
    String fileName, {
    String mimeType = 'text/plain',
  }) async {
    return saveBytes(utf8.encode(content), fileName, mimeType: mimeType);
  }

  static Future<void> saveBytes(
    List<int> bytes,
    String fileName, {
    String mimeType = 'application/octet-stream',
  }) async {
    final file = File('${Directory.systemTemp.path}/$fileName');
    await file.writeAsBytes(bytes);
    await Share.shareXFiles([XFile(file.path)], subject: fileName);
  }
}

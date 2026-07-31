// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

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
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final blob = html.Blob([data], mimeType);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..setAttribute('target', '_blank')
      ..setAttribute('rel', 'noopener noreferrer')
      ..style.display = 'none';

    html.document.body?.append(anchor);
    anchor.click();
    await Future.delayed(const Duration(milliseconds: 250));
    anchor.remove();
    html.Url.revokeObjectUrl(url);
  }
}

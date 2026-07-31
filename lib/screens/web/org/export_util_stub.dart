class OrgExportUtil {
  static Future<void> saveText(
    String content,
    String fileName, {
    String mimeType = 'text/plain',
  }) async {
    throw UnsupportedError('OrgExportUtil is not supported on this platform.');
  }

  static Future<void> saveBytes(
    List<int> bytes,
    String fileName, {
    String mimeType = 'application/octet-stream',
  }) async {
    throw UnsupportedError('OrgExportUtil is not supported on this platform.');
  }
}

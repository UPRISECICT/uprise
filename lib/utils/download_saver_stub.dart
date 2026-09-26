// Web side of download_saver.dart — nothing on web offers a download through
// it, so these only exist to keep the conditional import resolvable.

import 'dart:typed_data';

Future<({String path, bool inDownloads})> writeToDownloads(
  Uint8List bytes,
  String fileName,
) {
  throw UnsupportedError('Saving to Downloads is mobile-only.');
}

Future<void> openPath(String path) {
  throw UnsupportedError('Opening saved files is mobile-only.');
}

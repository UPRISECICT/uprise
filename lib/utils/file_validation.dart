import 'dart:typed_data';

/// Shared file/image upload validation used across admin screens (org
/// logos, e-signatures, profile photos, bulk-import spreadsheets) so every
/// upload site enforces the same size and type rules instead of trusting
/// the OS file picker's filter alone.
class FileValidation {
  static const int defaultMaxImageBytes = 5 * 1024 * 1024; // 5MB
  static const int defaultMaxDocumentBytes = 10 * 1024 * 1024; // 10MB

  /// Returns an error message if [bytes] isn't a supported, in-size image,
  /// or null if it's valid. Checks actual file content (magic bytes), not
  /// just the file extension, since a renamed file would otherwise pass.
  static String? validateImageBytes(
    Uint8List bytes, {
    int maxSizeBytes = defaultMaxImageBytes,
  }) {
    if (bytes.isEmpty) return 'The selected file is empty.';
    if (bytes.lengthInBytes > maxSizeBytes) {
      return 'Image is too large (${_formatSize(bytes.lengthInBytes)}). '
          'Max size is ${_formatSize(maxSizeBytes)}.';
    }
    if (!_looksLikeImage(bytes)) {
      return 'Unsupported file type. Please upload a PNG, JPEG, WEBP, or GIF image.';
    }
    return null;
  }

  /// Returns an error message if [bytes] exceeds [maxSizeBytes], or null if
  /// it's within limits. For non-image uploads (spreadsheets, PDFs) where
  /// content-sniffing isn't relevant — extension filtering is expected to
  /// already be handled by the file picker's `allowedExtensions`.
  static String? validateFileSize(
    Uint8List bytes, {
    int maxSizeBytes = defaultMaxDocumentBytes,
  }) {
    if (bytes.isEmpty) return 'The selected file is empty.';
    if (bytes.lengthInBytes > maxSizeBytes) {
      return 'File is too large (${_formatSize(bytes.lengthInBytes)}). '
          'Max size is ${_formatSize(maxSizeBytes)}.';
    }
    return null;
  }

  static bool _looksLikeImage(Uint8List bytes) {
    if (bytes.length < 4) return false;
    // PNG: 89 50 4E 47
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return true;
    }
    // JPEG: FF D8 FF
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return true;
    }
    // GIF: 47 49 46 38
    if (bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38) {
      return true;
    }
    // WEBP: RIFF....WEBP
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return true;
    }
    return false;
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}

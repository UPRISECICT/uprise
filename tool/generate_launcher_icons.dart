// tool/generate_launcher_icons.dart
//
// Regenerates the Android launcher icons from assets/images/logo.png.
//
// Run from the project root:
//   dart run tool/generate_launcher_icons.dart
//
// Uses the `image` package, which is already a direct dependency — no extra
// tooling or network access needed. Re-run this after changing the source
// logo; the five mipmap PNGs are generated output, not hand-edited files.
//
// Android's legacy launcher icons keep alpha, so the logo's transparent
// background is preserved as-is. The source is padded to a square first:
// scaling a non-square image straight to a square target would stretch it.

import 'dart:io';

import 'package:image/image.dart' as img;

/// Android density buckets and the icon edge length each one expects.
const _densities = <String, int>{
  'mdpi': 48,
  'hdpi': 72,
  'xhdpi': 96,
  'xxhdpi': 144,
  'xxxhdpi': 192,
};

const _source = 'assets/images/logo.png';
const _resDir = 'android/app/src/main/res';

void main() {
  final file = File(_source);
  if (!file.existsSync()) {
    stderr.writeln('Source logo not found: $_source');
    exitCode = 1;
    return;
  }

  final decoded = img.decodePng(file.readAsBytesSync());
  if (decoded == null) {
    stderr.writeln('Could not decode $_source as PNG.');
    exitCode = 1;
    return;
  }
  stdout.writeln('Source: ${decoded.width}x${decoded.height}');

  final square = _padToSquare(decoded);

  for (final entry in _densities.entries) {
    final resized = img.copyResize(
      square,
      width: entry.value,
      height: entry.value,
      // The logo has fine detail (the gear teeth and the lettering ring) that
      // turns to mush at 48px under a cheaper filter.
      interpolation: img.Interpolation.cubic,
    );

    final out = File('$_resDir/mipmap-${entry.key}/ic_launcher.png');
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(img.encodePng(resized));
    stdout.writeln('  wrote ${out.path} (${entry.value}x${entry.value})');
  }

  stdout.writeln('Done.');
}

/// Centres [src] on a transparent square canvas of its longest edge, so the
/// square resize below scales rather than distorts it.
img.Image _padToSquare(img.Image src) {
  if (src.width == src.height) return src;
  final side = src.width > src.height ? src.width : src.height;
  final canvas = img.Image(
    width: side,
    height: side,
    numChannels: 4,
  );
  // Fully transparent ground; compositing the logo over it leaves the padding
  // clear rather than black.
  img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));
  img.compositeImage(
    canvas,
    src,
    dstX: (side - src.width) ~/ 2,
    dstY: (side - src.height) ~/ 2,
  );
  return canvas;
}

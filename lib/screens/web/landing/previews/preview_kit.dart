import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../landing_palette.dart';

// Primitives for the illustrative, non-interactive UI previews on the
// landing pages. They borrow the look of the real dashboards (white cards,
// soft borders, brand accents) without being wired to any data — every
// window is labelled "Preview" so nothing reads as a live screenshot.

TextStyle previewText(
  double size, {
  FontWeight weight = FontWeight.w500,
  Color color = const Color(0xFF111827),
  double? height,
  double spacing = 0,
}) => GoogleFonts.beVietnamPro(
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: height,
  letterSpacing: spacing,
);

/// Browser-style frame: traffic-light dots, a title, and a "Preview" tag.
class PreviewWindow extends StatelessWidget {
  final LandingPalette palette;
  final String title;
  final Widget child;
  final double width;
  final double height;

  const PreviewWindow({
    required this.palette,
    required this.title,
    required this.child,
    required this.width,
    required this.height,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: palette.ink.withAlpha(28),
            blurRadius: 50,
            offset: const Offset(0, 26),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: palette.bg,
              border: Border(bottom: BorderSide(color: palette.border)),
            ),
            child: Row(
              children: [
                for (final c in const [
                  Color(0xFFFCA5A5),
                  Color(0xFFFCD34D),
                  Color(0xFF86EFAC),
                ]) ...[
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                ],
                const SizedBox(width: 10),
                Text(
                  title,
                  style: previewText(
                    11,
                    weight: FontWeight.w700,
                    color: palette.inkSoft,
                  ),
                ),
                const Spacer(),
                PreviewPill(text: 'Preview', color: palette.inkSoft),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Plain floating card used for the smaller layered previews.
class PreviewCard extends StatelessWidget {
  final LandingPalette palette;
  final Widget child;
  final double width;
  final EdgeInsets padding;

  const PreviewCard({
    required this.palette,
    required this.child,
    required this.width,
    this.padding = const EdgeInsets.all(16),
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: palette.ink.withAlpha(30),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: child,
    );
  }
}

class PreviewPill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;

  const PreviewPill({
    required this.text,
    required this.color,
    this.icon,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: previewText(9.5, weight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

/// Grey placeholder line standing in for secondary text.
class SkeletonLine extends StatelessWidget {
  final double width;
  final double height;
  final Color color;

  const SkeletonLine({
    required this.width,
    this.height = 7,
    this.color = const Color(0xFFE5E7EB),
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(height),
      ),
    );
  }
}

class IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const IconBadge({
    required this.icon,
    required this.color,
    this.size = 30,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, size: size * 0.52, color: color),
    );
  }
}

class InitialsAvatar extends StatelessWidget {
  final String initials;
  final Color color;
  final double size;

  const InitialsAvatar({
    required this.initials,
    required this.color,
    this.size = 28,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Text(
        initials,
        style: previewText(
          size * 0.36,
          weight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Small floating metric chip.
class StatChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color? color;
  final LandingPalette palette;

  const StatChip({
    required this.icon,
    required this.value,
    required this.label,
    this.color,
    required this.palette,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? palette.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: palette.ink.withAlpha(30),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconBadge(icon: icon, color: c, size: 34),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: previewText(
                  16,
                  weight: FontWeight.w800,
                  color: palette.ink,
                ),
              ),
              Text(label, style: previewText(9.5, color: palette.inkSoft)),
            ],
          ),
        ],
      ),
    );
  }
}

/// KPI tile: icon, label, big value.
class KpiTile extends StatelessWidget {
  final LandingPalette palette;
  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  const KpiTile({
    required this.palette,
    required this.icon,
    required this.label,
    required this.value,
    this.color,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? palette.primary;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          IconBadge(icon: icon, color: c, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: previewText(
                    16,
                    weight: FontWeight.w800,
                    color: palette.ink,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: previewText(9.5, color: palette.inkSoft),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Simple bar chart from plain containers.
class MiniBars extends StatelessWidget {
  final List<double> values;
  final Color color;
  final double height;
  final int highlight;

  const MiniBars({
    required this.values,
    required this.color,
    this.height = 80,
    this.highlight = -1,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final maxV = values.reduce(math.max);
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++) ...[
            Expanded(
              child: Container(
                height: height * values[i] / maxV,
                decoration: BoxDecoration(
                  color: i == highlight ? color : color.withAlpha(70),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            if (i < values.length - 1) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

/// Smooth line chart with a soft fill underneath.
class MiniLine extends StatelessWidget {
  final List<double> values;
  final Color color;
  final double height;

  const MiniLine({
    required this.values,
    required this.color,
    this.height = 70,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _LinePainter(values, color)),
    );
  }
}

class _LinePainter extends CustomPainter {
  final List<double> values;
  final Color color;

  _LinePainter(this.values, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final maxV = values.reduce(math.max);
    final minV = values.reduce(math.min);
    final span = (maxV - minV) == 0 ? 1 : maxV - minV;
    final pts = [
      for (var i = 0; i < values.length; i++)
        Offset(
          size.width * i / (values.length - 1),
          size.height - (values[i] - minV) / span * size.height * 0.85 - 4,
        ),
    ];
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1];
      final b = pts[i];
      final mid = (a.dx + b.dx) / 2;
      line.cubicTo(mid, a.dy, mid, b.dy, b.dx, b.dy);
    }
    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withAlpha(60), color.withAlpha(0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(pts.last, 3.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) =>
      old.values != values || old.color != color;
}

/// A deterministic QR-looking pattern (decorative, not a scannable code).
class PseudoQr extends StatelessWidget {
  final double size;
  final Color color;
  final int seed;

  const PseudoQr({
    required this.size,
    required this.color,
    this.seed = 7,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _QrPainter(color, seed)),
    );
  }
}

class _QrPainter extends CustomPainter {
  final Color color;
  final int seed;

  _QrPainter(this.color, this.seed);

  @override
  void paint(Canvas canvas, Size size) {
    const n = 21;
    final cell = size.width / n;
    final paint = Paint()..color = color;
    final rnd = math.Random(seed);
    bool finder(int x, int y) =>
        (x < 7 && y < 7) || (x >= n - 7 && y < 7) || (x < 7 && y >= n - 7);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (finder(x, y)) continue;
        if (rnd.nextDouble() < 0.47) {
          canvas.drawRect(
            Rect.fromLTWH(x * cell, y * cell, cell + 0.3, cell + 0.3),
            paint,
          );
        }
      }
    }
    for (final o in [
      Offset.zero,
      Offset((n - 7) * cell, 0),
      Offset(0, (n - 7) * cell),
    ]) {
      final outer = Rect.fromLTWH(o.dx, o.dy, cell * 7, cell * 7);
      canvas.drawRRect(
        RRect.fromRectAndRadius(outer.deflate(cell / 2), Radius.circular(cell)),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          outer.deflate(cell * 2),
          Radius.circular(cell / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _QrPainter old) =>
      old.color != color || old.seed != seed;
}

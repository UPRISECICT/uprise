import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';

import 'landing_common.dart';
import 'landing_motion.dart';
import 'landing_palette.dart';

/// Band of oversized words that scroll sideways on their own, endlessly —
/// two rows running in opposite directions. Hovering pauses the band;
/// under reduced motion it stays still.
class WordMarquee extends StatelessWidget {
  final LandingPalette palette;
  final String eyebrow;
  final List<String> words;

  const WordMarquee({
    required this.palette,
    required this.eyebrow,
    required this.words,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final fontSize = w < 600 ? 34.0 : (w < 1000 ? 52.0 : 68.0);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: palette.border),
          bottom: BorderSide(color: palette.border),
        ),
      ),
      padding: EdgeInsets.symmetric(vertical: w < 600 ? 40 : 64),
      child: Column(
        children: [
          Reveal(
            child: LandingContainer(
              child: Center(
                child: Eyebrow(palette: palette, text: eyebrow),
              ),
            ),
          ),
          SizedBox(height: w < 600 ? 20 : 30),
          _TickerRow(
            palette: palette,
            words: words,
            fontSize: fontSize,
            speed: 55,
            solid: true,
          ),
          SizedBox(height: w < 600 ? 4 : 8),
          _TickerRow(
            palette: palette,
            words: words.reversed.toList(),
            fontSize: fontSize,
            speed: -55,
            solid: false,
          ),
        ],
      ),
    );
  }
}

class _TickerRow extends StatefulWidget {
  final LandingPalette palette;
  final List<String> words;
  final double fontSize;

  /// Pixels per second; negative runs left-to-right.
  final double speed;

  /// First row (true) leads with the brand color, second with ink.
  final bool solid;

  const _TickerRow({
    required this.palette,
    required this.words,
    required this.fontSize,
    required this.speed,
    required this.solid,
  });

  @override
  State<_TickerRow> createState() => _TickerRowState();
}

class _TickerRowState extends State<_TickerRow>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  final ValueNotifier<double> _travel = ValueNotifier(0);
  Duration _last = Duration.zero;
  bool _paused = false;

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (!_paused) _travel.value += dt * widget.speed;
  }

  @override
  void initState() {
    super.initState();
    // Re-measure once the web font finishes loading; widths taken with the
    // fallback font would make the loop jump at the seam.
    PaintingBinding.instance.systemFonts.addListener(_onFonts);
  }

  void _onFonts() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = LandingMotion.reduced(context);
    if (reduced && _ticker.isActive) _ticker.stop();
    if (!reduced && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_onFonts);
    _ticker.dispose();
    _travel.dispose();
    super.dispose();
  }

  TextStyle _style(int i) {
    final p = widget.palette;
    return GoogleFonts.beVietnamPro(
      fontSize: widget.fontSize,
      fontWeight: FontWeight.w800,
      height: 1.1,
      letterSpacing: -1.5,
      // Strict brand/ink alternation; the second row starts on the other
      // color so the two rows never line up in the same pattern.
      color: (i % 2 == 0) == widget.solid ? p.primary : p.ink,
    );
  }

  /// An odd word count would put two same-colored words side by side at
  /// the loop seam, so odd lists run as two passes per loop.
  List<String> get _words => widget.words.length.isOdd
      ? [...widget.words, ...widget.words]
      : widget.words;

  @override
  Widget build(BuildContext context) {
    final words = _words;
    final fs = widget.fontSize;
    final gap = fs * 0.45;
    final dot = fs * 0.16;
    final scaler = MediaQuery.textScalerOf(context);

    // Exact width of one pass through the words, so the loop is seamless.
    var segment = 0.0;
    for (var i = 0; i < words.length; i++) {
      final tp = TextPainter(
        text: TextSpan(text: words[i], style: _style(i)),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      segment += tp.width + gap * 2 + dot;
      tp.dispose();
    }

    final copies = segment <= 0
        ? 1
        : (MediaQuery.of(context).size.width / segment).ceil() + 2;

    final row = RepaintBoundary(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var c = 0; c < copies; c++)
            for (var i = 0; i < words.length; i++) ...[
              Text(words[i], style: _style(i)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: gap),
                child: Container(
                  width: dot,
                  height: dot,
                  decoration: BoxDecoration(
                    color: widget.palette.accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
        ],
      ),
    );

    return MouseRegion(
      onEnter: (_) => _paused = true,
      onExit: (_) => _paused = false,
      child: ClipRect(
        child: SizedBox(
          height: fs * 1.25,
          child: OverflowBox(
            alignment: Alignment.centerLeft,
            maxWidth: double.infinity,
            child: ValueListenableBuilder<double>(
              valueListenable: _travel,
              child: row,
              builder: (context, travel, child) {
                // Wrap into [-segment, 0) so the repeated copies line up.
                final x = segment <= 0 ? 0.0 : -(travel % segment);
                return Transform.translate(offset: Offset(x, 0), child: child);
              },
            ),
          ),
        ),
      ),
    );
  }
}

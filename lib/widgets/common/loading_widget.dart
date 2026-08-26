import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const _kPrimary = Color(0xFFB45309);

// ── Full-screen loading spinner ───────────────────────────────────────────────
class UpriseLoader extends StatelessWidget {
  final String? message;
  const UpriseLoader({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(
            color: _kPrimary,
            strokeWidth: 2.5,
          ),
          if (message != null) ...[
            const SizedBox(height: 14),
            Text(
              message!,
              style: GoogleFonts.beVietnamPro(fontSize: 13, color: const Color(0xFF64748B)),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Inline list/card skeleton loader ─────────────────────────────────────────
class SkeletonLoader extends StatefulWidget {
  final int count;
  final double height;
  final double? width;
  final double borderRadius;

  const SkeletonLoader({
    super.key,
    this.count = 3,
    this.height = 80,
    this.width,
    this.borderRadius = 12,
  });

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 0.85).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      // Callers pass a fixed count/height and can't know how much room the
      // viewport actually has, so drop placeholders that wouldn't fit rather
      // than overflowing the Column. The org feed's loading state asked for
      // 3 x 220 (+10 gaps) = 690 in a 670 slot — a 20px overflow.
      //
      // maxHeight is unbounded in a sliver or a scrolling parent; there the
      // requested count is honoured as-is.
      builder: (_, __) => LayoutBuilder(
        builder: (context, constraints) {
          final spacing = widget.height + 10;
          var count = widget.count;
          if (constraints.maxHeight.isFinite && spacing > 0) {
            // n fits when n * height + (n - 1) * 10 <= maxHeight.
            final fits = (constraints.maxHeight + 10) ~/ spacing;
            count = fits.clamp(1, widget.count);
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(
              count,
              (i) => Padding(
                // No trailing gap — it counted against the height budget
                // while adding nothing below the last placeholder.
                padding: EdgeInsets.only(bottom: i == count - 1 ? 0 : 10),
                child: Container(
                  width: widget.width ?? double.infinity,
                  height: widget.height,
                  decoration: BoxDecoration(
                    color: Color.fromRGBO(180, 83, 9, _anim.value * 0.12),
                    borderRadius: BorderRadius.circular(widget.borderRadius),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────
class UpriseEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const UpriseEmptyState({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: _kPrimary.withAlpha(20),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, size: 30, color: _kPrimary.withAlpha(153)),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: GoogleFonts.beVietnamPro(
                fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF1A202C),
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                style: GoogleFonts.beVietnamPro(fontSize: 13, color: const Color(0xFF64748B), height: 1.5),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: onAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(
                  actionLabel!,
                  style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Error state with retry ────────────────────────────────────────────────────
class UpriseErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const UpriseErrorState({
    super.key,
    this.message = 'Something went wrong. Please try again.',
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.error_outline_rounded, size: 30, color: Color(0xFFDC2626)),
            ),
            const SizedBox(height: 16),
            Text(
              'Oops!',
              style: GoogleFonts.beVietnamPro(
                fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF1A202C),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: GoogleFonts.beVietnamPro(fontSize: 13, color: const Color(0xFF64748B), height: 1.5),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: Text('Try Again', style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kPrimary,
                  side: const BorderSide(color: _kPrimary),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

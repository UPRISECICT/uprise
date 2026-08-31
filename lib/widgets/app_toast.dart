// lib/widgets/app_toast.dart
//
// Single shared toast/snackbar system for the whole app — replaces the many
// one-off `ScaffoldMessenger.of(context).showSnackBar(SnackBar(...))` calls
// scattered across admin/org screens (each with its own ad-hoc color and
// dismiss behavior) with 4 consistent types. Every type now auto-dismisses
// (durations scaled to how much there is to read) and every type also shows
// a close button so it can be cleared early — manual-only dismissal for
// error/info turned out to just mean "toast that never goes away":
//   - success: green,  auto-dismisses after 3s
//   - warning: amber,  auto-dismisses after 5s
//   - info:    blue,   auto-dismisses after 5s
//   - error:   red,    auto-dismisses after 7s (longest — most to read)
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum AppToastType { success, error, warning, info }

class AppToast {
  AppToast._();

  static OverlayEntry? _currentEntry;

  static const Color _successBg = Color(0xFF059669);
  static const Color _errorBg = Color(0xFFDC2626);
  static const Color _warningBg = Color(0xFFF59E0B);
  static const Color _infoBg = Color(0xFF2563EB);

  static void success(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) => _show(
    context,
    message,
    type: AppToastType.success,
    actionLabel: actionLabel,
    onAction: onAction,
  );

  static void error(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) => _show(
    context,
    message,
    type: AppToastType.error,
    actionLabel: actionLabel,
    onAction: onAction,
  );

  static void warning(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) => _show(
    context,
    message,
    type: AppToastType.warning,
    actionLabel: actionLabel,
    onAction: onAction,
  );

  static void info(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) => _show(
    context,
    message,
    type: AppToastType.info,
    actionLabel: actionLabel,
    onAction: onAction,
  );

  static void _show(
    BuildContext context,
    String message, {
    required AppToastType type,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    if (!context.mounted) return;
    _currentEntry?.remove();
    _currentEntry = null;

    final (Color accent, IconData icon, String title, Duration duration) =
        switch (type) {
      AppToastType.success => (
        _successBg,
        Icons.check_circle_rounded,
        'Success',
        const Duration(seconds: 3),
      ),
      AppToastType.warning => (
        _warningBg,
        Icons.warning_rounded,
        'Attention needed',
        const Duration(seconds: 5),
      ),
      AppToastType.info => (
        _infoBg,
        Icons.info_rounded,
        'Information',
        const Duration(seconds: 5),
      ),
      AppToastType.error => (
        _errorBg,
        Icons.error_rounded,
        'Something went wrong',
        const Duration(seconds: 7),
      ),
    };

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (overlayContext) => _WebToastOverlay(
        accent: accent,
        icon: icon,
        title: title,
        message: message,
        duration: duration,
        actionLabel: actionLabel,
        onAction: onAction,
        onDismissed: () {
          entry.remove();
          if (identical(_currentEntry, entry)) _currentEntry = null;
        },
      ),
    );
    _currentEntry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
  }
}

class _WebToastOverlay extends StatefulWidget {
  final Color accent;
  final IconData icon;
  final String title;
  final String message;
  final Duration duration;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onDismissed;

  const _WebToastOverlay({
    required this.accent,
    required this.icon,
    required this.title,
    required this.message,
    required this.duration,
    required this.onDismissed,
    this.actionLabel,
    this.onAction,
  });

  @override
  State<_WebToastOverlay> createState() => _WebToastOverlayState();
}

class _WebToastOverlayState extends State<_WebToastOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;
  Timer? _timer;
  bool _isDismissing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 160),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0.08, -0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
    _timer = Timer(widget.duration, _dismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (_isDismissing) return;
    _isDismissing = true;
    await _controller.reverse();
    widget.onDismissed();
  }

  void _runAction() {
    widget.onAction?.call();
    _dismiss();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 20,
      right: width < 560 ? 16 : 24,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _controller,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width < 560 ? width - 32 : 420),
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x260F172A),
                      blurRadius: 24,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 5,
                      height: 54,
                      decoration: BoxDecoration(
                        color: widget.accent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: widget.accent.withAlpha(24),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(widget.icon, color: widget.accent, size: 21),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF1A202C),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            widget.message,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 12,
                              height: 1.35,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                          if (widget.actionLabel != null &&
                              widget.onAction != null) ...[
                            const SizedBox(height: 7),
                            TextButton(
                              onPressed: _runAction,
                              style: TextButton.styleFrom(
                                foregroundColor: widget.accent,
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                widget.actionLabel!,
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Dismiss',
                      onPressed: _dismiss,
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Color(0xFF94A3B8),
                        size: 19,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

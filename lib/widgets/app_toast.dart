// lib/widgets/app_toast.dart
//
// Single shared toast/snackbar system for the whole app — replaces the many
// one-off `ScaffoldMessenger.of(context).showSnackBar(SnackBar(...))` calls
// scattered across admin/org screens (each with its own ad-hoc color and
// dismiss behavior) with 4 consistent types:
//   - success: green, auto-dismisses after a few seconds
//   - error:   red,   stays until the user dismisses it (mistakes shouldn't
//              vanish before they're read)
//   - warning: amber, stays until the user dismisses it
//   - info:    blue,  stays until the user dismisses it
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum AppToastType { success, error, warning, info }

class AppToast {
  AppToast._();

  static const Color _successBg = Color(0xFF059669);
  static const Color _errorBg = Color(0xFFDC2626);
  static const Color _warningBg = Color(0xFFF59E0B);
  static const Color _infoBg = Color(0xFF2563EB);

  static void success(BuildContext context, String message) =>
      _show(context, message, type: AppToastType.success);

  static void error(BuildContext context, String message) =>
      _show(context, message, type: AppToastType.error);

  static void warning(BuildContext context, String message) =>
      _show(context, message, type: AppToastType.warning);

  static void info(BuildContext context, String message) =>
      _show(context, message, type: AppToastType.info);

  static void _show(
    BuildContext context,
    String message, {
    required AppToastType type,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();

    final (Color bg, IconData icon, bool autoDismiss) = switch (type) {
      AppToastType.success => (_successBg, Icons.check_circle_rounded, true),
      AppToastType.error => (_errorBg, Icons.error_rounded, false),
      AppToastType.warning => (_warningBg, Icons.warning_rounded, false),
      AppToastType.info => (_infoBg, Icons.info_rounded, false),
    };

    messenger.showSnackBar(
      SnackBar(
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        elevation: 4,
        duration: autoDismiss
            ? const Duration(seconds: 3)
            : const Duration(days: 365), // effectively "until dismissed"
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                  height: 1.35,
                ),
              ),
            ),
            if (!autoDismiss) ...[
              const SizedBox(width: 8),
              InkWell(
                onTap: () => messenger.hideCurrentSnackBar(),
                borderRadius: BorderRadius.circular(4),
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

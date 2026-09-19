import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Shared confirmation shell for web Admin and Org actions.
///
/// It standardizes the visual treatment only. Callers keep ownership of their
/// existing action logic by awaiting the boolean returned from `showDialog`.
class AppConfirmationDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final Color accentColor;
  final IconData icon;
  final Future<void> Function()? onConfirm;

  const AppConfirmationDialog({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.accentColor,
    required this.icon,
    this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Container(
        width: 460,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Color(0x330F172A),
              blurRadius: 32,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 40, 32, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: accentColor.withAlpha(22),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: accentColor, size: 34),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A202C),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13.5,
                      height: 1.5,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF475569),
                            side: const BorderSide(color: Color(0xFFE2E6EA)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            'Cancel',
                            style: GoogleFonts.beVietnamPro(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            Navigator.pop(context, true);
                            await onConfirm?.call();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentColor,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            confirmLabel,
                            style: GoogleFonts.beVietnamPro(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context, false),
                icon: const Icon(Icons.close_rounded),
                color: const Color(0xFF94A3B8),
                iconSize: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

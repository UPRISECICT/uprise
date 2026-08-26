// lib/screens/guest/guest_digital_id_notice.dart
//
// First-login "Your Digital ID is Ready" notice — shown once per guest
// account right after they land in authenticated mode.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'guest_auth_service.dart';
import 'guest_digital_id_screen.dart';
import '../../widgets/student/app_colors.dart';

const _kOrange = AppColors.primaryDark;
const _kOrangeLight = AppColors.primarySoft;

/// Shows the "Your Digital ID is Ready" dialog once per guest account.
/// Safe to call on every entry into authenticated guest mode — it no-ops
/// if the notice has already been shown for this guest's docId.
Future<void> maybeShowGuestDigitalIdNotice(BuildContext context) async {
  final svc = GuestAuthService();
  if (!svc.isAuthenticated || svc.docId == null) return;

  final docId = svc.docId!;
  final alreadyShown = await GuestAuthService.hasShownDigitalIdNotice(docId);
  if (alreadyShown || !context.mounted) return;

  await GuestAuthService.markDigitalIdNoticeShown(docId);
  if (!context.mounted) return;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration:
                  const BoxDecoration(color: _kOrangeLight, shape: BoxShape.circle),
              child: const Icon(Icons.badge_rounded, size: 32, color: _kOrange),
            ),
            const SizedBox(height: 18),
            Text(
              'Your Digital ID is Ready',
              textAlign: TextAlign.center,
              style: GoogleFonts.beVietnamPro(
                  fontSize: 18, fontWeight: FontWeight.w800, color: Colors.black87),
            ),
            const SizedBox(height: 10),
            Text(
              'A Digital ID has been automatically created using your approved account information. You may access it anytime from your Profile page.',
              textAlign: TextAlign.center,
              style: GoogleFonts.beVietnamPro(
                  fontSize: 13, color: Colors.grey, height: 1.5),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const GuestDigitalIdScreen()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kOrange,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text('View Digital ID',
                    style: GoogleFonts.beVietnamPro(fontSize: 14, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Later',
                  style: GoogleFonts.beVietnamPro(fontSize: 13, color: Colors.grey)),
            ),
          ],
        ),
      ),
    ),
  );
}

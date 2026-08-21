// lib/widgets/common/app_intro.dart
//
// Shared first-time-user-experience (FTUE) carousel for UPRISE — a short
// "what is this app" walkthrough shown once at each role's natural
// first-commitment gate (right before the existing Terms and Conditions
// checkbox): students see it on their very first login, before setting a
// real password; guests see it before starting their application. Purely
// presentational — no Firestore/SharedPreferences reads or writes.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../student/app_colors.dart';

class AppIntroSlide {
  final IconData icon;
  final String title;
  final String description;

  const AppIntroSlide({
    required this.icon,
    required this.title,
    required this.description,
  });
}

const List<AppIntroSlide> kStudentIntroSlides = [
  AppIntroSlide(
    icon: Icons.local_fire_department,
    title: 'Welcome to UPRISE',
    description:
        'Your CICT student-organization hub — events, announcements, '
        'and certificates, all in one place.',
  ),
  AppIntroSlide(
    icon: Icons.event_available_outlined,
    title: 'Discover & Join Events',
    description:
        'Browse events from CICT organizations, register in a tap, and '
        'check in with your Digital ID or a QR code.',
  ),
  AppIntroSlide(
    icon: Icons.workspace_premium_outlined,
    title: 'Track Your Journey',
    description:
        'See your registered events, submit feedback afterward, and '
        'collect verified certificates of participation.',
  ),
  AppIntroSlide(
    icon: Icons.forum_outlined,
    title: 'Stay Connected',
    description:
        'Get announcements from your organizations and message them '
        'directly — all from one inbox.',
  ),
];

const List<AppIntroSlide> kGuestIntroSlides = [
  AppIntroSlide(
    icon: Icons.local_fire_department,
    title: 'Welcome to UPRISE',
    description:
        'Your CICT student-organization hub — events, announcements, '
        'and certificates, all in one place.',
  ),
  AppIntroSlide(
    icon: Icons.explore_outlined,
    title: 'Browse as a Visitor',
    description:
        'Explore events, announcements, and the calendar right away — '
        'no account needed to look around.',
  ),
  AppIntroSlide(
    icon: Icons.badge_outlined,
    title: 'Apply for Full Access',
    description:
        'Submit the application below to unlock your Digital ID, event '
        'feedback, and certificates once approved.',
  ),
  AppIntroSlide(
    icon: Icons.verified_user_outlined,
    title: 'Reviewed by CICT Admin',
    description:
        'Applications are reviewed manually, not auto-approved — you\'ll '
        'be notified once the CICT Admin makes a decision.',
  ),
];

/// Swipeable first-time-guide carousel. [onDone] fires from both the
/// "Skip" action and the final slide's CTA — callers decide what happens
/// next (advance a step, dismiss, etc.), this widget has no navigation
/// opinions of its own.
class AppIntroScreen extends StatefulWidget {
  final List<AppIntroSlide> slides;
  final VoidCallback onDone;
  final Color accent;
  final String doneLabel;

  const AppIntroScreen({
    super.key,
    required this.slides,
    required this.onDone,
    this.accent = AppColors.primaryDark,
    this.doneLabel = 'Get Started',
  });

  @override
  State<AppIntroScreen> createState() => _AppIntroScreenState();
}

class _AppIntroScreenState extends State<AppIntroScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isLast => _page == widget.slides.length - 1;

  void _next() {
    if (_isLast) {
      widget.onDone();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: TextButton(
                  onPressed: widget.onDone,
                  child: Text(
                    'Skip',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: widget.slides.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) {
                  final slide = widget.slides[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: widget.accent.withAlpha(26),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: widget.accent.withAlpha(64),
                            ),
                          ),
                          child: Icon(slide.icon, size: 52, color: widget.accent),
                        ),
                        const SizedBox(height: 36),
                        Text(
                          slide.title,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.grey.shade900,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          slide.description,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(widget.slides.length, (i) {
                      final active = i == _page;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: active ? 22 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: active
                              ? widget.accent
                              : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _next,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.accent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        _isLast ? widget.doneLabel : 'Next',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../widgets/shared/app_support.dart'
    show kSupportEmailPrimary, kSupportEmailSecondary;
import 'admin_site_chrome.dart';

// Help content — categorized FAQ + a contact card.
class AdminHelpContent extends StatelessWidget {
  final ValueChanged<AdminSiteSection> onSelect;
  final VoidCallback onTerms;

  const AdminHelpContent({
    required this.onSelect,
    required this.onTerms,
    super.key,
  });

  static const _categories = [
    (
      'Getting Started',
      Icons.rocket_launch_rounded,
      [
        (
          'I forgot my admin password — what do I do?',
          'Use "Forgot password" on the Admin Login screen to receive a '
              'reset link at your registered email address.',
        ),
        (
          'How do I create student accounts in bulk?',
          'From Student Accounts, click "Batch Import," download the '
              'Excel template, fill in one row per student, and upload '
              'it. Each student gets a temporary password emailed '
              'automatically.',
        ),
      ],
    ),
    (
      'Managing the System',
      Icons.dashboard_customize_rounded,
      [
        (
          'How do I approve an organization\'s event or proposal?',
          'Open the relevant proposal from the admin dashboard — you '
              'can approve, reject, or archive it, and the organization '
              'is notified either way.',
        ),
        (
          'Where can I see a history of actions taken in the system?',
          'The Activity Logs section keeps a full, timestamped audit '
              'trail of every significant action across the portal.',
        ),
      ],
    ),
    (
      'Support',
      Icons.support_agent_rounded,
      [
        (
          'Who do I contact for a technical issue?',
          'Reach the UPRISE support team directly using either email '
              'below — include a screenshot if you can.',
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 48),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AdminSiteColors.primary.withAlpha(14),
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(color: AdminSiteColors.border),
                      ),
                      child: Text(
                        'SUPPORT',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: AdminSiteColors.primary,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Need a hand?',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: AdminSiteColors.ink,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Answers to what admins ask most — grouped by what '
                      'you\'re trying to do.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 15,
                        color: AdminSiteColors.inkSoft,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            color: AdminSiteColors.bg,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: Column(
                  children: [
                    for (final cat in _categories)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: AdminSiteColors.primary.withAlpha(
                                      14,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    cat.$2,
                                    size: 17,
                                    color: AdminSiteColors.primary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  cat.$1,
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: AdminSiteColors.ink,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            for (final f in cat.$3)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _FaqItem(question: f.$1, answer: f.$2),
                              ),
                          ],
                        ),
                      ),
                    _buildContactCard(),
                  ],
                ),
              ),
            ),
          ),
          AdminSiteFooter(onSelect: onSelect, onTerms: onTerms),
        ],
      ),
    );
  }

  Widget _buildContactCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AdminSiteColors.primary,
        borderRadius: BorderRadius.circular(18),
      ),
      child: LayoutBuilder(
        builder: (_, c) {
          final wide = c.maxWidth >= 560;
          final text = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Still stuck?',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Email the UPRISE support team directly.',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12.5,
                  color: Colors.white.withAlpha(220),
                ),
              ),
            ],
          );
          final buttons = Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _emailChip(kSupportEmailPrimary),
              _emailChip(kSupportEmailSecondary),
            ],
          );
          return wide
              ? Row(
                  children: [
                    Expanded(child: text),
                    const SizedBox(width: 16),
                    buttons,
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [text, const SizedBox(height: 16), buttons],
                );
        },
      ),
    );
  }

  Widget _emailChip(String email) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => launchUrl(
          Uri(
            scheme: 'mailto',
            path: email,
            query: 'subject=UPRISE Admin Portal Support',
          ),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.mail_outline_rounded,
                size: 15,
                color: AdminSiteColors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                email,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AdminSiteColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FaqItem extends StatefulWidget {
  final String question;
  final String answer;

  const _FaqItem({required this.question, required this.answer});

  @override
  State<_FaqItem> createState() => _FaqItemState();
}

class _FaqItemState extends State<_FaqItem> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdminSiteColors.border),
      ),
      child: Column(
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.question,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AdminSiteColors.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    AnimatedRotation(
                      turns: _open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: AdminSiteColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.answer,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    color: AdminSiteColors.inkSoft,
                    height: 1.6,
                  ),
                ),
              ),
            ),
            crossFadeState: _open
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
            sizeCurve: Curves.easeInOut,
          ),
        ],
      ),
    );
  }
}

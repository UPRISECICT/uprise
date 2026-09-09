import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../widgets/shared/app_support.dart'
    show kSupportEmailPrimary, kSupportEmailSecondary;
import 'org_site_chrome.dart';

// Structural mirror of the admin portal's Help page (admin_help_page.dart)
// — same categorized-FAQ + contact-card shape, org-specific questions.
class OrgHelpContent extends StatelessWidget {
  final ValueChanged<OrgSiteSection> onSelect;
  final VoidCallback onTerms;

  const OrgHelpContent({
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
          'I forgot my organization account password — what do I do?',
          'Use "Forgot password" on the Org Login screen to receive a '
              'reset link at your registered email address.',
        ),
        (
          'How do I complete my organization\'s profile?',
          'Log in with the temporary password your CICT Admin issued you, '
              'set a permanent password, then fill in your organization\'s '
              'profile from the dashboard.',
        ),
      ],
    ),
    (
      'Managing Your Organization',
      Icons.dashboard_customize_rounded,
      [
        (
          'How do I submit an event proposal?',
          'From Event Proposals, click "New Proposal," fill in the event '
              'details, and submit — you\'ll see its approval status '
              'update in real time.',
        ),
        (
          'How do I issue certificates after an event?',
          'From Certificates, generate a batch for the event — only '
              'attendees who\'ve submitted feedback are eligible, then '
              'send certificates individually or all at once.',
        ),
        (
          'How do I submit financial or accomplishment reports?',
          'From Report Submissions, open the finished event and submit '
              'each report before its deadline — overdue ones are flagged '
              'automatically.',
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
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: Colors.white,
                child: OrgAbstractBackdrop(
                  child: Padding(
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
                                color: OrgSiteColors.accentDeep.withAlpha(14),
                                borderRadius: BorderRadius.circular(100),
                                border: Border.all(color: OrgSiteColors.border),
                              ),
                              child: Text(
                                'SUPPORT',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: OrgSiteColors.accentDeep,
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
                                color: OrgSiteColors.ink,
                                letterSpacing: -0.6,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Answers to what organizations ask most — '
                              'grouped by what you\'re trying to do.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 15,
                                color: OrgSiteColors.inkSoft,
                                height: 1.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const OrgSectionSeam(from: Colors.white, to: OrgSiteColors.bg),
              Container(
                color: OrgSiteColors.bg,
                child: OrgAbstractBackdrop(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 24,
                    ),
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
                                            color: OrgSiteColors.accentDeep
                                                .withAlpha(14),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          child: Icon(
                                            cat.$2,
                                            size: 17,
                                            color: OrgSiteColors.accentDeep,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          cat.$1,
                                          style: GoogleFonts.beVietnamPro(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800,
                                            color: OrgSiteColors.ink,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    for (final f in cat.$3)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 10,
                                        ),
                                        child: _FaqItem(
                                          question: f.$1,
                                          answer: f.$2,
                                        ),
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
                ),
              ),
              const OrgSectionSeam(
                from: OrgSiteColors.bg,
                to: OrgSiteColors.navy,
              ),
              OrgSiteFooter(onSelect: onSelect, onTerms: onTerms),
            ],
          ),
          const OrgPageSpine(),
        ],
      ),
    );
  }

  Widget _buildContactCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: OrgSiteColors.slateDark,
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
            query: 'subject=UPRISE Org Portal Support',
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
                color: OrgSiteColors.accentDeep,
              ),
              const SizedBox(width: 8),
              Text(
                email,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: OrgSiteColors.accentDeep,
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
        border: Border.all(color: OrgSiteColors.border),
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
                          color: OrgSiteColors.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    AnimatedRotation(
                      turns: _open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: OrgSiteColors.accentDeep,
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
                    color: OrgSiteColors.inkSoft,
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

import 'package:flutter/material.dart';

import '../../../widgets/common/terms_and_conditions.dart';
import '../landing/feature_showcase.dart';
import '../landing/hero_section.dart';
import '../landing/landing_common.dart';
import '../landing/landing_footer.dart';
import '../landing/landing_motion.dart';
import '../landing/landing_navbar.dart';
import '../landing/landing_palette.dart';
import '../landing/layered_visual.dart';
import '../landing/portal_cta.dart';
import '../landing/previews/org_previews.dart';
import '../landing/previews/preview_kit.dart';
import '../landing/word_marquee.dart';
import '../landing/workflow_timeline.dart';
import 'org_about_page.dart';
import 'org_help_page.dart';
import 'org_login.dart';
import 'org_site_chrome.dart';

// Organization landing page: Org URL → this page → OrganizationLogin → the
// existing OrgDashboard. Shares every component in ../landing/ with the
// admin landing page; only the palette and content differ — this page
// follows an organization's event workflow rather than the admin's
// oversight role.

enum _View { home, about, help }

class OrgLandingPage extends StatefulWidget {
  const OrgLandingPage({super.key});

  @override
  State<OrgLandingPage> createState() => _OrgLandingPageState();
}

class _OrgLandingPageState extends State<OrgLandingPage> {
  static const _palette = LandingPalette.org;

  final _scroll = ScrollController();
  final _overviewKey = GlobalKey();
  final _featuresKey = GlobalKey();
  _View _view = _View.home;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _goToLogin() {
    // A plain push (not pushReplacement) so this landing page stays on the
    // stack underneath — the login page's own "Back" returns here with a
    // normal Navigator.pop().
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const OrganizationLogin()),
    );
  }

  void _openTerms() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const TermsAndConditionsScreen(accent: OrgSiteColors.accentDeep),
      ),
    );
  }

  void _goTo(GlobalKey key) {
    if (_view != _View.home) {
      setState(() => _view = _View.home);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => scrollToKey(_scroll, key),
      );
    } else {
      scrollToKey(_scroll, key);
    }
  }

  void _goTop() {
    if (_view != _View.home) {
      setState(() => _view = _View.home);
    } else if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _show(_View v) {
    if (_view != v) setState(() => _view = v);
  }

  // The existing About/Help content still speaks in OrgSiteSection.
  void _onSiteSelect(OrgSiteSection s) {
    switch (s) {
      case OrgSiteSection.home:
        _goTop();
      case OrgSiteSection.features:
        _goTo(_featuresKey);
      case OrgSiteSection.about:
        _show(_View.about);
      case OrgSiteSection.help:
        _show(_View.help);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nav = LandingNavbar(
      palette: _palette,
      controller: _view == _View.home ? _scroll : null,
      loginLabel: 'Organization Login',
      onLogin: _goToLogin,
      onLogoTap: _goTop,
      items: [
        LandingNavItem(label: 'Overview', onTap: () => _goTo(_overviewKey)),
        LandingNavItem(label: 'Features', onTap: () => _goTo(_featuresKey)),
        LandingNavItem(
          label: 'About',
          onTap: () => _show(_View.about),
          active: _view == _View.about,
        ),
      ],
    );

    if (_view != _View.home) {
      return Scaffold(
        backgroundColor: OrgSiteColors.bg,
        body: Column(
          children: [
            nav,
            Expanded(
              child: _view == _View.about
                  ? OrgAboutContent(
                      onSelect: _onSiteSelect,
                      onTerms: _openTerms,
                    )
                  : OrgHelpContent(
                      onSelect: _onSiteSelect,
                      onTerms: _openTerms,
                    ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: LandingScrollScope(
        controller: _scroll,
        child: Stack(
          children: [
            Positioned.fill(
              child: SingleChildScrollView(
                controller: _scroll,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _hero(),
                    const WordMarquee(
                      palette: _palette,
                      eyebrow: 'EVERYTHING IN ONE PLACE',
                      words: [
                        'Plan',
                        'Register',
                        'Attend',
                        'Certify',
                        'Report',
                        'Engage',
                      ],
                    ),
                    KeyedSubtree(key: _overviewKey, child: _workflow()),
                    KeyedSubtree(key: _featuresKey, child: _stories()),
                    PortalCta(
                      palette: _palette,
                      eyebrow: 'ORGANIZATION ACCESS',
                      title:
                          'Everything your organization needs, in one place.',
                      body:
                          'Sign in with the officer credentials issued by your '
                          'CICT Admin.',
                      buttonLabel: 'Continue to Organization Login',
                      onPressed: _goToLogin,
                    ),
                    LandingFooter(
                      palette: _palette,
                      tagline:
                          'The organization portal of UPRISE — events, '
                          'attendance, certificates, and reports for CICT '
                          'student organizations.',
                      links: [
                        FooterLink('Overview', () => _goTo(_overviewKey)),
                        FooterLink('Features', () => _goTo(_featuresKey)),
                        FooterLink('About', () => _show(_View.about)),
                        FooterLink('Help', () => _show(_View.help)),
                        FooterLink('Terms & Privacy', _openTerms),
                        FooterLink('Organization Login', _goToLogin),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Positioned(top: 0, left: 0, right: 0, child: nav),
          ],
        ),
      ),
    );
  }

  // ── Sections ─────────────────────────────────────────────────────────

  Widget _hero() {
    return LandingHero(
      palette: _palette,
      label: 'ORGANIZATION PORTAL',
      titleLines: const ['Plan.', 'Manage.', 'Engage.'],
      highlightLine: 2,
      description:
          'UPRISE helps CICT organizations run events, registrations, '
          'attendance, certificates, announcements, reports, and finances '
          'from one centralized platform.',
      primaryLabel: 'Organization Login',
      onPrimary: _goToLogin,
      secondaryLabel: 'Explore Platform',
      onSecondary: () => _goTo(_overviewKey),
      footnote: 'For CICT organization officers and advisers',
      visual: const LayeredVisual(
        palette: _palette,
        designSize: Size(680, 540),
        delay: Duration(milliseconds: 650),
        base: OrgDashboardPreview(),
        mobile: EventCardPreview(),
        layers: [
          StageLayer(
            left: -18,
            bottom: -8,
            depth: 0.8,
            order: 1,
            child: EventCardPreview(width: 250),
          ),
          StageLayer(
            right: 20,
            top: 14,
            depth: 0.5,
            order: 2,
            child: StatChip(
              palette: _palette,
              icon: Icons.how_to_reg_rounded,
              value: '248',
              label: 'Registrations',
            ),
          ),
          StageLayer(
            right: -20,
            bottom: -16,
            depth: 1,
            order: 3,
            child: QrAttendanceCard(),
          ),
        ],
      ),
    );
  }

  Widget _workflow() {
    return BrandBand(
      palette: _palette,
      padding: const EdgeInsets.only(top: 110, bottom: 90),
      child: Column(
        children: [
          const LandingContainer(
            child: SectionHeader(
              palette: _palette,
              eyebrow: 'EVENT WORKFLOW',
              title: 'From first proposal to final report.',
              subtitle:
                  'Every event in UPRISE moves through the same five '
                  'steps — scroll to follow one through.',
              center: true,
              dark: true,
            ),
          ),
          const SizedBox(height: 40),
          WorkflowTimeline(
            palette: _palette,
            steps: const [
              WorkflowStep(
                label: 'PLAN',
                icon: Icons.edit_calendar_rounded,
                title: 'Event proposals and scheduling',
                body:
                    'Draft a proposal, submit it for CICT Admin review, and '
                    'schedule the event once it\'s approved.',
                visual: ProposalStatusCard(),
              ),
              WorkflowStep(
                label: 'REGISTER',
                icon: Icons.how_to_reg_rounded,
                title: 'Registration forms and participants',
                body:
                    'Build a custom registration form for each event and '
                    'manage the participants who sign up.',
                visual: EventCardPreview(width: 260),
              ),
              WorkflowStep(
                label: 'ATTEND',
                icon: Icons.qr_code_scanner_rounded,
                title: 'QR or webinar-code attendance',
                body:
                    'Check attendees in on-site with a live rotating QR '
                    'code, or online with a webinar code.',
                visual: QrAttendanceCard(),
              ),
              WorkflowStep(
                label: 'CERTIFY',
                icon: Icons.workspace_premium_rounded,
                title: 'Certificates for attendees',
                body:
                    'Issue certificates to attendees who submitted their '
                    'event feedback — each with a public verification code.',
                visual: CertificateCard(width: 280),
              ),
              WorkflowStep(
                label: 'REPORT',
                icon: Icons.insights_rounded,
                title: 'Analytics and accomplishment reports',
                body:
                    'Review event analytics and submit accomplishment and '
                    'financial reports before their deadlines.',
                visual: ReportSubmitCard(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stories() {
    final w = MediaQuery.of(context).size.width;
    final gap = SizedBox(height: w < 980 ? 88 : 150);
    return Container(
      color: Colors.white,
      child: LandingContainer(
        padding: EdgeInsets.symmetric(vertical: w < 600 ? 72 : 120),
        child: Column(
          children: [
            const SectionHeader(
              palette: _palette,
              eyebrow: 'FEATURES',
              title: 'Built for the way organizations actually work.',
              center: true,
            ),
            SizedBox(height: w < 980 ? 64 : 110),
            const FeatureStory(
              palette: _palette,
              number: '01',
              eyebrow: 'EVENT MANAGEMENT',
              title: 'Run every event from one place.',
              body:
                  'Submit proposals, schedule approved events, publish '
                  'custom registration forms, and manage the participants '
                  'who sign up.',
              points: [
                'Proposal submission and tracking',
                'Event scheduling',
                'Custom registration forms',
                'Participant management',
              ],
              visual: LayeredVisual(
                palette: _palette,
                designSize: Size(620, 480),
                base: FormBuilderPreview(),
                mobile: EventCardPreview(),
                layers: [
                  StageLayer(
                    left: -10,
                    top: 14,
                    depth: 0.6,
                    order: 1,
                    child: StatChip(
                      palette: _palette,
                      icon: Icons.how_to_reg_rounded,
                      value: '186',
                      label: 'Registered',
                    ),
                  ),
                  StageLayer(
                    right: -20,
                    bottom: -18,
                    depth: 1,
                    order: 2,
                    child: EventCardPreview(width: 240),
                  ),
                ],
              ),
            ),
            gap,
            const FeatureStory(
              palette: _palette,
              number: '02',
              eyebrow: 'ENGAGEMENT & ATTENDANCE',
              title: 'Keep members informed and checked in.',
              body:
                  'Post announcements, send broadcast messages to your '
                  'members, and take attendance with live QR codes on-site '
                  'or webinar codes online.',
              points: [
                'Announcements',
                'Broadcast messages',
                'QR attendance',
                'Webinar attendance codes',
              ],
              reversed: true,
              visual: LayeredVisual(
                palette: _palette,
                designSize: Size(560, 460),
                base: QrAttendanceCard(),
                mobile: QrAttendanceCard(),
                layers: [
                  StageLayer(
                    left: -14,
                    top: 26,
                    depth: 0.8,
                    order: 1,
                    child: AnnouncementCard(),
                  ),
                  StageLayer(
                    right: -6,
                    bottom: 40,
                    depth: 1,
                    order: 2,
                    child: StatChip(
                      palette: _palette,
                      icon: Icons.check_circle_rounded,
                      value: '151',
                      label: 'Checked in',
                      color: Color(0xFF10B981),
                    ),
                  ),
                ],
              ),
            ),
            gap,
            const FeatureStory(
              palette: _palette,
              number: '03',
              eyebrow: 'POST-EVENT MANAGEMENT',
              title: 'Close every event properly.',
              body:
                  'Issue certificates to attendees who submitted their '
                  'feedback, review event analytics, and prepare '
                  'accomplishment reports.',
              points: [
                'Certificates with public verification codes',
                'Event analytics and feedback ratings',
                'Accomplishment reports',
              ],
              visual: LayeredVisual(
                palette: _palette,
                designSize: Size(580, 420),
                base: CertificateCard(width: 360),
                mobile: CertificateCard(),
                layers: [
                  StageLayer(
                    left: -16,
                    bottom: 10,
                    depth: 1,
                    order: 1,
                    child: EventAnalyticsCard(),
                  ),
                  StageLayer(
                    right: -14,
                    top: 18,
                    depth: 0.6,
                    order: 2,
                    child: StatChip(
                      palette: _palette,
                      icon: Icons.workspace_premium_rounded,
                      value: '156',
                      label: 'Certificates issued',
                    ),
                  ),
                ],
              ),
            ),
            gap,
            const FeatureStory(
              palette: _palette,
              number: '04',
              eyebrow: 'ORGANIZATION OPERATIONS',
              title: 'The day-to-day, organized.',
              body:
                  'Track organization funds, manage merchandise, keep your '
                  'organization profile up to date, and file letter requests '
                  'with the college office.',
              points: [
                'Financial tracking',
                'Merchandise management',
                'Organization profile',
                'Letter requests',
              ],
              reversed: true,
              visual: LayeredVisual(
                palette: _palette,
                designSize: Size(560, 400),
                base: FinanceCard(),
                mobile: FinanceCard(),
                layers: [
                  StageLayer(
                    left: 6,
                    top: 12,
                    depth: 0.7,
                    order: 1,
                    child: MerchCard(),
                  ),
                  StageLayer(
                    right: -10,
                    bottom: 20,
                    depth: 1,
                    order: 2,
                    child: LetterRequestCard(),
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

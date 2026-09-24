import 'package:flutter/material.dart';

import '../../../widgets/common/terms_and_conditions.dart';
import '../landing/feature_card.dart';
import '../landing/feature_showcase.dart';
import '../landing/hero_section.dart';
import '../landing/landing_common.dart';
import '../landing/landing_footer.dart';
import '../landing/landing_motion.dart';
import '../landing/landing_navbar.dart';
import '../landing/landing_palette.dart';
import '../landing/layered_visual.dart';
import '../landing/portal_cta.dart';
import '../landing/previews/admin_previews.dart';
import '../landing/previews/preview_kit.dart';
import '../landing/word_marquee.dart';
import 'admin_about_page.dart';
import 'admin_help_page.dart';
import 'admin_login.dart';
import 'admin_site_chrome.dart';

// Administrator landing page: Admin URL → this page → AdminLogin → the
// existing AdminDashboard. Built from the shared components in
// ../landing/ (the org landing page uses the same ones with its own palette
// and copy). Home is one scrolling page; About and Help swap in below the
// same navbar, reusing the existing admin About/Help content.

enum _View { home, about, help }

class AdminLandingPage extends StatefulWidget {
  const AdminLandingPage({super.key});

  @override
  State<AdminLandingPage> createState() => _AdminLandingPageState();
}

class _AdminLandingPageState extends State<AdminLandingPage> {
  static const _palette = LandingPalette.admin;

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
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AdminLogin()),
    );
  }

  void _openTerms() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const TermsAndConditionsScreen(accent: AdminSiteColors.blue),
      ),
    );
  }

  /// Scroll to a home-page section, switching back to home first if an
  /// About/Help view is showing.
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

  // The existing About/Help content still speaks in AdminSiteSection.
  void _onSiteSelect(AdminSiteSection s) {
    switch (s) {
      case AdminSiteSection.home:
        _goTop();
      case AdminSiteSection.features:
        _goTo(_featuresKey);
      case AdminSiteSection.about:
        _show(_View.about);
      case AdminSiteSection.help:
        _show(_View.help);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nav = LandingNavbar(
      palette: _palette,
      controller: _view == _View.home ? _scroll : null,
      loginLabel: 'Administrator Login',
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
        backgroundColor: AdminSiteColors.bg,
        body: Column(
          children: [
            nav,
            Expanded(
              child: _view == _View.about
                  ? AdminAboutContent(
                      onSelect: _onSiteSelect,
                      onTerms: _openTerms,
                    )
                  : AdminHelpContent(
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
                        'Organizations',
                        'Event Proposals',
                        'College Calendar',
                        'Accounts',
                        'Reports & Analytics',
                        'Letter Requests',
                        'Activity Logs',
                      ],
                    ),
                    KeyedSubtree(key: _overviewKey, child: _overview()),
                    KeyedSubtree(key: _featuresKey, child: _stories()),
                    PortalCta(
                      palette: _palette,
                      eyebrow: 'ADMINISTRATOR ACCESS',
                      title: 'Ready to manage UPRISE?',
                      body:
                          'Authorized CICT administrators can sign in to the '
                          'management portal with their issued credentials.',
                      buttonLabel: 'Continue to Administrator Login',
                      onPressed: _goToLogin,
                    ),
                    LandingFooter(
                      palette: _palette,
                      tagline:
                          'The administrator portal of UPRISE — centralized '
                          'oversight for student organizations of the College '
                          'of Information and Communications Technology.',
                      links: [
                        FooterLink('Overview', () => _goTo(_overviewKey)),
                        FooterLink('Features', () => _goTo(_featuresKey)),
                        FooterLink('About', () => _show(_View.about)),
                        FooterLink('Help', () => _show(_View.help)),
                        FooterLink('Terms & Privacy', _openTerms),
                        FooterLink('Administrator Login', _goToLogin),
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
      label: 'ADMINISTRATOR PORTAL',
      titleLines: const ['Centralized', 'oversight for CICT', 'organizations.'],
      highlightLine: 2,
      description:
          'UPRISE gives CICT administrators one place to oversee '
          'organizations, review event proposals, manage the college '
          'calendar, verify accounts, and keep every report and activity on '
          'record.',
      primaryLabel: 'Administrator Login',
      onPrimary: _goToLogin,
      secondaryLabel: 'Explore Platform',
      onSecondary: () => _goTo(_overviewKey),
      footnote: 'Built for Bulacan State University · CICT',
      visual: const LayeredVisual(
        palette: _palette,
        designSize: Size(680, 520),
        delay: Duration(milliseconds: 650),
        base: AdminDashboardPreview(),
        mobile: ProposalReviewCard(),
        layers: [
          StageLayer(
            left: -12,
            bottom: 6,
            depth: 0.8,
            order: 1,
            child: ProposalReviewCard(),
          ),
          StageLayer(
            right: 4,
            top: 24,
            depth: 0.55,
            order: 2,
            child: StatChip(
              palette: _palette,
              icon: Icons.groups_rounded,
              value: '18',
              label: 'Active organizations',
            ),
          ),
          StageLayer(
            right: -16,
            bottom: 34,
            depth: 1,
            order: 3,
            child: ActivityFeedCard(width: 240),
          ),
        ],
      ),
    );
  }

  Widget _overview() {
    return BrandBand(
      palette: _palette,
      child: LandingContainer(
        child: Column(
          children: [
            const SectionHeader(
              palette: _palette,
              eyebrow: 'PLATFORM OVERVIEW',
              title: 'One platform for CICT administration.',
              subtitle:
                  'Everything the college office oversees across student '
                  'organizations — in a single, secure console.',
              center: true,
              dark: true,
            ),
            const SizedBox(height: 56),
            CapabilityGrid(
              palette: _palette,
              dark: true,
              items: const [
                Capability(
                  Icons.group_work_rounded,
                  'Organization Management',
                  'Create and manage every recognized CICT organization, its '
                      'officer accounts, and advisers.',
                ),
                Capability(
                  Icons.event_available_rounded,
                  'Event Proposal Review',
                  'Approve, reject, or archive proposals before any event '
                      'reaches students.',
                ),
                Capability(
                  Icons.verified_user_rounded,
                  'Student & External Accounts',
                  'Provision student accounts and review guest and external '
                      'access requests.',
                ),
                Capability(
                  Icons.calendar_month_rounded,
                  'College Calendar',
                  'See every approved organization event on one shared '
                      'college calendar.',
                ),
                Capability(
                  Icons.insights_rounded,
                  'Reports & Analytics',
                  'Track financial and accomplishment reports against '
                      'university deadlines, and export summaries.',
                ),
                Capability(
                  Icons.mail_rounded,
                  'Letter Requests',
                  'Receive and act on letter requests from organizations in '
                      'one place.',
                ),
                Capability(
                  Icons.history_rounded,
                  'Activity Monitoring',
                  'Significant actions are written to an audit trail you can '
                      'review anytime.',
                ),
              ],
            ),
          ],
        ),
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
              title: 'Built around how the college office works.',
              center: true,
            ),
            SizedBox(height: w < 980 ? 64 : 110),
            const FeatureStory(
              palette: _palette,
              number: '01',
              eyebrow: 'ORGANIZATION OVERSIGHT',
              title: 'Every organization, one directory.',
              body:
                  'Create organization accounts, assign officers and '
                  'advisers, and keep each organization\'s information '
                  'current — without spreadsheets passed between offices.',
              points: [
                'Organization profiles and officer accounts',
                'Adviser role assignment',
                'Temporary-password onboarding for new officers',
              ],
              visual: LayeredVisual(
                palette: _palette,
                designSize: Size(620, 480),
                base: OrgDirectoryPreview(),
                mobile: AdviserCard(),
                layers: [
                  StageLayer(
                    left: -10,
                    top: 18,
                    depth: 0.6,
                    order: 1,
                    child: StatChip(
                      palette: _palette,
                      icon: Icons.verified_rounded,
                      value: '18',
                      label: 'Recognized organizations',
                    ),
                  ),
                  StageLayer(
                    right: -18,
                    bottom: 4,
                    depth: 1,
                    order: 2,
                    child: AdviserCard(),
                  ),
                ],
              ),
            ),
            gap,
            const FeatureStory(
              palette: _palette,
              number: '02',
              eyebrow: 'EVENT GOVERNANCE',
              title: 'Review proposals. Publish with confidence.',
              body:
                  'Organizations submit event proposals; you review the '
                  'details and approve, reject, or archive them — approved '
                  'events land on the college calendar for everyone.',
              points: [
                'One queue of pending proposals',
                'Approve, reject, or archive',
                'Shared college calendar of approved events',
              ],
              reversed: true,
              visual: LayeredVisual(
                palette: _palette,
                designSize: Size(620, 480),
                base: CollegeCalendarPreview(),
                mobile: ProposalReviewCard(),
                layers: [
                  StageLayer(
                    left: -18,
                    bottom: -6,
                    depth: 1,
                    order: 1,
                    child: ProposalReviewCard(),
                  ),
                  StageLayer(
                    right: -8,
                    top: 20,
                    depth: 0.6,
                    order: 2,
                    child: StatChip(
                      palette: _palette,
                      icon: Icons.pending_actions_rounded,
                      value: '5',
                      label: 'Pending review',
                      color: Color(0xFFF59E0B),
                    ),
                  ),
                ],
              ),
            ),
            gap,
            const FeatureStory(
              palette: _palette,
              number: '03',
              eyebrow: 'REPORTS & MONITORING',
              title: 'Know what\'s happening across the college.',
              body:
                  'Follow report submissions against university deadlines, '
                  'export records when you need them, and review the trail '
                  'of actions taken across the portal.',
              points: [
                'Financial & accomplishment report tracking',
                'PDF export of reports',
                'Complete activity log',
              ],
              visual: LayeredVisual(
                palette: _palette,
                designSize: Size(620, 480),
                base: ReportsPreview(),
                mobile: ActivityFeedCard(),
                layers: [
                  StageLayer(
                    left: -10,
                    top: 14,
                    depth: 0.6,
                    order: 1,
                    child: StatChip(
                      palette: _palette,
                      icon: Icons.task_alt_rounded,
                      value: '24',
                      label: 'Reports this semester',
                      color: Color(0xFF10B981),
                    ),
                  ),
                  StageLayer(
                    right: -18,
                    bottom: 0,
                    depth: 1,
                    order: 2,
                    child: ActivityFeedCard(width: 250),
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

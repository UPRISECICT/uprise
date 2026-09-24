import 'package:flutter/material.dart';

import '../landing_palette.dart';
import 'preview_kit.dart';

// Illustrative previews of the organization portal's real modules (events,
// registration forms, QR attendance, certificates, announcements, finance,
// merchandise, letter requests, analytics). Sample figures only.

const _p = LandingPalette.org;
const _green = Color(0xFF10B981);
const _warn = Color(0xFFF59E0B);

Widget _title(String t, {double size = 12.5}) => Text(
  t,
  style: previewText(size, weight: FontWeight.w800, color: _p.ink),
);

Widget _sub(String t, {double size = 10}) =>
    Text(t, style: previewText(size, color: _p.inkSoft));

/// Hero base: the organization dashboard shell.
class OrgDashboardPreview extends StatelessWidget {
  const OrgDashboardPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return PreviewWindow(
      palette: _p,
      title: 'UPRISE Organization · Dashboard',
      width: 560,
      height: 390,
      child: Row(
        children: [
          Container(
            width: 58,
            color: _p.bandTop,
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(
              children: [
                for (final (i, icon) in const [
                  Icons.dashboard_rounded,
                  Icons.event_note_rounded,
                  Icons.qr_code_scanner_rounded,
                  Icons.workspace_premium_rounded,
                  Icons.campaign_rounded,
                  Icons.account_balance_wallet_rounded,
                ].indexed)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: i == 0 ? _p.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      icon,
                      size: 18,
                      color: Colors.white.withAlpha(i == 0 ? 255 : 130),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              color: _p.bg,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _title('Welcome back', size: 15),
                  const SizedBox(height: 2),
                  _sub('Your organization this semester'),
                  const SizedBox(height: 12),
                  const Row(
                    children: [
                      Expanded(
                        child: KpiTile(
                          palette: _p,
                          icon: Icons.how_to_reg_rounded,
                          label: 'Registrations',
                          value: '248',
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: KpiTile(
                          palette: _p,
                          icon: Icons.event_rounded,
                          label: 'Upcoming events',
                          value: '3',
                          color: Color(0xFF2563EB),
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: KpiTile(
                          palette: _p,
                          icon: Icons.workspace_premium_rounded,
                          label: 'Certificates issued',
                          value: '156',
                          color: _green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 3,
                          child: _panel(
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _title('Registrations this week', size: 11),
                                const Spacer(),
                                MiniBars(
                                  values: const [12, 18, 15, 26, 22, 34, 30],
                                  color: _p.primary,
                                  height: 110,
                                  highlight: 5,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: _panel(
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _title('Next event', size: 11),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    _dateBlock('OCT', '14', 40),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          SkeletonLine(width: 80),
                                          SizedBox(height: 6),
                                          SkeletonLine(width: 54),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const Spacer(),
                                const PreviewPill(
                                  text: 'Registration open',
                                  color: _green,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _panel(Widget child) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _p.border),
    ),
    child: child,
  );
}

Widget _dateBlock(String month, String day, double size) => Container(
  width: size,
  height: size,
  decoration: BoxDecoration(
    color: _p.tint,
    borderRadius: BorderRadius.circular(size * 0.25),
  ),
  child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text(
        month,
        style: previewText(
          size * 0.2,
          weight: FontWeight.w800,
          color: _p.primary,
        ),
      ),
      Text(
        day,
        style: previewText(
          size * 0.36,
          weight: FontWeight.w800,
          color: _p.ink,
          height: 1,
        ),
      ),
    ],
  ),
);

/// Published event with registration progress.
class EventCardPreview extends StatelessWidget {
  final double width;

  const EventCardPreview({this.width = 290, super.key});

  @override
  Widget build(BuildContext context) {
    return PreviewCard(
      palette: _p,
      width: width,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 92,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              gradient: LinearGradient(colors: [_p.primary, _p.accent]),
            ),
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'OCT',
                        style: previewText(
                          8.5,
                          weight: FontWeight.w800,
                          color: _p.primary,
                        ),
                      ),
                      Text(
                        '14',
                        style: previewText(
                          16,
                          weight: FontWeight.w800,
                          color: _p.ink,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                const Icon(Icons.code_rounded, color: Colors.white70, size: 36),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PreviewPill(text: 'Open for registration', color: _green),
                const SizedBox(height: 8),
                _title('Intro to Flutter Workshop', size: 14),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.location_on_rounded,
                      size: 12,
                      color: _p.inkSoft,
                    ),
                    const SizedBox(width: 4),
                    _sub('CICT Computer Lab 3'),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _sub('Registered', size: 9.5),
                    const Spacer(),
                    Text(
                      '186 / 250',
                      style: previewText(
                        10,
                        weight: FontWeight.w800,
                        color: _p.ink,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: 186 / 250,
                    minHeight: 6,
                    color: _p.primary,
                    backgroundColor: _p.tint,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Live QR check-in.
class QrAttendanceCard extends StatelessWidget {
  const QrAttendanceCard({super.key});

  @override
  Widget build(BuildContext context) {
    return PreviewCard(
      palette: _p,
      width: 240,
      child: Column(
        children: [
          Row(
            children: [
              _title('Live attendance', size: 11.5),
              const Spacer(),
              const PreviewPill(text: '● Live', color: _green),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _p.border),
            ),
            child: PseudoQr(size: 132, color: _p.ink),
          ),
          const SizedBox(height: 8),
          _sub('Rotating check-in code', size: 9.5),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _count('Present', '142', _green)),
              const SizedBox(width: 8),
              Expanded(child: _count('Late', '9', _warn)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _count(String label, String value, Color c) => Container(
    padding: const EdgeInsets.symmetric(vertical: 7),
    decoration: BoxDecoration(
      color: c.withAlpha(20),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Column(
      children: [
        Text(
          value,
          style: previewText(14, weight: FontWeight.w800, color: c),
        ),
        Text(label, style: previewText(9, color: _p.inkSoft)),
      ],
    ),
  );
}

/// Certificate with its public verification code.
class CertificateCard extends StatelessWidget {
  final double width;

  const CertificateCard({this.width = 300, super.key});

  @override
  Widget build(BuildContext context) {
    return PreviewCard(
      palette: _p,
      width: width,
      padding: const EdgeInsets.all(10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBF5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _p.accent.withAlpha(110), width: 1.5),
        ),
        child: Column(
          children: [
            Text(
              'CERTIFICATE OF PARTICIPATION',
              style: previewText(
                9.5,
                weight: FontWeight.w800,
                spacing: 1.4,
                color: _p.primary,
              ),
            ),
            const SizedBox(height: 10),
            _sub('This certifies that', size: 9),
            const SizedBox(height: 8),
            const SkeletonLine(width: 150, height: 10),
            const SizedBox(height: 10),
            _sub('attended Intro to Flutter Workshop', size: 9),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.verified_rounded, color: _p.accent, size: 28),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sub('Verification code', size: 8.5),
                    Text(
                      'K7Q2 9XMA 3PLD',
                      style: previewText(
                        10.5,
                        weight: FontWeight.w800,
                        spacing: 1,
                        color: _p.ink,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Organization funds summary.
class FinanceCard extends StatelessWidget {
  const FinanceCard({super.key});

  @override
  Widget build(BuildContext context) {
    return PreviewCard(
      palette: _p,
      width: 260,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: Icons.account_balance_wallet_rounded,
                color: _p.primary,
                size: 26,
              ),
              const SizedBox(width: 8),
              _title('Organization funds', size: 11.5),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'PHP 12,450.00',
            style: previewText(20, weight: FontWeight.w800, color: _p.ink),
          ),
          const SizedBox(height: 10),
          for (final (label, value, icon, c) in const [
            ('Income', '+ 8,200', Icons.south_west_rounded, _green),
            (
              'Expenses',
              '− 3,150',
              Icons.north_east_rounded,
              Color(0xFFEF4444),
            ),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(icon, size: 13, color: c),
                  const SizedBox(width: 6),
                  _sub(label),
                  const Spacer(),
                  Text(
                    value,
                    style: previewText(10.5, weight: FontWeight.w700, color: c),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Announcement / broadcast to members.
class AnnouncementCard extends StatelessWidget {
  const AnnouncementCard({super.key});

  @override
  Widget build(BuildContext context) {
    return PreviewCard(
      palette: _p,
      width: 270,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(icon: Icons.campaign_rounded, color: _p.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _title('Announcement', size: 11.5),
                    _sub('Sent to all members', size: 9),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'General assembly this Friday',
            style: previewText(12, weight: FontWeight.w700, color: _p.ink),
          ),
          const SizedBox(height: 8),
          const SkeletonLine(width: 220),
          const SizedBox(height: 6),
          const SkeletonLine(width: 160),
        ],
      ),
    );
  }
}

/// Custom registration form builder.
class FormBuilderPreview extends StatelessWidget {
  const FormBuilderPreview({super.key});

  @override
  Widget build(BuildContext context) {
    const fields = [
      ('Full name', 'Short answer', Icons.short_text_rounded),
      ('Student number', 'Short answer', Icons.pin_rounded),
      ('Year level', 'Dropdown', Icons.arrow_drop_down_circle_rounded),
      ('Shirt size', 'Multiple choice', Icons.radio_button_checked_rounded),
    ];
    return PreviewWindow(
      palette: _p,
      title: 'Registration Forms',
      width: 480,
      height: 380,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title('Workshop registration form', size: 14),
            const SizedBox(height: 2),
            _sub('Custom fields for this event'),
            const SizedBox(height: 12),
            for (final (name, type, icon) in fields)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _p.border),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.drag_indicator_rounded,
                      size: 16,
                      color: _p.inkFaint,
                    ),
                    const SizedBox(width: 6),
                    Icon(icon, size: 16, color: _p.primary),
                    const SizedBox(width: 10),
                    Text(
                      name,
                      style: previewText(
                        11.5,
                        weight: FontWeight.w700,
                        color: _p.ink,
                      ),
                    ),
                    const Spacer(),
                    PreviewPill(text: type, color: _p.inkSoft),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 9),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _p.primary.withAlpha(120)),
                color: _p.tint,
              ),
              child: Text(
                '+ Add field',
                style: previewText(
                  11,
                  weight: FontWeight.w700,
                  color: _p.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Post-event analytics + feedback rating.
class EventAnalyticsCard extends StatelessWidget {
  const EventAnalyticsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return PreviewCard(
      palette: _p,
      width: 280,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _title('Event analytics', size: 11.5),
              const Spacer(),
              Icon(Icons.star_rounded, size: 14, color: _warn),
              const SizedBox(width: 2),
              Text(
                '4.6',
                style: previewText(11, weight: FontWeight.w800, color: _p.ink),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _sub('Attendance over the session', size: 9.5),
          const SizedBox(height: 10),
          MiniLine(
            values: const [20, 48, 90, 128, 140, 151, 151],
            color: _p.primary,
            height: 70,
          ),
        ],
      ),
    );
  }
}

/// Merchandise listing.
class MerchCard extends StatelessWidget {
  const MerchCard({super.key});

  @override
  Widget build(BuildContext context) {
    return PreviewCard(
      palette: _p,
      width: 190,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 100,
            decoration: BoxDecoration(
              color: _p.tint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Icon(Icons.checkroom_rounded, size: 52, color: _p.primary),
            ),
          ),
          const SizedBox(height: 8),
          _title('Org Shirt 2026', size: 11.5),
          const SizedBox(height: 2),
          Row(
            children: [
              Text(
                'PHP 350',
                style: previewText(
                  11,
                  weight: FontWeight.w800,
                  color: _p.primary,
                ),
              ),
              const Spacer(),
              const Icon(
                Icons.favorite_rounded,
                size: 12,
                color: Color(0xFFEF4444),
              ),
              const SizedBox(width: 3),
              _sub('48', size: 9.5),
            ],
          ),
        ],
      ),
    );
  }
}

/// Letter requests and their status.
class LetterRequestCard extends StatelessWidget {
  const LetterRequestCard({super.key});

  @override
  Widget build(BuildContext context) {
    return PreviewCard(
      palette: _p,
      width: 260,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.mail_rounded, size: 14, color: _p.primary),
              const SizedBox(width: 6),
              _title('Letter requests', size: 11.5),
            ],
          ),
          const SizedBox(height: 10),
          for (final (name, status, c) in const [
            ('Venue request', 'Approved', _green),
            ('Activity permit', 'Pending', _warn),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                children: [
                  Icon(Icons.description_outlined, size: 14, color: _p.inkSoft),
                  const SizedBox(width: 6),
                  Text(name, style: previewText(10.5, color: _p.ink)),
                  const Spacer(),
                  PreviewPill(text: status, color: c),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Proposal status (for the workflow PLAN step).
class ProposalStatusCard extends StatelessWidget {
  const ProposalStatusCard({super.key});

  @override
  Widget build(BuildContext context) {
    return PreviewCard(
      palette: _p,
      width: 270,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _sub('EVENT PROPOSAL', size: 9),
              const Spacer(),
              const PreviewPill(text: 'Approved', color: _green),
            ],
          ),
          const SizedBox(height: 8),
          _title('Intro to Flutter Workshop', size: 13.5),
          const SizedBox(height: 10),
          for (final (label, done) in const [
            ('Submitted', true),
            ('Reviewed by CICT Admin', true),
            ('Published to students', true),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(
                    done
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 14,
                    color: done ? _green : _p.inkFaint,
                  ),
                  const SizedBox(width: 6),
                  _sub(label),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Accomplishment / financial report submission.
class ReportSubmitCard extends StatelessWidget {
  const ReportSubmitCard({super.key});

  @override
  Widget build(BuildContext context) {
    return PreviewCard(
      palette: _p,
      width: 270,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('Event reports', size: 12),
          const SizedBox(height: 10),
          for (final (name, status, c) in const [
            ('Accomplishment report', 'Submitted', _green),
            ('Financial report', 'Due Oct 28', _warn),
          ])
            Container(
              margin: const EdgeInsets.only(bottom: 7),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _p.bg,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                children: [
                  Icon(Icons.upload_file_rounded, size: 14, color: _p.inkSoft),
                  const SizedBox(width: 6),
                  Text(name, style: previewText(10.5, color: _p.ink)),
                  const Spacer(),
                  PreviewPill(text: status, color: c),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

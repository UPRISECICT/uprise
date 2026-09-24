import 'package:flutter/material.dart';

import '../landing_palette.dart';
import 'preview_kit.dart';

// Illustrative previews of the admin portal's real modules (dashboard,
// organization management, event proposals + calendar, reports, activity
// logs). Sample figures only — nothing here reads live data.

const _p = LandingPalette.admin;
const _warn = Color(0xFFF59E0B);

Widget _title(String t, {double size = 12.5}) => Text(
  t,
  style: previewText(size, weight: FontWeight.w800, color: _p.ink),
);

Widget _sub(String t, {double size = 10}) =>
    Text(t, style: previewText(size, color: _p.inkSoft));

/// Hero base: the admin dashboard shell.
class AdminDashboardPreview extends StatelessWidget {
  const AdminDashboardPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return PreviewWindow(
      palette: _p,
      title: 'UPRISE Admin · Dashboard',
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
                  Icons.groups_rounded,
                  Icons.event_note_rounded,
                  Icons.calendar_month_rounded,
                  Icons.summarize_rounded,
                  Icons.history_rounded,
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
                  _title('Overview', size: 15),
                  const SizedBox(height: 2),
                  _sub('CICT organizations at a glance'),
                  const SizedBox(height: 12),
                  const Row(
                    children: [
                      Expanded(
                        child: KpiTile(
                          palette: _p,
                          icon: Icons.groups_rounded,
                          label: 'Organizations',
                          value: '18',
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: KpiTile(
                          palette: _p,
                          icon: Icons.pending_actions_rounded,
                          label: 'Pending proposals',
                          value: '5',
                          color: _warn,
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: KpiTile(
                          palette: _p,
                          icon: Icons.event_available_rounded,
                          label: 'Events this month',
                          value: '12',
                          color: Color(0xFF10B981),
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
                                _title('Events per month', size: 11),
                                const Spacer(),
                                MiniBars(
                                  values: const [4, 6, 5, 8, 7, 11, 9, 12],
                                  color: _p.primary,
                                  height: 110,
                                  highlight: 7,
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
                                _title('Recent activity', size: 11),
                                const SizedBox(height: 10),
                                for (final c in [
                                  _p.primary,
                                  const Color(0xFF10B981),
                                  _warn,
                                  _p.primary,
                                ])
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 11),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 7,
                                          height: 7,
                                          decoration: BoxDecoration(
                                            color: c,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        const Expanded(
                                          child: SkeletonLine(width: 90),
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

/// An event proposal waiting on the admin's decision.
class ProposalReviewCard extends StatelessWidget {
  const ProposalReviewCard({super.key});

  @override
  Widget build(BuildContext context) {
    return PreviewCard(
      palette: _p,
      width: 272,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _sub('EVENT PROPOSAL', size: 9),
              const Spacer(),
              const PreviewPill(text: 'Pending review', color: _warn),
            ],
          ),
          const SizedBox(height: 10),
          _title('CICT Tech Summit 2026', size: 14),
          const SizedBox(height: 4),
          _sub('Submitted by a CICT organization'),
          const SizedBox(height: 12),
          for (final (icon, text) in const [
            (Icons.calendar_today_rounded, 'Oct 14 · 1:00 PM'),
            (Icons.location_on_rounded, 'CICT Audio-Visual Room'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(icon, size: 12, color: _p.inkSoft),
                  const SizedBox(width: 6),
                  _sub(text),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _p.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Approve',
                    style: previewText(
                      11,
                      weight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _p.border),
                  ),
                  child: Text(
                    'Return',
                    style: previewText(
                      11,
                      weight: FontWeight.w700,
                      color: _p.ink,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Activity log feed.
class ActivityFeedCard extends StatelessWidget {
  final double width;

  const ActivityFeedCard({this.width = 260, super.key});

  @override
  Widget build(BuildContext context) {
    const rows = [
      (Icons.check_circle_rounded, 'Approved an event proposal', '2m'),
      (Icons.person_add_alt_1_rounded, 'Created officer account', '18m'),
      (Icons.upload_file_rounded, 'Report submitted', '1h'),
    ];
    return PreviewCard(
      palette: _p,
      width: width,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history_rounded, size: 14, color: _p.primary),
              const SizedBox(width: 6),
              _title('Activity log', size: 11.5),
            ],
          ),
          const SizedBox(height: 10),
          for (final (icon, text, time) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  IconBadge(icon: icon, color: _p.primary, size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      text,
                      overflow: TextOverflow.ellipsis,
                      style: previewText(10.5, color: _p.ink),
                    ),
                  ),
                  _sub(time, size: 9.5),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Organization directory with officers and advisers.
class OrgDirectoryPreview extends StatelessWidget {
  const OrgDirectoryPreview({super.key});

  @override
  Widget build(BuildContext context) {
    const orgs = [
      ('Computer Science Society', 'CS', Color(0xFF2563EB), '12 officers'),
      ('Information Technology Guild', 'IT', Color(0xFF7C3AED), '10 officers'),
      ('Information Systems Circle', 'IS', Color(0xFF0EA5E9), '9 officers'),
      ('CICT Student Council', 'SC', Color(0xFFF97316), '15 officers'),
      ('Developers Circle', 'DC', Color(0xFF10B981), '8 officers'),
    ];
    return PreviewWindow(
      palette: _p,
      title: 'Organization Management',
      width: 500,
      height: 410,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _title('Organizations', size: 14),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _p.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '+ New organization',
                    style: previewText(
                      10,
                      weight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final (name, ini, color, officers) in orgs)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _p.border),
                ),
                child: Row(
                  children: [
                    InitialsAvatar(initials: ini, color: color, size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        name,
                        style: previewText(
                          11.5,
                          weight: FontWeight.w700,
                          color: _p.ink,
                        ),
                      ),
                    ),
                    _sub(officers),
                    const SizedBox(width: 12),
                    const PreviewPill(text: 'Active', color: Color(0xFF10B981)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Officer + adviser assignment card.
class AdviserCard extends StatelessWidget {
  const AdviserCard({super.key});

  @override
  Widget build(BuildContext context) {
    return PreviewCard(
      palette: _p,
      width: 240,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('Officers & adviser', size: 11.5),
          const SizedBox(height: 10),
          for (final (ini, role, c) in const [
            ('AD', 'Adviser', Color(0xFF1E40AF)),
            ('PR', 'President', Color(0xFF2563EB)),
            ('SE', 'Secretary', Color(0xFF60A5FA)),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  InitialsAvatar(initials: ini, color: c, size: 24),
                  const SizedBox(width: 8),
                  const SkeletonLine(width: 70),
                  const Spacer(),
                  _sub(role, size: 9.5),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// College calendar with event markers.
class CollegeCalendarPreview extends StatelessWidget {
  const CollegeCalendarPreview({super.key});

  @override
  Widget build(BuildContext context) {
    const marks = {3: 0, 8: 1, 14: 0, 17: 2, 22: 1, 27: 0};
    const colors = [Color(0xFF2563EB), Color(0xFFF97316), Color(0xFF10B981)];
    return PreviewWindow(
      palette: _p,
      title: 'College Calendar',
      width: 480,
      height: 360,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                _title('October', size: 15),
                const Spacer(),
                Icon(Icons.chevron_left_rounded, size: 18, color: _p.inkSoft),
                Icon(Icons.chevron_right_rounded, size: 18, color: _p.inkSoft),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final d in const ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
                  Expanded(child: Center(child: _sub(d, size: 9.5))),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Column(
                children: [
                  for (var week = 0; week < 5; week++)
                    Expanded(
                      child: Row(
                        children: [
                          for (var dow = 0; dow < 7; dow++)
                            Expanded(
                              child: _day(week * 7 + dow - 2, marks, colors),
                            ),
                        ],
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

  Widget _day(int d, Map<int, int> marks, List<Color> colors) {
    if (d < 1 || d > 31) return const SizedBox.shrink();
    final mark = marks[d];
    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: d == 14 ? _p.tint : null,
        borderRadius: BorderRadius.circular(8),
        border: d == 14 ? Border.all(color: _p.primary.withAlpha(90)) : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$d',
            style: previewText(
              10.5,
              weight: d == 14 ? FontWeight.w800 : FontWeight.w500,
              color: _p.ink,
            ),
          ),
          if (mark != null) ...[
            const SizedBox(height: 3),
            Container(
              width: 14,
              height: 3,
              decoration: BoxDecoration(
                color: colors[mark],
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Report submissions + analytics.
class ReportsPreview extends StatelessWidget {
  const ReportsPreview({super.key});

  @override
  Widget build(BuildContext context) {
    const rows = [
      ('Financial report', 'Submitted', Color(0xFF10B981)),
      ('Accomplishment report', 'Submitted', Color(0xFF10B981)),
      ('Financial report', 'Due in 3 days', _warn),
    ];
    return PreviewWindow(
      palette: _p,
      title: 'Reports Management',
      width: 500,
      height: 370,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _title('Submissions this semester', size: 13),
                const Spacer(),
                const PreviewPill(
                  text: 'Export PDF',
                  color: Color(0xFF2563EB),
                  icon: Icons.download_rounded,
                ),
              ],
            ),
            const SizedBox(height: 12),
            MiniLine(
              values: const [3, 5, 4, 7, 6, 9, 8, 11],
              color: _p.primary,
              height: 96,
            ),
            const SizedBox(height: 14),
            for (final (name, status, c) in rows)
              Container(
                margin: const EdgeInsets.only(bottom: 7),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _p.bg,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.description_rounded,
                      size: 14,
                      color: _p.inkSoft,
                    ),
                    const SizedBox(width: 8),
                    Text(name, style: previewText(11, color: _p.ink)),
                    const Spacer(),
                    PreviewPill(text: status, color: c),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

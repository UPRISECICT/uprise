// lib/screens/web/org/org_announcements.dart
// Redesigned: Professional + Facebook-style feed
// Matches StudentAccounts design language exactly
// All Firestore parameters preserved for student-side compatibility

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart'; // 👈 for TapGestureRecognizer
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../services/activity_logger.dart' as activity_log;

// ─────────────────────────────────────────────────────────────────────────────
// Design Tokens — mirrors StudentAccounts exactly
// ─────────────────────────────────────────────────────────────────────────────
class _C {
  // Primary brand
  static const Color primaryDark = Color(0xFFEA580C);

  // Surfaces
  static const Color white = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFF8F9FB);
  static const Color pageBg = Color(0xFFFBFCFE);

  // Borders
  static const Color border = Color(0xFFE8ECF0);
  static const Color borderSoft = Color(0xFFE2E6EA);

  // Text
  static const Color charcoal = Color(0xFF1A202C);
  static const Color textMid = Color(0xFF374151);
  static const Color darkGray = Color(0xFF64748B);
  static const Color textFaint = Color(0xFF9AA5B4);

  // Semantic
  static const Color success = Color(0xFF059669);
  static const Color successBg = Color(0xFFECFDF5);
  static const Color warning = Color(0xFFFB923C);
  static const Color warningBg = Color(0xFFFFFBEB);
  static const Color error = Color(0xFFDC2626);
  static const Color errorBg = Color(0xFFFEF2F2);
  static const Color info = Color(0xFF2563EB);
  static const Color infoBg = Color(0xFFEFF6FF);
}

class _DS {
  static const double radiusSm = 8;
  static const double radiusLg = 16;
  static const double radiusPill = 100;

  static final List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Color.fromRGBO(0, 0, 0, 0.06),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];

  static final List<BoxShadow> postShadow = [
    BoxShadow(
      color: Color.fromRGBO(0, 0, 0, 0.07),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  // Required fields are labeled "Foo *" — the asterisk used to render in the
  // same muted gray as the rest of the label and was easy to miss. Splitting
  // it into its own red TextSpan (matching org_profile.dart's
  // _inputDecoration / org_event_proposals.dart's
  // _orgEventProposalsInputDecoration) makes it actually stand out.
  static InputDecoration inputDecoration(
    String label, {
    String? hint,
    IconData? icon,
  }) {
    final trimmed = label.trimRight();
    final isRequired = trimmed.endsWith('*');
    final baseLabel = isRequired
        ? trimmed.substring(0, trimmed.length - 1).trimRight()
        : label;

    return InputDecoration(
      labelText: isRequired ? null : label,
      label: isRequired ? requiredLabel(baseLabel) : null,
      hintText: hint,
      prefixIcon: icon != null
          ? Icon(icon, size: 18, color: _C.textFaint)
          : null,
      labelStyle: GoogleFonts.beVietnamPro(fontSize: 13, color: _C.darkGray),
      hintStyle: GoogleFonts.beVietnamPro(fontSize: 13, color: _C.textFaint),
      filled: true,
      fillColor: _C.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: const BorderSide(color: _C.borderSoft, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: const BorderSide(color: _C.borderSoft, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: const BorderSide(color: _C.primaryDark, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: const BorderSide(color: _C.error, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: const BorderSide(color: _C.error, width: 1.5),
      ),
    );
  }
}

// Shared by _DS.inputDecoration and the Category/Target Audience dropdowns
// (which build their own InputDecoration directly instead of going through
// _DS.inputDecoration) so every required-field asterisk in this modal is the
// same red, regardless of which field type renders it.
Widget requiredLabel(String text) {
  return RichText(
    text: TextSpan(
      children: [
        TextSpan(
          text: text,
          style: GoogleFonts.beVietnamPro(fontSize: 13, color: _C.darkGray),
        ),
        TextSpan(
          text: ' *',
          style: GoogleFonts.beVietnamPro(
            fontSize: 13,
            color: _C.error,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable micro-widgets
// ─────────────────────────────────────────────────────────────────────────────

String _relativeTime(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
  return DateFormat('MMM dd, yyyy').format(dt);
}

// One compact, fully-tappable card per pinned item — the "Pinned" badge,
// author avatar, and separate "View post" link all used to stack on top of
// each other per item (5 rows deep) when the panel header already says
// "Pinned", making three items look like a wall of chips and text. This
// keeps only what's actually useful at a glance: category, title, snippet,
// relative time.
class _PinnedItem extends StatelessWidget {
  final AnnouncementModel announcement;
  final VoidCallback onView;
  const _PinnedItem({required this.announcement, required this.onView});

  @override
  Widget build(BuildContext context) {
    final a = announcement;
    final theme = _categoryTheme(a.category);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: InkWell(
          onTap: onView,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _C.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 4,
                  height: 34,
                  margin: const EdgeInsets.only(top: 2, right: 10),
                  decoration: BoxDecoration(
                    color: theme.fg,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.title,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: _C.charcoal,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        a.content,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 11.5,
                          color: _C.darkGray,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            a.category,
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: theme.fg,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '·',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 10.5,
                              color: _C.textFaint,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _relativeTime(a.timestamp.toDate()),
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 10.5,
                              color: _C.textFaint,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: _C.textFaint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  const _FilterDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _C.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _C.borderSoft),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 18,
            color: _C.textFaint,
          ),
          style: GoogleFonts.beVietnamPro(fontSize: 13, color: _C.textMid),
          items: items
              .map(
                (s) => DropdownMenuItem(
                  value: s,
                  child: Text(s, style: GoogleFonts.beVietnamPro(fontSize: 13)),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

Widget _audienceBadge(String audience) {
  final Map<String, _BadgeTheme> map = {
    'Public': _BadgeTheme(_C.successBg, _C.success, Icons.public_rounded),
    'BulSUan': _BadgeTheme(
      const Color(0xFFF3E8FF),
      const Color(0xFF7C3AED),
      Icons.account_balance_rounded,
    ),
    'CICT Only': _BadgeTheme(_C.infoBg, _C.info, Icons.school_rounded),
    'Members Only': _BadgeTheme(_C.warningBg, _C.warning, Icons.group_rounded),
  };
  final t =
      map[audience] ??
      _BadgeTheme(
        const Color(0xFFF3F4F6),
        const Color(0xFF6B7280),
        Icons.people_outline,
      );
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: t.bg,
      borderRadius: BorderRadius.circular(_DS.radiusPill),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(t.icon, size: 11, color: t.fg),
        const SizedBox(width: 5),
        Text(
          audience,
          style: GoogleFonts.beVietnamPro(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: t.fg,
            letterSpacing: 0.3,
          ),
        ),
      ],
    ),
  );
}

class _BadgeTheme {
  final Color bg, fg;
  final IconData icon;
  const _BadgeTheme(this.bg, this.fg, this.icon);
}

IconData _audienceIcon(String audience) {
  switch (audience) {
    case 'Public':
      return Icons.public_rounded;
    case 'BulSUan':
      return Icons.account_balance_rounded;
    case 'CICT Only':
      return Icons.school_rounded;
    default:
      return Icons.group_rounded;
  }
}

// ── Linkable events (approved events with a published registration form) ──────
class _LinkableEvent {
  final String eventId;
  final String proposalId;
  final String title;
  final String audience;
  const _LinkableEvent({
    required this.eventId,
    required this.proposalId,
    required this.title,
    required this.audience,
  });
}

Future<List<_LinkableEvent>> _fetchLinkableEvents(String orgId) async {
  final eventsSnap = await FirebaseFirestore.instance
      .collection('events')
      .where('orgId', isEqualTo: orgId)
      .where('status', isEqualTo: 'approved')
      .get();

  final results = <_LinkableEvent>[];
  for (final doc in eventsSnap.docs) {
    final data = doc.data();
    final proposalId = (data['createdFromProposalId'] ?? '').toString();
    if (proposalId.isEmpty) continue;
    final formDoc = await FirebaseFirestore.instance
        .collection('registration_forms')
        .doc(proposalId)
        .get();
    if (!formDoc.exists) continue;
    if (formDoc.data()?['isPublished'] != true) continue;

    // Audience is sourced from the event itself (carried over from the
    // proposal on approval) so it stays in sync with what was approved.
    String audience = (data['audience'] ?? '').toString();
    if (audience.isEmpty) {
      final proposalDoc = await FirebaseFirestore.instance
          .collection('event_proposals')
          .doc(proposalId)
          .get();
      audience = (proposalDoc.data()?['audience'] ?? 'Public').toString();
    }

    results.add(
      _LinkableEvent(
        eventId: doc.id,
        proposalId: proposalId,
        title: (data['title'] ?? 'Event').toString(),
        audience: audience,
      ),
    );
  }
  return results;
}

// ── Categories ───────────────────────────────────────────────────────────────
// No fixed defaults — orgs create and manage their own categories.
const List<String> kDefaultAnnouncementCategories = [];

const Map<String, _BadgeTheme> _categoryThemes = {
  'General': _BadgeTheme(
    Color(0xFFF1F5F9),
    Color(0xFF475569),
    Icons.campaign_outlined,
  ),
  'New Hire': _BadgeTheme(
    Color(0xFFECFDF5),
    Color(0xFF059669),
    Icons.person_add_alt_1_rounded,
  ),
  'SOP Updates': _BadgeTheme(
    Color(0xFFEFF6FF),
    Color(0xFF2563EB),
    Icons.fact_check_outlined,
  ),
  'Policy Updates': _BadgeTheme(
    Color(0xFFF3E8FF),
    Color(0xFF7C3AED),
    Icons.policy_outlined,
  ),
  'Promotion': _BadgeTheme(
    Color(0xFFFFFBEB),
    Color(0xFFFB923C),
    Icons.trending_up_rounded,
  ),
  'Transfer': _BadgeTheme(
    Color(0xFFFFE4E6),
    Color(0xFFE11D48),
    Icons.swap_horiz_rounded,
  ),
  'Training': _BadgeTheme(
    Color(0xFFE0F2FE),
    Color(0xFF0284C7),
    Icons.school_outlined,
  ),
  'Special': _BadgeTheme(
    Color(0xFFFCE7F3),
    Color(0xFFDB2777),
    Icons.star_outline_rounded,
  ),
};

_BadgeTheme _categoryTheme(String category) =>
    _categoryThemes[category] ??
    const _BadgeTheme(
      Color(0xFFF1F5F9),
      Color(0xFF475569),
      Icons.label_outline_rounded,
    );

Widget _categoryBadge(String category) {
  final t = _categoryTheme(category);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: t.bg,
      borderRadius: BorderRadius.circular(_DS.radiusPill),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(t.icon, size: 11, color: t.fg),
        const SizedBox(width: 5),
        Text(
          category,
          style: GoogleFonts.beVietnamPro(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: t.fg,
            letterSpacing: 0.3,
          ),
        ),
      ],
    ),
  );
}

// Section label — same as StudentAccounts
Widget _sectionLabel(String text, {IconData? icon}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: _C.primaryDark),
          const SizedBox(width: 8),
        ],
        Text(
          text,
          style: GoogleFonts.beVietnamPro(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: _C.primaryDark,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(child: Divider(color: _C.borderSoft, thickness: 1)),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Main Screen
// ─────────────────────────────────────────────────────────────────────────────
class OrgAnnouncementsScreen extends StatefulWidget {
  final String orgId;
  const OrgAnnouncementsScreen({super.key, required this.orgId});

  @override
  State<OrgAnnouncementsScreen> createState() => _OrgAnnouncementsScreenState();
}

class _OrgAnnouncementsScreenState extends State<OrgAnnouncementsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _filterMode = 'All';
  int _currentPage = 1;
  static const int _pageSize = 5;

  // Category sidebar selection + any custom categories added this session.
  String _selectedCategory = 'All Announcement';
  final List<String> _customCategories = [];
  List<String> get _allCategories =>
      {...kDefaultAnnouncementCategories, ..._customCategories}.toList();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Created once, not a getter — re-evaluating .snapshots() on every
  // keystroke in the search box was re-subscribing to Firestore from
  // scratch on every character typed.
  late final Stream<QuerySnapshot> _stream = FirebaseFirestore.instance
      .collection('announcements')
      .where('orgId', isEqualTo: widget.orgId)
      .snapshots();

  List<AnnouncementModel> _filtered(List<AnnouncementModel> list) {
    var out = List<AnnouncementModel>.from(list);
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      out = out
          .where(
            (a) =>
                a.title.toLowerCase().contains(q) ||
                a.content.toLowerCase().contains(q),
          )
          .toList();
    }
    if (_filterMode == 'Pinned') {
      out = out.where((a) => a.isPinned).toList();
    } else if (_filterMode == 'With Attachments') {
      out = out.where((a) => a.attachmentsBase64.isNotEmpty).toList();
    }
    if (_selectedCategory != 'All Announcement') {
      out = out.where((a) => a.category == _selectedCategory).toList();
    }
    return out;
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                msg,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? _C.error : _C.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_DS.radiusSm),
        ),
      ),
    );
  }

  Future<void> _deleteAnnouncement(AnnouncementModel a) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_DS.radiusLg),
        ),
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _C.errorBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      color: _C.error,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    'Delete Announcement',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: _C.charcoal,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Are you sure you want to delete "${a.title}"? This action cannot be undone.',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 14,
                  color: _C.darkGray,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _C.borderSoft),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        color: _C.textMid,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _C.error,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'Delete',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirm != true) return;
    try {
      await FirebaseFirestore.instance
          .collection('announcements')
          .doc(a.id)
          .delete();
      await activity_log.ActivityLogger.log(
        action: 'delete_announcement',
        module: 'announcements',
        details: {'orgId': widget.orgId, 'announcementId': a.id},
      );
      if (mounted) _snack('Announcement deleted successfully');
    } catch (e) {
      if (mounted) _snack('Error: $e', isError: true);
    }
  }

  static const int _maxPinned = 3;

  // ── Toggle pin ────────────────────────────────────────────────────────────
  Future<void> _togglePin(
    AnnouncementModel a,
    List<AnnouncementModel> allAnnouncements,
  ) async {
    if (!a.isPinned) {
      final pinnedCount = allAnnouncements.where((x) => x.isPinned).length;
      if (pinnedCount >= _maxPinned) {
        _snack(
          'You can only pin up to $_maxPinned announcements at a time. Unpin one first.',
          isError: true,
        );
        return;
      }
    }
    try {
      await FirebaseFirestore.instance
          .collection('announcements')
          .doc(a.id)
          .update({'pinned': !a.isPinned});
      _snack(a.isPinned ? 'Unpinned' : 'Pinned announcement');
    } catch (e) {
      _snack('Error: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 720;
    final isTablet = width >= 720 && width < 1200;
    final isWide = width >= 1300;
    final horizontalPadding = isMobile ? 16.0 : 24.0;

    return Scaffold(
      backgroundColor: _C.pageBg,
      body: StreamBuilder<QuerySnapshot>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: _C.primaryDark),
            );
          }
          if (snap.hasError) {
            return Center(
              child: Text(
                'Error: ${snap.error}',
                style: GoogleFonts.beVietnamPro(),
              ),
            );
          }

          final all = (snap.data?.docs ?? [])
              .map((d) => AnnouncementModel.fromFirestore(d))
              .toList();
          all.sort((a, b) {
            // Pinned always first
            if (a.isPinned && !b.isPinned) return -1;
            if (!a.isPinned && b.isPinned) return 1;
            return b.timestamp.toDate().compareTo(a.timestamp.toDate());
          });

          return Padding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              20,
              horizontalPadding,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: isWide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _buildCenterColumn(
                                all,
                                isMobile,
                                isTablet,
                              ),
                            ),
                            const SizedBox(width: 20),
                            SizedBox(width: 280, child: _buildPinnedPanel(all)),
                          ],
                        )
                      : _buildCenterColumn(all, isMobile, isTablet),
                ),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Center column: toolbar + feed (shared by wide and narrow layouts) ─────
  Widget _buildCenterColumn(
    List<AnnouncementModel> all,
    bool isMobile,
    bool isTablet,
  ) {
    final filtered = _filtered(all);
    final totalPages = filtered.isEmpty
        ? 1
        : (filtered.length / _pageSize).ceil();
    final safePage = _currentPage.clamp(1, totalPages);
    final start = (safePage - 1) * _pageSize;
    final end = (start + _pageSize).clamp(0, filtered.length);
    final pageItems = filtered.isEmpty
        ? <AnnouncementModel>[]
        : filtered.sublist(start, end);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildToolbar(isMobile, isTablet),
        const SizedBox(height: 16),
        Expanded(
          child: all.isEmpty
              ? _buildEmptyState()
              : Container(
                  decoration: BoxDecoration(
                    color: _C.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _C.border),
                    boxShadow: _DS.cardShadow,
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: pageItems.isEmpty
                            ? _buildEmptySearchState()
                            : _buildFeedContent(pageItems, all),
                      ),
                      _buildPaginationFooter(
                        filtered.length,
                        totalPages,
                        start,
                        end,
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  // Category selection now lives in the toolbar (see _buildToolbar) as a
  // compact dropdown next to the existing Filter dropdown, instead of a
  // dedicated sidebar column — one less thing competing for attention on
  // this page. _promptAddCategory (below) is still reachable from the
  // announcement composer dialog.

  Future<String?> _promptAddCategory() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_DS.radiusLg),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'New Category',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _C.charcoal,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                autofocus: true,
                style: GoogleFonts.beVietnamPro(fontSize: 13),
                decoration: _DS.inputDecoration(
                  'Category name',
                  hint: 'e.g. Reminders',
                  icon: Icons.label_outline_rounded,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _C.borderSoft),
                    ),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        color: _C.textMid,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _C.primaryDark,
                      foregroundColor: Colors.white,
                      elevation: 0,
                    ),
                    child: Text(
                      'Add',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (result != null &&
        result.isNotEmpty &&
        !_allCategories.contains(result)) {
      setState(() => _customCategories.add(result));
    }
    return (result != null && result.isNotEmpty) ? result : null;
  }

  // ── Pinned panel (wide layout) ──────────────────────────────────────────────
  Widget _buildPinnedPanel(List<AnnouncementModel> all) {
    final pinned = all.where((a) => a.isPinned).take(_maxPinned).toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _C.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _C.border),
        boxShadow: _DS.cardShadow,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.push_pin_rounded, size: 15, color: _C.warning),
                const SizedBox(width: 6),
                Text(
                  'Pinned',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _C.charcoal,
                  ),
                ),
                if (pinned.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Text(
                    '${pinned.length}/$_maxPinned',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: _C.textFaint,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            if (pinned.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'No pinned announcements yet.',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12,
                    color: _C.textFaint,
                  ),
                ),
              )
            else
              ...pinned.map(
                (a) => _PinnedItem(
                  announcement: a,
                  onView: () => _showViewPostDialog(a),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showViewPostDialog(AnnouncementModel a) {
    // base64Decode throws synchronously for malformed data — decode once,
    // safely, up front instead of inline in the widget tree so a bad image
    // string can't take the whole dialog down with it.
    Uint8List? imageBytes;
    if (a.imageBase64 != null && a.imageBase64!.isNotEmpty) {
      try {
        imageBytes = base64Decode(a.imageBase64!);
      } catch (_) {
        imageBytes = null;
      }
    }
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_DS.radiusLg),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 480,
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
                decoration: const BoxDecoration(
                  color: _C.primaryDark,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(_DS.radiusLg),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        a.title,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _categoryBadge(a.category),
                          _audienceBadge(a.targetAudience),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        DateFormat(
                          'MMMM dd, yyyy • h:mm a',
                        ).format(a.timestamp.toDate()),
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 11,
                          color: _C.textFaint,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (imageBytes != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(_DS.radiusSm),
                          child: Image.memory(
                            imageBytes,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      // Use the same link-enabled text widget here as well
                      _buildContentWithLinks(a.content),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Toolbar (mirrors StudentAccounts toolbar exactly) ─────────────────────
  Widget _buildToolbar(bool isMobile, bool isTablet) {
    final searchField = SizedBox(
      width: isMobile ? double.infinity : 280,
      height: 40,
      child: TextField(
        controller: _searchController,
        style: GoogleFonts.beVietnamPro(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Search announcements…',
          hintStyle: GoogleFonts.beVietnamPro(
            fontSize: 13,
            color: _C.textFaint,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            size: 18,
            color: _C.textFaint,
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 0,
            horizontal: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _C.borderSoft),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _C.borderSoft),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _C.primaryDark, width: 1.5),
          ),
        ),
        onChanged: (v) => setState(() {
          _searchQuery = v;
          _currentPage = 1;
        }),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 680) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: searchField),
              const SizedBox(width: 12),
              if (_allCategories.isNotEmpty) ...[
                _FilterDropdown(
                  value: _selectedCategory,
                  items: ['All Announcement', ..._allCategories],
                  onChanged: (v) => setState(() {
                    _selectedCategory = v!;
                    _currentPage = 1;
                  }),
                ),
                const SizedBox(width: 12),
              ],
              _FilterDropdown(
                value: _filterMode,
                items: const ['All', 'Pinned', 'With Attachments'],
                onChanged: (v) => setState(() {
                  _filterMode = v!;
                  _currentPage = 1;
                }),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            searchField,
            const SizedBox(height: 10),
            if (_allCategories.isNotEmpty) ...[
              _FilterDropdown(
                value: _selectedCategory,
                items: ['All Announcement', ..._allCategories],
                onChanged: (v) => setState(() {
                  _selectedCategory = v!;
                  _currentPage = 1;
                }),
              ),
              const SizedBox(height: 10),
            ],
            _FilterDropdown(
              value: _filterMode,
              items: const ['All', 'Pinned', 'With Attachments'],
              onChanged: (v) => setState(() {
                _filterMode = v!;
                _currentPage = 1;
              }),
            ),
          ],
        );
      },
    );
  }

  // ── Feed shell (same card container as StudentAccounts table) ─────────────
  Widget _buildFeedContent(
    List<AnnouncementModel> items,
    List<AnnouncementModel> allAnnouncements,
  ) {
    return CustomScrollView(
      slivers: [
        // Composer teaser (Facebook-style "What's on your mind?")
        SliverToBoxAdapter(child: _buildComposerTeaser()),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => _PostCard(
                announcement: items[i],
                onEdit: () => _showAnnouncementDialog(existing: items[i]),
                onDelete: () => _deleteAnnouncement(items[i]),
                onTogglePin: () => _togglePin(items[i], allAnnouncements),
              ),
              childCount: items.length,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildComposerTeaser() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _C.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => _showAnnouncementDialog(),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Org avatar
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _C.primaryDark.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.campaign_rounded,
                      size: 20,
                      color: _C.primaryDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: _C.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _C.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              "What's on your mind? Create an announcement…",
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 13,
                                color: _C.textFaint,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.edit_note_rounded,
                            size: 16,
                            color: _C.textFaint,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: _C.borderSoft),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _C.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _C.border),
        boxShadow: _DS.cardShadow,
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: _C.surface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.campaign_outlined,
                size: 40,
                color: _C.textFaint,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No Announcements Yet',
              style: GoogleFonts.beVietnamPro(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _C.charcoal,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap "What\'s on your mind?" to create your first post.',
              style: GoogleFonts.beVietnamPro(fontSize: 13, color: _C.darkGray),
            ),
            const SizedBox(height: 20),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => _showAnnouncementDialog(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: _C.primaryDark,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.add_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Create Announcement',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptySearchState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.search_off_rounded, size: 48, color: _C.textFaint),
          const SizedBox(height: 12),
          Text(
            'No matching announcements',
            style: GoogleFonts.beVietnamPro(fontSize: 14, color: _C.darkGray),
          ),
        ],
      ),
    );
  }

  Widget _buildPaginationFooter(int total, int totalPages, int start, int end) {
    const int maxVisible = 5;
    int firstPage = (_currentPage - maxVisible ~/ 2).clamp(1, totalPages);
    int lastPage = (firstPage + maxVisible - 1).clamp(1, totalPages);
    final pages = List.generate(lastPage - firstPage + 1, (i) => firstPage + i);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _C.border)),
        color: _C.surface,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(14)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Showing ${total == 0 ? 0 : start + 1}–$end of $total announcements',
            style: GoogleFonts.beVietnamPro(fontSize: 12, color: _C.darkGray),
          ),
          Row(
            children: [
              _PageBtn(
                icon: Icons.chevron_left_rounded,
                enabled: _currentPage > 1,
                onTap: () => setState(() => _currentPage--),
              ),
              const SizedBox(width: 4),
              ...pages.map(
                (p) => _PageNumBtn(
                  page: p,
                  isActive: p == _currentPage,
                  onTap: () => setState(() => _currentPage = p),
                ),
              ),
              const SizedBox(width: 4),
              _PageBtn(
                icon: Icons.chevron_right_rounded,
                enabled: _currentPage < totalPages,
                onTap: () => setState(() => _currentPage++),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // CREATE / EDIT DIALOG
  // ==========================================================================
  void _showAnnouncementDialog({
    AnnouncementModel? existing,
    String? focusSection,
  }) {
    final isEdit = existing != null;
    final formKey = GlobalKey<FormState>();
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final contentCtrl = TextEditingController(text: existing?.content ?? '');
    final imageSectionKey = GlobalKey();

    final eventSectionKey = GlobalKey();
    bool isPinned = existing?.isPinned ?? false;
    String? imageBase64 = existing?.imageBase64;
    List<AttachmentBase64> attachments = List.from(
      existing?.attachmentsBase64 ?? [],
    );
    String targetAudience = existing?.targetAudience ?? 'Members Only';
    String category = existing?.category ?? '';
    bool isSubmitting = false;
    bool isScheduled = existing?.scheduledPublishDate != null;
    DateTime? scheduledDate;
    TimeOfDay? scheduledTime;
    String? linkedEventId = (existing?.linkedEventId.isNotEmpty ?? false)
        ? existing!.linkedEventId
        : null;
    String? linkedProposalId = (existing?.linkedProposalId.isNotEmpty ?? false)
        ? existing!.linkedProposalId
        : null;
    String? linkedEventTitle = (existing?.linkedEventTitle.isNotEmpty ?? false)
        ? existing!.linkedEventTitle
        : null;
    final linkableEventsFuture = _fetchLinkableEvents(widget.orgId);

    if (existing != null && existing.scheduledPublishDate != null) {
      scheduledDate = existing.scheduledPublishDate!.toDate();
      scheduledTime = TimeOfDay.fromDateTime(scheduledDate);
    }

    bool hasScrolledToFocus = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          if (!hasScrolledToFocus && focusSection != null) {
            hasScrolledToFocus = true;
            final targetKey = switch (focusSection) {
              'photo' => imageSectionKey,
              'event' => eventSectionKey,
              _ => null,
            };
            if (targetKey != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                final targetContext = targetKey.currentContext;
                if (targetContext != null) {
                  Scrollable.ensureVisible(
                    targetContext,
                    duration: const Duration(milliseconds: 300),
                    alignment: 0.1,
                  );
                }
              });
            }
          }
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            child: Container(
              width: 620,
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.88,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Header ──────────────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 18, 16, 18),
                    decoration: const BoxDecoration(
                      color: _C.primaryDark,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(18),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            isEdit
                                ? Icons.edit_rounded
                                : Icons.campaign_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isEdit
                                    ? 'Edit Announcement'
                                    : 'Create Announcement',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                'Fields marked * are required',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 11,
                                  color: Colors.white.withAlpha(180),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),

                  // ── Body ────────────────────────────────────────────────────
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sectionLabel(
                              'Post Details',
                              icon: Icons.article_outlined,
                            ),
                            TextFormField(
                              controller: titleCtrl,
                              decoration: _DS.inputDecoration(
                                'Title *',
                                hint: 'Enter announcement title',
                                icon: Icons.title_rounded,
                              ),
                              style: GoogleFonts.beVietnamPro(fontSize: 13),
                              onChanged: (_) => setDlg(() {}),
                              validator: (v) => v?.trim().isEmpty == true
                                  ? 'Title is required'
                                  : null,
                            ),
                            const SizedBox(height: 14),
                            Container(
                              decoration: BoxDecoration(
                                color: _C.surface,
                                borderRadius: BorderRadius.circular(
                                  _DS.radiusSm,
                                ),
                                border: Border.all(color: _C.borderSoft),
                              ),
                              child: DropdownButtonFormField<String>(
                                value: _allCategories.contains(category)
                                    ? category
                                    : null,
                                decoration: InputDecoration(
                                  label: requiredLabel('Category'),
                                  hintText: _allCategories.isEmpty
                                      ? 'No categories yet — add one'
                                      : 'Select a category',
                                  hintStyle: GoogleFonts.beVietnamPro(
                                    fontSize: 13,
                                    color: _C.textFaint,
                                  ),
                                  prefixIcon: Icon(
                                    category.isNotEmpty
                                        ? _categoryTheme(category).icon
                                        : Icons.label_outline_rounded,
                                    size: 18,
                                    color: _C.textFaint,
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                ),
                                items: [
                                  ..._allCategories.map(
                                    (c) => DropdownMenuItem(
                                      value: c,
                                      child: Text(
                                        c,
                                        style: GoogleFonts.beVietnamPro(
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: '__add_new__',
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.add_rounded,
                                          size: 16,
                                          color: _C.primaryDark,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Add new category',
                                          style: GoogleFonts.beVietnamPro(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: _C.primaryDark,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                onChanged: (v) async {
                                  if (v == '__add_new__') {
                                    final added = await _promptAddCategory();
                                    if (added != null)
                                      setDlg(() => category = added);
                                  } else if (v != null) {
                                    setDlg(() => category = v);
                                  }
                                },
                                validator: (_) => category.trim().isEmpty
                                    ? 'Please select or add a category'
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: contentCtrl,
                              maxLines: 5,
                              decoration: _DS.inputDecoration(
                                'Content *',
                                hint: 'Write your announcement here…',
                                icon: Icons.description_outlined,
                              ),
                              style: GoogleFonts.beVietnamPro(fontSize: 13),
                              onChanged: (_) => setDlg(() {}),
                              validator: (v) => v?.trim().isEmpty == true
                                  ? 'Content is required'
                                  : null,
                            ),
                            const SizedBox(height: 20),

                            // ── Live preview — mirrors the exact card the feed
                            // will render, so the org sees the real output
                            // before publishing instead of guessing from the
                            // raw form fields.
                            _sectionLabel(
                              'Preview',
                              icon: Icons.visibility_outlined,
                            ),
                            IgnorePointer(
                              child: _PostCard(
                                announcement: AnnouncementModel(
                                  id: 'preview',
                                  title: titleCtrl.text.trim().isEmpty
                                      ? 'Your title will appear here'
                                      : titleCtrl.text.trim(),
                                  content: contentCtrl.text.trim().isEmpty
                                      ? 'Your announcement content will appear here…'
                                      : contentCtrl.text.trim(),
                                  authorId: '',
                                  authorName:
                                      FirebaseAuth
                                          .instance
                                          .currentUser
                                          ?.displayName ??
                                      FirebaseAuth
                                          .instance
                                          .currentUser
                                          ?.email ??
                                      'You',
                                  timestamp: Timestamp.now(),
                                  attachmentsBase64: attachments,
                                  imageBase64: imageBase64,
                                  isPinned: isPinned,
                                  targetAudience: targetAudience,
                                  category: category.isEmpty
                                      ? 'General'
                                      : category,
                                ),
                                onEdit: () {},
                                onDelete: () {},
                                onTogglePin: () {},
                              ),
                            ),
                            const SizedBox(height: 20),

                            KeyedSubtree(
                              key: imageSectionKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _sectionLabel(
                                    'Banner Image',
                                    icon: Icons.image_outlined,
                                  ),
                                  _buildImagePicker(
                                    imageBase64,
                                    (v) => setDlg(() => imageBase64 = v),
                                    () => setDlg(() => imageBase64 = null),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),

                            _sectionLabel(
                              'Attachments',
                              icon: Icons.attach_file_rounded,
                            ),
                            _buildAttachmentsPicker(
                              attachments,
                              (v) => setDlg(() => attachments = v),
                            ),
                            const SizedBox(height: 20),

                            KeyedSubtree(
                              key: eventSectionKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _sectionLabel(
                                    'Link to Event',
                                    icon: Icons.event_available_rounded,
                                  ),
                                  FutureBuilder<List<_LinkableEvent>>(
                                    future: linkableEventsFuture,
                                    builder: (ctx2, snap) {
                                      final events =
                                          snap.data ?? const <_LinkableEvent>[];
                                      if (snap.connectionState !=
                                          ConnectionState.done) {
                                        return const Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: 8,
                                          ),
                                          child: SizedBox(
                                            height: 18,
                                            width: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                        );
                                      }
                                      if (events.isEmpty) {
                                        return Text(
                                          'No approved events with a published registration form yet.',
                                          style: GoogleFonts.beVietnamPro(
                                            fontSize: 11.5,
                                            color: _C.textFaint,
                                          ),
                                        );
                                      }
                                      return Container(
                                        decoration: BoxDecoration(
                                          color: _C.surface,
                                          borderRadius: BorderRadius.circular(
                                            _DS.radiusSm,
                                          ),
                                          border: Border.all(
                                            color: _C.borderSoft,
                                          ),
                                        ),
                                        child: DropdownButtonFormField<String>(
                                          value: linkedProposalId,
                                          decoration: InputDecoration(
                                            labelText:
                                                'Registration form (optional)',
                                            labelStyle:
                                                GoogleFonts.beVietnamPro(
                                                  fontSize: 13,
                                                  color: _C.darkGray,
                                                ),
                                            prefixIcon: const Icon(
                                              Icons.link_rounded,
                                              size: 18,
                                              color: _C.textFaint,
                                            ),
                                            border: InputBorder.none,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 16,
                                                  vertical: 14,
                                                ),
                                          ),
                                          items: [
                                            DropdownMenuItem(
                                              value: null,
                                              child: Text(
                                                'None',
                                                style: GoogleFonts.beVietnamPro(
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                            ...events.map(
                                              (e) => DropdownMenuItem(
                                                value: e.proposalId,
                                                child: Text(
                                                  e.title,
                                                  style:
                                                      GoogleFonts.beVietnamPro(
                                                        fontSize: 13,
                                                      ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ),
                                          ],
                                          onChanged: (v) => setDlg(() {
                                            if (v == null) {
                                              linkedEventId = null;
                                              linkedProposalId = null;
                                              linkedEventTitle = null;
                                            } else {
                                              final ev = events.firstWhere(
                                                (e) => e.proposalId == v,
                                              );
                                              linkedEventId = ev.eventId;
                                              linkedProposalId = ev.proposalId;
                                              linkedEventTitle = ev.title;
                                              // Audience is auto-determined from the linked event.
                                              targetAudience = ev.audience;
                                            }
                                          }),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),

                            _sectionLabel('Settings', icon: Icons.tune_rounded),
                            // Audience — auto-determined when linked to an event,
                            // otherwise the org picks it manually.
                            if (linkedProposalId != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: _C.infoBg,
                                  borderRadius: BorderRadius.circular(
                                    _DS.radiusSm,
                                  ),
                                  border: Border.all(
                                    color: _C.info.withAlpha(64),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    _audienceBadge(targetAudience),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Automatically determined by the linked event',
                                        style: GoogleFonts.beVietnamPro(
                                          fontSize: 11.5,
                                          color: _C.info,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              Container(
                                decoration: BoxDecoration(
                                  color: _C.surface,
                                  borderRadius: BorderRadius.circular(
                                    _DS.radiusSm,
                                  ),
                                  border: Border.all(color: _C.borderSoft),
                                ),
                                child: DropdownButtonFormField<String>(
                                  value: targetAudience,
                                  decoration: InputDecoration(
                                    labelText: 'Target Audience',
                                    labelStyle: GoogleFonts.beVietnamPro(
                                      fontSize: 13,
                                      color: _C.darkGray,
                                    ),
                                    prefixIcon: const Icon(
                                      Icons.people_outline,
                                      size: 18,
                                      color: _C.textFaint,
                                    ),
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 14,
                                    ),
                                  ),
                                  items:
                                      [
                                            'Public',
                                            'BulSUan',
                                            'CICT Only',
                                            'Members Only',
                                          ]
                                          .map(
                                            (o) => DropdownMenuItem(
                                              value: o,
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    _audienceIcon(o),
                                                    size: 15,
                                                    color: _C.primaryDark,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    o,
                                                    style:
                                                        GoogleFonts.beVietnamPro(
                                                          fontSize: 13,
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          )
                                          .toList(),
                                  onChanged: (v) =>
                                      setDlg(() => targetAudience = v!),
                                ),
                              ),
                            const SizedBox(height: 14),

                            // Schedule
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: _C.surface,
                                borderRadius: BorderRadius.circular(
                                  _DS.radiusSm,
                                ),
                                border: Border.all(color: _C.borderSoft),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Switch(
                                        value: isScheduled,
                                        onChanged: (val) => setDlg(() {
                                          isScheduled = val;
                                          if (!isScheduled) {
                                            scheduledDate = null;
                                            scheduledTime = null;
                                          }
                                        }),
                                        activeColor: _C.primaryDark,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Schedule for later',
                                        style: GoogleFonts.beVietnamPro(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: _C.charcoal,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (isScheduled) ...[
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: InkWell(
                                            onTap: () async {
                                              final p = await showDatePicker(
                                                context: ctx,
                                                initialDate: DateTime.now(),
                                                firstDate: DateTime.now(),
                                                lastDate: DateTime.now().add(
                                                  const Duration(days: 365),
                                                ),
                                                // Material 3's default seed skews
                                                // purple/indigo unless the scheme is
                                                // seeded from the brand color instead.
                                                builder: (context, child) {
                                                  final baseTheme = Theme.of(
                                                    context,
                                                  );
                                                  final scheme =
                                                      ColorScheme.fromSeed(
                                                        seedColor:
                                                            _C.primaryDark,
                                                        brightness:
                                                            Brightness.light,
                                                      ).copyWith(
                                                        primary: _C.primaryDark,
                                                        onPrimary: Colors.white,
                                                        surface: Colors.white,
                                                        surfaceTint:
                                                            Colors.transparent,
                                                      );
                                                  return Theme(
                                                    data: baseTheme.copyWith(
                                                      colorScheme: scheme,
                                                      textButtonTheme:
                                                          TextButtonThemeData(
                                                            style: TextButton.styleFrom(
                                                              foregroundColor:
                                                                  _C.primaryDark,
                                                            ),
                                                          ),
                                                    ),
                                                    child: child!,
                                                  );
                                                },
                                              );
                                              if (p != null)
                                                setDlg(() => scheduledDate = p);
                                            },
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 14,
                                                    vertical: 12,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(
                                                      _DS.radiusSm,
                                                    ),
                                                border: Border.all(
                                                  color: _C.borderSoft,
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  const Icon(
                                                    Icons
                                                        .calendar_today_rounded,
                                                    size: 15,
                                                    color: _C.primaryDark,
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Text(
                                                    scheduledDate != null
                                                        ? DateFormat(
                                                            'MMM dd, yyyy',
                                                          ).format(
                                                            scheduledDate!,
                                                          )
                                                        : 'Select date',
                                                    style:
                                                        GoogleFonts.beVietnamPro(
                                                          fontSize: 13,
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: InkWell(
                                            onTap: () async {
                                              final p = await showTimePicker(
                                                context: ctx,
                                                initialTime: TimeOfDay.now(),
                                              );
                                              if (p != null)
                                                setDlg(() => scheduledTime = p);
                                            },
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 14,
                                                    vertical: 12,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(
                                                      _DS.radiusSm,
                                                    ),
                                                border: Border.all(
                                                  color: _C.borderSoft,
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  const Icon(
                                                    Icons.access_time_rounded,
                                                    size: 15,
                                                    color: _C.primaryDark,
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Text(
                                                    scheduledTime != null
                                                        ? scheduledTime!.format(
                                                            ctx,
                                                          )
                                                        : 'Select time',
                                                    style:
                                                        GoogleFonts.beVietnamPro(
                                                          fontSize: 13,
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Pin toggle
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: isPinned ? _C.warningBg : _C.surface,
                                borderRadius: BorderRadius.circular(
                                  _DS.radiusSm,
                                ),
                                border: Border.all(
                                  color: isPinned
                                      ? _C.warning.withOpacity(0.4)
                                      : _C.borderSoft,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Switch(
                                    value: isPinned,
                                    onChanged: (v) =>
                                        setDlg(() => isPinned = v),
                                    activeColor: _C.warning,
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(
                                    Icons.push_pin_rounded,
                                    size: 15,
                                    color: _C.warning,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Pin this announcement',
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: _C.charcoal,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    'Pinned posts appear at the top of the feed',
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 11,
                                      color: _C.darkGray,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // ── Footer ──────────────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: _C.border)),
                      color: _C.surface,
                      borderRadius: BorderRadius.vertical(
                        bottom: Radius.circular(18),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: _C.borderSoft),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 11,
                            ),
                          ),
                          child: Text(
                            'Cancel',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 13,
                              color: _C.textMid,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: isSubmitting
                              ? null
                              : () async {
                                  if (!formKey.currentState!.validate()) return;

                                  // Firestore caps a single document at
                                  // ~1MiB; the image and every attachment
                                  // are stored inline as base64 in this
                                  // same doc, so keep their combined size
                                  // well under that ceiling rather than
                                  // let a large announcement fail with a
                                  // raw Firestore error at write time.
                                  final totalBase64Bytes =
                                      (imageBase64?.length ?? 0) +
                                      attachments.fold<int>(
                                        0,
                                        (acc, a) => acc + a.base64.length,
                                      );
                                  if (totalBase64Bytes > 900 * 1024) {
                                    _snack(
                                      'This announcement is too large to save. '
                                      'Remove the image or an attachment and try again.',
                                      isError: true,
                                    );
                                    return;
                                  }

                                  setDlg(() => isSubmitting = true);
                                  try {
                                    final user =
                                        FirebaseAuth.instance.currentUser!;
                                    final userDoc = await FirebaseFirestore
                                        .instance
                                        .collection('users')
                                        .doc(user.uid)
                                        .get();
                                    final authorName =
                                        userDoc.data()?['name'] ??
                                        user.email ??
                                        'Unknown';

                                    Timestamp? scheduledTs;
                                    if (isScheduled &&
                                        scheduledDate != null &&
                                        scheduledTime != null) {
                                      scheduledTs = Timestamp.fromDate(
                                        DateTime(
                                          scheduledDate!.year,
                                          scheduledDate!.month,
                                          scheduledDate!.day,
                                          scheduledTime!.hour,
                                          scheduledTime!.minute,
                                        ),
                                      );
                                    }

                                    // ─ All original Firestore fields preserved ─
                                    final data = {
                                      'orgId': widget.orgId,
                                      'title': titleCtrl.text.trim(),
                                      'content': contentCtrl.text.trim(),
                                      'authorId': user.uid,
                                      'authorName': authorName,
                                      'attachmentsBase64': attachments
                                          .map(
                                            (a) => {
                                              'name': a.name,
                                              'base64': a.base64,
                                              'size': a.size,
                                            },
                                          )
                                          .toList(),
                                      'imageBase64': imageBase64 ?? '',
                                      'pinned': isPinned,
                                      'targetAudience': targetAudience,
                                      'category': category,
                                      'isScheduled': isScheduled,
                                      'scheduledPublishDate': scheduledTs,
                                      'isPublished': !isScheduled,
                                      'linkedEventId': linkedEventId ?? '',
                                      'linkedProposalId':
                                          linkedProposalId ?? '',
                                      'linkedEventTitle':
                                          linkedEventTitle ?? '',
                                      'updatedAt': FieldValue.serverTimestamp(),
                                    };

                                    if (isEdit) {
                                      await FirebaseFirestore.instance
                                          .collection('announcements')
                                          .doc(existing.id)
                                          .update(data);
                                    } else {
                                      data['timestamp'] =
                                          FieldValue.serverTimestamp();
                                      await FirebaseFirestore.instance
                                          .collection('announcements')
                                          .add(data);
                                    }
                                    if (ctx.mounted) Navigator.pop(ctx);
                                    if (mounted) {
                                      _snack(
                                        isEdit
                                            ? 'Announcement updated'
                                            : isScheduled
                                            ? 'Announcement scheduled'
                                            : 'Announcement posted',
                                      );
                                    }
                                  } catch (e) {
                                    setDlg(() => isSubmitting = false);
                                    if (ctx.mounted) {
                                      ScaffoldMessenger.of(ctx).showSnackBar(
                                        SnackBar(
                                          content: Text('Error: $e'),
                                          backgroundColor: _C.error,
                                        ),
                                      );
                                    }
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _C.primaryDark,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 11,
                            ),
                          ),
                          child: isSubmitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  isEdit
                                      ? 'Save Changes'
                                      : isScheduled
                                      ? 'Schedule'
                                      : 'Share',
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
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
        },
      ),
    );
  }

  // ── Image picker ──────────────────────────────────────────────────────────
  Widget _buildImagePicker(
    String? currentBase64,
    Function(String) onSelected,
    VoidCallback onRemove,
  ) {
    if (currentBase64 != null && currentBase64.isNotEmpty) {
      return Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(_DS.radiusSm),
            child: Image.memory(
              base64Decode(currentBase64),
              width: double.infinity,
              height: 220,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                height: 220,
                color: _C.surface,
                child: const Icon(Icons.broken_image),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: InkWell(
              onTap: onRemove,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.65),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () async {
          final result = await FilePicker.platform.pickFiles(
            type: FileType.image,
            withData: true,
          );
          if (result == null) return;
          try {
            final bytes = result.files.first.bytes!;
            // Firestore caps a single document at ~1MiB and this image is
            // stored inline as base64 (which inflates raw bytes by ~33%), so
            // keep a safety margin well under that ceiling rather than let a
            // large photo fail with a raw Firestore error at write time.
            if (bytes.length > 700 * 1024) {
              _snack('Image too large! Max 700KB', isError: true);
              return;
            }
            onSelected(base64Encode(bytes));
            _snack('Image uploaded');
          } catch (e) {
            _snack('Upload failed: $e', isError: true);
          }
        },
        child: Container(
          width: double.infinity,
          height: 110,
          decoration: BoxDecoration(
            color: _C.surface,
            borderRadius: BorderRadius.circular(_DS.radiusSm),
            border: Border.all(color: _C.borderSoft),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _C.primaryDark.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.image_outlined, color: _C.primaryDark),
              ),
              const SizedBox(height: 8),
              Text(
                'Click to upload banner image',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _C.charcoal,
                ),
              ),
              Text(
                'PNG, JPG up to 700KB',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 11,
                  color: _C.textFaint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Attachments picker ────────────────────────────────────────────────────
  Widget _buildAttachmentsPicker(
    List<AttachmentBase64> attachments,
    Function(List<AttachmentBase64>) onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () async {
              final result = await FilePicker.platform.pickFiles(
                allowMultiple: true,
                withData: true,
              );
              if (result == null) return;
              try {
                final newAtts = <AttachmentBase64>[];
                // Attachments share the announcement's single Firestore doc
                // with the banner image, so cap both the count and the
                // running base64 total here — catching it during picking
                // gives the org feedback immediately instead of only at
                // submit time (see the aggregate check on the Post button).
                var totalBase64Bytes = attachments.fold<int>(
                  0,
                  (acc, a) => acc + a.base64.length,
                );
                for (final file in result.files) {
                  if (attachments.length + newAtts.length >= 5) {
                    _snack('Maximum 5 attachments allowed', isError: true);
                    break;
                  }
                  final bytes = file.bytes!;
                  if (bytes.length > 700 * 1024) {
                    _snack('${file.name} exceeds 700 KB', isError: true);
                    continue;
                  }
                  final encoded = base64Encode(bytes);
                  if (totalBase64Bytes + encoded.length > 600 * 1024) {
                    _snack(
                      '${file.name} would make attachments too large overall',
                      isError: true,
                    );
                    continue;
                  }
                  totalBase64Bytes += encoded.length;
                  newAtts.add(
                    AttachmentBase64(
                      name: file.name,
                      base64: encoded,
                      size: '${(bytes.length / 1024).toStringAsFixed(1)} KB',
                    ),
                  );
                }
                onChanged([...attachments, ...newAtts]);
                if (newAtts.isNotEmpty)
                  _snack('${newAtts.length} file(s) attached');
              } catch (e) {
                _snack('Upload failed: $e', isError: true);
              }
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: _C.surface,
                borderRadius: BorderRadius.circular(_DS.radiusSm),
                border: Border.all(color: _C.borderSoft),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.attach_file_rounded,
                    size: 22,
                    color: _C.primaryDark,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Add attachments',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _C.charcoal,
                    ),
                  ),
                  Text(
                    'PDF, DOC, DOCX, TXT, JPG, PNG — max 700 KB each',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 10,
                      color: _C.textFaint,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        ...attachments.asMap().entries.map(
          (e) => Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _C.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _C.borderSoft),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.insert_drive_file_outlined,
                  size: 18,
                  color: _C.info,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    e.value.name,
                    style: GoogleFonts.beVietnamPro(fontSize: 12),
                  ),
                ),
                if (e.value.size != null)
                  Text(
                    e.value.size!,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 10,
                      color: _C.textFaint,
                    ),
                  ),
                IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: _C.darkGray,
                  ),
                  onPressed: () => onChanged([...attachments]..removeAt(e.key)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Link-detecting content widget (used in feed and view dialog) ─────────
  Widget _buildContentWithLinks(String text) {
    final style = GoogleFonts.beVietnamPro(
      fontSize: 14,
      height: 1.65,
      color: _C.textMid,
    );
    final urlRegex = RegExp(r'(https?:\/\/[^\s]+)');
    final matches = urlRegex.allMatches(text);

    if (matches.isEmpty) {
      return Text(text, style: style);
    }

    final spans = <TextSpan>[];
    int lastEnd = 0;
    for (final match in matches) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      final url = match.group(0)!;
      spans.add(
        TextSpan(
          text: url,
          style: GoogleFonts.beVietnamPro(
            fontSize: 14,
            color: _C.info,
            decoration: TextDecoration.underline,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () async {
              final uri = Uri.tryParse(url);
              if (uri != null && await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
        ),
      );
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return RichText(
      text: TextSpan(style: style, children: spans),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Post Card — Facebook-style post
// ─────────────────────────────────────────────────────────────────────────────
class _PostCard extends StatefulWidget {
  final AnnouncementModel announcement;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTogglePin;

  const _PostCard({
    required this.announcement,
    required this.onEdit,
    required this.onDelete,
    required this.onTogglePin,
  });

  @override
  State<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<_PostCard> {
  bool _expanded = false;

  String _timeAgo(Timestamp ts) {
    final diff = DateTime.now().difference(ts.toDate());
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    return DateFormat('MMM dd, yyyy').format(ts.toDate());
  }

  Future<void> _openVideoLink(String url) async {
    final uri = Uri.tryParse(url);
    final opened = uri != null && await canLaunchUrl(uri)
        ? await launchUrl(uri, mode: LaunchMode.externalApplication)
        : false;
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open video link')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.announcement;
    // base64Decode throws synchronously for malformed data — Image.memory's
    // own errorBuilder only ever catches decode/paint failures *after* this
    // point, so a bad string here used to take the whole card down with it
    // instead of just hiding the image.
    Uint8List? imageBytes;
    if (a.imageBase64 != null && a.imageBase64!.isNotEmpty) {
      try {
        imageBytes = base64Decode(a.imageBase64!);
      } catch (_) {
        imageBytes = null;
      }
    }
    final hasImage = imageBytes != null;
    final contentLines = a.content.split('\n');
    final isLong = a.content.length > 280 || contentLines.length > 4;
    final truncated = isLong && !_expanded;

    // Use the parent's _buildContentWithLinks method – we need access to it.
    // Since _PostCard is a separate class, we can't directly call _OrgAnnouncementsScreenState's method.
    // Instead, we'll create a standalone helper function or duplicate the logic here.
    // For simplicity, we duplicate the logic inside _PostCard.
    Widget buildContent(String text) {
      final style = GoogleFonts.beVietnamPro(
        fontSize: 14,
        height: 1.65,
        color: _C.textMid,
      );
      final urlRegex = RegExp(r'(https?:\/\/[^\s]+)');
      final matches = urlRegex.allMatches(text);

      if (matches.isEmpty) {
        return Text(text, style: style);
      }

      final spans = <TextSpan>[];
      int lastEnd = 0;
      for (final match in matches) {
        if (match.start > lastEnd) {
          spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
        }
        final url = match.group(0)!;
        spans.add(
          TextSpan(
            text: url,
            style: GoogleFonts.beVietnamPro(
              fontSize: 14,
              color: _C.info,
              decoration: TextDecoration.underline,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () async {
                final uri = Uri.tryParse(url);
                if (uri != null && await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
          ),
        );
        lastEnd = match.end;
      }
      if (lastEnd < text.length) {
        spans.add(TextSpan(text: text.substring(lastEnd)));
      }

      return RichText(
        text: TextSpan(style: style, children: spans),
      );
    }

    // A BoxDecoration border can only have a borderRadius when every side is
    // the same color — mixing a category-colored left edge with a plain
    // grey/warning border on the other three sides throws
    // "A borderRadius can only be given on borders with uniform colors" at
    // paint time, which silently blanks the whole card instead of showing a
    // build-time error. The category accent is a separate Container instead,
    // clipped to match by the outer Container's own rounded corners.
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: _C.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: a.isPinned ? _C.warning.withAlpha(102) : _C.border,
          width: a.isPinned ? 1.5 : 1,
        ),
        boxShadow: _DS.postShadow,
      ),
      clipBehavior: Clip.antiAlias,
      // Stack instead of IntrinsicHeight+Row for the accent bar: IntrinsicHeight
      // computes the Column's height in a separate intrinsic-sizing pass, and
      // for a Column containing an Image.memory(fit: BoxFit.contain, cacheWidth:
      // ...) that computed height can be a pixel or two off from the height the
      // Column actually renders at (aspect-ratio rounding differs between the
      // intrinsic pass and the real layout pass), which threw a "bottom
      // overflowed by 2.0 pixels" on any post with an attached image. A
      // Positioned accent bar over a plain (non-Expanded) Column sizes exactly,
      // with no separate intrinsic measurement to drift out of sync.
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Pinned indicator strip ──────────────────────────────────────────
              if (a.isPinned)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  color: _C.warningBg,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.push_pin_rounded,
                        size: 13,
                        color: _C.warning,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Pinned Announcement',
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _C.warning,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),

              // ── Post header ─────────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Author avatar
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _C.primaryDark.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          a.authorName.isNotEmpty
                              ? a.authorName[0].toUpperCase()
                              : '?',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: _C.primaryDark,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Author info + timestamp
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            a.authorName,
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _C.charcoal,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.access_time_rounded,
                                    size: 12,
                                    color: _C.textFaint,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _timeAgo(a.timestamp),
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 11,
                                      color: _C.textFaint,
                                    ),
                                  ),
                                ],
                              ),
                              _categoryBadge(a.category),
                              _audienceBadge(a.targetAudience),
                              if (a.isScheduled && !a.isPublished)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _C.infoBg,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.schedule_rounded,
                                        size: 10,
                                        color: _C.info,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Scheduled',
                                        style: GoogleFonts.beVietnamPro(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          color: _C.info,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Actions menu
                    PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'edit') widget.onEdit();
                        if (v == 'delete') widget.onDelete();
                        if (v == 'pin') widget.onTogglePin();
                      },
                      icon: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: _C.surface,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.more_horiz_rounded,
                          size: 18,
                          color: _C.darkGray,
                        ),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 4,
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              const Icon(
                                Icons.edit_outlined,
                                size: 15,
                                color: _C.darkGray,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Edit',
                                style: GoogleFonts.beVietnamPro(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'pin',
                          child: Row(
                            children: [
                              Icon(
                                a.isPinned
                                    ? Icons.push_pin_outlined
                                    : Icons.push_pin_rounded,
                                size: 15,
                                color: _C.warning,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                a.isPinned ? 'Unpin' : 'Pin',
                                style: GoogleFonts.beVietnamPro(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              const Icon(
                                Icons.delete_outline_rounded,
                                size: 15,
                                color: _C.error,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Delete',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 13,
                                  color: _C.error,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── Title ───────────────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  a.title,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _C.charcoal,
                    height: 1.3,
                  ),
                ),
              ),

              // ── Content (with hyperlink support) ────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    buildContent(
                      truncated
                          ? '${a.content.substring(0, a.content.length.clamp(0, 280))}…'
                          : a.content,
                    ),
                    if (isLong) ...[
                      const SizedBox(height: 4),
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () => setState(() => _expanded = !_expanded),
                          child: Text(
                            _expanded ? 'See less' : 'See more',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _C.primaryDark,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // ── Linked event badge ─────────────────────────────────────────────
              if (a.linkedProposalId.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _C.infoBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _C.info.withOpacity(0.25)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.event_available_rounded,
                          size: 14,
                          color: _C.info,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Registration linked: ${a.linkedEventTitle}',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: _C.info,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // ── Banner image (shown in full, never cropped) ───────────────────────
              if (hasImage) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 480),
                  color: _C.surface,
                  child: Image.memory(
                    imageBytes,
                    width: double.infinity,
                    fit: BoxFit.contain,
                    // Decodes at a feed-card-sized resolution instead of
                    // whatever the org originally uploaded — see
                    // org_merchandise.dart's identical fix for why this matters
                    // for a repeating list of cards.
                    cacheWidth: 960,
                    errorBuilder: (_, __, ___) => Container(
                      height: 280,
                      color: _C.surface,
                      child: const Icon(
                        Icons.broken_image,
                        color: _C.textFaint,
                      ),
                    ),
                  ),
                ),
              ],

              // ── Linked video ───────────────────────────────────────────────────────
              if (a.videoUrl.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: InkWell(
                    onTap: () => _openVideoLink(a.videoUrl),
                    borderRadius: BorderRadius.circular(_DS.radiusSm),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: _C.errorBg,
                        borderRadius: BorderRadius.circular(_DS.radiusSm),
                        border: Border.all(color: _C.error.withAlpha(64)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: _C.error.withAlpha(38),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: _C.error,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Watch Video',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _C.error,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.open_in_new_rounded,
                            size: 15,
                            color: _C.error,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],

              // ── Attachments ──────────────────────────────────────────────────────
              if (a.attachmentsBase64.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.attach_file_rounded,
                            size: 14,
                            color: _C.darkGray,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${a.attachmentsBase64.length} attachment${a.attachmentsBase64.length > 1 ? 's' : ''}',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _C.darkGray,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...a.attachmentsBase64.map(
                        (att) => Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: _C.infoBg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: _C.info.withOpacity(0.2)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.insert_drive_file_outlined,
                                size: 16,
                                color: _C.info,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  att.name,
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: _C.info,
                                  ),
                                ),
                              ),
                              if (att.size != null)
                                Text(
                                  att.size!,
                                  style: GoogleFonts.beVietnamPro(
                                    fontSize: 10,
                                    color: _C.textFaint,
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

              // ── Footer divider + meta ─────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_rounded,
                      size: 12,
                      color: _C.textFaint,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      DateFormat(
                        'MMMM dd, yyyy • h:mm a',
                      ).format(a.timestamp.toDate()),
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 11,
                        color: _C.textFaint,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(width: 4, color: _categoryTheme(a.category).fg),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pagination helpers
// ─────────────────────────────────────────────────────────────────────────────
class _PageBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  const _PageBtn({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          icon,
          size: 20,
          color: enabled ? _C.textMid : const Color(0xFFD1D5DB),
        ),
      ),
    );
  }
}

class _PageNumBtn extends StatelessWidget {
  final int page;
  final bool isActive;
  final VoidCallback onTap;
  const _PageNumBtn({
    required this.page,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? _C.primaryDark : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '$page',
            style: GoogleFonts.beVietnamPro(
              fontSize: 12,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.normal,
              color: isActive ? Colors.white : _C.textMid,
            ),
          ),
        ),
      ),
    );
  }
}

// Test-only hook so test/org_announcements_postcard_test.dart can construct
// the private _PostCard from outside this file — that test is a regression
// guard for a real bug (see its file header) that a normal build couldn't
// catch, since flutter analyze doesn't run widgets through a paint pass.
@visibleForTesting
Widget debugPostCardForTest(AnnouncementModel a) {
  return _PostCard(
    announcement: a,
    onEdit: () {},
    onDelete: () {},
    onTogglePin: () {},
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Models — identical to original (full Firestore compatibility)
// ─────────────────────────────────────────────────────────────────────────────
class AttachmentBase64 {
  final String name;
  final String base64;
  final String? size;
  const AttachmentBase64({required this.name, required this.base64, this.size});
}

class AnnouncementModel {
  final String id, title, content, authorId, authorName;
  final Timestamp timestamp;
  final List<AttachmentBase64> attachmentsBase64;
  final String? imageBase64;
  final bool isPinned;
  final String targetAudience;
  final String category;
  final bool isScheduled;
  final Timestamp? scheduledPublishDate;
  final bool isPublished;
  final String linkedEventId;
  final String linkedProposalId;
  final String linkedEventTitle;
  final String videoUrl;

  const AnnouncementModel({
    required this.id,
    required this.title,
    required this.content,
    required this.authorId,
    required this.authorName,
    required this.timestamp,
    required this.attachmentsBase64,
    this.imageBase64,
    this.isPinned = false,
    this.targetAudience = 'Members Only',
    this.category = 'General',
    this.isScheduled = false,
    this.scheduledPublishDate,
    this.isPublished = true,
    this.linkedEventId = '',
    this.linkedProposalId = '',
    this.linkedEventTitle = '',
    this.videoUrl = '',
  });

  factory AnnouncementModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    List<AttachmentBase64> attachments = [];
    final attsList = d['attachmentsBase64'] as List?;
    if (attsList != null) {
      attachments = attsList
          .map(
            (a) => AttachmentBase64(
              name: a['name'] ?? '',
              base64: a['base64'] ?? '',
              size: a['size'],
            ),
          )
          .toList();
    }
    return AnnouncementModel(
      id: doc.id,
      title: d['title'] ?? '',
      content: d['content'] ?? '',
      authorId: d['authorId'] ?? '',
      authorName: d['authorName'] ?? 'Unknown',
      timestamp: d['timestamp'] as Timestamp? ?? Timestamp.now(),
      attachmentsBase64: attachments,
      imageBase64: d['imageBase64'] as String?,
      isPinned: d['pinned'] as bool? ?? false,
      targetAudience: d['targetAudience'] as String? ?? 'Members Only',
      category: d['category'] as String? ?? 'General',
      isScheduled: d['isScheduled'] as bool? ?? false,
      scheduledPublishDate: d['scheduledPublishDate'] as Timestamp?,
      isPublished: d['isPublished'] as bool? ?? true,
      linkedEventId: d['linkedEventId'] as String? ?? '',
      linkedProposalId: d['linkedProposalId'] as String? ?? '',
      linkedEventTitle: d['linkedEventTitle'] as String? ?? '',
      videoUrl: d['videoUrl'] as String? ?? '',
    );
  }
}

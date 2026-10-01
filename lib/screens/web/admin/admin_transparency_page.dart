import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../utils/platform_file_utils.dart' as file_utils;
import '../landing/landing_common.dart';
import '../landing/landing_palette.dart';
import 'admin_site_chrome.dart';

/// Public directory of reports submitted by recognized organizations.
/// Reports are created with a pending status and have no separate public
/// approval flow, so this page labels them as submissions.
class AdminTransparencyPage extends StatefulWidget {
  final VoidCallback onBack;
  final VoidCallback onTerms;
  final ValueChanged<AdminSiteSection> onSelect;

  const AdminTransparencyPage({super.key, required this.onBack, required this.onTerms, required this.onSelect});

  @override
  State<AdminTransparencyPage> createState() => _AdminTransparencyPageState();
}

class _AdminTransparencyPageState extends State<AdminTransparencyPage> {
  static const _blue = Color(0xFF2563EB);
  static const _palette = LandingPalette.admin;
  String? _selectedOrgId;
  Map<String, dynamic>? _selectedOrg;
  Future<List<Map<String, dynamic>>>? _finishedEventsFuture;
  Set<String> _eventSchoolYears = {};
  final _orgSearchController = TextEditingController();
  final _reportSearchController = TextEditingController();
  String _reportTypeFilter = 'All reports';
  String _schoolYearFilter = 'All school years';

  @override
  void dispose() {
    _orgSearchController.dispose();
    _reportSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedOrg;
    return Container(
      color: Colors.white,
      child: Stack(children: [
        const Positioned.fill(child: DotGridBackground()),
        ListView(children: [
          LandingContainer(
            padding: const EdgeInsets.only(top: 48, bottom: 68),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextButton.icon(
                onPressed: _selectedOrgId == null
                    ? widget.onBack
                    : () => setState(() {
                        _selectedOrgId = null;
                        _selectedOrg = null;
                        _finishedEventsFuture = null;
                        _eventSchoolYears = {};
                        _reportSearchController.clear();
                        _reportTypeFilter = 'All reports';
                        _schoolYearFilter = 'All school years';
                      }),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: Text(_selectedOrgId == null ? 'Back to home' : 'All organizations'),
              ),
              const SizedBox(height: 24),
              if (selected == null) ...[
                const SectionHeader(
                  palette: _palette,
                  eyebrow: 'PUBLIC INFORMATION',
                  title: 'Transparency',
                  subtitle: 'Explore the accomplishments and financial reports CICT organizations have submitted through UPRISE.',
                ),
                const SizedBox(height: 38),
                _searchField(
                  controller: _orgSearchController,
                  hint: 'Search organizations by name or abbreviation',
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 18),
                _organizationList(),
              ] else ...[
                _organizationProfile(selected),
                const SizedBox(height: 28),
                _reportFilters(),
                const SizedBox(height: 16),
                _reportList(),
              ],
            ]),
          ),
          AdminSiteFooter(onSelect: widget.onSelect, onTerms: widget.onTerms),
        ]),
      ]),
    );
  }

  Widget _organizationList() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.collection('organizations').snapshots(),
    builder: (context, snapshot) {
      if (snapshot.hasError) return _message('Organizations could not be loaded.');
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final orgs = snapshot.data!.docs.where((doc) {
        final data = doc.data();
        final name = _orgName(data);
        final abbrev = (data['shortName'] ?? '').toString();
        final query = _orgSearchController.text.trim().toLowerCase();
        return name.trim().isNotEmpty &&
            (query.isEmpty || '$name $abbrev'.toLowerCase().contains(query));
      }).toList()
        ..sort((a, b) => _orgName(a.data()).compareTo(_orgName(b.data())));
      if (orgs.isEmpty) {
        return _message(_orgSearchController.text.trim().isEmpty
            ? 'No organizations are listed yet.'
            : 'No organizations match your search.');
      }
      return LayoutBuilder(builder: (context, constraints) {
        final columns = constraints.maxWidth >= 850 ? 3 : constraints.maxWidth >= 560 ? 2 : 1;
        final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [for (final org in orgs)
            SizedBox(width: width, child: _orgCard(org.id, org.data()))],
        );
      });
    },
  );

  Widget _orgCard(String id, Map<String, dynamic> data) {
    final name = _orgName(data);
    final abbrev = (data['shortName'] ?? '').toString();
    final shortName = abbrev.trim();
    final initials = shortName.isNotEmpty
        ? shortName[0].toUpperCase()
        : name.trim().isEmpty
        ? 'O'
        : name.trim()[0].toUpperCase();
    return InkWell(
      onTap: () => setState(() {
        _selectedOrgId = id;
        _selectedOrg = data;
        _eventSchoolYears = {};
        _finishedEventsFuture = _loadFinishedEvents(id);
        _finishedEventsFuture!.then((events) {
          if (!mounted || _selectedOrgId != id) return;
          setState(() => _eventSchoolYears = {
            for (final event in events)
              if ((event['schoolYear'] ?? '').toString().trim().isNotEmpty)
                event['schoolYear'].toString(),
          });
        });
      }),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0))),
        child: Row(children: [
          _logo(data['logoUrl']?.toString() ?? '', 48, initials),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w700, fontSize: 15)),
            if (abbrev.isNotEmpty) Text(abbrev, style: GoogleFonts.beVietnamPro(fontSize: 12, color: const Color(0xFF64748B))),
          ])),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFF64748B)),
        ]),
      ),
    );
  }

  String _orgName(Map<String, dynamic> data) =>
      (data['orgName'] ?? data['name'] ?? data['shortName'] ?? 'Organization').toString();

  Widget _logo(String value, double size, String initials) {
    if (value.isEmpty) return _logoFallback(size, initials);
    if (value.startsWith('data:')) {
      try {
        return ClipOval(child: Image.memory(base64Decode(value.split(',').last), width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _logoFallback(size, initials)));
      } catch (_) {
        return _logoFallback(size, initials);
      }
    }
    return ClipOval(child: Image.network(value, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _logoFallback(size, initials)));
  }

  Widget _logoFallback(double size, String initials) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: _palette.tint, shape: BoxShape.circle),
    child: Text(initials, style: TextStyle(color: _blue, fontSize: size * .36, fontWeight: FontWeight.w700)),
  );

  Widget _organizationProfile(Map<String, dynamic> data) {
    final name = _orgName(data);
    final shortName = (data['shortName'] ?? '').toString().trim();
    final initials = (shortName.isNotEmpty ? shortName : name).trim();
    final about = (data['description'] ?? '').toString().trim();
    final cover = (data['coverPhotoUrl'] ?? '').toString();
    Widget? coverWidget;
    if (cover.startsWith('data:')) {
      try {
        coverWidget = Image.memory(base64Decode(cover.split(',').last), height: 150, width: double.infinity, fit: BoxFit.cover);
      } catch (_) {}
    } else if (cover.isNotEmpty) {
      coverWidget = Image.network(cover, height: 150, width: double.infinity, fit: BoxFit.cover);
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: AdminSiteColors.border), boxShadow: const [BoxShadow(color: Color(0x0A0F172A), blurRadius: 20, offset: Offset(0, 8))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (coverWidget != null) ClipRRect(borderRadius: BorderRadius.circular(12), child: coverWidget),
        if (coverWidget != null) const SizedBox(height: 20),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          _logo((data['logoUrl'] ?? '').toString(), 82, initials.isEmpty ? '?' : initials[0].toUpperCase()),
          const SizedBox(width: 18),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (shortName.isNotEmpty) Text(shortName.toUpperCase(), style: GoogleFonts.beVietnamPro(fontSize: 11, color: _blue, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
            Text(name, style: GoogleFonts.beVietnamPro(fontSize: 25, color: _palette.ink, fontWeight: FontWeight.w800)),
            if (about.isNotEmpty) ...[const SizedBox(height: 8), Text(about, style: GoogleFonts.beVietnamPro(fontSize: 13, height: 1.6, color: _palette.inkSoft))],
          ])),
        ]),
      ]),
    );
  }

  Widget _searchField({
    required TextEditingController controller,
    required String hint,
    required ValueChanged<String> onChanged,
  }) => TextField(
    controller: controller,
    onChanged: onChanged,
    decoration: InputDecoration(
      hintText: hint,
      prefixIcon: const Icon(Icons.search_rounded, color: _blue),
      suffixIcon: controller.text.isEmpty
          ? null
          : IconButton(
              tooltip: 'Clear search',
              icon: const Icon(Icons.close_rounded),
              onPressed: () {
                controller.clear();
                onChanged('');
              },
            ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AdminSiteColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AdminSiteColors.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _blue, width: 1.5)),
    ),
  );

  Widget _reportFilters() => LayoutBuilder(builder: (context, constraints) {
    final years = <String>{'All school years'};
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('reports').where('orgId', isEqualTo: _selectedOrgId).snapshots(),
      builder: (context, snapshot) {
        for (final doc in snapshot.data?.docs ?? []) {
          final year = doc.data()['schoolYear']?.toString().trim() ?? '';
          if (year.isNotEmpty) years.add(year);
        }
        years.addAll(_eventSchoolYears);
        final choices = years.toList()..sort((a, b) => a == 'All school years' ? -1 : b == 'All school years' ? 1 : b.compareTo(a));
        final wide = constraints.maxWidth >= 700;
        final search = _searchField(
          controller: _reportSearchController,
          hint: 'Search report titles or file names',
          onChanged: (_) => setState(() {}),
        );
        final type = DropdownButtonFormField<String>(
          value: _reportTypeFilter,
          decoration: _filterDecoration('Report type'),
          items: const [
            DropdownMenuItem(value: 'All reports', child: Text('All report types')),
            DropdownMenuItem(value: 'accomplishment', child: Text('Accomplishment')),
            DropdownMenuItem(value: 'financial', child: Text('Financial')),
          ],
          onChanged: (value) => setState(() => _reportTypeFilter = value ?? 'All reports'),
        );
        final year = DropdownButtonFormField<String>(
          value: choices.contains(_schoolYearFilter) ? _schoolYearFilter : 'All school years',
          decoration: _filterDecoration('School year'),
          items: [for (final value in choices) DropdownMenuItem(value: value, child: Text(value))],
          onChanged: (value) => setState(() => _schoolYearFilter = value ?? 'All school years'),
        );
        if (wide) {
          return Row(children: [Expanded(flex: 3, child: search), const SizedBox(width: 12), Expanded(child: type), const SizedBox(width: 12), Expanded(child: year)]);
        }
        return Column(children: [search, const SizedBox(height: 10), Row(children: [Expanded(child: type), const SizedBox(width: 10), Expanded(child: year)])]);
      },
    );
  });

  InputDecoration _filterDecoration(String label) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AdminSiteColors.border)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AdminSiteColors.border)),
  );

  Widget _reportList() => FutureBuilder<List<Map<String, dynamic>>>(
    future: _finishedEventsFuture,
    builder: (context, eventSnapshot) {
      if (eventSnapshot.hasError) return _message('Reporting periods could not be loaded.');
      if (!eventSnapshot.hasData) return const Center(child: CircularProgressIndicator());
      return _reportStream(eventSnapshot.data!);
    },
  );

  Future<List<Map<String, dynamic>>> _loadFinishedEvents(String orgId) async {
    final snap = await FirebaseFirestore.instance
        .collection('events')
        .where('status', isEqualTo: 'approved')
        .get();
    final now = DateTime.now();
    return snap.docs.where((doc) {
      final data = doc.data();
      final date = data['date'];
      return data['orgId']?.toString() == orgId &&
          date is Timestamp && date.toDate().isBefore(now);
    }).map((doc) {
      final data = doc.data();
      return {
        'eventId': doc.id,
        'title': data['title']?.toString() ?? 'Untitled event',
        'schoolYear': data['schoolYear']?.toString() ?? '',
      };
    }).toList();
  }

  Widget _reportStream(List<Map<String, dynamic>> expectedEvents) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.collection('reports').where('orgId', isEqualTo: _selectedOrgId).snapshots(),
    builder: (context, snapshot) {
      if (snapshot.hasError) return _message('Reports could not be loaded.');
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final docs = snapshot.data!.docs.toList()..sort((a, b) {
        final ta = a.data()['submittedAt']; final tb = b.data()['submittedAt'];
        final da = ta is Timestamp ? ta.toDate() : DateTime(1970);
        final db = tb is Timestamp ? tb.toDate() : DateTime(1970);
        return db.compareTo(da);
      });
      final accomplishments = docs.where((d) => d.data()['type'] == 'accomplishment').toList();
      final financial = docs.where((d) => d.data()['type'] == 'financial').toList();
      final filteredAccomplishments = _filterReports(accomplishments, expectedEvents);
      final filteredFinancial = _filterReports(financial, expectedEvents);
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_reportTypeFilter != 'financial')
          _section('Accomplishment Reports', Icons.emoji_events_outlined, filteredAccomplishments, expectedEvents, accomplishments),
        if (_reportTypeFilter == 'All reports') const SizedBox(height: 30),
        if (_reportTypeFilter != 'accomplishment')
          _section('Financial Reports', Icons.account_balance_wallet_outlined, filteredFinancial, expectedEvents, financial),
      ]);
    },
  );

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterReports(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> reports,
    List<Map<String, dynamic>> expectedEvents,
  ) {
    final query = _reportSearchController.text.trim().toLowerCase();
    final eventsById = {
      for (final event in expectedEvents) event['eventId']: event,
    };
    return reports.where((doc) {
      final data = doc.data();
      final scope = (data['scope'] ?? 'event').toString();
      final event = eventsById[data['eventId']];
      final year = scope == 'event'
          ? (event?['schoolYear'] ?? '').toString()
          : (data['schoolYear'] ?? '').toString();
      final matchesYear = _schoolYearFilter == 'All school years' || year == _schoolYearFilter;
      final matchesQuery = query.isEmpty ||
          '${data['title'] ?? ''} ${data['fileName'] ?? ''} ${data['semester'] ?? ''}'
              .toLowerCase()
              .contains(query);
      return matchesYear && matchesQuery;
    }).toList();
  }

  Widget _section(
    String title,
    IconData icon,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    List<Map<String, dynamic>> expectedEvents,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> allSubmitted,
  ) {
    final type = title.startsWith('Financial') ? 'financial' : 'accomplishment';
    final submittedEventIds = allSubmitted
        .where((doc) => (doc.data()['scope'] ?? 'event') == 'event')
        .map((doc) => doc.data()['eventId']?.toString())
        .whereType<String>()
        .toSet();
    final query = _reportSearchController.text.trim().toLowerCase();
    final missingEvents = expectedEvents.where((event) {
      final year = (event['schoolYear'] ?? '').toString();
      final matchesYear = _schoolYearFilter == 'All school years' || year == _schoolYearFilter;
      final matchesSearch = query.isEmpty || (event['title'] ?? '').toString().toLowerCase().contains(query);
      return !submittedEventIds.contains(event['eventId']) && matchesYear && matchesSearch;
    }).toList();
    return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [Icon(icon, color: _blue), const SizedBox(width: 10), Text(title, style: GoogleFonts.beVietnamPro(fontSize: 19, fontWeight: FontWeight.w700))]),
      const SizedBox(height: 12),
      if (docs.isEmpty && missingEvents.isEmpty)
        _message(allSubmitted.isEmpty && expectedEvents.isEmpty
            ? 'No reports have been submitted yet.'
            : 'No reports match the selected filters.')
      else ...docs.map(_reportCard),
      if (missingEvents.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 10),
          child: Text('No $type report submitted for these completed events', style: GoogleFonts.beVietnamPro(fontSize: 12, color: _palette.inkSoft, fontWeight: FontWeight.w600)),
        ),
        ...missingEvents.map((event) => _missingReportCard(event['title']?.toString() ?? 'Completed event')),
      ],
    ],
  );
  }

  Widget _missingReportCard(String eventTitle) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFFDE68A))),
    child: Row(children: [
      const Icon(Icons.schedule_rounded, color: Color(0xFFB45309)),
      const SizedBox(width: 12),
      Expanded(child: Text(eventTitle, style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w600, color: _palette.ink))),
      const SizedBox(width: 8),
      Text('Not submitted', style: GoogleFonts.beVietnamPro(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF92400E))),
    ]),
  );

  Widget _reportCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final title = (d['title'] ?? d['schoolYear'] ?? 'Organization report').toString();
    final fileName = (d['fileName'] ?? 'Report file').toString();
    final submitted = d['submittedAt'];
    final date = submitted is Timestamp ? DateFormat('MMM d, yyyy').format(submitted.toDate()) : 'Date unavailable';
    final scope = (d['scope'] ?? 'event').toString();
    final period = scope == 'semester' ? '${d['semester'] ?? ''} ${d['schoolYear'] ?? ''}' : scope == 'year' ? '${d['schoolYear'] ?? ''} (whole year)' : 'Event report';
    final encoded = d['fileBase64']?.toString() ?? '';
    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxWidth < 600;
      final details = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('$period  ·  Submitted $date  ·  $fileName', style: GoogleFonts.beVietnamPro(fontSize: 12, color: const Color(0xFF64748B))),
      ]);
      final button = OutlinedButton.icon(
        onPressed: encoded.isEmpty ? null : () => _openFile(encoded, fileName),
        icon: const Icon(Icons.open_in_new_rounded, size: 16),
        label: const Text('Open report'),
      );
      return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: compact
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [details, const SizedBox(height: 12), button])
          : Row(children: [const Icon(Icons.description_outlined, color: _blue), const SizedBox(width: 14), Expanded(child: details), const SizedBox(width: 12), button]),
      );
    });
  }

  Future<void> _openFile(String encoded, String fileName) async {
    try {
      final bytes = Uint8List.fromList(base64Decode(encoded));
      final lower = fileName.toLowerCase();
      final mime = lower.endsWith('.pdf') ? 'application/pdf' : lower.endsWith('.png') ? 'image/png' : lower.endsWith('.jpg') || lower.endsWith('.jpeg') ? 'image/jpeg' : 'application/octet-stream';
      await file_utils.saveBytesToTempAndOpen(bytes, fileName, mimeType: mime);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open this report file.')));
    }
  }

  Widget _message(String text) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE2E8F0))),
    child: Text(text, style: GoogleFonts.beVietnamPro(color: const Color(0xFF64748B))),
  );
}

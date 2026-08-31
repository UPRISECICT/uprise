// lib/widgets/common/announcement_filter_bar.dart
//
// Search + Organization + Category filtering for the announcement feeds,
// shared by the student and guest screens so the two can't drift.
//
// Filtering is client-side over documents the screen has already streamed —
// the same approach org_announcements.dart's _filtered() takes on the web. A
// server-side `where` on orgId or category combined with the existing
// orderBy/audience clauses would need new composite indexes, and this app has
// been bitten before by a query silently returning nothing when one wasn't
// provisioned.

import 'package:flutter/material.dart';

import '../student/app_colors.dart';

/// Sentinel for "don't filter on this field". Not a valid orgId or category.
const String kAnnouncementFilterAll = '__all__';

/// The three filter values, plus the predicate that applies them.
///
/// Operates on the raw Firestore map rather than a parsed model because the
/// two screens parse announcements differently — the student side builds an
/// `AnnouncementData`, the guest side reads fields inline.
class AnnouncementFilters {
  final String query;
  final String orgId;
  final String category;

  const AnnouncementFilters({
    this.query = '',
    this.orgId = kAnnouncementFilterAll,
    this.category = kAnnouncementFilterAll,
  });

  bool get isActive =>
      query.trim().isNotEmpty ||
      orgId != kAnnouncementFilterAll ||
      category != kAnnouncementFilterAll;

  AnnouncementFilters copyWith({
    String? query,
    String? orgId,
    String? category,
  }) => AnnouncementFilters(
    query: query ?? this.query,
    orgId: orgId ?? this.orgId,
    category: category ?? this.category,
  );

  bool matches(Map<String, dynamic> data) {
    if (orgId != kAnnouncementFilterAll &&
        (data['orgId'] ?? '').toString() != orgId) {
      return false;
    }
    if (category != kAnnouncementFilterAll &&
        (data['category'] ?? '').toString().trim() != category) {
      return false;
    }
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      final title = (data['title'] ?? '').toString().toLowerCase();
      final content = (data['content'] ?? '').toString().toLowerCase();
      if (!title.contains(q) && !content.contains(q)) return false;
    }
    return true;
  }
}

/// Organizations to offer, as `orgId -> display name`, derived from the posts
/// themselves.
///
/// Reading the docs rather than the `organizations` collection keeps one source
/// of truth and guarantees every option actually has posts behind it — an org
/// that has never posted would otherwise sit in the dropdown leading to an
/// empty list. Announcements carry the org's display name in `authorName`;
/// there is no `orgName` field on them.
Map<String, String> announcementOrgOptions(List<Map<String, dynamic>> docs) {
  final out = <String, String>{};
  for (final d in docs) {
    final id = (d['orgId'] ?? '').toString();
    if (id.isEmpty) continue;
    final name = (d['authorName'] ?? '').toString().trim();
    out[id] = name.isEmpty ? 'Organization' : name;
  }
  final entries = out.entries.toList()
    ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
  return Map.fromEntries(entries);
}

/// Categories to offer, derived from the posts themselves.
///
/// Deliberately not a fixed list: `kDefaultAnnouncementCategories` in
/// org_announcements.dart is empty, and orgs define their own categories at
/// post time, so any hardcoded set here would go stale immediately.
List<String> announcementCategoryOptions(List<Map<String, dynamic>> docs) {
  final out = <String>{};
  for (final d in docs) {
    final c = (d['category'] ?? '').toString().trim();
    if (c.isNotEmpty) out.add(c);
  }
  final list = out.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return list;
}

class AnnouncementFilterBar extends StatelessWidget {
  final AnnouncementFilters filters;
  final ValueChanged<AnnouncementFilters> onChanged;

  /// `orgId -> display name`, from [announcementOrgOptions].
  final Map<String, String> orgOptions;

  /// From [announcementCategoryOptions].
  final List<String> categoryOptions;

  /// How many posts survive the current filters — shown only while a filter is
  /// active, so the bar stays quiet on an unfiltered feed.
  final int? resultCount;

  const AnnouncementFilterBar({
    super.key,
    required this.filters,
    required this.onChanged,
    required this.orgOptions,
    required this.categoryOptions,
    this.resultCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            initialValue: filters.query,
            onChanged: (v) => onChanged(filters.copyWith(query: v)),
            decoration: InputDecoration(
              hintText: 'Search announcements',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              filled: true,
              fillColor: const Color(0xFFF5F6F8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _dropdown(
                  icon: Icons.apartment_rounded,
                  value: filters.orgId,
                  allLabel: 'All organizations',
                  entries: orgOptions.entries
                      .map((e) => MapEntry(e.key, e.value))
                      .toList(),
                  onChanged: (v) => onChanged(
                    filters.copyWith(orgId: v ?? kAnnouncementFilterAll),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _dropdown(
                  icon: Icons.label_outline_rounded,
                  value: filters.category,
                  allLabel: 'All categories',
                  entries: categoryOptions.map((c) => MapEntry(c, c)).toList(),
                  onChanged: (v) => onChanged(
                    filters.copyWith(category: v ?? kAnnouncementFilterAll),
                  ),
                ),
              ),
            ],
          ),
          if (filters.isActive && resultCount != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  resultCount == 1 ? '1 result' : '$resultCount results',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => onChanged(const AnnouncementFilters()),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primaryDark,
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Clear filters',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _dropdown({
    required IconData icon,
    required String value,
    required String allLabel,
    required List<MapEntry<String, String>> entries,
    required ValueChanged<String?> onChanged,
  }) {
    // A value that isn't in the list throws in DropdownButton — that happens
    // when the only post from the selected org (or in the selected category)
    // is edited away while the filter is applied.
    final safeValue = value == kAnnouncementFilterAll
        ? kAnnouncementFilterAll
        : (entries.any((e) => e.key == value) ? value : kAnnouncementFilterAll);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6F8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: safeValue,
          isExpanded: true,
          isDense: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          borderRadius: BorderRadius.circular(12),
          style: const TextStyle(fontSize: 13, color: Colors.black87),
          onChanged: onChanged,
          items: [
            DropdownMenuItem(
              value: kAnnouncementFilterAll,
              child: _row(icon, allLabel, muted: true),
            ),
            for (final e in entries)
              DropdownMenuItem(value: e.key, child: _row(icon, e.value)),
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String label, {bool muted = false}) => Row(
    children: [
      Icon(
        icon,
        size: 15,
        color: muted ? Colors.grey.shade500 : AppColors.primaryDark,
      ),
      const SizedBox(width: 7),
      Expanded(
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            color: muted ? Colors.grey.shade600 : Colors.black87,
          ),
        ),
      ),
    ],
  );
}

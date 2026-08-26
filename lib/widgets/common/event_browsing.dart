// lib/widgets/common/event_browsing.dart
//
// The chrome around a list of event cards.
//
// A browse tab is more than its cards: a search field, an organization filter,
// a row of time-status chips, a grid/list toggle, the category tiles it lands
// on before anything is filtered, and the results surface itself. All of that
// grew inside student_events_screen.dart as private widgets — _FilterChips,
// _OrgFilterDropdown, _ViewToggleRow, _buildCategoryGrid, _EventResultsList.
//
// Guest's Discover tab had a parallel, thinner set: a plain search box over a
// row of category chips over a flat list of dark photo-scrim cards. Pulling the
// student version out here is what lets both browse tabs be the same surface
// without guest importing student's Firestore-bound tab widgets.
//
// Presentation-only, in the same spirit as event_card.dart: nothing here knows
// about EventModel or FirestoreEvent. Each side filters and sorts its own
// domain objects, then maps every one it wants shown to an [EventListItem].

import 'package:flutter/material.dart';

import '../student/app_colors.dart';
import 'empty_state.dart';
import 'event_card.dart';
import 'feed_cards.dart' show feedCategoryColor, feedCategoryIcon;

/// The categories a browse tab lands on.
///
/// Must stay in sync with the org-facing category picker
/// (org_event_proposals.dart's `_categories`), since that is what actually gets
/// written to each event's `category` field. An event filed under something
/// outside this list is still reachable through search, org and status — it
/// just has no tile of its own.
const kEventCategories = <String>[
  'Workshop',
  'Seminar',
  'Competition',
  'General Assembly',
  'Social',
  'Outreach',
  'Sports',
  'Academic',
  'Technical',
  'Cultural',
  'Other',
];

/// The search box that sits above a browse tab.
///
/// The controller and the current [query] both live with the caller: the
/// caller already holds the query as filter state, and passing it back in is
/// what decides whether the clear button renders, without this widget having
/// to listen to its own controller.
class EventSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String query;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const EventSearchField({
    super.key,
    required this.controller,
    required this.query,
    required this.hintText,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 13.5),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: query.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: onClear,
              ),
        isDense: true,
        filled: true,
        fillColor: Colors.grey.shade100,
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

/// Compact single-select chips — time status on Discover, view filter on My
/// Events. `onTap` fires with the tapped value; the caller decides whether that
/// selects it or clears an already-active one.
///
/// `dotValue`, when given, draws a small status dot on that one chip.
class FilterChips<T> extends StatelessWidget {
  final List<(T, String)> options;
  final T? selected;
  final ValueChanged<T> onTap;
  final T? dotValue;

  const FilterChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onTap,
    this.dotValue,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final opt in options) ...[
          _buildChip(opt.$1, opt.$2),
          if (opt != options.last) const SizedBox(width: 6),
        ],
      ],
    );
  }

  Widget _buildChip(T value, String label) {
    final hasDot = dotValue != null && value == dotValue;
    final isSelected = selected == value;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryDark : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasDot) ...[
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : Colors.green,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isSelected ? Colors.white : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One entry in [OrgFilterDropdown].
///
/// A plain pair rather than a Firestore document, because the two callers do
/// not source it the same way: student reads the `organizations` collection,
/// guest derives it from the events already in memory.
class OrgOption {
  final String id;
  final String name;

  const OrgOption({required this.id, required this.name});
}

/// Organization filter for a browse tab. A null selection means "All".
///
/// [selectedOrgId] is matched against [orgs] rather than trusted: a dropdown
/// whose value has no matching item asserts, and the guest list can shrink
/// under the selection when the events backing an org stop being visible.
class OrgFilterDropdown extends StatelessWidget {
  final List<OrgOption> orgs;
  final String? selectedOrgId;
  final ValueChanged<String?> onChanged;

  const OrgFilterDropdown({
    super.key,
    required this.orgs,
    required this.selectedOrgId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final value = orgs.any((o) => o.id == selectedOrgId) ? selectedOrgId : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: value,
          isExpanded: true,
          icon: const Icon(Icons.expand_more, size: 20),
          style: const TextStyle(fontSize: 13, color: Colors.black87),
          hint: Text(
            'All Organizations',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('All Organizations'),
            ),
            for (final org in orgs)
              DropdownMenuItem<String?>(
                value: org.id,
                child: Text(org.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// Grid/list switch, right-aligned above a results list.
class ViewToggleRow extends StatelessWidget {
  final bool compact;
  final ValueChanged<bool> onChanged;

  const ViewToggleRow({
    super.key,
    required this.compact,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          IconButton(
            icon: Icon(
              compact ? Icons.view_list_rounded : Icons.grid_view_rounded,
              color: AppColors.primaryDark,
            ),
            tooltip: compact ? 'Switch to list view' : 'Switch to grid view',
            onPressed: () => onChanged(!compact),
          ),
        ],
      ),
    );
  }
}

/// The landing grid of category tiles.
///
/// Colours and icons come from feed_cards.dart's shared per-category map, so a
/// tile matches the badge on the cards it leads to and the category colour
/// already used on Home's event feed.
class CategoryTileGrid extends StatelessWidget {
  final List<String> categories;
  final ValueChanged<String> onTap;
  final EdgeInsets padding;

  const CategoryTileGrid({
    super.key,
    required this.onTap,
    this.categories = kEventCategories,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 16),
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: padding,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.1,
      ),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final category = categories[index];
        final color = feedCategoryColor(category);
        return GestureDetector(
          onTap: () => onTap(category),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color, Color.lerp(color, Colors.black, 0.35)!],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(23),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Positioned(
                  right: -8,
                  bottom: -8,
                  child: Icon(
                    feedCategoryIcon(category),
                    size: 84,
                    color: Colors.white.withAlpha(46),
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: Text(
                    category,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One row of [EventResultsList] — a card's content plus what to do on tap.
class EventListItem {
  final EventCardData data;
  final VoidCallback onTap;
  final bool isRegistered;
  final bool showLiveBadge;
  final bool showSoonBadge;

  /// Pinned to the bottom of the full card's banner. The student side passes
  /// its webinar code banner for a live event it holds a registration for;
  /// anything Firestore-backed stays out of the card and arrives through here.
  final Widget? bannerOverlay;

  const EventListItem({
    required this.data,
    required this.onTap,
    this.isRegistered = false,
    this.showLiveBadge = false,
    this.showSoonBadge = false,
    this.bannerOverlay,
  });
}

/// The results surface: full cards in a list, or compact cards in a two-column
/// grid, or the empty state when nothing survived the filters.
///
/// The grid's `childAspectRatio` is what gives [CompactEventCard] the bounded
/// height it needs — its content column ends in a Spacer.
class EventResultsList extends StatelessWidget {
  final List<EventListItem> items;
  final bool compact;

  /// Bold line for the empty state — what isn't here.
  final String emptyTitle;

  /// Optional quieter second line — what to do about it.
  final String? emptyMessage;

  final IconData emptyIcon;

  const EventResultsList({
    super.key,
    required this.items,
    required this.compact,
    required this.emptyTitle,
    this.emptyMessage,
    this.emptyIcon = Icons.event_busy,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return EmptyStateView(
        icon: emptyIcon,
        title: emptyTitle,
        message: emptyMessage,
      );
    }

    if (compact) {
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.72,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return CompactEventCard(
            data: item.data,
            isRegistered: item.isRegistered,
            showLiveBadge: item.showLiveBadge,
            onTap: item.onTap,
          );
        },
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: EventCard(
            data: item.data,
            isRegistered: item.isRegistered,
            showLiveBadge: item.showLiveBadge,
            showSoonBadge: item.showSoonBadge,
            bannerOverlay: item.bannerOverlay,
            onTap: item.onTap,
          ),
        );
      },
    );
  }
}

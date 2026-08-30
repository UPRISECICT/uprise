// lib/widgets/stat_cards.dart
//
// The one stat card, the one summary strip, and the row layout that holds
// them — used by every admin and org page that shows counts above a table.
//
// Before this file there were 24 separate private implementations of the
// same card (15 classes literally named `_StatCard`, plus 5 differently
// named ones and 4 function builders). They had drifted into two families:
// an admin "Row" variant (icon | label / value / subtitle) and an org
// "Column" variant (icon + big number, label underneath, with a selected
// state). The Column layout wins here because the label gets the full card
// width instead of sharing it with the icon, which is what starts to break
// once a page has four or more cards on a narrow window. The admin
// variant's `subtitle` survives as an optional third line.
//
// The companion rule this file exists to enforce: **a page shows at most
// four cards.** Counts beyond that are secondary, and secondary counts
// belong in a [StatStrip] — plain text, no border, no shadow, no icon —
// not in a fifth, sixth and seventh bordered box competing with the first
// four. `StatCardsRow`'s `maxPerRow` stays at 4 for the same reason.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

export 'admin_stat_cards_row.dart' show StatCardsRow;

/// Shared surface tokens. Every copy of the old card hardcoded these exact
/// values; they live in one place now so a change lands everywhere.
class StatCardTokens {
  static const Color border = Color(0xFFE8ECF0);
  static const Color label = Color(0xFF64748B);
  static const Color value = Color(0xFF1A202C);
  static const Color faint = Color(0xFF9AA5B4);
  static const double radius = 12;

  static final List<BoxShadow> shadow = [
    BoxShadow(
      color: Colors.black.withAlpha(15),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];
}

/// A single KPI card: tinted icon badge, the number, a label, and an
/// optional subtitle.
///
/// Supply either [value] (a pre-computed string) or [stream] (a live
/// Firestore query whose document count becomes the number). [stream] wins
/// when both are given. Pass [onTap] to make the card a filter toggle and
/// [selected] to show it as the active one.
class StatCard extends StatelessWidget {
  final String label;
  final String? value;
  final Stream<QuerySnapshot>? stream;
  final String? subtitle;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  const StatCard({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    this.value,
    this.stream,
    this.subtitle,
    this.selected = false,
    this.onTap,
  }) : assert(
         value != null || stream != null,
         'StatCard needs either a value or a stream',
       );

  @override
  Widget build(BuildContext context) {
    if (stream == null) return _card(context, value ?? '0');
    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snapshot) =>
          _card(context, '${snapshot.data?.docs.length ?? 0}'),
    );
  }

  Widget _card(BuildContext context, String shownValue) {
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(StatCardTokens.radius),
        border: Border.all(
          color: selected ? color : StatCardTokens.border,
          width: selected ? 2 : 1,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: color.withAlpha(46),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : StatCardTokens.shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withAlpha(26),
                  borderRadius: BorderRadius.circular(StatCardTokens.radius),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 8),
              // Flexible + ellipsis: a peso total or a four-digit count is
              // wide enough to overflow a quarter-width card otherwise.
              Flexible(
                child: Text(
                  shownValue,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: StatCardTokens.value,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.beVietnamPro(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: StatCardTokens.label,
            ),
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.beVietnamPro(
                fontSize: 10,
                color: StatCardTokens.faint,
              ),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return card;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: card),
    );
  }
}

/// One entry in a [StatStrip].
class StatStripItem {
  final String label;
  final String value;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  const StatStripItem({
    required this.label,
    required this.value,
    this.color = StatCardTokens.label,
    this.selected = false,
    this.onTap,
  });

  StatStripItem.count({
    required String label,
    required int count,
    Color color = StatCardTokens.label,
    bool selected = false,
    VoidCallback? onTap,
  }) : this(
         label: label,
         value: '$count',
         color: color,
         selected: selected,
         onTap: onTap,
       );
}

/// A row of secondary counts as plain text — `Rejected 4   Archived 2`.
///
/// This is the demotion target for any stat past the fourth. The pattern is
/// lifted from org_certificates.dart, where a four-stat summary was moved
/// out of a bordered, shadowed section card for exactly this reason: four
/// numbers didn't need framing that made them compete with the list they
/// were describing. Tapping still filters, and the active entry is marked
/// with a 2px underline rather than a fill.
class StatStrip extends StatelessWidget {
  final List<StatStripItem> items;
  final double spacing;
  final double runSpacing;

  const StatStrip({
    super.key,
    required this.items,
    this.spacing = 20,
    this.runSpacing = 8,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: spacing,
      runSpacing: runSpacing,
      children: [for (final item in items) _StatStripEntry(item: item)],
    );
  }
}

class _StatStripEntry extends StatelessWidget {
  final StatStripItem item;
  const _StatStripEntry({required this.item});

  @override
  Widget build(BuildContext context) {
    final entry = Container(
      padding: const EdgeInsets.only(bottom: 5),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: item.selected ? item.color : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Flexible(
            child: Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.beVietnamPro(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: StatCardTokens.label,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            item.value,
            style: GoogleFonts.beVietnamPro(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: StatCardTokens.value,
            ),
          ),
        ],
      ),
    );

    if (item.onTap == null) return entry;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: item.onTap, child: entry),
    );
  }
}

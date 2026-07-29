// lib/widgets/admin_stat_cards_row.dart
//
// Shared layout for the row of stat cards at the top of every admin page.
// Cards always stretch to fill the full available width (so there's no dead
// space on pages with only 2-4 cards), but a row never holds more than
// [maxPerRow] cards — pages with 5+ cards wrap onto a second, evenly split
// row instead of squeezing every card into one line. Card HEIGHT is already
// consistent across every page (fixed padding/icon/font sizes in _StatCard),
// so this only needs to manage width.
import 'package:flutter/material.dart';

class StatCardsRow extends StatelessWidget {
  final List<Widget> cards;
  final bool isMobile;
  final double gap;
  final int maxPerRow;

  const StatCardsRow({
    super.key,
    required this.cards,
    required this.isMobile,
    this.gap = 14,
    this.maxPerRow = 4,
  });

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final card in cards) ...[card, SizedBox(height: gap)],
        ],
      );
    }

    final rowCount = (cards.length / maxPerRow).ceil();
    final perRow = (cards.length / rowCount).ceil();
    final rows = <List<Widget>>[
      for (var i = 0; i < cards.length; i += perRow)
        cards.sublist(i, (i + perRow).clamp(0, cards.length)),
    ];

    return Column(
      children: [
        for (var r = 0; r < rows.length; r++) ...[
          Row(
            children: [
              for (var c = 0; c < rows[r].length; c++) ...[
                Expanded(child: rows[r][c]),
                if (c < rows[r].length - 1) SizedBox(width: gap),
              ],
            ],
          ),
          if (r < rows.length - 1) SizedBox(height: gap),
        ],
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'anchored_dropdown.dart';

class AdminExportButton extends StatefulWidget {
  // Accepts either a sync `void Function(String)` or an
  // `async`/`Future<void> Function(String)` callback — whichever the
  // caller already wrote. Typed loosely on purpose so every existing call
  // site keeps compiling unchanged.
  final dynamic Function(String) onSelected;
  final bool enabled;
  final String label;

  const AdminExportButton({
    super.key,
    required this.onSelected,
    this.enabled = true,
    this.label = 'Export',
  });

  @override
  State<AdminExportButton> createState() => _AdminExportButtonState();
}

class _AdminExportButtonState extends State<AdminExportButton> {
  bool _busy = false;

  // The actual PDF/CSV generation this triggers is CPU-bound and runs on
  // the UI thread, so without this the app just freezes with no feedback
  // for however long that takes — this at least shows a spinner and gives
  // the engine one frame to paint it before the heavy work blocks.
  Future<void> _handleSelected(String value) async {
    setState(() => _busy = true);
    await Future.delayed(Duration.zero);
    try {
      final result = widget.onSelected(value);
      if (result is Future) await result;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const _items = ['excel', 'pdf'];

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled && !_busy;
    final iconColor = enabled ? const Color(0xFF374151) : const Color(0xFF9AA5B4);
    final textColor = enabled ? const Color(0xFF374151) : const Color(0xFF9AA5B4);

    final trigger = Container(
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E6EA)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _busy
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: iconColor),
                )
              : Icon(Icons.download_rounded, size: 16, color: iconColor),
          const SizedBox(width: 6),
          Text(_busy ? 'Exporting…' : widget.label,
              style: GoogleFonts.beVietnamPro(
                  fontSize: 13, fontWeight: FontWeight.w500, color: textColor)),
          const SizedBox(width: 4),
          Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: iconColor),
        ]),
      ),
    );

    if (!enabled) return trigger;

    return AnchoredMenuTrigger<String>(
      trigger: trigger,
      items: _items,
      menuWidth: 190,
      itemBuilder: (value, selected) => Row(children: [
        Icon(
          value == 'excel' ? Icons.table_chart_rounded : Icons.picture_as_pdf_rounded,
          size: 16,
          color: const Color(0xFF64748B),
        ),
        const SizedBox(width: 10),
        Text(
          value == 'excel' ? 'Export as Excel' : 'Export as PDF',
          style: GoogleFonts.beVietnamPro(fontSize: 13),
        ),
      ]),
      onSelected: _handleSelected,
    );
  }
}

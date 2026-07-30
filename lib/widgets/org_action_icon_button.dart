import 'package:flutter/material.dart';

/// Shared table chrome + action-icon styling used across all org web
/// screens (Finance, Reports, Merchandise, Certificates, Event Proposals,
/// Letter Request, Attendance QR) so every table looks and behaves the same.
class OrgTableStyle {
  static const double containerRadius = 14;
  static const Color containerBorder = Color(0xFFE8ECF0);
  static const Color headerBg = Color(0xFFFFF7ED);
  static const EdgeInsets headerPadding = EdgeInsets.symmetric(
    horizontal: 20,
    vertical: 13,
  );
  static const EdgeInsets rowPadding = EdgeInsets.symmetric(
    horizontal: 20,
    vertical: 14,
  );
  static const Color rowDivider = Color(0xFFF1F5F9);
  static const Color rowHover = Color(0xFFF8F9FB);
  static const double actionIconGap = 6;

  static List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Colors.black.withAlpha(15),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];

  static BoxDecoration containerDecoration() => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(containerRadius),
    border: Border.all(color: containerBorder),
    boxShadow: cardShadow,
  );

  static BoxDecoration headerDecoration({required Color accent}) =>
      BoxDecoration(
        color: headerBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        border: Border(bottom: BorderSide(color: accent.withAlpha(60))),
      );
}

/// Standard row-action icon button (view/edit/archive/etc.), consistent
/// pad/radius/size/tint across every org table.
class OrgActionIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color? color;

  const OrgActionIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  static const Map<int, Color> _bgByFg = {
    0xFF3B82F6: Color(0xFFEFF6FF), // view - blue
    0xFF2563EB: Color(0xFFEFF6FF), // publish - blue
    0xFFB45309: Color(0xFFFFF7ED), // edit - orange (UpriseColors.primaryDark)
    0xFF7C3AED: Color(0xFFF3E8FF), // revise - purple
    0xFF0D9488: Color(0xFFECFDF5), // form builder - teal
    0xFF6B7280: Color(0xFFF3F4F6), // archive - gray
    0xFFDC2626: Color(0xFFFEF2F2), // delete - red
    0xFF059669: Color(0xFFECFDF5), // approve/live - green
  };

  @override
  Widget build(BuildContext context) {
    final fg = onTap == null
        ? const Color(0xFFD1D5DB)
        : (color ?? const Color(0xFF3B82F6));
    final bg = onTap == null
        ? const Color(0xFFF1F5F9)
        : (_bgByFg[fg.value] ?? fg.withAlpha(26));
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: fg),
        ),
      ),
    );
  }
}

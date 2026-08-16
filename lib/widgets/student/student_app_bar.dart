// lib/widgets/student/student_app_bar.dart
//
// Shared app bar for student screens — replaces N near-identical but subtly
// different custom AppBars (different title colors, different back-arrow
// icon families, different font sizes) with one consistent component.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class StudentAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final bool centerTitle;
  final Widget? leading;
  final bool showDivider;
  // Optional TabBar (or any PreferredSizeWidget) below the title — when
  // set, this replaces the plain 1px divider rather than stacking with it,
  // since AppBar only has one `bottom` slot. Null preserves every existing
  // call site's behavior exactly.
  final PreferredSizeWidget? bottom;

  const StudentAppBar({
    super.key,
    required this.title,
    this.actions,
    this.centerTitle = true,
    this.leading,
    this.showDivider = true,
    this.bottom,
  });

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 1));

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      centerTitle: centerTitle,
      leading:
          leading ??
          (Navigator.of(context).canPop()
              ? IconButton(
                  icon: const Icon(
                    Icons.arrow_back,
                    color: AppColors.textPrimary,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                )
              : null),
      title: Text(
        title,
        style: GoogleFonts.beVietnamPro(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
      actions: actions,
      bottom:
          bottom ??
          (showDivider
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(1),
                  child: Container(height: 1, color: AppColors.divider),
                )
              : null),
    );
  }
}

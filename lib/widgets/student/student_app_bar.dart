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

  // False when the screen is hosted as a sub-tab and the parent already shows
  // a title — the title row collapses to nothing but [bottom] (a TabBar) is
  // still rendered. Without this the embedded screen stacks a second, empty
  // toolbar under the host's, which is what the guest Calendar and My Events
  // sub-tabs used to open-code as `toolbarHeight: 0`.
  final bool showTitleBar;

  const StudentAppBar({
    super.key,
    required this.title,
    this.actions,
    this.centerTitle = true,
    this.leading,
    this.showDivider = true,
    this.bottom,
    this.showTitleBar = true,
  });

  @override
  Size get preferredSize => Size.fromHeight(
    (showTitleBar ? kToolbarHeight : 0) + (bottom?.preferredSize.height ?? 1),
  );

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      // Material 3 tints the bar with the primary color once content scrolls
      // under it, which turned every one of these bars pink mid-scroll. The
      // home SliverAppBar already opts out; this makes the shared bar agree
      // with it, so the chrome stays white on every screen.
      scrolledUnderElevation: 0,
      centerTitle: centerTitle,
      toolbarHeight: showTitleBar ? kToolbarHeight : 0,
      automaticallyImplyLeading: showTitleBar,
      leading: !showTitleBar
          ? null
          : leading ??
                (Navigator.of(context).canPop()
                    ? IconButton(
                        icon: const Icon(
                          Icons.arrow_back,
                          color: AppColors.textPrimary,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      )
                    : null),
      title: showTitleBar
          ? Text(
              title,
              style: GoogleFonts.beVietnamPro(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            )
          : null,
      actions: showTitleBar ? actions : null,
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

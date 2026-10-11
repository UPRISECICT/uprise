// lib/widgets/common/bottom_nav_bar.dart
//
// Shared bottom navigation bar.
//
// Extracted from student_home_screen.dart so the guest shell can use the same
// nav chrome instead of hand-rolling its own — the two had drifted apart
// (different heights, different active treatments) purely because this lived
// in a student-only file. The `_UiTokens` aliases it used to reference are
// resolved to their `AppColors` sources here.

import 'package:flutter/material.dart';
import '../student/app_colors.dart';

class BottomNavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const BottomNavItem(this.icon, this.selectedIcon, this.label);
}

class BottomNavBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  final List<BottomNavItem> items;

  const BottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 360;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFF0F0F0), width: 1)),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            isCompact ? 4 : 8,
            isCompact ? 3 : 5,
            isCompact ? 4 : 8,
            2,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(items.length, (index) {
              final item = items[index];
              final isSelected = currentIndex == index;

              return Expanded(
                child: GestureDetector(
                  onTap: () => onTap(index),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: EdgeInsets.symmetric(
                      vertical: isCompact ? 4 : 5,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.surfaceTint
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isSelected ? item.selectedIcon : item.icon,
                          color: isSelected
                              ? AppColors.primaryDark
                              : AppColors.textSecondary,
                          size: isCompact ? 22 : 24,
                        ),
                        SizedBox(height: isCompact ? 3 : 4),
                        // FittedBox instead of overflow:visible — a label
                        // longer than "Announce" (e.g. "Announcements")
                        // would otherwise spill past its Expanded slot and
                        // overlap the neighboring tab instead of shrinking
                        // to fit.
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              item.label,
                              style: TextStyle(
                                fontSize: isCompact ? 11 : 12,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: isSelected
                                    ? AppColors.primaryDark
                                    : AppColors.textSecondary,
                                decoration: TextDecoration.none,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

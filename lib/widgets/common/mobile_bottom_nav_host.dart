import 'package:flutter/material.dart';

import 'bottom_nav_bar.dart';

/// Root navigator key used to return to the active home shell when a tab is
/// selected while a pushed detail page is open.
final GlobalKey<NavigatorState> mobileRootNavigatorKey =
    GlobalKey<NavigatorState>();

class _MobileNavState extends ChangeNotifier {
  bool isVisible = false;
  int selectedIndex = 0;
  ValueChanged<int>? _onTabSelected;

  void attach({required int selectedIndex, required ValueChanged<int> onTap}) {
    final changed = !isVisible || this.selectedIndex != selectedIndex;
    isVisible = true;
    this.selectedIndex = selectedIndex;
    _onTabSelected = onTap;
    if (changed) notifyListeners();
  }

  void updateSelectedIndex(int index) {
    if (selectedIndex == index) return;
    selectedIndex = index;
    notifyListeners();
  }

  void detach() {
    if (!isVisible) return;
    isVisible = false;
    _onTabSelected = null;
    notifyListeners();
  }

  void selectTab(int index) {
    selectedIndex = index;
    notifyListeners();
    _onTabSelected?.call(index);
    mobileRootNavigatorKey.currentState?.popUntil((route) => route.isFirst);
  }
}

final _mobileNavState = _MobileNavState();

/// Keeps the student/guest primary navigation outside the route stack, so it
/// remains visible over mobile detail pages pushed by any tab.
class MobileBottomNavHost extends StatelessWidget {
  final Widget child;

  const MobileBottomNavHost({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _mobileNavState,
      builder: (context, _) => Column(
        children: [
          Expanded(child: child),
          if (_mobileNavState.isVisible)
            BottomNavBar(
              currentIndex: _mobileNavState.selectedIndex,
              onTap: _mobileNavState.selectTab,
              items: const [
                BottomNavItem(Icons.home_outlined, Icons.home, 'Home'),
                BottomNavItem(
                  Icons.calendar_today_outlined,
                  Icons.calendar_today,
                  'Events',
                ),
                BottomNavItem(Icons.groups_outlined, Icons.groups, 'Orgs'),
                BottomNavItem(Icons.person_outline, Icons.person, 'Profile'),
              ],
            ),
        ],
      ),
    );
  }
}

void attachMobileBottomNav({
  required int selectedIndex,
  required ValueChanged<int> onTap,
}) => _mobileNavState.attach(selectedIndex: selectedIndex, onTap: onTap);

void updateMobileBottomNavIndex(int index) =>
    _mobileNavState.updateSelectedIndex(index);

void detachMobileBottomNav() => _mobileNavState.detach();

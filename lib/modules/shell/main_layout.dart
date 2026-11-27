import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../controllers/friend_controller.dart';
import '../../controllers/shell_controller.dart';
import '../../core/ui.dart';
import 'quick_add_sheet.dart';
import '../home/dashboard_screen.dart';
import '../friends/friends_screen.dart';
import '../groups/groups_screen.dart';
import '../profile/profile_screen.dart';

/// The app shell: a fixed bottom bar over swipeable tabs. Swipe left/right
/// to move between Home, Groups, Friends and Profile; tapping the bar slides
/// to the tab. Tabs are built the first time they are shown and keep their
/// state (scroll position, search) after that.
class MainLayout extends StatefulWidget {
  final int initialIndex;
  const MainLayout({super.key, this.initialIndex = 0});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  late final ShellController _shell = Get.find<ShellController>();
  late final PageController _pager;
  Worker? _worker;

  /// True while the pager is sliding because the bar (or code) asked it to;
  /// pages it passes on the way must not change the selected tab.
  bool _sliding = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialIndex != 0) _shell.index.value = widget.initialIndex;
    _pager = PageController(initialPage: _shell.index.value);
    _worker = ever<int>(_shell.index, _slideTo);
  }

  @override
  void dispose() {
    _worker?.dispose();
    _pager.dispose();
    super.dispose();
  }

  Future<void> _slideTo(int i) async {
    if (!_pager.hasClients) return;
    final current = _pager.page?.round() ?? i;
    if (current == i) return;
    _sliding = true;
    try {
      // Far jumps (Home → Profile) skip the in-between tabs.
      if ((current - i).abs() > 1) {
        _pager.jumpToPage(i > current ? i - 1 : i + 1);
      }
      await _pager.animateToPage(
        i,
        duration: AppMotion.slow,
        curve: AppMotion.curve,
      );
    } finally {
      _sliding = false;
    }
  }

  void _onSwiped(int i) {
    if (_sliding || _shell.index.value == i) return;
    HapticFeedback.selectionClick();
    _shell.index.value = i;
  }

  Widget _build(int i) => switch (i) {
        1 => const GroupsScreen(),
        2 => const FriendsScreen(),
        3 => const ProfileScreen(),
        _ => const DashboardScreen(),
      };

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final index = _shell.index.value;
      return PopScope(
        canPop: index == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && index != 0) _shell.select(AppTab.home);
        },
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: (AppColors.isDark
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark)
              .copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: AppColors.background,
            systemNavigationBarIconBrightness:
                AppColors.isDark ? Brightness.light : Brightness.dark,
          ),
          child: Scaffold(
            backgroundColor: AppColors.background,
            extendBody: false,
            body: PageView.builder(
              controller: _pager,
              itemCount: 4,
              onPageChanged: _onSwiped,
              physics: const PageScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              itemBuilder: (_, i) => _KeepAlive(child: _build(i)),
            ),
            bottomNavigationBar: _BottomBar(
              index: index,
              onSelect: (i) {
                if (i == index) return;
                HapticFeedback.selectionClick();
                _shell.index.value = i;
              },
            ),
          ),
        ),
      );
    });
  }
}

/// Keeps a tab alive once it has been built, so swiping back to it is
/// instant and it remembers where you were.
class _KeepAlive extends StatefulWidget {
  final Widget child;
  const _KeepAlive({required this.child});

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _BottomBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;

  const _BottomBar({required this.index, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final requests = Get.find<FriendController>().friendRequests;
    return ColoredBox(
      color: AppColors.background,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          child: Center(
            heightFactor: 1,
            child: Container(
              height: 62,
              constraints: const BoxConstraints(maxWidth: 360),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: AppColors.nav,
                borderRadius: BorderRadius.circular(31),
              ),
              child: Row(
                children: [
                  _NavItem(
                    icon: Icons.home_outlined,
                    activeIcon: Icons.home_rounded,
                    label: 'Home',
                    selected: index == 0,
                    onTap: () => onSelect(0),
                  ),
                  _NavItem(
                    icon: Icons.groups_outlined,
                    activeIcon: Icons.groups_rounded,
                    label: 'Groups',
                    selected: index == 1,
                    onTap: () => onSelect(1),
                  ),
                  Expanded(
                    child: Center(
                      child: Tooltip(
                        message: 'Quick add',
                        child: Semantics(
                          button: true,
                          label: 'Quick add',
                          excludeSemantics: true,
                          child: Pressable(
                            onTap: QuickAdd.show,
                            child: Container(
                              width: 58,
                              height: 46,
                              decoration: BoxDecoration(
                                color: AppColors.accent,
                                borderRadius: BorderRadius.circular(23),
                              ),
                              child: Icon(Icons.add_rounded,
                                  color: AppColors.onAccent, size: 28),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Obx(() => _NavItem(
                        icon: Icons.people_alt_outlined,
                        activeIcon: Icons.people_alt_rounded,
                        label: 'Friends',
                        selected: index == 2,
                        badge: requests.length,
                        onTap: () => onSelect(2),
                      )),
                  _NavItem(
                    icon: Icons.person_outline_rounded,
                    activeIcon: Icons.person_rounded,
                    label: 'Profile',
                    selected: index == 3,
                    onTap: () => onSelect(3),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Icon-only nav item inside the dark pill. The selected tab sits on a
/// pistachio capsule; the name is announced and shown as a tooltip.
class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark;
    final pill = dark ? AppColors.primary : AppColors.hero;
    final onPill = dark ? AppColors.onPrimary : AppColors.onHero;
    final color = selected ? onPill : AppColors.navIdle;
    return Expanded(
      child: Tooltip(
        message: label,
        child: Semantics(
          selected: selected,
          button: true,
          label: badge > 0 ? '$label, $badge new' : label,
          excludeSemantics: true,
          child: InkResponse(
            onTap: onTap,
            radius: 30,
            child: Center(
              child: AnimatedContainer(
                duration: AppMotion.normal,
                curve: AppMotion.curve,
                width: 56,
                height: 46,
                decoration: BoxDecoration(
                  color: selected ? pill : Colors.transparent,
                  borderRadius: BorderRadius.circular(23),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Icon(selected ? activeIcon : icon, color: color, size: 24),
                    if (badge > 0)
                      Positioned(
                        right: 8,
                        top: 6,
                        child: Container(
                          constraints:
                              const BoxConstraints(minWidth: 16, minHeight: 16),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.nav, width: 1.5),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            badge > 9 ? '9+' : '$badge',
                            style: TextStyle(
                              color: AppColors.onAccent,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

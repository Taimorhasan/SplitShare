import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../controllers/friend_controller.dart';
import '../controllers/shell_controller.dart';
import '../core/ui.dart';
import 'dashboard_screen.dart';
import 'friends_screen.dart';
import 'groups_screen.dart';
import 'profile_screen.dart';

/// The app shell: a fixed bottom navigation bar with lazily-built,
/// state-preserving tabs (IndexedStack). Only the content area changes when
/// switching tabs — the bar itself never rebuilds its position or size.
class MainLayout extends StatefulWidget {
  final int initialIndex;
  const MainLayout({super.key, this.initialIndex = 0});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  late final ShellController _shell = Get.find<ShellController>();
  final List<Widget?> _pages = List<Widget?>.filled(4, null);
  Worker? _worker;

  @override
  void initState() {
    super.initState();
    if (widget.initialIndex != 0) _shell.index.value = widget.initialIndex;
    _pages[_shell.index.value] = _build(_shell.index.value);
    _worker = ever<int>(_shell.index, (i) {
      if (_pages[i] == null && mounted) setState(() => _pages[i] = _build(i));
    });
  }

  @override
  void dispose() {
    _worker?.dispose();
    super.dispose();
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
          value: SystemUiOverlayStyle.dark.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.white,
            systemNavigationBarIconBrightness: Brightness.dark,
          ),
          child: Scaffold(
            backgroundColor: AppColors.background,
            extendBody: false,
            body: IndexedStack(
              index: index,
              children: [
                for (var i = 0; i < 4; i++)
                  _pages[i] == null
                      ? const SizedBox.shrink()
                      : TickerMode(enabled: i == index, child: _pages[i]!),
              ],
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

class _BottomBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;

  const _BottomBar({required this.index, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final requests = Get.find<FriendController>().friendRequests;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 70,
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
                    message: 'Add expense',
                    child: Pressable(
                      onTap: () => AppNav.addExpense(),
                      child: Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          gradient: AppColors.brandGradient,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: AppShadows.glow(AppColors.primary),
                        ),
                        child: const Icon(Icons.add_rounded,
                            color: Colors.white, size: 30),
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
    );
  }
}

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
    final color = selected ? AppColors.primary : AppColors.textMuted;
    final item = Semantics(
      selected: selected,
      button: true,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: 36,
        highlightShape: BoxShape.rectangle,
        containedInkWell: false,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: AppMotion.normal,
              curve: AppMotion.curve,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
              decoration: BoxDecoration(
                color: selected ? AppColors.primaryLight : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedSwitcher(
                    duration: AppMotion.fast,
                    transitionBuilder: (c, a) =>
                        ScaleTransition(scale: a, child: c),
                    child: Icon(
                      selected ? activeIcon : icon,
                      key: ValueKey(selected),
                      color: color,
                      size: 24,
                    ),
                  ),
                  if (badge > 0)
                    Positioned(
                      right: -6,
                      top: -4,
                      child: Container(
                        constraints:
                            const BoxConstraints(minWidth: 16, minHeight: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: AppColors.negative,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          badge > 9 ? '9+' : '$badge',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            AnimatedDefaultTextStyle(
              duration: AppMotion.fast,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
              child: Text(label, maxLines: 1),
            ),
          ],
        ),
      ),
    );
    return Expanded(child: item);
  }
}

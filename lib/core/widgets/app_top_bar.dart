import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../app_colors.dart';
import 'app_button.dart';

/// Standard app bar for pushed (non-tab) screens.
///
/// Shows a rounded back button when the route can pop.
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final bool showBack;
  final VoidCallback? onBack;
  final Color? background;

  const AppTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.showBack = true,
    this.onBack,
    this.background,
  });

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return AppBar(
      backgroundColor: background ?? AppColors.background,
      toolbarHeight: 64,
      automaticallyImplyLeading: false,
      titleSpacing: showBack && canPop ? 4 : 20,
      leadingWidth: 64,
      leading: showBack && canPop
          ? Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Center(
                child: AppIconButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  tooltip: 'Back',
                  size: 42,
                  onPressed: onBack ?? () => Get.back(),
                ),
              ),
            )
          : null,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
        ],
      ),
      actions: [
        ...actions,
        const SizedBox(width: 12),
      ],
    );
  }
}

/// Large title header used at the top of the main tab screens.
class TabHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  const TabHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.headlineMedium),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ],
            ),
          ),
          for (final a in actions) ...[const SizedBox(width: 10), a],
        ],
      ),
    );
  }
}

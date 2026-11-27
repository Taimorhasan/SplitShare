import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../app/routes/app_routes.dart';
import '../controllers/auth_controller.dart';
import '../controllers/expense_controller.dart';
import '../controllers/friend_controller.dart';
import '../controllers/group_controller.dart';
import '../controllers/notification_controller.dart';
import '../controllers/profile_controller.dart';
import '../controllers/shell_controller.dart';
import '../controllers/theme_controller.dart';
import '../core/ui.dart';

/// Profile tab: the user's identity, quick stats and app settings.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  ProfileController get _profile => ProfileController.to;
  bool _exporting = false;

  /// Human name of the social provider the user signed in with.
  String get _providerName {
    final providers =
        FirebaseAuth.instance.currentUser?.providerData
            .map((p) => p.providerId)
            .toList() ??
        const <String>[];
    if (providers.contains('google.com')) return 'Google';
    if (providers.contains('apple.com')) return 'Apple';
    return 'your sign-in provider';
  }

  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      await _profile.exportUserData();
    } catch (e) {
      AppToast.error(AppToast.friendly(e), title: 'Export failed');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _toggleNotifications(bool value) async {
    try {
      await _profile.toggleNotifications(value);
    } catch (e) {
      AppToast.error(AppToast.friendly(e), title: 'Couldn\'t update setting');
    }
  }

  void _pickCurrency() {
    AppDialogs.sheet<void>(
      title: 'Default currency',
      child: _CurrencySheet(
        selected: _profile.currencyCode.value,
        onSelect: (code) async {
          if (code == _profile.currencyCode.value) return;
          try {
            await _profile.changeCurrency(code);
            AppToast.success(
              '${Currencies.names[code] ?? code} is now your default currency.',
              title: 'Currency updated',
            );
          } catch (e) {
            AppToast.error(AppToast.friendly(e));
          }
        },
      ),
    );
  }

  void _pickAppearance() {
    AppDialogs.sheet<void>(
      title: 'Appearance',
      child: Builder(
        builder: (sheetContext) {
          final current = ThemeController.to.mode.value;
          Widget option(ThemeMode mode, String label, IconData icon) {
            final selected = mode == current;
            return AppListTile(
              icon: icon,
              title: label,
              showChevron: false,
              trailing: selected
                  ? Icon(Icons.check_rounded, color: AppColors.primary)
                  : null,
              onTap: () {
                // Navigator.pop (not Get.back) so an open toast can't swallow it.
                Navigator.of(sheetContext).pop();
                ThemeController.to.setMode(mode);
              },
            );
          }

          return Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                option(ThemeMode.system, 'Same as phone',
                    Icons.phone_android_rounded),
                option(ThemeMode.light, 'Light', Icons.light_mode_outlined),
                option(ThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showAbout() {
    AppDialogs.sheet<void>(
      child: Builder(
        builder: (sheetContext) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppLogo(size: 76),
              const SizedBox(height: AppSpacing.lg),
              Text('SplitShare', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Version 1.0.0',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Split bills with friends and groups, keep track of who owes '
                'whom in any currency, and settle up when you\'re ready.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              AppButton.outline(
                label: 'Open-source licenses',
                icon: Icons.description_outlined,
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  showLicensePage(
                    context: context,
                    applicationName: 'SplitShare',
                    applicationVersion: '1.0.0',
                    applicationIcon: const Padding(
                      padding: EdgeInsets.all(12),
                      child: AppLogo(size: 56, withShadow: false),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _logout() async {
    final ok = await AppDialogs.confirm(
      title: 'Log out?',
      message: 'You\'ll need to sign in again to see your groups and balances.',
      confirmLabel: 'Log out',
      destructive: true,
      icon: Icons.logout_rounded,
    );
    if (ok) await AuthController.instance.logout();
  }

  @override
  Widget build(BuildContext context) {
    final hasPassword = AuthController.instance.hasPasswordProvider;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TabHeader(
                title: 'Profile',
                actions: [
                  Obx(
                    () => AppIconButton(
                      icon: Icons.notifications_none_rounded,
                      tooltip: 'Notifications',
                      badgeCount: NotificationController.to.unreadCount,
                      onPressed: () => Get.toNamed(AppRoutes.notifications),
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.page,
                  AppSpacing.sm,
                  AppSpacing.page,
                  0,
                ),
                child: FadeSlideIn(child: _ProfileHeader()),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.page,
                  AppSpacing.xl,
                  AppSpacing.page,
                  0,
                ),
                child: FadeSlideIn(index: 1, child: _StatsRow()),
              ),

              // Preferences
              const SectionHeader(title: 'Preferences'),
              FadeSlideIn(
                index: 2,
                child: _SettingsCard(
                  children: [
                    Obx(() {
                      final code = _profile.currencyCode.value;
                      return AppListTile(
                        icon: Icons.payments_outlined,
                        title: 'Default currency',
                        subtitle: '$code · ${Currencies.names[code] ?? code}',
                        onTap: _pickCurrency,
                      );
                    }),
                    Obx(
                      () => AppListTile(
                        icon: Icons.contrast_rounded,
                        title: 'Appearance',
                        subtitle: ThemeController.to.label,
                        onTap: _pickAppearance,
                      ),
                    ),
                    Obx(
                      () => AppListTile(
                        icon: Icons.notifications_active_outlined,
                        title: 'Notifications',
                        subtitle: _profile.notificationsEnabled.value
                            ? 'Friends can send you in-app notifications for expenses, payments and reminders'
                            : 'Off — others can\'t send you in-app notifications',
                        onTap: () => _toggleNotifications(
                          !_profile.notificationsEnabled.value,
                        ),
                        trailing: Switch.adaptive(
                          value: _profile.notificationsEnabled.value,
                          onChanged: _toggleNotifications,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Account
              const SectionHeader(title: 'Account'),
              FadeSlideIn(
                index: 3,
                child: _SettingsCard(
                  children: [
                    AppListTile(
                      icon: Icons.person_outline_rounded,
                      title: 'Edit profile',
                      subtitle: 'Name, photo and phone number',
                      onTap: () => Get.toNamed(AppRoutes.editProfile),
                    ),
                    if (hasPassword)
                      AppListTile(
                        icon: Icons.lock_outline_rounded,
                        title: 'Change password',
                        onTap: () => Get.toNamed(AppRoutes.changePassword),
                      )
                    else
                      AppListTile(
                        icon: Icons.verified_user_outlined,
                        title: 'Signed in with $_providerName',
                        subtitle: 'Your password is managed by your provider',
                        showChevron: false,
                      ),
                    Obx(() {
                      final count = FriendController.to.friendRequests.length;
                      return AppListTile(
                        icon: Icons.person_add_alt_1_outlined,
                        title: 'Friend requests',
                        subtitle: count == 0
                            ? 'No pending requests'
                            : '$count waiting for your reply',
                        onTap: () => Get.toNamed(AppRoutes.friendRequests),
                        trailing: count == 0
                            ? null
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  StatusPill(
                                    label: '$count',
                                    color: AppColors.negative,
                                  ),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    color: AppColors.textMuted,
                                  ),
                                ],
                              ),
                      );
                    }),
                    AppListTile(
                      icon: Icons.download_rounded,
                      title: 'Export my data',
                      subtitle: _exporting
                          ? 'Preparing your export…'
                          : 'Profile, friends, groups and expenses as JSON',
                      onTap: _exporting ? null : _export,
                      showChevron: !_exporting,
                      trailing: _exporting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                              ),
                            )
                          : null,
                    ),
                  ],
                ),
              ),

              // Support
              const SectionHeader(title: 'Support'),
              FadeSlideIn(
                index: 4,
                child: _SettingsCard(
                  children: [
                    AppListTile(
                      icon: Icons.help_outline_rounded,
                      title: 'Help & FAQ',
                      onTap: () => Get.toNamed(AppRoutes.help),
                    ),
                    AppListTile(
                      icon: Icons.info_outline_rounded,
                      title: 'About SplitShare',
                      subtitle: 'Version 1.0.0',
                      onTap: _showAbout,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.xxl),
              FadeSlideIn(
                index: 5,
                child: _SettingsCard(
                  children: [
                    AppListTile(
                      icon: Icons.logout_rounded,
                      title: 'Log out',
                      destructive: true,
                      showChevron: false,
                      onTap: _logout,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader();

  @override
  Widget build(BuildContext context) {
    final p = ProfileController.to;
    return Obx(() {
      final name = p.name.value.trim().isEmpty ? 'Your name' : p.name.value;
      final since = p.memberSince.value;
      return Row(
        children: [
          AppAvatar(
            name: name,
            imageUrl: p.avatarUrl.value,
            radius: 34,
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  p.email.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13.5,
                  ),
                ),
                if (since != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Member since ${Fmt.date(since)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          AppButton.outline(
            label: 'Edit',
            icon: Icons.edit_outlined,
            expand: false,
            height: 40,
            onPressed: () => Get.toNamed(AppRoutes.editProfile),
          ),
        ],
      );
    });
  }
}

/// Plain figures: count in ink over a quiet label, between hairline rules.
class _StatsRow extends StatelessWidget {
  const _StatsRow();

  @override
  Widget build(BuildContext context) {
    Widget rule() => Container(width: 1, height: 36, color: AppColors.border);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.symmetric(
          horizontal: BorderSide(color: AppColors.border),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Obx(
              () => _StatTile(
                value: FriendController.to.friends.length,
                label: 'Friends',
                onTap: () => AppNav.toTab(AppTab.friends),
              ),
            ),
          ),
          rule(),
          Expanded(
            child: Obx(
              () => _StatTile(
                value: GroupController.to.groups.length,
                label: 'Groups',
                onTap: () => AppNav.toTab(AppTab.groups),
              ),
            ),
          ),
          rule(),
          Expanded(
            child: Obx(
              () => _StatTile(
                value: ExpenseController.to.balances.length,
                label: 'Open balances',
                onTap: () => Get.toNamed(AppRoutes.settleUp),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final int value;
  final String label;
  final VoidCallback onTap;

  const _StatTile({
    required this.value,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$value $label',
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            children: [
              AnimatedSwitcher(
                duration: AppMotion.normal,
                child: Text(
                  '$value',
                  key: ValueKey(value),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ruled block holding a group of settings rows with inset dividers.
class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
      child: AppCard(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  thickness: 1,
                  indent: 68,
                  endIndent: 14,
                  color: AppColors.border,
                ),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

class _CurrencySheet extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;

  const _CurrencySheet({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final codes = Currencies.symbols.keys.toList();
    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      itemCount: codes.length,
      itemBuilder: (_, i) {
        final code = codes[i];
        final isSelected = code == selected;
        return Material(
          color: isSelected ? AppColors.primaryLight : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: () {
              // Navigator.pop (not Get.back) so an open toast can't swallow it.
              Navigator.of(context).pop();
              onSelect(code);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Text(
                      Currencies.symbols[code]!,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isSelected
                            ? AppColors.onPrimary
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          Currencies.names[code] ?? code,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          code,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: AppMotion.fast,
                    child: isSelected
                        ? Icon(
                            Icons.check_circle_rounded,
                            key: const ValueKey('on'),
                            color: AppColors.primary,
                          )
                        : const SizedBox(key: ValueKey('off'), width: 24),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

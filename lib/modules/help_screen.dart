import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../controllers/shell_controller.dart';
import '../core/ui.dart';

class _Faq {
  final String question;
  final String answer;
  const _Faq(this.question, this.answer);
}

class _FaqSection {
  final String title;
  final IconData icon;
  final List<_Faq> items;
  const _FaqSection(this.title, this.icon, this.items);
}

const _sections = <_FaqSection>[
  _FaqSection(
    'Balances',
    Icons.account_balance_wallet_outlined,
    [
      _Faq(
        'How are balances calculated?',
        'When someone pays for an expense, each other person\'s share is owed '
            'to whoever paid. Your balance with a friend is everything they owe '
            'you minus everything you owe them, across all shared expenses and '
            'groups.',
      ),
      _Faq(
        'What happens when I record a payment?',
        'A payment reduces the balance between the two of you by that amount. '
            'Once everything is paid back, you\'re shown as settled up.',
      ),
      _Faq(
        'How are different currencies handled?',
        'Amounts in different currencies are kept separately — SplitShare '
            'doesn\'t convert between them. If you owe \$10 and are owed €5 '
            'with the same person, you\'ll see both amounts.',
      ),
    ],
  ),
  _FaqSection('Expenses', Icons.receipt_long_outlined, [
    _Faq(
      'What split types can I use?',
      'Equally divides the amount evenly between everyone involved. Percent '
          'lets you give each person a percentage — the percentages must add '
          'up to 100%. Exact lets you enter each person\'s amount — the '
          'amounts must add up to the total. Full amount means no split: '
          'whoever paid is owed the whole amount (for example, you paid for '
          "a friend's ticket).",
    ),
    _Faq(
      'Who can edit or delete an expense?',
      'Only the person who added an expense can edit or delete it. If '
          'something looks wrong, ask them to update it.',
    ),
    _Faq(
      'Does deleting an expense change balances?',
      'Yes. Balances are always calculated from the current expenses and '
          'payments, so editing or deleting one updates everyone\'s balance.',
    ),
  ]),
  _FaqSection('Settling up', Icons.handshake_outlined, [
    _Faq(
      'How do I settle up?',
      'Open Settle up, pick a person, then record a partial payment or settle '
          'everything you owe each other at once.',
    ),
    _Faq(
      'Does SplitShare move money?',
      'No. Settling up only records that a payment happened. Pay each other '
          'however you normally do — cash, bank transfer or a payment app — '
          'and then record it here.',
    ),
  ]),
  _FaqSection('Groups', Icons.groups_2_outlined, [
    _Faq(
      'How do groups work?',
      'Create a group for a trip, home or event and add your friends as '
          'members. Expenses added to the group are split between its members, '
          'and you can add more members at any time.',
    ),
    _Faq(
      'Can I leave a group?',
      'Yes, as long as your balance in that group is settled. Settle up with '
          'the other members first, then leave.',
    ),
    _Faq(
      'Who can delete a group?',
      'Only the person who created the group can delete it.',
    ),
  ]),
  _FaqSection('Friends', Icons.people_alt_outlined, [
    _Faq(
      'How do I add friends?',
      'Search for people by name or email address, scan their QR code, or use '
          'their friend code. They\'ll get a friend request to accept.',
    ),
    _Faq(
      'How does contacts matching work?',
      'If you choose to find friends from your contacts, matching happens on '
          'your device using email addresses. Your contacts are not uploaded '
          'or stored.',
    ),
  ]),
  _FaqSection(
    'Notifications',
    Icons.notifications_none_rounded,
    [
      _Faq(
        'What notifications will I get?',
        'In-app notifications for friend requests, new expenses, payments, '
            'reminders and group activity. You\'ll find them behind the bell '
            'icon.',
      ),
      _Faq(
        'How do I turn notifications off?',
        'Go to Profile → Preferences and switch off Notifications. Other people '
            'then can\'t send you in-app notifications.',
      ),
    ],
  ),
  _FaqSection('Privacy & data', Icons.shield_outlined, [
    _Faq(
      'Who can see my details?',
      'Your phone number is private and only visible to you. Your name, email '
          'and photo are visible to signed-in SplitShare users so friends can '
          'find you.',
    ),
    _Faq(
      'Can I get a copy of my data?',
      'Yes. Go to Profile → Export my data to share a copy of your profile, '
          'friends, groups and expenses as a JSON file.',
    ),
  ]),
];

/// Searchable FAQ plus a way to report a problem.
class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<_FaqSection> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _sections;
    final result = <_FaqSection>[];
    for (final s in _sections) {
      final sectionMatch = s.title.toLowerCase().contains(q);
      final items = sectionMatch
          ? s.items
          : s.items
                .where(
                  (f) =>
                      f.question.toLowerCase().contains(q) ||
                      f.answer.toLowerCase().contains(q),
                )
                .toList();
      if (items.isNotEmpty) {
        result.add(_FaqSection(s.title, s.icon, items));
      }
    }
    return result;
  }

  String get _platformName => switch (defaultTargetPlatform) {
    TargetPlatform.android => 'Android',
    TargetPlatform.iOS => 'iOS',
    TargetPlatform.macOS => 'macOS',
    TargetPlatform.windows => 'Windows',
    TargetPlatform.linux => 'Linux',
    TargetPlatform.fuchsia => 'Fuchsia',
  };

  Future<void> _reportProblem() async {
    final platform = kIsWeb ? 'Web ($_platformName)' : _platformName;
    final text =
        '''
SplitShare problem report

App version: 1.0.0
Platform: $platform

What happened:


What did you expect to happen:


Steps to reproduce:
1.
2.
3.
''';
    try {
      await SharePlus.instance.share(
        ShareParams(subject: 'SplitShare problem report', text: text),
      );
    } catch (e) {
      AppToast.error(AppToast.friendly(e), title: 'Couldn\'t open share');
    }
  }

  @override
  Widget build(BuildContext context) {
    final sections = _filtered;
    final searching = _query.trim().isNotEmpty;

    return Scaffold(
      appBar: const AppTopBar(title: 'Help & FAQ'),
      body: GestureDetector(
        onTap: AppNav.unfocus,
        behavior: HitTestBehavior.translucent,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.sm,
            AppSpacing.page,
            AppSpacing.xxxl,
          ),
          children: [
            AnimatedSize(
              duration: AppMotion.normal,
              curve: AppMotion.curve,
              child: searching
                  ? const SizedBox(width: double.infinity)
                  : const Padding(
                      padding: EdgeInsets.only(bottom: AppSpacing.lg),
                      child: FadeSlideIn(child: _HelpHero()),
                    ),
            ),
            AppSearchField(
              controller: _searchCtrl,
              hint: 'Search help articles',
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: AppSpacing.sm),
            AnimatedSwitcher(
              duration: AppMotion.normal,
              child: sections.isEmpty
                  ? Padding(
                      key: const ValueKey('empty'),
                      padding: const EdgeInsets.only(top: AppSpacing.xxl),
                      child: EmptyState(
                        icon: Icons.search_off_rounded,
                        title: 'No results',
                        message:
                            'Nothing matches "${_query.trim()}". Try another word, or report a problem below.',
                        illustrationSize: 140,
                        actionLabel: 'Clear search',
                        actionIcon: Icons.close_rounded,
                        onAction: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      ),
                    )
                  : Column(
                      key: ValueKey('results-$_query'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < sections.length; i++)
                          FadeSlideIn(
                            index: i,
                            child: _SectionCard(
                              section: sections[i],
                              expandAll: searching,
                            ),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            _StillNeedHelp(onReport: _reportProblem),
          ],
        ),
      ),
    );
  }
}

class _HelpHero extends StatelessWidget {
  const _HelpHero();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How can we help?',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Answers about balances, splitting, settling up, groups '
            'and your privacy.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final _FaqSection section;
  final bool expandAll;

  const _SectionCard({required this.section, required this.expandAll});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            2,
            AppSpacing.xxl,
            2,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              IconBadge(
                icon: section.icon,
                color: AppColors.primary,
                size: 30,
                iconSize: 16,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  section.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: Column(
              children: [
                for (var i = 0; i < section.items.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      indent: 16,
                      endIndent: 16,
                      color: AppColors.border,
                    ),
                  _FaqTile(
                    // Re-key so search results open expanded.
                    key: ValueKey('${section.items[i].question}-$expandAll'),
                    faq: section.items[i],
                    initiallyExpanded: expandAll,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FaqTile extends StatelessWidget {
  final _Faq faq;
  final bool initiallyExpanded;

  const _FaqTile({
    super.key,
    required this.faq,
    required this.initiallyExpanded,
  });

  @override
  Widget build(BuildContext context) {
    const shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)),
    );
    return ExpansionTile(
      initiallyExpanded: initiallyExpanded,
      shape: shape,
      collapsedShape: shape,
      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      iconColor: AppColors.primary,
      collapsedIconColor: AppColors.textMuted,
      expansionAnimationStyle: const AnimationStyle(
        duration: AppMotion.normal,
        curve: AppMotion.curve,
      ),
      title: Text(
        faq.question,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      children: [
        Text(
          faq.answer,
          style: TextStyle(
            fontSize: 14,
            color: AppColors.textSecondary,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class _StillNeedHelp extends StatelessWidget {
  final VoidCallback onReport;
  const _StillNeedHelp({required this.onReport});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconBadge(
                icon: Icons.bug_report_outlined,
                color: AppColors.primary,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Still need help?',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Create a problem report, fill in what went wrong and '
                      'send it using any app on your device.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton.secondary(
            label: 'Report a problem',
            icon: Icons.ios_share_rounded,
            onPressed: onReport,
          ),
        ],
      ),
    );
  }
}

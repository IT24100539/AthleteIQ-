import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/risk_chip.dart';
import '../widgets/app_card.dart';
import '../widgets/app_buttons.dart';
import '../widgets/section_header.dart';
import '../widgets/stat_tile.dart';
import '../widgets/empty_state.dart';
import '../widgets/hero_card.dart';
import '../widgets/pill_selector.dart';

/// Visual catalog of every shared widget — open via `/dev/widgets` or
/// `flutter run --dart-define=SHOW_WIDGET_CATALOG=true`.
class WidgetCatalog extends StatefulWidget {
  const WidgetCatalog({super.key});

  @override
  State<WidgetCatalog> createState() => _WidgetCatalogState();
}

class _WidgetCatalogState extends State<WidgetCatalog> {
  String selectedSport = 'Running';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Widget Catalog')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        children: [
          const SectionHeader('Risk chips'),
          const Wrap(
            spacing: AppSpacing.itemGap,
            runSpacing: AppSpacing.itemGap,
            children: [
              RiskChip(level: 'HIGH'),
              RiskChip(level: 'MEDIUM'),
              RiskChip(level: 'LOW'),
            ],
          ),
          const SizedBox(height: AppSpacing.itemGap),
          const RiskChip(level: 'MEDIUM', large: true),
          const SizedBox(height: 6),
          Text(
            'Confidence: Medium (HRV not available)',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: AppSpacing.sectionGap),

          const SectionHeader('Stat tiles'),
          const Row(
            children: [
              Expanded(
                child: StatTile(
                  label: 'Training load',
                  value: '412',
                  trend: StatTrend.up,
                  compact: true,
                ),
              ),
              SizedBox(width: AppSpacing.statGap),
              Expanded(
                child: StatTile(
                  label: 'ACWR',
                  value: '1.62',
                  trend: StatTrend.up,
                  valueColor: AppColors.coral,
                  compact: true,
                ),
              ),
              SizedBox(width: AppSpacing.statGap),
              Expanded(
                child: StatTile(
                  label: 'Sleep',
                  value: '7.2h',
                  trend: StatTrend.down,
                  compact: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sectionGap),

          const SectionHeader('App card'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Garmin Connect',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Synced 4 minutes ago',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const RiskDot(level: 'LOW'),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Last sync pulled HRV, sleep, and training load.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sectionGap),

          const SectionHeader('Buttons'),
          PrimaryButton(
            label: 'Save check-in',
            icon: Icons.check_rounded,
            onPressed: () {},
          ),
          const SizedBox(height: AppSpacing.itemGap),
          SecondaryButton(
            label: 'Cancel',
            onPressed: () {},
          ),
          const SizedBox(height: AppSpacing.sectionGap),

          const SectionHeader('Section header'),
          const SectionHeader('Recent training'),
          const SizedBox(height: AppSpacing.sectionGap),

          const SectionHeader('Empty states'),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
            child: EmptyState(
              icon: Icons.show_chart_rounded,
              heading: 'No data yet',
              subtext:
                  'Start with a check-in (how you felt and what you trained) or connect '
                  'a wearable for sleep and heart rate. AthleteIQ will not invent a '
                  'forecast until you have logged days.',
              actionLabel: 'Log a check-in',
              secondaryActionLabel: 'Connect a device',
              onAction: () {},
              onSecondaryAction: () {},
            ),
          ),
          const SizedBox(height: AppSpacing.itemGap),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
            child: EmptyState(
              icon: Icons.watch_rounded,
              heading: 'Apple Watch sync failed',
              subtext: 'Could not read HealthKit: Health data not available',
              actionLabel: 'Reconnect device',
              warn: true,
              onAction: () {},
            ),
          ),
          const SizedBox(height: AppSpacing.itemGap),
          const AppCard(
            padding: EdgeInsets.symmetric(vertical: 32, horizontal: 16),
            child: EmptyState(
              icon: Icons.person_outline,
              heading: 'No forecast for this athlete yet',
              subtext:
                  'This athlete joined 2 days ago. AthleteIQ needs about 5 days of '
                  'training history before scoring risk or performance. 3 of 5 check-ins needed to calibrate.',
            ),
          ),
          const SizedBox(height: AppSpacing.sectionGap),

          const SectionHeader('Hero gradient card'),
          HeroGradientCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(
                  "Today's status",
                  padding: EdgeInsets.zero,
                ),
                Text(
                  'Reduce training volume by 20%, add one rest day.',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  'Approved by your coach.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sectionGap),

          const SectionHeader('Selectable chips'),
          Wrap(
            spacing: AppSpacing.itemGap,
            runSpacing: AppSpacing.itemGap,
            children: ['Running', 'Rugby', 'Badminton', 'Boxing']
                .map(
                  (s) => SelectableChip(
                    label: s,
                    selected: selectedSport == s,
                    onTap: () => setState(() => selectedSport = s),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: AppSpacing.sectionGap),

          const SectionHeader('Pill row'),
          PillRow(
            items: [
              const PillItem(
                label: 'Approve',
                icon: Icons.check_rounded,
                color: AppColors.mintDark,
                background: AppColors.mint,
              ),
              PillItem(
                label: 'Edit',
                icon: Icons.edit_rounded,
                color: AppColors.textSecondary,
                background: AppColors.surface,
              ),
              const PillItem(
                label: 'Reject',
                icon: Icons.close_rounded,
                color: AppColors.coral,
                background: AppColors.riskHighBg,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sectionGap),
        ],
      ),
    );
  }
}

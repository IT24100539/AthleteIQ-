import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/checkin.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/async_body.dart';

class TrainingCalendarScreen extends StatelessWidget {
  final String athleteUid;

  const TrainingCalendarScreen({super.key, required this.athleteUid});

  @override
  Widget build(BuildContext context) {
    final fs = FirestoreService();
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Training calendar'),
        centerTitle: true,
      ),
      body: StreamBuilder<List<CheckIn>>(
        stream: fs.recentCheckIns(athleteUid, days: 35),
        builder: (context, snapshot) {
          final blocked = asyncBody(
            snapshot,
            heading: 'Could not load your calendar',
          );
          if (blocked != null) return blocked;

          final checkins = snapshot.data ?? [];

          // Map checkins by date key
          final checkinMap = <String, CheckIn>{};
          for (final c in checkins) {
            final key = DateFormat('yyyy-MM-dd').format(c.date);
            checkinMap[key] = c;
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.screenEdge),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat('MMMM yyyy').format(now),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 16),

                  // Calendar Grid
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.cardPadding),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      children: [
                        // Day of week headers
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _DowHeader('S'),
                            _DowHeader('M'),
                            _DowHeader('T'),
                            _DowHeader('W'),
                            _DowHeader('T'),
                            _DowHeader('F'),
                            _DowHeader('S'),
                          ],
                        ),
                        Divider(height: 24, color: AppColors.border),

                        // Monthly Days Matrix
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: 35, // 5 weeks x 7 days
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 7,
                            mainAxisSpacing: 4,
                            crossAxisSpacing: 4,
                            childAspectRatio: 1,
                          ),
                          itemBuilder: (ctx, i) {
                            final firstOfMonth = DateTime(now.year, now.month, 1);
                            final startOffset = firstOfMonth.weekday % 7;
                            final dayDate = firstOfMonth.add(Duration(days: i - startOffset));
                            final dateKey = DateFormat('yyyy-MM-dd').format(dayDate);

                            final isCurrentMonth = dayDate.month == now.month;
                            final isToday = dayDate.year == now.year &&
                                dayDate.month == now.month &&
                                dayDate.day == now.day;

                            final checkin = checkinMap[dateKey];
                            final isTrained = checkin != null && (checkin.sessionDurationMinutes ?? 0) > 0;
                            final isRest = checkin != null && (checkin.sessionDurationMinutes ?? 0) == 0;

                            return _CalendarDayCell(
                              day: dayDate.day,
                              isCurrentMonth: isCurrentMonth,
                              isToday: isToday,
                              isTrained: isTrained,
                              isRest: isRest,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Legend
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Flexible(
                        child: _LegendItem(
                          color: AppColors.mintTint,
                          label: 'Trained',
                        ),
                      ),
                      Flexible(
                        child: _LegendItem(
                          color: AppColors.calendarRest,
                          label: 'Rest',
                        ),
                      ),
                      Flexible(
                        child: _LegendItem(
                          color: AppColors.surface,
                          borderColor: AppColors.mint,
                          label: 'Today',
                        ),
                      ),
                    ],
                  ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DowHeader extends StatelessWidget {
  final String label;
  const _DowHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: AppColors.textMuted,
      ),
    );
  }
}

class _CalendarDayCell extends StatelessWidget {
  final int day;
  final bool isCurrentMonth;
  final bool isToday;
  final bool isTrained;
  final bool isRest;

  const _CalendarDayCell({
    required this.day,
    required this.isCurrentMonth,
    required this.isToday,
    required this.isTrained,
    required this.isRest,
  });

  @override
  Widget build(BuildContext context) {
    Color bg = AppColors.surfaceAlt;
    Border? border;

    if (isTrained) {
      bg = AppColors.mintTint;
    } else if (isRest) {
      bg = AppColors.calendarRest;
    }

    if (isToday) {
      border = Border.all(color: AppColors.mint, width: 1.5);
    }

    return Semantics(
      label: [
        'Day $day',
        if (isToday) 'today',
        if (isTrained) 'trained',
        if (isRest) 'rest',
      ].join(', '),
      child: Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isCurrentMonth ? bg : AppColors.background.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(4),
        border: border ?? Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: Text(
        '$day',
        style: TextStyle(
          fontSize: 13,
          fontWeight: isToday || isTrained ? FontWeight.w700 : FontWeight.w400,
          color: isCurrentMonth
              ? (isTrained ? AppColors.mint : AppColors.textPrimary)
              : AppColors.textFaint,
        ),
      ),
    ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final Color? borderColor;
  final String label;

  const _LegendItem({
    required this.color,
    this.borderColor,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: borderColor ?? Colors.transparent),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../utils/constants.dart';
import 'app_card.dart';

/// Hiển thị tần suất và nhịp độ chi tiêu theo tuần (Spending Rhythm)
class WeeklyHeatmapCard extends StatelessWidget {
  final Map<String, List<int>> heatmapData;

  const WeeklyHeatmapCard({super.key, required this.heatmapData});

  Color _cellColor(BuildContext context, int level) {
    final baseColor = Theme.of(context).colorScheme.primary;
    switch (level) {
      case 0:
        return context.appBorder.withValues(alpha: 0.35);
      case 1:
        return baseColor.withValues(alpha: 0.20);
      case 2:
        return baseColor.withValues(alpha: 0.45);
      case 3:
        return baseColor.withValues(alpha: 0.70);
      case 4:
        return baseColor;
      default:
        return context.appBorder.withValues(alpha: 0.35);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (heatmapData.isEmpty) {
      return const SizedBox.shrink();
    }

    // Tính tổng tần suất theo 7 ngày trong tuần
    final dailyTotals = List<int>.filled(7, 0);
    for (final values in heatmapData.values) {
      for (int i = 0; i < 7; i++) {
        if (i < values.length) {
          dailyTotals[i] += values[i];
        }
      }
    }

    int peakDayIndex = 0;
    int maxTotal = dailyTotals[0];
    for (int i = 1; i < 7; i++) {
      if (dailyTotals[i] > maxTotal) {
        maxTotal = dailyTotals[i];
        peakDayIndex = i;
      }
    }

    final totalScore = dailyTotals.fold<int>(0, (a, b) => a + b);
    final weekdayScore = dailyTotals.sublist(0, 5).fold<int>(0, (a, b) => a + b);
    final weekendScore = dailyTotals.sublist(5).fold<int>(0, (a, b) => a + b);

    final weekdayPct =
        totalScore > 0 ? (weekdayScore / totalScore * 100).round() : 70;
    final weekendPct =
        totalScore > 0 ? (weekendScore / totalScore * 100).round() : 30;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.calendar_view_week_rounded,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('heatmap_title'),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: context.appTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.tr('heatmap_subtitle'),
                      style: TextStyle(
                        fontSize: 12,
                        color: context.appTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 96),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: context.appBackground,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: context.appBorder),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      context.tr('heatmap_30_days'),
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: context.appTextSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Tóm tắt Highlights
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: context.appBackground,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.appBorder),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.bolt_rounded,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: context.tr('heatmap_peak_prefix')),
                        TextSpan(
                          text: context.tr('heatmap_day_$peakDayIndex'),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: context.appTextPrimary,
                          ),
                        ),
                        TextSpan(
                          text: context.tr(
                            'heatmap_weekday_weekend_ratio',
                            params: {
                              'weekday': '$weekdayPct',
                              'weekend': '$weekendPct',
                            },
                          ),
                          style: TextStyle(color: context.appTextSecondary),
                        ),
                      ],
                    ),
                    style: const TextStyle(fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Nhãn các thứ trong tuần
          Row(
            children: [
              const SizedBox(width: 80),
              ...List.generate(
                7,
                (i) => Expanded(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 2),
                      decoration: i == peakDayIndex
                          ? BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            )
                          : null,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            context.tr('heatmap_wd_$i'),
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: i == peakDayIndex
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: i == peakDayIndex
                                  ? Theme.of(context).colorScheme.primary
                                  : context.appTextSecondary,
                            ),
                          ),
                        ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Các hàng danh mục
          ...heatmapData.entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: Text(
                      entry.key,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: context.appTextPrimary,
                      ),
                    ),
                  ),
                  ...List.generate(
                    7,
                    (i) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2.5),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: Container(
                            decoration: BoxDecoration(
                              color: _cellColor(context, entry.value[i]),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: entry.value[i] > 0
                                    ? Colors.transparent
                                    : context.appBorder.withValues(alpha: 0.3),
                                width: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    context.tr('heatmap_low'),
                    maxLines: 1,
                    style: TextStyle(
                        fontSize: 11, color: context.appTextSecondary),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              ...List.generate(
                5,
                (i) => Container(
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: _cellColor(context, i),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    context.tr('heatmap_high'),
                    maxLines: 1,
                    style: TextStyle(
                        fontSize: 11, color: context.appTextSecondary),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

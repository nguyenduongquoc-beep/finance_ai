import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/trend_result.dart';
import '../utils/constants.dart';
import 'app_card.dart';

class TrendChartCard extends StatelessWidget {
  final TrendResult trendResult;

  const TrendChartCard({super.key, required this.trendResult});

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[];
    for (int i = 0; i < trendResult.monthlyAmounts.length; i++) {
      spots.add(FlSpot(i.toDouble(), trendResult.monthlyAmounts[i]));
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight.withAlpha(25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.show_chart_rounded, color: AppColors.primaryLight, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Xu hướng chi tiêu 6 tháng',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: context.appTextPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: context.appBorder),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                lineTouchData: const LineTouchData(enabled: true),
                gridData: const FlGridData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 45,
                      interval: _calcYInterval(),
                      getTitlesWidget: (val, meta) {
                        return Text(
                          _formatY(val),
                          style: TextStyle(fontSize: 10, color: context.appTextSecondary),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        if (value != value.toInt()) return const SizedBox();
                        final index = value.toInt();
                        if (index < 0 || index >= trendResult.monthlyAmounts.length) {
                          return const SizedBox();
                        }
                        final now = DateTime.now();
                        final month = DateTime(now.year, now.month - (trendResult.monthlyAmounts.length - 1 - index), 1);
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'Th${month.month}',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: context.appTextSecondary),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: (trendResult.monthlyAmounts.length - 1).toDouble(),
                minY: 0,
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: AppColors.primaryLight,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                        radius: 4,
                        color: AppColors.primaryLight,
                        strokeWidth: 2,
                        strokeColor: Colors.white,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: AppColors.primaryLight.withAlpha(30),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            trendResult.insight,
            style: TextStyle(
              height: 1.5,
              fontSize: 13,
              color: context.appTextPrimary,
            ),
          ),
        ],
      ),
    );
  }

  double _calcYInterval() {
    final max = trendResult.monthlyAmounts.isEmpty ? 0 : trendResult.monthlyAmounts.reduce((a, b) => a > b ? a : b);
    final interval = (max / 4).ceilToDouble();
    return interval > 0 ? interval : 1;
  }

  String _formatY(double val) {
    if (val >= 1000000) {
      return '${(val / 1000000).toStringAsFixed(1)}M';
    } else if (val >= 1000) {
      return '${(val / 1000).toStringAsFixed(0)}k';
    }
    return val.toStringAsFixed(0);
  }
}

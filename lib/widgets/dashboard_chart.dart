import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../utils/constants.dart';
import '../utils/formatters.dart';

/// Biểu đồ cột: Thu / Chi theo tháng (hỗ trợ chạm chọn tháng chuẩn Fintech)
class IncomeExpenseBarChart extends StatelessWidget {
  final List<double> incomeByMonth;
  final List<double> expenseByMonth;
  final List<String> monthLabels;
  final int selectedIndex;
  final void Function(int monthIndex) onMonthTap;

  const IncomeExpenseBarChart({
    super.key,
    required this.incomeByMonth,
    required this.expenseByMonth,
    required this.monthLabels,
    required this.selectedIndex,
    required this.onMonthTap,
  });

  @override
  Widget build(BuildContext context) {
    final maxVal = [...incomeByMonth, ...expenseByMonth].fold<double>(0, (a, b) => a > b ? a : b);
    final hasAnyData = maxVal > 0;
    final chartMaxY = hasAnyData ? maxVal * 1.25 : 1.0;

    return SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          maxY: chartMaxY,
          minY: 0,
          alignment: BarChartAlignment.spaceAround,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (group) =>
                  context.isDarkMode ? AppColors.slate800 : AppColors.slate900,
              tooltipRoundedRadius: 8,
              tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final isIncome = rodIndex == 0;
                final rawValue = (isIncome ? incomeByMonth : expenseByMonth)[groupIndex] * 1e6;
                return BarTooltipItem(
                  '${isIncome ? "Thu: " : "Chi: "}${AppFormatters.compactCurrency(rawValue, unit: '₫')}',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                );
              },
            ),
            touchCallback: (event, response) {
              if (event is FlTapUpEvent && response?.spot != null) {
                onMonthTap(response!.spot!.touchedBarGroupIndex);
              }
            },
          ),
          barGroups: List.generate(monthLabels.length, (i) {
            final isSelected = i == selectedIndex;
            final incVal = incomeByMonth[i];
            final expVal = expenseByMonth[i];

            return BarChartGroupData(
              x: i,
              barsSpace: 4,
              barRods: [
                BarChartRodData(
                  toY: incVal > 0 ? incVal : (hasAnyData ? 0 : 0.04),
                  color: isSelected
                      ? AppColors.income
                      : AppColors.income.withValues(alpha: hasAnyData ? 0.35 : 0.15),
                  width: 8.5,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                  borderSide: BorderSide.none,
                ),
                BarChartRodData(
                  toY: expVal > 0 ? expVal : (hasAnyData ? 0 : 0.04),
                  color: isSelected
                      ? AppColors.expense
                      : AppColors.expense.withValues(alpha: hasAnyData ? 0.35 : 0.15),
                  width: 8.5,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                  borderSide: BorderSide.none,
                ),
              ],
            );
          }),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= monthLabels.length) return const SizedBox();
                  final isSelected = i == selectedIndex;
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: GestureDetector(
                      onTap: () => onMonthTap(i),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: isSelected ? 6 : 2,
                          vertical: 2,
                        ),
                        decoration: isSelected
                            ? BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              )
                            : null,
                        child: Text(
                          monthLabels[i],
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected
                                ? (context.isDarkMode ? Colors.white : AppColors.primary)
                                : context.appTextSecondary,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            drawHorizontalLine: true,
            horizontalInterval: hasAnyData ? (chartMaxY / 3) : 0.5,
            getDrawingHorizontalLine: (value) => FlLine(
              color: context.isDarkMode
                  ? AppColors.slate700.withValues(alpha: 0.4)
                  : AppColors.slate200.withValues(alpha: 0.7),
              strokeWidth: 1,
              dashArray: [4, 4],
            ),
          ),
          borderData: FlBorderData(show: false),
        ),
      ),
    );
  }
}

/// Biểu đồ tròn: Tỷ lệ chi tiêu theo danh mục
class CategoryPieChart extends StatelessWidget {
  final Map<String, double> categoryTotals;
  final List<Color> colors;

  const CategoryPieChart({super.key, required this.categoryTotals, required this.colors});

  @override
  Widget build(BuildContext context) {
    final total = categoryTotals.values.fold<double>(0, (a, b) => a + b);
    final entries = categoryTotals.entries.toList();

    entries.sort((a, b) => b.value.compareTo(a.value));

    final List<int> percentages = List.filled(entries.length, 0);
    if (total > 0) {
      final List<double> rawPercentages = entries.map((e) => (e.value / total) * 100).toList();
      final List<int> floors = rawPercentages.map((p) => p.floor()).toList();
      final List<double> remainders = List.generate(entries.length, (i) => rawPercentages[i] - floors[i]);

      final int sumFloors = floors.fold<int>(0, (a, b) => a + b);
      final int difference = 100 - sumFloors;

      final List<int> indices = List.generate(entries.length, (i) => i);
      indices.sort((a, b) {
        final cmp = remainders[b].compareTo(remainders[a]);
        if (cmp != 0) return cmp;
        return entries[b].value.compareTo(entries[a].value);
      });

      for (int i = 0; i < difference; i++) {
        if (i < indices.length) {
          floors[indices[i]] += 1;
        }
      }

      for (int i = 0; i < entries.length; i++) {
        percentages[i] = floors[i];
      }
    }

    return SizedBox(
      height: 220,
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 40,
                    sections: List.generate(entries.length, (i) {
                      return PieChartSectionData(
                        value: entries[i].value,
                        color: colors[i % colors.length],
                        title: '',
                        radius: 55,
                      );
                    }),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Tổng', style: TextStyle(fontSize: 11, color: context.appTextSecondary)),
                    Text(
                      '100%',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.appTextPrimary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ListView.builder(
              itemCount: entries.length,
              itemBuilder: (context, i) {
                final percent = percentages[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: colors[i % colors.length],
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entries[i].key,
                          style: TextStyle(fontSize: 12, color: context.appTextPrimary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$percent%',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: context.appTextPrimary,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

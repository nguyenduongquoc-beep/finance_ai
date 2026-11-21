import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../utils/constants.dart';
import '../utils/formatters.dart';

/// Biểu đồ đường cong diện tích (Smooth Area Line Chart) hiển thị xu hướng chi tiêu 3 tháng gần nhất.
/// - Đường trung bình 3 tháng (Dashed line + nhãn `TB: ...`).
/// - Điểm đỉnh chi tiêu nổi bật và hỗ trợ chạm từng kỳ để đối chiếu chi tiết ở dải tóm tắt 3 cột.
class SpendingTrendBarChart extends StatefulWidget {
  final List<double> amounts;
  final List<String> monthLabels;
  final bool showLegend;

  const SpendingTrendBarChart({
    super.key,
    required this.amounts,
    required this.monthLabels,
    this.showLegend = true,
  });

  static Widget buildLegendDot(
    BuildContext context, {
    required Color color,
    required String label,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: context.appTextSecondary,
          ),
        ),
      ],
    );
  }

  @override
  State<SpendingTrendBarChart> createState() => _SpendingTrendBarChartState();
}

class _SpendingTrendBarChartState extends State<SpendingTrendBarChart> {
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.amounts.isNotEmpty ? widget.amounts.length - 1 : 0;
  }

  @override
  void didUpdateWidget(covariant SpendingTrendBarChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.amounts.isEmpty) {
      _selectedIndex = 0;
    } else if (_selectedIndex >= widget.amounts.length ||
        oldWidget.amounts.length != widget.amounts.length) {
      _selectedIndex = widget.amounts.length - 1;
    }
  }

  static String formatCompactAmount(double v) {
    if (v <= 0) return '0 ₫';
    if (v >= 1e9) {
      final b = v / 1e9;
      return b % 1 == 0 ? '${b.toInt()}B' : '${b.toStringAsFixed(1)}B';
    }
    if (v >= 1000000) {
      final m = v / 1000000;
      return m % 1 == 0 ? '${m.toInt()}M' : '${m.toStringAsFixed(1)}M';
    }
    if (v >= 1000) {
      final k = v / 1000;
      return k % 1 == 0 ? '${k.toInt()}K' : '${k.toStringAsFixed(1)}K';
    }
    return '${v.round()} ₫';
  }

  static String formatFullCurrency(double v) {
    if (v.abs() >= 1e9) {
      return AppFormatters.compactCurrency(v, unit: '₫');
    }
    return '${AppFormatters.number(v)} ₫';
  }

  @override
  Widget build(BuildContext context) {
    final amounts = widget.amounts;
    final monthLabels = widget.monthLabels;

    if (amounts.isEmpty || monthLabels.isEmpty) {
      return SizedBox(
        height: 150,
        child: Center(
          child: Text(
            context.tr('trend_no_data'),
            style: TextStyle(color: context.appTextSecondary, fontSize: 13),
          ),
        ),
      );
    }

    final count = math.min(amounts.length, monthLabels.length);
    final safeAmounts = amounts.sublist(0, count);
    final safeLabels = monthLabels.sublist(0, count);
    final selectedIdx = _selectedIndex.clamp(0, count - 1);

    final maxVal = safeAmounts.reduce((a, b) => a > b ? a : b);
    final avgVal = safeAmounts.fold<double>(0, (a, b) => a + b) / count;
    // Nếu có nhiều tháng cùng đạt đỉnh chi tiêu bằng nhau, ưu tiên tháng gần nhất
    int peakIndex = -1;
    if (maxVal > 0) {
      for (int i = count - 1; i >= 0; i--) {
        if (safeAmounts[i] == maxVal) {
          peakIndex = i;
          break;
        }
      }
    }
    final peakLabel = peakIndex >= 0 ? safeLabels[peakIndex] : '—';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showLegend)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 14,
                runSpacing: 4,
                children: [
                  SpendingTrendBarChart.buildLegendDot(
                    context,
                    color: AppColors.primary,
                    label: context.tr('trend_current_period'),
                  ),
                  SpendingTrendBarChart.buildLegendDot(
                    context,
                    color: AppColors.warning,
                    label: context.tr('trend_peak_spend'),
                  ),
                ],
              ),
            ),
          ),

        // Vùng vẽ biểu đồ đường cong + đường trung bình + các điểm nút
        SizedBox(
          height: 162,
          width: double.infinity,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _SpendingTrendAreaPainter(
                    amounts: safeAmounts,
                    maxVal: maxVal,
                    avgVal: avgVal,
                    peakIndex: peakIndex,
                    selectedIndex: selectedIdx,
                    lineColor: AppColors.primary,
                    peakColor: AppColors.warning,
                    cardColor: context.appCard,
                    baselineColor: context.appBorder,
                    dashedLineColor: context.appTextSecondary
                        .withValues(alpha: context.isDarkMode ? 0.55 : 0.45),
                    textPrimary: context.appTextPrimary,
                    textSecondary: context.appTextSecondary,
                    valueLabels:
                        safeAmounts.map(formatCompactAmount).toList(),
                    avgLabel: avgVal > 0 && maxVal > 0
                        ? context.tr(
                            'trend_avg_short',
                            params: {'amount': formatCompactAmount(avgVal)},
                          )
                        : null,
                    isDarkMode: context.isDarkMode,
                  ),
                ),
              ),
              // Vùng chạm vô hình chia đều theo từng cột tháng
              Positioned.fill(
                child: Row(
                  children: List.generate(count, (i) {
                    return Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _selectedIndex = i),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 4),

        // Hàng nhãn tháng ngay dưới đường nền
        Row(
          children: List.generate(count, (i) {
            final isCurrent = i == count - 1;
            final isSelected = i == selectedIdx;
            final pillLabel = isCurrent
                ? context.tr(
                    'trend_bar_current_label',
                    params: {'label': safeLabels[i]},
                  )
                : safeLabels[i];

            return Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _selectedIndex = i),
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: EdgeInsets.symmetric(
                      horizontal: (isCurrent || isSelected) ? 10 : 6,
                      vertical: 4.5,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary.withValues(
                              alpha: context.isDarkMode ? 0.28 : 0.14,
                            )
                          : (isCurrent
                              ? AppColors.primary.withValues(
                                  alpha: context.isDarkMode ? 0.14 : 0.07,
                                )
                              : Colors.transparent),
                      borderRadius: BorderRadius.circular(20),
                      border: isSelected && !isCurrent
                          ? Border.all(
                              color: AppColors.primary.withValues(alpha: 0.35),
                              width: 1,
                            )
                          : null,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        pillLabel,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: (isCurrent || isSelected)
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: (isCurrent || isSelected)
                              ? (context.isDarkMode
                                  ? Colors.white
                                  : const Color(0xFF123C4C))
                              : context.appTextSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),

        const SizedBox(height: 16),

        // Dải tóm tắt 3 cột thống nhất với vạch chia dọc thanh mảnh
        _buildUnifiedSummaryStrip(
          context,
          selectedLabel: safeLabels[selectedIdx],
          selectedAmount: safeAmounts[selectedIdx],
          isCurrent: selectedIdx == count - 1,
          avgVal: avgVal,
          maxVal: maxVal,
          peakLabel: peakLabel,
        ),
      ],
    );
  }

  Widget _buildUnifiedSummaryStrip(
    BuildContext context, {
    required String selectedLabel,
    required double selectedAmount,
    required bool isCurrent,
    required double avgVal,
    required double maxVal,
    required String peakLabel,
  }) {
    final double? diffFromAvg =
        avgVal > 0 ? ((selectedAmount - avgVal) / avgVal) * 100 : null;
    final int? roundedDiff = diffFromAvg?.round();

    final String comparisonText;
    if (avgVal <= 0) {
      comparisonText = context.tr('trend_no_3m_data');
    } else if (roundedDiff == 0) {
      comparisonText = context.tr('trend_equal_3m_avg');
    } else if (diffFromAvg! > 0) {
      comparisonText = context.tr('trend_above_3m_avg');
    } else {
      comparisonText = context.tr('trend_below_3m_avg');
    }

    // Phối màu chuẩn Finance AI: chi tiêu thấp hơn TB -> xanh (tích cực), cao hơn TB -> đỏ/cảnh báo
    final bool isBetterOrEqual = roundedDiff != null && roundedDiff <= 0;
    final Color badgeTextColor =
        isBetterOrEqual ? AppColors.income : AppColors.expense;
    final Color badgeBgColor = context.isDarkMode
        ? badgeTextColor.withValues(alpha: 0.18)
        : (isBetterOrEqual
            ? AppColors.incomeBackground
            : AppColors.expenseBackground);

    final Widget selectedColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: selectedLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: context.appTextPrimary,
                  ),
                ),
                if (isCurrent)
                  TextSpan(
                    text: context.tr('trend_current_paren'),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: context.appTextSecondary,
                    ),
                  ),
              ],
            ),
            maxLines: 1,
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                formatFullCurrency(selectedAmount),
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: context.appTextPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (roundedDiff != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: badgeBgColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${roundedDiff > 0 ? '+' : ''}$roundedDiff%',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: badgeTextColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 3),
        Text(
          comparisonText,
          style: TextStyle(
            fontSize: 11,
            color: context.appTextSecondary,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );

    final Widget avgColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          context.tr('trend_3m_avg_title'),
          style: TextStyle(
            fontSize: 11.5,
            color: context.appTextSecondary,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            avgVal > 0
                ? '${formatCompactAmount(avgVal)}${context.tr('trend_per_month')}'
                : context.tr('trend_zero_per_month'),
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: context.appTextPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );

    final Widget peakColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          context.tr('trend_peak_spend'),
          style: TextStyle(
            fontSize: 11.5,
            color: context.appTextSecondary,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            maxVal > 0
                ? '$peakLabel (${formatCompactAmount(maxVal)})'
                : context.tr('trend_none'),
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: context.appTextPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      decoration: BoxDecoration(
        color: context.isDarkMode
            ? AppColors.slate900.withValues(alpha: 0.42)
            : AppColors.slate50.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.appBorder),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Trên màn hình chuẩn (>= 275px bên trong strip): hiển thị đủ 3 cột chia bởi hairline dọc như thiết kế
          if (constraints.maxWidth >= 275) {
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 15,
                    child: selectedColumn,
                  ),
                  VerticalDivider(
                    width: 12,
                    thickness: 1,
                    indent: 2,
                    endIndent: 2,
                    color: context.appBorder,
                  ),
                  Expanded(
                    flex: 9,
                    child: avgColumn,
                  ),
                  VerticalDivider(
                    width: 12,
                    thickness: 1,
                    indent: 2,
                    endIndent: 2,
                    color: context.appBorder,
                  ),
                  Expanded(
                    flex: 11,
                    child: peakColumn,
                  ),
                ],
              ),
            );
          }

          // Fallback an toàn cho màn hình siêu hẹp hoặc phóng to chữ hệ thống quá lớn
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              selectedColumn,
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Divider(height: 1, color: context.appBorder),
              ),
              IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(child: avgColumn),
                    VerticalDivider(
                      width: 16,
                      thickness: 1,
                      color: context.appBorder,
                    ),
                    Expanded(child: peakColumn),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SpendingTrendAreaPainter extends CustomPainter {
  final List<double> amounts;
  final double maxVal;
  final double avgVal;
  final int peakIndex;
  final int selectedIndex;
  final Color lineColor;
  final Color peakColor;
  final Color cardColor;
  final Color baselineColor;
  final Color dashedLineColor;
  final Color textPrimary;
  final Color textSecondary;
  final List<String> valueLabels;
  final String? avgLabel;
  final bool isDarkMode;

  _SpendingTrendAreaPainter({
    required this.amounts,
    required this.maxVal,
    required this.avgVal,
    required this.peakIndex,
    required this.selectedIndex,
    required this.lineColor,
    required this.peakColor,
    required this.cardColor,
    required this.baselineColor,
    required this.dashedLineColor,
    required this.textPrimary,
    required this.textSecondary,
    required this.valueLabels,
    required this.avgLabel,
    required this.isDarkMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final count = amounts.length;
    if (count == 0 || size.width <= 0 || size.height <= 0) return;

    const double topPadding = 34.0;
    const double bottomPadding = 12.0;
    final double baselineY = size.height - bottomPadding;
    final double plotHeight = math.max(24.0, baselineY - topPadding);

    // Tọa độ X của mỗi điểm khớp đúng tâm của từng cột nhãn tháng bên dưới
    final double colW = size.width / count;
    final List<Offset> points = List.generate(count, (i) {
      final double x = (i + 0.5) * colW;
      final double ratio =
          maxVal <= 0 ? 0.0 : (amounts[i] / maxVal).clamp(0.0, 1.0);
      final double y = baselineY - ratio * plotHeight;
      return Offset(x, y);
    });

    // 1. Vẽ đường nền (0 đ) kéo dài toàn chiều ngang vùng biểu đồ
    final baselinePaint = Paint()
      ..color = baselineColor
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(0, baselineY),
      Offset(size.width, baselineY),
      baselinePaint,
    );

    // 2. Vẽ đường trung bình 3 tháng (Dashed line) & nhãn "TB: ..." ở mép trái
    double? avgY;
    if (maxVal > 0 && avgVal > 0) {
      final double avgRatio = (avgVal / maxVal).clamp(0.0, 1.0);
      avgY = baselineY - avgRatio * plotHeight;

      final dashedPaint = Paint()
        ..color = dashedLineColor
        ..strokeWidth = 1.15
        ..style = PaintingStyle.stroke;

      const dashW = 4.0;
      const dashGap = 4.0;
      double startX = 0;
      while (startX < size.width) {
        canvas.drawLine(
          Offset(startX, avgY),
          Offset(math.min(startX + dashW, size.width), avgY),
          dashedPaint,
        );
        startX += dashW + dashGap;
      }

      if (avgLabel != null) {
        final avgPainter = TextPainter(
          text: TextSpan(
            text: avgLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout();

        // Đặt nhãn ngay phía trên đường đứt nét bên trái
        final double labelY = math.max(2.0, avgY - avgPainter.height - 4.0);
        avgPainter.paint(canvas, Offset(2.0, labelY));
      }
    }

    // 3. Tạo đường cong Monotone Cubic Hermite (đảm bảo không bị võng xuống âm khi 2 điểm = 0)
    final Path curvePath = _buildMonotoneSplinePath(points);

    // 4. Vẽ vùng gradient mờ phía dưới đường cong
    if (points.length >= 2 && maxVal > 0) {
      final Path fillPath = Path.from(curvePath)
        ..lineTo(points.last.dx, baselineY)
        ..lineTo(points.first.dx, baselineY)
        ..close();

      final Rect gradientBounds = Rect.fromLTRB(
        points.first.dx,
        topPadding,
        points.last.dx,
        baselineY,
      );

      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            lineColor.withValues(alpha: isDarkMode ? 0.28 : 0.18),
            lineColor.withValues(alpha: 0.01),
          ],
        ).createShader(gradientBounds)
        ..style = PaintingStyle.fill;

      canvas.drawPath(fillPath, fillPaint);
    }

    // 5. Vẽ đường cong chính
    final strokePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(curvePath, strokePaint);

    // 6. Vẽ các điểm nút tròn + nhãn giá trị phía trên mỗi điểm
    for (int i = 0; i < count; i++) {
      final pt = points[i];
      final bool isPeak = i == peakIndex && maxVal > 0;
      final bool isSelected = i == selectedIndex;

      // Vòng sáng nhẹ khi điểm đang được chọn
      if (isSelected) {
        final haloPaint = Paint()
          ..color = (isPeak ? peakColor : lineColor).withValues(alpha: 0.18)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(pt, 9.5, haloPaint);
      }

      if (isPeak) {
        // Điểm Đỉnh chi tiêu: lõi vàng hổ phách + viền tối tinh tế giống thiết kế
        final outerRing = Paint()
          ..color = lineColor
          ..style = PaintingStyle.fill;
        final innerDot = Paint()
          ..color = peakColor
          ..style = PaintingStyle.fill;
        canvas.drawCircle(pt, 5.5, outerRing);
        canvas.drawCircle(pt, 3.3, innerDot);
      } else {
        // Điểm thường / kỳ 0đ: nền card + viền Petrol
        final fillPaint = Paint()
          ..color = isSelected ? lineColor : cardColor
          ..style = PaintingStyle.fill;
        final borderPaint = Paint()
          ..color = lineColor
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke;
        canvas.drawCircle(pt, isSelected ? 5.0 : 4.2, fillPaint);
        canvas.drawCircle(pt, isSelected ? 5.0 : 4.2, borderPaint);
      }

      // Nhãn giá trị phía trên từng nút
      final bool emphasize = isPeak || isSelected || amounts[i] > 0;
      final valuePainter = TextPainter(
        text: TextSpan(
          text: valueLabels[i],
          style: TextStyle(
            fontSize: (isPeak || isSelected) ? 13 : 12,
            fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
            color: textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout();

      final double clampedX = (pt.dx - valuePainter.width / 2)
          .clamp(2.0, math.max(2.0, size.width - valuePainter.width - 2.0));
      double labelY = pt.dy - valuePainter.height - 9.0;

      // Tránh nhãn điểm bị chạm vào đường trung bình nếu nằm sát nhau
      if (avgY != null &&
          (labelY + valuePainter.height > avgY - 2 && labelY < avgY + 2) &&
          i > 0) {
        labelY = math.max(2.0, avgY - valuePainter.height - 6.0);
      }
      labelY = labelY.clamp(2.0, math.max(2.0, baselineY - valuePainter.height - 6.0));

      valuePainter.paint(canvas, Offset(clampedX, labelY));
    }
  }

  /// Thuật toán Fritsch-Carlson Monotone Cubic Hermite giúp đường cong mượt,
  /// không bị vồng vượt đỉnh hoặc võng âm dưới 0 giữa 2 tháng có cùng giá trị.
  Path _buildMonotoneSplinePath(List<Offset> pts) {
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    final int n = pts.length;
    if (n < 2) return path;
    if (n == 2) {
      path.lineTo(pts[1].dx, pts[1].dy);
      return path;
    }

    final List<double> dx = List<double>.filled(n - 1, 0);
    final List<double> d = List<double>.filled(n - 1, 0);
    for (int i = 0; i < n - 1; i++) {
      dx[i] = math.max(1e-6, pts[i + 1].dx - pts[i].dx);
      d[i] = (pts[i + 1].dy - pts[i].dy) / dx[i];
    }

    final List<double> m = List<double>.filled(n, 0);
    m[0] = d[0];
    m[n - 1] = d[n - 2];

    for (int i = 1; i < n - 1; i++) {
      if (d[i - 1] * d[i] <= 0) {
        m[i] = 0;
      } else {
        m[i] = 2 * d[i - 1] * d[i] / (d[i - 1] + d[i]);
      }
    }

    for (int i = 0; i < n - 1; i++) {
      if (d[i].abs() < 1e-9) {
        m[i] = 0;
        m[i + 1] = 0;
      } else {
        final double alpha = m[i] / d[i];
        final double beta = m[i + 1] / d[i];
        final double h = alpha * alpha + beta * beta;
        if (h > 9.0) {
          final double tau = 3.0 / math.sqrt(h);
          m[i] = tau * alpha * d[i];
          m[i + 1] = tau * beta * d[i];
        }
      }
    }

    for (int i = 0; i < n - 1; i++) {
      final double segDx = dx[i] / 3.0;
      final double c1x = pts[i].dx + segDx;
      final double c1y = pts[i].dy + m[i] * segDx;
      final double c2x = pts[i + 1].dx - segDx;
      final double c2y = pts[i + 1].dy - m[i + 1] * segDx;

      path.cubicTo(
        c1x,
        c1y,
        c2x,
        c2y,
        pts[i + 1].dx,
        pts[i + 1].dy,
      );
    }

    return path;
  }

  @override
  bool shouldRepaint(covariant _SpendingTrendAreaPainter oldDelegate) {
    return oldDelegate.amounts != amounts ||
        oldDelegate.maxVal != maxVal ||
        oldDelegate.avgVal != avgVal ||
        oldDelegate.peakIndex != peakIndex ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.peakColor != peakColor ||
        oldDelegate.cardColor != cardColor ||
        oldDelegate.isDarkMode != isDarkMode;
  }
}

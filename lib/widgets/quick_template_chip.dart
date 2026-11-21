import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';
import '../models/quick_template.dart';
import '../utils/constants.dart';
import '../utils/formatters.dart';

/// Chip mẫu giao dịch nhanh phong cách Fintech.
/// - Chạm 1 lần (`onSelect`): áp dụng mẫu vào biểu mẫu giao dịch.
/// - Nhấn giữ (`onLongPress`): mở hộp thoại xác nhận xóa mẫu (không kích hoạt `onSelect`).
class QuickTemplateChip extends StatelessWidget {
  final QuickTemplate template;
  final void Function(QuickTemplate) onSelect;
  final void Function(QuickTemplate)? onLongPress;
  final double? maxWidth;
  final double? minWidth;

  const QuickTemplateChip({
    super.key,
    required this.template,
    required this.onSelect,
    this.onLongPress,
    this.maxWidth,
    this.minWidth,
  });

  @override
  Widget build(BuildContext context) {
    final isIncome = template.type == 'income';
    final color = isIncome ? AppColors.income : AppColors.expense;

    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: minWidth ?? 48,
        maxWidth: maxWidth ?? 140,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => onSelect(template),
          onLongPress: onLongPress != null
              ? () {
                  HapticFeedback.mediumImpact();
                  onLongPress!(template);
                }
              : null,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: color.withAlpha(18),
              border: Border.all(color: color.withAlpha(65), width: 1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        template.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: context.appTextPrimary,
                          height: 1.15,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    AppFormatters.compactCurrency(template.amount),
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: color,
                      height: 1.15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bộ tính toán kích thước và phân trang động cho danh sách Mẫu nhanh.
class QuickTemplateLayoutHelper {
  static const double chipSpacing = 6.0;
  static const double navButtonWidth = 28.0;
  static const double navReserveSingle = navButtonWidth + chipSpacing;
  static const double navReserveDouble = 2 * (navButtonWidth + chipSpacing);

  /// Ước tính chiều rộng hợp lý của 1 tag dựa trên nội dung thực tế, cỡ chữ và chiều rộng màn hình.
  static double estimateChipWidth(
    QuickTemplate template, {
    required double availableWidth,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    const double titleFontSize = 11.5;
    const double amountFontSize = 10.5;

    final titlePainter = TextPainter(
      text: TextSpan(
        text: template.title,
        style: const TextStyle(
            fontSize: titleFontSize, fontWeight: FontWeight.w600),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout();

    final amountText = AppFormatters.compactCurrency(template.amount);
    final amountPainter = TextPainter(
      text: TextSpan(
        text: amountText,
        style: const TextStyle(
            fontSize: amountFontSize, fontWeight: FontWeight.w700),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout();

    final double scale = textScaler.scale(1.0);
    // Chuẩn hóa độ rộng chữ để hoạt động chính xác cả với font thực tế (Inter/Roboto) và font Ahem khi chạy test
    final double realisticTitleWidth = math.min(
      titlePainter.width,
      template.title.runes.length * titleFontSize * 0.58 * scale,
    );
    final double realisticAmountWidth = math.min(
      amountPainter.width,
      amountText.runes.length * amountFontSize * 0.56 * scale,
    );

    // 5px dot + 4px gap = 9px cho dòng tiêu đề; 8*2 padding + 2 border = 18px
    final double naturalTitleRowWidth = realisticTitleWidth + 9.0 + 18.0;
    final double naturalAmountRowWidth = realisticAmountWidth + 18.0;
    final double rawWidth =
        math.max(naturalTitleRowWidth, naturalAmountRowWidth);

    final double safeAvailable = math.max(120.0, availableWidth);
    final double maxTitleCap = (safeAvailable * 0.40).clamp(80.0, 132.0);
    // Đảm bảo số tiền không bao giờ bị ép quá nhỏ
    final double effectiveMax = math.max(
      maxTitleCap,
      naturalAmountRowWidth.clamp(50.0, safeAvailable * 0.55),
    );

    return rawWidth.clamp(50.0, effectiveMax);
  }

  /// Chia danh sách mẫu nhanh thành các nhóm (trang) dựa trên chiều rộng thực tế.
  /// - Tận dụng tối đa bề ngang cho mỗi lần lướt (lên tới 6 tag ngắn hoặc 3-5 tag vừa/dài).
  /// - Tính cả diện tích của nút điều hướng `[←]` và `[→]` để không bao giờ tràn màn hình.
  static List<List<QuickTemplate>> paginateTemplates({
    required List<QuickTemplate> templates,
    required double availableWidth,
    TextScaler textScaler = TextScaler.noScaling,
    int maxItemsPerGroup = 6,
  }) {
    if (templates.isEmpty) return const [];
    final double safeWidth = math.max(140.0, availableWidth);

    final List<double> widths = templates
        .map((t) => estimateChipWidth(
              t,
              availableWidth: safeWidth,
              textScaler: textScaler,
            ))
        .toList();

    // Kiểm tra nếu tất cả các tag đều nằm gọn trong 1 nhóm duy nhất (không cần nút điều hướng)
    if (templates.length <= maxItemsPerGroup) {
      double totalWidth = 0;
      for (int i = 0; i < widths.length; i++) {
        totalWidth += (i == 0 ? 0 : chipSpacing) + widths[i];
      }
      if (totalWidth <= safeWidth) {
        return [templates];
      }
    }

    final List<List<QuickTemplate>> groups = [];
    int index = 0;

    while (index < templates.length) {
      final bool isFirstGroup = groups.isEmpty;

      // Nếu không phải nhóm đầu, kiểm tra xem toàn bộ phần còn lại có vừa khít nhóm cuối không (chỉ cần nút `[←]`)
      if (!isFirstGroup) {
        final int remainingCount = templates.length - index;
        if (remainingCount <= maxItemsPerGroup) {
          double remainingWidth = 0;
          for (int j = index; j < templates.length; j++) {
            remainingWidth += (j == index ? 0 : chipSpacing) + widths[j];
          }
          final double lastGroupBudget =
              math.max(60.0, safeWidth - navReserveSingle);
          if (remainingWidth <= lastGroupBudget) {
            groups.add(templates.sublist(index));
            break;
          }
        }
      }

      // Nhóm đầu chỉ cần nút `[→]`; nhóm giữa cần cả `[←]` và `[→]`
      final double groupBudget = isFirstGroup
          ? math.max(60.0, safeWidth - navReserveSingle)
          : math.max(60.0, safeWidth - navReserveDouble);

      final List<QuickTemplate> currentGroup = [];
      double usedWidth = 0;

      while (
          index < templates.length && currentGroup.length < maxItemsPerGroup) {
        final double w = widths[index];
        final double nextWidth =
            currentGroup.isEmpty ? w : (usedWidth + chipSpacing + w);

        if (nextWidth <= groupBudget || currentGroup.isEmpty) {
          currentGroup.add(templates[index]);
          usedWidth = nextWidth;
          index++;
        } else {
          break;
        }
      }

      groups.add(currentGroup);
    }

    return groups;
  }
}

/// Hiển thị hộp thoại xác nhận xóa mẫu nhanh chuyên nghiệp.
Future<bool> showDeleteQuickTemplateDialog(
  BuildContext context,
  QuickTemplate template,
) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          const Icon(Icons.delete_outline_rounded,
              color: AppColors.expense, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.tr('qt_delete_title'),
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      content: Text(
        context.tr(
          'qt_delete_content',
          params: {'title': template.title},
        ),
        style: TextStyle(
          fontSize: 14,
          color: context.appTextPrimary,
          height: 1.4,
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(
            context.tr('common_cancel'),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: context.appTextSecondary,
            ),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.expense,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(
            context.tr('common_delete'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
  return result == true;
}

/// Khu vực hiển thị Mẫu nhanh kết hợp:
/// - Kéo trườn ngang bằng tay (`PageView` + `BouncingScrollPhysics`)
/// - Nút điều hướng nhanh `[←]` và `[→]`
/// - Co giãn lấp đầy khoảng trống thông minh để không bị hở khoảng trống lớn
/// - Nhấn giữ để xóa mẫu
class QuickTemplatePaginatedBar extends StatefulWidget {
  final List<QuickTemplate> templates;
  final void Function(QuickTemplate) onSelect;
  final Future<void> Function(QuickTemplate)? onDelete;

  const QuickTemplatePaginatedBar({
    super.key,
    required this.templates,
    required this.onSelect,
    this.onDelete,
  });

  @override
  State<QuickTemplatePaginatedBar> createState() =>
      _QuickTemplatePaginatedBarState();
}

class _QuickTemplatePaginatedBarState extends State<QuickTemplatePaginatedBar> {
  int _currentPage = 0;
  late PageController _pageController;
  final Set<String> _optimisticDeletedIds = <String>{};
  bool _isConfirmingDelete = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentPage);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _handleLongPress(QuickTemplate template) async {
    if (_isConfirmingDelete || widget.onDelete == null) return;
    _isConfirmingDelete = true;
    try {
      final confirmed = await showDeleteQuickTemplateDialog(context, template);
      if (!confirmed || !mounted) return;

      setState(() {
        _optimisticDeletedIds.add(template.id);
      });

      try {
        await widget.onDelete!(template);
      } catch (e) {
        if (mounted) {
          setState(() {
            _optimisticDeletedIds.remove(template.id);
          });
        }
        rethrow;
      }
    } finally {
      _isConfirmingDelete = false;
    }
  }

  void _goToPage(int targetPage, int maxPage) {
    final clamped = targetPage.clamp(0, maxPage);
    if (clamped == _currentPage) return;
    HapticFeedback.selectionClick();
    setState(() {
      _currentPage = clamped;
    });
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        clamped,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleTemplates = widget.templates
        .where((t) => !_optimisticDeletedIds.contains(t.id))
        .toList();

    if (visibleTemplates.isEmpty) {
      return const SizedBox.shrink();
    }

    final textScaler = MediaQuery.textScalerOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final double availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width - 32;

        final groups = QuickTemplateLayoutHelper.paginateTemplates(
          templates: visibleTemplates,
          availableWidth: availableWidth,
          textScaler: textScaler,
        );

        if (groups.isEmpty) return const SizedBox.shrink();

        final int maxPageIndex = groups.length - 1;
        final int safePage = _currentPage.clamp(0, maxPageIndex);
        if (safePage != _currentPage) {
          // Tự điều chỉnh về nhóm hợp lệ gần nhất khi xóa hết mẫu ở trang cuối
          _currentPage = safePage;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _pageController.hasClients) {
              _pageController.jumpToPage(safePage);
            }
          });
        }

        final bool hasPrev = safePage > 0;
        final bool hasNext = safePage < maxPageIndex;
        final double barHeight =
            math.max(44.0, 42.0 * textScaler.scale(1.0).clamp(1.0, 1.35));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 2, right: 2, bottom: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            context.tr('qt_section_header'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                              color: context.appTextSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            context.tr('qt_section_hint'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                              color: context.appTextSecondary.withAlpha(180),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (groups.length > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: context.appInputFill,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: context.appBorder),
                      ),
                      child: Text(
                        '${safePage + 1}/${groups.length}',
                        key: const ValueKey('template_group_indicator'),
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: context.appTextSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: barHeight,
              child: Row(
                mainAxisSize: MainAxisSize.max,
                children: [
                  if (hasPrev) ...[
                    _TemplateNavButton(
                      key: const ValueKey('template_nav_prev'),
                      icon: Icons.arrow_back_rounded,
                      tooltip: context.tr('qt_prev_tooltip'),
                      height: barHeight,
                      onTap: () => _goToPage(safePage - 1, maxPageIndex),
                    ),
                    const SizedBox(width: QuickTemplateLayoutHelper.chipSpacing),
                  ],
                  Expanded(
                    key: const ValueKey('template_pageview_slot'),
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(
                        dragDevices: {
                          PointerDeviceKind.touch,
                          PointerDeviceKind.mouse,
                          PointerDeviceKind.trackpad,
                          PointerDeviceKind.stylus,
                        },
                      ),
                      child: PageView.builder(
                        key: const ValueKey('template_pageview'),
                        controller: _pageController,
                        physics: groups.length > 1
                            ? const BouncingScrollPhysics()
                            : const NeverScrollableScrollPhysics(),
                        itemCount: groups.length,
                        onPageChanged: (index) {
                          if (index != _currentPage && mounted) {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _currentPage = index;
                            });
                          }
                        },
                        itemBuilder: (context, pageIdx) {
                          final group = groups[pageIdx];
                          return LayoutBuilder(
                            builder: (context, pageConstraints) {
                              final pageWidth = pageConstraints.maxWidth;
                              final estimatedWidths = group
                                  .map(
                                    (t) => QuickTemplateLayoutHelper
                                        .estimateChipWidth(
                                      t,
                                      availableWidth: availableWidth,
                                      textScaler: textScaler,
                                    ),
                                  )
                                  .toList();
                              final totalSpacing = math.max(
                                0.0,
                                (group.length - 1) *
                                    QuickTemplateLayoutHelper.chipSpacing,
                              );
                              final totalNaturalWidth = estimatedWidths.fold<
                                      double>(0.0, (a, b) => a + b) +
                                  totalSpacing;

                              // Nếu trang có từ 3 tag trở lên hoặc tổng độ rộng tự nhiên đã chiếm >= 60% khung,
                              // cho các tag tự co giãn theo tỷ lệ để lấp kín vừa vặn bề ngang, không hở khoảng trống lớn.
                              final bool fillRowWidth = group.length >= 3 ||
                                  totalNaturalWidth >= pageWidth * 0.60;

                              return Container(
                                width: double.infinity,
                                height: double.infinity,
                                color: Colors.transparent,
                                alignment: Alignment.centerLeft,
                                child: Row(
                                  mainAxisSize: fillRowWidth
                                      ? MainAxisSize.max
                                      : MainAxisSize.min,
                                  children: [
                                    for (int i = 0; i < group.length; i++) ...[
                                      if (i > 0)
                                        const SizedBox(
                                          width: QuickTemplateLayoutHelper
                                              .chipSpacing,
                                        ),
                                      if (fillRowWidth)
                                        Expanded(
                                          flex: math.max(
                                            10,
                                            (estimatedWidths[i] * 10).round(),
                                          ),
                                          child: QuickTemplateChip(
                                            key: ValueKey(
                                                'quick_template_${group[i].id}'),
                                            template: group[i],
                                            minWidth: 0,
                                            maxWidth: double.infinity,
                                            onSelect: (tmpl) {
                                              if (_isConfirmingDelete) return;
                                              widget.onSelect(tmpl);
                                            },
                                            onLongPress: widget.onDelete != null
                                                ? _handleLongPress
                                                : null,
                                          ),
                                        )
                                      else
                                        Flexible(
                                          fit: FlexFit.loose,
                                          child: QuickTemplateChip(
                                            key: ValueKey(
                                                'quick_template_${group[i].id}'),
                                            template: group[i],
                                            maxWidth: math.min(
                                              pageWidth,
                                              estimatedWidths[i] + 16,
                                            ),
                                            onSelect: (tmpl) {
                                              if (_isConfirmingDelete) return;
                                              widget.onSelect(tmpl);
                                            },
                                            onLongPress: widget.onDelete != null
                                                ? _handleLongPress
                                                : null,
                                          ),
                                        ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),
                  if (hasNext) ...[
                    const SizedBox(width: QuickTemplateLayoutHelper.chipSpacing),
                    _TemplateNavButton(
                      key: const ValueKey('template_nav_next'),
                      icon: Icons.arrow_forward_rounded,
                      tooltip: context.tr('qt_next_tooltip'),
                      height: barHeight,
                      onTap: () => _goToPage(safePage + 1, maxPageIndex),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TemplateNavButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double height;

  const _TemplateNavButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.height = 42,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: context.appInputFill,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: QuickTemplateLayoutHelper.navButtonWidth,
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.appBorder, width: 1),
            ),
            child: Icon(
              icon,
              size: 16,
              color: AppColors.primaryLight,
            ),
          ),
        ),
      ),
    );
  }
}

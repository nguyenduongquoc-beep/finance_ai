import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/constants.dart';
import '../utils/formatters.dart';

/// Bottom-sheet bàn phím số tùy chỉnh hiện đại, tối ưu cho nhập tiền tệ fintech.
class CustomNumpad extends StatefulWidget {
  final String initialValue;
  final String? title;

  const CustomNumpad({
    super.key,
    this.initialValue = '',
    this.title,
  });

  @override
  State<CustomNumpad> createState() => _CustomNumpadState();
}

class _CustomNumpadState extends State<CustomNumpad> {
  late String _raw; // Dạng chuỗi chỉ gồm các chữ số

  @override
  void initState() {
    super.initState();
    _raw = AppFormatters.parseCurrencyInput(widget.initialValue)
        .toStringAsFixed(0)
        .replaceAll(RegExp(r'\.0$'), '');
    if (_raw == '0') _raw = '';
  }

  double get _numericValue => double.tryParse(_raw) ?? 0;

  String get _display {
    if (_raw.isEmpty) return '0';
    return AppFormatters.number(_numericValue);
  }

  void _onKey(String key) {
    HapticFeedback.selectionClick();
    setState(() {
      if (key == 'DEL') {
        if (_raw.isNotEmpty) {
          _raw = _raw.substring(0, _raw.length - 1);
        }
      } else if (key == 'C') {
        _raw = '';
      } else if (key == '000') {
        if (_raw.isNotEmpty) {
          _raw += '000';
        }
      } else if (key == '00') {
        if (_raw.isNotEmpty) {
          _raw += '00';
        }
      } else {
        if (_raw == '0') {
          _raw = key;
        } else {
          _raw += key;
        }
      }
      if (_raw.length > 15) _raw = _raw.substring(0, 15);
    });
  }

  void _addQuickAmount(double amount) {
    HapticFeedback.lightImpact();
    setState(() {
      final current = _numericValue;
      final updated = current + amount;
      _raw = updated.toStringAsFixed(0);
      if (_raw.length > 15) _raw = _raw.substring(0, 15);
    });
  }

  void _confirm() {
    HapticFeedback.mediumImpact();
    final value = _numericValue;
    if (value <= 0) {
      Navigator.of(context).pop<String>(null);
      return;
    }
    Navigator.of(context).pop<String>(AppFormatters.number(value));
  }

  @override
  Widget build(BuildContext context) {
    final value = _numericValue;

    return Container(
      decoration: BoxDecoration(
        color: context.appCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Thanh kéo drag handle
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: context.appBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // Tiêu đề nếu có
                if (widget.title != null) ...[
                  Text(
                    widget.title!,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.appTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                // Khung hiển thị số tiền lớn (Chống tràn viền tự động với FittedBox)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: context.appInputFill,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: context.appBorder, width: 1.2),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Text(
                                '$_display ₫',
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primaryLight,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ),
                            if (value >= 1e6) ...[
                              const SizedBox(height: 2),
                              Text(
                                '≈ ${AppFormatters.compactCurrency(value)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: context.appTextSecondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (_raw.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Xóa toàn bộ (C)',
                          icon: Icon(Icons.cancel_rounded,
                              color: context.appTextSecondary, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            setState(() => _raw = '');
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Hàng nút tiền nhanh (+50k, +100k, +500k, +1Tr)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _QuickAmountChip(
                        label: '+50.000',
                        onTap: () => _addQuickAmount(50000),
                      ),
                      const SizedBox(width: 6),
                      _QuickAmountChip(
                        label: '+100.000',
                        onTap: () => _addQuickAmount(100000),
                      ),
                      const SizedBox(width: 6),
                      _QuickAmountChip(
                        label: '+500.000',
                        onTap: () => _addQuickAmount(500000),
                      ),
                      const SizedBox(width: 6),
                      _QuickAmountChip(
                        label: '+1.000.000',
                        onTap: () => _addQuickAmount(1000000),
                      ),
                      const SizedBox(width: 6),
                      _QuickAmountChip(
                        label: '+5.000.000',
                        onTap: () => _addQuickAmount(5000000),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // Lưới bàn phím số chuyên dụng (Có phím 000, C, DEL)
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 2.2,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: [
                    ...[
                      '1', '2', '3',
                      '4', '5', '6',
                      '7', '8', '9',
                      'C', '0', '000',
                    ].map((key) => _NumpadKey(
                          label: key,
                          isAction: key == 'C' || key == '000',
                          onTap: () => _onKey(key),
                        )),
                  ],
                ),
                const SizedBox(height: 8),

                // Hàng nút Xóa lùi và Xác nhận
                Row(
                  children: [
                    // Nút xóa lùi (Backspace)
                    SizedBox(
                      width: 68,
                      height: 46,
                      child: Material(
                        color: AppColors.expenseBackground,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _onKey('DEL'),
                          child: const Center(
                            child: Icon(Icons.backspace_outlined,
                                color: AppColors.expense, size: 20),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Nút xác nhận số tiền
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: ElevatedButton(
                          onPressed: _confirm,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            value > 0 ? 'Xác nhận: $_display ₫' : 'Xác nhận',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickAmountChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickAmountChip({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.appInputFill,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: context.appTextSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _NumpadKey extends StatelessWidget {
  final String label;
  final bool isAction;
  final VoidCallback onTap;

  const _NumpadKey({
    required this.label,
    required this.onTap,
    this.isAction = false,
  });

  @override
  Widget build(BuildContext context) {
    Color? textColor = context.appTextPrimary;
    Color? bgColor = context.appInputFill;

    if (label == 'C') {
      textColor = AppColors.expense;
      bgColor = AppColors.expenseBackground;
    } else if (label == '000') {
      textColor = AppColors.primaryLight;
    }

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: label == '000' ? 16 : 18,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}

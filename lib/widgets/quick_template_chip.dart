import 'package:flutter/material.dart';
import '../models/quick_template.dart';
import '../utils/constants.dart';
import '../utils/formatters.dart';

/// Chip mẫu giao dịch nhanh phong cách Fintech
class QuickTemplateChip extends StatelessWidget {
  final QuickTemplate template;
  final void Function(QuickTemplate) onSelect;

  const QuickTemplateChip({
    super.key,
    required this.template,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final isIncome = template.type == 'income';
    final color = isIncome ? AppColors.income : AppColors.expense;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => onSelect(template),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withAlpha(20),
            border: Border.all(color: color.withAlpha(60), width: 1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: color.withAlpha(30),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isIncome ? Icons.add_rounded : Icons.remove_rounded,
                  size: 12,
                  color: color,
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    template.title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.appTextPrimary,
                    ),
                  ),
                  Text(
                    AppFormatters.compactCurrency(template.amount),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: color,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

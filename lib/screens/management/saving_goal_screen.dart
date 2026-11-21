import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../l10n/app_localizations.dart';
import '../../models/category_model.dart';
import '../../models/saving_goal_model.dart';
import '../../models/transaction_model.dart';
import '../../models/wallet_model.dart';
import '../../services/firestore_service.dart';
import '../../services/ai_service.dart';
import '../../services/language_controller.dart';
import '../../utils/category_localization_helper.dart';
import '../../utils/constants.dart';
import '../../utils/formatters.dart';
import '../../utils/wallet_localization_helper.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/stream_error_widget.dart';

/// Hỗ trợ tính toán thời hạn tháng/năm và ngày hoàn thành dự kiến cho Mục tiêu tiết kiệm.
class SavingGoalDurationHelper {
  SavingGoalDurationHelper._();

  static const int minMonths = 1;
  static const int maxMonths = 360;

  static DateTime addMonthsClamped(DateTime base, int months) {
    final safeMonths = months.clamp(minMonths, maxMonths);
    final totalMonths = base.year * 12 + (base.month - 1) + safeMonths;
    final targetYear = totalMonths ~/ 12;
    final targetMonth = (totalMonths % 12) + 1;
    final lastDay = DateTime(targetYear, targetMonth + 1, 0).day;
    final targetDay = math.min(base.day, lastDay);
    return DateTime(targetYear, targetMonth, targetDay);
  }

  static int monthsBetweenForTargetDate(DateTime base, DateTime target) {
    final baseOnly = DateTime(base.year, base.month, base.day);
    final targetOnly = DateTime(target.year, target.month, target.day);
    int diff =
        (targetOnly.year - baseOnly.year) * 12 +
        (targetOnly.month - baseOnly.month);
    if (targetOnly.day > baseOnly.day) {
      diff += 1;
    }
    return diff.clamp(minMonths, maxMonths);
  }

  static String formatDurationLabel(BuildContext context, int totalMonths) {
    final safeMonths = totalMonths < 1 ? 1 : totalMonths;
    final years = safeMonths ~/ 12;
    final extraMonths = safeMonths % 12;
    if (years == 0) {
      return context.tr(
        'goal_mgmt_dur_months',
        params: {'count': '$extraMonths'},
      );
    }
    if (extraMonths == 0) {
      return context.tr(
        'goal_mgmt_dur_years',
        params: {'count': '$years'},
      );
    }
    return context.tr(
      'goal_mgmt_dur_years_months',
      params: {'years': '$years', 'months': '$extraMonths'},
    );
  }
}

/// 16. Mục tiêu tiết kiệm - Quản lý, theo dõi tiến độ và lập kế hoạch tài chính cùng AI
class SavingGoalScreen extends StatefulWidget {
  const SavingGoalScreen({super.key});

  @override
  State<SavingGoalScreen> createState() => _SavingGoalScreenState();
}

class _SavingGoalScreenState extends State<SavingGoalScreen> {
  final FirestoreService _firestoreService = FirestoreService();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? '';

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(context.tr('goal_mgmt_title')),
        elevation: 0,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 3,
        onPressed: () => _showGoalSheet(context, _firestoreService, uid),
        icon: const Icon(Icons.add_rounded),
        label: Text(context.tr('goal_mgmt_add_fab'),
            style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: Builder(
        builder: (context) {
          if (uid.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.account_circle_outlined,
                        size: 54, color: AppColors.primary),
                    const SizedBox(height: 14),
                    Text(
                      context.tr('goal_mgmt_unauth_title'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: context.appTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      context.tr('goal_mgmt_unauth_desc'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13, color: context.appTextSecondary),
                    ),
                  ],
                ),
              ),
            );
          }

          return StreamBuilder<List<Wallet>>(
            stream: _firestoreService.streamWallets(uid),
            initialData: const <Wallet>[],
            builder: (context, walletSnap) {
              final walletMap = <String, Wallet>{
                for (final w in walletSnap.data ?? const <Wallet>[])
                  w.walletId: w,
              };
              return StreamBuilder<List<SavingGoal>>(
                stream: _firestoreService.streamSavingGoals(uid),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return StreamErrorWidget(
                      error: snap.error.toString(),
                      onRetry: () => setState(() {}),
                    );
                  }
                  if (!snap.hasData &&
                      snap.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary));
                  }
                  final goals = snap.data ?? [];
                  if (goals.isEmpty) {
                    return _buildEmptyState(context, _firestoreService, uid);
                  }

                  final totalSaved =
                      goals.fold<double>(0, (a, g) => a + g.savedAmount);
                  final totalTarget =
                      goals.fold<double>(0, (a, g) => a + g.targetAmount);
                  final completedCount =
                      goals.where((g) => g.percentComplete >= 1.0).length;

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    children: [
                      _buildSavingsHero(
                        context: context,
                        totalSaved: totalSaved,
                        totalTarget: totalTarget,
                        totalGoals: goals.length,
                        completedGoals: completedCount,
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              context.tr('goal_mgmt_list_header',
                                  params: {'count': '${goals.length}'}),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: context.appTextPrimary,
                              ),
                            ),
                          ),
                          if (completedCount > 0) ...[
                            const SizedBox(width: 8),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 150),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.incomeBackground,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    context.tr('goal_mgmt_completed_badge',
                                        params: {'count': '$completedCount'}),
                                    maxLines: 1,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.income,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...goals.map((goal) => _GoalCard(
                            key: ValueKey(goal.goalId),
                            goal: goal,
                            walletMap: walletMap,
                            firestoreService: _firestoreService,
                            onEdit: () => _showGoalSheet(
                                context, _firestoreService, uid,
                                goal: goal),
                          )),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  /// Thẻ Hero tổng quan tình hình tiết kiệm
  Widget _buildSavingsHero({
    required BuildContext context,
    required double totalSaved,
    required double totalTarget,
    required int totalGoals,
    required int completedGoals,
  }) {
    final ratio =
        totalTarget <= 0 ? 0.0 : (totalSaved / totalTarget).clamp(0.0, 1.0);
    final percentInt = (ratio * 100).round();
    final remaining = (totalTarget - totalSaved).clamp(0.0, double.infinity);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1F6F8B), Color(0xFF134A5D)],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -40,
            top: -40,
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.savings_rounded,
                              color: Colors.white, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            context.tr('goal_mgmt_hero_total_saved'),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.88),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      context.tr('goal_mgmt_hero_count',
                          params: {'count': '$totalGoals'}),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  AppFormatters.compactCurrency(totalSaved, unit: '₫'),
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.6,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // Progress Bar
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 8,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Color(0xFF56D69B)),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      context.tr('goal_mgmt_hero_achieved_pct',
                          params: {'pct': '$percentInt'}),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.95),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      context.tr('goal_mgmt_hero_needed', params: {
                        'amount':
                            AppFormatters.compactCurrency(remaining, unit: '₫')
                      }),
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(
      BuildContext context, FirestoreService fs, String uid) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: AppCard(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.savings_outlined,
                  size: 38,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                context.tr('goal_mgmt_empty_title'),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: context.appTextPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.tr('goal_mgmt_empty_desc'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: context.appTextSecondary,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () => _showGoalSheet(context, fs, uid),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(context.tr('goal_mgmt_empty_btn')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Bottom Sheet Tạo / Sửa mục tiêu tiết kiệm
  void _showGoalSheet(
    BuildContext context,
    FirestoreService firestoreService,
    String uid, {
    SavingGoal? goal,
  }) {
    final nameController = TextEditingController(text: goal?.name ?? '');
    final amountController = TextEditingController(
      text: goal != null ? AppFormatters.number(goal.targetAmount) : '',
    );
    int selectedMonths = goal?.months ?? 6;
    bool isSaving = false;
    String? nameError;
    String? amountError;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.appCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          Future<void> submit() async {
            final name = nameController.text.trim();
            final target =
                AppFormatters.parseCurrencyInput(amountController.text);

            if (name.isEmpty) {
              setSheetState(() => nameError = ctx.tr('goal_mgmt_name_err'));
              return;
            }
            if (target <= 0) {
              setSheetState(() => amountError = ctx.tr('goal_mgmt_amount_err'));
              return;
            }

            setSheetState(() => isSaving = true);
            try {
              if (goal == null) {
                await firestoreService.createSavingGoal(SavingGoal(
                  goalId: '',
                  userId: uid,
                  name: name,
                  targetAmount: target,
                  months: selectedMonths,
                  createdAt: DateTime.now(),
                ));
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  AppSnackbar.show(
                      context,
                      ctx.tr('goal_mgmt_created_ok',
                          params: {'name': name}));
                }
              } else {
                await firestoreService.updateSavingGoal(goal.goalId, {
                  'name': name,
                  'targetAmount': target,
                  'months': selectedMonths,
                  'updatedAt': DateTime.now().toIso8601String(),
                });
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  AppSnackbar.show(context, ctx.tr('goal_mgmt_updated_ok'));
                }
              }
            } catch (e) {
              debugPrint('❌ Lỗi lưu mục tiêu: $e');
              if (ctx.mounted) {
                setSheetState(() => isSaving = false);
                AppSnackbar.show(context, ctx.tr('goal_mgmt_save_err'),
                    isError: true);
              }
            }
          }

          return Padding(
            padding:
                EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: context.appBorder,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.flag_rounded,
                            color: AppColors.primary, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              goal == null
                                  ? ctx.tr('goal_mgmt_sheet_add')
                                  : ctx.tr('goal_mgmt_sheet_edit'),
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                                color: context.appTextPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              ctx.tr('goal_mgmt_sheet_sub'),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: context.appTextSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    ctx.tr('goal_mgmt_name_label'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.appTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: nameController,
                    autofocus: goal == null,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) {
                      if (nameError != null) {
                        setSheetState(() => nameError = null);
                      }
                    },
                    decoration: InputDecoration(
                      hintText: ctx.tr('goal_mgmt_name_hint'),
                      errorText: nameError,
                      prefixIcon:
                          const Icon(Icons.bookmark_outline_rounded, size: 20),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    ctx.tr('goal_mgmt_target_label'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.appTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    inputFormatters: const [CurrencyInputFormatter()],
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700),
                    onChanged: (_) {
                      setSheetState(() {
                        if (amountError != null) amountError = null;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: '0',
                      suffixText: '₫',
                      errorText: amountError,
                      prefixIcon: const Icon(Icons.payments_outlined, size: 20),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    ctx.tr('goal_mgmt_duration_label'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.appTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Builder(
                    builder: (_) {
                      final baseDate = goal?.createdAt ?? DateTime.now();
                      final baseOnly = DateTime(
                          baseDate.year, baseDate.month, baseDate.day);
                      final targetDate =
                          SavingGoalDurationHelper.addMonthsClamped(
                              baseOnly, selectedMonths);
                      final parsedTarget = AppFormatters.parseCurrencyInput(
                          amountController.text);
                      final estimatedRemaining =
                          (parsedTarget - (goal?.savedAmount ?? 0.0))
                              .clamp(0.0, double.infinity);
                      final estMonthly = selectedMonths > 0
                          ? estimatedRemaining / selectedMonths
                          : 0.0;
                      final estDaily = estMonthly / 30;
                      final formattedDuration =
                          SavingGoalDurationHelper.formatDurationLabel(
                              ctx, selectedMonths);
                      final summaryDuration = selectedMonths >= 12
                          ? '$formattedDuration (${ctx.tr('goal_mgmt_dur_months', params: {'count': '$selectedMonths'})})'
                          : formattedDuration;

                      Future<void> openTargetDatePicker() async {
                        FocusScope.of(ctx).unfocus();
                        final tomorrow = baseOnly.add(const Duration(days: 1));
                        final minFirstDate = targetDate.isBefore(tomorrow)
                            ? targetDate
                            : tomorrow;
                        final maxLastDate = DateTime(
                          baseOnly.year + 30,
                          baseOnly.month,
                          baseOnly.day,
                        );
                        final safeInit = targetDate.isAfter(maxLastDate)
                            ? maxLastDate
                            : targetDate;
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: safeInit,
                          firstDate: minFirstDate,
                          lastDate: maxLastDate,
                          helpText: ctx.tr('goal_mgmt_dur_pick_date_help'),
                          locale: LanguageController.currentLocale.value,
                        );
                        if (picked != null && ctx.mounted) {
                          setSheetState(() {
                            selectedMonths = SavingGoalDurationHelper
                                .monthsBetweenForTargetDate(
                              baseOnly,
                              picked,
                            );
                          });
                        }
                      }

                      Widget buildPresetRow(List<int> monthOptions) {
                        return Row(
                          children: [
                            for (var i = 0; i < monthOptions.length; i++) ...[
                              if (i > 0) const SizedBox(width: 8),
                              Expanded(
                                child: Builder(
                                  builder: (_) {
                                    final m = monthOptions[i];
                                    final isSelected = selectedMonths == m;
                                    final label = (m < 12 || m % 12 != 0)
                                        ? ctx.tr('goal_mgmt_dur_months',
                                            params: {'count': '$m'})
                                        : ctx.tr('goal_mgmt_dur_years',
                                            params: {'count': '${m ~/ 12}'});
                                    return Material(
                                      color: isSelected
                                          ? AppColors.primary
                                          : context.appInputFill,
                                      borderRadius: BorderRadius.circular(10),
                                      child: InkWell(
                                        onTap: () => setSheetState(
                                            () => selectedMonths = m),
                                        borderRadius: BorderRadius.circular(10),
                                        child: Container(
                                          height: 38,
                                          alignment: Alignment.center,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6),
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            border: Border.all(
                                              color: isSelected
                                                  ? AppColors.primary
                                                  : context.appBorder,
                                            ),
                                          ),
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text(
                                              label,
                                              maxLines: 1,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: isSelected
                                                    ? Colors.white
                                                    : context.appTextPrimary,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ],
                        );
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Material(
                            color: context.appInputFill,
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              onTap: openTargetDatePicker,
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 11),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: AppColors.primary
                                                .withValues(alpha: 0.12),
                                            borderRadius:
                                                BorderRadius.circular(11),
                                          ),
                                          child: const Icon(
                                            Icons.calendar_month_rounded,
                                            color: AppColors.primary,
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                ctx.tr(
                                                  'goal_mgmt_dur_target_date',
                                                  params: {
                                                    'date': DateFormat(
                                                            'dd/MM/yyyy')
                                                        .format(targetDate),
                                                  },
                                                ),
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w700,
                                                  color: context.appTextPrimary,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                ctx.tr(
                                                  'goal_mgmt_dur_total_summary',
                                                  params: {
                                                    'duration': summaryDuration,
                                                  },
                                                ),
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.primary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary
                                                .withValues(alpha: 0.1),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                ctx.tr(
                                                    'goal_mgmt_dur_pick_date_btn'),
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.primary,
                                                ),
                                              ),
                                              const SizedBox(width: 2),
                                              const Icon(
                                                Icons.chevron_right_rounded,
                                                size: 16,
                                                color: AppColors.primary,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (estimatedRemaining > 0) ...[
                                      const SizedBox(height: 8),
                                      Divider(
                                        height: 1,
                                        color: AppColors.primary
                                            .withValues(alpha: 0.15),
                                      ),
                                      const SizedBox(height: 7),
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.savings_outlined,
                                            size: 14,
                                            color: AppColors.primary,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              ctx.tr(
                                                'goal_mgmt_dur_est_pace',
                                                params: {
                                                  'monthly': AppFormatters
                                                      .compactCurrency(
                                                          estMonthly,
                                                          unit: '₫'),
                                                  'daily': AppFormatters
                                                      .compactCurrency(estDaily,
                                                          unit: '₫'),
                                                },
                                              ),
                                              style: const TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w600,
                                                color: AppColors.primary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          buildPresetRow(const [1, 3, 6]),
                          const SizedBox(height: 8),
                          buildPresetRow(const [12, 24, 60]),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: OutlinedButton(
                            onPressed:
                                isSaving ? null : () => Navigator.pop(ctx),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: context.appTextPrimary,
                              side: BorderSide(color: context.appBorder),
                            ),
                            child: Text(ctx.tr('common_cancel'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            onPressed: isSaving ? null : submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                            ),
                            child: isSaving
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                    ),
                                  )
                                : Text(
                                    goal == null
                                        ? ctx.tr('goal_mgmt_create_btn')
                                        : ctx.tr('cat_mgmt_save_changes'),
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600),
                                  ),
                          ),
                        ),
                      ),
                    ],
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

class _GoalCard extends StatefulWidget {
  final SavingGoal goal;
  final Map<String, Wallet> walletMap;
  final FirestoreService firestoreService;
  final VoidCallback onEdit;

  const _GoalCard({
    super.key,
    required this.goal,
    this.walletMap = const {},
    required this.firestoreService,
    required this.onEdit,
  });

  @override
  State<_GoalCard> createState() => _GoalCardState();
}

class _GoalCardState extends State<_GoalCard> {
  final _aiService = AiService();
  String? _aiPlan;
  bool _isLoadingPlan = false;
  bool _planExpanded = false;
  bool _isSyncingSources = false;

  bool get _isCompleted => widget.goal.percentComplete >= 1.0;

  @override
  void initState() {
    super.initState();
    _syncSourcesIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _GoalCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.goal.needsSourceSync && !_isSyncingSources) {
      _syncSourcesIfNeeded();
    }
  }

  Future<void> _syncSourcesIfNeeded() async {
    if (!widget.goal.needsSourceSync || _isSyncingSources) return;
    _isSyncingSources = true;
    try {
      await widget.firestoreService.syncGoalWalletSourcesIfNeeded(widget.goal);
    } finally {
      if (mounted) {
        _isSyncingSources = false;
      }
    }
  }

  Future<void> _loadAiPlan() async {
    setState(() => _isLoadingPlan = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      double? monthlyIncome;
      double? monthlyExpense;
      List<String>? flexibleCategorySummaries;

      if (uid.isNotEmpty) {
        final fs = FirestoreService();
        final now = DateTime.now();
        final monthStart = DateTime(now.year, now.month, 1);
        final results = await Future.wait<dynamic>([
          fs.getTransactionsSafely(uid),
          fs.getCategoriesSafely(uid),
        ]);
        final allTx = results[0] as List;
        final categories = results[1] as List<Category>;
        final catMap = {for (final c in categories) c.categoryId: c};

        double inc = 0;
        double exp = 0;
        final Map<String, double> flexByCatName = {};
        for (final dynamic t in allTx) {
          if (t.date.isAfter(monthStart.subtract(const Duration(seconds: 1)))) {
            if (t.type == 'income') {
              inc += (t.amount as num).toDouble();
            } else if (t.type == 'expense') {
              final amt = (t.amount as num).toDouble();
              exp += amt;
              final cat = catMap[t.categoryId];
              if (cat == null || !cat.isEssential) {
                final name = cat != null
                    ? CategoryLocalizationHelper.localizeName(cat.name)
                    : AppLocalizations.tr('common_other');
                flexByCatName[name] = (flexByCatName[name] ?? 0) + amt;
              }
            }
          }
        }
        if (inc > 0) monthlyIncome = inc;
        if (exp > 0) monthlyExpense = exp;
        final sortedFlex = flexByCatName.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        flexibleCategorySummaries = sortedFlex
            .take(3)
            .map((e) =>
                '${e.key} (${AppFormatters.compactCurrency(e.value)})')
            .toList();
      }

      final plan = await _aiService.generateSavingPlan(
        goalName: widget.goal.name,
        targetAmount: widget.goal.targetAmount,
        months: widget.goal.months,
        savedAmount: widget.goal.savedAmount,
        monthlyIncome: monthlyIncome,
        monthlyExpense: monthlyExpense,
        flexibleCategorySummaries: flexibleCategorySummaries,
      );
      if (!mounted) return;
      setState(() {
        _aiPlan = plan;
        _isLoadingPlan = false;
        _planExpanded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingPlan = false);
      final msg = AiService.isNoNetworkException(e)
          ? context.tr('goal_mgmt_ai_no_net')
          : context.tr('goal_mgmt_ai_err');
      AppSnackbar.show(context, msg, isError: true);
    }
  }

  Future<void> _confirmDeleteGoal() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('goal_mgmt_del_title')),
        content: Text(
          ctx.tr('goal_mgmt_del_msg', params: {'name': widget.goal.name}),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.tr('common_cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr('common_delete'),
                style: const TextStyle(color: AppColors.expense)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await widget.firestoreService.deleteSavingGoal(widget.goal.goalId);
        if (mounted) {
          AppSnackbar.show(context, context.tr('goal_mgmt_del_ok'));
        }
      } catch (e) {
        if (mounted) {
          AppSnackbar.show(context, context.tr('goal_mgmt_del_err'),
              isError: true);
        }
      }
    }
  }

  Future<void> _showDepositSheet() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final syncedGoal =
        await widget.firestoreService.syncGoalWalletSourcesIfNeeded(widget.goal);
    final wallets = await widget.firestoreService.streamWallets(uid).first;
    final activeWallets = wallets.where((w) => w.isActive).toList();

    if (activeWallets.isEmpty) {
      if (mounted) {
        AppSnackbar.show(
          context,
          context.tr('goal_mgmt_no_wallet_dep'),
          isError: true,
        );
      }
      return;
    }

    if (!mounted) return;
    final amountController = TextEditingController();
    String selectedWalletId = activeWallets.first.walletId;
    bool isSubmitting = false;
    String? amountError;
    final remainingGoalAmount =
        (syncedGoal.targetAmount - syncedGoal.savedAmount)
            .clamp(0.0, double.infinity);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.appCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final selectedWallet = activeWallets.firstWhere(
            (w) => w.walletId == selectedWalletId,
            orElse: () => activeWallets.first,
          );
          final selectedWalletDisplayName =
              WalletLocalizationHelper.localizeWalletWithContext(
                  ctx, selectedWallet);
          final alreadyDepositedFromSelected =
              syncedGoal.totalDepositedForWallet(selectedWallet.walletId);
          final withdrawableFromSelected =
              syncedGoal.withdrawableForWallet(selectedWallet.walletId);

          Future<void> submit() async {
            final deposit =
                AppFormatters.parseCurrencyInput(amountController.text);
            if (deposit <= 0) {
              setSheetState(
                () => amountError = ctx.tr('goal_mgmt_invalid_amt'),
              );
              return;
            }

            if (selectedWallet.balance < deposit) {
              setSheetState(
                () => amountError = ctx.tr('goal_mgmt_wallet_insufficient',
                    params: {
                      'name': selectedWalletDisplayName,
                      'balance': AppFormatters.currency(selectedWallet.balance),
                    }),
              );
              return;
            }

            if (deposit > remainingGoalAmount) {
              setSheetState(
                () => amountError = ctx.tr('goal_mgmt_dep_exceeds', params: {
                  'remaining': AppFormatters.currency(remainingGoalAmount),
                }),
              );
              return;
            }

            setSheetState(() {
              amountError = null;
              isSubmitting = true;
            });
            try {
              final tx = AppTransaction(
                transactionId: '',
                userId: uid,
                walletId: selectedWalletId,
                categoryId: '',
                amount: deposit,
                type: 'goal_deposit',
                goalId: syncedGoal.goalId,
                note: ctx.tr('goal_mgmt_dep_tx_note', params: {
                  'goal': syncedGoal.name,
                  'wallet': selectedWalletDisplayName,
                }),
                date: DateTime.now(),
              );
              await widget.firestoreService.createTransaction(tx);
              if (ctx.mounted) {
                Navigator.pop(ctx);
                if (mounted) {
                  AppSnackbar.show(
                    context,
                    context.tr('goal_mgmt_dep_ok', params: {
                      'amount': AppFormatters.currency(deposit),
                      'wallet': selectedWalletDisplayName,
                    }),
                  );
                }
              }
            } catch (e) {
              debugPrint('❌ Lỗi nạp tiền mục tiêu: $e');
              if (ctx.mounted) {
                setSheetState(() => isSubmitting = false);
                final errorMsg = e.toString().replaceFirst('Exception: ', '');
                AppSnackbar.show(ctx, errorMsg, isError: true);
              }
            }
          }

          return Padding(
            padding:
                EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: context.appBorder,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    ctx.tr('goal_mgmt_dep_title'),
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: context.appTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ctx.tr('goal_mgmt_dep_sub', params: {
                      'name': syncedGoal.name,
                      'remaining': AppFormatters.currency(remainingGoalAmount),
                    }),
                    style: TextStyle(
                        fontSize: 13, color: context.appTextSecondary),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    ctx.tr('goal_mgmt_dep_wallet_label'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.appTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: selectedWalletId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      prefixIcon:
                          Icon(Icons.account_balance_wallet_outlined, size: 20),
                    ),
                    items: activeWallets.map((w) {
                      final wLabel =
                          WalletLocalizationHelper.localizeWalletWithContext(
                              ctx, w);
                      return DropdownMenuItem(
                        value: w.walletId,
                        child: Text(
                          '$wLabel (${AppFormatters.compactCurrency(w.balance, unit: '₫')})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setSheetState(() {
                          selectedWalletId = v;
                          amountError = null;
                        });
                      }
                    },
                  ),
                  if (alreadyDepositedFromSelected > 0) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded,
                              size: 16, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              ctx.tr('goal_mgmt_dep_wallet_hist', params: {
                                'wallet': selectedWalletDisplayName,
                                'deposited': AppFormatters.currency(
                                    alreadyDepositedFromSelected),
                                'withdrawable': AppFormatters.currency(
                                    withdrawableFromSelected),
                              }),
                              style: TextStyle(
                                fontSize: 12,
                                color: context.appTextSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    ctx.tr('goal_mgmt_dep_amt_label'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.appTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    inputFormatters: const [CurrencyInputFormatter()],
                    autofocus: true,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700),
                    onChanged: (_) {
                      if (amountError != null) {
                        setSheetState(() => amountError = null);
                      }
                    },
                    decoration: InputDecoration(
                      hintText: '0',
                      suffixText: '₫',
                      errorText: amountError,
                      prefixIcon:
                          const Icon(Icons.add_circle_outline_rounded, size: 20),
                    ),
                  ),
                  const SizedBox(height: 24),
                  AppButton(
                    text: ctx.tr('goal_mgmt_dep_confirm'),
                    icon: Icons.savings_rounded,
                    isLoading: isSubmitting,
                    onPressed: submit,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showWithdrawSheet() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final syncedGoal =
        await widget.firestoreService.syncGoalWalletSourcesIfNeeded(widget.goal);
    final wallets = await widget.firestoreService.streamWallets(uid).first;
    final walletMap = {for (final w in wallets) w.walletId: w};

    if (!mounted) return;

    final withdrawableSources = syncedGoal.withdrawableSources;
    if (withdrawableSources.isEmpty) {
      final msg = syncedGoal.unattributedSavedAmount > 0
          ? context.tr('goal_mgmt_wdr_unattrib', params: {
              'amount': AppFormatters.currency(syncedGoal.unattributedSavedAmount),
            })
          : context.tr('goal_mgmt_wdr_none_left');
      AppSnackbar.show(context, msg, isError: true);
      return;
    }

    final amountController = TextEditingController();
    String selectedSourceWalletId = withdrawableSources.first.walletId;
    bool isSubmitting = false;
    String? amountError;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.appCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final selectedSource = withdrawableSources.firstWhere(
            (s) => s.walletId == selectedSourceWalletId,
            orElse: () => withdrawableSources.first,
          );
          final linkedWallet = walletMap[selectedSource.walletId];
          final resolvedWalletName = linkedWallet != null
              ? WalletLocalizationHelper.localizeWalletWithContext(
                  ctx, linkedWallet)
              : WalletLocalizationHelper.localizeNameWithContext(
                  ctx, selectedSource.walletName);
          final maxWithdrawable = selectedSource.withdrawableAmount;
          final exhaustedSources = syncedGoal.allOrderedSources
              .where((s) => s.withdrawableAmount <= 0)
              .toList();

          Future<void> submit() async {
            final withdraw =
                AppFormatters.parseCurrencyInput(amountController.text);
            if (withdraw <= 0) {
              setSheetState(
                () => amountError = ctx.tr('goal_mgmt_invalid_amt'),
              );
              return;
            }
            if (withdraw > maxWithdrawable) {
              setSheetState(
                () => amountError = ctx.tr('goal_mgmt_wdr_exceeds', params: {
                  'wallet': resolvedWalletName,
                  'max': AppFormatters.currency(maxWithdrawable),
                }),
              );
              return;
            }
            if (linkedWallet == null) {
              AppSnackbar.show(
                ctx,
                ctx.tr('goal_mgmt_wdr_missing_w',
                    params: {'wallet': resolvedWalletName}),
                isError: true,
              );
              return;
            }
            if (!linkedWallet.isActive) {
              AppSnackbar.show(
                ctx,
                ctx.tr('goal_mgmt_wdr_hidden_w',
                    params: {'wallet': resolvedWalletName}),
                isError: true,
              );
              return;
            }

            setSheetState(() {
              amountError = null;
              isSubmitting = true;
            });
            try {
              final tx = AppTransaction(
                transactionId: '',
                userId: uid,
                walletId: selectedSource.walletId,
                categoryId: '',
                amount: withdraw,
                type: 'goal_withdraw',
                goalId: syncedGoal.goalId,
                note: ctx.tr('goal_mgmt_wdr_tx_note', params: {
                  'goal': syncedGoal.name,
                  'wallet': resolvedWalletName,
                }),
                date: DateTime.now(),
              );
              await widget.firestoreService.createTransaction(tx);
              if (ctx.mounted) {
                Navigator.pop(ctx);
                if (mounted) {
                  AppSnackbar.show(
                    context,
                    context.tr('goal_mgmt_wdr_ok', params: {
                      'amount': AppFormatters.currency(withdraw),
                      'wallet': resolvedWalletName,
                    }),
                  );
                }
              }
            } catch (e) {
              debugPrint('❌ Lỗi rút tiền mục tiêu: $e');
              if (ctx.mounted) {
                setSheetState(() => isSubmitting = false);
                final errorMsg = e.toString().replaceFirst('Exception: ', '');
                AppSnackbar.show(ctx, errorMsg, isError: true);
              }
            }
          }

          return Padding(
            padding:
                EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: context.appBorder,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    context.tr('goal_mgmt_wdr_title'),
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: context.appTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.tr(
                      'goal_mgmt_wdr_sub',
                      params: {
                        'goal': syncedGoal.name,
                        'total': AppFormatters.currency(syncedGoal.savedAmount),
                      },
                    ),
                    style: TextStyle(
                        fontSize: 13, color: context.appTextSecondary),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    context.tr('goal_mgmt_wdr_pick_label'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.appTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      FocusScope.of(ctx).unfocus();
                      final pickedWalletId =
                          await _showWithdrawSourcePickerSheet(
                        context: ctx,
                        goalName: syncedGoal.name,
                        withdrawableSources: withdrawableSources,
                        exhaustedSources: exhaustedSources,
                        walletMap: walletMap,
                        selectedWalletId: selectedSource.walletId,
                      );
                      if (pickedWalletId != null &&
                          pickedWalletId != selectedSourceWalletId &&
                          ctx.mounted) {
                        setSheetState(() {
                          selectedSourceWalletId = pickedWalletId;
                          final currentVal = AppFormatters.parseCurrencyInput(
                              amountController.text);
                          final newMax =
                              syncedGoal.withdrawableForWallet(pickedWalletId);
                          if (currentVal > newMax) {
                            final pickedWallet = walletMap[pickedWalletId];
                            final newName = pickedWallet != null
                                ? WalletLocalizationHelper
                                    .localizeWalletWithContext(
                                        ctx, pickedWallet)
                                : WalletLocalizationHelper
                                    .localizeNameWithContext(
                                    ctx,
                                    syncedGoal.walletSources[pickedWalletId]
                                            ?.walletName ??
                                        context.tr(
                                            'goal_mgmt_wdr_wallet_default'),
                                  );
                            amountError = context.tr(
                              'goal_mgmt_wdr_exceed_pick',
                              params: {
                                'wallet': newName,
                                'max': AppFormatters.currency(newMax),
                              },
                            );
                          } else {
                            amountError = null;
                          }
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 13),
                      decoration: BoxDecoration(
                        color: context.appInputFill,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.appBorder),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.account_balance_wallet_outlined,
                            size: 20,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  resolvedWalletName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: context.appTextPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  context.tr(
                                    'goal_mgmt_wdr_can_amt',
                                    params: {
                                      'amount': AppFormatters.currency(
                                          maxWithdrawable),
                                    },
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 115),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      context.tr('goal_mgmt_wdr_change_btn'),
                                      maxLines: 1,
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    const Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      size: 18,
                                      color: AppColors.primary,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (exhaustedSources.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      context.tr(
                        'goal_mgmt_wdr_exhausted_list',
                        params: {
                          'names': exhaustedSources.map((s) {
                            final linked = walletMap[s.walletId];
                            return linked != null
                                ? WalletLocalizationHelper
                                    .localizeWalletWithContext(ctx, linked)
                                : WalletLocalizationHelper
                                    .localizeNameWithContext(ctx, s.walletName);
                          }).join(', '),
                        },
                      ),
                      style: TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: context.appTextSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  // Thông tin chi tiết nguồn ví được chọn
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.appInputFill,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.appBorder),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                context.tr(
                                  'goal_mgmt_wdr_total_dep_row',
                                  params: {'wallet': resolvedWalletName},
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.appTextSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 140),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  AppFormatters.currency(
                                      selectedSource.totalDeposited),
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: context.appTextPrimary,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                context.tr('goal_mgmt_wdr_max_row'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.appTextSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 140),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  AppFormatters.currency(maxWithdrawable),
                                  maxLines: 1,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Divider(height: 1),
                        ),
                        Row(
                          children: [
                            const Icon(Icons.lock_outline_rounded,
                                size: 15, color: AppColors.primary),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                context.tr(
                                  'goal_mgmt_wdr_refund_note',
                                  params: {'wallet': resolvedWalletName},
                                ),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          context.tr('goal_mgmt_wdr_amt_label'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: context.appTextSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 175),
                        child: InkWell(
                          onTap: () {
                            final formattedMax =
                                AppFormatters.number(maxWithdrawable);
                            amountController.value = TextEditingValue(
                              text: formattedMax,
                              selection: TextSelection.collapsed(
                                  offset: formattedMax.length),
                            );
                            setSheetState(() => amountError = null);
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Text(
                                context.tr(
                                  'goal_mgmt_wdr_max_btn',
                                  params: {
                                    'amount':
                                        AppFormatters.number(maxWithdrawable),
                                  },
                                ),
                                maxLines: 1,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    inputFormatters: const [CurrencyInputFormatter()],
                    autofocus: true,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700),
                    onChanged: (val) {
                      final entered = AppFormatters.parseCurrencyInput(val);
                      if (entered > maxWithdrawable) {
                        setSheetState(
                          () => amountError = context.tr(
                            'goal_mgmt_wdr_exceed_pick',
                            params: {
                              'wallet': resolvedWalletName,
                              'max': AppFormatters.currency(maxWithdrawable),
                            },
                          ),
                        );
                      } else if (amountError != null) {
                        setSheetState(() => amountError = null);
                      }
                    },
                    decoration: InputDecoration(
                      hintText: '0',
                      suffixText: '₫',
                      errorText: amountError,
                      prefixIcon: const Icon(
                          Icons.remove_circle_outline_rounded,
                          size: 20),
                    ),
                  ),
                  const SizedBox(height: 24),
                  AppButton(
                    text: context.tr(
                      'goal_mgmt_wdr_confirm',
                      params: {'wallet': resolvedWalletName},
                    ),
                    icon: Icons.undo_rounded,
                    backgroundColor: AppColors.expense,
                    isLoading: isSubmitting,
                    onPressed: submit,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Bottom Sheet chọn nguồn ví đã nạp để rút tiền (tránh lỗi Dropdown nhảy vị trí khi đóng/mở bàn phím)
  Future<String?> _showWithdrawSourcePickerSheet({
    required BuildContext context,
    required String goalName,
    required List<GoalWalletSource> withdrawableSources,
    required List<GoalWalletSource> exhaustedSources,
    required Map<String, Wallet> walletMap,
    required String selectedWalletId,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.appCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (pickerCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: pickerCtx.appBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pickerCtx.tr('goal_mgmt_wdr_pick_label'),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: pickerCtx.appTextPrimary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            pickerCtx.tr('goal_mgmt_pick_sub',
                                params: {'goal': goalName}),
                            style: TextStyle(
                              fontSize: 12,
                              color: pickerCtx.appTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(pickerCtx),
                      icon: Icon(
                        Icons.close_rounded,
                        color: pickerCtx.appTextSecondary,
                      ),
                      tooltip: pickerCtx.tr('common_close'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...withdrawableSources.map((src) {
                          final isSelected = src.walletId == selectedWalletId;
                          final linked = walletMap[src.walletId];
                          final wName = linked != null
                              ? WalletLocalizationHelper
                                  .localizeWalletWithContext(pickerCtx, linked)
                              : WalletLocalizationHelper
                                  .localizeNameWithContext(
                                      pickerCtx, src.walletName);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () =>
                                  Navigator.pop(pickerCtx, src.walletId),
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.primary
                                          .withValues(alpha: 0.08)
                                      : pickerCtx.appInputFill,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isSelected
                                        ? AppColors.primary
                                        : pickerCtx.appBorder,
                                    width: isSelected ? 1.5 : 1.0,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? AppColors.primary
                                                .withValues(alpha: 0.16)
                                            : pickerCtx.appCard,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        Icons.account_balance_wallet_rounded,
                                        size: 20,
                                        color: isSelected
                                            ? AppColors.primary
                                            : pickerCtx.appTextSecondary,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            wName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              color: pickerCtx.appTextPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            pickerCtx.tr('goal_mgmt_pick_dep',
                                                params: {
                                                  'amount':
                                                      AppFormatters.currency(
                                                          src.totalDeposited),
                                                }),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: pickerCtx.appTextSecondary,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            pickerCtx.tr(
                                                'goal_mgmt_wdr_can_amt',
                                                params: {
                                                  'amount':
                                                      AppFormatters.currency(
                                                          src.withdrawableAmount),
                                                }),
                                            style: const TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(
                                      isSelected
                                          ? Icons.check_circle_rounded
                                          : Icons.radio_button_unchecked_rounded,
                                      color: isSelected
                                          ? AppColors.primary
                                          : pickerCtx.appTextSecondary
                                              .withValues(alpha: 0.5),
                                      size: 22,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                        if (exhaustedSources.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            pickerCtx.tr('goal_mgmt_pick_exhausted_hdr'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: pickerCtx.appTextSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...exhaustedSources.map((src) {
                            final linked = walletMap[src.walletId];
                            final wName = linked != null
                                ? WalletLocalizationHelper
                                    .localizeWalletWithContext(
                                        pickerCtx, linked)
                                : WalletLocalizationHelper
                                    .localizeNameWithContext(
                                        pickerCtx, src.walletName);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Opacity(
                                opacity: 0.55,
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: pickerCtx.appInputFill,
                                    borderRadius: BorderRadius.circular(12),
                                    border:
                                        Border.all(color: pickerCtx.appBorder),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.account_balance_wallet_outlined,
                                        size: 18,
                                        color: pickerCtx.appTextSecondary,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          pickerCtx.tr(
                                              'goal_mgmt_pick_item_dep',
                                              params: {
                                                'wallet': wName,
                                                'amount':
                                                    AppFormatters.currency(
                                                        src.totalDeposited),
                                              }),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: pickerCtx.appTextSecondary,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          pickerCtx
                                              .tr('goal_mgmt_pick_item_zero'),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontStyle: FontStyle.italic,
                                            color: pickerCtx.appTextSecondary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final goal = widget.goal;
    final pct = goal.percentComplete;
    final remaining =
        (goal.targetAmount - goal.savedAmount).clamp(0.0, double.infinity);

    final Color statusColor = _isCompleted
        ? AppColors.income
        : pct >= 0.7
            ? AppColors.primary
            : const Color(0xFFE59819);

    return AppCard(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: statusColor.withValues(
                      alpha: context.isDarkMode ? 0.25 : 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  _isCompleted
                      ? Icons.check_circle_rounded
                      : Icons.savings_rounded,
                  color: statusColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            goal.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: context.appTextPrimary,
                            ),
                          ),
                        ),
                        if (_isCompleted) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.incomeBackground,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              context.tr('goal_mgmt_card_achieved'),
                              style: const TextStyle(
                                color: AppColors.income,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Builder(
                      builder: (_) {
                        final durationStr =
                            SavingGoalDurationHelper.formatDurationLabel(
                          context,
                          goal.months,
                        );
                        final targetDate =
                            SavingGoalDurationHelper.addMonthsClamped(
                          goal.createdAt,
                          goal.months,
                        );
                        return Text(
                          context.tr(
                            'goal_mgmt_card_target_fmt',
                            params: {
                              'amount': AppFormatters.compactCurrency(
                                  goal.targetAmount,
                                  unit: '₫'),
                              'duration': durationStr,
                              'date':
                                  DateFormat('MM/yyyy').format(targetDate),
                            },
                          ),
                          style: TextStyle(
                              fontSize: 12, color: context.appTextSecondary),
                        );
                      },
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded,
                    color: context.appTextSecondary, size: 20),
                tooltip: context.tr('cat_mgmt_options_tooltip'),
                onSelected: (action) {
                  if (action == 'edit') {
                    widget.onEdit();
                  } else if (action == 'delete') {
                    _confirmDeleteGoal();
                  }
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        const Icon(Icons.edit_outlined, size: 18),
                        const SizedBox(width: 8),
                        Text(ctx.tr('cat_mgmt_edit')),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        const Icon(Icons.delete_outline_rounded,
                            size: 18, color: AppColors.expense),
                        const SizedBox(width: 8),
                        Text(ctx.tr('goal_mgmt_delete_menu'),
                            style: const TextStyle(color: AppColors.expense)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: pct.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: context.appInputFill,
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  context.tr('goal_mgmt_card_saved', params: {
                    'amount':
                        AppFormatters.compactCurrency(goal.savedAmount, unit: '₫'),
                  }),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  context.tr('goal_mgmt_card_left', params: {
                    'amount':
                        AppFormatters.compactCurrency(remaining, unit: '₫'),
                    'pct': '${(pct * 100).round()}',
                  }),
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.appTextSecondary,
                  ),
                ),
              ),
            ],
          ),
          if (!_isCompleted) ...[
            const SizedBox(height: 6),
            Text(
              context.tr('goal_mgmt_card_pace', params: {
                'monthly': AppFormatters.compactCurrency(goal.monthlyRequired,
                    unit: '₫'),
                'daily': AppFormatters.compactCurrency(goal.dailyRequired,
                    unit: '₫'),
              }),
              style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: context.appTextSecondary,
              ),
            ),
          ],
          if (goal.allOrderedSources.isNotEmpty ||
              goal.unattributedSavedAmount > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.appInputFill,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: context.appBorder.withValues(alpha: 0.7),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.account_balance_wallet_outlined,
                        size: 14,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        flex: 4,
                        child: Text(
                          context.tr('goal_mgmt_tbl_source'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: context.appTextSecondary,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            context.tr('goal_mgmt_tbl_dep'),
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: context.appTextSecondary,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            context.tr('goal_mgmt_tbl_wdr'),
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: context.appTextSecondary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ...goal.allOrderedSources.map(
                    (source) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2.5),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 4,
                            child: Text(
                              () {
                                final linked =
                                    widget.walletMap[source.walletId];
                                return linked != null
                                    ? WalletLocalizationHelper
                                        .localizeWalletWithContext(
                                            context, linked)
                                    : WalletLocalizationHelper
                                        .localizeNameWithContext(
                                        context,
                                        source.walletName,
                                      );
                              }(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: context.appTextPrimary,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              AppFormatters.compactCurrency(
                                source.totalDeposited,
                                unit: '₫',
                              ),
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: context.appTextSecondary,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              AppFormatters.compactCurrency(
                                source.withdrawableAmount,
                                unit: '₫',
                              ),
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: source.withdrawableAmount > 0
                                    ? AppColors.primary
                                    : context.appTextSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (goal.unattributedSavedAmount > 0) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2.5),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 4,
                            child: Text(
                              context.tr('goal_mgmt_tbl_unattrib'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontStyle: FontStyle.italic,
                                color: context.appTextSecondary,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              AppFormatters.compactCurrency(
                                goal.unattributedSavedAmount,
                                unit: '₫',
                              ),
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: context.appTextSecondary,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              '—',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: context.appTextSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          // Action Buttons Row
          Row(
            children: [
              if (!_isCompleted)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _showDepositSheet,
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        context.tr('goal_mgmt_btn_deposit'),
                        maxLines: 1,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              if (goal.savedAmount > 0) ...[
                if (!_isCompleted) const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _showWithdrawSheet,
                    icon: const Icon(Icons.undo_rounded, size: 15),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        context.tr('goal_mgmt_btn_withdraw'),
                        maxLines: 1,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.appTextSecondary,
                      side: BorderSide(color: context.appBorder),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Flexible(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: (_aiPlan != null || _isLoadingPlan)
                        ? () => setState(() => _planExpanded = !_planExpanded)
                        : _loadAiPlan,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: AppColors.aiAccent.withValues(alpha: 0.4)),
                        borderRadius: BorderRadius.circular(10),
                        color: AppColors.aiAccent
                            .withValues(alpha: context.isDarkMode ? 0.2 : 0.08),
                      ),
                      child: _isLoadingPlan
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    AppColors.aiAccent),
                              ),
                            )
                          : FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.auto_awesome,
                                      size: 16, color: AppColors.aiAccent),
                                  const SizedBox(width: 4),
                                  Text(
                                    _aiPlan != null
                                        ? (_planExpanded
                                            ? context
                                                .tr('goal_mgmt_btn_collapse')
                                            : context
                                                .tr('goal_mgmt_btn_view_plan'))
                                        : context.tr('goal_mgmt_btn_ai_plan'),
                                    maxLines: 1,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.aiAccent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          // AI Plan Section
          if (_aiPlan != null && _planExpanded) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.aiAccent
                    .withValues(alpha: context.isDarkMode ? 0.15 : 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.aiAccent.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome,
                          size: 16, color: AppColors.aiAccent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          context.tr('goal_mgmt_ai_plan_title'),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.aiAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _aiPlan!,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: context.appTextPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

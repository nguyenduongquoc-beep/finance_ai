import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/saving_goal_model.dart';
import '../../models/transaction_model.dart';
import '../../services/firestore_service.dart';
import '../../services/ai_service.dart';
import '../../utils/constants.dart';
import '../../utils/formatters.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/stream_error_widget.dart';

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
        title: const Text('Mục tiêu tiết kiệm'),
        elevation: 0,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 3,
        onPressed: () => _showGoalSheet(context, _firestoreService, uid),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Thêm mục tiêu',
            style: TextStyle(fontWeight: FontWeight.w600)),
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
                      'Chưa xác thực tài khoản',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: context.appTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Vui lòng đăng nhập để xem và quản lý các mục tiêu tiết kiệm.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13, color: context.appTextSecondary),
                    ),
                  ],
                ),
              ),
            );
          }

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
                    child: CircularProgressIndicator(color: AppColors.primary));
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
                      Text(
                        'Danh sách mục tiêu (${goals.length})',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: context.appTextPrimary,
                        ),
                      ),
                      if (completedCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.incomeBackground,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Đã hoàn thành $completedCount',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.income,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...goals.map((goal) => _GoalCard(
                        key: ValueKey(goal.goalId),
                        goal: goal,
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
                            'Tổng tiền đã tích lũy',
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
                      '$totalGoals mục tiêu',
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
                      'Đạt $percentInt% tổng mục tiêu',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.95),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Cần: ${AppFormatters.compactCurrency(remaining, unit: '₫')}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.75),
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
                'Chưa có mục tiêu tiết kiệm',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: context.appTextPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Đặt mục tiêu (mua laptop, quỹ khẩn cấp, du lịch...) để AI lên kế hoạch giúp bạn hoàn thành đúng hạn.',
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
                  label: const Text('Tạo mục tiêu đầu tiên'),
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
              setSheetState(() => nameError = 'Vui lòng nhập tên mục tiêu');
              return;
            }
            if (target <= 0) {
              setSheetState(
                  () => amountError = 'Số tiền mục tiêu phải lớn hơn 0');
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
                      context, 'Đã tạo mục tiêu "$name" thành công!');
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
                  AppSnackbar.show(context, 'Đã cập nhật mục tiêu thành công!');
                }
              }
            } catch (e) {
              debugPrint('❌ Lỗi lưu mục tiêu: $e');
              if (ctx.mounted) {
                setSheetState(() => isSaving = false);
                AppSnackbar.show(
                    context, 'Không thể lưu mục tiêu. Vui lòng thử lại.',
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
                                  ? 'Mục tiêu tiết kiệm mới'
                                  : 'Chỉnh sửa mục tiêu',
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                                color: context.appTextPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Xác định rõ số tiền và thời hạn cần đạt',
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
                    'Tên mục tiêu',
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
                      if (nameError != null)
                        setSheetState(() => nameError = null);
                    },
                    decoration: InputDecoration(
                      hintText: 'VD: Mua Laptop, Quỹ dự phòng, Du lịch...',
                      errorText: nameError,
                      prefixIcon:
                          const Icon(Icons.bookmark_outline_rounded, size: 20),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Số tiền cần tích lũy (VNĐ)',
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
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700),
                    onChanged: (_) {
                      if (amountError != null)
                        setSheetState(() => amountError = null);
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
                    'Thời gian hoàn thành mục tiêu',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.appTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [3, 6, 12, 24, 36].map((m) {
                      final isSelected = selectedMonths == m;
                      return ChoiceChip(
                        showCheckmark: false,
                        selected: isSelected,
                        selectedColor: AppColors.primary,
                        label: Text(m < 12 ? '$m tháng' : '${m ~/ 12} năm'),
                        labelStyle: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? Colors.white
                              : context.appTextPrimary,
                        ),
                        onSelected: (_) =>
                            setSheetState(() => selectedMonths = m),
                      );
                    }).toList(),
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
                            child: const Text('Hủy',
                                style: TextStyle(fontWeight: FontWeight.w600)),
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
                                        ? 'Tạo mục tiêu'
                                        : 'Lưu thay đổi',
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
  final FirestoreService firestoreService;
  final VoidCallback onEdit;

  const _GoalCard({
    super.key,
    required this.goal,
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

  bool get _isCompleted => widget.goal.percentComplete >= 1.0;

  Future<void> _loadAiPlan() async {
    setState(() => _isLoadingPlan = true);
    try {
      final plan = await _aiService.generateSavingPlan(
        goalName: widget.goal.name,
        targetAmount: widget.goal.targetAmount,
        months: widget.goal.months,
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
          ? 'Không có kết nối mạng. Vui lòng thử lại.'
          : 'Không thể tải kế hoạch AI lúc này.';
      AppSnackbar.show(context, msg, isError: true);
    }
  }

  Future<void> _confirmDeleteGoal() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa mục tiêu?'),
        content: Text(
          'Bạn có chắc chắn muốn xóa mục tiêu "${widget.goal.name}"? '
          'Lưu ý: Tiền đã nạp trước đây trong ví sẽ không bị mất.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Xóa', style: TextStyle(color: AppColors.expense)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await widget.firestoreService.deleteSavingGoal(widget.goal.goalId);
        if (mounted) {
          AppSnackbar.show(context, 'Đã xóa mục tiêu tiết kiệm');
        }
      } catch (e) {
        if (mounted) {
          AppSnackbar.show(context, 'Không thể xóa mục tiêu. Vui lòng thử lại.',
              isError: true);
        }
      }
    }
  }

  Future<void> _showDepositSheet() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final wallets = await widget.firestoreService.streamWallets(uid).first;
    final activeWallets = wallets.where((w) => w.isActive).toList();

    if (activeWallets.isEmpty) {
      if (mounted) {
        AppSnackbar.show(
          context,
          'Bạn chưa có ví nào để nạp tiền. Vui lòng tạo ví trước.',
          isError: true,
        );
      }
      return;
    }

    if (!mounted) return;
    final amountController = TextEditingController();
    String selectedWalletId = activeWallets.first.walletId;
    bool isSubmitting = false;

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
            final deposit =
                AppFormatters.parseCurrencyInput(amountController.text);
            if (deposit <= 0) {
              AppSnackbar.show(
                  context, 'Vui lòng nhập số tiền hợp lệ lớn hơn 0',
                  isError: true);
              return;
            }

            final wallet =
                activeWallets.firstWhere((w) => w.walletId == selectedWalletId);
            if (wallet.balance < deposit) {
              AppSnackbar.show(
                context,
                'Số dư trong ví "${wallet.walletName}" không đủ để nạp.',
                isError: true,
              );
              return;
            }

            setSheetState(() => isSubmitting = true);
            try {
              final tx = AppTransaction(
                transactionId: '',
                userId: uid,
                walletId: selectedWalletId,
                categoryId: '',
                amount: deposit,
                type: 'goal_deposit',
                goalId: widget.goal.goalId,
                note: 'Nạp vào mục tiêu tiết kiệm: ${widget.goal.name}',
                date: DateTime.now(),
              );
              await widget.firestoreService.createTransaction(tx);
              if (ctx.mounted) {
                Navigator.pop(ctx);
                if (mounted) {
                  AppSnackbar.show(context,
                      'Đã nạp ${AppFormatters.currency(deposit)} vào mục tiêu!');
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
                    'Nạp tiền tích lũy',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: context.appTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Mục tiêu: "${widget.goal.name}"',
                    style: TextStyle(
                        fontSize: 13, color: context.appTextSecondary),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Trích từ ví',
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
                      return DropdownMenuItem(
                        value: w.walletId,
                        child: Text(
                          '${w.walletName} (${AppFormatters.compactCurrency(w.balance, unit: '₫')})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) setSheetState(() => selectedWalletId = v);
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Số tiền nạp (VNĐ)',
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
                    autofocus: true,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700),
                    decoration: const InputDecoration(
                      hintText: '0',
                      suffixText: '₫',
                      prefixIcon:
                          Icon(Icons.add_circle_outline_rounded, size: 20),
                    ),
                  ),
                  const SizedBox(height: 24),
                  AppButton(
                    text: 'Xác nhận nạp tiền',
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
    final wallets = await widget.firestoreService.streamWallets(uid).first;
    final activeWallets = wallets.where((w) => w.isActive).toList();

    if (activeWallets.isEmpty) {
      if (mounted) {
        AppSnackbar.show(
          context,
          'Bạn chưa có ví nào để nhận lại tiền. Vui lòng tạo ví trước.',
          isError: true,
        );
      }
      return;
    }

    if (!mounted) return;
    final amountController = TextEditingController();
    String selectedWalletId = activeWallets.first.walletId;
    bool isSubmitting = false;

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
            final withdraw =
                AppFormatters.parseCurrencyInput(amountController.text);
            if (withdraw <= 0) {
              AppSnackbar.show(
                  context, 'Vui lòng nhập số tiền hợp lệ lớn hơn 0',
                  isError: true);
              return;
            }
            if (withdraw > widget.goal.savedAmount) {
              AppSnackbar.show(
                context,
                'Số tiền rút không được vượt quá số tiền hiện có (${AppFormatters.currency(widget.goal.savedAmount)}).',
                isError: true,
              );
              return;
            }

            setSheetState(() => isSubmitting = true);
            try {
              final tx = AppTransaction(
                transactionId: '',
                userId: uid,
                walletId: selectedWalletId,
                categoryId: '',
                amount: withdraw,
                type: 'goal_withdraw',
                goalId: widget.goal.goalId,
                note: 'Rút từ mục tiêu tiết kiệm: ${widget.goal.name}',
                date: DateTime.now(),
              );
              await widget.firestoreService.createTransaction(tx);
              if (ctx.mounted) {
                Navigator.pop(ctx);
                if (mounted) {
                  AppSnackbar.show(context,
                      'Đã rút ${AppFormatters.currency(withdraw)} về ví!');
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
                    'Rút tiền về ví',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: context.appTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Đang có: ${AppFormatters.currency(widget.goal.savedAmount)} trong mục tiêu "${widget.goal.name}"',
                    style: TextStyle(
                        fontSize: 13, color: context.appTextSecondary),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Nhận về ví',
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
                      return DropdownMenuItem(
                        value: w.walletId,
                        child: Text(
                          '${w.walletName} (${AppFormatters.compactCurrency(w.balance, unit: '₫')})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) setSheetState(() => selectedWalletId = v);
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Số tiền rút (VNĐ)',
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
                    autofocus: true,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700),
                    decoration: const InputDecoration(
                      hintText: '0',
                      suffixText: '₫',
                      prefixIcon:
                          Icon(Icons.remove_circle_outline_rounded, size: 20),
                    ),
                  ),
                  const SizedBox(height: 24),
                  AppButton(
                    text: 'Xác nhận rút tiền',
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
                            child: const Text(
                              'Đạt mục tiêu! 🎉',
                              style: TextStyle(
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
                    Text(
                      'Mục tiêu: ${AppFormatters.compactCurrency(goal.targetAmount, unit: '₫')} • ${goal.months} tháng',
                      style: TextStyle(
                          fontSize: 12, color: context.appTextSecondary),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded,
                    color: context.appTextSecondary, size: 20),
                tooltip: 'Tùy chọn',
                onSelected: (action) {
                  if (action == 'edit') {
                    widget.onEdit();
                  } else if (action == 'delete') {
                    _confirmDeleteGoal();
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('Chỉnh sửa'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline_rounded,
                            size: 18, color: AppColors.expense),
                        SizedBox(width: 8),
                        Text('Xóa mục tiêu',
                            style: TextStyle(color: AppColors.expense)),
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
                  'Đã tích lũy: ${AppFormatters.compactCurrency(goal.savedAmount, unit: '₫')}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Còn: ${AppFormatters.compactCurrency(remaining, unit: '₫')} (${(pct * 100).round()}%)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: context.appTextSecondary,
                ),
              ),
            ],
          ),
          if (!_isCompleted) ...[
            const SizedBox(height: 6),
            Text(
              'Cần tích lũy ~${AppFormatters.compactCurrency(goal.monthlyRequired, unit: '₫')}/tháng '
              '(khoảng ${AppFormatters.compactCurrency(goal.dailyRequired, unit: '₫')}/ngày)',
              style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: context.appTextSecondary,
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
                    label: const Text('Nạp tiền',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 10),
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
                    label: const Text('Rút về ví',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.appTextSecondary,
                      side: BorderSide(color: context.appBorder),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Material(
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
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.auto_awesome,
                                  size: 16, color: AppColors.aiAccent),
                              const SizedBox(width: 4),
                              Text(
                                _aiPlan != null
                                    ? (_planExpanded
                                        ? 'Thu gọn'
                                        : 'Xem kế hoạch')
                                    : 'AI Kế hoạch',
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
                  const Row(
                    children: [
                      Icon(Icons.auto_awesome,
                          size: 16, color: AppColors.aiAccent),
                      SizedBox(width: 6),
                      Text(
                        'Kế hoạch tích lũy tối ưu từ AI',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.aiAccent,
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

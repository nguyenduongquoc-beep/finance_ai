import 'dart:io';
import 'dart:ui' show FontFeature;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/category_model.dart';
import '../../models/transaction_model.dart';
import '../../models/user_model.dart';
import '../../models/wallet_model.dart';
import '../../services/firestore_service.dart';
import '../../utils/constants.dart';
import '../../utils/formatters.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/dashboard_chart.dart';
import '../../widgets/stream_error_widget.dart';
import '../../widgets/transaction_card.dart';
import '../ai/ai_insight_screen.dart';
import '../ai/ai_report_screen.dart';
import '../notification_screen.dart';
import 'add_transaction_screen.dart';
import 'transaction_detail_screen.dart';
import 'transaction_list_screen.dart';

/// Trang chủ FinAI Dashboard - Hiện đại, Khoa học, Chống tràn số tiền lớn, Hỗ trợ Danh mục Thu & Chi.
class HomeDashboardScreen extends StatefulWidget {
  const HomeDashboardScreen({super.key});

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  late int _selectedYear;
  late int _selectedHalf;
  int _selectedMonthIndex = 0;
  String _selectedCategoryType = 'expense'; // 'expense' hoặc 'income'
  bool _isBalanceVisible = true;

  final _firestoreService = FirestoreService();
  late final String _uid;
  late final Stream<AppUser?> _userStream;
  late final Stream<List<Wallet>> _walletsStream;
  late final Stream<List<Category>> _categoriesStream;
  late final Stream<List<AppTransaction>> _currentMonthTxStream;
  late Stream<List<AppTransaction>> _sixMonthTxStream;

  // Cache dữ liệu lịch sử để khi đổi năm/kỳ không bao giờ bị chớp trắng màn hình
  List<AppTransaction>? _cachedHistory;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedYear = now.year;
    _selectedHalf = now.month <= 6 ? 1 : 2;
    _selectedMonthIndex = _defaultMonthIndexFor(_selectedYear, _selectedHalf);

    _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _userStream = _firestoreService.streamUserProfile(_uid);
    _walletsStream = _firestoreService.streamWallets(_uid);
    _categoriesStream = _firestoreService.streamCategories(_uid);
    _currentMonthTxStream = _firestoreService.streamTransactions(
      _uid,
      from: DateTime(now.year, now.month, 1),
    );
    _sixMonthTxStream = _firestoreService.streamTransactions(
      _uid,
      from: _filterFrom,
      to: _filterTo,
    );
  }

  /// Tính toán vị trí tháng mặc định chuẩn theo thời gian thực
  int _defaultMonthIndexFor(int year, int half) {
    final now = DateTime.now();
    if (year == now.year) {
      final firstMonth = half == 1 ? 1 : 7;
      final offset = now.month - firstMonth;
      if (offset >= 0 && offset <= 5) return offset;
      return half == 1 ? 5 : 0;
    }
    return 0;
  }

  DateTime get _filterFrom =>
      DateTime(_selectedYear, _selectedHalf == 1 ? 1 : 7, 1);

  DateTime get _filterTo => _selectedHalf == 1
      ? DateTime(_selectedYear, 6, 30, 23, 59, 59)
      : DateTime(_selectedYear, 12, 31, 23, 59, 59);

  DateTime get _selectedMonthDate {
    final firstMonth = _selectedHalf == 1 ? 1 : 7;
    return DateTime(_selectedYear, firstMonth + _selectedMonthIndex, 1);
  }

  void _refreshSixMonthStream() {
    _sixMonthTxStream = _firestoreService.streamTransactions(
      _uid,
      from: _filterFrom,
      to: _filterTo,
    );
  }

  Future<void> _handleRefresh() async {
    setState(() {
      _refreshSixMonthStream();
    });
    await Future.delayed(const Duration(milliseconds: 350));
  }

  Map<String, List<double>> _buildSixMonthData(List<AppTransaction> txs) {
    final income = <double>[];
    final expense = <double>[];
    final firstMonth = _selectedHalf == 1 ? 1 : 7;

    for (var index = 0; index < 6; index++) {
      final from = DateTime(_selectedYear, firstMonth + index, 1);
      final to = DateTime(_selectedYear, firstMonth + index + 1, 1);
      final monthlyTx = txs.where(
        (tx) => !tx.date.isBefore(from) && tx.date.isBefore(to),
      );
      income.add(
        monthlyTx
                .where((tx) => tx.type == 'income')
                .fold<double>(0, (sum, tx) => sum + tx.amount) /
            1e6,
      );
      expense.add(
        monthlyTx
                .where((tx) => tx.type == 'expense')
                .fold<double>(0, (sum, tx) => sum + tx.amount) /
            1e6,
      );
    }
    return {'income': income, 'expense': expense};
  }

  List<String> _buildMonthLabels() {
    final firstMonth = _selectedHalf == 1 ? 1 : 7;
    return [
      for (var index = 0; index < 6; index++) 'Th${firstMonth + index}',
    ];
  }

  List<AppTransaction> _transactionsForSelectedMonth(
    List<AppTransaction> txs,
  ) {
    final from = _selectedMonthDate;
    final to = DateTime(from.year, from.month + 1, 1);
    return txs
        .where((tx) => !tx.date.isBefore(from) && tx.date.isBefore(to))
        .toList();
  }

  /// Điều hướng mượt mà với hiệu ứng chuyển trang Fintech
  Future<T?> _navigateTo<T>(BuildContext context, Widget screen) {
    return Navigator.of(context).push<T>(
      PageRouteBuilder<T>(
        pageBuilder: (context, animation, secondaryAnimation) => screen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.06, 0.0),
              end: Offset.zero,
            ).animate(curved),
            child: FadeTransition(
              opacity: curved,
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 220),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      body: SafeArea(
        child: StreamBuilder<AppUser?>(
          stream: _userStream,
          builder: (context, userSnapshot) {
            if (userSnapshot.hasError) {
              return StreamErrorWidget(error: userSnapshot.error.toString());
            }

            return StreamBuilder<List<Wallet>>(
              stream: _walletsStream,
              builder: (context, walletSnapshot) {
                if (walletSnapshot.hasError) {
                  return StreamErrorWidget(
                    error: walletSnapshot.error.toString(),
                  );
                }
                final wallets = walletSnapshot.data ?? [];
                final balance = wallets
                    .where((wallet) => wallet.isActive)
                    .fold<double>(0, (sum, wallet) => sum + wallet.balance);

                return StreamBuilder<List<Category>>(
                  stream: _categoriesStream,
                  builder: (context, categorySnapshot) {
                    if (categorySnapshot.hasError) {
                      return StreamErrorWidget(
                        error: categorySnapshot.error.toString(),
                      );
                    }

                    final categories = categorySnapshot.data ?? [];

                    return StreamBuilder<List<AppTransaction>>(
                      stream: _currentMonthTxStream,
                      builder: (context, currentMonthSnapshot) {
                        if (currentMonthSnapshot.hasError) {
                          return StreamErrorWidget(
                            error: currentMonthSnapshot.error.toString(),
                          );
                        }

                        final currentMonthTransactions =
                            currentMonthSnapshot.data ?? [];
                        final income = currentMonthTransactions
                            .where((tx) => tx.type == 'income')
                            .fold<double>(0, (sum, tx) => sum + tx.amount);
                        final expense = currentMonthTransactions
                            .where((tx) => tx.type == 'expense')
                            .fold<double>(0, (sum, tx) => sum + tx.amount);

                        // StreamBuilder riêng cho dữ liệu biểu đồ xu hướng 6 tháng
                        return StreamBuilder<List<AppTransaction>>(
                          stream: _sixMonthTxStream,
                          builder: (context, historySnapshot) {
                            if (historySnapshot.hasData) {
                              _cachedHistory = historySnapshot.data;
                            }
                            final history = _cachedHistory ?? [];

                            return _buildDashboardContent(
                              user: userSnapshot.data,
                              wallets: wallets,
                              balance: balance,
                              income: income,
                              expense: expense,
                              history: history,
                              recentTransactions: currentMonthTransactions,
                              categories: categories,
                              isHistoryLoading: !historySnapshot.hasData &&
                                  _cachedHistory == null,
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildDashboardContent({
    required AppUser? user,
    required List<Wallet> wallets,
    required double balance,
    required double income,
    required double expense,
    required List<AppTransaction> history,
    required List<AppTransaction> recentTransactions,
    required List<Category> categories,
    required bool isHistoryLoading,
  }) {
    final net = income - expense;
    final chartData = _buildSixMonthData(history);
    final selectedMonthTransactions = _transactionsForSelectedMonth(history);
    final selectedDate = _selectedMonthDate;
    final activeWalletsCount = wallets.where((w) => w.isActive).length;

    return RefreshIndicator(
      onRefresh: _handleRefresh,
      color: AppColors.primary,
      backgroundColor: context.appCard,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
        children: [
          _buildHeader(user),
          const SizedBox(height: 20),
          _buildBalanceHero(
            balance: balance,
            income: income,
            expense: expense,
            activeWalletsCount: activeWalletsCount,
          ),
          const SizedBox(height: 24),
          _sectionTitle('Thao tác nhanh'),
          const SizedBox(height: 12),
          _buildQuickActions(),
          const SizedBox(height: 24),
          _buildMonthlyOverview(
            net: net,
            income: income,
            expense: expense,
            transactionCount: recentTransactions.length,
          ),
          const SizedBox(height: 24),
          _buildTrendPanel(
            chartData: chartData,
            monthLabels: _buildMonthLabels(),
            selectedTransactions: selectedMonthTransactions,
            selectedDate: selectedDate,
            isLoading: isHistoryLoading,
          ),
          const SizedBox(height: 24),
          _buildCategoryPanel(
            selectedMonthTransactions,
            categories,
            selectedDate,
          ),
          const SizedBox(height: 28),
          _sectionTitle(
            'Giao dịch gần đây',
            actionText: 'Xem tất cả',
            onAction: () => _navigateTo(
              context,
              const TransactionListScreen(),
            ),
          ),
          const SizedBox(height: 8),
          if (recentTransactions.isEmpty)
            AppEmptyState(
              title: 'Chưa có giao dịch trong tháng này',
              subtitle: 'Ghi lại một khoản thu hoặc chi để bắt đầu theo dõi.',
              icon: Icons.receipt_long_outlined,
              actionText: 'Thêm giao dịch',
              onAction: _openNewTransaction,
            )
          else ...[
            ...recentTransactions.take(4).map(
                  (transaction) => TransactionCard(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    transaction: transaction,
                    onTap: () => _navigateTo(
                      context,
                      TransactionDetailScreen(transaction: transaction),
                    ),
                    category: categories
                        .where((category) =>
                            category.categoryId == transaction.categoryId)
                        .firstOrNull,
                  ),
                ),
            if (recentTransactions.length > 4)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: TextButton.icon(
                    onPressed: () => _navigateTo(
                      context,
                      const TransactionListScreen(),
                    ),
                    icon: const Icon(Icons.arrow_downward_rounded, size: 16),
                    label: Text(
                      'Xem toàn bộ ${recentTransactions.length} giao dịch',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 24),
          _buildAiCallout(),
        ],
      ),
    );
  }

  Widget _buildHeader(AppUser? user) {
    final name = user?.name.trim();
    final hour = DateTime.now().hour;
    final greetingPrefix = hour < 12
        ? 'Chào buổi sáng'
        : (hour < 18 ? 'Chào buổi chiều' : 'Chào buổi tối');
    final displayName = name == null || name.isEmpty ? 'bạn!' : '$name';

    return Row(
      children: [
        _buildAvatar(user),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$greetingPrefix,',
                style: TextStyle(
                  color: context.appTextSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.appTextPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
        ),
        _TactileTap(
          onTap: () => _navigateTo(context, const NotificationScreen()),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: context.appCard,
              shape: BoxShape.circle,
              border: Border.all(color: context.appBorder),
            ),
            child: Icon(
              Icons.notifications_none_rounded,
              color: context.appTextPrimary,
              size: 22,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAvatar(AppUser? user) {
    final path = user?.avatar;
    if (path != null && path.isNotEmpty) {
      return CircleAvatar(
        radius: 23,
        backgroundColor: context.appInputFill,
        backgroundImage: FileImage(File(path)),
        onBackgroundImageError: (_, __) {},
      );
    }

    final initial = user?.name.trim().isNotEmpty == true
        ? user!.name.trim().substring(0, 1).toUpperCase()
        : 'F';
    return CircleAvatar(
      radius: 23,
      backgroundColor: AppColors.primary,
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
    );
  }

  Widget _buildBalanceHero({
    required double balance,
    required double income,
    required double expense,
    required int activeWalletsCount,
  }) {
    final expenseRatio = income > 0 ? (expense / income).clamp(0.0, 1.0) : 0.0;
    final expensePercent = income > 0 ? (expense / income * 100).toInt() : 0;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: context.appInputFill,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.account_balance_wallet_outlined,
                      size: 13,
                      color: context.appTextSecondary,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Tổng tài sản • $activeWalletsCount ví',
                      style: TextStyle(
                        color: context.appTextSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              _TactileTap(
                onTap: () =>
                    setState(() => _isBalanceVisible = !_isBalanceVisible),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: context.appInputFill,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isBalanceVisible
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: context.appTextSecondary,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _isBalanceVisible
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    balance.abs() >= 1e9
                        ? AppFormatters.compactCurrency(balance, unit: 'VNĐ')
                        : AppFormatters.currency(balance),
                    style: TextStyle(
                      color: context.appTextPrimary,
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.8,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                if (balance.abs() >= 1e9) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Chi tiết: ${AppFormatters.currency(balance)}',
                    style: TextStyle(
                      color: context.appTextSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
            secondChild: Text(
              '•••••••• ₫',
              style: TextStyle(
                color: context.appTextPrimary,
                fontSize: 32,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.8,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (income > 0) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 5,
                child: Row(
                  children: [
                    Expanded(
                      flex: (expenseRatio * 100).toInt(),
                      child: Container(color: AppColors.expense),
                    ),
                    Expanded(
                      flex: ((1.0 - expenseRatio) * 100).toInt().clamp(0, 100),
                      child: Container(
                        color: AppColors.income.withValues(
                          alpha: context.isDarkMode ? 0.7 : 0.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              expensePercent > 100
                  ? 'Chi tiêu đã vượt 100% thu nhập tháng này'
                  : 'Đã chi $expensePercent% thu nhập tháng này',
              style: TextStyle(
                color: expensePercent > 100
                    ? AppColors.expense
                    : context.appTextSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ] else ...[
            Divider(height: 1, color: context.appBorder),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildHeroMetric(
                  label: 'Thu nhập tháng',
                  amount: income,
                  color: AppColors.income,
                  icon: Icons.arrow_downward_rounded,
                ),
              ),
              Container(width: 1, height: 36, color: context.appBorder),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: _buildHeroMetric(
                    label: 'Chi tiêu tháng',
                    amount: expense,
                    color: AppColors.expense,
                    icon: Icons.arrow_upward_rounded,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeroMetric({
    required String label,
    required double amount,
    required Color color,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 10),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.appTextSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            _isBalanceVisible
                ? AppFormatters.compactCurrency(amount, unit: '₫')
                : '••••••',
            style: TextStyle(
              color: context.appTextPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActions() {
    return Row(
      children: [
        _quickActionItem(
          label: 'Thu nhập',
          icon: Icons.add_circle_outline_rounded,
          color: AppColors.income,
          bgColor: AppColors.income.withValues(
            alpha: context.isDarkMode ? 0.16 : 0.08,
          ),
          onTap: () => _openTransaction(initialType: 'income'),
        ),
        const SizedBox(width: 10),
        _quickActionItem(
          label: 'Chuyển tiền',
          icon: Icons.swap_horiz_rounded,
          color: AppColors.primary,
          bgColor: AppColors.primary.withValues(
            alpha: context.isDarkMode ? 0.16 : 0.08,
          ),
          onTap: () => _openTransaction(isTransfer: true),
        ),
        const SizedBox(width: 10),
        _quickActionItem(
          label: 'Quét hóa đơn',
          icon: Icons.document_scanner_outlined,
          color: AppColors.warning,
          bgColor: AppColors.warning.withValues(
            alpha: context.isDarkMode ? 0.16 : 0.08,
          ),
          badge: 'OCR',
          onTap: () => _openTransaction(autoTriggerOcr: true),
        ),
        const SizedBox(width: 10),
        _quickActionItem(
          label: 'Báo cáo AI',
          icon: Icons.auto_awesome_rounded,
          color: AppColors.primary,
          bgColor: AppColors.primary.withValues(
            alpha: context.isDarkMode ? 0.16 : 0.08,
          ),
          badge: 'AI',
          onTap: () => _navigateTo(context, const AiReportScreen()),
        ),
      ],
    );
  }

  Widget _quickActionItem({
    required String label,
    required IconData icon,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
    String? badge,
  }) {
    return Expanded(
      child: _TactileTap(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
            color: context.appCard,
            borderRadius: BorderRadius.circular(AppColors.radiusCard),
            border: Border.all(color: context.appBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 22),
                  ),
                  if (badge != null)
                    Positioned(
                      top: -4,
                      right: -6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          badge,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.appTextPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Thẻ tổng quan dòng tiền - Tự động co dãn chống tràn số tiền lớn
  Widget _buildMonthlyOverview({
    required double net,
    required double income,
    required double expense,
    required int transactionCount,
  }) {
    final isPositive = net >= 0;
    final accent = isPositive ? AppColors.income : AppColors.expense;
    final savingsRate =
        income > 0 ? ((net / income) * 100).clamp(0, 100).toInt() : 0;

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accent.withValues(
                alpha: context.isDarkMode ? 0.20 : 0.10,
              ),
              borderRadius: BorderRadius.circular(AppColors.radiusControl),
            ),
            child: Icon(
              isPositive
                  ? Icons.trending_up_rounded
                  : Icons.trending_down_rounded,
              color: accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isPositive ? 'Dòng tiền thặng dư' : 'Dòng tiền thâm hụt',
                  style: TextStyle(
                    color: context.appTextPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '$transactionCount giao dịch tháng này',
                  style: TextStyle(
                    color: context.appTextSecondary,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 135),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    _isBalanceVisible
                        ? '${isPositive ? '+' : ''}${AppFormatters.compactCurrency(net, unit: 'VNĐ')}'
                        : '••••••',
                    style: TextStyle(
                      color: accent,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              if (isPositive && income > 0) ...[
                const SizedBox(height: 3),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.income.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '+$savingsRate% tích lũy',
                    style: const TextStyle(
                      color: AppColors.income,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ] else if (!isPositive) ...[
                const SizedBox(height: 3),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.expense.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Cảnh báo bội chi',
                    style: TextStyle(
                      color: AppColors.expense,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTrendPanel({
    required Map<String, List<double>> chartData,
    required List<String> monthLabels,
    required List<AppTransaction> selectedTransactions,
    required DateTime selectedDate,
    required bool isLoading,
  }) {
    final selectedIncome = selectedTransactions
        .where((tx) => tx.type == 'income')
        .fold<double>(0, (sum, tx) => sum + tx.amount);
    final selectedExpense = selectedTransactions
        .where((tx) => tx.type == 'expense')
        .fold<double>(0, (sum, tx) => sum + tx.amount);
    final selectedNet = selectedIncome - selectedExpense;

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dòng tiền theo tháng',
                      style: TextStyle(
                        color: context.appTextPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Chạm cột để xem chi tiết từng tháng',
                      style: TextStyle(
                        color: context.appTextSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _buildYearMenu(),
            ],
          ),
          const SizedBox(height: 14),
          _buildHalfSelector(),
          const SizedBox(height: 14),
          Row(
            children: [
              _legendItem('Thu nhập', AppColors.income),
              const SizedBox(width: 14),
              _legendItem('Chi tiêu', AppColors.expense),
            ],
          ),
          const SizedBox(height: 12),
          IncomeExpenseBarChart(
            incomeByMonth: chartData['income']!,
            expenseByMonth: chartData['expense']!,
            monthLabels: monthLabels,
            selectedIndex: _selectedMonthIndex,
            onMonthTap: (index) => setState(() => _selectedMonthIndex = index),
          ),
          const SizedBox(height: 12),
          // Thanh tóm tắt tháng được chọn thiết kế cấu trúc 2 tầng chuẩn mực, chống tràn 100%
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: context.appInputFill,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: context.appBorder.withValues(alpha: 0.5),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Hàng 1: Tháng được chọn và nhãn Hiện tại (bỏ số tiền trùng lặp vì đã có ô Tổng thu & Tổng chi bên dưới)
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      size: 14,
                      color: context.appTextSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Tháng ${selectedDate.month}/${selectedDate.year}',
                      style: TextStyle(
                        color: context.appTextPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (selectedDate.year == DateTime.now().year &&
                        selectedDate.month == DateTime.now().month) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Hiện tại',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                // Hàng 2: Hai ô thống kê Tổng thu và Tổng chi với FittedBox chống tràn số tiền lớn
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: context.appCard,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: context.appBorder.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: AppColors.income,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'Tổng thu',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: context.appTextSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '+${AppFormatters.compactCurrency(selectedIncome, unit: '₫')}',
                                style: const TextStyle(
                                  color: AppColors.income,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: context.appCard,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: context.appBorder.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: AppColors.expense,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'Tổng chi',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: context.appTextSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '-${AppFormatters.compactCurrency(selectedExpense, unit: '₫')}',
                                style: const TextStyle(
                                  color: AppColors.expense,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildYearMenu() {
    final currentYear = DateTime.now().year;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: context.appInputFill,
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _selectedYear,
          isDense: true,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: context.appTextSecondary,
          ),
          style: TextStyle(
            color: context.appTextPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          items: [
            for (var year = currentYear - 3; year <= currentYear + 1; year++)
              DropdownMenuItem(
                value: year,
                child: Text(
                  year == currentYear ? '$year (Hiện tại)' : '$year',
                ),
              ),
          ],
          onChanged: (year) {
            if (year == null) return;
            setState(() {
              _selectedYear = year;
              _selectedMonthIndex = _defaultMonthIndexFor(year, _selectedHalf);
              _refreshSixMonthStream();
            });
          },
        ),
      ),
    );
  }

  Widget _buildHalfSelector() {
    final now = DateTime.now();
    final isCurrentYear = _selectedYear == now.year;
    final currentHalf = now.month <= 6 ? 1 : 2;

    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: context.appInputFill,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _halfOption(
            label: '6 tháng đầu (T1–T6)',
            isRealtimeCurrent: isCurrentYear && currentHalf == 1,
            value: 1,
          ),
          _halfOption(
            label: '6 tháng cuối (T7–T12)',
            isRealtimeCurrent: isCurrentYear && currentHalf == 2,
            value: 2,
          ),
        ],
      ),
    );
  }

  Widget _halfOption({
    required String label,
    required bool isRealtimeCurrent,
    required int value,
  }) {
    final isSelected = _selectedHalf == value;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          if (isSelected) return;
          setState(() {
            _selectedHalf = value;
            _selectedMonthIndex = _defaultMonthIndexFor(_selectedYear, value);
            _refreshSixMonthStream();
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? context.appCard : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isSelected
                          ? context.appTextPrimary
                          : context.appTextSecondary,
                      fontSize: 12,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
              if (isRealtimeCurrent) ...[
                const SizedBox(width: 4),
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _legendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(color: context.appTextSecondary, fontSize: 12),
        ),
      ],
    );
  }

  /// Bảng phân loại danh mục: Hỗ trợ chuyển đổi giữa Chi tiêu & Thu nhập
  Widget _buildCategoryPanel(
    List<AppTransaction> transactions,
    List<Category> categories,
    DateTime selectedDate,
  ) {
    final isExpense = _selectedCategoryType == 'expense';
    final filteredTransactions =
        transactions.where((tx) => tx.type == _selectedCategoryType);

    final totals = <String, double>{};
    for (final transaction in filteredTransactions) {
      final category = categories
          .where((item) => item.categoryId == transaction.categoryId)
          .firstOrNull;
      final name = category?.name ?? 'Khác';
      totals[name] = (totals[name] ?? 0) + transaction.amount;
    }

    final totalAmount =
        totals.values.fold<double>(0, (sum, amount) => sum + amount);
    final sortedCategories = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Bảng màu chuyên biệt cho Chi tiêu và Thu nhập
    final categoryColors = isExpense
        ? const [
            AppColors.expense,
            AppColors.warning,
            Color(0xFFE11D48),
            Color(0xFFF97316),
            Color(0xFF8B5CF6),
            Color(0xFFEC4899),
            Color(0xFF64748B),
          ]
        : const [
            AppColors.income,
            Color(0xFF10B981),
            Color(0xFF059669),
            AppColors.primary,
            Color(0xFF0D9488),
            Color(0xFF0284C7),
            Color(0xFF6366F1),
          ];

    final themeColor = isExpense ? AppColors.expense : AppColors.income;

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tiêu đề trọn vẹn bề ngang không bị co ép hay xuống dòng
          Text(
            isExpense ? 'Chi tiêu theo danh mục' : 'Thu nhập theo danh mục',
            style: TextStyle(
              color: context.appTextPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Tháng ${selectedDate.month}/${selectedDate.year}',
            style: TextStyle(
              color: context.appTextSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          // Nút chuyển đổi: Chi tiêu vs Thu nhập
          _buildCategoryTypeSelector(),
          // Thanh tổng tiền thu/chi nằm riêng biệt phía dưới bộ chọn, thẩm mỹ và không gây tràn chữ
          if (totalAmount > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: themeColor.withValues(
                  alpha: context.isDarkMode ? 0.16 : 0.08,
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: themeColor.withValues(alpha: 0.20),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isExpense
                        ? Icons.arrow_outward_rounded
                        : Icons.arrow_downward_rounded,
                    size: 16,
                    color: themeColor,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isExpense ? 'Tổng chi tiêu tháng:' : 'Tổng thu nhập tháng:',
                    style: TextStyle(
                      color: context.appTextPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      AppFormatters.compactCurrency(totalAmount, unit: '₫'),
                      style: TextStyle(
                        color: themeColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (totals.isEmpty)
            SizedBox(
              height: 120,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.pie_chart_outline_rounded,
                      size: 28,
                      color: context.appTextSecondary.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isExpense
                          ? 'Không có khoản chi trong tháng ${selectedDate.month}/${selectedDate.year}'
                          : 'Không có khoản thu trong tháng ${selectedDate.month}/${selectedDate.year}',
                      style: TextStyle(
                        color: context.appTextSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            CategoryPieChart(
              categoryTotals: totals,
              colors: categoryColors,
            ),
            const SizedBox(height: 16),
            Divider(height: 1, color: context.appBorder),
            const SizedBox(height: 12),
            Text(
              isExpense ? 'Top danh mục chi tiêu' : 'Top nguồn thu nhập',
              style: TextStyle(
                color: context.appTextSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ...sortedCategories.take(3).map((entry) {
              final pct = totalAmount > 0 ? (entry.value / totalAmount) : 0.0;
              final matchedCat =
                  categories.where((c) => c.name == entry.key).firstOrNull;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          _getCategoryIcon(matchedCat?.icon),
                          size: 16,
                          color: context.appTextSecondary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            entry.key,
                            style: TextStyle(
                              color: context.appTextPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${(pct * 100).toStringAsFixed(0)}%',
                          style: TextStyle(
                            color: context.appTextSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 110),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              AppFormatters.compactCurrency(entry.value,
                                  unit: '₫'),
                              style: TextStyle(
                                color: context.appTextPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 4,
                        backgroundColor: context.appInputFill,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          themeColor,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  /// Nút chọn loại danh mục: Chi tiêu vs Thu nhập
  Widget _buildCategoryTypeSelector() {
    return Container(
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: context.appInputFill,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _categoryTypeOption(label: 'Chi tiêu', value: 'expense'),
          _categoryTypeOption(label: 'Thu nhập', value: 'income'),
        ],
      ),
    );
  }

  Widget _categoryTypeOption({
    required String label,
    required String value,
  }) {
    final isSelected = _selectedCategoryType == value;
    final isExpense = value == 'expense';
    final activeColor = isExpense ? AppColors.expense : AppColors.income;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          if (isSelected) return;
          setState(() => _selectedCategoryType = value);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? context.appCard : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: isSelected
                      ? activeColor
                      : context.appTextSecondary.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? context.appTextPrimary
                      : context.appTextSecondary,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAiCallout() {
    return _TactileTap(
      onTap: () => _navigateTo(context, const AiInsightScreen()),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.aiAccent.withValues(
            alpha: context.isDarkMode ? 0.16 : 0.06,
          ),
          borderRadius: BorderRadius.circular(AppColors.radiusCard),
          border: Border.all(
            color: AppColors.aiAccent.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.aiAccent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Trợ lý FinAI',
                        style: TextStyle(
                          color: context.appTextPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.aiAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Thông minh',
                          style: TextStyle(
                            color: AppColors.aiAccent,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Xem điểm sức khỏe tài chính và gợi ý tối ưu chi tiêu.',
                    style: TextStyle(
                      color: context.appTextSecondary,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: AppColors.aiAccent.withValues(alpha: 0.8),
              size: 14,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(
    String title, {
    String? actionText,
    VoidCallback? onAction,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: context.appTextPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.25,
            ),
          ),
        ),
        if (actionText != null && onAction != null)
          _TactileTap(
            onTap: onAction,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text(
                actionText,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _openNewTransaction() => _openTransaction();

  void _openTransaction({
    String? initialType,
    bool isTransfer = false,
    bool autoTriggerOcr = false,
  }) {
    _navigateTo(
      context,
      AddTransactionScreen(
        initialType: initialType,
        initialIsTransfer: isTransfer ? true : null,
        autoTriggerOcr: autoTriggerOcr ? true : null,
      ),
    );
  }

  IconData _getCategoryIcon(String? iconName) {
    switch (iconName) {
      case 'work':
        return Icons.work_outline_rounded;
      case 'card_giftcard':
        return Icons.card_giftcard_rounded;
      case 'storefront':
        return Icons.storefront_rounded;
      case 'restaurant':
        return Icons.restaurant_rounded;
      case 'shopping_bag':
        return Icons.shopping_bag_outlined;
      case 'local_gas_station':
        return Icons.local_gas_station_rounded;
      case 'school':
        return Icons.school_outlined;
      case 'movie':
        return Icons.movie_outlined;
      case 'flight':
        return Icons.flight_takeoff_rounded;
      case 'local_hospital':
        return Icons.local_hospital_outlined;
      default:
        return Icons.receipt_long_rounded;
    }
  }
}

/// Widget bọc hiệu ứng nhấn nhẹ (Tactile bounce)
class _TactileTap extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final double scale;

  const _TactileTap({
    required this.child,
    required this.onTap,
    this.scale = 0.94,
  });

  @override
  State<_TactileTap> createState() => _TactileTapState();
}

class _TactileTapState extends State<_TactileTap> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/transaction_model.dart';
import '../../models/category_model.dart';
import '../../models/wallet_model.dart';
import '../../services/firestore_service.dart';
import '../../services/financial_export_service.dart';
import '../../services/transaction_intelligence_service.dart';
import '../../utils/constants.dart';
import '../../utils/formatters.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/transaction_card.dart';
import '../../widgets/stream_error_widget.dart';
import 'transaction_detail_screen.dart';

/// ============================================================
/// TRANSACTION LIST SCREEN (LỊCH SỬ GIAO DỊCH CHUẨN FINTECH)
/// - Tìm kiếm thông minh: theo ghi chú, danh mục, tên ví, số tiền, ngày tháng, tiếng Việt không dấu.
/// - Thẻ thống kê tài chính trực quan: Thu, Chi, Dòng tiền của tập giao dịch đang xem.
/// - Bộ lọc đa chiều: Loại, Khoảng thời gian, Danh mục, Ví tiền, Mức tiền, Sắp xếp.
/// - Phân nhóm theo ngày chuyên nghiệp với tổng thu/chi từng ngày.
/// ============================================================
class TransactionListScreen extends StatefulWidget {
  const TransactionListScreen({super.key});

  @override
  State<TransactionListScreen> createState() => _TransactionListScreenState();
}

class _TransactionListScreenState extends State<TransactionListScreen> {
  final _firestoreService = FirestoreService();
  final _exportService = FinancialExportService();
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  late final String _uid;
  late Stream<List<AppTransaction>> _transactionsStream;
  late final Stream<List<Category>> _categoriesStream;
  late final Stream<List<Wallet>> _walletsStream;

  // Search & Filter State
  String _searchQuery = '';
  String _typeFilter = 'all'; // 'all' | 'expense' | 'income' | 'transfer'
  String _timeFilter =
      'all'; // 'all' | 'today' | 'this_month' | 'last_month' | 'last_7_days' | 'custom_date' | 'custom_range'
  DateTime? _selectedDate;
  DateTime? _selectedMonth;
  DateTimeRange? _selectedDateRange;
  String? _selectedCategoryId;
  String? _selectedWalletId;
  String _amountFilter =
      'all'; // 'all' | 'under_100k' | '100k_500k' | '500k_2m' | 'over_2m'
  String _sortBy =
      'newest'; // 'newest' | 'oldest' | 'amount_desc' | 'amount_asc'

  bool _isExportingCsv = false;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _categoriesStream = _firestoreService.streamCategories(_uid);
    _walletsStream = _firestoreService.streamWallets(_uid);
    _transactionsStream = _firestoreService.streamTransactions(_uid);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// Đếm số lượng bộ lọc đang được kích hoạt (khác mặc định)
  int get _activeFilterCount {
    int count = 0;
    if (_typeFilter != 'all') count++;
    if (_timeFilter != 'all' ||
        _selectedDate != null ||
        _selectedMonth != null ||
        _selectedDateRange != null) count++;
    if (_selectedCategoryId != null) count++;
    if (_selectedWalletId != null) count++;
    if (_amountFilter != 'all') count++;
    if (_sortBy != 'newest') count++;
    return count;
  }

  /// Đặt lại toàn bộ bộ lọc về mặc định
  void _resetAllFilters() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _typeFilter = 'all';
      _timeFilter = 'all';
      _selectedDate = null;
      _selectedMonth = null;
      _selectedDateRange = null;
      _selectedCategoryId = null;
      _selectedWalletId = null;
      _amountFilter = 'all';
      _sortBy = 'newest';
    });
  }

  // ============================================================
  // THUẬT TOÁN TÌM KIẾM THÔNG MINH (SMART SEARCH)
  // ============================================================
  bool _matchesSearch(
    AppTransaction tx,
    Category? category,
    Wallet? wallet,
    Wallet? toWallet,
    String query,
  ) {
    return TransactionSearchFilterHelper.matchesSearch(
        tx, category, wallet, toWallet, query);
  }

  // ============================================================
  // BỘ LỌC THỜI GIAN & ĐIỀU KIỆN
  // ============================================================
  bool _matchesTimeFilter(DateTime txDate) {
    final now = DateTime.now();

    if (_timeFilter == 'today') {
      return txDate.year == now.year &&
          txDate.month == now.month &&
          txDate.day == now.day;
    }
    if (_timeFilter == 'last_7_days') {
      final start = DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 6));
      return txDate.isAfter(start.subtract(const Duration(seconds: 1)));
    }
    if (_timeFilter == 'this_month') {
      return txDate.year == now.year && txDate.month == now.month;
    }
    if (_timeFilter == 'last_month') {
      final lastMonth = DateTime(now.year, now.month - 1, 1);
      return txDate.year == lastMonth.year && txDate.month == lastMonth.month;
    }
    if (_timeFilter == 'custom_date' && _selectedDate != null) {
      return txDate.year == _selectedDate!.year &&
          txDate.month == _selectedDate!.month &&
          txDate.day == _selectedDate!.day;
    }
    if (_timeFilter == 'custom_month' && _selectedMonth != null) {
      return txDate.year == _selectedMonth!.year &&
          txDate.month == _selectedMonth!.month;
    }
    if (_timeFilter == 'custom_range' && _selectedDateRange != null) {
      final start = DateTime(_selectedDateRange!.start.year,
          _selectedDateRange!.start.month, _selectedDateRange!.start.day);
      final end = DateTime(
          _selectedDateRange!.end.year,
          _selectedDateRange!.end.month,
          _selectedDateRange!.end.day,
          23,
          59,
          59);
      return txDate.isAfter(start.subtract(const Duration(seconds: 1))) &&
          txDate.isBefore(end.add(const Duration(seconds: 1)));
    }
    return true;
  }

  bool _matchesAmountFilter(double amount) {
    if (_amountFilter == 'under_100k') return amount < 100000;
    if (_amountFilter == '100k_500k')
      return amount >= 100000 && amount <= 500000;
    if (_amountFilter == '500k_2m') return amount > 500000 && amount <= 2000000;
    if (_amountFilter == 'over_2m') return amount > 2000000;
    return true;
  }

  // ============================================================
  // XUẤT CSV AN TOÀN
  // ============================================================
  Future<void> _exportFilteredCsv(List<AppTransaction> filteredList,
      List<Category> categories, List<Wallet> wallets) async {
    if (_isExportingCsv || filteredList.isEmpty) return;
    setState(() => _isExportingCsv = true);

    try {
      final savingGoals = await _firestoreService.streamSavingGoals(_uid).first;
      final now = DateTime.now();
      final prefix =
          'giao_dich_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';

      final csvFile = await _exportService.exportTransactionsCsv(
        transactions: filteredList,
        categories: categories,
        wallets: wallets,
        savingGoals: savingGoals,
        filenamePrefix: prefix,
      );

      if (!mounted) return;
      AppSnackbar.show(context, 'Đã xuất file CSV thành công');

      await _exportService.shareFile(
        csvFile.path,
        text: 'Xuất danh sách ${filteredList.length} giao dịch',
        subject: 'Dữ liệu giao dịch',
      );
    } catch (e) {
      debugPrint('Export CSV Error: $e');
      if (mounted) {
        AppSnackbar.show(context, 'Không thể xuất file: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isExportingCsv = false);
    }
  }

  // ============================================================
  // GIAO DIỆN CHÍNH (BUILD)
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: _buildAppBar(),
      body: StreamBuilder<List<AppTransaction>>(
        stream: _transactionsStream,
        builder: (context, txSnap) {
          if (txSnap.hasError)
            return StreamErrorWidget(error: txSnap.error.toString());
          if (!txSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final allTransactions = txSnap.data ?? [];

          return StreamBuilder<List<Category>>(
            stream: _categoriesStream,
            builder: (context, catSnap) {
              final categories = catSnap.data ?? [];

              return StreamBuilder<List<Wallet>>(
                stream: _walletsStream,
                builder: (context, walletSnap) {
                  final wallets = walletSnap.data ?? [];

                  // Áp dụng tìm kiếm và tất cả bộ lọc
                  final filteredTransactions = allTransactions.where((tx) {
                    final cat = categories.cast<Category?>().firstWhere(
                          (c) => c?.categoryId == tx.categoryId,
                          orElse: () => null,
                        );
                    final wallet = wallets.cast<Wallet?>().firstWhere(
                          (w) => w?.walletId == tx.walletId,
                          orElse: () => null,
                        );
                    final toWallet = tx.toWalletId != null
                        ? wallets.cast<Wallet?>().firstWhere(
                              (w) => w?.walletId == tx.toWalletId,
                              orElse: () => null,
                            )
                        : null;

                    // 1. Loại giao dịch
                    if (_typeFilter != 'all') {
                      if (_typeFilter == 'transfer') {
                        if (tx.type != 'transfer' && !tx.type.contains('goal'))
                          return false;
                      } else if (tx.type != _typeFilter) {
                        return false;
                      }
                    }

                    // 2. Thời gian
                    if (!_matchesTimeFilter(tx.date)) return false;

                    // 3. Danh mục
                    if (_selectedCategoryId != null &&
                        tx.categoryId != _selectedCategoryId) {
                      return false;
                    }

                    // 4. Ví tiền
                    if (_selectedWalletId != null &&
                        tx.walletId != _selectedWalletId &&
                        tx.toWalletId != _selectedWalletId) {
                      return false;
                    }

                    // 5. Khoảng số tiền
                    if (!_matchesAmountFilter(tx.amount)) return false;

                    // 6. Tìm kiếm thông minh
                    return _matchesSearch(
                        tx, cat, wallet, toWallet, _searchQuery);
                  }).toList();

                  // Sắp xếp danh sách
                  _sortTransactions(filteredTransactions);

                  return Column(
                    children: [
                      // 1. Thanh Tìm kiếm Đa năng
                      _buildSearchBar(),

                      // 2. Thanh Quick Filters cuộn ngang
                      _buildQuickFiltersRow(categories, wallets),

                      // 3. Feedback kết quả tìm kiếm (nếu đang search/lọc)
                      if (_searchQuery.isNotEmpty || _activeFilterCount > 0)
                        _buildFilterFeedbackBar(filteredTransactions.length,
                            allTransactions.length),

                      // 4. Danh sách Giao dịch phân nhóm theo ngày
                      Expanded(
                        child: filteredTransactions.isEmpty
                            ? _buildEmptyState(allTransactions.isEmpty)
                            : _buildGroupedListView(
                                filteredTransactions, categories, wallets),
                      ),
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

  /// AppBar chuẩn Fintech sang trọng
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: context.appCard,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleSpacing: 16,
      title: Text(
        'Lịch sử giao dịch',
        style: GoogleFonts.inter(
          fontWeight: FontWeight.bold,
          fontSize: 18.5,
          color: context.appTextPrimary,
        ),
      ),
      actions: [
        // Nút Xuất CSV
        IconButton(
          icon: _isExportingCsv
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.primary),
                )
              : Icon(Icons.file_download_outlined,
                  color: context.appTextPrimary, size: 22),
          tooltip: 'Xuất CSV',
          onPressed: _isExportingCsv
              ? null
              : () async {
                  final transactions =
                      await _firestoreService.streamTransactions(_uid).first;
                  final categories =
                      await _firestoreService.streamCategories(_uid).first;
                  final wallets =
                      await _firestoreService.streamWallets(_uid).first;
                  _exportFilteredCsv(transactions, categories, wallets);
                },
        ),

        // Nút Bộ Lọc Nâng Cao kèm Badge
        Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: Icon(
                _activeFilterCount > 0
                    ? Icons.tune_rounded
                    : Icons.filter_list_rounded,
                color: _activeFilterCount > 0
                    ? AppColors.primary
                    : context.appTextPrimary,
                size: 21,
              ),
              tooltip: 'Bộ lọc nâng cao',
              onPressed: () => _showAdvancedFilterModal(),
            ),
            if (_activeFilterCount > 0)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.all(3.5),
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$_activeFilterCount',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8.5,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  /// Thanh Tìm kiếm Thông minh chuẩn Fintech
  Widget _buildSearchBar() {
    final hasFocus = _searchFocusNode.hasFocus;
    final hasQuery = _searchQuery.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 48,
        decoration: BoxDecoration(
          color: context.appCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasFocus
                ? AppColors.primary
                : context.appBorder.withValues(alpha: 0.9),
            width: hasFocus ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: hasFocus
                  ? AppColors.primary.withValues(alpha: 0.12)
                  : Colors.black
                      .withValues(alpha: context.isDarkMode ? 0.25 : 0.04),
              blurRadius: hasFocus ? 10 : 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Icon kính lúp trong hộp mềm
            Container(
              margin: const EdgeInsets.only(left: 10, right: 10),
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: (hasFocus || hasQuery)
                    ? AppColors.primary.withValues(alpha: 0.12)
                    : (context.isDarkMode
                        ? AppColors.slate700
                        : AppColors.slate100),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.search_rounded,
                color: (hasFocus || hasQuery)
                    ? AppColors.primary
                    : context.appTextSecondary,
                size: 18,
              ),
            ),

            // Input field
            Expanded(
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: (v) => setState(() => _searchQuery = v),
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: context.appTextPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Tìm theo ghi chú, danh mục, ví, số tiền...',
                  hintStyle: GoogleFonts.inter(
                    color: context.appTextSecondary.withValues(alpha: 0.75),
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),

            // Nút xóa từ khóa
            if (hasQuery)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: context.isDarkMode
                          ? AppColors.slate700
                          : AppColors.slate200,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      size: 13,
                      color: context.appTextSecondary,
                    ),
                  ),
                  tooltip: 'Xóa tìm kiếm',
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Thanh Quick Filters cuộn ngang tiện lợi
  Widget _buildQuickFiltersRow(
      List<Category> categories, List<Wallet> wallets) {
    return Container(
      height: 38,
      margin: const EdgeInsets.only(top: 6, bottom: 4),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          // 1. Nút mở Modal Bộ lọc Tổng hợp
          ActionChip(
            avatar: Icon(
              Icons.tune_rounded,
              size: 15,
              color: _activeFilterCount > 0 ? Colors.white : AppColors.primary,
            ),
            label: Text(
              _activeFilterCount > 0
                  ? 'Bộ lọc ($_activeFilterCount)'
                  : 'Bộ lọc',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _activeFilterCount > 0
                    ? Colors.white
                    : context.appTextPrimary,
              ),
            ),
            backgroundColor:
                _activeFilterCount > 0 ? AppColors.primary : context.appCard,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: _activeFilterCount > 0
                    ? AppColors.primary
                    : context.appBorder,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            onPressed: () => _showAdvancedFilterModal(),
          ),
          const SizedBox(width: 8),

          // 2. Chip Loại giao dịch
          _buildFilterChip(
            label: _typeFilter == 'all'
                ? 'Loại: Tất cả'
                : (_typeFilter == 'expense'
                    ? 'Chi tiêu'
                    : (_typeFilter == 'income' ? 'Thu nhập' : 'Chuyển khoản')),
            isActive: _typeFilter != 'all',
            onTap: () => _showTypePicker(),
          ),
          const SizedBox(width: 6),

          // 3. Chip Thời gian
          _buildFilterChip(
            label: _getTimeFilterLabel(),
            isActive: _timeFilter != 'all',
            onTap: () => _showTimeFilterPicker(),
          ),
          const SizedBox(width: 6),

          // 4. Chip Danh mục
          _buildFilterChip(
            label: _selectedCategoryId != null
                ? (categories
                    .firstWhere((c) => c.categoryId == _selectedCategoryId,
                        orElse: () => categories.first)
                    .name)
                : 'Danh mục',
            isActive: _selectedCategoryId != null,
            onTap: () => _showCategoryPicker(categories),
          ),
          const SizedBox(width: 6),

          // 5. Chip Ví tiền
          _buildFilterChip(
            label: _selectedWalletId != null
                ? (wallets
                    .firstWhere((w) => w.walletId == _selectedWalletId,
                        orElse: () => wallets.first)
                    .walletName)
                : 'Ví tiền',
            isActive: _selectedWalletId != null,
            onTap: () => _showWalletPicker(wallets),
          ),
          const SizedBox(width: 6),

          // 6. Chip Sắp xếp
          _buildFilterChip(
            label: _getSortLabel(),
            isActive: _sortBy != 'newest',
            onTap: () => _showSortPicker(),
          ),

          // Nút Đặt lại toàn bộ
          if (_activeFilterCount > 0) ...[
            const SizedBox(width: 8),
            ActionChip(
              avatar: const Icon(Icons.refresh_rounded,
                  size: 14, color: AppColors.expense),
              label: const Text(
                'Đặt lại',
                style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.expense,
                    fontWeight: FontWeight.bold),
              ),
              backgroundColor: AppColors.expenseBackground,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side:
                    BorderSide(color: AppColors.expense.withValues(alpha: 0.3)),
              ),
              onPressed: _resetAllFilters,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primary.withValues(alpha: 0.12)
              : context.appCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? AppColors.primary : context.appBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                color: isActive ? AppColors.primary : context.appTextPrimary,
              ),
            ),
            const SizedBox(width: 3),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 15,
              color: isActive ? AppColors.primary : context.appTextSecondary,
            ),
          ],
        ),
      ),
    );
  }

  String _getTimeFilterLabel() {
    if (_timeFilter == 'today') return 'Hôm nay';
    if (_timeFilter == 'this_month') return 'Tháng này';
    if (_timeFilter == 'last_month') return 'Tháng trước';
    if (_timeFilter == 'last_7_days') return '7 ngày qua';
    if (_timeFilter == 'custom_date' && _selectedDate != null) {
      return AppFormatters.date(_selectedDate!);
    }
    if (_timeFilter == 'custom_month' && _selectedMonth != null) {
      return 'Tháng ${_selectedMonth!.month}/${_selectedMonth!.year}';
    }
    if (_timeFilter == 'custom_range' && _selectedDateRange != null) {
      return '${AppFormatters.date(_selectedDateRange!.start)} - ${AppFormatters.date(_selectedDateRange!.end)}';
    }
    return 'Thời gian';
  }

  String _getSortLabel() {
    if (_sortBy == 'oldest') return 'Cũ nhất';
    if (_sortBy == 'amount_desc') return 'Số tiền: Cao ➔ Thấp';
    if (_sortBy == 'amount_asc') return 'Số tiền: Thấp ➔ Cao';
    return 'Mới nhất';
  }

  /// Thanh phản hồi kết quả tìm kiếm/lọc
  Widget _buildFilterFeedbackBar(int filteredCount, int totalCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              'Tìm thấy $filteredCount / $totalCount giao dịch',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.appTextSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_searchQuery.isNotEmpty || _activeFilterCount > 0)
            InkWell(
              onTap: _resetAllFilters,
              child: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Text(
                  'Xóa bộ lọc',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Danh sách Giao dịch Phân nhóm Theo Ngày chuyên nghiệp
  Widget _buildGroupedListView(
    List<AppTransaction> transactions,
    List<Category> categories,
    List<Wallet> wallets,
  ) {
    final grouped = _groupByDay(transactions);

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      itemCount: grouped.length,
      itemBuilder: (context, i) {
        final entry = grouped.entries.elementAt(i);
        final dayTxList = entry.value;
        final date = dayTxList.first.date;

        // Tính tổng chi và tổng thu trong ngày
        double dayExpense = 0;
        double dayIncome = 0;
        for (final t in dayTxList) {
          if (t.type == 'expense') dayExpense += t.amount;
          if (t.type == 'income') dayIncome += t.amount;
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: context.appCard,
            borderRadius: BorderRadius.circular(AppColors.radiusCard),
            border: Border.all(color: context.appBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Date Header
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: context.isDarkMode
                      ? AppColors.slate800.withValues(alpha: 0.7)
                      : AppColors.slate100.withValues(alpha: 0.7),
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(AppColors.radiusCard)),
                  border: Border(
                      bottom: BorderSide(
                          color: context.appBorder.withValues(alpha: 0.5))),
                ),
                child: Row(
                  children: [
                    // Ngày tháng năm bên trái
                    Expanded(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.calendar_today_rounded,
                            size: 13,
                            color: AppColors.primary.withValues(alpha: 0.9),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              _formatDayDetailed(date),
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: context.appTextPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Thống kê Thu / Chi trong ngày dạng Micro-Badge tinh tế
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (dayIncome > 0)
                            Flexible(
                              child: _buildHeaderAmountBadge(
                                text:
                                    '+${AppFormatters.compactCurrency(dayIncome)}',
                                color: AppColors.income,
                                icon: Icons.arrow_upward_rounded,
                              ),
                            ),
                          if (dayIncome > 0 && dayExpense > 0)
                            const SizedBox(width: 5),
                          if (dayExpense > 0)
                            Flexible(
                              child: _buildHeaderAmountBadge(
                                text:
                                    '-${AppFormatters.compactCurrency(dayExpense)}',
                                color: AppColors.expense,
                                icon: Icons.arrow_downward_rounded,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // 2. Danh sách các giao dịch trong ngày
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                itemCount: dayTxList.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  indent: 14,
                  endIndent: 14,
                  color: context.appBorder.withValues(alpha: 0.5),
                ),
                itemBuilder: (context, idx) {
                  final tx = dayTxList[idx];
                  final cat = categories.cast<Category?>().firstWhere(
                        (c) => c?.categoryId == tx.categoryId,
                        orElse: () => null,
                      );

                  return TransactionCard(
                    transaction: tx,
                    category: cat,
                    margin: EdgeInsets.zero,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            TransactionDetailScreen(transaction: tx),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// Nhóm giao dịch theo ngày
  Map<String, List<AppTransaction>> _groupByDay(
      List<AppTransaction> transactions) {
    final Map<String, List<AppTransaction>> grouped = {};
    for (final tx in transactions) {
      final key = AppFormatters.date(tx.date);
      grouped.putIfAbsent(key, () => []).add(tx);
    }
    return grouped;
  }

  String _formatDayDetailed(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final compare = DateTime(date.year, date.month, date.day);

    if (compare == today) {
      return 'Hôm nay (${AppFormatters.date(date)})';
    } else if (compare == yesterday) {
      return 'Hôm qua (${AppFormatters.date(date)})';
    } else {
      final weekdays = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
      final weekdayStr = weekdays[date.weekday - 1];
      return '$weekdayStr, ${AppFormatters.date(date)}';
    }
  }

  /// Badge hiển thị tổng thu / tổng chi trong ngày tinh tế
  Widget _buildHeaderAmountBadge({
    required String text,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6.5, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.22), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Sắp xếp danh sách theo tiêu chí
  void _sortTransactions(List<AppTransaction> list) {
    switch (_sortBy) {
      case 'oldest':
        list.sort((a, b) => a.date.compareTo(b.date));
        break;
      case 'amount_desc':
        list.sort((a, b) => b.amount.compareTo(a.amount));
        break;
      case 'amount_asc':
        list.sort((a, b) => a.amount.compareTo(b.amount));
        break;
      case 'newest':
      default:
        list.sort((a, b) => b.date.compareTo(a.date));
        break;
    }
  }

  /// Empty State đẹp mắt & Thân thiện
  Widget _buildEmptyState(bool isTotalEmpty) {
    if (isTotalEmpty) {
      return const AppEmptyState(
        title: 'Chưa có giao dịch nào',
        subtitle: 'Hãy thêm giao dịch đầu tiên để bắt đầu theo dõi thu chi.',
        icon: Icons.receipt_long_outlined,
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.search_off_rounded,
                  size: 48, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text(
              'Không tìm thấy giao dịch',
              style: GoogleFonts.inter(
                fontSize: 16.5,
                fontWeight: FontWeight.bold,
                color: context.appTextPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _searchQuery.isNotEmpty
                  ? 'Không có kết quả nào khớp với "$_searchQuery".'
                  : 'Không có giao dịch nào thỏa mãn bộ lọc hiện tại.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, color: context.appTextSecondary, height: 1.4),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Xóa bộ lọc & Tìm lại'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              onPressed: _resetAllFilters,
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // DIALOGS & MODAL BỘ LỌC CHI TIẾT
  // ============================================================
  void _showTypePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.appCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildModalHeader('Chọn loại giao dịch'),
            ListTile(
              leading:
                  const Icon(Icons.list_alt_rounded, color: AppColors.primary),
              title: const Text('Tất cả giao dịch'),
              trailing: _typeFilter == 'all'
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () {
                setState(() => _typeFilter = 'all');
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.arrow_upward_rounded,
                  color: AppColors.expense),
              title: const Text('Chi tiêu (Tiền ra)'),
              trailing: _typeFilter == 'expense'
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () {
                setState(() => _typeFilter = 'expense');
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.arrow_downward_rounded,
                  color: AppColors.income),
              title: const Text('Thu nhập (Tiền vào)'),
              trailing: _typeFilter == 'income'
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () {
                setState(() => _typeFilter = 'income');
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz_rounded,
                  color: AppColors.primary),
              title: const Text('Chuyển tiền & Mục tiêu'),
              trailing: _typeFilter == 'transfer'
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () {
                setState(() => _typeFilter = 'transfer');
                Navigator.pop(ctx);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showTimeFilterPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.appCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildModalHeader('Lọc theo thời gian'),
            ListTile(
              leading: const Icon(Icons.all_inclusive_rounded,
                  color: AppColors.primary),
              title: const Text('Tất cả thời gian'),
              trailing: _timeFilter == 'all'
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () {
                setState(() {
                  _timeFilter = 'all';
                  _selectedDate = null;
                  _selectedMonth = null;
                  _selectedDateRange = null;
                });
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.today_rounded, color: AppColors.primary),
              title: const Text('Hôm nay'),
              trailing: _timeFilter == 'today'
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () {
                setState(() => _timeFilter = 'today');
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.date_range_rounded,
                  color: AppColors.primary),
              title: const Text('7 ngày qua'),
              trailing: _timeFilter == 'last_7_days'
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () {
                setState(() => _timeFilter = 'last_7_days');
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.calendar_month_rounded,
                  color: AppColors.primary),
              title: const Text('Tháng này'),
              trailing: _timeFilter == 'this_month'
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () {
                setState(() => _timeFilter = 'this_month');
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.history_rounded, color: AppColors.primary),
              title: const Text('Tháng trước'),
              trailing: _timeFilter == 'last_month'
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () {
                setState(() => _timeFilter = 'last_month');
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.event_available_rounded,
                  color: AppColors.primary),
              title: const Text('Chọn khoảng ngày (Từ ngày ➔ Đến ngày)'),
              trailing: _timeFilter == 'custom_range'
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () async {
                Navigator.pop(ctx);
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                  initialDateRange: _selectedDateRange ??
                      DateTimeRange(
                        start: DateTime.now().subtract(const Duration(days: 7)),
                        end: DateTime.now(),
                      ),
                );
                if (picked != null) {
                  setState(() {
                    _timeFilter = 'custom_range';
                    _selectedDateRange = picked;
                  });
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showCategoryPicker(List<Category> categories) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.appCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildModalHeader('Chọn danh mục'),
            ListTile(
              title: const Text('Tất cả danh mục'),
              trailing: _selectedCategoryId == null
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () {
                setState(() => _selectedCategoryId = null);
                Navigator.pop(ctx);
              },
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: categories.length,
                itemBuilder: (context, i) {
                  final cat = categories[i];
                  final isSelected = _selectedCategoryId == cat.categoryId;
                  return ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Color(cat.color).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.category_rounded,
                          size: 16, color: Color(cat.color)),
                    ),
                    title: Text(cat.name),
                    trailing: isSelected
                        ? const Icon(Icons.check, color: AppColors.primary)
                        : null,
                    onTap: () {
                      setState(() => _selectedCategoryId = cat.categoryId);
                      Navigator.pop(ctx);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showWalletPicker(List<Wallet> wallets) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.appCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildModalHeader('Chọn ví tài khoản'),
            ListTile(
              title: const Text('Tất cả ví'),
              trailing: _selectedWalletId == null
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () {
                setState(() => _selectedWalletId = null);
                Navigator.pop(ctx);
              },
            ),
            ...wallets.map((w) {
              final isSelected = _selectedWalletId == w.walletId;
              return ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined,
                    color: AppColors.primary),
                title: Text(w.walletName),
                subtitle:
                    Text('Số dư: ${AppFormatters.compactCurrency(w.balance)}'),
                trailing: isSelected
                    ? const Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () {
                  setState(() => _selectedWalletId = w.walletId);
                  Navigator.pop(ctx);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showSortPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.appCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildModalHeader('Sắp xếp giao dịch'),
            ListTile(
              title: const Text('Mới nhất trước (Mặc định)'),
              trailing: _sortBy == 'newest'
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () {
                setState(() => _sortBy = 'newest');
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              title: const Text('Cũ nhất trước'),
              trailing: _sortBy == 'oldest'
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () {
                setState(() => _sortBy = 'oldest');
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              title: const Text('Số tiền: Lớn nhất ➔ Nhỏ nhất'),
              trailing: _sortBy == 'amount_desc'
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () {
                setState(() => _sortBy = 'amount_desc');
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              title: const Text('Số tiền: Nhỏ nhất ➔ Lớn nhất'),
              trailing: _sortBy == 'amount_asc'
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () {
                setState(() => _sortBy = 'amount_asc');
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Modal Bộ Lọc Chi Tiết Toàn Diện (Advanced Filter Sheet)
  void _showAdvancedFilterModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.appCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return SafeArea(
            child: Container(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.85),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Bộ lọc nâng cao',
                        style: GoogleFonts.inter(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: context.appTextPrimary),
                      ),
                      TextButton(
                        onPressed: () {
                          _resetAllFilters();
                          setModalState(() {});
                        },
                        child: const Text('Đặt lại',
                            style: TextStyle(color: AppColors.expense)),
                      ),
                    ],
                  ),
                  const Divider(),
                  Expanded(
                    child: ListView(
                      children: [
                        // 1. Khoảng số tiền
                        Text('Khoảng số tiền',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: context.appTextPrimary)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildModalFilterChip(
                                'Tất cả', _amountFilter == 'all', () {
                              setModalState(() => _amountFilter = 'all');
                            }),
                            _buildModalFilterChip(
                                '< 100k', _amountFilter == 'under_100k', () {
                              setModalState(() => _amountFilter = 'under_100k');
                            }),
                            _buildModalFilterChip(
                                '100k - 500k', _amountFilter == '100k_500k',
                                () {
                              setModalState(() => _amountFilter = '100k_500k');
                            }),
                            _buildModalFilterChip(
                                '500k - 2tr', _amountFilter == '500k_2m', () {
                              setModalState(() => _amountFilter = '500k_2m');
                            }),
                            _buildModalFilterChip(
                                '> 2tr', _amountFilter == 'over_2m', () {
                              setModalState(() => _amountFilter = 'over_2m');
                            }),
                          ],
                        ),
                        const SizedBox(height: 18),

                        // 2. Loại giao dịch
                        Text('Loại giao dịch',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: context.appTextPrimary)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildModalFilterChip(
                                'Tất cả', _typeFilter == 'all', () {
                              setModalState(() => _typeFilter = 'all');
                            }),
                            _buildModalFilterChip(
                                'Chi tiêu', _typeFilter == 'expense', () {
                              setModalState(() => _typeFilter = 'expense');
                            }),
                            _buildModalFilterChip(
                                'Thu nhập', _typeFilter == 'income', () {
                              setModalState(() => _typeFilter = 'income');
                            }),
                            _buildModalFilterChip(
                                'Chuyển khoản', _typeFilter == 'transfer', () {
                              setModalState(() => _typeFilter = 'transfer');
                            }),
                          ],
                        ),
                        const SizedBox(height: 18),

                        // 3. Thời gian
                        Text('Thời gian',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: context.appTextPrimary)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildModalFilterChip(
                                'Tất cả', _timeFilter == 'all', () {
                              setModalState(() => _timeFilter = 'all');
                            }),
                            _buildModalFilterChip(
                                'Hôm nay', _timeFilter == 'today', () {
                              setModalState(() => _timeFilter = 'today');
                            }),
                            _buildModalFilterChip(
                                '7 ngày qua', _timeFilter == 'last_7_days', () {
                              setModalState(() => _timeFilter = 'last_7_days');
                            }),
                            _buildModalFilterChip(
                                'Tháng này', _timeFilter == 'this_month', () {
                              setModalState(() => _timeFilter = 'this_month');
                            }),
                            _buildModalFilterChip(
                                'Tháng trước', _timeFilter == 'last_month', () {
                              setModalState(() => _timeFilter = 'last_month');
                            }),
                          ],
                        ),
                        const SizedBox(height: 18),

                        // 4. Sắp xếp
                        Text('Sắp xếp',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: context.appTextPrimary)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildModalFilterChip(
                                'Mới nhất', _sortBy == 'newest', () {
                              setModalState(() => _sortBy = 'newest');
                            }),
                            _buildModalFilterChip(
                                'Cũ nhất', _sortBy == 'oldest', () {
                              setModalState(() => _sortBy = 'oldest');
                            }),
                            _buildModalFilterChip(
                                'Tiền cao ➔ thấp', _sortBy == 'amount_desc',
                                () {
                              setModalState(() => _sortBy = 'amount_desc');
                            }),
                            _buildModalFilterChip(
                                'Tiền thấp ➔ cao', _sortBy == 'amount_asc', () {
                              setModalState(() => _sortBy = 'amount_asc');
                            }),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        setState(() {});
                        Navigator.pop(ctx);
                      },
                      child: const Text('Áp dụng bộ lọc',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildModalFilterChip(
      String label, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : context.appCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? AppColors.primary : context.appBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : context.appTextPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildModalHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title,
              style:
                  GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
          InkWell(
            onTap: () => Navigator.pop(context),
            child: const Icon(Icons.close, size: 20),
          ),
        ],
      ),
    );
  }
}

/// ============================================================
/// TRANSACTION SEARCH & FILTER HELPER
/// ============================================================
class TransactionSearchFilterHelper {
  /// Kiểm tra giao dịch có khớp với từ khóa tìm kiếm hay không
  static bool matchesSearch(
    AppTransaction tx,
    Category? category,
    Wallet? wallet,
    Wallet? toWallet,
    String query, {
    DateTime? referenceDate,
  }) {
    if (query.isEmpty) return true;

    final cleanQuery = query.trim();
    final lowerQuery = cleanQuery.toLowerCase();
    final normQuery =
        TransactionIntelligenceService.removeVietnameseDiacritics(cleanQuery);

    // 1. So khớp Ghi chú (Note)
    if (tx.note != null && tx.note!.isNotEmpty) {
      final lowerNote = tx.note!.toLowerCase();
      final normNote =
          TransactionIntelligenceService.removeVietnameseDiacritics(tx.note!);
      if (lowerNote.contains(lowerQuery) || normNote.contains(normQuery)) {
        return true;
      }
    }

    // 2. So khớp Danh mục (Category)
    if (category != null) {
      final lowerCat = category.name.toLowerCase();
      final normCat = TransactionIntelligenceService.removeVietnameseDiacritics(
          category.name);
      if (lowerCat.contains(lowerQuery) || normCat.contains(normQuery)) {
        return true;
      }
    }

    // 3. So khớp Ví nguồn & Ví đích (Wallet)
    if (wallet != null) {
      final lowerWallet = wallet.walletName.toLowerCase();
      final normWallet =
          TransactionIntelligenceService.removeVietnameseDiacritics(
              wallet.walletName);
      if (lowerWallet.contains(lowerQuery) || normWallet.contains(normQuery)) {
        return true;
      }
    }
    if (toWallet != null) {
      final lowerToWallet = toWallet.walletName.toLowerCase();
      final normToWallet =
          TransactionIntelligenceService.removeVietnameseDiacritics(
              toWallet.walletName);
      if (lowerToWallet.contains(lowerQuery) ||
          normToWallet.contains(normQuery)) {
        return true;
      }
    }

    // 4. So khớp Loại giao dịch bằng từ khóa tiếng Việt
    if (normQuery == 'thu' ||
        normQuery == 'thu nhap' ||
        normQuery == 'tien vao') {
      if (tx.type == 'income') return true;
    }
    if (normQuery == 'chi' ||
        normQuery == 'chi tieu' ||
        normQuery == 'tien ra') {
      if (tx.type == 'expense') return true;
    }
    if (normQuery == 'chuyen' ||
        normQuery == 'chuyen tien' ||
        normQuery == 'chuyen khoan') {
      if (tx.type == 'transfer') return true;
    }
    if (normQuery == 'tiet kiem' || normQuery == 'muc tieu') {
      if (tx.type.contains('goal')) return true;
    }

    // 5. So khớp Số tiền (Hỗ trợ 50k, 1tr, 50.000, > 200k, < 1tr...)
    if (matchesAmountQuery(tx.amount, cleanQuery)) {
      return true;
    }

    // 6. So khớp Ngày tháng (Hôm nay, hôm qua, tháng 10, 15/10...)
    if (matchesDateQuery(tx.date, normQuery, referenceDate: referenceDate)) {
      return true;
    }

    return false;
  }

  /// So khớp số tiền linh hoạt: số nguyên, đơn vị k/tr/ty, dấu chấm phân cách, so sánh > / <
  static bool matchesAmountQuery(double amount, String query) {
    final clean = query
        .toLowerCase()
        .replaceAll(' ', '')
        .replaceAll('₫', '')
        .replaceAll('vnđ', '')
        .replaceAll('vnd', '');

    // Toán tử so sánh lớn hơn (> 500k, >= 500k)
    if (clean.startsWith('>=') || clean.startsWith('>')) {
      final numStr =
          clean.startsWith('>=') ? clean.substring(2) : clean.substring(1);
      final target = parseAmountString(numStr);
      if (target != null && amount >= target) return true;
    }

    // Toán tử so sánh nhỏ hơn (< 200k, <= 200k)
    if (clean.startsWith('<=') || clean.startsWith('<')) {
      final numStr =
          clean.startsWith('<=') ? clean.substring(2) : clean.substring(1);
      final target = parseAmountString(numStr);
      if (target != null && amount <= target) return true;
    }

    // So sánh số tiền chính xác
    final parsed = parseAmountString(clean);
    if (parsed != null && (amount - parsed).abs() < 1) {
      return true;
    }

    // So khớp chuỗi số con (VD: gõ "250" -> khớp với 250.000 đ)
    final amountIntStr = amount.toInt().toString();
    final digitsOnly = clean.replaceAll(RegExp(r'[^\d]'), '');
    if (digitsOnly.length >= 2 && amountIntStr.contains(digitsOnly)) {
      return true;
    }

    return false;
  }

  /// Chuyển đổi chuỗi số có đuôi k, tr, m, b, ty hoặc định dạng 50.000 sang double
  static double? parseAmountString(String str) {
    var s = str.trim().replaceAll(',', '.');
    double multiplier = 1;
    if (s.endsWith('k')) {
      multiplier = 1000;
      s = s.substring(0, s.length - 1);
    } else if (s.endsWith('tr') || s.endsWith('m') || s.endsWith('trieu')) {
      multiplier = 1000000;
      s = s.replaceAll('trieu', '').replaceAll('tr', '').replaceAll('m', '');
    } else if (s.endsWith('ty') || s.endsWith('b')) {
      multiplier = 1000000000;
      s = s.replaceAll('ty', '').replaceAll('b', '');
    }

    if (multiplier == 1) {
      // Phân cách hàng nghìn kiểu Việt Nam: 50.000 hoặc 1.000.000
      if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(s)) {
        s = s.replaceAll('.', '');
      } else if ('.'.allMatches(s).length > 1) {
        s = s.replaceAll('.', '');
      }
    }

    final val = double.tryParse(s);
    if (val != null) return val * multiplier;
    return null;
  }

  /// So khớp ngày tháng (hôm nay, hôm qua, tháng X, ngày/tháng...)
  static bool matchesDateQuery(DateTime date, String normQuery,
      {DateTime? referenceDate}) {
    final now = referenceDate ?? DateTime.now();
    if (normQuery == 'hom nay') {
      return date.year == now.year &&
          date.month == now.month &&
          date.day == now.day;
    }
    if (normQuery == 'hom qua') {
      final yest = now.subtract(const Duration(days: 1));
      return date.year == yest.year &&
          date.month == yest.month &&
          date.day == yest.day;
    }
    if (normQuery.startsWith('thang ')) {
      final mStr = normQuery.replaceAll('thang ', '').trim();
      final m = int.tryParse(mStr);
      if (m != null && date.month == m) return true;
    }

    final dayMonth =
        '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
    final fullDate = '$dayMonth/${date.year}';
    if (normQuery == dayMonth ||
        normQuery == fullDate ||
        normQuery == '${date.month}/${date.year}') {
      return true;
    }

    return false;
  }

  /// Tính tổng dòng tiền nhanh cho danh sách giao dịch
  static ({double totalIncome, double totalExpense, double netFlow})
      calculateOverview(
    List<AppTransaction> transactions,
  ) {
    double totalIncome = 0;
    double totalExpense = 0;
    for (final tx in transactions) {
      if (tx.type == 'income') {
        totalIncome += tx.amount;
      } else if (tx.type == 'expense') {
        totalExpense += tx.amount;
      }
    }
    return (
      totalIncome: totalIncome,
      totalExpense: totalExpense,
      netFlow: totalIncome - totalExpense,
    );
  }
}

import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../l10n/app_localizations.dart';
import '../../models/category_model.dart';
import '../../models/category_suggestion.dart';
import '../../models/quick_template.dart';
import '../../models/receipt_info.dart';
import '../../models/transaction_anomaly_result.dart';
import '../../models/transaction_model.dart';
import '../../models/wallet_model.dart';
import '../../models/wallet_suggestion.dart';
import '../../services/ai_service.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
import '../../services/template_service.dart';
import '../../services/transaction_intelligence_service.dart';
import '../../utils/category_localization_helper.dart';
import '../../utils/category_utils.dart';
import '../../utils/constants.dart';
import '../../utils/formatters.dart';
import '../../utils/validation_utils.dart';
import '../../utils/wallet_localization_helper.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/custom_numpad.dart';
import '../../widgets/quick_template_chip.dart';
import '../../widgets/stream_error_widget.dart';

/// Màn hình Thêm / Chỉnh sửa giao dịch phong cách Fintech hiện đại, trực quan
class AddTransactionScreen extends StatefulWidget {
  final AppTransaction? transactionToEdit;
  final String? initialType; // 'income' | 'expense' | 'transfer'
  final bool? initialIsTransfer;
  final bool? autoTriggerOcr;
  final Stream<List<Wallet>>? walletsStream;
  final Stream<List<Category>>? categoriesStream;
  final ReceiptInfo? initialOcrReceiptForTest;

  const AddTransactionScreen({
    super.key,
    this.transactionToEdit,
    this.initialType,
    this.initialIsTransfer,
    this.autoTriggerOcr,
    this.walletsStream,
    this.categoriesStream,
    this.initialOcrReceiptForTest,
  });

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  final _locationController = TextEditingController();
  final _picker = ImagePicker();

  final _firestoreService = FirestoreService();
  final _storageService = StorageService();
  final _templateService = TemplateService();
  final _intelligenceService = TransactionIntelligenceService();

  String _type = 'expense';
  String? _selectedWalletId;
  String? _selectedToWalletId;
  String? _selectedCategoryId;
  DateTime _selectedDate = DateTime.now();
  Uint8List? _receiptImageBytes;
  String? _existingImagePath;

  bool _isSaving = false;
  bool _walletBalanceExceeded = false;
  BudgetValidationStatus _budgetStatus = BudgetValidationStatus.ok;
  int _budgetProjectedPercent = 0;
  bool _isParsing = false;
  bool _isValidating = false;

  bool _isOcrExtracted = false;
  ReceiptInfo? _lastOcrInfo;
  bool _isWalletManuallySelected = false;
  WalletSuggestion? _walletSuggestion;
  bool _isCategoryManuallySelected = false;
  CategorySuggestion? _categorySuggestion;
  TransactionAnomalyResult _anomalyResult = TransactionAnomalyResult.normal();
  List<AppTransaction> _userHistory = [];
  List<Wallet> _allWallets = [];
  List<Category> _allCategories = [];
  Timer? _debounceTimer;
  String? _aiExplanation;
  bool _isLoadingAiExplanation = false;

  Stream<List<QuickTemplate>>? _templatesStream;
  Stream<List<Wallet>>? _walletsStream;
  Stream<List<Category>>? _categoriesStream;

  String get _safeUid {
    try {
      return FirebaseAuth.instance.currentUser?.uid ?? '';
    } catch (_) {
      return '';
    }
  }

  @override
  void initState() {
    super.initState();
    _noteController.addListener(_onNoteChanged);

    final uid = _safeUid;
    if (uid.isNotEmpty) {
      _templatesStream = _templateService.streamUserTemplates();
      _walletsStream =
          widget.walletsStream ?? _firestoreService.streamWallets(uid);
      _categoriesStream =
          widget.categoriesStream ?? _firestoreService.streamCategories(uid);
    } else {
      _templatesStream = const Stream.empty();
      _walletsStream = widget.walletsStream ?? const Stream.empty();
      _categoriesStream = widget.categoriesStream ?? const Stream.empty();
    }

    if (widget.initialIsTransfer == true || widget.initialType == 'transfer') {
      _type = 'transfer';
    } else if (widget.initialType != null && widget.initialType!.isNotEmpty) {
      _type = widget.initialType!;
    }

    if (widget.transactionToEdit != null) {
      final tx = widget.transactionToEdit!;
      if (tx.type == 'goal_deposit' || tx.type == 'goal_withdraw') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            AppSnackbar.show(
              context,
              context.tr('add_tx_goal_no_edit'),
              isError: true,
            );
            Navigator.of(context).pop();
          }
        });
        return;
      }
      _type = tx.type;
      _amountController.text = AppFormatters.number(tx.amount);
      _selectedWalletId = tx.walletId.isNotEmpty ? tx.walletId : null;
      if (tx.walletId.isNotEmpty) {
        _isWalletManuallySelected = true;
      }
      _selectedToWalletId = tx.toWalletId;
      _selectedCategoryId = tx.categoryId.isNotEmpty ? tx.categoryId : null;
      if (tx.categoryId.isNotEmpty) {
        _isCategoryManuallySelected = true;
      }
      _selectedDate = tx.date;
      _noteController.text = tx.note ?? '';
      _locationController.text = tx.location ?? '';
      _existingImagePath = tx.image;

      WidgetsBinding.instance.addPostFrameCallback((_) => _runValidation());
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final uid = _safeUid;
      if (uid.isNotEmpty) {
        try {
          final history = await _firestoreService.getUserTransactions(
            uid,
            from: DateTime.now().subtract(const Duration(days: 90)),
          );
          if (mounted) {
            setState(() {
              _userHistory = history;
            });
            _runIntelligenceCheck();
          }
        } catch (e) {
          debugPrint('[AddTransactionScreen] Lỗi tải lịch sử giao dịch: $e');
        }
      }

      if (widget.initialOcrReceiptForTest != null && mounted) {
        await _applyExtractedReceiptInfo(widget.initialOcrReceiptForTest!);
      } else if (widget.autoTriggerOcr == true) {
        _pickImage();
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _noteController.removeListener(_onNoteChanged);
    _amountController.dispose();
    _noteController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  void _onNoteChanged() {
    if (!_isOcrExtracted) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        _runIntelligenceCheck();
      }
    });
  }

  void _runIntelligenceCheck() {
    if (!mounted || _type == 'transfer') return;

    CategorySuggestion? nextCategorySuggestion;
    WalletSuggestion? nextWalletSuggestion;
    String? newCategoryId = _selectedCategoryId;
    String? newWalletId = _selectedWalletId;

    // CHỈ gợi ý AI và tự động chọn Ví / Danh mục khi trích xuất từ OCR hóa đơn (_isOcrExtracted == true).
    // Khi người dùng nhập thủ công (_isOcrExtracted == false), không hiển thị câu gợi ý AI.
    if (_isOcrExtracted) {
      final note = _noteController.text.trim();
      final ocrMerchantContext = [
        if (_lastOcrInfo?.merchant != null &&
            _lastOcrInfo!.merchant.trim().isNotEmpty)
          _lastOcrInfo!.merchant.trim(),
        if (note.isNotEmpty) note,
      ].join(' ').trim();

      final catSuggestion = _intelligenceService.suggestCategory(
        note: note,
        ocrMerchant: ocrMerchantContext.isNotEmpty ? ocrMerchantContext : null,
        categories: _allCategories,
        transactionType: _type,
        userHistory: _userHistory,
      );
      nextCategorySuggestion = catSuggestion;

      if (!_isCategoryManuallySelected &&
          catSuggestion.confidence >= 80 &&
          catSuggestion.categoryId.isNotEmpty) {
        newCategoryId = catSuggestion.categoryId;
      }

      final walletSuggestion = _intelligenceService.suggestWallet(
        paymentMethod: _lastOcrInfo?.paymentMethod,
        ocrRawText: _lastOcrInfo?.rawText,
        ocrMerchant: _lastOcrInfo?.merchant,
        wallets: _allWallets,
      );
      nextWalletSuggestion = walletSuggestion;

      if (!_isWalletManuallySelected) {
        if (walletSuggestion.isMatched &&
            walletSuggestion.walletId.isNotEmpty) {
          newWalletId = walletSuggestion.walletId;
        } else if (walletSuggestion.hasDetection &&
            !walletSuggestion.isMatched) {
          newWalletId = null;
        }
      }
    }

    final amount = AppFormatters.parseCurrencyInput(_amountController.text);
    final selectedCat = _allCategories.firstWhere(
      (c) => c.categoryId == (newCategoryId ?? ''),
      orElse: () => Category(
        categoryId: newCategoryId ?? '',
        userId: '',
        name: '',
        type: _type,
        icon: '',
        color: 0,
      ),
    );

    final anomaly = _intelligenceService.detectAnomaly(
      amount: amount,
      categoryId: newCategoryId ?? '',
      categoryName: selectedCat.name,
      transactionType: _type,
      userHistory: _userHistory,
      excludeTransactionId: widget.transactionToEdit?.transactionId,
    );

    setState(() {
      _categorySuggestion = nextCategorySuggestion;
      _walletSuggestion = nextWalletSuggestion;
      _selectedCategoryId = newCategoryId;
      _selectedWalletId = newWalletId;
      _anomalyResult = anomaly;
      _aiExplanation = null;
    });
  }

  Future<void> _explainAnomalyWithAi() async {
    if (!_anomalyResult.isAnomalous || _isLoadingAiExplanation) return;
    setState(() => _isLoadingAiExplanation = true);
    final ai = AiService();
    try {
      final explanation = await ai.explainTransactionAnomaly(
        categoryName: _anomalyResult.categoryName,
        currentAmount: _anomalyResult.currentAmount,
        expectedAmount: _anomalyResult.expectedAmount,
        ratio: _anomalyResult.ratio,
        historySampleSize: _anomalyResult.historySampleSize,
      );
      if (mounted) {
        setState(() {
          _aiExplanation = explanation;
        });
      }
    } catch (e) {
      if (mounted) {
        final msg = AiService.isNoNetworkException(e)
            ? context.tr('add_tx_ai_no_network')
            : context.tr('add_tx_ai_explain_error');
        setState(() {
          _aiExplanation = msg;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingAiExplanation = false);
      }
    }
  }

  Future<void> _pickImage() async {
    const ImageSource source = ImageSource.camera;
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      var status = await Permission.camera.request();
      if (!status.isGranted) {
        if (!mounted) return;
        AppSnackbar.show(context, context.tr('add_tx_camera_denied'),
            isError: true);
        return;
      }
    }
    final picked = await _picker.pickImage(source: source, imageQuality: 70);
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() => _receiptImageBytes = bytes);
      await _parseReceipt();
    }
  }

  Future<void> _pickGalleryImage() async {
    final picked =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() => _receiptImageBytes = bytes);
      await _parseReceipt();
    }
  }

  Future<void> _applyExtractedReceiptInfo(ReceiptInfo info) async {
    _isOcrExtracted = true;
    _lastOcrInfo = info;
    _isCategoryManuallySelected = false;
    _isWalletManuallySelected = false;
    _selectedWalletId = null;
    _selectedCategoryId = null;

    if (info.total > 0) {
      _amountController.text = AppFormatters.number(info.total);
    }
    if (info.date != null) {
      _selectedDate = info.date!;
    }
    final formattedNote = info.buildFormattedNote();
    if (formattedNote.isNotEmpty) {
      _noteController.text = formattedNote;
    }

    final resolvedLoc = info.resolvedLocation;
    if (resolvedLoc.isNotEmpty) {
      _locationController.text = resolvedLoc;
    }

    _runIntelligenceCheck();
    await _runValidation();
  }

  Future<void> _parseReceipt() async {
    if (_receiptImageBytes == null) return;
    _noteController.clear();
    _locationController.clear();
    setState(() {
      _isParsing = true;
      _isOcrExtracted = false;
      _lastOcrInfo = null;
      _categorySuggestion = null;
      _walletSuggestion = null;
      _isCategoryManuallySelected = false;
      _isWalletManuallySelected = false;
    });
    final ai = AiService();
    try {
      final info = await ai.extractReceiptInfo(_receiptImageBytes!);
      if (!mounted) return;
      if (info != null) {
        await _applyExtractedReceiptInfo(info);
        if (!mounted) return;
        AppSnackbar.show(context, context.tr('add_tx_ocr_success'));
      } else {
        AppSnackbar.show(context, context.tr('add_tx_ocr_fail'),
            isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      final msg = AiService.isNoNetworkException(e)
          ? context.tr('add_tx_ocr_no_network')
          : context.tr('add_tx_ocr_err', params: {'error': '$e'});
      AppSnackbar.show(context, msg, isError: true);
    } finally {
      if (mounted) {
        setState(() => _isParsing = false);
      }
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  void _setDatePreset(DateTime date) {
    HapticFeedback.selectionClick();
    setState(() => _selectedDate = date);
  }

  Future<void> _showNumpad() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CustomNumpad(
        initialValue: _amountController.text,
        title: _type == 'expense'
            ? context.tr('add_tx_numpad_expense')
            : (_type == 'income'
                ? context.tr('add_tx_numpad_income')
                : context.tr('add_tx_numpad_transfer')),
      ),
    );
    if (result != null) {
      setState(() => _amountController.text = result);
      _runIntelligenceCheck();
      await _runValidation();
    }
  }

  void _clearAmount() async {
    HapticFeedback.lightImpact();
    setState(() {
      _amountController.clear();
    });
    _runIntelligenceCheck();
    await _runValidation();
  }

  Future<void> _runValidation() async {
    setState(() => _isValidating = true);
    try {
      final amount = AppFormatters.parseCurrencyInput(_amountController.text);
      final uid = _safeUid;

      if (_type == 'income') {
        setState(() {
          _walletBalanceExceeded = false;
          _budgetStatus = BudgetValidationStatus.ok;
          _budgetProjectedPercent = 0;
        });
        return;
      }

      if (_type == 'transfer') {
        setState(() {
          _budgetStatus = BudgetValidationStatus.ok;
          _budgetProjectedPercent = 0;
        });
        if (_selectedWalletId != null) {
          final exceed = await ValidationUtils.exceedsWalletBalance(
            walletId: _selectedWalletId!,
            amount: amount,
            firestoreService: _firestoreService,
          );
          setState(() => _walletBalanceExceeded = exceed);
        }
        return;
      }

      if (_selectedWalletId != null) {
        final exceed = await ValidationUtils.exceedsWalletBalance(
          walletId: _selectedWalletId!,
          amount: amount,
          firestoreService: _firestoreService,
        );
        setState(() => _walletBalanceExceeded = exceed);
      }
      if (_selectedCategoryId != null) {
        final result = await ValidationUtils.checkCategoryBudgetStatus(
          userId: uid,
          categoryId: _selectedCategoryId!,
          amount: amount,
          firestoreService: _firestoreService,
        );
        setState(() {
          _budgetStatus = result.status;
          _budgetProjectedPercent = result.percent;
        });
      }
    } catch (e) {
      debugPrint('⚠️ Lỗi khi kiểm tra vượt số dư ví/ngân sách: $e');
      setState(() {
        _walletBalanceExceeded = false;
        _budgetStatus = BudgetValidationStatus.ok;
        _budgetProjectedPercent = 0;
      });
    } finally {
      if (mounted) {
        setState(() => _isValidating = false);
      }
    }
  }

  Future<void> _saveAsTemplate() async {
    final titleCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(context.tr('add_tx_save_tmpl_title'),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        content: TextField(
          controller: titleCtrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: context.tr('add_tx_tmpl_name_label'),
            hintText: context.tr('add_tx_tmpl_name_hint'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('common_cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('common_save')),
          ),
        ],
      ),
    );
    if (confirmed == true && titleCtrl.text.isNotEmpty) {
      final amount = AppFormatters.parseCurrencyInput(_amountController.text);
      await _templateService.createTemplate(
        title: titleCtrl.text,
        amount: amount,
        type: _type,
        walletId: _selectedWalletId ?? '',
        categoryId: _selectedCategoryId ?? '',
        note: _noteController.text,
        location: _locationController.text,
        date: _selectedDate,
        imagePath: null,
      );
      if (mounted) {
        AppSnackbar.show(context, context.tr('add_tx_save_tmpl_success'));
      }
    }
  }

  Future<void> _handleSave() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final amount = AppFormatters.parseCurrencyInput(_amountController.text);

    if (uid == null || amount <= 0 || _selectedWalletId == null) {
      AppSnackbar.show(
          context, context.tr('add_tx_err_missing_amount_wallet'),
          isError: true);
      return;
    }

    if (_type == 'transfer') {
      if (_selectedToWalletId == null) {
        AppSnackbar.show(context, context.tr('add_tx_err_missing_to_wallet'),
            isError: true);
        return;
      }
      if (_selectedToWalletId == _selectedWalletId) {
        AppSnackbar.show(context, context.tr('add_tx_err_same_wallet'),
            isError: true);
        return;
      }
    } else if (_selectedCategoryId == null) {
      AppSnackbar.show(context, context.tr('add_tx_err_missing_category'),
          isError: true);
      return;
    }

    if (_walletBalanceExceeded) {
      AppSnackbar.show(
          context, context.tr('add_tx_err_insufficient_balance'),
          isError: true);
      return;
    }
    if (_type != 'transfer' &&
        _budgetStatus == BudgetValidationStatus.exceeded) {
      AppSnackbar.show(context, context.tr('add_tx_err_budget_exceeded'),
          isError: true);
      return;
    }

    setState(() => _isSaving = true);
    try {
      String? imageUrl;
      if (_type != 'transfer' && _receiptImageBytes != null) {
        try {
          imageUrl = await _storageService.uploadReceiptImage(
              uid, _receiptImageBytes!);
        } catch (e) {
          debugPrint(
              '⚠️ Upload ảnh hóa đơn thất bại, tiếp tục lưu giao dịch: $e');
        }
      }

      final categoryIdToSave =
          _type == 'transfer' ? '' : (_selectedCategoryId ?? '');
      final toWalletIdToSave = _type == 'transfer' ? _selectedToWalletId : null;

      if (widget.transactionToEdit != null) {
        final newTx = AppTransaction(
          transactionId: widget.transactionToEdit!.transactionId,
          userId: uid,
          walletId: _selectedWalletId!,
          categoryId: categoryIdToSave,
          amount: amount,
          type: _type,
          toWalletId: toWalletIdToSave,
          note: _noteController.text.trim(),
          image: imageUrl ?? _existingImagePath,
          location: _locationController.text.trim(),
          date: _selectedDate,
        );
        await _firestoreService.updateTransactionSafely(
            widget.transactionToEdit!, newTx);
        if (!mounted) return;
        Navigator.of(context).pop(true);
      } else {
        final tx = AppTransaction(
          transactionId: '',
          userId: uid,
          walletId: _selectedWalletId!,
          categoryId: categoryIdToSave,
          amount: amount,
          type: _type,
          toWalletId: toWalletIdToSave,
          note: _noteController.text.trim(),
          image: imageUrl,
          location: _locationController.text.trim(),
          date: _selectedDate,
        );
        await _firestoreService.createTransaction(tx);
        if (!mounted) return;
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('❌ Lỗi khi lưu giao dịch: $e');
      if (mounted) {
        final errorMsg = e.toString().replaceFirst('Exception: ', '');
        AppSnackbar.show(context, errorMsg, isError: true);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
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
        return Icons.category_outlined;
    }
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  Widget build(BuildContext context) {
    final uid = _safeUid;
    final accentColor = _type == 'transfer'
        ? AppColors.info
        : (_type == 'income' ? AppColors.income : AppColors.expense);

    final amountNum = AppFormatters.parseCurrencyInput(_amountController.text);
    final hasAmount = amountNum > 0;
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));

    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        title: Text(
          widget.transactionToEdit != null
              ? context.tr('add_tx_edit_title')
              : context.tr('home_add_transaction'),
          style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        actions: [
          if (widget.transactionToEdit == null && _type != 'transfer')
            IconButton(
              icon: const Icon(Icons.bookmark_add_outlined),
              tooltip: context.tr('add_tx_save_tmpl_tooltip'),
              onPressed: _saveAsTemplate,
            ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: context.appCard,
          border: Border(top: BorderSide(color: context.appBorder)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: SafeArea(
          child: AppButton(
            text: widget.transactionToEdit != null
                ? context.tr('add_tx_update_btn')
                : context.tr('add_tx_save_btn'),
            isLoading: _isSaving,
            backgroundColor: accentColor,
            onPressed: (_isSaving ||
                    _isParsing ||
                    _isValidating ||
                    !hasAmount ||
                    _selectedWalletId == null ||
                    (_type == 'transfer' &&
                        (_selectedToWalletId == null ||
                            _selectedToWalletId == _selectedWalletId)) ||
                    (_type != 'transfer' && _selectedCategoryId == null) ||
                    (_type != 'transfer' &&
                        _budgetStatus == BudgetValidationStatus.exceeded) ||
                    _walletBalanceExceeded)
                ? null
                : _handleSave,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Phân loại giao dịch (Segmented Type Selector)
            _buildTypeSelector(),
            const SizedBox(height: 14),

            // Quick Template Chips (Chỉ hiển thị cho Expense / Income)
            if (widget.transactionToEdit == null && _type != 'transfer') ...[
              _buildTemplateBar(),
              const SizedBox(height: 12),
            ],

            // 2. HERO MONEY INPUT CARD (Tâm điểm thị giác cao cấp)
            _buildHeroMoneyCard(accentColor, amountNum, hasAmount),
            const SizedBox(height: 16),

            // Cảnh báo số dư ví nguồn vượt mức
            if (_walletBalanceExceeded) ...[
              _buildWalletBalanceWarning(),
              const SizedBox(height: 14),
            ],

            // 3. VÍ NGUỒN & VÍ ĐÍCH
            _buildWalletSection(uid),
            const SizedBox(height: 14),

            // 4. DANH MỤC & GỢI Ý AI (Chỉ cho Thu nhập / Chi tiêu)
            if (_type != 'transfer') ...[
              _buildCategorySection(uid),
              const SizedBox(height: 14),
            ],

            // 5. CẢNH BÁO NGÂN SÁCH & BẤT THƯỜNG
            _buildAnomalyAndBudgetWarnings(),

            // 6. NGÀY & THỜI GIAN GIAO DỊCH
            _buildDateSection(now, yesterday),
            const SizedBox(height: 14),

            // 7. GHI CHÚ & ĐỊA ĐIỂM
            _buildNotesAndLocationSection(),
            const SizedBox(height: 14),

            // 8. ẢNH HÓA ĐƠN & OCR
            if (_type != 'transfer') ...[
              _buildReceiptOcrSection(),
              const SizedBox(height: 20),
            ],
          ],
        ),
      ),
    );
  }

  /// Segmented 3-Way Selector
  Widget _buildTypeSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.appInputFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.appBorder, width: 1),
      ),
      child: Row(
        children: [
          Expanded(
              child: _typeToggleButton(context.tr('common_expense'), 'expense',
                  AppColors.expense, Icons.arrow_downward_rounded)),
          const SizedBox(width: 4),
          Expanded(
              child: _typeToggleButton(context.tr('common_income'), 'income',
                  AppColors.income, Icons.arrow_upward_rounded)),
          const SizedBox(width: 4),
          Expanded(
              child: _typeToggleButton(context.tr('add_tx_type_transfer'),
                  'transfer', AppColors.info, Icons.sync_alt_rounded)),
        ],
      ),
    );
  }

  Widget _typeToggleButton(
      String label, String type, Color activeColor, IconData icon) {
    final selected = _type == type;
    return GestureDetector(
      onTap: () async {
        if (widget.transactionToEdit != null && _type == type) return;
        HapticFeedback.selectionClick();
        setState(() {
          if (widget.transactionToEdit == null) {
            _type = type;
            _selectedCategoryId = null;
            _isCategoryManuallySelected = false;
            _categorySuggestion = null;
            _isWalletManuallySelected = false;
            _walletSuggestion = null;
            _isOcrExtracted = false;
            _lastOcrInfo = null;
            _anomalyResult = TransactionAnomalyResult.normal();
            _aiExplanation = null;
            _selectedWalletId = null;
            _selectedToWalletId = null;
            _amountController.clear();
            _noteController.clear();
            _locationController.clear();
            _receiptImageBytes = null;
            _existingImagePath = null;
            _walletBalanceExceeded = false;
            _budgetStatus = BudgetValidationStatus.ok;
            _budgetProjectedPercent = 0;
            _isSaving = false;
            _isParsing = false;
            _isValidating = false;
          } else {
            _type = type;
            _selectedCategoryId = null;
            _selectedToWalletId = null;
            _isCategoryManuallySelected = false;
            _categorySuggestion = null;
            _walletSuggestion = null;
            _isOcrExtracted = false;
            _lastOcrInfo = null;
            _anomalyResult = TransactionAnomalyResult.normal();
            _aiExplanation = null;
          }
        });
        _runIntelligenceCheck();
        await _runValidation();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: activeColor.withAlpha(50),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 15,
              color: selected ? Colors.white : context.appTextSecondary,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: selected ? Colors.white : context.appTextSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Template Bar (Có phân trang theo nhóm `[←] ... [→]` và nhấn giữ để xóa)
  Widget _buildTemplateBar() {
    return StreamBuilder<List<QuickTemplate>>(
      stream: _templatesStream ?? _templateService.streamUserTemplates(),
      builder: (streamCtx, snapshot) {
        if (snapshot.hasError) {
          return StreamErrorWidget(error: snapshot.error.toString());
        }
        final templates = snapshot.data ?? [];
        if (templates.isEmpty) return const SizedBox.shrink();

        return QuickTemplatePaginatedBar(
          templates: templates,
          onSelect: (tmpl) async {
            HapticFeedback.selectionClick();
            setState(() {
              _type = tmpl.type;
              _isOcrExtracted = false;
              _lastOcrInfo = null;
              _categorySuggestion = null;
              _walletSuggestion = null;
              _amountController.text = AppFormatters.number(tmpl.amount);
              _selectedWalletId =
                  tmpl.walletId.isNotEmpty ? tmpl.walletId : null;
              _isWalletManuallySelected = tmpl.walletId.isNotEmpty;
              _selectedCategoryId =
                  tmpl.categoryId.isNotEmpty ? tmpl.categoryId : null;
              _isCategoryManuallySelected = tmpl.categoryId.isNotEmpty;
              _noteController.text = tmpl.note;
              _locationController.text = tmpl.location;
            });
            _runIntelligenceCheck();
            await _runValidation();
          },
          onDelete: (tmpl) async {
            try {
              await _templateService.deleteTemplate(tmpl.id);
              if (mounted) {
                AppSnackbar.show(
                  context,
                  context.tr(
                    'add_tx_tmpl_deleted',
                    params: {'title': tmpl.title},
                  ),
                );
              }
            } catch (e) {
              if (mounted) {
                AppSnackbar.show(
                  context,
                  context.tr(
                    'add_tx_tmpl_delete_err',
                    params: {'error': '$e'},
                  ),
                  isError: true,
                );
              }
              rethrow;
            }
          },
        );
      },
    );
  }

  /// HERO MONEY CARD
  Widget _buildHeroMoneyCard(
      Color accentColor, double amountNum, bool hasAmount) {
    final prefix = _type == 'expense' ? '- ' : (_type == 'income' ? '+ ' : '');
    final displayAmount =
        _amountController.text.isEmpty ? '0' : _amountController.text;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: context.appCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasAmount ? accentColor.withAlpha(60) : context.appBorder,
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(6),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    context.tr('add_tx_sec_amount'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: context.appTextSecondary,
                    ),
                  ),
                ),
                if (hasAmount) ...[
                  const SizedBox(width: 8),
                  Material(
                    color: AppColors.expenseBackground,
                    borderRadius: BorderRadius.circular(6),
                    child: InkWell(
                      onTap: _clearAmount,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.clear_rounded,
                                size: 13, color: AppColors.expense),
                            const SizedBox(width: 3),
                            Text(
                              context.tr('common_delete'),
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.expense),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Tap to enter amount
          InkWell(
            onTap: _showNumpad,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            prefix,
                            style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w700,
                              color: accentColor,
                            ),
                          ),
                          Text(
                            displayAmount,
                            style: GoogleFonts.outfit(
                              fontSize: 40,
                              fontWeight: FontWeight.w700,
                              color: accentColor,
                              letterSpacing: -0.5,
                            ),
                          ),
                          Text(
                            ' ₫',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              color: context.appTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Hiển thị đọc số thông minh (tránh nhầm số 0 khi số tiền lớn)
          if (amountNum >= 1e6) ...[
            const SizedBox(height: 4),
            Text(
              '≈ ${AppFormatters.compactCurrency(amountNum)}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: accentColor,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Cảnh báo số dư ví
  Widget _buildWalletBalanceWarning() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.expenseBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.expense.withAlpha(90)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: AppColors.expense, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.tr('add_tx_wallet_exceeded_banner'),
              style: const TextStyle(
                  color: AppColors.expense,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  /// VÍ NGUỒN & VÍ ĐÍCH
  Widget _buildWalletSection(String uid) {
    return StreamBuilder<List<Wallet>>(
      stream: _walletsStream ?? _firestoreService.streamWallets(uid),
      builder: (context, snap) {
        if (snap.hasError)
          return StreamErrorWidget(error: snap.error.toString());
        final allWallets = snap.data ?? [];
        if (!areWalletListsEqual(_allWallets, allWallets)) {
          _allWallets = allWallets;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _runIntelligenceCheck();
              _runValidation();
            }
          });
        }

        final wallets = allWallets
            .where((w) =>
                w.isActive ||
                (widget.transactionToEdit != null &&
                    (w.walletId == widget.transactionToEdit!.walletId ||
                        w.walletId == widget.transactionToEdit!.toWalletId)))
            .toList();

        if (snap.hasData &&
            _selectedWalletId != null &&
            !wallets.any((w) => w.walletId == _selectedWalletId)) {
          _selectedWalletId = null;
        }

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.appCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.appBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.account_balance_wallet_rounded,
                      size: 18, color: AppColors.primaryLight),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _type == 'transfer'
                          ? context.tr('add_tx_sec_wallets_transfer')
                          : context.tr('add_tx_sec_wallet_single'),
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
                ],
              ),
              const SizedBox(height: 10),

              // Dropdown ví nguồn
              DropdownButtonFormField<String>(
                value: wallets.any((w) => w.walletId == _selectedWalletId)
                    ? _selectedWalletId
                    : null,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: _type == 'transfer'
                      ? context.tr('add_tx_from_wallet_label')
                      : context.tr('tx_detail_payment_wallet'),
                  prefixIcon: const Icon(Icons.wallet_rounded,
                      color: AppColors.primaryLight, size: 20),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                items: wallets.map((w) {
                  return DropdownMenuItem(
                    value: w.walletId,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            WalletLocalizationHelper.localizeWalletWithContext(
                              context,
                              w,
                            ),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          AppFormatters.compactCurrency(w.balance),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: w.balance < 0
                                ? AppColors.expense
                                : context.appTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (v) async {
                  setState(() {
                    _selectedWalletId = v;
                    _isWalletManuallySelected = true;
                  });
                  await _runValidation();
                },
              ),

              // Chip gợi ý AI cho Ví thanh toán (chỉ hiển thị khi trích xuất OCR)
              if (_type != 'transfer' &&
                  _isOcrExtracted &&
                  _walletSuggestion != null &&
                  _walletSuggestion!.hasDetection) ...[
                const SizedBox(height: 10),
                if (_walletSuggestion!.isMatched &&
                    _walletSuggestion!.walletId.isNotEmpty)
                  InkWell(
                    onTap: () async {
                      HapticFeedback.lightImpact();
                      setState(() {
                        _selectedWalletId = _walletSuggestion!.walletId;
                        _isWalletManuallySelected = true;
                      });
                      await _runValidation();
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight.withAlpha(22),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppColors.primaryLight.withAlpha(80)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.auto_awesome_rounded,
                              color: AppColors.primaryLight, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              context.tr(
                                'add_tx_ai_suggest',
                                params: {
                                  'name': () {
                                    final matchedW = wallets
                                        .where((w) =>
                                            w.walletId ==
                                            _walletSuggestion!.walletId)
                                        .firstOrNull;
                                    return matchedW != null
                                        ? WalletLocalizationHelper
                                            .localizeWalletWithContext(
                                                context, matchedW)
                                        : WalletLocalizationHelper
                                            .localizeNameWithContext(
                                            context,
                                            _walletSuggestion!.walletName,
                                          );
                                  }(),
                                  'confidence':
                                      '${_walletSuggestion!.confidence}',
                                },
                              ),
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.primaryLight,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const Icon(Icons.touch_app_rounded,
                              color: AppColors.primaryLight, size: 16),
                        ],
                      ),
                    ),
                  )
                else
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: AppColors.warningBackground,
                      borderRadius: BorderRadius.circular(10),
                      border:
                          Border.all(color: AppColors.warning.withAlpha(90)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: AppColors.warning, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            context.tr(
                              'add_tx_no_ocr_wallet',
                              params: {
                                'label':
                                    _walletSuggestion!.detectedPaymentLabel,
                              },
                            ),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.warning,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],

              if (_type == 'transfer') ...[
                const SizedBox(height: 10),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: context.appInputFill,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_downward_rounded,
                        size: 16, color: AppColors.info),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _selectedToWalletId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: context.tr('add_tx_to_wallet_label'),
                    prefixIcon: const Icon(Icons.input_rounded,
                        color: AppColors.info, size: 20),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  items: wallets
                      .where((w) => w.walletId != _selectedWalletId)
                      .map((w) => DropdownMenuItem(
                            value: w.walletId,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                  child: Text(
                                    WalletLocalizationHelper
                                        .localizeWalletWithContext(context, w),
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w500),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  AppFormatters.compactCurrency(w.balance),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: context.appTextSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ))
                      .toList(),
                  onChanged: (v) async {
                    setState(() => _selectedToWalletId = v);
                    await _runValidation();
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// DANH MỤC & GỢI Ý AI
  Widget _buildCategorySection(String uid) {
    return StreamBuilder<List<Category>>(
      stream: _categoriesStream ?? _firestoreService.streamCategories(uid),
      builder: (context, snap) {
        if (snap.hasError)
          return StreamErrorWidget(error: snap.error.toString());
        final allCategories = snap.data ?? [];
        if (!areCategoryListsEqual(_allCategories, allCategories)) {
          _allCategories = allCategories;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _runIntelligenceCheck();
              _runValidation();
            }
          });
        }
        final categories = allCategories.where((c) => c.type == _type).toList();

        if (snap.hasData &&
            _selectedCategoryId != null &&
            !allCategories.any((c) => c.categoryId == _selectedCategoryId)) {
          _selectedCategoryId = null;
        }

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.appCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.appBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.category_rounded,
                      size: 18, color: AppColors.primaryLight),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.tr('add_tx_sec_category'),
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
                ],
              ),
              const SizedBox(height: 10),

              // Dropdown danh mục
              DropdownButtonFormField<String>(
                value:
                    categories.any((c) => c.categoryId == _selectedCategoryId)
                        ? _selectedCategoryId
                        : null,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: context.tr('add_tx_choose_category'),
                  prefixIcon: const Icon(Icons.grid_view_rounded,
                      color: AppColors.primaryLight, size: 20),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                items: categories.map((c) {
                  return DropdownMenuItem(
                    value: c.categoryId,
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Color(c.color).withAlpha(40),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(_getCategoryIcon(c.icon),
                              size: 16, color: Color(c.color)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            CategoryLocalizationHelper.localizeNameWithContext(
                                context, c.name),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (v) async {
                  setState(() {
                    _selectedCategoryId = v;
                    _isCategoryManuallySelected = true;
                  });
                  _runIntelligenceCheck();
                  await _runValidation();
                },
              ),

              // Chip gợi ý AI (chỉ hiển thị khi trích xuất OCR)
              if (_isOcrExtracted &&
                  _categorySuggestion != null &&
                  _categorySuggestion!.confidence > 0 &&
                  _categorySuggestion!.categoryId.isNotEmpty) ...[
                const SizedBox(height: 10),
                InkWell(
                  onTap: () async {
                    HapticFeedback.lightImpact();
                    setState(() {
                      _selectedCategoryId = _categorySuggestion!.categoryId;
                      _isCategoryManuallySelected = true;
                    });
                    _runIntelligenceCheck();
                    await _runValidation();
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight.withAlpha(22),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppColors.primaryLight.withAlpha(80)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.auto_awesome_rounded,
                            color: AppColors.primaryLight, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            context.tr(
                              'add_tx_ai_suggest',
                              params: {
                                'name': CategoryLocalizationHelper
                                    .localizeNameWithContext(
                                  context,
                                  _categorySuggestion!.categoryName,
                                ),
                                'confidence':
                                    '${_categorySuggestion!.confidence}',
                              },
                            ),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.primaryLight,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Icon(Icons.touch_app_rounded,
                            color: AppColors.primaryLight, size: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Cảnh báo ngân sách và bất thường
  Widget _buildAnomalyAndBudgetWarnings() {
    if (_type == 'transfer') return const SizedBox.shrink();

    final List<Widget> items = [];

    if (_budgetStatus == BudgetValidationStatus.nearLimit) {
      items.add(
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.warningBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.warning.withAlpha(90)),
          ),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: AppColors.warning, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.tr(
                    'add_tx_budget_near_limit',
                    params: {'percent': '$_budgetProjectedPercent'},
                  ),
                  style: const TextStyle(
                      color: AppColors.warning,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      );
    } else if (_budgetStatus == BudgetValidationStatus.exceeded) {
      items.add(
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.expenseBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.expense.withAlpha(90)),
          ),
          child: Row(
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: AppColors.expense, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.tr('add_tx_budget_over_limit'),
                  style: const TextStyle(
                      color: AppColors.expense,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_anomalyResult.isAnomalous) {
      final isCritical = _anomalyResult.severity == 'critical';
      items.add(
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isCritical
                ? AppColors.expenseBackground
                : AppColors.warningBackground,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isCritical
                  ? AppColors.expense.withAlpha(90)
                  : AppColors.warning.withAlpha(90),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isCritical
                        ? Icons.error_outline_rounded
                        : Icons.warning_amber_rounded,
                    color: isCritical ? AppColors.expense : AppColors.warning,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.tr('add_tx_anomaly_title'),
                      style: TextStyle(
                        color:
                            isCritical ? AppColors.expense : AppColors.warning,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _anomalyResult.reason,
                style: TextStyle(
                    color: context.appTextPrimary, fontSize: 13, height: 1.3),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryLight,
                    side: const BorderSide(color: AppColors.primaryLight),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed:
                      _isLoadingAiExplanation ? null : _explainAnomalyWithAi,
                  icon: _isLoadingAiExplanation
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome_rounded, size: 14),
                  label: Text(
                    _isLoadingAiExplanation
                        ? context.tr('add_tx_ai_analyzing')
                        : context.tr('add_tx_explain_with_ai'),
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              if (_aiExplanation != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.appCard,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: context.appBorder),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.psychology_rounded,
                          color: AppColors.primaryLight, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _aiExplanation!,
                          style: TextStyle(
                              fontSize: 12,
                              color: context.appTextPrimary,
                              height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (items.isEmpty) return const SizedBox.shrink();
    return Column(children: items);
  }

  /// NGÀY GIAO DỊCH
  Widget _buildDateSection(DateTime now, DateTime yesterday) {
    final isToday = _isSameDay(_selectedDate, now);
    final isYesterday = _isSameDay(_selectedDate, yesterday);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_rounded,
                        size: 18, color: AppColors.primaryLight),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context.tr('add_tx_sec_date'),
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
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        context.tr('add_tx_pick_calendar'),
                        maxLines: 1,
                        style: const TextStyle(
                            color: AppColors.primaryLight,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final todayChip = _buildDatePresetChip(
                context.tr('add_tx_today'),
                isToday,
                () => _setDatePreset(now),
              );
              final yesterdayChip = _buildDatePresetChip(
                context.tr('add_tx_yesterday'),
                isYesterday,
                () => _setDatePreset(yesterday),
              );
              final dateButton = InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: context.appInputFill,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: context.appBorder),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            AppFormatters.date(_selectedDate),
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: context.appTextPrimary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.edit_calendar_outlined,
                          size: 16, color: context.appTextSecondary),
                    ],
                  ),
                ),
              );

              final isCompact = constraints.maxWidth < 310;
              if (isCompact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(child: todayChip),
                        const SizedBox(width: 8),
                        Expanded(child: yesterdayChip),
                      ],
                    ),
                    const SizedBox(height: 8),
                    dateButton,
                  ],
                );
              }

              return Row(
                children: [
                  Flexible(child: todayChip),
                  const SizedBox(width: 8),
                  Flexible(child: yesterdayChip),
                  const SizedBox(width: 10),
                  Expanded(flex: 2, child: dateButton),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDatePresetChip(
      String label, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : context.appInputFill,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: isSelected ? AppColors.primary : context.appBorder),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isSelected ? Colors.white : context.appTextSecondary,
            ),
          ),
        ),
      ),
    );
  }

  /// GHI CHÚ & ĐỊA ĐIỂM
  Widget _buildNotesAndLocationSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.edit_note_rounded,
                  size: 18, color: AppColors.primaryLight),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.tr('add_tx_sec_extra'),
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
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _noteController,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: context.tr('tx_detail_note'),
              hintText: context.tr('add_tx_note_hint'),
              prefixIcon: const Icon(Icons.notes_rounded,
                  size: 20, color: AppColors.primaryLight),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _locationController,
            decoration: InputDecoration(
              labelText: context.tr('add_tx_location_label'),
              hintText: context.tr('add_tx_location_hint'),
              prefixIcon: const Icon(Icons.location_on_outlined,
                  size: 20, color: AppColors.primaryLight),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          if (_isOcrExtracted &&
              _lastOcrInfo != null &&
              _lastOcrInfo!.hasInferredData) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.auto_fix_high_rounded,
                      size: 16,
                      color: AppColors.warning,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('add_tx_ocr_inferred_banner'),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.warning,
                          ),
                        ),
                        if (_lastOcrInfo!.inferredFields.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          ..._lastOcrInfo!.inferredFields.map(
                            (fieldNote) => Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                '• $fieldNote',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: context.appTextSecondary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
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

  /// ẢNH HÓA ĐƠN & OCR
  Widget _buildReceiptOcrSection() {
    final hasImage = _receiptImageBytes != null || _existingImagePath != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.document_scanner_rounded,
                        size: 18, color: AppColors.primaryLight),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context.tr('add_tx_sec_ocr'),
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
                  ],
                ),
              ),
              if (_isParsing) ...[
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 135),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight.withAlpha(25),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                              width: 10,
                              height: 10,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(width: 6),
                          Text(context.tr('add_tx_ai_reading'),
                              maxLines: 1,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.primaryLight,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          if (!hasImage) ...[
            // Trạng thái chưa có ảnh: Card nút tinh gọn, thanh lịch
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: context.appInputFill,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: context.appBorder, style: BorderStyle.solid),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('add_tx_attach_receipt'),
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: context.appTextPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          context.tr('add_tx_attach_receipt_sub'),
                          style: TextStyle(
                              fontSize: 11, color: context.appTextSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: context.tr('add_tx_take_photo'),
                    icon: const Icon(Icons.camera_alt_rounded,
                        color: AppColors.primaryLight),
                    onPressed: _pickImage,
                  ),
                  IconButton(
                    tooltip: context.tr('add_tx_pick_gallery'),
                    icon: const Icon(Icons.photo_library_rounded,
                        color: AppColors.primaryLight),
                    onPressed: _pickGalleryImage,
                  ),
                ],
              ),
            ),
          ] else ...[
            // Trạng thái đã có ảnh: Preview sắc nét kèm các nút thao tác
            Container(
              height: 140,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.appBorder),
              ),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _receiptImageBytes != null
                        ? Image.memory(
                            _receiptImageBytes!,
                            width: double.infinity,
                            height: 140,
                            fit: BoxFit.cover,
                          )
                        : Image.file(
                            File(_existingImagePath!),
                            width: double.infinity,
                            height: 140,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: context.appInputFill,
                              child: const Center(
                                child: Icon(Icons.broken_image_outlined,
                                    color: Colors.grey),
                              ),
                            ),
                          ),
                  ),
                  if (_isParsing)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(160),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 3),
                            const SizedBox(height: 8),
                            Text(
                              context.tr('add_tx_ai_extracting'),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Nút thao tác góc phải
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.black.withAlpha(150),
                          radius: 15,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            tooltip: context.tr('add_tx_retake_photo'),
                            icon: const Icon(Icons.camera_alt_rounded,
                                color: Colors.white, size: 16),
                            onPressed: _pickImage,
                          ),
                        ),
                        const SizedBox(width: 6),
                        CircleAvatar(
                          backgroundColor: Colors.black.withAlpha(150),
                          radius: 15,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            tooltip: context.tr('add_tx_remove_photo'),
                            icon: const Icon(Icons.close_rounded,
                                color: Colors.white, size: 16),
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              setState(() {
                                _receiptImageBytes = null;
                                _existingImagePath = null;
                                _isOcrExtracted = false;
                                _lastOcrInfo = null;
                                _categorySuggestion = null;
                                _walletSuggestion = null;
                              });
                            },
                          ),
                        ),
                      ],
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

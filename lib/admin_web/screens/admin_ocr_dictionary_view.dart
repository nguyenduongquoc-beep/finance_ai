import 'package:flutter/material.dart';
import '../../models/ai_runtime_config_model.dart';
import '../../models/category_model.dart';
import '../../models/category_suggestion.dart';
import '../../models/wallet_model.dart';
import '../../models/wallet_suggestion.dart';
import '../../services/ai_config_sync_service.dart';
import '../../services/transaction_intelligence_service.dart';
import '../../utils/constants.dart';
import '../services/admin_web_service.dart';
import '../widgets/admin_governance_widgets.dart';

/// Khu vực 4: OCR Dictionary (`transaction_rules`)
/// - Hiển thị chỉ đọc (Locked) Built-in Keywords & Protected Payment Providers.
/// - Thêm / bật-tắt (`disabledAdminKeywords`) / xóa từ khóa Admin bổ sung với
///   `validateCandidateKeyword` theo thời gian thực.
/// - Quản lý Custom Payment Provider Rules (kèm bật/tắt `isActive`).
/// - Kiểm thử khớp cục bộ bằng `TransactionIntelligenceService` (không gọi API Key).
class AdminOcrDictionaryView extends StatefulWidget {
  final AdminWebService adminWebService;
  final String currentAdminUid;
  final String currentAdminEmail;
  final Map<String, dynamic>? tokenClaimsOverride;
  final String? initialCandidateKeyword;

  const AdminOcrDictionaryView({
    super.key,
    required this.adminWebService,
    required this.currentAdminUid,
    required this.currentAdminEmail,
    this.tokenClaimsOverride,
    this.initialCandidateKeyword,
  });

  @override
  State<AdminOcrDictionaryView> createState() => _AdminOcrDictionaryViewState();
}

class _AdminOcrDictionaryViewState extends State<AdminOcrDictionaryView> {
  final _keywordInputCtrl = TextEditingController();
  final _testReceiptCtrl = TextEditingController(
    text: 'Highlands Coffee 45,000d thanh toan qua VNPay',
  );

  bool _formInitialized = false;
  bool _isBusy = false;

  // Draft mutable state
  Map<String, List<String>> _addedExpenseKeywords = {};
  Map<String, List<String>> _addedIncomeKeywords = {};
  List<String> _disabledAdminKeywords = [];
  List<CustomPaymentProviderRule> _customProviders = [];

  // Keyword input form controls
  bool _isIncomeTarget = false;
  String _selectedGroupKey = 'an uong';
  KeywordConflictCheckResult? _lastCheckResult;

  // Interactive test state
  String _testTxType = 'expense';
  CategorySuggestion? _testCategoryResult;
  WalletSuggestion? _testWalletResult;

  @override
  void initState() {
    super.initState();
    if (widget.initialCandidateKeyword != null &&
        widget.initialCandidateKeyword!.trim().isNotEmpty) {
      _keywordInputCtrl.text = widget.initialCandidateKeyword!.trim();
    }
    _lastCheckResult = _computeLiveKeywordCheck();
  }

  @override
  void didUpdateWidget(covariant AdminOcrDictionaryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialCandidateKeyword != oldWidget.initialCandidateKeyword &&
        widget.initialCandidateKeyword != null &&
        widget.initialCandidateKeyword!.trim().isNotEmpty) {
      _keywordInputCtrl.text = widget.initialCandidateKeyword!.trim();
      _lastCheckResult = _computeLiveKeywordCheck();
    }
  }

  @override
  void dispose() {
    _keywordInputCtrl.dispose();
    _testReceiptCtrl.dispose();
    super.dispose();
  }

  void _applyConfigToState(TransactionIntelligenceConfig cfg) {
    _addedExpenseKeywords = {
      for (final e in cfg.addedExpenseKeywords.entries)
        e.key: List<String>.from(e.value),
    };
    _addedIncomeKeywords = {
      for (final e in cfg.addedIncomeKeywords.entries)
        e.key: List<String>.from(e.value),
    };
    _disabledAdminKeywords = List<String>.from(cfg.disabledAdminKeywords);
    _customProviders = List<CustomPaymentProviderRule>.from(
      cfg.customPaymentProviders,
    );
    _lastCheckResult = _computeLiveKeywordCheck();
  }

  TransactionIntelligenceConfig _buildLocalConfig() {
    return TransactionIntelligenceConfig(
      addedExpenseKeywords: _addedExpenseKeywords,
      addedIncomeKeywords: _addedIncomeKeywords,
      disabledBuiltInKeywords: const [], // Luôn rỗng — Built-in là chỉ đọc
      disabledAdminKeywords: _disabledAdminKeywords,
      customPaymentProviders: _customProviders,
    );
  }

  Map<String, dynamic> _buildLocalPayload() => _buildLocalConfig().toPayloadMap();

  KeywordConflictCheckResult? _computeLiveKeywordCheck() {
    final raw = _keywordInputCtrl.text;
    if (raw.trim().isEmpty) {
      return null;
    }
    return TransactionIntelligenceConfig.validateCandidateKeyword(
      rawKeyword: raw,
      targetGroupKey: _selectedGroupKey,
      isIncomeGroup: _isIncomeTarget,
      builtInKeywordsByGroup: _isIncomeTarget
          ? kProtectedBuiltInIncomeKeywords
          : kProtectedBuiltInExpenseKeywords,
      addedKeywordsByGroup:
          _isIncomeTarget ? _addedIncomeKeywords : _addedExpenseKeywords,
    );
  }

  void _runLiveKeywordCheck() {
    setState(() => _lastCheckResult = _computeLiveKeywordCheck());
  }

  void _addAdminKeyword() {
    final res = TransactionIntelligenceConfig.validateCandidateKeyword(
      rawKeyword: _keywordInputCtrl.text,
      targetGroupKey: _selectedGroupKey,
      isIncomeGroup: _isIncomeTarget,
      builtInKeywordsByGroup: _isIncomeTarget
          ? kProtectedBuiltInIncomeKeywords
          : kProtectedBuiltInExpenseKeywords,
      addedKeywordsByGroup:
          _isIncomeTarget ? _addedIncomeKeywords : _addedExpenseKeywords,
    );
    setState(() => _lastCheckResult = res);
    if (!res.isValid) {
      showAdminSnackBar(
        context,
        res.errorMessage ?? 'Từ khóa không hợp lệ.',
        isError: true,
      );
      return;
    }

    final targetMap =
        _isIncomeTarget ? _addedIncomeKeywords : _addedExpenseKeywords;
    final list = List<String>.from(targetMap[_selectedGroupKey] ?? const []);
    list.add(res.normalizedKeyword);
    list.sort();

    setState(() {
      targetMap[_selectedGroupKey] = list;
      _disabledAdminKeywords.remove(res.normalizedKeyword);
      _keywordInputCtrl.clear();
      _lastCheckResult = null;
    });
  }

  void _toggleAdminKeywordActive(String keyword) {
    final norm = normalizeVietnameseKeyword(keyword);
    setState(() {
      if (_disabledAdminKeywords.contains(norm)) {
        _disabledAdminKeywords.remove(norm);
      } else {
        _disabledAdminKeywords.add(norm);
        _disabledAdminKeywords.sort();
      }
    });
  }

  void _removeAdminKeyword({
    required bool isIncome,
    required String groupKey,
    required String keyword,
  }) {
    final map = isIncome ? _addedIncomeKeywords : _addedExpenseKeywords;
    final next = List<String>.from(map[groupKey] ?? const [])..remove(keyword);
    setState(() {
      if (next.isEmpty) {
        map.remove(groupKey);
      } else {
        map[groupKey] = next;
      }
      _disabledAdminKeywords.remove(normalizeVietnameseKeyword(keyword));
    });
  }

  void _runLocalMatchTest() {
    final text = _testReceiptCtrl.text.trim();
    if (text.isEmpty) {
      showAdminSnackBar(
        context,
        'Nhập chuỗi mô tả / văn bản hóa đơn OCR để kiểm thử.',
        isError: true,
      );
      return;
    }
    final service = TransactionIntelligenceService(
      rulesOverride: _buildLocalConfig(),
    );

    final sampleCategories = <Category>[
      for (final entry in kCanonicalExpenseGroupLabels.entries)
        Category(
          categoryId: 'test_exp_${entry.key}',
          userId: 'sandbox_test',
          name: entry.value,
          type: 'expense',
          icon: 'category',
          color: 0xFF1F6F8B,
          isEssential: entry.key == 'hoa don' || entry.key == 'di chuyen',
        ),
      for (final entry in kCanonicalIncomeGroupLabels.entries)
        Category(
          categoryId: 'test_inc_${entry.key}',
          userId: 'sandbox_test',
          name: entry.value,
          type: 'income',
          icon: 'payments',
          color: 0xFF2E8B57,
          isEssential: false,
        ),
    ];

    final sampleWallets = <Wallet>[
      Wallet(
        walletId: 'w_cash',
        userId: 'sandbox_test',
        walletName: 'Tiền mặt',
        type: 'cash',
        balance: 0,
        createdAt: DateTime(2026, 1, 1),
      ),
      Wallet(
        walletId: 'w_momo',
        userId: 'sandbox_test',
        walletName: 'MoMo',
        type: 'eWallet',
        balance: 0,
        createdAt: DateTime(2026, 1, 1),
      ),
      Wallet(
        walletId: 'w_vcb',
        userId: 'sandbox_test',
        walletName: 'Vietcombank',
        type: 'bank',
        balance: 0,
        createdAt: DateTime(2026, 1, 1),
      ),
      for (final rule in _customProviders)
        if (rule.isActive)
          Wallet(
            walletId: 'w_custom_${rule.key}',
            userId: 'sandbox_test',
            walletName: rule.displayLabel,
            type: rule.walletType,
            balance: 0,
            createdAt: DateTime(2026, 1, 1),
          ),
    ];

    final catSug = service.suggestCategory(
      note: text,
      ocrMerchant: text,
      transactionType: _testTxType,
      categories: sampleCategories,
    );
    final walletSug = service.suggestWallet(
      ocrRawText: text,
      wallets: sampleWallets,
    );

    setState(() {
      _testCategoryResult = catSug;
      _testWalletResult = walletSug;
    });
  }

  Future<void> _saveDraft() async {
    final payload = _buildLocalPayload();
    final errors = TransactionIntelligenceConfig.validateRawInput(payload);
    if (errors.isNotEmpty) {
      showAdminSnackBar(context, errors.first, isError: true);
      return;
    }

    setState(() => _isBusy = true);
    try {
      await widget.adminWebService.saveConfigDraft(
        adminUid: widget.currentAdminUid,
        configType: AiConfigSyncService.kDocTransactionRules,
        payload: payload,
        tokenClaimsOverride: widget.tokenClaimsOverride,
      );
      if (!mounted) return;
      showAdminSnackBar(
        context,
        'Đã lưu bản nháp Từ điển OCR. Hãy xác minh HMAC Sandbox trước khi Publish.',
      );
    } catch (e) {
      if (!mounted) return;
      showAdminSnackBar(context, formatAdminErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _verifySandbox() async {
    setState(() => _isBusy = true);
    try {
      await widget.adminWebService.verifyDraftInSandbox(
        adminUid: widget.currentAdminUid,
        configType: AiConfigSyncService.kDocTransactionRules,
        simulationSummary: {
          'addedExpenseCount': _addedExpenseKeywords.values
              .fold<int>(0, (acc, list) => acc + list.length),
          'addedIncomeCount': _addedIncomeKeywords.values
              .fold<int>(0, (acc, list) => acc + list.length),
          'disabledAdminKeywordsCount': _disabledAdminKeywords.length,
          'customProvidersCount': _customProviders.length,
        },
        tokenClaimsOverride: widget.tokenClaimsOverride,
      );
      if (!mounted) return;
      showAdminSnackBar(
        context,
        'Đã ký xác minh HMAC Sandbox cho Từ điển OCR!',
      );
    } catch (e) {
      if (!mounted) return;
      showAdminSnackBar(context, formatAdminErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _publishRules() async {
    final confirm = await showAdminConfirmDialog(
      context: context,
      title: 'Publish Từ điển OCR & Quy tắc Giao dịch?',
      message:
          'Từ khóa bổ sung và quy tắc nhà cung cấp thanh toán mới sẽ được đồng bộ tới TransactionIntelligenceService trên App User.',
      confirmLabel: 'Publish ngay',
      confirmColor: AppColors.income,
      showNoteField: true,
      confirmButtonKey: const ValueKey('ocr_confirm_publish_btn'),
    );
    if (confirm == null || !confirm.confirmed) return;

    setState(() => _isBusy = true);
    try {
      final res = await widget.adminWebService.publishConfig(
        adminUid: widget.currentAdminUid,
        configType: AiConfigSyncService.kDocTransactionRules,
        changeNote: confirm.note,
        tokenClaimsOverride: widget.tokenClaimsOverride,
      );
      if (!mounted) return;
      showAdminSnackBar(
        context,
        'Đã Publish Transaction Rules v${res['version'] ?? ''}!',
      );
    } catch (e) {
      if (!mounted) return;
      showAdminSnackBar(context, formatAdminErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _rollbackRules(ConfigVersionSnapshot target) async {
    final confirm = await showAdminConfirmDialog(
      context: context,
      title: 'Rollback Từ điển OCR về phiên bản v${target.versionNumber}?',
      message:
          'Hệ thống sẽ tạo phiên bản mới mang nội dung của v${target.versionNumber} để đưa vào Production.',
      confirmLabel: 'Xác nhận Rollback',
      confirmColor: AppColors.warning,
      showNoteField: true,
      noteRequired: true,
      noteLabel: 'Lý do Rollback (bắt buộc)',
    );
    if (confirm == null || !confirm.confirmed) return;

    setState(() => _isBusy = true);
    try {
      final res = await widget.adminWebService.rollbackConfig(
        adminUid: widget.currentAdminUid,
        configType: AiConfigSyncService.kDocTransactionRules,
        targetVersionNumber: target.versionNumber,
        reason: confirm.note,
        tokenClaimsOverride: widget.tokenClaimsOverride,
      );
      if (!mounted) return;
      _applyConfigToState(
        TransactionIntelligenceConfig.fromMap(target.payloadSnapshot),
      );
      showAdminSnackBar(
        context,
        'Đã khôi phục Transaction Rules thành v${res['version'] ?? ''}!',
      );
    } catch (e) {
      if (!mounted) return;
      showAdminSnackBar(context, formatAdminErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _showProviderDialog({
    CustomPaymentProviderRule? existing,
    int? editIndex,
  }) async {
    final savedRule = await showDialog<CustomPaymentProviderRule>(
      context: context,
      builder: (ctx) => _CustomProviderDialog(
        existing: existing,
        editIndex: editIndex,
        existingProviders: _customProviders,
      ),
    );

    if (savedRule != null && mounted) {
      setState(() {
        if (editIndex != null) {
          _customProviders[editIndex] = savedRule;
        } else {
          _customProviders.add(savedRule);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: widget.adminWebService.streamPublishedConfigMap(
        AiConfigSyncService.kDocTransactionRules,
      ),
      builder: (context, pubSnap) {
        return StreamBuilder<DraftConfigEnvelope?>(
          stream: widget.adminWebService.streamDraftConfigEnvelope(
            AiConfigSyncService.kDocTransactionRules,
          ),
          builder: (context, draftSnap) {
            if ((pubSnap.connectionState == ConnectionState.waiting ||
                    draftSnap.connectionState == ConnectionState.waiting) &&
                !_formInitialized &&
                !pubSnap.hasData &&
                !draftSnap.hasData &&
                !pubSnap.hasError &&
                !draftSnap.hasError) {
              return const AdminLoadingCard(
                message: 'Đang tải Từ điển OCR & Quy tắc giao dịch...',
              );
            }
            if (draftSnap.hasError) {
              return AdminErrorStateCard(error: draftSnap.error!);
            }
            if (pubSnap.hasError) {
              return AdminErrorStateCard(error: pubSnap.error!);
            }

            final pubMap = pubSnap.data;
            final publishedCfg = TransactionIntelligenceConfig.fromMap(pubMap);
            final publishedVer =
                pubMap != null ? (pubMap['version'] as num?)?.toInt() ?? 1 : null;
            final publishedAt = pubMap?['updatedAt'] != null
                ? DateTime.tryParse(pubMap!['updatedAt'].toString())
                : null;
            final publishedByEmail = pubMap?['updatedByEmail'] as String?;

            final draftEnvelope = draftSnap.data;
            if (!_formInitialized) {
              if (draftEnvelope != null) {
                _applyConfigToState(
                  TransactionIntelligenceConfig.fromMap(
                    draftEnvelope.draftPayload,
                  ),
                );
              } else {
                _applyConfigToState(publishedCfg);
              }
              _formInitialized = true;
            }

            final localPayload = _buildLocalPayload();
            final localHash = computeCanonicalConfigHash(localPayload);
            final localErrors =
                TransactionIntelligenceConfig.validateRawInput(localPayload);
            final bool hasUnsavedChanges = draftEnvelope == null
                ? true
                : localHash != draftEnvelope.draftHash;

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AdminDraftPublishBar(
                    configTitle: 'Từ điển Nhận diện OCR & Giao dịch (transaction_rules)',
                    publishedVersion: publishedVer,
                    publishedAt: publishedAt,
                    publishedByEmail: publishedByEmail,
                    draftEnvelope: draftEnvelope,
                    localPayloadHash: localHash,
                    hasUnsavedLocalChanges: hasUnsavedChanges,
                    localValidationErrors: localErrors,
                    isBusy: _isBusy,
                    onSaveDraft: _saveDraft,
                    onVerifySandbox: _verifySandbox,
                    onPublish: _publishRules,
                    onResetToPublished: () {
                      setState(() => _applyConfigToState(publishedCfg));
                    },
                    onResetToDefaults: () {
                      setState(() {
                        _applyConfigToState(
                          TransactionIntelligenceConfig.defaults(),
                        );
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildAddAdminKeywordSection(),
                  const SizedBox(height: 16),
                  _buildCustomProvidersSection(),
                  const SizedBox(height: 16),
                  _buildLocalMatchTestSection(),
                  const SizedBox(height: 16),
                  _buildProtectedBuiltInSection(),
                  const SizedBox(height: 16),
                  AdminVersionHistoryCard(
                    configType: AiConfigSyncService.kDocTransactionRules,
                    currentPublishedVersion: publishedVer,
                    adminWebService: widget.adminWebService,
                    isBusy: _isBusy,
                    onRollbackRequested: _rollbackRules,
                    onLoadSnapshotIntoDraft: (ver) {
                      setState(() {
                        _applyConfigToState(
                          TransactionIntelligenceConfig.fromMap(
                            ver.payloadSnapshot,
                          ),
                        );
                      });
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAddAdminKeywordSection() {
    final groupLabels = _isIncomeTarget
        ? kCanonicalIncomeGroupLabels
        : kCanonicalExpenseGroupLabels;
    final activeAddedMap =
        _isIncomeTarget ? _addedIncomeKeywords : _addedExpenseKeywords;
    final check = _lastCheckResult;

    return AdminSectionCard(
      title: 'Từ khóa Admin bổ sung (Theo Nhóm ngữ nghĩa Chuẩn)',
      subtitle:
          'Mọi từ khóa mới đều được chuẩn hóa không dấu và kiểm tra xung đột với toàn bộ từ khóa lõi trước khi thêm. Có thể bật/tắt bằng disabledAdminKeywords.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(
                    value: false,
                    label: Text('Chi tiêu (7 nhóm)'),
                  ),
                  ButtonSegment<bool>(
                    value: true,
                    label: Text('Thu nhập (2 nhóm)'),
                  ),
                ],
                selected: {_isIncomeTarget},
                onSelectionChanged: (s) {
                  setState(() {
                    _isIncomeTarget = s.first;
                    _selectedGroupKey = _isIncomeTarget ? 'luong' : 'an uong';
                  });
                  _runLiveKeywordCheck();
                },
              ),
              SizedBox(
                width: 260,
                child: DropdownButtonFormField<String>(
                  key: const ValueKey('ocr_group_dropdown'),
                  initialValue: groupLabels.containsKey(_selectedGroupKey)
                      ? _selectedGroupKey
                      : groupLabels.keys.first,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Nhóm ngữ nghĩa đích',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  items: groupLabels.entries.map((e) {
                    return DropdownMenuItem<String>(
                      value: e.key,
                      child: Text('${e.value} (${e.key})'),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _selectedGroupKey = v);
                      _runLiveKeywordCheck();
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('ocr_keyword_input'),
                  controller: _keywordInputCtrl,
                  onChanged: (_) => _runLiveKeywordCheck(),
                  onSubmitted: (_) => _addAdminKeyword(),
                  decoration: InputDecoration(
                    labelText: 'Nhập từ khóa hoặc tên thương hiệu mới',
                    hintText: 'VD: phuc long, katinat, xoi xeo...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                key: const ValueKey('ocr_add_keyword_btn'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 16,
                  ),
                ),
                onPressed: (check == null || !check.isValid)
                    ? null
                    : _addAdminKeyword,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Thêm từ khóa'),
              ),
            ],
          ),
          if (check != null) ...[
            const SizedBox(height: 8),
            if (!check.isValid)
              Container(
                key: const ValueKey('ocr_keyword_conflict_banner'),
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.expenseBackground,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  check.errorMessage ?? 'Từ khóa xung đột.',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.expense,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else if (check.warningMessage != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.warningBackground,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Chuẩn hóa: "${check.normalizedKeyword}" • ${check.warningMessage}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.warning,
                  ),
                ),
              ),
          ],
          const SizedBox(height: 16),
          for (final entry in groupLabels.entries) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${entry.value} (${entry.key}):',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.slate700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if ((activeAddedMap[entry.key] ?? const []).isEmpty)
                    const Text(
                      'Chưa có từ khóa Admin bổ sung.',
                      style: TextStyle(fontSize: 12, color: AppColors.slate400),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final kw in (activeAddedMap[entry.key] ??
                            const <String>[]))
                          _AdminKeywordChip(
                            keyword: kw,
                            isDisabled: _disabledAdminKeywords.contains(
                              normalizeVietnameseKeyword(kw),
                            ),
                            onToggleActive: () => _toggleAdminKeywordActive(kw),
                            onDelete: () => _removeAdminKeyword(
                              isIncome: _isIncomeTarget,
                              groupKey: entry.key,
                              keyword: kw,
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCustomProvidersSection() {
    return AdminSectionCard(
      title: 'Nhà cung cấp Thanh toán mở rộng (Custom Payment Providers)',
      subtitle:
          'Bổ sung quy tắc nhận diện ngân hàng / ví mới trên hóa đơn OCR. Không ghi đè các khóa lõi được bảo vệ.',
      trailing: ElevatedButton.icon(
        key: const ValueKey('ocr_add_provider_btn'),
        onPressed: () => _showProviderDialog(),
        icon: const Icon(Icons.add, size: 17),
        label: const Text('Thêm nhà cung cấp'),
      ),
      child: _customProviders.isEmpty
          ? AdminEmptyStateCard(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Chưa có nhà cung cấp thanh toán mở rộng',
              subtitle:
                  'Hệ thống vẫn nhận diện đầy đủ ${kProtectedPaymentProviderKeys.length} nhà cung cấp mặc định được bảo vệ.',
            )
          : Column(
              children: [
                for (int i = 0; i < _customProviders.length; i++) ...[
                  if (i > 0) const Divider(height: 14, color: AppColors.slate200),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  _customProviders[i].displayLabel,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                AdminStatusBadge(
                                  label:
                                      '${_customProviders[i].key} • ${_customProviders[i].walletType}',
                                  color: AppColors.info,
                                  backgroundColor: AppColors.infoBackground,
                                ),
                                AdminStatusBadge(
                                  label: _customProviders[i].isActive
                                      ? 'Đang bật'
                                      : 'Đã tắt',
                                  color: _customProviders[i].isActive
                                      ? AppColors.income
                                      : AppColors.warning,
                                  backgroundColor: _customProviders[i].isActive
                                      ? AppColors.incomeBackground
                                      : AppColors.warningBackground,
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Từ khóa hóa đơn: ${_customProviders[i].receiptKeywords.join(', ')}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.slate600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        key: ValueKey(
                          'ocr_provider_active_switch_${_customProviders[i].key}',
                        ),
                        value: _customProviders[i].isActive,
                        onChanged: (v) {
                          final old = _customProviders[i];
                          setState(() {
                            _customProviders[i] = CustomPaymentProviderRule(
                              key: old.key,
                              displayLabel: old.displayLabel,
                              walletType: old.walletType,
                              receiptKeywords: old.receiptKeywords,
                              walletNameAliases: old.walletNameAliases,
                              isActive: v,
                            );
                          });
                        },
                      ),
                      IconButton(
                        tooltip: 'Chỉnh sửa',
                        onPressed: () => _showProviderDialog(
                          existing: _customProviders[i],
                          editIndex: i,
                        ),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                      ),
                      IconButton(
                        tooltip: 'Xóa khỏi Draft',
                        onPressed: () {
                          setState(() => _customProviders.removeAt(i));
                        },
                        icon: const Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: AppColors.expense,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildLocalMatchTestSection() {
    return AdminSectionCard(
      title: 'Kiểm thử khớp Từ điển cục bộ (TransactionIntelligenceService)',
      subtitle:
          'Chạy thuật toán đối chiếu nội bộ 100% bằng bản Draft hiện tại, không gọi Gemini API.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'expense', label: Text('Giao dịch Chi')),
                  ButtonSegment(value: 'income', label: Text('Giao dịch Thu')),
                ],
                selected: {_testTxType},
                onSelectionChanged: (s) =>
                    setState(() => _testTxType = s.first),
              ),
              ElevatedButton.icon(
                key: const ValueKey('ocr_run_local_test_btn'),
                onPressed: _runLocalMatchTest,
                icon: const Icon(Icons.troubleshoot_rounded, size: 18),
                label: const Text('Kiểm thử khớp ngay'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('ocr_local_test_input'),
            controller: _testReceiptCtrl,
            decoration: InputDecoration(
              labelText: 'Văn bản hóa đơn / Ghi chú giao dịch giả lập',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          if (_testCategoryResult != null || _testWalletResult != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                if (_testCategoryResult != null)
                  AdminStatusBadge(
                    label: _testCategoryResult!.categoryName.isNotEmpty
                        ? 'Danh mục khớp: ${_testCategoryResult!.categoryName} (${_testCategoryResult!.source})'
                        : 'Danh mục: Chưa khớp nhóm nào',
                    color: _testCategoryResult!.categoryName.isNotEmpty
                        ? AppColors.income
                        : AppColors.slate600,
                    backgroundColor: _testCategoryResult!.categoryName.isNotEmpty
                        ? AppColors.incomeBackground
                        : AppColors.slate100,
                  ),
                if (_testWalletResult != null)
                  AdminStatusBadge(
                    label: _testWalletResult!.detectedPaymentLabel.isNotEmpty
                        ? 'Thanh toán: ${_testWalletResult!.detectedPaymentLabel} (${_testWalletResult!.detectedWalletType})'
                        : 'Thanh toán: Không phát hiện ví/ngân hàng',
                    color: _testWalletResult!.detectedPaymentLabel.isNotEmpty
                        ? AppColors.info
                        : AppColors.slate600,
                    backgroundColor:
                        _testWalletResult!.detectedPaymentLabel.isNotEmpty
                            ? AppColors.infoBackground
                            : AppColors.slate100,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProtectedBuiltInSection() {
    return AdminSectionCard(
      title: 'Quy tắc lõi Hệ thống được bảo vệ (Built-in — Chỉ đọc)',
      subtitle:
          'Không thể xóa hoặc vô hiệu hóa các từ khóa và nhà cung cấp mặc định này để bảo toàn độ chính xác nền tảng.',
      trailing: const AdminStatusBadge(
        label: 'Read-Only Locked',
        color: AppColors.slate700,
        backgroundColor: AppColors.slate100,
        icon: Icons.lock_outline_rounded,
      ),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text(
          'Xem danh sách từ khóa chi tiêu, thu nhập và nhà cung cấp thanh toán lõi',
          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Chi tiêu mặc định:',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                for (final e in kProtectedBuiltInExpenseKeywords.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• ${kCanonicalExpenseGroupLabels[e.key] ?? e.key}: ${e.value.join(', ')}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.slate600,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                const Text(
                  'Thu nhập mặc định:',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                for (final e in kProtectedBuiltInIncomeKeywords.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• ${kCanonicalIncomeGroupLabels[e.key] ?? e.key}: ${e.value.join(', ')}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.slate600,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                const Text(
                  'Khóa nhà cung cấp thanh toán được bảo vệ:',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final k in kProtectedPaymentProviderKeys)
                      Chip(
                        avatar: const Icon(Icons.lock, size: 13),
                        label: Text(k, style: const TextStyle(fontSize: 11.5)),
                        visualDensity: VisualDensity.compact,
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
}

class _AdminKeywordChip extends StatelessWidget {
  final String keyword;
  final bool isDisabled;
  final VoidCallback onToggleActive;
  final VoidCallback onDelete;

  const _AdminKeywordChip({
    required this.keyword,
    required this.isDisabled,
    required this.onToggleActive,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isDisabled ? AppColors.slate100 : AppColors.infoBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDisabled
              ? AppColors.slate300
              : AppColors.info.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            keyword,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: isDisabled ? AppColors.slate500 : AppColors.slate800,
              decoration: isDisabled ? TextDecoration.lineThrough : null,
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            key: ValueKey('ocr_toggle_kw_$keyword'),
            onTap: onToggleActive,
            child: Tooltip(
              message: isDisabled ? 'Bật lại từ khóa' : 'Tạm tắt từ khóa',
              child: Icon(
                isDisabled ? Icons.visibility_off_outlined : Icons.visibility,
                size: 16,
                color: isDisabled ? AppColors.slate500 : AppColors.info,
              ),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            key: ValueKey('ocr_delete_kw_$keyword'),
            onTap: onDelete,
            child: const Tooltip(
              message: 'Xóa khỏi Draft',
              child: Icon(Icons.close, size: 16, color: AppColors.expense),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomProviderDialog extends StatefulWidget {
  final CustomPaymentProviderRule? existing;
  final int? editIndex;
  final List<CustomPaymentProviderRule> existingProviders;

  const _CustomProviderDialog({
    required this.existing,
    required this.editIndex,
    required this.existingProviders,
  });

  @override
  State<_CustomProviderDialog> createState() => _CustomProviderDialogState();
}

class _CustomProviderDialogState extends State<_CustomProviderDialog> {
  late final TextEditingController _keyCtrl;
  late final TextEditingController _labelCtrl;
  late final TextEditingController _keywordsCtrl;
  late final TextEditingController _aliasesCtrl;
  late String _walletType;
  late bool _isActive;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _keyCtrl = TextEditingController(text: existing?.key ?? '');
    _labelCtrl = TextEditingController(text: existing?.displayLabel ?? '');
    _keywordsCtrl = TextEditingController(
      text: (existing?.receiptKeywords ?? const []).join(', '),
    );
    _aliasesCtrl = TextEditingController(
      text: (existing?.walletNameAliases ?? const []).join(', '),
    );
    _walletType = existing?.walletType ?? 'bank';
    _isActive = existing?.isActive ?? true;
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _labelCtrl.dispose();
    _keywordsCtrl.dispose();
    _aliasesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    final normKey = normalizeVietnameseKeyword(_keyCtrl.text)
        .replaceAll(' ', '_');
    final kws = _keywordsCtrl.text
        .split(',')
        .map(normalizeVietnameseKeyword)
        .where((s) => s.length >= 2)
        .toSet()
        .toList();
    final aliases = _aliasesCtrl.text
        .split(',')
        .map(normalizeVietnameseKeyword)
        .where((s) => s.length >= 2)
        .toSet()
        .toList();

    final errs = <String>[];
    if (!RegExp(r'^[a-z0-9_]{2,40}$').hasMatch(normKey)) {
      errs.add('Key phải dài 2-40 ký tự a-z, 0-9 hoặc "_".');
    } else if (kProtectedPaymentProviderKeys.contains(normKey)) {
      errs.add(
        'Không thể ghi đè nhà cung cấp mặc định được bảo vệ ($normKey).',
      );
    } else if (widget.existingProviders.asMap().entries.any(
          (e) => e.key != widget.editIndex && e.value.key == normKey,
        )) {
      errs.add('Key "$normKey" đã tồn tại trong danh sách.');
    }
    final cleanLabel = _labelCtrl.text.trim();
    if (cleanLabel.length < 2 || cleanLabel.length > 60) {
      errs.add('Tên hiển thị phải từ 2 đến 60 ký tự.');
    }
    if (kws.isEmpty) {
      errs.add('Phải nhập ít nhất 1 receiptKeywords (cách nhau bằng dấu phẩy).');
    }

    return AlertDialog(
      title: Text(
        existing == null
            ? 'Thêm Nhà cung cấp Thanh toán mới'
            : 'Chỉnh sửa: ${existing.displayLabel}',
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const ValueKey('ocr_provider_key_input'),
                controller: _keyCtrl,
                readOnly: existing != null,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Provider Key (VD: shopeepay_biz, kredivo)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('ocr_provider_label_input'),
                controller: _labelCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Tên hiển thị (VD: Kredivo PayLater)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _walletType,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Loại ví ánh xạ (walletType)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                items: kCanonicalWalletTypes.map((w) {
                  return DropdownMenuItem<String>(
                    value: w,
                    child: Text(w, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _walletType = v);
                },
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('ocr_provider_keywords_input'),
                controller: _keywordsCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Từ khóa trên hóa đơn (cách nhau bởi dấu phẩy)',
                  hintText: 'VD: kredivo, kredivo pay',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _aliasesCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText:
                      'Tên ví tương đương (tùy chọn, mặc định dùng receiptKeywords)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Bật quy tắc (isActive)'),
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
              ),
              if (errs.isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.expenseBackground,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final err in errs)
                        Text(
                          '• $err',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.expense,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Hủy'),
        ),
        ElevatedButton(
          key: const ValueKey('ocr_provider_save_btn'),
          onPressed: errs.isNotEmpty
              ? null
              : () {
                  Navigator.of(context).pop(
                    CustomPaymentProviderRule(
                      key: normKey,
                      displayLabel: cleanLabel,
                      walletType: _walletType,
                      receiptKeywords: kws,
                      walletNameAliases: aliases.isEmpty ? kws : aliases,
                      isActive: _isActive,
                    ),
                  );
                },
          child: const Text('Lưu vào Draft'),
        ),
      ],
    );
  }
}

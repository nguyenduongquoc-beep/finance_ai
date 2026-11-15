import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/ai_runtime_config_model.dart';
import '../../services/ai_config_sync_service.dart';
import '../../utils/constants.dart';
import '../services/admin_ai_sandbox_service.dart';
import '../services/admin_web_service.dart';
import '../widgets/admin_governance_widgets.dart';

class _HeuristicsFieldSpec {
  final String key;
  final String label;
  final String hint;
  final double min;
  final double max;
  final double defaultValue;
  final bool isInt;
  final int groupIndex; // 1..4

  const _HeuristicsFieldSpec({
    required this.key,
    required this.label,
    required this.hint,
    required this.min,
    required this.max,
    required this.defaultValue,
    this.isInt = false,
    required this.groupIndex,
  });
}

/// Khu vực 3: Financial Rules & Knowledge
/// - Subtab 0: Bộ tham số & Ngưỡng định lượng Tài chính (`financial_heuristics` - 18 tham số).
/// - Subtab 1: Kho Tri thức Tài chính (`financial_knowledge_drafts` / `financial_knowledge_published`).
class AdminRulesKnowledgeView extends StatefulWidget {
  final AdminWebService adminWebService;
  final String currentAdminUid;
  final String currentAdminEmail;
  final AdminAiSandboxService sandboxService;
  final Map<String, dynamic>? tokenClaimsOverride;
  final int initialSubTabIndex;

  const AdminRulesKnowledgeView({
    super.key,
    required this.adminWebService,
    required this.currentAdminUid,
    required this.currentAdminEmail,
    this.sandboxService = const AdminAiSandboxService(),
    this.tokenClaimsOverride,
    this.initialSubTabIndex = 0,
  });

  @override
  State<AdminRulesKnowledgeView> createState() =>
      _AdminRulesKnowledgeViewState();
}

class _AdminRulesKnowledgeViewState extends State<AdminRulesKnowledgeView> {
  static const List<_HeuristicsFieldSpec> _fieldSpecs = [
    // Nhóm 1: Phân tích vấn đề chi tiêu tháng
    _HeuristicsFieldSpec(
      key: 'categorySpikeRatio',
      label: 'Ngưỡng đột biến danh mục (Tỷ lệ tăng)',
      hint: '0.15 – 0.60 (VD: 0.30 = tăng >= 30%)',
      min: 0.15,
      max: 0.60,
      defaultValue: 0.30,
      groupIndex: 1,
    ),
    _HeuristicsFieldSpec(
      key: 'categoryIncomeShareThreshold',
      label: 'Ngưỡng tỷ trọng danh mục / Thu nhập',
      hint: '0.15 – 0.50 (VD: 0.25 = >= 25% thu nhập)',
      min: 0.15,
      max: 0.50,
      defaultValue: 0.25,
      groupIndex: 1,
    ),
    _HeuristicsFieldSpec(
      key: 'minRecommendedSavingRate',
      label: 'Tỷ lệ tiết kiệm khuyến nghị tối thiểu',
      hint: '0.05 – 0.40 (VD: 0.20 = 20%)',
      min: 0.05,
      max: 0.40,
      defaultValue: 0.20,
      groupIndex: 1,
    ),
    _HeuristicsFieldSpec(
      key: 'incomeDropWarningRatio',
      label: 'Ngưỡng cảnh báo sụt giảm thu nhập',
      hint: '0.10 – 0.40 (VD: 0.20 = giảm 20%)',
      min: 0.10,
      max: 0.40,
      defaultValue: 0.20,
      groupIndex: 1,
    ),
    _HeuristicsFieldSpec(
      key: 'incomeDropCriticalRatio',
      label: 'Ngưỡng nghiêm trọng sụt giảm thu nhập',
      hint: '0.25 – 0.70 (Phải >= cảnh báo + 0.10)',
      min: 0.25,
      max: 0.70,
      defaultValue: 0.40,
      groupIndex: 1,
    ),
    // Nhóm 2: Lập kế hoạch tháng
    _HeuristicsFieldSpec(
      key: 'defaultSavingRateNoGoal',
      label: 'Tỷ lệ tiết kiệm mặc định (Khi chưa có mục tiêu)',
      hint: '0.05 – 0.35 (Phải <= mức khuyến nghị)',
      min: 0.05,
      max: 0.35,
      defaultValue: 0.15,
      groupIndex: 2,
    ),
    _HeuristicsFieldSpec(
      key: 'flexibleSpendFloorRatio',
      label: 'Ngưỡng sàn chi tiêu linh hoạt tối thiểu',
      hint: '0.50 – 0.85 (Tối thiểu giữ lại khi cắt giảm)',
      min: 0.50,
      max: 0.85,
      defaultValue: 0.70,
      groupIndex: 2,
    ),
    _HeuristicsFieldSpec(
      key: 'planBudgetAdherenceWeight',
      label: 'Trọng số tuân thủ ngân sách (Saving = 1 - weight)',
      hint: '0.40 – 0.80 (VD: 0.60)',
      min: 0.40,
      max: 0.80,
      defaultValue: 0.60,
      groupIndex: 2,
    ),
    // Nhóm 3: Dự báo danh mục, Ngân sách & Điểm sức khỏe
    _HeuristicsFieldSpec(
      key: 'budgetNearLimitRatio',
      label: 'Ngưỡng cảnh báo sắp vượt ngân sách',
      hint: '0.70 – 0.95 (VD: 0.80 = 80% hạn mức)',
      min: 0.70,
      max: 0.95,
      defaultValue: 0.80,
      groupIndex: 3,
    ),
    _HeuristicsFieldSpec(
      key: 'categoryForecastWarningRatio',
      label: 'Hệ số cảnh báo dự báo danh mục',
      hint: '1.15 – 1.60 (VD: 1.30x)',
      min: 1.15,
      max: 1.60,
      defaultValue: 1.30,
      groupIndex: 3,
    ),
    _HeuristicsFieldSpec(
      key: 'categoryForecastCriticalRatio',
      label: 'Hệ số nghiêm trọng dự báo danh mục',
      hint: '1.40 – 2.50 (Phải >= cảnh báo + 0.15)',
      min: 1.40,
      max: 2.50,
      defaultValue: 1.60,
      groupIndex: 3,
    ),
    _HeuristicsFieldSpec(
      key: 'categoryForecastMinDiffVnd',
      label: 'Chênh lệch tối thiểu cảnh báo dự báo (VND)',
      hint: '50,000 – 500,000 VND',
      min: 50000,
      max: 500000,
      defaultValue: 100000,
      groupIndex: 3,
    ),
    _HeuristicsFieldSpec(
      key: 'healthNegativeBalancePenalty',
      label: 'Điểm trừ dự báo dòng tiền âm',
      hint: '10 – 40 điểm (Số nguyên)',
      min: 10,
      max: 40,
      defaultValue: 25,
      isInt: true,
      groupIndex: 3,
    ),
    _HeuristicsFieldSpec(
      key: 'healthBudgetExceededPenalty',
      label: 'Điểm trừ mỗi ngân sách vượt hạn mức',
      hint: '5 – 25 điểm (Số nguyên)',
      min: 5,
      max: 25,
      defaultValue: 15,
      isInt: true,
      groupIndex: 3,
    ),
    _HeuristicsFieldSpec(
      key: 'healthBudgetAtRiskPenalty',
      label: 'Điểm trừ mỗi ngân sách có nguy cơ vượt',
      hint: '5 – 20 điểm (Số nguyên)',
      min: 5,
      max: 20,
      defaultValue: 10,
      isInt: true,
      groupIndex: 3,
    ),
    // Nhóm 4: Cảnh báo giao dịch đơn lẻ bất thường
    _HeuristicsFieldSpec(
      key: 'txAnomalyMinDiffVnd',
      label: 'Chênh lệch tối thiểu giao dịch lẻ (VND)',
      hint: '50,000 – 500,000 VND',
      min: 50000,
      max: 500000,
      defaultValue: 100000,
      groupIndex: 4,
    ),
    _HeuristicsFieldSpec(
      key: 'txAnomalyWarningMultiplier',
      label: 'Hệ số cảnh báo giao dịch lẻ bất thường',
      hint: '1.5 – 3.5x trung vị 90 ngày',
      min: 1.5,
      max: 3.5,
      defaultValue: 2.0,
      groupIndex: 4,
    ),
    _HeuristicsFieldSpec(
      key: 'txAnomalyCriticalMultiplier',
      label: 'Hệ số nghiêm trọng giao dịch lẻ bất thường',
      hint: '3.0 – 6.0x (Phải >= cảnh báo + 1.0)',
      min: 3.0,
      max: 6.0,
      defaultValue: 4.0,
      groupIndex: 4,
    ),
  ];

  static const Map<int, String> _groupTitles = {
    1: 'Nhóm 1: Phát hiện vấn đề chi tiêu & thu nhập tháng',
    2: 'Nhóm 2: Thuật toán lập kế hoạch tài chính tháng',
    3: 'Nhóm 3: Dự báo ngân sách & Điểm sức khỏe tài chính',
    4: 'Nhóm 4: Cảnh báo giao dịch đơn lẻ bất thường',
  };

  static const Map<String, String> _topicLabels = {
    'budget_rule': 'Quy tắc phân bổ ngân sách',
    'saving_strategy': 'Chiến lược tiết kiệm',
    'spending_control': 'Kiểm soát chi tiêu',
    'crisis_recovery': 'Phục hồi khi thâm hụt',
  };

  late int _subTabIndex;
  final Map<String, TextEditingController> _heurCtrls = {};
  bool _heurFormInitialized = false;
  bool _isBusy = false;

  // Deterministic preview state for Heuristics
  final List<SyntheticPersona> _personas = SyntheticPersona.builtInPersonas();
  late String _previewPersonaId;
  AdminSandboxSimulationResult? _publishedPreview;
  AdminSandboxSimulationResult? _draftPreview;

  @override
  void initState() {
    super.initState();
    _subTabIndex = widget.initialSubTabIndex;
    _previewPersonaId = _personas.first.id;
    for (final spec in _fieldSpecs) {
      _heurCtrls[spec.key] = TextEditingController(
        text: spec.isInt
            ? spec.defaultValue.toInt().toString()
            : spec.defaultValue.toString(),
      );
    }
  }

  @override
  void didUpdateWidget(covariant AdminRulesKnowledgeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialSubTabIndex != oldWidget.initialSubTabIndex) {
      _subTabIndex = widget.initialSubTabIndex;
    }
  }

  @override
  void dispose() {
    for (final c in _heurCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _applyHeuristicsToForm(FinancialHeuristicsConfig cfg) {
    final map = cfg.toPayloadMap();
    for (final spec in _fieldSpecs) {
      final val = map[spec.key];
      if (val is num) {
        _heurCtrls[spec.key]?.text = spec.isInt
            ? val.toInt().toString()
            : _formatCleanDouble(val.toDouble());
      }
    }
  }

  String _formatCleanDouble(double v) {
    if (v >= 1000 && v == v.roundToDouble()) {
      return v.toInt().toString();
    }
    return v.toString();
  }

  Map<String, dynamic> _buildCurrentHeuristicsRawPayload() {
    final out = <String, dynamic>{};
    for (final spec in _fieldSpecs) {
      final rawText = (_heurCtrls[spec.key]?.text ?? '').trim();
      if (rawText.isEmpty) {
        out[spec.key] = null;
        continue;
      }
      if (spec.isInt) {
        final parsed = int.tryParse(rawText);
        if (parsed != null) {
          out[spec.key] = parsed;
        } else {
          final parsedDouble = double.tryParse(rawText);
          out[spec.key] = parsedDouble ?? rawText;
        }
      } else {
        final parsed = double.tryParse(rawText);
        out[spec.key] = parsed ?? rawText;
      }
    }
    return out;
  }

  Future<void> _saveHeuristicsDraft() async {
    final payload = _buildCurrentHeuristicsRawPayload();
    final errors = FinancialHeuristicsConfig.validateRawInput(payload);
    if (errors.isNotEmpty) {
      showAdminSnackBar(context, errors.first, isError: true);
      return;
    }

    setState(() => _isBusy = true);
    try {
      await widget.adminWebService.saveConfigDraft(
        adminUid: widget.currentAdminUid,
        configType: AiConfigSyncService.kDocFinancialHeuristics,
        payload: payload,
        tokenClaimsOverride: widget.tokenClaimsOverride,
      );
      if (!mounted) return;
      showAdminSnackBar(
        context,
        'Đã lưu bản nháp Tham số Định lượng. Hãy xác minh Sandbox trước khi Publish.',
      );
    } catch (e) {
      if (!mounted) return;
      showAdminSnackBar(context, formatAdminErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _verifyHeuristicsDraft(
    FinancialHeuristicsConfig publishedCfg,
    FinancialHeuristicsConfig draftCfg,
  ) async {
    setState(() => _isBusy = true);
    try {
      final sim = _draftPreview ??
          widget.sandboxService.simulatePersona(
            persona: _personas.firstWhere((p) => p.id == _previewPersonaId),
            runtimeConfig: AiRuntimeConfig.defaults(),
            heuristicsConfig: draftCfg,
            transactionRules: TransactionIntelligenceConfig.defaults(),
          );
      await widget.adminWebService.verifyDraftInSandbox(
        adminUid: widget.currentAdminUid,
        configType: AiConfigSyncService.kDocFinancialHeuristics,
        simulationSummary: sim.toVerificationSummary(),
        tokenClaimsOverride: widget.tokenClaimsOverride,
      );
      if (!mounted) return;
      showAdminSnackBar(
        context,
        'Đã ký xác minh HMAC Sandbox cho Tham số Định lượng!',
      );
    } catch (e) {
      if (!mounted) return;
      showAdminSnackBar(context, formatAdminErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _publishHeuristics() async {
    final confirm = await showAdminConfirmDialog(
      context: context,
      title: 'Publish Tham số Định lượng lên Production?',
      message:
          'Các ngưỡng cảnh báo, lập kế hoạch và điểm sức khỏe tài chính sẽ áp dụng cho toàn bộ người dùng sau lần đồng bộ cấu hình tiếp theo.',
      confirmLabel: 'Publish ngay',
      confirmColor: AppColors.income,
      showNoteField: true,
      confirmButtonKey: const ValueKey('heuristics_confirm_publish_btn'),
    );
    if (confirm == null || !confirm.confirmed) return;

    setState(() => _isBusy = true);
    try {
      final res = await widget.adminWebService.publishConfig(
        adminUid: widget.currentAdminUid,
        configType: AiConfigSyncService.kDocFinancialHeuristics,
        changeNote: confirm.note,
        tokenClaimsOverride: widget.tokenClaimsOverride,
      );
      if (!mounted) return;
      showAdminSnackBar(
        context,
        'Đã Publish Financial Heuristics v${res['version'] ?? ''}!',
      );
    } catch (e) {
      if (!mounted) return;
      showAdminSnackBar(context, formatAdminErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _rollbackHeuristics(ConfigVersionSnapshot target) async {
    final confirm = await showAdminConfirmDialog(
      context: context,
      title: 'Rollback Tham số Định lượng về v${target.versionNumber}?',
      message:
          'Hệ thống sẽ tạo phiên bản mới mang giá trị của bản chụp v${target.versionNumber}. Lịch sử cũ luôn được bảo toàn.',
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
        configType: AiConfigSyncService.kDocFinancialHeuristics,
        targetVersionNumber: target.versionNumber,
        reason: confirm.note,
        tokenClaimsOverride: widget.tokenClaimsOverride,
      );
      if (!mounted) return;
      _applyHeuristicsToForm(
        FinancialHeuristicsConfig.fromMap(target.payloadSnapshot),
      );
      showAdminSnackBar(
        context,
        'Đã khôi phục Heuristics thành phiên bản mới v${res['version'] ?? ''}!',
      );
    } catch (e) {
      if (!mounted) return;
      showAdminSnackBar(context, formatAdminErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _runHeuristicsImpactComparison(FinancialHeuristicsConfig publishedCfg) {
    final payload = _buildCurrentHeuristicsRawPayload();
    final errors = FinancialHeuristicsConfig.validateRawInput(payload);
    if (errors.isNotEmpty) {
      showAdminSnackBar(context, errors.first, isError: true);
      return;
    }
    final draftCfg = FinancialHeuristicsConfig.fromMap(payload);
    final persona = _personas.firstWhere(
      (p) => p.id == _previewPersonaId,
      orElse: () => _personas.first,
    );

    final pubRes = widget.sandboxService.simulatePersona(
      persona: persona,
      runtimeConfig: AiRuntimeConfig.defaults(),
      heuristicsConfig: publishedCfg,
      transactionRules: TransactionIntelligenceConfig.defaults(),
    );
    final draftRes = widget.sandboxService.simulatePersona(
      persona: persona,
      runtimeConfig: AiRuntimeConfig.defaults(),
      heuristicsConfig: draftCfg,
      transactionRules: TransactionIntelligenceConfig.defaults(),
    );
    setState(() {
      _publishedPreview = pubRes;
      _draftPreview = draftRes;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment<int>(
                    value: 0,
                    icon: Icon(Icons.tune_rounded, size: 17),
                    label: Text('Tham số Định lượng (18 chỉ số)'),
                  ),
                  ButtonSegment<int>(
                    value: 1,
                    icon: Icon(Icons.menu_book_rounded, size: 17),
                    label: Text('Kho Tri thức Tài chính'),
                  ),
                ],
                selected: {_subTabIndex},
                onSelectionChanged: (s) {
                  setState(() => _subTabIndex = s.first);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _subTabIndex == 0
                ? _buildHeuristicsTab(context)
                : _buildKnowledgeBaseTab(context),
          ),
        ],
      ),
    );
  }

  Widget _buildHeuristicsTab(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: widget.adminWebService.streamPublishedConfigMap(
        AiConfigSyncService.kDocFinancialHeuristics,
      ),
      builder: (context, pubSnap) {
        return StreamBuilder<DraftConfigEnvelope?>(
          stream: widget.adminWebService.streamDraftConfigEnvelope(
            AiConfigSyncService.kDocFinancialHeuristics,
          ),
          builder: (context, draftSnap) {
            if ((pubSnap.connectionState == ConnectionState.waiting ||
                    draftSnap.connectionState == ConnectionState.waiting) &&
                !_heurFormInitialized &&
                !pubSnap.hasData &&
                !draftSnap.hasData &&
                !pubSnap.hasError &&
                !draftSnap.hasError) {
              return const AdminLoadingCard(
                message: 'Đang tải bộ tham số Financial Heuristics...',
              );
            }
            if (draftSnap.hasError) {
              return AdminErrorStateCard(error: draftSnap.error!);
            }
            if (pubSnap.hasError) {
              return AdminErrorStateCard(error: pubSnap.error!);
            }

            final pubMap = pubSnap.data;
            final publishedCfg = FinancialHeuristicsConfig.fromMap(pubMap);
            final publishedVer =
                pubMap != null ? (pubMap['version'] as num?)?.toInt() ?? 1 : null;
            final publishedAt = pubMap?['updatedAt'] != null
                ? DateTime.tryParse(pubMap!['updatedAt'].toString())
                : null;
            final publishedByEmail = pubMap?['updatedByEmail'] as String?;

            final draftEnvelope = draftSnap.data;
            if (!_heurFormInitialized) {
              if (draftEnvelope != null) {
                _applyHeuristicsToForm(
                  FinancialHeuristicsConfig.fromMap(draftEnvelope.draftPayload),
                );
              } else {
                _applyHeuristicsToForm(publishedCfg);
              }
              _heurFormInitialized = true;
            }

            final localPayload = _buildCurrentHeuristicsRawPayload();
            final localErrors =
                FinancialHeuristicsConfig.validateRawInput(localPayload);
            final normalizedForHash = localErrors.isEmpty
                ? FinancialHeuristicsConfig.fromMap(localPayload).toPayloadMap()
                : localPayload;
            final localHash = computeCanonicalConfigHash(normalizedForHash);
            final bool hasUnsavedChanges = draftEnvelope == null
                ? true
                : localHash != draftEnvelope.draftHash;

            return SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AdminDraftPublishBar(
                    configTitle: 'Bộ tham số Định lượng (financial_heuristics)',
                    publishedVersion: publishedVer,
                    publishedAt: publishedAt,
                    publishedByEmail: publishedByEmail,
                    draftEnvelope: draftEnvelope,
                    localPayloadHash: localHash,
                    hasUnsavedLocalChanges: hasUnsavedChanges,
                    localValidationErrors: localErrors,
                    isBusy: _isBusy,
                    onSaveDraft: _saveHeuristicsDraft,
                    onVerifySandbox: () => _verifyHeuristicsDraft(
                      publishedCfg,
                      FinancialHeuristicsConfig.fromMap(normalizedForHash),
                    ),
                    onPublish: _publishHeuristics,
                    onResetToPublished: () {
                      setState(() {
                        _applyHeuristicsToForm(publishedCfg);
                      });
                    },
                    onResetToDefaults: () {
                      setState(() {
                        _applyHeuristicsToForm(
                          FinancialHeuristicsConfig.defaults(),
                        );
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  for (int g = 1; g <= 4; g++) ...[
                    _buildHeuristicsGroupCard(g, publishedCfg.toPayloadMap()),
                    const SizedBox(height: 14),
                  ],
                  _buildHeuristicsImpactCard(publishedCfg),
                  const SizedBox(height: 16),
                  AdminVersionHistoryCard(
                    configType: AiConfigSyncService.kDocFinancialHeuristics,
                    currentPublishedVersion: publishedVer,
                    adminWebService: widget.adminWebService,
                    isBusy: _isBusy,
                    onRollbackRequested: _rollbackHeuristics,
                    onLoadSnapshotIntoDraft: (ver) {
                      setState(() {
                        _applyHeuristicsToForm(
                          FinancialHeuristicsConfig.fromMap(ver.payloadSnapshot),
                        );
                      });
                      showAdminSnackBar(
                        context,
                        'Đã nạp bản chụp v${ver.versionNumber} vào form nháp.',
                      );
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

  Widget _buildHeuristicsGroupCard(
    int groupIndex,
    Map<String, dynamic> publishedPayload,
  ) {
    final specs =
        _fieldSpecs.where((s) => s.groupIndex == groupIndex).toList();
    return AdminSectionCard(
      title: _groupTitles[groupIndex] ?? 'Nhóm tham số',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 900
              ? 3
              : (constraints.maxWidth >= 560 ? 2 : 1);
          final itemWidth =
              (constraints.maxWidth - (columns - 1) * 14) / columns;

          return Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              for (final spec in specs)
                SizedBox(
                  width: itemWidth,
                  child: TextField(
                    key: ValueKey('heur_input_${spec.key}'),
                    controller: _heurCtrls[spec.key],
                    keyboardType: TextInputType.numberWithOptions(
                      decimal: !spec.isInt,
                    ),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: spec.label,
                      helperText:
                          '${spec.hint} • Published: ${publishedPayload[spec.key]}',
                      helperMaxLines: 2,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeuristicsImpactCard(FinancialHeuristicsConfig publishedCfg) {
    return AdminSectionCard(
      title: 'Kiểm thử tác động định lượng (Published vs Draft trên Synthetic Persona)',
      subtitle:
          'So sánh Health Score, số vấn đề chi tiêu và mức tiết kiệm mục tiêu trước khi ký HMAC.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 360,
                child: DropdownButtonFormField<String>(
                  initialValue: _previewPersonaId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Chọn Synthetic Persona đối chiếu',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  items: _personas.map((p) {
                    return DropdownMenuItem<String>(
                      value: p.id,
                      child: Text(p.title, overflow: TextOverflow.ellipsis),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _previewPersonaId = v);
                  },
                ),
              ),
              ElevatedButton.icon(
                key: const ValueKey('heuristics_run_comparison_btn'),
                onPressed: () => _runHeuristicsImpactComparison(publishedCfg),
                icon: const Icon(Icons.compare_arrows_rounded, size: 18),
                label: const Text('Chạy đối chiếu Published vs Draft'),
              ),
            ],
          ),
          if (_publishedPreview != null && _draftPreview != null) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                _ImpactSummaryTile(
                  title: 'Bản Published hiện tại',
                  result: _publishedPreview!,
                  color: AppColors.info,
                  bgColor: AppColors.infoBackground,
                ),
                _ImpactSummaryTile(
                  title: 'Bản Draft đang chỉnh sửa',
                  result: _draftPreview!,
                  color: AppColors.income,
                  bgColor: AppColors.incomeBackground,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildKnowledgeBaseTab(BuildContext context) {
    return StreamBuilder<List<AdminKnowledgeDraftRecord>>(
      stream: widget.adminWebService.streamKnowledgeDrafts(),
      builder: (context, draftSnap) {
        return StreamBuilder<List<AdminKnowledgePublishedRecord>>(
          stream: widget.adminWebService.streamKnowledgePublished(),
          builder: (context, pubSnap) {
            if ((draftSnap.connectionState == ConnectionState.waiting ||
                    pubSnap.connectionState == ConnectionState.waiting) &&
                !draftSnap.hasData &&
                !pubSnap.hasData &&
                !draftSnap.hasError &&
                !pubSnap.hasError) {
              return const AdminLoadingCard(
                message: 'Đang tải Kho Tri thức Tài chính...',
              );
            }
            if (draftSnap.hasError) {
              return AdminErrorStateCard(error: draftSnap.error!);
            }
            if (pubSnap.hasError) {
              return AdminErrorStateCard(error: pubSnap.error!);
            }

            final drafts = draftSnap.data ?? const [];
            final publishedList = pubSnap.data ?? const [];
            final publishedById = {
              for (final p in publishedList) p.article.articleId: p,
            };

            return SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AdminSectionCard(
                    title: 'Quản trị Kho Tri thức Tài chính (Draft -> Publish -> Active/Inactive)',
                    subtitle:
                        'Bài viết được tiêm tối đa ${FinancialKnowledgeArticle.kMaxInjectedSnippetsPerPrompt} snippet (<= ${FinancialKnowledgeArticle.kMaxSnippetLength} ký tự) vào AI Prompt theo triggerCondition. Tạm ngưng chỉ đặt isActive=false, luôn bảo toàn lịch sử.',
                    trailing: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (drafts.isEmpty)
                          OutlinedButton.icon(
                            key: const ValueKey('kb_seed_defaults_btn'),
                            onPressed: _isBusy ? null : _seedDefaultKnowledgeDrafts,
                            icon: const Icon(Icons.auto_fix_high_outlined, size: 17),
                            label: const Text('Nạp 3 bài mẫu vào Draft'),
                          ),
                        ElevatedButton.icon(
                          key: const ValueKey('kb_add_article_btn'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _isBusy
                              ? null
                              : () => _showArticleEditorDialog(existing: null),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Thêm bài viết Draft'),
                        ),
                      ],
                    ),
                    child: drafts.isEmpty && publishedList.isEmpty
                        ? const AdminEmptyStateCard(
                            icon: Icons.library_books_outlined,
                            title: 'Chưa có bài viết tri thức nào trong Kho',
                            subtitle:
                                'Hãy tạo bài viết mới hoặc nạp 3 nguyên tắc mẫu chuẩn để bắt đầu biên tập và xuất bản.',
                          )
                        : Column(
                            children: [
                              for (final rec in drafts) ...[
                                _KnowledgeArticleCard(
                                  draftRecord: rec,
                                  publishedRecord:
                                      publishedById[rec.article.articleId],
                                  topicLabel:
                                      _topicLabels[rec.article.topic] ??
                                          rec.article.topic,
                                  isBusy: _isBusy,
                                  onEditDraft: () => _showArticleEditorDialog(
                                    existing: rec.article,
                                  ),
                                  onPublish: () =>
                                      _publishKnowledgeArticle(rec.article),
                                  onToggleActive: () =>
                                      _toggleKnowledgeActive(
                                    rec.article,
                                    publishedById[rec.article.articleId],
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                              // Hiện cả những bài đang ở Published mà chưa có bản Draft riêng
                              for (final pub in publishedList)
                                if (!drafts.any(
                                  (d) =>
                                      d.article.articleId ==
                                      pub.article.articleId,
                                )) ...[
                                  _KnowledgePublishedOnlyCard(
                                    publishedRecord: pub,
                                    topicLabel:
                                        _topicLabels[pub.article.topic] ??
                                            pub.article.topic,
                                    isBusy: _isBusy,
                                    onCloneToDraft: () =>
                                        _clonePublishedKnowledgeToDraft(pub),
                                    onToggleActive: () =>
                                        _toggleKnowledgeActive(
                                      pub.article,
                                      pub,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                            ],
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _clonePublishedKnowledgeToDraft(
    AdminKnowledgePublishedRecord pub,
  ) async {
    setState(() => _isBusy = true);
    try {
      await widget.adminWebService.saveKnowledgeDraft(
        adminUid: widget.currentAdminUid,
        article: pub.article,
        tokenClaimsOverride: widget.tokenClaimsOverride,
      );
      if (!mounted) return;
      showAdminSnackBar(
        context,
        'Đã tạo bản Draft từ bài Published "${pub.article.title}".',
      );
    } catch (e) {
      if (!mounted) return;
      showAdminSnackBar(context, formatAdminErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _seedDefaultKnowledgeDrafts() async {
    setState(() => _isBusy = true);
    try {
      for (final art in FinancialKnowledgeArticle.defaultArticles()) {
        await widget.adminWebService.saveKnowledgeDraft(
          adminUid: widget.currentAdminUid,
          article: art,
          tokenClaimsOverride: widget.tokenClaimsOverride,
        );
      }
      if (!mounted) return;
      showAdminSnackBar(
        context,
        'Đã nạp 3 bài viết Tri thức Tài chính mặc định vào financial_knowledge_drafts.',
      );
    } catch (e) {
      if (!mounted) return;
      showAdminSnackBar(context, formatAdminErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _publishKnowledgeArticle(
    FinancialKnowledgeArticle article,
  ) async {
    final confirm = await showAdminConfirmDialog(
      context: context,
      title: 'Publish bài viết "${article.title}"?',
      message:
          'Bài viết sẽ được đẩy từ Draft sang financial_knowledge_published (tăng version +1) và có hiệu lực trong AI Grounding trên app User.',
      confirmLabel: 'Publish bài viết',
      confirmColor: AppColors.income,
      showNoteField: true,
      confirmButtonKey: ValueKey('kb_confirm_publish_${article.articleId}'),
    );
    if (confirm == null || !confirm.confirmed) return;

    setState(() => _isBusy = true);
    try {
      final res = await widget.adminWebService.publishKnowledgeArticle(
        adminUid: widget.currentAdminUid,
        articleId: article.articleId,
        action: 'publish',
        isActive: article.isActive,
        changeNote: confirm.note,
        tokenClaimsOverride: widget.tokenClaimsOverride,
      );
      if (!mounted) return;
      showAdminSnackBar(
        context,
        'Đã xuất bản bài viết "${article.title}" v${res['publishedVersion'] ?? ''}!',
      );
    } catch (e) {
      if (!mounted) return;
      showAdminSnackBar(context, formatAdminErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _toggleKnowledgeActive(
    FinancialKnowledgeArticle article,
    AdminKnowledgePublishedRecord? published,
  ) async {
    final currentActive = published?.article.isActive ?? article.isActive;
    final nextActive = !currentActive;

    final confirm = await showAdminConfirmDialog(
      context: context,
      title: nextActive
          ? 'Kích hoạt lại bài viết "${article.title}"?'
          : 'Tạm ngưng bài viết "${article.title}"?',
      message: nextActive
          ? 'Bài viết sẽ tiếp tục được tiêm vào AI Prompt khi thỏa mãn triggerCondition.'
          : 'Hệ thống sẽ đặt isActive = false qua Cloud Function (KHÔNG xóa bài viết, bảo toàn toàn bộ lịch sử phiên bản).',
      confirmLabel: nextActive ? 'Kích hoạt lại' : 'Tạm ngưng (Giữ lịch sử)',
      confirmColor: nextActive ? AppColors.income : AppColors.warning,
      showNoteField: true,
      confirmButtonKey: ValueKey('kb_confirm_toggle_${article.articleId}'),
    );
    if (confirm == null || !confirm.confirmed) return;

    setState(() => _isBusy = true);
    try {
      await widget.adminWebService.publishKnowledgeArticle(
        adminUid: widget.currentAdminUid,
        articleId: article.articleId,
        action: 'toggle_active',
        isActive: nextActive,
        changeNote: confirm.note,
        tokenClaimsOverride: widget.tokenClaimsOverride,
      );
      if (!mounted) return;
      showAdminSnackBar(
        context,
        nextActive
            ? 'Đã kích hoạt lại bài viết "${article.title}".'
            : 'Đã tạm ngưng hiển thị bài viết "${article.title}" (giữ nguyên lịch sử).',
      );
    } catch (e) {
      if (!mounted) return;
      showAdminSnackBar(context, formatAdminErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _showArticleEditorDialog({
    required FinancialKnowledgeArticle? existing,
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => _KnowledgeArticleDialog(
        existing: existing,
        adminWebService: widget.adminWebService,
        currentAdminUid: widget.currentAdminUid,
        tokenClaimsOverride: widget.tokenClaimsOverride,
      ),
    );

    if (saved == true && mounted) {
      showAdminSnackBar(context, 'Đã lưu bản nháp bài viết Tri thức Tài chính.');
    }
  }
}

class _ImpactSummaryTile extends StatelessWidget {
  final String title;
  final AdminSandboxSimulationResult result;
  final Color color;
  final Color bgColor;

  const _ImpactSummaryTile({
    required this.title,
    required this.result,
    required this.color,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    final vndFmt = NumberFormat.decimalPattern('vi_VN');
    return Container(
      width: 340,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Health Score: ${result.healthScore}/100 (${result.healthRating})',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
          Text(
            'Số vấn đề phát hiện: ${result.issues.length}',
            style: const TextStyle(fontSize: 12.5),
          ),
          Text(
            'Mục tiêu tiết kiệm gợi ý: ${vndFmt.format(result.monthlyPlan.targetSavingAmount.round())} đ (${result.monthlyPlan.dataTierUsed.name})',
            style: const TextStyle(fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

class _KnowledgeArticleCard extends StatelessWidget {
  final AdminKnowledgeDraftRecord draftRecord;
  final AdminKnowledgePublishedRecord? publishedRecord;
  final String topicLabel;
  final bool isBusy;
  final VoidCallback onEditDraft;
  final VoidCallback onPublish;
  final VoidCallback onToggleActive;

  const _KnowledgeArticleCard({
    required this.draftRecord,
    required this.publishedRecord,
    required this.topicLabel,
    required this.isBusy,
    required this.onEditDraft,
    required this.onPublish,
    required this.onToggleActive,
  });

  @override
  Widget build(BuildContext context) {
    final art = draftRecord.article;
    final pub = publishedRecord;
    final bool isPublishedActive = pub?.article.isActive ?? false;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.slate50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                art.title,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.slate800,
                ),
              ),
              AdminStatusBadge(
                label: 'P${art.priority}',
                color: AppColors.primary,
                backgroundColor: AppColors.infoBackground,
              ),
              AdminStatusBadge(
                label: topicLabel,
                color: AppColors.slate700,
                backgroundColor: Colors.white,
              ),
              AdminStatusBadge(
                label: 'Trigger: ${art.triggerCondition.code}',
                color: AppColors.info,
                backgroundColor: Colors.white,
              ),
              if (pub != null)
                AdminStatusBadge(
                  label:
                      'Published v${pub.publishedVersion} (${isPublishedActive ? "Đang bật" : "Đã tạm ngưng"})',
                  color: isPublishedActive ? AppColors.income : AppColors.warning,
                  backgroundColor: isPublishedActive
                      ? AppColors.incomeBackground
                      : AppColors.warningBackground,
                )
              else
                const AdminStatusBadge(
                  label: 'Chưa Publish (Chỉ có Draft)',
                  color: AppColors.warning,
                  backgroundColor: AppColors.warningBackground,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'ID: ${art.articleId}',
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.slate500,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tóm tắt User: ${art.summaryForUser}',
            style: const TextStyle(fontSize: 12.5, color: AppColors.slate700),
          ),
          const SizedBox(height: 4),
          Text(
            'AI Snippet: ${art.aiGroundingSnippet}',
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.slate800,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: ValueKey('kb_edit_${art.articleId}'),
                onPressed: isBusy ? null : onEditDraft,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Sửa Draft'),
              ),
              ElevatedButton.icon(
                key: ValueKey('kb_publish_${art.articleId}'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.income,
                  foregroundColor: Colors.white,
                ),
                onPressed: isBusy ? null : onPublish,
                icon: const Icon(Icons.publish_rounded, size: 16),
                label: const Text('Publish'),
              ),
              if (pub != null)
                OutlinedButton.icon(
                  key: ValueKey('kb_toggle_active_${art.articleId}'),
                  onPressed: isBusy ? null : onToggleActive,
                  icon: Icon(
                    isPublishedActive
                        ? Icons.pause_circle_outline
                        : Icons.play_circle_outline,
                    size: 16,
                  ),
                  label: Text(
                    isPublishedActive ? 'Tạm ngưng (Giữ lịch sử)' : 'Kích hoạt lại',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _KnowledgePublishedOnlyCard extends StatelessWidget {
  final AdminKnowledgePublishedRecord publishedRecord;
  final String topicLabel;
  final bool isBusy;
  final VoidCallback onCloneToDraft;
  final VoidCallback onToggleActive;

  const _KnowledgePublishedOnlyCard({
    required this.publishedRecord,
    required this.topicLabel,
    required this.isBusy,
    required this.onCloneToDraft,
    required this.onToggleActive,
  });

  @override
  Widget build(BuildContext context) {
    final art = publishedRecord.article;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.infoBackground.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              Text(
                art.title,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              AdminStatusBadge(
                label:
                    'Published v${publishedRecord.publishedVersion} (${art.isActive ? "Đang bật" : "Đã tạm ngưng"})',
                color: art.isActive ? AppColors.income : AppColors.warning,
                backgroundColor: art.isActive
                    ? AppColors.incomeBackground
                    : AppColors.warningBackground,
              ),
              AdminStatusBadge(
                label: topicLabel,
                color: AppColors.slate700,
                backgroundColor: Colors.white,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(art.aiGroundingSnippet, style: const TextStyle(fontSize: 12.5)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: isBusy ? null : onCloneToDraft,
                icon: const Icon(Icons.copy_all_outlined, size: 16),
                label: const Text('Nạp sang Draft để sửa'),
              ),
              OutlinedButton.icon(
                key: ValueKey('kb_toggle_active_${art.articleId}'),
                onPressed: isBusy ? null : onToggleActive,
                icon: Icon(
                  art.isActive
                      ? Icons.pause_circle_outline
                      : Icons.play_circle_outline,
                  size: 16,
                ),
                label: Text(art.isActive ? 'Tạm ngưng' : 'Kích hoạt lại'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _KnowledgeArticleDialog extends StatefulWidget {
  final FinancialKnowledgeArticle? existing;
  final AdminWebService adminWebService;
  final String currentAdminUid;
  final Map<String, dynamic>? tokenClaimsOverride;

  const _KnowledgeArticleDialog({
    required this.existing,
    required this.adminWebService,
    required this.currentAdminUid,
    this.tokenClaimsOverride,
  });

  @override
  State<_KnowledgeArticleDialog> createState() =>
      _KnowledgeArticleDialogState();
}

class _KnowledgeArticleDialogState extends State<_KnowledgeArticleDialog> {
  late final TextEditingController _idCtrl;
  late final TextEditingController _titleCtrl;
  late final TextEditingController _summaryCtrl;
  late final TextEditingController _snippetCtrl;
  late final TextEditingController _promptsCtrl;
  late String _topic;
  late KnowledgeTriggerCondition _trigger;
  late int _priority;
  late bool _isActive;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _idCtrl = TextEditingController(
      text: existing?.articleId ?? 'kb_custom_rule_1',
    );
    _titleCtrl = TextEditingController(text: existing?.title ?? '');
    _summaryCtrl = TextEditingController(text: existing?.summaryForUser ?? '');
    _snippetCtrl =
        TextEditingController(text: existing?.aiGroundingSnippet ?? '');
    _promptsCtrl = TextEditingController(
      text: (existing?.suggestedPrompts ?? const []).join('\n'),
    );
    _topic = existing?.topic ?? FinancialKnowledgeArticle.kAllowedTopics.first;
    _trigger = existing?.triggerCondition ?? KnowledgeTriggerCondition.always;
    _priority = existing?.priority ?? 7;
    _isActive = existing?.isActive ?? true;
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    _titleCtrl.dispose();
    _summaryCtrl.dispose();
    _snippetCtrl.dispose();
    _promptsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    final isNew = existing == null;
    final parsedPrompts = _promptsCtrl.text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final candidateMap = {
      'articleId': _idCtrl.text.trim(),
      'title': _titleCtrl.text.trim(),
      'topic': _topic,
      'triggerCondition': _trigger.code,
      'priority': _priority,
      'summaryForUser': _summaryCtrl.text.trim(),
      'aiGroundingSnippet': _snippetCtrl.text.trim(),
      'suggestedPrompts': parsedPrompts,
      'isActive': _isActive,
    };
    final errors = FinancialKnowledgeArticle.validateRawInput(candidateMap);

    return AlertDialog(
      title: Text(
        isNew
            ? 'Tạo bài viết Tri thức Tài chính mới (Draft)'
            : 'Chỉnh sửa Draft: ${existing.articleId}',
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const ValueKey('kb_dialog_id_input'),
                controller: _idCtrl,
                readOnly: !isNew,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Article ID (^[a-zA-Z0-9_-]{3,80}\$)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('kb_dialog_title_input'),
                controller: _titleCtrl,
                maxLength: 120,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Tiêu đề bài viết (3 – 120 ký tự)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _topic,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Chủ đề (topic)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      items: FinancialKnowledgeArticle.kAllowedTopics.map((t) {
                        return DropdownMenuItem<String>(
                          value: t,
                          child: Text(
                            _AdminRulesKnowledgeViewState._topicLabels[t] ?? t,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _topic = v);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 130,
                    child: DropdownButtonFormField<int>(
                      initialValue: _priority,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Ưu tiên (1-10)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      items: List.generate(
                        10,
                        (i) => DropdownMenuItem<int>(
                          value: i + 1,
                          child: Text('Mức ${i + 1}'),
                        ),
                      ),
                      onChanged: (v) {
                        if (v != null) setState(() => _priority = v);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<KnowledgeTriggerCondition>(
                initialValue: _trigger,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Điều kiện kích hoạt (triggerCondition)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                items: KnowledgeTriggerCondition.values.map((t) {
                  return DropdownMenuItem<KnowledgeTriggerCondition>(
                    value: t,
                    child: Text(
                      t.displayLabel,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _trigger = v);
                },
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('kb_dialog_summary_input'),
                controller: _summaryCtrl,
                maxLength: FinancialKnowledgeArticle.kMaxSummaryLength,
                maxLines: 3,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Tóm tắt cho người dùng (tối đa 250 ký tự)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('kb_dialog_snippet_input'),
                controller: _snippetCtrl,
                maxLength: FinancialKnowledgeArticle.kMaxSnippetLength,
                maxLines: 3,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'AI Grounding Snippet (tối đa 300 ký tự)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _promptsCtrl,
                maxLines: 3,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText:
                      'Câu hỏi gợi ý (tối đa 3 dòng, mỗi dòng <= 120 ký tự)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Bật hoạt động (isActive)'),
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
              ),
              if (errors.isNotEmpty) ...[
                const SizedBox(height: 8),
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
                      for (final err in errors)
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
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Hủy'),
        ),
        ElevatedButton(
          key: const ValueKey('kb_dialog_save_draft_btn'),
          onPressed: (_saving || errors.isNotEmpty)
              ? null
              : () async {
                  setState(() => _saving = true);
                  final article = FinancialKnowledgeArticle(
                    articleId: _idCtrl.text.trim(),
                    title: _titleCtrl.text.trim(),
                    topic: _topic,
                    triggerCondition: _trigger,
                    priority: _priority,
                    summaryForUser: _summaryCtrl.text.trim(),
                    aiGroundingSnippet: _snippetCtrl.text.trim(),
                    suggestedPrompts: parsedPrompts.take(3).toList(),
                    isActive: _isActive,
                  );
                  try {
                    await widget.adminWebService.saveKnowledgeDraft(
                      adminUid: widget.currentAdminUid,
                      article: article,
                      tokenClaimsOverride: widget.tokenClaimsOverride,
                    );
                    if (context.mounted) Navigator.of(context).pop(true);
                  } catch (e) {
                    if (!context.mounted) return;
                    showAdminSnackBar(
                      context,
                      formatAdminErrorMessage(e),
                      isError: true,
                    );
                  } finally {
                    if (mounted) setState(() => _saving = false);
                  }
                },
          child: const Text('Lưu Draft'),
        ),
      ],
    );
  }
}

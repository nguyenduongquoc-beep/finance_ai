import 'package:flutter/material.dart';
import '../../models/ai_runtime_config_model.dart';
import '../../services/ai_config_sync_service.dart';
import '../../utils/constants.dart';
import '../services/admin_ai_sandbox_service.dart';
import '../services/admin_web_service.dart';
import '../widgets/admin_governance_widgets.dart';

/// Khu vực 2: AI Studio & Sandbox (`ai_runtime`)
/// - Quản lý Draft / Published của Model Chain, Temperature, History & Prompts.
/// - Tích hợp Deterministic Sandbox (3 Synthetic Personas) & Live Gemini Sandbox (Backend).
/// - Quy trình bắt buộc: Lưu Draft -> Xác minh HMAC Sandbox -> Publish / Rollback.
class AdminAiStudioView extends StatefulWidget {
  final AdminWebService adminWebService;
  final String currentAdminUid;
  final String currentAdminEmail;
  final AdminAiSandboxService sandboxService;
  final Map<String, dynamic>? tokenClaimsOverride;

  const AdminAiStudioView({
    super.key,
    required this.adminWebService,
    required this.currentAdminUid,
    required this.currentAdminEmail,
    this.sandboxService = const AdminAiSandboxService(),
    this.tokenClaimsOverride,
  });

  @override
  State<AdminAiStudioView> createState() => _AdminAiStudioViewState();
}

class _AdminAiStudioViewState extends State<AdminAiStudioView> {
  final _chatInstCtrl = TextEditingController();
  final _planRuleCtrl = TextEditingController();
  final _anomalyRuleCtrl = TextEditingController();
  final _goalRuleCtrl = TextEditingController();
  final _ocrHintsCtrl = TextEditingController();
  final _liveQuestionCtrl = TextEditingController(
    text: 'Tháng này tôi nên cắt giảm khoản nào để đạt mục tiêu tiết kiệm?',
  );
  final _customPromptTextCtrl = TextEditingController();

  bool _formInitialized = false;
  bool _isEnabled = true;
  String _primaryModel = AiRuntimeConfig.kDefaultPrimaryModel;
  List<String> _fallbackModels = List<String>.from(
    AiRuntimeConfig.kDefaultFallbackModels,
  );
  double _temperature = 0.35;
  int _maxChatHistory = 10;
  Map<String, List<String>> _suggestedPrompts = {};
  String _selectedPromptGroupKey = 'general';

  // Sandbox state
  final List<SyntheticPersona> _personas = SyntheticPersona.builtInPersonas();
  late String _selectedPersonaId;
  bool _useDraftKnowledgeInSandbox = true;
  int _sandboxTabIndex = 0; // 0 = Deterministic, 1 = Live Gemini
  AdminSandboxSimulationResult? _lastSimulation;
  bool _liveExpectStructuredJson = false;
  bool _liveIncludeSystemInstruction = true;
  bool _isRunningLiveSandbox = false;
  AdminSandboxRunResult? _lastLiveResult;
  Object? _lastLiveError;

  bool _isBusy = false;

  static const Map<String, String> _promptGroupLabels = {
    'general': 'Mặc định / Chung',
    'over_budget': 'Khi vượt ngân sách',
    'low_saving': 'Khi tiết kiệm thấp',
    'no_data': 'Người dùng mới / Ít dữ liệu',
  };

  @override
  void initState() {
    super.initState();
    _selectedPersonaId = _personas.first.id;
    _applyConfigToForm(AiRuntimeConfig.defaults());
  }

  @override
  void dispose() {
    _chatInstCtrl.dispose();
    _planRuleCtrl.dispose();
    _anomalyRuleCtrl.dispose();
    _goalRuleCtrl.dispose();
    _ocrHintsCtrl.dispose();
    _liveQuestionCtrl.dispose();
    _customPromptTextCtrl.dispose();
    super.dispose();
  }

  void _applyConfigToForm(AiRuntimeConfig config) {
    _isEnabled = config.isEnabled;
    _primaryModel = config.primaryModel;
    _fallbackModels = List<String>.from(config.fallbackModels);
    _temperature = config.temperature;
    _maxChatHistory = config.maxChatHistoryMessages;
    _chatInstCtrl.text = config.chatSystemInstruction;
    _planRuleCtrl.text = config.monthlyPlanAdvisoryRule;
    _anomalyRuleCtrl.text = config.anomalyAdvisoryRule;
    _goalRuleCtrl.text = config.savingGoalAdvisoryRule;
    _ocrHintsCtrl.text = config.ocrExtraHints;
    _suggestedPrompts = {
      for (final entry in config.customSuggestedChatPrompts.entries)
        entry.key: List<String>.from(entry.value),
    };
  }

  AiRuntimeConfig _buildCurrentLocalConfig({int version = 1}) {
    return AiRuntimeConfig(
      version: version,
      isEnabled: _isEnabled,
      primaryModel: _primaryModel,
      fallbackModels: List<String>.from(_fallbackModels),
      temperature: double.parse(_temperature.toStringAsFixed(2)),
      maxChatHistoryMessages: _maxChatHistory,
      chatSystemInstruction: _chatInstCtrl.text,
      monthlyPlanAdvisoryRule: _planRuleCtrl.text,
      anomalyAdvisoryRule: _anomalyRuleCtrl.text,
      savingGoalAdvisoryRule: _goalRuleCtrl.text,
      ocrExtraHints: _ocrHintsCtrl.text,
      customSuggestedChatPrompts: _suggestedPrompts,
    );
  }

  Map<String, dynamic> _buildCurrentLocalRawPayload() {
    return {
      'isEnabled': _isEnabled,
      'primaryModel': _primaryModel,
      'fallbackModels': List<String>.from(_fallbackModels),
      'temperature': double.parse(_temperature.toStringAsFixed(2)),
      'maxChatHistoryMessages': _maxChatHistory,
      'prompts': {
        'chatSystemInstruction': _chatInstCtrl.text.trim(),
        'monthlyPlanAdvisoryRule': _planRuleCtrl.text.trim(),
        'anomalyAdvisoryRule': _anomalyRuleCtrl.text.trim(),
        'savingGoalAdvisoryRule': _goalRuleCtrl.text.trim(),
        'ocrExtraHints': _ocrHintsCtrl.text.trim(),
      },
      'customSuggestedChatPrompts': _suggestedPrompts,
    };
  }

  SyntheticPersona get _activePersona => _personas.firstWhere(
        (p) => p.id == _selectedPersonaId,
        orElse: () => _personas.first,
      );

  Future<void> _saveDraft() async {
    final payload = _buildCurrentLocalRawPayload();
    final errors = AiRuntimeConfig.validateRawInput(payload);
    if (errors.isNotEmpty) {
      showAdminSnackBar(context, errors.first, isError: true);
      return;
    }

    setState(() => _isBusy = true);
    try {
      await widget.adminWebService.saveConfigDraft(
        adminUid: widget.currentAdminUid,
        configType: AiConfigSyncService.kDocAiRuntime,
        payload: payload,
        tokenClaimsOverride: widget.tokenClaimsOverride,
      );
      if (!mounted) return;
      showAdminSnackBar(
        context,
        'Đã lưu bản nháp AI Runtime. Hãy chạy Sandbox và ký xác minh HMAC trước khi Publish.',
      );
    } catch (e) {
      if (!mounted) return;
      showAdminSnackBar(context, formatAdminErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _verifyDraftInSandbox() async {
    setState(() => _isBusy = true);
    try {
      final summary = _lastSimulation?.toVerificationSummary();
      await widget.adminWebService.verifyDraftInSandbox(
        adminUid: widget.currentAdminUid,
        configType: AiConfigSyncService.kDocAiRuntime,
        simulationSummary: summary,
        tokenClaimsOverride: widget.tokenClaimsOverride,
      );
      if (!mounted) return;
      showAdminSnackBar(
        context,
        'Đã ký xác minh HMAC Sandbox thành công! Draft hiện sẵn sàng Publish.',
      );
    } catch (e) {
      if (!mounted) return;
      showAdminSnackBar(context, formatAdminErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _publishConfig() async {
    final confirm = await showAdminConfirmDialog(
      context: context,
      title: 'Publish cấu hình AI Runtime lên Production?',
      message:
          'Cấu hình Model, Temperature và System Instructions đã xác minh sẽ có hiệu lực với toàn bộ người dùng Flutter App sau chu kỳ đồng bộ tiếp theo.',
      confirmLabel: 'Publish ngay',
      confirmColor: AppColors.income,
      showNoteField: true,
      noteLabel: 'Ghi chú thay đổi (Change Note)',
      confirmButtonKey: const ValueKey('ai_studio_confirm_publish_btn'),
      noteFieldKey: const ValueKey('ai_studio_publish_note_input'),
    );
    if (confirm == null || !confirm.confirmed) return;

    setState(() => _isBusy = true);
    try {
      final res = await widget.adminWebService.publishConfig(
        adminUid: widget.currentAdminUid,
        configType: AiConfigSyncService.kDocAiRuntime,
        changeNote: confirm.note,
        tokenClaimsOverride: widget.tokenClaimsOverride,
      );
      if (!mounted) return;
      final nextVer = res['version'] ?? '';
      showAdminSnackBar(
        context,
        'Đã Publish AI Runtime v$nextVer lên Production!',
      );
    } catch (e) {
      if (!mounted) return;
      showAdminSnackBar(context, formatAdminErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _rollbackVersion(ConfigVersionSnapshot target) async {
    final confirm = await showAdminConfirmDialog(
      context: context,
      title: 'Rollback AI Runtime về phiên bản v${target.versionNumber}?',
      message:
          'Hệ thống sẽ tạo một phiên bản mới từ bản chụp v${target.versionNumber} (không ghi đè lịch sử cũ) và đưa vào Production ngay.',
      confirmLabel: 'Xác nhận Rollback',
      confirmColor: AppColors.warning,
      showNoteField: true,
      noteRequired: true,
      noteLabel: 'Lý do Rollback (bắt buộc)',
      confirmButtonKey: const ValueKey('ai_studio_confirm_rollback_btn'),
      noteFieldKey: const ValueKey('ai_studio_rollback_reason_input'),
    );
    if (confirm == null || !confirm.confirmed) return;

    setState(() => _isBusy = true);
    try {
      final res = await widget.adminWebService.rollbackConfig(
        adminUid: widget.currentAdminUid,
        configType: AiConfigSyncService.kDocAiRuntime,
        targetVersionNumber: target.versionNumber,
        reason: confirm.note,
        tokenClaimsOverride: widget.tokenClaimsOverride,
      );
      if (!mounted) return;
      _applyConfigToForm(AiRuntimeConfig.fromMap(target.payloadSnapshot));
      final newVer = res['version'] ?? '';
      showAdminSnackBar(
        context,
        'Đã khôi phục cấu hình từ v${target.versionNumber} thành phiên bản mới v$newVer!',
      );
    } catch (e) {
      if (!mounted) return;
      showAdminSnackBar(context, formatAdminErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _runDeterministicSimulation({
    required FinancialHeuristicsConfig heuristics,
    required TransactionIntelligenceConfig txRules,
    required List<FinancialKnowledgeArticle> knowledgeArticles,
  }) {
    final config = _buildCurrentLocalConfig();
    final sim = widget.sandboxService.simulatePersona(
      persona: _activePersona,
      runtimeConfig: config,
      heuristicsConfig: heuristics,
      transactionRules: txRules,
      knowledgeArticles: knowledgeArticles,
    );
    setState(() {
      _lastSimulation = sim;
    });
  }

  Future<void> _runLiveGeminiSandbox({
    required FinancialHeuristicsConfig heuristics,
    required TransactionIntelligenceConfig txRules,
    required List<FinancialKnowledgeArticle> knowledgeArticles,
  }) async {
    final config = _buildCurrentLocalConfig();
    final errors = AiRuntimeConfig.validateRawInput(_buildCurrentLocalRawPayload());
    if (errors.isNotEmpty) {
      showAdminSnackBar(context, errors.first, isError: true);
      return;
    }

    // Đảm bảo có simulation hiện tại cho Persona đang chọn
    final sim = widget.sandboxService.simulatePersona(
      persona: _activePersona,
      runtimeConfig: config,
      heuristicsConfig: heuristics,
      transactionRules: txRules,
      knowledgeArticles: knowledgeArticles,
    );

    final String promptToSend;
    final String? sysInstToSend;
    if (_liveExpectStructuredJson) {
      promptToSend = sim.structuredPlanPromptPreview;
      sysInstToSend = null;
    } else {
      final q = _liveQuestionCtrl.text.trim();
      if (q.isEmpty) {
        showAdminSnackBar(
          context,
          'Vui lòng nhập câu hỏi thử nghiệm cho Gemini Chatbot.',
          isError: true,
        );
        return;
      }
      promptToSend = q;
      sysInstToSend =
          _liveIncludeSystemInstruction ? sim.systemPromptPreview : null;
    }

    setState(() {
      _lastSimulation = sim;
      _isRunningLiveSandbox = true;
      _lastLiveError = null;
    });

    try {
      final res = await widget.adminWebService.runLiveGeminiSandbox(
        adminUid: widget.currentAdminUid,
        mode: _liveExpectStructuredJson ? 'structured_plan_json' : 'chat_prompt',
        prompt: promptToSend,
        systemInstruction: sysInstToSend,
        primaryModel: config.primaryModel,
        fallbackModels: config.fallbackModels,
        temperature: config.temperature,
        expectStructuredPlanJson: _liveExpectStructuredJson,
        persona: _activePersona,
        tokenClaimsOverride: widget.tokenClaimsOverride,
      );
      if (!mounted) return;
      setState(() {
        _lastLiveResult = res;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _lastLiveError = e;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRunningLiveSandbox = false;
        });
      }
    }
  }

  void _addSuggestedPrompt() {
    final text = _customPromptTextCtrl.text.trim();
    if (text.isEmpty || text.length > 120) {
      showAdminSnackBar(
        context,
        'Câu gợi ý phải dài từ 1 đến 120 ký tự.',
        isError: true,
      );
      return;
    }
    final list = List<String>.from(
      _suggestedPrompts[_selectedPromptGroupKey] ?? const [],
    );
    if (list.length >= 6) {
      showAdminSnackBar(
        context,
        'Mỗi nhóm chỉ được chứa tối đa 6 câu gợi ý.',
        isError: true,
      );
      return;
    }
    if (!list.contains(text)) {
      list.add(text);
    }
    setState(() {
      _suggestedPrompts[_selectedPromptGroupKey] = list;
      _customPromptTextCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: widget.adminWebService.streamPublishedConfigMap(
        AiConfigSyncService.kDocAiRuntime,
      ),
      builder: (context, pubSnap) {
        return StreamBuilder<DraftConfigEnvelope?>(
          stream: widget.adminWebService.streamDraftConfigEnvelope(
            AiConfigSyncService.kDocAiRuntime,
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
                message: 'Đang tải cấu hình AI Runtime & Sandbox...',
              );
            }

            if (draftSnap.hasError) {
              return AdminErrorStateCard(error: draftSnap.error!);
            }
            if (pubSnap.hasError) {
              return AdminErrorStateCard(error: pubSnap.error!);
            }

            final pubMap = pubSnap.data;
            final publishedConfig = AiRuntimeConfig.fromMap(pubMap);
            final publishedVersion =
                pubMap != null ? (pubMap['version'] as num?)?.toInt() ?? 1 : null;
            final publishedAt = pubMap?['updatedAt'] != null
                ? DateTime.tryParse(pubMap!['updatedAt'].toString())
                : null;
            final publishedByEmail = pubMap?['updatedByEmail'] as String?;

            final draftEnvelope = draftSnap.data;
            if (!_formInitialized) {
              if (draftEnvelope != null) {
                _applyConfigToForm(
                  AiRuntimeConfig.fromMap(draftEnvelope.draftPayload),
                );
              } else {
                _applyConfigToForm(publishedConfig);
              }
              _formInitialized = true;
            }

            final localPayload = _buildCurrentLocalRawPayload();
            final localHash = computeCanonicalConfigHash(localPayload);
            final localErrors = AiRuntimeConfig.validateRawInput(localPayload);
            final bool hasUnsavedChanges = draftEnvelope == null
                ? true
                : localHash != draftEnvelope.draftHash;

            return _buildStudioBody(
              context: context,
              publishedConfig: publishedConfig,
              publishedVersion: publishedVersion,
              publishedAt: publishedAt,
              publishedByEmail: publishedByEmail,
              draftEnvelope: draftEnvelope,
              localHash: localHash,
              localErrors: localErrors,
              hasUnsavedChanges: hasUnsavedChanges,
            );
          },
        );
      },
    );
  }

  Widget _buildStudioBody({
    required BuildContext context,
    required AiRuntimeConfig publishedConfig,
    required int? publishedVersion,
    required DateTime? publishedAt,
    required String? publishedByEmail,
    required DraftConfigEnvelope? draftEnvelope,
    required String localHash,
    required List<String> localErrors,
    required bool hasUnsavedChanges,
  }) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: widget.adminWebService.streamPublishedConfigMap(
        AiConfigSyncService.kDocFinancialHeuristics,
      ),
      builder: (context, heurSnap) {
        return StreamBuilder<Map<String, dynamic>?>(
          stream: widget.adminWebService.streamPublishedConfigMap(
            AiConfigSyncService.kDocTransactionRules,
          ),
          builder: (context, rulesSnap) {
            return StreamBuilder<List<AdminKnowledgeDraftRecord>>(
              stream: widget.adminWebService.streamKnowledgeDrafts(),
              builder: (context, kbDraftSnap) {
                return StreamBuilder<List<AdminKnowledgePublishedRecord>>(
                  stream: widget.adminWebService.streamKnowledgePublished(),
                  builder: (context, kbPubSnap) {
                    final heuristics =
                        FinancialHeuristicsConfig.fromMap(heurSnap.data);
                    final txRules =
                        TransactionIntelligenceConfig.fromMap(rulesSnap.data);
                    final kbArticles = _useDraftKnowledgeInSandbox
                        ? (kbDraftSnap.data ?? const [])
                            .map((e) => e.article)
                            .toList()
                        : (kbPubSnap.data ?? const [])
                            .map((e) => e.article)
                            .toList();

                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AdminDraftPublishBar(
                            configTitle: 'AI Runtime & Model Chain (ai_runtime)',
                            publishedVersion: publishedVersion,
                            publishedAt: publishedAt,
                            publishedByEmail: publishedByEmail,
                            draftEnvelope: draftEnvelope,
                            localPayloadHash: localHash,
                            hasUnsavedLocalChanges: hasUnsavedChanges,
                            localValidationErrors: localErrors,
                            isBusy: _isBusy,
                            onSaveDraft: _saveDraft,
                            onVerifySandbox: _verifyDraftInSandbox,
                            onPublish: _publishConfig,
                            onResetToPublished: () {
                              setState(() {
                                _applyConfigToForm(publishedConfig);
                              });
                              showAdminSnackBar(
                                context,
                                'Đã nạp cấu hình đang chạy trên Production vào trình chỉnh sửa.',
                              );
                            },
                            onResetToDefaults: () {
                              setState(() {
                                _applyConfigToForm(AiRuntimeConfig.defaults());
                              });
                              showAdminSnackBar(
                                context,
                                'Đã khôi phục thông số mặc định trong trình chỉnh sửa (chưa lưu Draft).',
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final isWide = constraints.maxWidth >= 1060;
                              final editorWidget = _buildEditorColumn(context);
                              final sandboxWidget = _buildSandboxColumn(
                                context: context,
                                heuristics: heuristics,
                                txRules: txRules,
                                kbArticles: kbArticles,
                              );

                              if (isWide) {
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(flex: 11, child: editorWidget),
                                    const SizedBox(width: 16),
                                    Expanded(flex: 10, child: sandboxWidget),
                                  ],
                                );
                              }
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  editorWidget,
                                  const SizedBox(height: 16),
                                  sandboxWidget,
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          AdminVersionHistoryCard(
                            configType: AiConfigSyncService.kDocAiRuntime,
                            currentPublishedVersion: publishedVersion,
                            adminWebService: widget.adminWebService,
                            isBusy: _isBusy,
                            onRollbackRequested: _rollbackVersion,
                            onLoadSnapshotIntoDraft: (ver) {
                              setState(() {
                                _applyConfigToForm(
                                  AiRuntimeConfig.fromMap(ver.payloadSnapshot),
                                );
                              });
                              showAdminSnackBar(
                                context,
                                'Đã nạp bản chụp v${ver.versionNumber} vào trình chỉnh sửa (chưa lưu Draft).',
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
          },
        );
      },
    );
  }

  Widget _buildEditorColumn(BuildContext context) {
    final primaryCandidates = kSupportedGeminiModels
        .where((m) => !m.isMutableAlias)
        .toList();
    final selectedPrimaryDesc = findGeminiModelDescriptor(_primaryModel);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminSectionCard(
          title: 'Cấu hình Model & Tham số Suy luận',
          subtitle:
              'Whitelist đối chiếu theo tài liệu Gemini Developer API; không lưu API Key ở cấu hình.',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Bật AI',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 6),
              Switch(
                key: const ValueKey('ai_studio_enabled_switch'),
                value: _isEnabled,
                onChanged: (v) => setState(() => _isEnabled = v),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                key: const ValueKey('ai_studio_primary_model_dropdown'),
                initialValue: primaryCandidates.any((m) => m.modelId == _primaryModel)
                    ? _primaryModel
                    : AiRuntimeConfig.kDefaultPrimaryModel,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Model chính (Primary Model)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                items: primaryCandidates.map((m) {
                  return DropdownMenuItem<String>(
                    value: m.modelId,
                    child: Text(
                      '${m.displayName} (${m.modelId}) — ${m.roleBadge}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val == null) return;
                  setState(() {
                    _primaryModel = val;
                    _fallbackModels.remove(val);
                  });
                },
              ),
              if (selectedPrimaryDesc != null) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    AdminStatusBadge(
                      label: 'Kênh: ${selectedPrimaryDesc.releaseChannel.name.toUpperCase()}',
                      color: selectedPrimaryDesc.isStable
                          ? AppColors.income
                          : AppColors.warning,
                      backgroundColor: selectedPrimaryDesc.isStable
                          ? AppColors.incomeBackground
                          : AppColors.warningBackground,
                    ),
                    Text(
                      selectedPrimaryDesc.description,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.slate600,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'Chuỗi Model Dự phòng (Fallback Chain theo thứ tự ưu tiên)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.slate700,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in kSupportedGeminiModels)
                    if (m.modelId != _primaryModel)
                      FilterChip(
                        label: Text(
                          m.isMutableAlias
                              ? '${m.modelId} (Alias)'
                              : '${m.modelId} (${m.releaseChannel.name})',
                          style: const TextStyle(fontSize: 12),
                        ),
                        selected: _fallbackModels.contains(m.modelId),
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              if (!_fallbackModels.contains(m.modelId)) {
                                _fallbackModels.add(m.modelId);
                              }
                            } else {
                              _fallbackModels.remove(m.modelId);
                            }
                          });
                        },
                      ),
                ],
              ),
              if (_fallbackModels.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.slate50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.slate200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Thứ tự gọi thực tế:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.slate600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (int i = 0; i < _fallbackModels.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '#${i + 1}: ${_fallbackModels[i]}',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: 'Đưa lên trên',
                                onPressed: i == 0
                                    ? null
                                    : () {
                                        setState(() {
                                          final item =
                                              _fallbackModels.removeAt(i);
                                          _fallbackModels.insert(i - 1, item);
                                        });
                                      },
                                icon: const Icon(Icons.arrow_upward, size: 16),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: 'Đưa xuống dưới',
                                onPressed: i == _fallbackModels.length - 1
                                    ? null
                                    : () {
                                        setState(() {
                                          final item =
                                              _fallbackModels.removeAt(i);
                                          _fallbackModels.insert(i + 1, item);
                                        });
                                      },
                                icon:
                                    const Icon(Icons.arrow_downward, size: 16),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Temperature: ${_temperature.toStringAsFixed(2)} (0.10 – 0.80)',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Slider(
                          key: const ValueKey('ai_studio_temperature_slider'),
                          value: _temperature.clamp(
                            AiRuntimeConfig.kMinTemperature,
                            AiRuntimeConfig.kMaxTemperature,
                          ),
                          min: AiRuntimeConfig.kMinTemperature,
                          max: AiRuntimeConfig.kMaxTemperature,
                          divisions: 14,
                          label: _temperature.toStringAsFixed(2),
                          onChanged: (v) {
                            setState(() {
                              _temperature =
                                  double.parse(v.toStringAsFixed(2));
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ngữ cảnh lịch sử chat: $_maxChatHistory tin nhắn (4 – 20)',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Slider(
                          key: const ValueKey('ai_studio_max_history_slider'),
                          value: _maxChatHistory.toDouble().clamp(
                                AiRuntimeConfig.kMinChatHistory.toDouble(),
                                AiRuntimeConfig.kMaxChatHistory.toDouble(),
                              ),
                          min: AiRuntimeConfig.kMinChatHistory.toDouble(),
                          max: AiRuntimeConfig.kMaxChatHistory.toDouble(),
                          divisions: 16,
                          label: '$_maxChatHistory',
                          onChanged: (v) {
                            setState(() {
                              _maxChatHistory = v.round();
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AdminSectionCard(
          title: 'System Instructions & Prompt Rules',
          subtitle:
              'Hệ thống vẫn giữ nguyên ràng buộc số liệu & từ chối ngoài phạm vi ở tầng Code khi tiêm vào AI.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPromptField(
                fieldKey: const ValueKey('ai_studio_chat_instruction_input'),
                controller: _chatInstCtrl,
                label: 'Chat System Instruction (Trợ lý CFP)',
                maxLength: AiRuntimeConfig.kMaxInstructionChars,
                maxLines: 6,
              ),
              const SizedBox(height: 12),
              _buildPromptField(
                fieldKey: const ValueKey('ai_studio_plan_rule_input'),
                controller: _planRuleCtrl,
                label: 'Monthly Plan Advisory Rule (Lập kế hoạch tháng)',
                maxLength: 1500,
                maxLines: 4,
              ),
              const SizedBox(height: 12),
              _buildPromptField(
                fieldKey: const ValueKey('ai_studio_anomaly_rule_input'),
                controller: _anomalyRuleCtrl,
                label: 'Anomaly Advisory Rule (Giải thích giao dịch bất thường)',
                maxLength: 600,
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              _buildPromptField(
                fieldKey: const ValueKey('ai_studio_goal_rule_input'),
                controller: _goalRuleCtrl,
                label: 'Saving Goal Advisory Rule (Lộ trình mục tiêu tiết kiệm)',
                maxLength: 800,
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              _buildPromptField(
                fieldKey: const ValueKey('ai_studio_ocr_hints_input'),
                controller: _ocrHintsCtrl,
                label: 'OCR Extra Hints (Gợi ý nhận diện hóa đơn)',
                maxLength: 800,
                maxLines: 3,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AdminSectionCard(
          title: 'Câu hỏi gợi ý cho Chat User (Suggested Chat Prompts)',
          subtitle: 'Tùy chỉnh danh sách câu hỏi nhanh hiển thị theo ngữ cảnh người dùng.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: _promptGroupLabels.entries.map((entry) {
                  final selected = _selectedPromptGroupKey == entry.key;
                  return ChoiceChip(
                    label: Text(entry.value),
                    selected: selected,
                    onSelected: (_) {
                      setState(() => _selectedPromptGroupKey = entry.key);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _customPromptTextCtrl,
                      decoration: InputDecoration(
                        labelText:
                            'Thêm câu gợi ý (${_promptGroupLabels[_selectedPromptGroupKey]})',
                        hintText: 'VD: Tuần này tôi nên giới hạn ăn uống bao nhiêu?',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onSubmitted: (_) => _addSuggestedPrompt(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _addSuggestedPrompt,
                    icon: const Icon(Icons.add, size: 17),
                    label: const Text('Thêm'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if ((_suggestedPrompts[_selectedPromptGroupKey] ?? const [])
                  .isEmpty)
                const Text(
                  'Nhóm này chưa có câu gợi ý tùy chỉnh (User app sẽ dùng mặc định hệ thống).',
                  style: TextStyle(fontSize: 12, color: AppColors.slate500),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final item in (_suggestedPrompts[_selectedPromptGroupKey] ??
                        const <String>[]))
                      InputChip(
                        label: Text(item),
                        onDeleted: () {
                          setState(() {
                            final next = List<String>.from(
                              _suggestedPrompts[_selectedPromptGroupKey] ??
                                  const [],
                            )..remove(item);
                            if (next.isEmpty) {
                              _suggestedPrompts.remove(_selectedPromptGroupKey);
                            } else {
                              _suggestedPrompts[_selectedPromptGroupKey] = next;
                            }
                          });
                        },
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPromptField({
    required Key fieldKey,
    required TextEditingController controller,
    required String label,
    required int maxLength,
    required int maxLines,
  }) {
    return TextField(
      key: fieldKey,
      controller: controller,
      maxLength: maxLength,
      maxLines: maxLines,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: label,
        alignLabelWithHint: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildSandboxColumn({
    required BuildContext context,
    required FinancialHeuristicsConfig heuristics,
    required TransactionIntelligenceConfig txRules,
    required List<FinancialKnowledgeArticle> kbArticles,
  }) {
    final persona = _activePersona;
    return AdminSectionCard(
      title: 'AI Sandbox (100% Synthetic Persona)',
      subtitle:
          'Cô lập hoàn toàn khỏi dữ liệu tài chính thật của User. Kiểm thử Prompt & Model trước khi Publish.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            key: const ValueKey('ai_studio_persona_dropdown'),
            initialValue: persona.id,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Chọn Synthetic Persona',
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
            onChanged: (val) {
              if (val == null) return;
              setState(() {
                _selectedPersonaId = val;
              });
            },
          ),
          const SizedBox(height: 6),
          Text(
            persona.subtitle,
            style: const TextStyle(fontSize: 12, color: AppColors.slate600),
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text(
              'Nạp Kho Tri thức từ bản Draft (thay vì Published)',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            value: _useDraftKnowledgeInSandbox,
            onChanged: (v) {
              setState(() => _useDraftKnowledgeInSandbox = v);
            },
          ),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment<int>(
                value: 0,
                icon: Icon(Icons.calculate_outlined, size: 16),
                label: Text('Deterministic Sandbox'),
              ),
              ButtonSegment<int>(
                value: 1,
                icon: Icon(Icons.auto_awesome_outlined, size: 16),
                label: Text('Live Gemini Sandbox'),
              ),
            ],
            selected: {_sandboxTabIndex},
            onSelectionChanged: (s) {
              setState(() => _sandboxTabIndex = s.first);
            },
          ),
          const SizedBox(height: 14),
          if (_sandboxTabIndex == 0)
            _buildDeterministicSandboxPanel(
              heuristics: heuristics,
              txRules: txRules,
              kbArticles: kbArticles,
            )
          else
            _buildLiveGeminiSandboxPanel(
              heuristics: heuristics,
              txRules: txRules,
              kbArticles: kbArticles,
            ),
        ],
      ),
    );
  }

  Widget _buildDeterministicSandboxPanel({
    required FinancialHeuristicsConfig heuristics,
    required TransactionIntelligenceConfig txRules,
    required List<FinancialKnowledgeArticle> kbArticles,
  }) {
    final sim = _lastSimulation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            key: const ValueKey('ai_studio_run_deterministic_btn'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
            onPressed: () => _runDeterministicSimulation(
              heuristics: heuristics,
              txRules: txRules,
              knowledgeArticles: kbArticles,
            ),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Chạy mô phỏng & Render System Prompt'),
          ),
        ),
        const SizedBox(height: 14),
        if (sim == null)
          const AdminEmptyStateCard(
            icon: Icons.science_outlined,
            title: 'Chưa có kết quả mô phỏng',
            subtitle:
                'Nhấn nút bên trên để chạy Financial Analytics + AI Prompt Builder trên Persona giả lập.',
          )
        else ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.infoBackground,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Persona: ${sim.personaTitle}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.slate800,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    AdminStatusBadge(
                      label: 'Health Score: ${sim.healthScore}/100 (${sim.healthRating})',
                      color: AppColors.primary,
                      backgroundColor: Colors.white,
                    ),
                    AdminStatusBadge(
                      label: 'Data Tier: ${sim.monthlyPlan.dataTierUsed.name}',
                      color: AppColors.slate700,
                      backgroundColor: Colors.white,
                    ),
                    AdminStatusBadge(
                      label: 'Vấn đề phát hiện: ${sim.issues.length}',
                      color: sim.issues.isEmpty
                          ? AppColors.income
                          : AppColors.warning,
                      backgroundColor: Colors.white,
                    ),
                  ],
                ),
                if (sim.issues.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final issue in sim.issues)
                    Text(
                      '• [${issue.severity.name.toUpperCase()}] ${issue.title}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.slate700,
                      ),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Rendered System Prompt Preview:',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 240),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.slate50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.slate200),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                sim.systemPromptPreview,
                key: const ValueKey('ai_studio_system_prompt_preview'),
                style: const TextStyle(
                  fontSize: 11.5,
                  fontFamily: 'monospace',
                  color: AppColors.slate800,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Rendered Structured Plan Prompt Preview:',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 180),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.slate50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.slate200),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                sim.structuredPlanPromptPreview,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontFamily: 'monospace',
                  color: AppColors.slate800,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLiveGeminiSandboxPanel({
    required FinancialHeuristicsConfig heuristics,
    required TransactionIntelligenceConfig txRules,
    required List<FinancialKnowledgeArticle> kbArticles,
  }) {
    final res = _lastLiveResult;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.infoBackground,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text(
            'Live Sandbox gọi Cloud Function adminRunSandbox (Secret Manager GEMINI_API_KEY). Dùng Model Chain & Temperature đang chỉnh sửa ở bên trái.',
            style: TextStyle(fontSize: 12, color: AppColors.slate700),
          ),
        ),
        const SizedBox(height: 10),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text(
            'Chế độ Structured Plan JSON (Kiểm tra hợp đồng 4 khóa JSON)',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
          value: _liveExpectStructuredJson,
          onChanged: (v) => setState(() => _liveExpectStructuredJson = v),
        ),
        if (!_liveExpectStructuredJson) ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text(
              'Kèm System Prompt đã render từ Persona',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            value: _liveIncludeSystemInstruction,
            onChanged: (v) => setState(() => _liveIncludeSystemInstruction = v),
          ),
          const SizedBox(height: 6),
          TextField(
            key: const ValueKey('ai_studio_live_question_input'),
            controller: _liveQuestionCtrl,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Câu hỏi kiểm thử Gemini Chat',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            key: const ValueKey('ai_studio_run_live_gemini_btn'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
            onPressed: _isRunningLiveSandbox
                ? null
                : () => _runLiveGeminiSandbox(
                      heuristics: heuristics,
                      txRules: txRules,
                      knowledgeArticles: kbArticles,
                    ),
            icon: _isRunningLiveSandbox
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.bolt_rounded),
            label: Text(
              _isRunningLiveSandbox
                  ? 'Đang gọi Backend Gemini Sandbox...'
                  : 'Chạy Live Gemini Sandbox',
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_lastLiveError != null) AdminErrorStateCard(error: _lastLiveError!),
        if (res != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.slate50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.slate200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    AdminStatusBadge(
                      label: 'Model: ${res.modelUsed}',
                      color: AppColors.income,
                      backgroundColor: AppColors.incomeBackground,
                    ),
                    AdminStatusBadge(
                      label: 'Latency: ${res.latencyMs} ms',
                      color: AppColors.info,
                      backgroundColor: AppColors.infoBackground,
                    ),
                    if (res.jsonValid != null)
                      AdminStatusBadge(
                        label: res.jsonValid!
                            ? 'JSON Schema: HỢP LỆ'
                            : 'JSON Schema: LỖI',
                        color: res.jsonValid!
                            ? AppColors.income
                            : AppColors.expense,
                        backgroundColor: res.jsonValid!
                            ? AppColors.incomeBackground
                            : AppColors.expenseBackground,
                      ),
                  ],
                ),
                if (res.triedModels.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Chuỗi model đã thử: ${res.triedModels.join(' -> ')}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.slate600,
                    ),
                  ),
                ],
                if (res.jsonValidationErrors.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  for (final err in res.jsonValidationErrors)
                    Text(
                      '• $err',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.expense,
                      ),
                    ),
                ],
                const Divider(height: 16),
                SelectableText(
                  res.responseText,
                  key: const ValueKey('ai_studio_live_response_text'),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.slate800,
                    height: 1.45,
                  ),
                ),
                if (res.draftVerificationNote.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    res.draftVerificationNote,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontStyle: FontStyle.italic,
                      color: AppColors.slate500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

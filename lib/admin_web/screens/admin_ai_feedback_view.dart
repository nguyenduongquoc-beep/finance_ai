import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/ai_runtime_config_model.dart';
import '../../utils/constants.dart';
import '../services/admin_web_service.dart';
import '../widgets/admin_governance_widgets.dart';

/// Khu vực 5: Quản trị Phản hồi Chất lượng AI (`ai_feedback_reports`)
/// - Chỉ đọc trực tiếp trên Client; mọi xử lý (`resolved` / `ignored`) đi qua
///   Cloud Function `adminResolveAiFeedback`.
/// - Không bao giờ hiển thị UID gốc hay dữ liệu tài chính cá nhân.
class AdminAiFeedbackView extends StatefulWidget {
  final AdminWebService adminWebService;
  final String currentAdminUid;
  final String currentAdminEmail;
  final Map<String, dynamic>? tokenClaimsOverride;
  final void Function(String? suggestedKeyword)? onOpenOcrDictionary;
  final VoidCallback? onOpenAiStudio;
  final VoidCallback? onOpenHeuristics;

  const AdminAiFeedbackView({
    super.key,
    required this.adminWebService,
    required this.currentAdminUid,
    required this.currentAdminEmail,
    this.tokenClaimsOverride,
    this.onOpenOcrDictionary,
    this.onOpenAiStudio,
    this.onOpenHeuristics,
  });

  @override
  State<AdminAiFeedbackView> createState() => _AdminAiFeedbackViewState();
}

class _AdminAiFeedbackViewState extends State<AdminAiFeedbackView> {
  String _statusFilter = 'all';
  String _ratingFilter = 'all';
  String _featureFilter = 'all';
  final _searchCtrl = TextEditingController();
  bool _isBusy = false;

  static const Map<String, String> _featureLabels = {
    'ai_chat': 'AI Chat (CFP)',
    'monthly_plan': 'Kế hoạch tháng',
    'ocr_suggestion': 'Gợi ý OCR & Danh mục',
    'anomaly_alert': 'Cảnh báo bất thường',
  };

  static const List<String> _appliedActionPresets = [
    'updated_ocr_dictionary',
    'tuned_ai_prompt',
    'adjusted_heuristics',
    'updated_knowledge_base',
    'no_change_needed',
  ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _showResolveDialog(AiFeedbackReport report) async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    String? resultStatus;
    try {
      resultStatus = await showDialog<String>(
        context: context,
        builder: (ctx) => _ResolveFeedbackDialog(
          report: report,
          adminWebService: widget.adminWebService,
          currentAdminUid: widget.currentAdminUid,
          tokenClaimsOverride: widget.tokenClaimsOverride,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }

    if (resultStatus != null && mounted) {
      showAdminSnackBar(
        context,
        'Đã cập nhật trạng thái phản hồi #${report.reportId} thành $resultStatus.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AiFeedbackReport>>(
      stream: widget.adminWebService.streamAiFeedbackReports(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const AdminLoadingCard(
            message: 'Đang tải phản hồi chất lượng AI...',
          );
        }
        if (snapshot.hasError) {
          return AdminErrorStateCard(error: snapshot.error!);
        }

        final allReports = snapshot.data ?? const <AiFeedbackReport>[];
        final openCount = allReports.where((r) => r.status == 'open').length;
        final resolvedCount =
            allReports.where((r) => r.status == 'resolved').length;
        final ignoredCount =
            allReports.where((r) => r.status == 'ignored').length;
        final negativeCount =
            allReports.where((r) => r.rating == 'negative').length;

        final q = _searchCtrl.text.trim().toLowerCase();
        final filtered = allReports.where((r) {
          if (_statusFilter != 'all' && r.status != _statusFilter) return false;
          if (_ratingFilter != 'all' && r.rating != _ratingFilter) return false;
          if (_featureFilter != 'all' && r.targetFeature != _featureFilter) {
            return false;
          }
          if (q.isNotEmpty) {
            final haystack = [
              r.reportId,
              r.reasonCode,
              r.userNote ?? '',
              r.suggestedKeywordOrMerchant ?? '',
              r.modelUsed,
              r.targetFeature,
            ].join(' ').toLowerCase();
            if (!haystack.contains(q)) return false;
          }
          return true;
        }).toList();

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.infoBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.info.withValues(alpha: 0.35),
                  ),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.privacy_tip_outlined, color: AppColors.info),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Bảo vệ quyền riêng tư: Bảng ai_feedback_reports chỉ chứa metadata phiên bản AI, lý do đánh giá, chế độ anonymous/pseudonymous và ghi chú đã lọc số nhạy cảm. Hoàn toàn không lưu số dư ví, số tiền giao dịch hay UID gốc.',
                        style: TextStyle(fontSize: 12.5, color: AppColors.slate800),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _FeedbackKpiChip(
                    label: 'Tổng báo cáo',
                    count: allReports.length,
                    color: AppColors.primary,
                    bgColor: AppColors.infoBackground,
                  ),
                  _FeedbackKpiChip(
                    label: 'Đang chờ xử lý (open)',
                    count: openCount,
                    color: AppColors.warning,
                    bgColor: AppColors.warningBackground,
                  ),
                  _FeedbackKpiChip(
                    label: 'Đã xử lý (resolved)',
                    count: resolvedCount,
                    color: AppColors.income,
                    bgColor: AppColors.incomeBackground,
                  ),
                  _FeedbackKpiChip(
                    label: 'Đã bỏ qua (ignored)',
                    count: ignoredCount,
                    color: AppColors.slate600,
                    bgColor: AppColors.slate100,
                  ),
                  _FeedbackKpiChip(
                    label: 'Đánh giá chưa hài lòng',
                    count: negativeCount,
                    color: AppColors.expense,
                    bgColor: AppColors.expenseBackground,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              AdminSectionCard(
                title: 'Bộ lọc & Danh sách Phản hồi AI',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'all', label: Text('Tất cả')),
                            ButtonSegment(value: 'open', label: Text('Open')),
                            ButtonSegment(
                              value: 'resolved',
                              label: Text('Resolved'),
                            ),
                            ButtonSegment(
                              value: 'ignored',
                              label: Text('Ignored'),
                            ),
                          ],
                          selected: {_statusFilter},
                          onSelectionChanged: (s) =>
                              setState(() => _statusFilter = s.first),
                        ),
                        SizedBox(
                          width: 170,
                          child: DropdownButtonFormField<String>(
                            initialValue: _ratingFilter,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: 'Đánh giá',
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'all',
                                child: Text(
                                  'Tất cả',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'negative',
                                child: Text(
                                  'Tiêu cực (Negative)',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'positive',
                                child: Text(
                                  'Tích cực (Positive)',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                            onChanged: (v) {
                              if (v != null) setState(() => _ratingFilter = v);
                            },
                          ),
                        ),
                        SizedBox(
                          width: 210,
                          child: DropdownButtonFormField<String>(
                            initialValue: _featureFilter,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: 'Tính năng AI',
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: 'all',
                                child: Text(
                                  'Tất cả tính năng',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              for (final f
                                  in AiFeedbackReport.allowedTargetFeatures)
                                DropdownMenuItem(
                                  value: f,
                                  child: Text(
                                    _featureLabels[f] ?? f,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (v) {
                              if (v != null) setState(() => _featureFilter = v);
                            },
                          ),
                        ),
                        SizedBox(
                          width: 240,
                          child: TextField(
                            key: const ValueKey('feedback_search_input'),
                            controller: _searchCtrl,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: 'Tìm lý do, từ khóa OCR, model...',
                              isDense: true,
                              prefixIcon: const Icon(Icons.search, size: 18),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (filtered.isEmpty)
                      const AdminEmptyStateCard(
                        icon: Icons.feedback_outlined,
                        title: 'Không có báo cáo phản hồi AI nào khớp bộ lọc',
                        subtitle:
                            'Các phản hồi từ User App sẽ hiển thị tại đây khi được gửi qua Cloud Function submitAiFeedback.',
                      )
                    else
                      Column(
                        children: [
                          for (final report in filtered) ...[
                            _FeedbackReportCard(
                              report: report,
                              featureLabel:
                                  _featureLabels[report.targetFeature] ??
                                      report.targetFeature,
                              isBusy: _isBusy,
                              onResolve: () => _showResolveDialog(report),
                              onOpenOcrDictionary: widget.onOpenOcrDictionary,
                              onOpenAiStudio: widget.onOpenAiStudio,
                              onOpenHeuristics: widget.onOpenHeuristics,
                            ),
                            const SizedBox(height: 12),
                          ],
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FeedbackKpiChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final Color bgColor;

  const _FeedbackKpiChip({
    required this.label,
    required this.count,
    required this.color,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.slate700,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedbackReportCard extends StatelessWidget {
  final AiFeedbackReport report;
  final String featureLabel;
  final bool isBusy;
  final VoidCallback onResolve;
  final void Function(String? suggestedKeyword)? onOpenOcrDictionary;
  final VoidCallback? onOpenAiStudio;
  final VoidCallback? onOpenHeuristics;

  const _FeedbackReportCard({
    required this.report,
    required this.featureLabel,
    required this.isBusy,
    required this.onResolve,
    this.onOpenOcrDictionary,
    this.onOpenAiStudio,
    this.onOpenHeuristics,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    final isNeg = report.rating == 'negative';
    final statusColor = report.status == 'resolved'
        ? AppColors.income
        : (report.status == 'ignored' ? AppColors.slate600 : AppColors.warning);
    final statusBg = report.status == 'resolved'
        ? AppColors.incomeBackground
        : (report.status == 'ignored'
            ? AppColors.slate100
            : AppColors.warningBackground);

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
              AdminStatusBadge(
                label: report.status.toUpperCase(),
                color: statusColor,
                backgroundColor: statusBg,
              ),
              AdminStatusBadge(
                label: isNeg ? 'Chưa hài lòng' : 'Hài lòng',
                color: isNeg ? AppColors.expense : AppColors.income,
                backgroundColor: isNeg
                    ? AppColors.expenseBackground
                    : AppColors.incomeBackground,
                icon: isNeg
                    ? Icons.thumb_down_alt_outlined
                    : Icons.thumb_up_alt_outlined,
              ),
              AdminStatusBadge(
                label: featureLabel,
                color: AppColors.info,
                backgroundColor: AppColors.infoBackground,
              ),
              AdminStatusBadge(
                label: report.feedbackMode == 'pseudonymous'
                    ? 'Giả danh (pseudonymous)'
                    : 'Ẩn danh (anonymous)',
                color: AppColors.slate700,
                backgroundColor: Colors.white,
              ),
              Text(
                fmt.format(report.createdAt.toLocal()),
                style: const TextStyle(fontSize: 12, color: AppColors.slate500),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Lý do: ${report.reasonCode} • Model: ${report.modelUsed} • AI v${report.aiConfigVersion} • Heuristics v${report.heuristicsVersion} • Tier: ${report.dataTier}',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.slate800,
            ),
          ),
          if (report.reporterHash != null &&
              report.reporterHash!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Reporter Hash (1 chiều): ${report.reporterHash!.length > 16 ? '${report.reporterHash!.substring(0, 16)}...' : report.reporterHash}',
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.slate500,
                fontFamily: 'monospace',
              ),
            ),
          ],
          if (report.userNote != null && report.userNote!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Ghi chú User: "${report.userNote}"',
              style: const TextStyle(fontSize: 13, color: AppColors.slate700),
            ),
          ],
          if (report.suggestedKeywordOrMerchant != null &&
              report.suggestedKeywordOrMerchant!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.slate200),
              ),
              child: Text(
                'Từ khóa / Thương hiệu đề xuất: "${report.suggestedKeywordOrMerchant}"',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
          if (report.adminResolutionNote != null &&
                  report.adminResolutionNote!.isNotEmpty ||
              report.appliedAction != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.slate200),
              ),
              child: Text(
                'Xử lý bởi Admin (${report.appliedAction ?? 'N/A'}): ${report.adminResolutionNote ?? ''}',
                style: const TextStyle(fontSize: 12, color: AppColors.slate700),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                key: ValueKey('feedback_resolve_btn_${report.reportId}'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: isBusy ? null : onResolve,
                icon: const Icon(Icons.task_alt_rounded, size: 16),
                label: Text(
                  report.status == 'open'
                      ? 'Xử lý phản hồi'
                      : 'Cập nhật xử lý',
                ),
              ),
              if ((report.targetFeature == 'ocr_suggestion' ||
                      (report.suggestedKeywordOrMerchant ?? '').isNotEmpty) &&
                  onOpenOcrDictionary != null)
                OutlinedButton.icon(
                  key: ValueKey('feedback_goto_ocr_${report.reportId}'),
                  onPressed: () =>
                      onOpenOcrDictionary!(report.suggestedKeywordOrMerchant),
                  icon: const Icon(Icons.spellcheck_outlined, size: 16),
                  label: const Text('Mở OCR Dictionary'),
                ),
              if ((report.targetFeature == 'ai_chat' ||
                      report.targetFeature == 'monthly_plan') &&
                  onOpenAiStudio != null)
                OutlinedButton.icon(
                  key: ValueKey('feedback_goto_studio_${report.reportId}'),
                  onPressed: onOpenAiStudio,
                  icon: const Icon(Icons.psychology_outlined, size: 16),
                  label: const Text('Mở AI Studio'),
                ),
              if (report.targetFeature == 'anomaly_alert' &&
                  onOpenHeuristics != null)
                OutlinedButton.icon(
                  onPressed: onOpenHeuristics,
                  icon: const Icon(Icons.tune_rounded, size: 16),
                  label: const Text('Mở Ngưỡng định lượng'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResolveFeedbackDialog extends StatefulWidget {
  final AiFeedbackReport report;
  final AdminWebService adminWebService;
  final String currentAdminUid;
  final Map<String, dynamic>? tokenClaimsOverride;

  const _ResolveFeedbackDialog({
    required this.report,
    required this.adminWebService,
    required this.currentAdminUid,
    this.tokenClaimsOverride,
  });

  @override
  State<_ResolveFeedbackDialog> createState() => _ResolveFeedbackDialogState();
}

class _ResolveFeedbackDialogState extends State<_ResolveFeedbackDialog> {
  late String _selectedStatus;
  late final TextEditingController _noteCtrl;
  String? _selectedAction;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _selectedStatus =
        widget.report.status == 'ignored' ? 'ignored' : 'resolved';
    _noteCtrl = TextEditingController(
      text: widget.report.adminResolutionNote ?? '',
    );
    _selectedAction = widget.report.appliedAction ??
        (widget.report.targetFeature == 'ocr_suggestion'
            ? 'updated_ocr_dictionary'
            : 'tuned_ai_prompt');
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    const presets = _AdminAiFeedbackViewState._appliedActionPresets;
    const featureLabels = _AdminAiFeedbackViewState._featureLabels;

    return AlertDialog(
      title: const Text('Xử lý Phản hồi Chất lượng AI'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.slate50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.slate200),
                ),
                child: Text(
                  'Báo cáo #${report.reportId} • ${featureLabels[report.targetFeature] ?? report.targetFeature}\nLý do: ${report.reasonCode}${report.feedbackMode == 'pseudonymous' ? '\n(Chế độ giả danh: Backend sẽ tự động gửi thông báo ẩn danh tới người gửi)' : '\n(Chế độ ẩn danh hoàn toàn)'}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.slate700,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment<String>(
                    value: 'resolved',
                    icon: Icon(Icons.check_circle_outline, size: 17),
                    label: Text('Đã xử lý (resolved)'),
                  ),
                  ButtonSegment<String>(
                    value: 'ignored',
                    icon: Icon(Icons.do_not_disturb_on_outlined, size: 17),
                    label: Text('Bỏ qua (ignored)'),
                  ),
                ],
                selected: {_selectedStatus},
                onSelectionChanged: (s) {
                  setState(() {
                    _selectedStatus = s.first;
                    if (_selectedStatus == 'ignored') {
                      _selectedAction = 'no_change_needed';
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: presets.contains(_selectedAction)
                    ? _selectedAction
                    : presets.first,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Hành động khắc phục đã thực hiện (appliedAction)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                items: presets.map((a) {
                  return DropdownMenuItem<String>(
                    value: a,
                    child: Text(a, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (v) {
                  setState(() => _selectedAction = v);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('feedback_resolve_note_input'),
                controller: _noteCtrl,
                maxLength: 300,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Ghi chú xử lý của Admin',
                  hintText:
                      'VD: Đã bổ sung từ khóa mới vào OCR Dictionary và publish v2.',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(null),
          child: const Text('Hủy'),
        ),
        ElevatedButton(
          key: const ValueKey('feedback_confirm_resolve_btn'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _selectedStatus == 'resolved'
                ? AppColors.income
                : AppColors.slate700,
            foregroundColor: Colors.white,
          ),
          onPressed: _submitting
              ? null
              : () async {
                  setState(() => _submitting = true);
                  try {
                    await widget.adminWebService.resolveAiFeedback(
                      adminUid: widget.currentAdminUid,
                      reportId: report.reportId,
                      status: _selectedStatus,
                      adminResolutionNote: _noteCtrl.text.trim(),
                      appliedAction: _selectedAction,
                      tokenClaimsOverride: widget.tokenClaimsOverride,
                    );
                    if (context.mounted) {
                      Navigator.of(context).pop(_selectedStatus);
                    }
                  } catch (e) {
                    if (!context.mounted) return;
                    showAdminSnackBar(
                      context,
                      formatAdminErrorMessage(e),
                      isError: true,
                    );
                  } finally {
                    if (mounted) setState(() => _submitting = false);
                  }
                },
          child: const Text('Xác nhận qua Cloud Function'),
        ),
      ],
    );
  }
}

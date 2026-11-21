import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../l10n/app_localizations.dart';
import '../../models/support_ticket_model.dart';
import '../../services/firestore_service.dart';
import '../../services/support_service.dart';
import '../../utils/constants.dart';
import '../../utils/support_device_info.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_snackbar.dart';

/// Màn hình Tạo Yêu cầu Hỗ trợ / Tư vấn mới (User App)
class CreateSupportTicketScreen extends StatefulWidget {
  final SupportService? supportService;
  final FirestoreService? firestoreService;
  final SupportTicket? relatedTicket;
  final SupportTechnicalInfo Function()? technicalInfoCollector;
  final String? userIdOverride;
  final String? userNameOverride;
  final String? userEmailOverride;

  const CreateSupportTicketScreen({
    super.key,
    this.supportService,
    this.firestoreService,
    this.relatedTicket,
    this.technicalInfoCollector,
    this.userIdOverride,
    this.userNameOverride,
    this.userEmailOverride,
  });

  @override
  State<CreateSupportTicketScreen> createState() =>
      _CreateSupportTicketScreenState();
}

class _CreateSupportTicketScreenState extends State<CreateSupportTicketScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _sharedCtxCtrl = TextEditingController();

  late final SupportService _supportService;
  late SupportCategory _selectedCategory;
  SupportUserImpact _selectedImpact = SupportUserImpact.normal;
  SupportTicket? _attachedRelatedTicket;
  bool _includeTechnicalInfo = true;
  SupportTechnicalInfo? _previewTechnicalInfo;
  bool _includeOptInSummary = false;
  bool _isLoadingSummary = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _supportService = widget.supportService ?? SupportService();
    _attachedRelatedTicket =
        (widget.relatedTicket != null && widget.relatedTicket!.isClosed)
            ? widget.relatedTicket
            : null;
    _selectedCategory =
        _attachedRelatedTicket?.category ?? SupportCategory.appGuide;
    if (_selectedCategory == SupportCategory.bugReport) {
      _refreshTechnicalInfoPreview();
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _sharedCtxCtrl.dispose();
    super.dispose();
  }

  void _refreshTechnicalInfoPreview() {
    final collector =
        widget.technicalInfoCollector ?? collectBasicSupportTechnicalInfo;
    _previewTechnicalInfo = collector();
  }

  Future<void> _onToggleOptInSummary(bool enabled) async {
    setState(() {
      _includeOptInSummary = enabled;
      if (!enabled) {
        _sharedCtxCtrl.clear();
      }
    });
    if (!enabled) return;

    final uid =
        widget.userIdOverride ?? FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;

    setState(() => _isLoadingSummary = true);
    try {
      final summary = await _supportService.buildOptInMonthlySummary(
        uid,
        firestoreService: widget.firestoreService,
      );
      if (mounted && _includeOptInSummary) {
        setState(() {
          _sharedCtxCtrl.text = summary;
          _isLoadingSummary = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingSummary = false);
      }
    }
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    setState(() => _isSubmitting = true);
    try {
      String? resolvedName = widget.userNameOverride;
      String? resolvedEmail = widget.userEmailOverride;

      final currentUser = widget.userIdOverride != null
          ? null
          : FirebaseAuth.instance.currentUser;
      resolvedName ??= currentUser?.displayName;
      resolvedEmail ??= currentUser?.email;

      SupportTechnicalInfo? attachedTech;
      if (_selectedCategory == SupportCategory.bugReport &&
          _includeTechnicalInfo) {
        final collector =
            widget.technicalInfoCollector ?? collectBasicSupportTechnicalInfo;
        attachedTech = collector();
      }

      final created = await _supportService.createTicket(
        category: _selectedCategory,
        title: _titleCtrl.text,
        description: _descCtrl.text,
        sharedContext:
            _includeOptInSummary ? _sharedCtxCtrl.text.trim() : null,
        userImpact: _selectedImpact,
        technicalInfo: attachedTech,
        relatedTicket: _attachedRelatedTicket,
        userIdOverride: widget.userIdOverride,
        userNameOverride: resolvedName,
        userEmailOverride: resolvedEmail,
      );

      if (!mounted) return;
      AppSnackbar.show(context, context.tr('support_submit_success'));
      Navigator.of(context).pop(created);
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.show(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(
          context.tr('support_create_title'),
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            color: context.appTextPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_attachedRelatedTicket != null) ...[
                  Container(
                    key: const ValueKey('support_related_ticket_banner'),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.infoBackground,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.link_rounded,
                              size: 18,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                context.tr(
                                  'support_related_banner_title',
                                  params: {
                                    'code': _attachedRelatedTicket!.ticketCode,
                                  },
                                ),
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            TextButton(
                              key: const ValueKey('support_related_remove_btn'),
                              style: TextButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                minimumSize: const Size(0, 30),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () {
                                setState(() => _attachedRelatedTicket = null);
                              },
                              child: Text(
                                context.tr('support_related_remove'),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          context.tr('support_related_banner_sub'),
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppColors.slate700,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                Text(
                  context.tr('support_cat_label'),
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: context.appTextPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                ...SupportCategory.values.map((cat) {
                  final isSelected = _selectedCategory == cat;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      key: ValueKey('support_cat_option_${cat.code}'),
                      borderRadius: BorderRadius.circular(AppColors.radiusCard),
                      onTap: () {
                        setState(() {
                          _selectedCategory = cat;
                          if (cat == SupportCategory.bugReport) {
                            _refreshTechnicalInfoPreview();
                          }
                          if (cat != SupportCategory.financialAdvisory &&
                              _includeOptInSummary) {
                            _includeOptInSummary = false;
                            _sharedCtxCtrl.clear();
                          }
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? cat.accentColor.withValues(alpha: 0.08)
                              : context.appCard,
                          borderRadius:
                              BorderRadius.circular(AppColors.radiusCard),
                          border: Border.all(
                            color: isSelected
                                ? cat.accentColor
                                : context.appBorder,
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: cat.accentColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                cat.icon,
                                color: cat.accentColor,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    cat.localizedLabel(context),
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: context.appTextPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    cat.localizedDescription(context),
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: context.appTextSecondary,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              isSelected
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_off_rounded,
                              color: isSelected
                                  ? cat.accentColor
                                  : context.appTextSecondary,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                if (_selectedCategory == SupportCategory.financialAdvisory) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.infoBackground,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 18,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            context.tr('support_advisory_scope_note'),
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppColors.slate700,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  context.tr('support_impact_label'),
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: context.appTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  context.tr('support_impact_note'),
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    color: context.appTextSecondary,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: SupportUserImpact.values.map((imp) {
                    final selected = _selectedImpact == imp;
                    return ChoiceChip(
                      key: ValueKey('support_impact_option_${imp.code}'),
                      label: Text(imp.localizedLabel(context)),
                      tooltip: imp.localizedDescription(context),
                      selected: selected,
                      onSelected: (_) => setState(() => _selectedImpact = imp),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Text(
                  context.tr('support_field_title'),
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: context.appTextPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  key: const ValueKey('support_title_input'),
                  controller: _titleCtrl,
                  maxLength: SupportTicket.kMaxTitleLength,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    hintText: _selectedCategory.localizedTitleHint(context),
                  ),
                  validator: (val) {
                    final len = (val ?? '').trim().length;
                    if (len < SupportTicket.kMinTitleLength ||
                        len > SupportTicket.kMaxTitleLength) {
                      return context.tr('support_err_title');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  context.tr('support_field_desc'),
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: context.appTextPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  key: const ValueKey('support_desc_input'),
                  controller: _descCtrl,
                  maxLines: 5,
                  minLines: 4,
                  maxLength: SupportTicket.kMaxDescriptionLength,
                  decoration: InputDecoration(
                    hintText: _selectedCategory.localizedDescHint(context),
                    alignLabelWithHint: true,
                  ),
                  validator: (val) {
                    final len = (val ?? '').trim().length;
                    if (len < SupportTicket.kMinDescriptionLength ||
                        len > SupportTicket.kMaxDescriptionLength) {
                      return context.tr('support_err_desc');
                    }
                    return null;
                  },
                ),
                if (_selectedCategory == SupportCategory.bugReport) ...[
                  const SizedBox(height: 8),
                  AppCard(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile(
                          key: const ValueKey('support_tech_info_switch'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: _includeTechnicalInfo,
                          onChanged: (enabled) {
                            setState(() {
                              _includeTechnicalInfo = enabled;
                              if (enabled && _previewTechnicalInfo == null) {
                                _refreshTechnicalInfoPreview();
                              }
                            });
                          },
                          title: Text(
                            context.tr('support_tech_info_title'),
                            style: GoogleFonts.inter(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: context.appTextPrimary,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              context.tr('support_tech_info_sub'),
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: context.appTextSecondary,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ),
                        if (_includeTechnicalInfo &&
                            _previewTechnicalInfo != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            key: const ValueKey('support_tech_info_preview'),
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: context.appInputFill,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.devices_other_rounded,
                                  size: 16,
                                  color: context.appTextSecondary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _previewTechnicalInfo!.summaryLine,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: context.appTextPrimary,
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
                if (_selectedCategory == SupportCategory.financialAdvisory) ...[
                  const SizedBox(height: 8),
                  AppCard(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile(
                          key: const ValueKey('support_optin_summary_switch'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: _includeOptInSummary,
                          onChanged: _onToggleOptInSummary,
                          title: Text(
                            context.tr('support_optin_title'),
                            style: GoogleFonts.inter(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: context.appTextPrimary,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              context.tr('support_optin_sub'),
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: context.appTextSecondary,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ),
                        if (_includeOptInSummary) ...[
                          const SizedBox(height: 8),
                          if (_isLoadingSummary)
                            Row(
                              children: [
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  context.tr('support_optin_loading'),
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: context.appTextSecondary,
                                  ),
                                ),
                              ],
                            )
                          else
                            TextFormField(
                              key: const ValueKey('support_shared_ctx_input'),
                              controller: _sharedCtxCtrl,
                              maxLines: 5,
                              maxLength: SupportTicket.kMaxSharedContextLength,
                              decoration: InputDecoration(
                                labelText:
                                    context.tr('support_optin_preview_label'),
                                isDense: true,
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  context.tr('support_text_only_note'),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: context.appTextSecondary,
                  ),
                ),
                const SizedBox(height: 18),
                AppButton(
                  key: const ValueKey('support_submit_btn'),
                  text: context.tr('support_submit_btn'),
                  isLoading: _isSubmitting,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

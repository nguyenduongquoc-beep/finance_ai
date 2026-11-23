import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/monthly_financial_plan.dart';
import '../../utils/category_icons.dart';
import '../../utils/constants.dart';
import '../../widgets/app_snackbar.dart';
import '../services/admin_web_service.dart';
import '../widgets/admin_governance_widgets.dart';

/// Màn hình Quản lý Danh mục Mặc định Hệ thống (`system_categories`) trên Admin Web Portal (Mục 3.3).
/// Chức năng:
/// - Xem danh sách danh mục hệ thống (lọc theo Chi tiêu / Thu nhập, Đang hiển thị / Đang ẩn).
/// - Thêm mới và chỉnh sửa đầy đủ: Tên, Loại, Icon, Màu sắc, Thiết lập Essential / Flexible.
/// - Ẩn/hiện danh mục thông qua `isActive` (không xóa cứng để bảo toàn lịch sử tham chiếu).
/// - Đồng bộ trực tiếp với `category_setup_screen.dart` cho người dùng mới mà không ghi đè danh mục cá nhân của người dùng cũ.
class AdminCategoriesManagementView extends StatefulWidget {
  final AdminWebService adminService;
  final String currentAdminUid;
  final String currentAdminEmail;
  final Map<String, dynamic>? tokenClaimsOverride;

  const AdminCategoriesManagementView({
    super.key,
    required this.adminService,
    required this.currentAdminUid,
    required this.currentAdminEmail,
    this.tokenClaimsOverride,
  });

  @override
  State<AdminCategoriesManagementView> createState() =>
      _AdminCategoriesManagementViewState();
}

class _AdminCategoriesManagementViewState
    extends State<AdminCategoriesManagementView> {
  String _typeFilter = 'all'; // 'all' | 'expense' | 'income'
  bool _showHidden = true;
  late Stream<List<SystemCategoryTemplate>> _categoriesStream;
  final Set<String> _busyCategoryIds = <String>{};
  bool _isSeeding = false;

  @override
  void initState() {
    super.initState();
    _categoriesStream =
        widget.adminService.firestoreService.streamSystemCategoryTemplates();
  }

  @override
  void didUpdateWidget(covariant AdminCategoriesManagementView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.adminService != widget.adminService) {
      _categoriesStream =
          widget.adminService.firestoreService.streamSystemCategoryTemplates();
    }
  }

  void _retryStream() {
    setState(() {
      _categoriesStream =
          widget.adminService.firestoreService.streamSystemCategoryTemplates();
    });
  }

  Future<void> _openCategoryFormDialog({
    SystemCategoryTemplate? existing,
  }) async {
    final savedName = await showDialog<String>(
      context: context,
      builder: (ctx) => _CategoryFormDialog(
        existing: existing,
        onSave: (template, isNew) => widget.adminService.saveSystemCategory(
          adminUid: widget.currentAdminUid,
          adminEmail: widget.currentAdminEmail,
          template: template,
          isNew: isNew,
          tokenClaimsOverride: widget.tokenClaimsOverride,
        ),
      ),
    );

    if (savedName == null || !mounted) return;
    AppSnackbar.show(
      context,
      existing == null
          ? 'Đã thêm danh mục hệ thống "$savedName".'
          : 'Đã cập nhật danh mục hệ thống "$savedName".',
    );
  }

  Future<void> _handleSeedDefaults() async {
    if (_isSeeding) return;
    setState(() => _isSeeding = true);
    try {
      await widget.adminService.seedInitialSystemCategories(
        adminUid: widget.currentAdminUid,
        adminEmail: widget.currentAdminEmail,
        tokenClaimsOverride: widget.tokenClaimsOverride,
      );
      if (!mounted) return;
      AppSnackbar.show(
        context,
        'Đã khởi tạo bộ danh mục hệ thống mặc định.',
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.show(
        context,
        'Không thể khởi tạo danh mục mặc định: ${formatAdminErrorMessage(e)}',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isSeeding = false);
    }
  }

  Future<void> _handleToggleEssential(SystemCategoryTemplate item) async {
    if (_busyCategoryIds.contains(item.id)) return;
    setState(() => _busyCategoryIds.add(item.id));
    final nextEssential = !item.isEssential;
    try {
      await widget.adminService.saveSystemCategory(
        adminUid: widget.currentAdminUid,
        adminEmail: widget.currentAdminEmail,
        template: item.copyWith(isEssential: nextEssential),
        isNew: false,
        tokenClaimsOverride: widget.tokenClaimsOverride,
      );
      if (!mounted) return;
      AppSnackbar.show(
        context,
        nextEssential
            ? 'Đã chuyển "${item.name}" thành Khoản chi Thiết yếu.'
            : 'Đã chuyển "${item.name}" thành Khoản chi Linh hoạt.',
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.show(
        context,
        'Không thể cập nhật phân loại Thiết yếu/Linh hoạt: ${formatAdminErrorMessage(e)}',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _busyCategoryIds.remove(item.id));
      }
    }
  }

  Future<void> _handleToggleActive(
    SystemCategoryTemplate item,
    bool nextActive,
  ) async {
    if (_busyCategoryIds.contains(item.id)) return;
    setState(() => _busyCategoryIds.add(item.id));
    try {
      await widget.adminService.toggleSystemCategoryActive(
        adminUid: widget.currentAdminUid,
        adminEmail: widget.currentAdminEmail,
        template: item,
        isActive: nextActive,
        tokenClaimsOverride: widget.tokenClaimsOverride,
      );
      if (!mounted) return;
      AppSnackbar.show(
        context,
        nextActive
            ? 'Đã hiển thị lại danh mục "${item.name}".'
            : 'Đã ẩn danh mục "${item.name}" khỏi danh sách mặc định.',
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.show(
        context,
        'Không thể cập nhật trạng thái hiển thị: ${formatAdminErrorMessage(e)}',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _busyCategoryIds.remove(item.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<SystemCategoryTemplate>>(
      stream: _categoriesStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: AdminErrorStateCard(
              error: snapshot.error!,
              onRetry: _retryStream,
            ),
          );
        }

        final allCategories =
            snapshot.data ?? const <SystemCategoryTemplate>[];
        final filtered = allCategories.where((c) {
          if (!_showHidden && !c.isActive) return false;
          if (_typeFilter != 'all' && c.type != _typeFilter) return false;
          return true;
        }).toList();

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thanh công cụ & Bộ lọc
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.slate200),
                ),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _buildFilterChip('Tất cả (${allCategories.length})', 'all'),
                        _buildFilterChip(
                          'Chi tiêu (${allCategories.where((c) => c.type == 'expense').length})',
                          'expense',
                        ),
                        _buildFilterChip(
                          'Thu nhập (${allCategories.where((c) => c.type == 'income').length})',
                          'income',
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          label: const Text('Hiển thị cả danh mục đã ẩn'),
                          selected: _showHidden,
                          onSelected: (v) => setState(() => _showHidden = v),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (allCategories.isEmpty) ...[
                          OutlinedButton.icon(
                            key: const ValueKey('admin_seed_categories_btn'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 42),
                            ),
                            onPressed: _isSeeding ? null : _handleSeedDefaults,
                            icon: _isSeeding
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.auto_fix_high_rounded,
                                    size: 18,
                                  ),
                            label: const Text('Khởi tạo bộ mặc định'),
                          ),
                          const SizedBox(width: 10),
                        ],
                        FilledButton.icon(
                          key: const ValueKey('admin_add_category_btn'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 42),
                          ),
                          onPressed: () => _openCategoryFormDialog(),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Thêm Danh mục Hệ thống'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Danh sách danh mục hệ thống
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.slate200),
                  ),
                  child: filtered.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.category_outlined,
                                  size: 46,
                                  color: AppColors.slate400,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Chưa có danh mục hệ thống nào trong bộ lọc này.',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.slate700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Nhấn "Thêm Danh mục Hệ thống" hoặc "Khởi tạo bộ mặc định" để cung cấp danh mục mẫu cho người dùng mới.',
                                  style: GoogleFonts.inter(
                                    fontSize: 12.5,
                                    color: AppColors.slate500,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const Divider(
                            height: 16,
                            color: AppColors.slate200,
                          ),
                          itemBuilder: (context, index) {
                            final item = filtered[index];
                            final isExpense = item.type == 'expense';
                            final itemColor = Color(item.color);

                            return Opacity(
                              opacity: item.isActive ? 1.0 : 0.55,
                              child: Row(
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: itemColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(11),
                                    ),
                                    child: Icon(
                                      categoryIconData(item.icon),
                                      color: itemColor,
                                      size: 21,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              item.name,
                                              style: GoogleFonts.inter(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.slate900,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            _buildTag(
                                              isExpense
                                                  ? 'Chi tiêu'
                                                  : 'Thu nhập',
                                              isExpense
                                                  ? AppColors.expense
                                                  : AppColors.income,
                                            ),
                                            if (isExpense) ...[
                                              const SizedBox(width: 6),
                                              _buildTag(
                                                item.isEssential
                                                    ? 'Essential (Thiết yếu)'
                                                    : 'Flexible (Linh hoạt)',
                                                item.isEssential
                                                    ? AppColors.primary
                                                    : const Color(0xFFD97706),
                                              ),
                                            ],
                                            const SizedBox(width: 6),
                                            _buildTag(
                                              item.isActive
                                                  ? 'Đang hiển thị'
                                                  : 'Đang ẩn',
                                              item.isActive
                                                  ? AppColors.income
                                                  : AppColors.slate500,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          'Mã: ${item.id} · Icon: ${item.icon}',
                                          style: GoogleFonts.inter(
                                            fontSize: 11.5,
                                            color: AppColors.slate500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isExpense) ...[
                                    Tooltip(
                                      message:
                                          'Chuyển đổi Thiết yếu (Essential) / Linh hoạt (Flexible)',
                                      child: OutlinedButton(
                                        key: ValueKey(
                                            'toggle_essential_${item.id}'),
                                        style: OutlinedButton.styleFrom(
                                          minimumSize: const Size(0, 36),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                        ),
                                        onPressed: _busyCategoryIds
                                                .contains(item.id)
                                            ? null
                                            : () =>
                                                _handleToggleEssential(item),
                                        child: Text(
                                          item.isEssential
                                              ? 'Đặt Linh hoạt'
                                              : 'Đặt Thiết yếu',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  IconButton(
                                    key: ValueKey('edit_cat_${item.id}'),
                                    tooltip: 'Chỉnh sửa danh mục',
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 20,
                                    ),
                                    onPressed:
                                        _busyCategoryIds.contains(item.id)
                                            ? null
                                            : () => _openCategoryFormDialog(
                                                existing: item),
                                  ),
                                  Switch(
                                    key: ValueKey('toggle_active_${item.id}'),
                                    value: item.isActive,
                                    onChanged:
                                        _busyCategoryIds.contains(item.id)
                                            ? null
                                            : (val) =>
                                                _handleToggleActive(item, val),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final selected = _typeFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _typeFilter = value),
    );
  }

  Widget _buildTag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// Dialog Thêm / Sửa Danh mục Mặc định Hệ thống:
/// - Tự quản lý và giải phóng `TextEditingController`, `FocusNode`, `ScrollController`.
/// - Hiển thị thanh cuộn rõ ràng, báo lỗi validation nếu bỏ trống hoặc vượt quá 80 ký tự.
/// - Bọc `try/catch` + trạng thái loading chống bấm đúp để không bao giờ bị "đơ/im lặng" khi Cloud Function lỗi.
class _CategoryFormDialog extends StatefulWidget {
  final SystemCategoryTemplate? existing;
  final Future<String> Function(SystemCategoryTemplate template, bool isNew)
      onSave;

  const _CategoryFormDialog({
    required this.existing,
    required this.onSave,
  });

  @override
  State<_CategoryFormDialog> createState() => _CategoryFormDialogState();
}

class _CategoryFormDialogState extends State<_CategoryFormDialog> {
  static const int _kMaxCategoryNameLength = 80;

  late final TextEditingController _nameCtrl;
  final _nameFocusNode = FocusNode();
  final _scrollCtrl = ScrollController();

  late String _selectedType;
  late String _selectedIcon;
  late int _selectedColor;
  late bool _isEssential;
  late bool _isActive;

  bool _isSaving = false;
  String? _errorMessage;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _selectedType = widget.existing?.type ?? 'expense';
    _selectedIcon = widget.existing?.icon ?? 'restaurant';
    _selectedColor = widget.existing?.color ?? kSystemCategoryColorPalette.first;
    _isEssential = widget.existing?.isEssential ?? false;
    _isActive = widget.existing?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _nameFocusNode.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSaving) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() {
        _errorMessage = 'Vui lòng nhập tên danh mục mặc định trước khi lưu.';
      });
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
      _nameFocusNode.requestFocus();
      return;
    }
    if (name.length > _kMaxCategoryNameLength) {
      setState(() {
        _errorMessage =
            'Tên danh mục không được vượt quá $_kMaxCategoryNameLength ký tự.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final id = widget.existing?.id ??
        'sys_${DateTime.now().millisecondsSinceEpoch}';
    final template = SystemCategoryTemplate(
      id: id,
      name: name,
      type: _selectedType,
      icon: _selectedIcon,
      color: _selectedColor,
      isEssential: _selectedType == 'expense' ? _isEssential : false,
      isActive: _isActive,
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    try {
      await widget.onSave(template, _isNew);
      if (mounted) {
        Navigator.of(context).pop(name);
      }
    } catch (e) {
      if (!mounted) return;
      final msg = formatAdminErrorMessage(e);
      setState(() {
        _isSaving = false;
        _errorMessage = msg;
      });
      AppSnackbar.show(context, msg, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _isNew
            ? 'Thêm Danh mục Mặc định Hệ thống'
            : 'Chỉnh sửa Danh mục Hệ thống',
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: Scrollbar(
                controller: _scrollCtrl,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.only(right: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        key: const ValueKey('admin_cat_name_input'),
                        controller: _nameCtrl,
                        focusNode: _nameFocusNode,
                        enabled: !_isSaving,
                        maxLength: _kMaxCategoryNameLength,
                        decoration: const InputDecoration(
                          labelText: 'Tên danh mục mặc định',
                          hintText: 'VD: Ăn uống, Di chuyển, Lương...',
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: const ValueKey('admin_cat_type_dropdown'),
                        initialValue: _selectedType,
                        decoration:
                            const InputDecoration(labelText: 'Loại danh mục'),
                        items: const [
                          DropdownMenuItem(
                            value: 'expense',
                            child: Text('Chi tiêu (Expense)'),
                          ),
                          DropdownMenuItem(
                            value: 'income',
                            child: Text('Thu nhập (Income)'),
                          ),
                        ],
                        onChanged: _isSaving
                            ? null
                            : (val) {
                                setState(() {
                                  _selectedType = val ?? 'expense';
                                  if (_selectedType == 'income') {
                                    _isEssential = false;
                                  }
                                });
                              },
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Biểu tượng (Icon)',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.slate600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: kSystemCategoryIconOptions.map((opt) {
                          final iconKey = opt['key'] as String;
                          final iconData = opt['icon'] as IconData;
                          final label = opt['label'] as String;
                          final isSelected = _selectedIcon == iconKey;

                          return Tooltip(
                            message: label,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: _isSaving
                                  ? null
                                  : () => setState(() => _selectedIcon = iconKey),
                              child: Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Color(_selectedColor)
                                          .withValues(alpha: 0.16)
                                      : AppColors.slate100,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isSelected
                                        ? Color(_selectedColor)
                                        : AppColors.slate200,
                                    width: isSelected ? 1.8 : 1,
                                  ),
                                ),
                                child: Icon(
                                  iconData,
                                  size: 20,
                                  color: isSelected
                                      ? Color(_selectedColor)
                                      : AppColors.slate600,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Màu sắc nhận diện',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.slate600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: kSystemCategoryColorPalette.map((colorVal) {
                          final isSelected = _selectedColor == colorVal;
                          return InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: _isSaving
                                ? null
                                : () =>
                                    setState(() => _selectedColor = colorVal),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Color(colorVal),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected
                                      ? AppColors.slate900
                                      : Colors.transparent,
                                  width: 2.5,
                                ),
                              ),
                              child: isSelected
                                  ? const Icon(
                                      Icons.check_rounded,
                                      size: 16,
                                      color: Colors.white,
                                    )
                                  : null,
                            ),
                          );
                        }).toList(),
                      ),
                      if (_selectedType == 'expense') ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.slate50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.slate200),
                          ),
                          child: SwitchListTile(
                            key: const ValueKey('admin_cat_essential_switch'),
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              'Khoản chi Thiết yếu (Essential)',
                              style: GoogleFonts.inter(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              'Bật: Thiết yếu (Ưu tiên giữ nguyên khi AI lập kế hoạch).\nTắt: Linh hoạt (Có thể điều chỉnh tiết kiệm).',
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                color: AppColors.slate500,
                              ),
                            ),
                            value: _isEssential,
                            onChanged: _isSaving
                                ? null
                                : (v) => setState(() => _isEssential = v),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.slate50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.slate200),
                        ),
                        child: SwitchListTile(
                          key: const ValueKey('admin_cat_active_switch'),
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'Hiển thị cho người dùng mới (isActive)',
                            style: GoogleFonts.inter(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            'Khi tắt, danh mục sẽ được ẩn khỏi màn hình khởi tạo của người dùng mới nhưng không xóa dữ liệu lịch sử.',
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              color: AppColors.slate500,
                            ),
                          ),
                          value: _isActive,
                          onChanged: _isSaving
                              ? null
                              : (v) => setState(() => _isActive = v),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                key: const ValueKey('admin_cat_form_error'),
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.expenseBackground,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.expense.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  _errorMessage!,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.expense,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          key: const ValueKey('admin_cat_save_btn'),
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(_isNew ? 'Thêm danh mục' : 'Lưu thay đổi'),
        ),
      ],
    );
  }
}

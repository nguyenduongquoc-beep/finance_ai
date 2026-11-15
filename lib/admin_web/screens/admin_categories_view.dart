import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/monthly_financial_plan.dart';
import '../../utils/category_icons.dart';
import '../../utils/constants.dart';
import '../../widgets/app_snackbar.dart';
import '../services/admin_web_service.dart';

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

  Future<void> _openCategoryFormDialog({
    SystemCategoryTemplate? existing,
  }) async {
    final isNew = existing == null;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    String selectedType = existing?.type ?? 'expense';
    String selectedIcon = existing?.icon ?? 'restaurant';
    int selectedColor = existing?.color ?? kSystemCategoryColorPalette.first;
    bool isEssential = existing?.isEssential ?? false;
    bool isActive = existing?.isActive ?? true;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Text(
              isNew
                  ? 'Thêm Danh mục Mặc định Hệ thống'
                  : 'Chỉnh sửa Danh mục Hệ thống',
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      key: const ValueKey('admin_cat_name_input'),
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Tên danh mục mặc định',
                        hintText: 'VD: Ăn uống, Di chuyển, Lương...',
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      key: const ValueKey('admin_cat_type_dropdown'),
                      initialValue: selectedType,
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
                      onChanged: (val) {
                        setDialogState(() {
                          selectedType = val ?? 'expense';
                          if (selectedType == 'income') {
                            isEssential = false;
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
                        final isSelected = selectedIcon == iconKey;

                        return Tooltip(
                          message: label,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () =>
                                setDialogState(() => selectedIcon = iconKey),
                            child: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Color(selectedColor).withValues(alpha: 0.16)
                                    : AppColors.slate100,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected
                                      ? Color(selectedColor)
                                      : AppColors.slate200,
                                  width: isSelected ? 1.8 : 1,
                                ),
                              ),
                              child: Icon(
                                iconData,
                                size: 20,
                                color: isSelected
                                    ? Color(selectedColor)
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
                        final isSelected = selectedColor == colorVal;
                        return InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () =>
                              setDialogState(() => selectedColor = colorVal),
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
                    if (selectedType == 'expense') ...[
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
                          value: isEssential,
                          onChanged: (v) =>
                              setDialogState(() => isEssential = v),
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
                        value: isActive,
                        onChanged: (v) => setDialogState(() => isActive = v),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Hủy'),
              ),
              FilledButton(
                key: const ValueKey('admin_cat_save_btn'),
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) return;

                  final id = existing?.id ??
                      'sys_${DateTime.now().millisecondsSinceEpoch}';
                  final template = SystemCategoryTemplate(
                    id: id,
                    name: name,
                    type: selectedType,
                    icon: selectedIcon,
                    color: selectedColor,
                    isEssential: selectedType == 'expense' ? isEssential : false,
                    isActive: isActive,
                    createdAt: existing?.createdAt ?? DateTime.now(),
                    updatedAt: DateTime.now(),
                  );

                  await widget.adminService.saveSystemCategory(
                    adminUid: widget.currentAdminUid,
                    adminEmail: widget.currentAdminEmail,
                    template: template,
                    isNew: isNew,
                    tokenClaimsOverride: widget.tokenClaimsOverride,
                  );

                  if (ctx.mounted) Navigator.of(ctx).pop();
                  if (!mounted) return;
                  AppSnackbar.show(
                    context,
                    isNew
                        ? 'Đã thêm danh mục hệ thống "$name".'
                        : 'Đã cập nhật danh mục hệ thống "$name".',
                  );
                },
                child: Text(isNew ? 'Thêm danh mục' : 'Lưu thay đổi'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final firestore = widget.adminService.firestoreService;

    return StreamBuilder<List<SystemCategoryTemplate>>(
      stream: firestore.streamSystemCategoryTemplates(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
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
                            onPressed: () async {
                              await widget.adminService
                                  .seedInitialSystemCategories(
                                adminUid: widget.currentAdminUid,
                                adminEmail: widget.currentAdminEmail,
                                tokenClaimsOverride: widget.tokenClaimsOverride,
                              );
                              if (!context.mounted) return;
                              AppSnackbar.show(
                                context,
                                'Đã khởi tạo bộ danh mục hệ thống mặc định.',
                              );
                            },
                            icon: const Icon(
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
                                        onPressed: () async {
                                          await widget.adminService
                                              .saveSystemCategory(
                                            adminUid: widget.currentAdminUid,
                                            adminEmail:
                                                widget.currentAdminEmail,
                                            template: item.copyWith(
                                              isEssential: !item.isEssential,
                                            ),
                                            isNew: false,
                                            tokenClaimsOverride:
                                                widget.tokenClaimsOverride,
                                          );
                                        },
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
                                    onPressed: () => _openCategoryFormDialog(
                                      existing: item,
                                    ),
                                  ),
                                  Switch(
                                    key: ValueKey('toggle_active_${item.id}'),
                                    value: item.isActive,
                                    onChanged: (val) async {
                                      await widget.adminService
                                          .toggleSystemCategoryActive(
                                        adminUid: widget.currentAdminUid,
                                        adminEmail: widget.currentAdminEmail,
                                        template: item,
                                        isActive: val,
                                        tokenClaimsOverride:
                                            widget.tokenClaimsOverride,
                                      );
                                      if (!context.mounted) return;
                                      AppSnackbar.show(
                                        context,
                                        val
                                            ? 'Đã hiển thị lại danh mục "${item.name}".'
                                            : 'Đã ẩn danh mục "${item.name}" khỏi danh sách mặc định.',
                                      );
                                    },
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

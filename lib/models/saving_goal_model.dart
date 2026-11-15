/// Bản ghi chi tiết từng lần nạp tiền vào mục tiêu tiết kiệm
class GoalDepositRecord {
  final String depositId;
  final String walletId;
  final String walletName;
  final double depositedAmount;
  final double remainingAmount;
  final DateTime createdAt;

  const GoalDepositRecord({
    required this.depositId,
    required this.walletId,
    required this.walletName,
    required this.depositedAmount,
    required this.remainingAmount,
    required this.createdAt,
  });

  GoalDepositRecord copyWith({
    String? depositId,
    String? walletId,
    String? walletName,
    double? depositedAmount,
    double? remainingAmount,
    DateTime? createdAt,
  }) {
    return GoalDepositRecord(
      depositId: depositId ?? this.depositId,
      walletId: walletId ?? this.walletId,
      walletName: walletName ?? this.walletName,
      depositedAmount: depositedAmount ?? this.depositedAmount,
      remainingAmount: remainingAmount ?? this.remainingAmount,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory GoalDepositRecord.fromMap(Map<String, dynamic> map) {
    final deposited = SavingGoal._parseDouble(map['depositedAmount'] ?? map['amount']);
    final remaining = map.containsKey('remainingAmount')
        ? SavingGoal._parseDouble(map['remainingAmount'])
        : deposited;
    return GoalDepositRecord(
      depositId: map['depositId']?.toString() ?? '',
      walletId: map['walletId']?.toString() ?? '',
      walletName: map['walletName']?.toString() ?? 'Ví',
      depositedAmount: deposited,
      remainingAmount: remaining.clamp(0.0, deposited),
      createdAt: SavingGoal._parseDate(map['createdAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'depositId': depositId,
      'walletId': walletId,
      'walletName': walletName,
      'depositedAmount': depositedAmount,
      'remainingAmount': remainingAmount,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

/// Thông tin tổng hợp nguồn tiền đã nạp và còn có thể rút theo từng ví nguồn
class GoalWalletSource {
  final String walletId;
  final String walletName;
  final double totalDeposited;
  final double withdrawableAmount;
  final DateTime? lastDepositedAt;

  const GoalWalletSource({
    required this.walletId,
    required this.walletName,
    required this.totalDeposited,
    required this.withdrawableAmount,
    this.lastDepositedAt,
  });

  GoalWalletSource copyWith({
    String? walletId,
    String? walletName,
    double? totalDeposited,
    double? withdrawableAmount,
    DateTime? lastDepositedAt,
  }) {
    return GoalWalletSource(
      walletId: walletId ?? this.walletId,
      walletName: walletName ?? this.walletName,
      totalDeposited: totalDeposited ?? this.totalDeposited,
      withdrawableAmount: withdrawableAmount ?? this.withdrawableAmount,
      lastDepositedAt: lastDepositedAt ?? this.lastDepositedAt,
    );
  }

  factory GoalWalletSource.fromMap(Map<String, dynamic> map, [String? keyId]) {
    final totalDep = SavingGoal._parseDouble(map['totalDeposited']);
    final withdrawable = SavingGoal._parseDouble(map['withdrawableAmount']);
    return GoalWalletSource(
      walletId: map['walletId']?.toString() ?? keyId ?? '',
      walletName: map['walletName']?.toString() ?? 'Ví',
      totalDeposited: totalDep,
      withdrawableAmount: withdrawable.clamp(0.0, double.infinity),
      lastDepositedAt: map['lastDepositedAt'] != null
          ? SavingGoal._parseDate(map['lastDepositedAt'])
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'walletId': walletId,
      'walletName': walletName,
      'totalDeposited': totalDeposited,
      'withdrawableAmount': withdrawableAmount,
      if (lastDepositedAt != null)
        'lastDepositedAt': lastDepositedAt!.toIso8601String(),
    };
  }
}

/// ============================================================
/// SAVING GOAL MODEL
/// Firestore collection: savingGoals/{goalId}
/// Theo dõi tiến độ tích lũy và nguồn tiền nạp/rút theo từng ví
/// ============================================================
class SavingGoal {
  final String goalId;
  final String userId;
  final String name; // vd: "Laptop"
  final double targetAmount; // vd: 30.000.000
  final double savedAmount; // vd: 12.000.000
  final int months; // số tháng để đạt mục tiêu
  final DateTime createdAt;
  final Map<String, GoalWalletSource> walletSources;
  final List<GoalDepositRecord> deposits;
  final bool sourcesSynced;

  SavingGoal({
    required this.goalId,
    required this.userId,
    required this.name,
    required this.targetAmount,
    this.savedAmount = 0,
    required this.months,
    required this.createdAt,
    Map<String, GoalWalletSource>? walletSources,
    List<GoalDepositRecord>? deposits,
    this.sourcesSynced = false,
  })  : walletSources = walletSources ?? const {},
        deposits = deposits ?? const [];

  SavingGoal copyWith({
    String? goalId,
    String? userId,
    String? name,
    double? targetAmount,
    double? savedAmount,
    int? months,
    DateTime? createdAt,
    Map<String, GoalWalletSource>? walletSources,
    List<GoalDepositRecord>? deposits,
    bool? sourcesSynced,
  }) {
    return SavingGoal(
      goalId: goalId ?? this.goalId,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      targetAmount: targetAmount ?? this.targetAmount,
      savedAmount: savedAmount ?? this.savedAmount,
      months: months ?? this.months,
      createdAt: createdAt ?? this.createdAt,
      walletSources: walletSources ?? this.walletSources,
      deposits: deposits ?? this.deposits,
      sourcesSynced: sourcesSynced ?? this.sourcesSynced,
    );
  }

  double get percentComplete =>
      targetAmount == 0 ? 0 : (savedAmount / targetAmount).clamp(0, 1);

  double get monthlyRequired {
    if (months <= 0) return 0;
    final remaining = targetAmount - savedAmount;
    if (remaining <= 0) return 0;
    return remaining / months;
  }

  double get dailyRequired => monthlyRequired / 30;

  /// Đã có thông tin theo dõi nguồn ví (hoặc đã đồng bộ từ lịch sử giao dịch)
  bool get hasTrackedSources =>
      sourcesSynced || walletSources.isNotEmpty || deposits.isNotEmpty;

  /// Cần đồng bộ nguồn ví từ lịch sử giao dịch (dành cho dữ liệu cũ trước khi có trường walletSources)
  bool get needsSourceSync => savedAmount > 0 && !hasTrackedSources;

  /// Tổng số tiền đã nạp từ tất cả các nguồn ví được ghi nhận
  double get totalDepositedFromSources => walletSources.values
      .fold<double>(0.0, (sum, item) => sum + item.totalDeposited);

  /// Tổng số tiền hiện còn có thể rút từ tất cả các nguồn ví được ghi nhận
  double get totalWithdrawableFromSources => walletSources.values
      .fold<double>(0.0, (sum, item) => sum + item.withdrawableAmount);

  /// Phần số dư lịch sử không xác định được ví nguồn (nếu có dữ liệu cũ không có lịch sử giao dịch)
  double get unattributedSavedAmount =>
      (savedAmount - totalWithdrawableFromSources).clamp(0.0, double.infinity);

  /// Số tiền tối đa còn có thể rút của một ví nguồn cụ thể
  double withdrawableForWallet(String walletId) {
    return walletSources[walletId]?.withdrawableAmount ?? 0.0;
  }

  /// Tổng số tiền đã nạp của một ví nguồn cụ thể
  double totalDepositedForWallet(String walletId) {
    return walletSources[walletId]?.totalDeposited ?? 0.0;
  }

  /// Danh sách các nguồn ví hiện còn số dư có thể rút (> 0)
  List<GoalWalletSource> get withdrawableSources {
    final list = walletSources.values
        .where((s) => s.withdrawableAmount > 0)
        .toList();
    list.sort((a, b) => b.withdrawableAmount.compareTo(a.withdrawableAmount));
    return list;
  }

  /// Tất cả các nguồn ví đã từng nạp vào mục tiêu
  List<GoalWalletSource> get allOrderedSources {
    final list = walletSources.values
        .where((s) => s.totalDeposited > 0 || s.withdrawableAmount > 0)
        .toList();
    list.sort((a, b) {
      final cmp = b.withdrawableAmount.compareTo(a.withdrawableAmount);
      if (cmp != 0) return cmp;
      return b.totalDeposited.compareTo(a.totalDeposited);
    });
    return list;
  }

  factory SavingGoal.fromMap(Map<String, dynamic> map, String id) {
    final parsedSources = <String, GoalWalletSource>{};
    final rawSources = map['walletSources'];
    if (rawSources is Map) {
      rawSources.forEach((key, value) {
        if (value is Map) {
          final k = key.toString();
          final source = GoalWalletSource.fromMap(
            Map<String, dynamic>.from(value),
            k,
          );
          if (source.walletId.isNotEmpty) {
            parsedSources[source.walletId] = source;
          }
        }
      });
    } else if (rawSources is List) {
      for (final item in rawSources) {
        if (item is Map) {
          final source = GoalWalletSource.fromMap(
            Map<String, dynamic>.from(item),
          );
          if (source.walletId.isNotEmpty) {
            parsedSources[source.walletId] = source;
          }
        }
      }
    }

    final parsedDeposits = <GoalDepositRecord>[];
    final rawDeposits = map['deposits'];
    if (rawDeposits is List) {
      for (final item in rawDeposits) {
        if (item is Map) {
          parsedDeposits.add(
            GoalDepositRecord.fromMap(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    final savedAmt = _parseDouble(map['savedAmount']);
    final hasExplicitSync = map['sourcesSynced'] == true ||
        map.containsKey('walletSources') ||
        map.containsKey('deposits') ||
        savedAmt == 0;

    return SavingGoal(
      goalId: id,
      userId: map['userId']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      targetAmount: _parseDouble(map['targetAmount']),
      savedAmount: savedAmt,
      months: _parseInt(map['months'], defaultValue: 1),
      createdAt: _parseDate(map['createdAt']),
      walletSources: parsedSources,
      deposits: parsedDeposits,
      sourcesSynced: hasExplicitSync,
    );
  }

  static double _parseDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val) ?? 0.0;
    return 0.0;
  }

  static int _parseInt(dynamic val, {int defaultValue = 1}) {
    if (val == null) return defaultValue;
    if (val is int) return val;
    if (val is num) return val.toInt();
    if (val is String) return int.tryParse(val) ?? defaultValue;
    return defaultValue;
  }

  static DateTime _parseDate(dynamic val) {
    if (val == null) return DateTime.now();
    if (val is DateTime) return val;
    if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
    try {
      // Hỗ trợ Firestore Timestamp (có toDate())
      return (val as dynamic).toDate() as DateTime;
    } catch (_) {
      return DateTime.now();
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'name': name,
      'targetAmount': targetAmount,
      'savedAmount': savedAmount,
      'months': months,
      'createdAt': createdAt.toIso8601String(),
      'walletSources': {
        for (final entry in walletSources.entries)
          entry.key: entry.value.toMap(),
      },
      'deposits': deposits.map((d) => d.toMap()).toList(),
      'sourcesSynced': sourcesSynced,
    };
  }
}

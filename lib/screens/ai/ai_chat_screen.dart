import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import '../../l10n/app_localizations.dart';
import '../../models/category_model.dart';
import '../../models/monthly_financial_plan.dart';
import '../../services/ai_prompt_builder.dart';
import '../../services/firestore_service.dart';
import '../../services/ai_service.dart';
import '../../services/financial_chat_context_service.dart';
import '../../services/financial_context_revision_tracker.dart';
import '../../services/language_controller.dart';
import '../../utils/category_localization_helper.dart';
import '../../utils/constants.dart';
import '../../utils/formatters.dart';
import '../../widgets/app_snackbar.dart';
import '../management/budget_management_screen.dart';
import '../management/saving_goal_screen.dart';
import '../home/transaction_list_screen.dart';
import '../home/add_transaction_screen.dart';

/// Model tin nhắn trong phiên trò chuyện
class _ChatMessage {
  final String id;
  String text;
  final bool isUser;
  final DateTime timestamp;
  ChatInsightCardData? insightCard;
  final bool isError;
  final String? retryPrompt;

  _ChatMessage({
    String? id,
    required this.text,
    required this.isUser,
    DateTime? timestamp,
    this.insightCard,
    this.isError = false,
    this.retryPrompt,
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'text': text,
      'isUser': isUser,
      'timestamp': timestamp.toIso8601String(),
      'insightCard': insightCard?.toMap(),
      'isError': isError,
      'retryPrompt': retryPrompt,
    };
  }

  factory _ChatMessage.fromMap(Map<String, dynamic> map) {
    ChatInsightCardData? card;
    if (map['insightCard'] != null && map['insightCard'] is Map) {
      card = ChatInsightCardData.fromMap(
        Map<String, dynamic>.from(map['insightCard'] as Map),
      );
    }
    return _ChatMessage(
      id: map['id'] as String?,
      text: map['text'] as String? ?? '',
      isUser: map['isUser'] == true,
      timestamp: map['timestamp'] != null
          ? DateTime.tryParse(map['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
      insightCard: card,
      isError: map['isError'] == true,
      retryPrompt: map['retryPrompt'] as String?,
    );
  }
}

/// ============================================================
/// AI FINANCIAL ASSISTANT SCREEN (TRỢ LÝ AI TÀI CHÍNH CÁ NHÂN)
/// - Quản lý phiên trò chuyện (Conversation Session) bền vững trên Firestore
/// - Hiểu ngữ cảnh dữ liệu 90 ngày (Ví, Giao dịch, Ngân sách, Mục tiêu)
/// - Phản hồi đa cấp độ: Trả lời nhanh, Phân tích thu-chi, Tư vấn cắt giảm, Phản biện mục tiêu
/// - Actionable Insight Cards tương tác điều hướng trực tiếp
/// - Thanh 1 hàng gọn gồm 4-5 câu hỏi gợi ý động ưu tiên cảnh báo theo ngữ cảnh
/// ============================================================
class AiChatScreen extends StatefulWidget {
  final AiService? aiService;
  final FirestoreService? firestoreService;
  final FinancialChatContextService? contextService;
  final String? userIdOverride;

  const AiChatScreen({
    super.key,
    this.aiService,
    this.firestoreService,
    this.contextService,
    this.userIdOverride,
  });

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  late final AiService _aiService;
  late final FirestoreService _firestoreService;
  late final FinancialChatContextService _contextService;

  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _inputFocusNode = FocusNode();

  final List<_ChatMessage> _messages = [];
  FinancialChatContext? _financialContext;
  List<Category> _categories = [];
  bool _isLoadingContext = true;
  bool _isSending = false;

  // Quản lý Conversation Session
  String _currentSessionId = const Uuid().v4();
  String _currentSessionTitle =
      AppLocalizations.tr('ai_chat_new_session_title');
  String _lastLocaleCode = LanguageController.currentLocale.value.languageCode;

  // Trạng thái cuộn mượt mà & vị trí đọc tin nhắn
  bool _showScrollToBottom = false;

  String? get _currentUid {
    if (widget.userIdOverride != null) return widget.userIdOverride;
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  bool _isDefaultSessionTitle(String title) =>
      title == 'Cuộc trò chuyện mới' ||
      title == 'New conversation' ||
      title == 'Cuộc trò chuyện' ||
      title == 'Conversation';

  @override
  void initState() {
    super.initState();
    _aiService = widget.aiService ?? AiService();
    _firestoreService = widget.firestoreService ?? FirestoreService();
    _contextService = widget.contextService ??
        FinancialChatContextService(firestoreService: _firestoreService);
    LanguageController.currentLocale.addListener(_onLocaleChanged);
    _scrollController.addListener(_onScroll);
    _initChatData();
  }

  void _onLocaleChanged() {
    final nextCode = LanguageController.currentLocale.value.languageCode;
    if (nextCode == _lastLocaleCode || !mounted) return;
    _lastLocaleCode = nextCode;
    _refreshChatLocalization();
  }

  Future<void> _refreshChatLocalization() async {
    final uid = _currentUid;
    if (!mounted) return;
    if (_isDefaultSessionTitle(_currentSessionTitle)) {
      _currentSessionTitle = AppLocalizations.tr('ai_chat_new_session_title');
    }
    if (uid == null || uid.isEmpty) {
      if (!_messages.any((m) => m.isUser) && _messages.length == 1) {
        setState(() {
          _messages[0] = _ChatMessage(
            text: AppLocalizations.tr('ai_chat_sign_in_required'),
            isUser: false,
          );
        });
      }
      return;
    }

    try {
      final ctx = await _contextService.buildContext(uid);
      if (!mounted) return;
      setState(() {
        _financialContext = ctx;
        if (!_messages.any((m) => m.isUser)) {
          _setupInitialGreeting();
        }
      });
    } catch (_) {
      if (mounted && !_messages.any((m) => m.isUser)) {
        setState(() => _setupInitialGreeting());
      }
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final current = _scrollController.offset;
    final isFarFromBottom = (maxScroll - current) > 280;
    if (isFarFromBottom != _showScrollToBottom) {
      setState(() {
        _showScrollToBottom = isFarFromBottom;
      });
    }
  }

  @override
  void dispose() {
    LanguageController.currentLocale.removeListener(_onLocaleChanged);
    _scrollController.removeListener(_onScroll);
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  /// Khởi tạo dữ liệu: Tải ngữ cảnh tài chính và phiên trò chuyện gần nhất
  Future<void> _initChatData() async {
    final uid = _currentUid;
    if (uid == null || uid.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoadingContext = false;
          _messages.add(_ChatMessage(
            text: AppLocalizations.tr('ai_chat_sign_in_required'),
            isUser: false,
          ));
        });
      }
      return;
    }

    try {
      // 1. Tải ngữ cảnh tài chính định lượng và categories an toàn
      final results = await Future.wait<dynamic>([
        _contextService.buildContext(uid),
        _firestoreService.getCategoriesSafely(uid),
        _firestoreService.getUserChatSessions(uid),
      ]);

      if (mounted) {
        setState(() {
          _financialContext = results[0] as FinancialChatContext;
          _categories = results[1] as List<Category>;
          _isLoadingContext = false;
        });

        final sessions = results[2] as List<Map<String, dynamic>>;
        if (sessions.isNotEmpty) {
          // Khôi phục phiên trò chuyện gần nhất của người dùng
          final latest = sessions.first;
          _loadExistingSession(latest);
        } else {
          // Tạo phiên trò chuyện đầu tiên
          _setupInitialGreeting();
        }
      }
    } catch (e, stack) {
      debugPrint('Error loading financial chat context: $e\n$stack');
      if (mounted) {
        setState(() {
          _isLoadingContext = false;
          _setupInitialGreeting();
        });
      }
    }
  }

  /// Nạp dữ liệu một phiên trò chuyện cũ từ Firestore
  void _loadExistingSession(Map<String, dynamic> sessionData) {
    final rawMessages = sessionData['messages'] as List<dynamic>? ?? [];
    final loadedMessages = <_ChatMessage>[];

    for (final item in rawMessages) {
      if (item is Map) {
        final msg = _ChatMessage.fromMap(Map<String, dynamic>.from(item));
        if (!msg.isError) {
          loadedMessages.add(msg);
        }
      }
    }

    final rawTitle = (sessionData['title'] as String?)?.trim();
    final resolvedTitle = (rawTitle == null ||
            rawTitle.isEmpty ||
            _isDefaultSessionTitle(rawTitle))
        ? AppLocalizations.tr('ai_chat_session_default_title')
        : rawTitle;

    setState(() {
      _currentSessionId =
          sessionData['sessionId'] as String? ?? const Uuid().v4();
      _currentSessionTitle = resolvedTitle;
      _messages.clear();
      if (loadedMessages.isNotEmpty) {
        _messages.addAll(loadedMessages);
      } else {
        _setupInitialGreeting();
      }
    });

    // Phục hồi Conversation Context cho Gemini AI
    if (_financialContext != null && loadedMessages.isNotEmpty) {
      final messageMaps = loadedMessages.map((m) => m.toMap()).toList();
      _aiService.restoreChatHistory(
        contextData: _financialContext!.rawPromptContext,
        previousMessages: messageMaps,
      );
    }

    _scrollToBottom(animated: false);
  }

  /// Thiết lập lời chào và thẻ tóm tắt ban đầu cho phiên mới
  void _setupInitialGreeting() {
    _messages.clear();
    final ctx = _financialContext;

    if (ctx == null || ctx.isEmptyData) {
      _messages.add(_ChatMessage(
        text: AppLocalizations.tr('ai_chat_empty_greeting'),
        isUser: false,
        insightCard: ChatInsightCardData(
          type: ChatInsightCardType.emptyDataPrompt,
          title: AppLocalizations.tr('ai_chat_empty_card_title'),
          subtitle: AppLocalizations.tr('ai_chat_empty_card_sub'),
          primaryMetric: AppLocalizations.tr('ai_chat_empty_card_metric'),
          actionLabel: AppLocalizations.tr('ai_chat_empty_card_action'),
        ),
      ));
      return;
    }

    final greetingBuffer = StringBuffer();
    greetingBuffer.writeln(AppLocalizations.tr('ai_chat_greet_hello'));
    greetingBuffer.writeln(AppLocalizations.tr('ai_chat_greet_synced'));
    greetingBuffer.writeln('');
    greetingBuffer.writeln(AppLocalizations.tr('ai_chat_greet_summary_hdr'));
    greetingBuffer.writeln(AppLocalizations.tr('ai_chat_greet_income',
        params: {'amount': AppFormatters.compactCurrency(ctx.incomeThisMonth)}));
    greetingBuffer.writeln(AppLocalizations.tr('ai_chat_greet_expense',
        params: {
          'amount': AppFormatters.compactCurrency(ctx.expenseThisMonth)
        }));
    greetingBuffer.writeln(AppLocalizations.tr('ai_chat_greet_net', params: {
      'sign': ctx.netCashFlow >= 0 ? '+' : '',
      'amount': AppFormatters.compactCurrency(ctx.netCashFlow),
      'status': ctx.netCashFlow >= 0
          ? AppLocalizations.tr('ai_chat_surplus_word')
          : AppLocalizations.tr('ai_chat_deficit_word'),
    }));
    greetingBuffer.writeln(AppLocalizations.tr('ai_chat_greet_save_rate',
        params: {'pct': '${ctx.savingsRate}'}));

    if (ctx.overBudgets.isNotEmpty) {
      greetingBuffer.writeln('');
      greetingBuffer.writeln(AppLocalizations.tr('ai_chat_greet_over_warn',
          params: {'count': '${ctx.overBudgets.length}'}));
    }

    greetingBuffer.writeln('');
    greetingBuffer.writeln(AppLocalizations.tr('ai_chat_greet_footer'));

    ChatInsightCardData? initialCard;
    if (ctx.overBudgets.isNotEmpty) {
      final b = ctx.overBudgets.first;
      final cat = _categories.firstWhere(
        (c) => c.categoryId == b.categoryId,
        orElse: () => Category(
            categoryId: b.categoryId,
            userId: '',
            name: AppLocalizations.tr('ai_rep_default_cat'),
            type: 'expense',
            icon: '',
            color: 0),
      );
      initialCard = ChatInsightCardData(
        type: ChatInsightCardType.budgetOverrun,
        title: AppLocalizations.tr('ai_chat_budget_alert_title', params: {
          'category': CategoryLocalizationHelper.localizeName(cat.name),
        }),
        subtitle: AppLocalizations.tr('ai_chat_budget_over_sub'),
        primaryMetric: AppLocalizations.tr('ai_chat_budget_limit_metric',
            params: {'amount': AppFormatters.compactCurrency(b.limit)}),
        actionLabel: AppLocalizations.tr('ai_chat_view_budget_btn'),
        targetId: b.budgetId,
      );
    }

    _messages.add(_ChatMessage(
      text: greetingBuffer.toString(),
      isUser: false,
      insightCard: initialCard,
    ));
  }

  /// Tự động lưu phiên trò chuyện hiện tại vào Firestore
  /// (chỉ khi có ít nhất 1 tin nhắn từ user và luôn lọc bỏ các bubble lỗi tạm thời `isError == true`)
  Future<void> _saveCurrentSession() async {
    final uid = _currentUid;
    if (uid == null || uid.isEmpty || _messages.isEmpty) return;

    final persistableMessages = _messages.where((m) => !m.isError).toList();
    // Không lưu phiên rỗng nếu người dùng chưa tương tác gửi câu hỏi nào
    final hasUserMessage = persistableMessages.any((m) => m.isUser);
    if (!hasUserMessage) return;

    if (_isDefaultSessionTitle(_currentSessionTitle)) {
      final firstUserMsg = persistableMessages.firstWhere(
        (m) => m.isUser,
        orElse: () => _ChatMessage(text: '', isUser: false),
      );
      if (firstUserMsg.text.isNotEmpty) {
        _currentSessionTitle = firstUserMsg.text.length > 32
            ? '${firstUserMsg.text.substring(0, 32)}...'
            : firstUserMsg.text;
      }
    }

    final messageMaps = persistableMessages.map((m) => m.toMap()).toList();
    await _firestoreService.saveChatSession(
      userId: uid,
      sessionId: _currentSessionId,
      title: _currentSessionTitle,
      messages: messageMaps,
    );
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        if (animated) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        } else {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      }
    });
  }

  /// Định vị cuộn êm đến vị trí bắt đầu câu trả lời của AI để người dùng đọc tự nhiên từ đầu câu
  void _scrollToAiResponseStart(double anchorExtent) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final maxScroll = _scrollController.position.maxScrollExtent;
      final target = (anchorExtent - 12).clamp(0.0, maxScroll);
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  /// Gửi tin nhắn và nhận phản hồi dòng (Streaming) từ Trợ lý AI
  Future<void> _sendMessage(
    String text, {
    String? retryErrorMessageId,
  }) async {
    final trimmedText = text.trim();
    if (trimmedText.isEmpty || _isSending) return;

    final uid = _currentUid ?? '';

    // Ghi nhận vị trí cuối cùng trước khi thêm tin nhắn
    final double anchorBeforeSend = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;

    // Khi bấm "Thử lại", nếu bubble ngay trước bubble lỗi đã là câu hỏi của user cùng nội dung,
    // giữ nguyên bubble user đó để không nhân đôi câu hỏi trên giao diện.
    bool shouldAddUserBubble = true;
    if (retryErrorMessageId != null) {
      final errIdx = _messages.indexWhere((m) => m.id == retryErrorMessageId);
      if (errIdx > 0 &&
          _messages[errIdx - 1].isUser &&
          _messages[errIdx - 1].text.trim() == trimmedText) {
        shouldAddUserBubble = false;
      }
    }

    setState(() {
      if (shouldAddUserBubble) {
        _messages.add(_ChatMessage(text: trimmedText, isUser: true));
      }
      _isSending = true;
    });
    _inputController.clear();
    _scrollToBottom();

    final aiMessage = _ChatMessage(
      text: '',
      isUser: false,
    );
    bool messageAdded = false;
    final responseBuffer = StringBuffer();

    try {
      // Đảm bảo dữ liệu tài chính luôn được đồng bộ mới nhất khi có thay đổi
      // ở các màn hình khác (transactions, budgets, categories, savingGoals, monthly_plans)
      // hoặc khi trạng thái trước đó là chưa có dữ liệu.
      final bool needsContextRefresh = _financialContext == null ||
          _financialContext!.isEmptyData ||
          _financialContext!.mutationVersion !=
              FinancialContextRevisionTracker.localMutationVersion;

      if (needsContextRefresh && uid.isNotEmpty) {
        final refreshed = await Future.wait<dynamic>([
          _contextService.buildContext(uid),
          _firestoreService.getCategoriesSafely(uid),
        ]);
        if (mounted) {
          setState(() {
            _financialContext = refreshed[0] as FinancialChatContext;
            _categories = refreshed[1] as List<Category>;
          });
        }
      }

      final contextData = _financialContext?.rawPromptContext ??
          AppLocalizations.tr('ai_chat_no_fin_data_ctx');

      // Sử dụng streaming để người dùng nhìn thấy phản hồi tức thì
      await for (final chunk in _aiService.chatWithFinancialDataStream(
        userQuestion: trimmedText,
        contextData: contextData,
        onStreamReset: () {
          // Reset sạch buffer nếu model trước đứt giữa chừng và chuyển sang fallback
          responseBuffer.clear();
          if (mounted && messageAdded) {
            setState(() {
              aiMessage.text = '';
            });
          }
        },
      )) {
        if (!mounted) return;
        responseBuffer.write(chunk);

        if (!messageAdded) {
          final double anchorBeforeAi = _scrollController.hasClients
              ? _scrollController.position.maxScrollExtent
              : anchorBeforeSend;

          setState(() {
            _isSending = false; // Tắt typing indicator
            if (retryErrorMessageId != null) {
              _messages.removeWhere((m) => m.id == retryErrorMessageId);
            }
            _messages.add(aiMessage);
            messageAdded = true;
          });

          // Cuộn đến đầu câu trả lời của AI
          _scrollToAiResponseStart(anchorBeforeAi);
        }

        setState(() {
          aiMessage.text = responseBuffer.toString();
        });
      }

      // Chuẩn hóa số tiền sau khi nhận đủ toàn bộ nội dung stream (VD: 5000000đ -> 5.000.000đ)
      final fullReply = AiPromptBuilder.formatCurrencyNumbersInText(
        responseBuffer.toString(),
      );

      // Nhận diện Action Card dựa trên toàn bộ ngữ cảnh hỏi & đáp
      ChatInsightCardData? card;
      if (_financialContext != null) {
        card = _contextService.detectInsightCard(
          question: trimmedText,
          answer: fullReply,
          context: _financialContext!,
          categories: _categories,
        );
      }

      if (mounted) {
        setState(() {
          if (retryErrorMessageId != null) {
            _messages.removeWhere((m) => m.id == retryErrorMessageId);
          }
          if (!messageAdded && fullReply.isNotEmpty) {
            _messages.add(aiMessage);
            messageAdded = true;
          }
          aiMessage.text = fullReply;
          aiMessage.insightCard = card;
        });
      }

      // Tự động lưu phiên trò chuyện sau khi hoàn thành
      await _saveCurrentSession();
    } catch (e, stackTrace) {
      debugPrint('AI Chat Error: $e');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        final isNoNet = AiService.isNoNetworkException(e);
        final errorMessage = isNoNet
            ? AppLocalizations.tr('ai_chat_err_no_net')
            : AppLocalizations.tr('ai_chat_err_generic');
        setState(() {
          // Gỡ bỏ bubble AI nửa vời nếu stream đứt giữa chừng rồi fallback cũng lỗi
          if (messageAdded) {
            _messages.remove(aiMessage);
          }
          // Thay thế bubble lỗi cũ (nếu đang bấm Thử lại) để tránh trùng lặp
          if (retryErrorMessageId != null) {
            _messages.removeWhere((m) => m.id == retryErrorMessageId);
          }
          _messages.add(_ChatMessage(
            text: errorMessage,
            isUser: false,
            isError: true,
            retryPrompt: trimmedText,
          ));
        });
        _scrollToBottom();
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  /// Tạo cuộc trò chuyện mới
  void _createNewChatSession({bool showSnack = true}) async {
    final hasUserMessage = _messages.any((m) => m.isUser);
    if (hasUserMessage) {
      await _saveCurrentSession();
    }
    _aiService.resetChatSession();
    setState(() {
      _currentSessionId = const Uuid().v4();
      _currentSessionTitle = AppLocalizations.tr('ai_chat_new_session_title');
      _setupInitialGreeting();
    });
    if (mounted && showSnack) {
      AppSnackbar.show(context, AppLocalizations.tr('ai_chat_new_opened_snack'));
    }
  }

  /// Xem và chuyển đổi các phiên trò chuyện đã lưu trong lịch sử
  void _showChatHistoryModal() async {
    final uid = _currentUid;
    if (uid == null || uid.isEmpty) return;

    final sessions = await _firestoreService.getUserChatSessions(uid);

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: context.appCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(Icons.history_rounded,
                              color: AppColors.primary, size: 22),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              context.tr('ai_chat_history_title'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.bold,
                                color: context.appTextPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (sessions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        context.tr('ai_chat_no_sessions'),
                        style: TextStyle(
                            color: context.appTextSecondary, fontSize: 13.5),
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: sessions.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, color: context.appBorder),
                      itemBuilder: (context, index) {
                        final s = sessions[index];
                        final sId = s['sessionId'] as String? ?? '';
                        final rawTitle = (s['title'] as String?)?.trim();
                        final sTitle = (rawTitle == null ||
                                rawTitle.isEmpty ||
                                _isDefaultSessionTitle(rawTitle))
                            ? AppLocalizations.tr(
                                'ai_chat_session_default_title')
                            : rawTitle;
                        final sUpdated = s['updatedAt'] as String? ?? '';
                        final isCurrent = sId == _currentSessionId;

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? AppColors.primary.withValues(alpha: 0.15)
                                  : context.appInputFill,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 18,
                              color: isCurrent
                                  ? AppColors.primary
                                  : context.appTextSecondary,
                            ),
                          ),
                          title: Text(
                            sTitle,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight:
                                  isCurrent ? FontWeight.bold : FontWeight.w500,
                              color: isCurrent
                                  ? AppColors.primary
                                  : context.appTextPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            sUpdated.isNotEmpty
                                ? (DateTime.tryParse(sUpdated) != null
                                    ? AppFormatters.dateTime(
                                        DateTime.parse(sUpdated))
                                    : sUpdated)
                                : '',
                            style: TextStyle(
                                fontSize: 11.5,
                                color: context.appTextSecondary),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isCurrent)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  margin: const EdgeInsets.only(right: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(ctx.tr('ai_chat_current_badge'),
                                      style: const TextStyle(
                                          fontSize: 10,
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.bold)),
                                ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded,
                                    size: 19, color: AppColors.expense),
                                tooltip: ctx.tr('ai_chat_delete_session_tip'),
                                onPressed: () async {
                                  final sheetNav = Navigator.of(ctx);
                                  final confirm = await showDialog<bool>(
                                    context: ctx,
                                    builder: (dCtx) => AlertDialog(
                                      backgroundColor: context.appCard,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(16)),
                                      title: Text(
                                          dCtx.tr(
                                              'ai_chat_delete_session_dlg_title'),
                                          style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold)),
                                      content: Text(
                                        dCtx.tr(
                                            'ai_chat_delete_session_dlg_body'),
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                      actions: [
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(dCtx, false),
                                            child:
                                                Text(dCtx.tr('common_cancel'))),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  AppColors.expense),
                                          onPressed: () =>
                                              Navigator.pop(dCtx, true),
                                          child: Text(dCtx.tr('common_delete'),
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ),
                                  );

                                  if (confirm == true) {
                                    await _firestoreService.deleteChatSession(
                                        uid, sId);
                                    sheetNav.pop();
                                    if (isCurrent) {
                                      _createNewChatSession(showSnack: false);
                                    }
                                    if (!mounted) return;
                                    AppSnackbar.show(
                                        this.context,
                                        AppLocalizations.tr(
                                            'ai_chat_session_deleted_snack'));
                                  }
                                },
                              ),
                            ],
                          ),
                          onTap: () async {
                            Navigator.pop(ctx);
                            if (!isCurrent) {
                              if (_messages.any((m) => m.isUser)) {
                                await _saveCurrentSession();
                              }
                              if (!mounted) return;
                              _loadExistingSession(s);
                              final shortTitle = sTitle.length > 25
                                  ? '${sTitle.substring(0, 25)}...'
                                  : sTitle;
                              AppSnackbar.show(
                                  this.context,
                                  AppLocalizations.tr(
                                      'ai_chat_session_opened_snack',
                                      params: {'title': shortTitle}));
                            }
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Xác nhận xóa cuộc trò chuyện hiện tại
  void _confirmDeleteCurrentSession() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.appCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.delete_outline_rounded,
                color: AppColors.expense, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(ctx.tr('ai_chat_delete_chat_title'),
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: context.appTextPrimary)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ctx.tr('ai_chat_delete_chat_body'),
              style: TextStyle(fontSize: 13.5, color: context.appTextSecondary),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shield_outlined,
                      size: 16, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      ctx.tr('ai_chat_delete_chat_safe_note'),
                      style: TextStyle(
                          fontSize: 12,
                          color: context.appTextPrimary,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ctx.tr('common_cancel'),
                style: TextStyle(color: context.appTextSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.expense),
            onPressed: () async {
              Navigator.pop(ctx);
              final uid = _currentUid;
              if (uid != null && uid.isNotEmpty) {
                await _firestoreService.deleteChatSession(
                    uid, _currentSessionId);
              }
              _createNewChatSession(showSnack: false);
              if (mounted) {
                AppSnackbar.show(
                    context, AppLocalizations.tr('ai_chat_chat_deleted_snack'));
              }
            },
            child: Text(ctx.tr('common_delete'),
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// Nút ⚡ Phân tích nhanh - Mở sheet gợi ý các phân tích chuyên sâu
  void _showQuickAnalysisSheet() {
    final quickQueries = [
      {
        'icon': '📊',
        'title': context.tr('ai_chat_qa_1_title'),
        'prompt': context.tr('ai_chat_qa_1_prompt'),
      },
      {
        'icon': '⚠️',
        'title': context.tr('ai_chat_qa_2_title'),
        'prompt': context.tr('ai_chat_qa_2_prompt'),
      },
      {
        'icon': '🎯',
        'title': context.tr('ai_chat_qa_3_title'),
        'prompt': context.tr('ai_chat_qa_3_prompt'),
      },
      {
        'icon': '💡',
        'title': context.tr('ai_chat_qa_4_title'),
        'prompt': context.tr('ai_chat_qa_4_prompt'),
      },
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: context.appCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(Icons.bolt_rounded,
                              color: AppColors.primary, size: 24),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              context.tr('ai_chat_qa_sheet_title'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: context.appTextPrimary),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ...quickQueries.map((q) {
                  return ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Text(q['icon']!,
                          style: const TextStyle(fontSize: 16)),
                    ),
                    title: Text(
                      q['title']!,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: context.appTextPrimary),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios_rounded,
                        size: 14, color: AppColors.primary),
                    onTap: () {
                      Navigator.pop(ctx);
                      _sendMessage(q['prompt']!);
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    AppSnackbar.show(context, context.tr('ai_chat_copied_snack'));
  }

  void _showAiAssistantInfo() {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.appCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.auto_awesome,
                          color: AppColors.primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        context.tr('ai_chat_info_title'),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: context.appTextPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildInfoRow(
                  Icons.calculate_outlined,
                  context.tr('ai_chat_info_1_title'),
                  context.tr('ai_chat_info_1_desc'),
                ),
                const SizedBox(height: 12),
                _buildInfoRow(
                  Icons.psychology_outlined,
                  context.tr('ai_chat_info_2_title'),
                  context.tr('ai_chat_info_2_desc'),
                ),
                const SizedBox(height: 12),
                _buildInfoRow(
                  Icons.forum_outlined,
                  context.tr('ai_chat_info_3_title'),
                  context.tr('ai_chat_info_3_desc'),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(context.tr('ai_chat_understood'),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(IconData icon, String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.appTextPrimary),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                    fontSize: 13,
                    color: context.appTextSecondary,
                    height: 1.35),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _handleInsightCardAction(ChatInsightCardData card) async {
    switch (card.type) {
      case ChatInsightCardType.budgetOverrun:
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BudgetManagementScreen()),
        );
        break;
      case ChatInsightCardType.savingGoalProgress:
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SavingGoalScreen()),
        );
        break;
      case ChatInsightCardType.cashFlowSnapshot:
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TransactionListScreen()),
        );
        break;
      case ChatInsightCardType.emptyDataPrompt:
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AddTransactionScreen()),
        );
        break;
      case ChatInsightCardType.none:
        return;
    }

    // Làm mới ngữ cảnh nếu người dùng vừa thao tác dữ liệu
    final uid = _currentUid;
    if (uid != null && uid.isNotEmpty && mounted) {
      final updatedContext = await _contextService.buildContext(uid);
      if (mounted) {
        setState(() => _financialContext = updatedContext);
      }
    }
  }

  String _resolveAppBarStatusLabel(BuildContext context) {
    if (_isLoadingContext) {
      return context.tr('ai_chat_status_syncing');
    }
    final ctx = _financialContext;
    if (ctx == null || ctx.isEmptyData) {
      return context.tr('ai_chat_status_empty');
    }
    if (!ctx.hasSufficientData ||
        ctx.dataTier == DataSufficiencyTier.preliminary) {
      return context.tr('ai_chat_status_limited');
    }
    return context.tr('ai_chat_status_90d');
  }

  Color _resolveAppBarStatusColor(BuildContext context) {
    if (_isLoadingContext) {
      return AppColors.warning;
    }
    final ctx = _financialContext;
    if (ctx == null || ctx.isEmptyData) {
      return context.appTextSecondary;
    }
    if (!ctx.hasSufficientData ||
        ctx.dataTier == DataSufficiencyTier.preliminary) {
      return AppColors.warning;
    }
    return const Color(0xFF10B981);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  itemCount: _messages.length + (_isSending ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (_isSending && index == _messages.length) {
                      return const _TypingIndicator();
                    }
                    final msg = _messages[index];
                    return _ChatBubble(
                      message: msg,
                      onCopy: () => _copyToClipboard(msg.text),
                      onRetry: msg.retryPrompt != null
                          ? () => _sendMessage(
                                msg.retryPrompt!,
                                retryErrorMessageId: msg.id,
                              )
                          : null,
                      onCardAction: msg.insightCard != null
                          ? () => _handleInsightCardAction(msg.insightCard!)
                          : null,
                    );
                  },
                ),
              ),
              _buildDynamicPromptsList(),
              _buildInputBar(),
            ],
          ),
          if (_showScrollToBottom)
            Positioned(
              bottom: 112,
              right: 16,
              child: _buildScrollToBottomButton(),
            ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final canPop = Navigator.canPop(context);
    final statusColor = _resolveAppBarStatusColor(context);
    final statusLabel = _resolveAppBarStatusLabel(context);

    return AppBar(
      elevation: 0,
      backgroundColor: context.appCard,
      surfaceTintColor: Colors.transparent,
      automaticallyImplyLeading: false,
      leading: canPop
          ? IconButton(
              icon: Icon(Icons.arrow_back, color: context.appTextPrimary),
              onPressed: () => Navigator.pop(context),
            )
          : null,
      titleSpacing: canPop ? 0 : 16,
      title: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome,
                color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.tr('ai_chat_appbar_title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: context.appTextPrimary,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      key: const ValueKey('ai_chat_status_dot'),
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        statusLabel,
                        key: const ValueKey('ai_chat_status_label'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: context.appTextSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.bolt_rounded),
          tooltip: context.tr('ai_chat_quick_tip'),
          color: AppColors.primary,
          onPressed: _isSending ? null : _showQuickAnalysisSheet,
        ),
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert_rounded, color: context.appTextSecondary),
          tooltip: context.tr('ai_chat_options_tip'),
          color: context.appCard,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onSelected: (value) {
            if (value == 'new') {
              _createNewChatSession();
            } else if (value == 'history') {
              _showChatHistoryModal();
            } else if (value == 'delete') {
              _confirmDeleteCurrentSession();
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'new',
              child: Row(
                children: [
                  const Icon(Icons.add_comment_outlined,
                      size: 18, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(context.tr('ai_chat_menu_new'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5)),
                  ),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'history',
              child: Row(
                children: [
                  const Icon(Icons.history_rounded,
                      size: 18, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(context.tr('ai_chat_menu_history'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5)),
                  ),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  const Icon(Icons.delete_outline_rounded,
                      size: 18, color: AppColors.expense),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(context.tr('ai_chat_menu_delete'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13.5, color: AppColors.expense)),
                  ),
                ],
              ),
            ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.info_outline_rounded),
          tooltip: context.tr('ai_chat_info_tip'),
          color: context.appTextSecondary,
          onPressed: _showAiAssistantInfo,
        ),
      ],
    );
  }

  /// Nút cuộn xuống tin nhắn mới nhất xuất hiện khi người dùng cuộn lên trên
  Widget _buildScrollToBottomButton() {
    return Material(
      color: Colors.transparent,
      elevation: 4,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _scrollToBottom(animated: true),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: context.appCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: context.appBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.arrow_downward_rounded,
                  size: 16, color: AppColors.primary),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  context.tr('ai_chat_latest_btn'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: context.appTextPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Thanh 1 hàng gọn gồm 4-5 câu hỏi gợi ý động thông minh nhất theo ngữ cảnh
  /// (ưu tiên chip cảnh báo đỏ khi vượt ngân sách / dòng tiền âm / chi đột biến).
  Widget _buildDynamicPromptsList() {
    final allPrompts = _financialContext?.dynamicPrompts ??
        [
          DynamicPromptChip(
              label: context.tr('ai_chat_chip_1'),
              category: 'featured',
              icon: '🔥'),
          DynamicPromptChip(
              label: context.tr('ai_chat_chip_4'),
              category: 'overview'),
          DynamicPromptChip(
              label: context.tr('ai_chat_chip_6'),
              category: 'expense'),
          DynamicPromptChip(
              label: context.tr('ai_chat_chip_8'),
              category: 'budget'),
          DynamicPromptChip(
              label: context.tr('ai_chat_chip_9'),
              category: 'saving'),
        ];

    final compactPrompts = FinancialChatContextService.selectCompactPrompts(
      allPrompts,
      maxCount: 5,
      hasNearLimitBudgets:
          _financialContext?.nearLimitBudgets.isNotEmpty ?? false,
    );

    if (compactPrompts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      key: const ValueKey('ai_chat_compact_prompts_bar'),
      height: 40,
      margin: const EdgeInsets.only(top: 6, bottom: 6),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: compactPrompts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final prompt = compactPrompts[i];
          final isAlert = prompt.isAlert;

          return ActionChip(
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isAlert) ...[
                  const Icon(Icons.warning_amber_rounded,
                      size: 14, color: AppColors.expense),
                  const SizedBox(width: 4),
                ] else if (prompt.icon != null) ...[
                  Text(prompt.icon!, style: const TextStyle(fontSize: 12)),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    prompt.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color:
                          isAlert ? AppColors.expense : context.appTextPrimary,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor:
                isAlert ? AppColors.expenseBackground : context.appCard,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: isAlert
                    ? AppColors.expense.withValues(alpha: 0.5)
                    : context.appBorder,
              ),
            ),
            onPressed: _isSending ? null : () => _sendMessage(prompt.label),
          );
        },
      ),
    );
  }

  /// Thanh nhập tin nhắn bên dưới
  Widget _buildInputBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        decoration: BoxDecoration(
          color: context.appCard,
          border: Border(top: BorderSide(color: context.appBorder)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 110),
                decoration: BoxDecoration(
                  color: context.appInputFill,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: context.appBorder),
                ),
                child: TextField(
                  controller: _inputController,
                  focusNode: _inputFocusNode,
                  style: TextStyle(fontSize: 14, color: context.appTextPrimary),
                  decoration: InputDecoration(
                    hintText: context.tr('ai_chat_input_hint'),
                    hintStyle: TextStyle(
                        color: context.appTextSecondary, fontSize: 13.5),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) {
                    final text = _inputController.text;
                    _sendMessage(text);
                  },
                ),
              ),
            ),
            const SizedBox(width: 10),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color:
                    _isSending ? context.appTextSecondary : AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: _isSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded,
                        color: Colors.white, size: 20),
                onPressed: _isSending
                    ? null
                    : () {
                        final text = _inputController.text;
                        _sendMessage(text);
                      },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ============================================================
/// BONG BÓNG TIN NHẮN (CHAT BUBBLE)
/// Hỗ trợ Markdown, RichText và Thẻ Hành Động Tương Tác
/// ============================================================
class _ChatBubble extends StatelessWidget {
  final _ChatMessage message;
  final VoidCallback onCopy;
  final VoidCallback? onRetry;
  final VoidCallback? onCardAction;

  const _ChatBubble({
    required this.message,
    required this.onCopy,
    this.onRetry,
    this.onCardAction,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final isError = message.isError;

    if (isUser) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.78),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(4),
                  ),
                ),
                child: Text(
                  message.text,
                  style: const TextStyle(
                    color: Colors.white,
                    height: 1.4,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // AI Message
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            margin: const EdgeInsets.only(top: 2, right: 10),
            decoration: BoxDecoration(
              color: isError
                  ? AppColors.expense.withValues(alpha: 0.12)
                  : AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isError ? Icons.error_outline : Icons.auto_awesome,
              color: isError ? AppColors.expense : AppColors.primary,
              size: 18,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.85),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color:
                        isError ? AppColors.expenseBackground : context.appCard,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(18),
                      bottomLeft: Radius.circular(18),
                      bottomRight: Radius.circular(18),
                    ),
                    border: Border.all(
                      color: isError
                          ? AppColors.expense.withValues(alpha: 0.4)
                          : context.appBorder,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FormattedMarkdownText(
                        text: message.text,
                        isError: isError,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (isError && onRetry != null)
                            InkWell(
                              onTap: onRetry,
                              borderRadius: BorderRadius.circular(4),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.refresh,
                                        size: 14, color: AppColors.expense),
                                    const SizedBox(width: 4),
                                    Text(context.tr('common_retry'),
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.expense,
                                            fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ),
                          if (!isError)
                            InkWell(
                              onTap: onCopy,
                              borderRadius: BorderRadius.circular(4),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 2),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.copy_rounded,
                                        size: 13,
                                        color: context.appTextSecondary),
                                    const SizedBox(width: 4),
                                    Text(
                                      context.tr('ai_chat_copy_btn'),
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: context.appTextSecondary),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (message.insightCard != null) ...[
                  const SizedBox(height: 8),
                  _ActionableInsightCard(
                    card: message.insightCard!,
                    onAction: onCardAction,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ============================================================
/// ACTIONABLE INSIGHT CARD
/// Thẻ hành động tương tác hiển thị trực tiếp trong dòng chat
/// ============================================================
class _ActionableInsightCard extends StatelessWidget {
  final ChatInsightCardData card;
  final VoidCallback? onAction;

  const _ActionableInsightCard({
    required this.card,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    Color themeColor;
    Color bgColor;
    IconData icon;

    switch (card.type) {
      case ChatInsightCardType.budgetOverrun:
        if (card.isAlert) {
          themeColor = AppColors.expense;
          bgColor = AppColors.expenseBackground;
          icon = Icons.warning_amber_rounded;
        } else {
          themeColor = AppColors.income;
          bgColor = AppColors.incomeBackground;
          icon = Icons.check_circle_outline_rounded;
        }
        break;
      case ChatInsightCardType.savingGoalProgress:
        themeColor = AppColors.income;
        bgColor = AppColors.incomeBackground;
        icon = Icons.savings_outlined;
        break;
      case ChatInsightCardType.cashFlowSnapshot:
        themeColor = AppColors.primary;
        bgColor = AppColors.aiBackgroundLight;
        icon = Icons.account_balance_wallet_outlined;
        break;
      case ChatInsightCardType.emptyDataPrompt:
        themeColor = AppColors.primary;
        bgColor = AppColors.aiBackgroundLight;
        icon = Icons.add_circle_outline_rounded;
        break;
      case ChatInsightCardType.none:
        return const SizedBox.shrink();
    }

    return Container(
      constraints:
          BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: themeColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: themeColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 16, color: themeColor),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  card.title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: context.appTextPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            card.subtitle,
            style: TextStyle(
                fontSize: 12, color: context.appTextSecondary, height: 1.3),
          ),
          const SizedBox(height: 8),
          if (card.progressPercent != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: card.progressPercent!.clamp(0.0, 1.0),
                backgroundColor: context.appBorder,
                color: themeColor,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  card.primaryMetric,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: themeColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 145),
                child: InkWell(
                  onTap: onAction,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: themeColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            card.actionLabel,
                            maxLines: 1,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_forward_ios_rounded,
                              size: 10, color: Colors.white),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// ============================================================
/// PARSER VĂN BẢN MARKDOWN TỐI ƯU CHO GIAO DIỆN CHAT FINTECH
/// Hỗ trợ Header, Bullet Points, Bold/Italic TextSpans
/// ============================================================
class _FormattedMarkdownText extends StatelessWidget {
  final String text;
  final bool isError;

  const _FormattedMarkdownText({
    required this.text,
    this.isError = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isError) {
      return Text(
        text,
        style: const TextStyle(
          color: AppColors.expense,
          fontSize: 13.5,
          height: 1.4,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    final lines = text.split('\n');
    final List<Widget> widgets = [];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trimRight();
      if (line.isEmpty) {
        widgets.add(const SizedBox(height: 6));
        continue;
      }

      // 1. Tiêu đề H2 hoặc H3
      if (line.startsWith('### ') || line.startsWith('## ')) {
        final headingText = line.replaceFirst(RegExp(r'^#{2,3}\s*'), '');
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 4),
          child: Text(
            headingText,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.bold,
              color: context.appTextPrimary,
            ),
          ),
        ));
        continue;
      }

      // 2. Dấu đầu dòng Bullet (• hoặc - hoặc *)
      final bulletMatch = RegExp(r'^([•\-\*])\s+(.*)$').firstMatch(line);
      if (bulletMatch != null) {
        final content = bulletMatch.group(2) ?? '';
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 5,
                height: 5,
                margin: const EdgeInsets.only(top: 7, right: 8),
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
              Expanded(
                child: _buildRichSpanText(context, content),
              ),
            ],
          ),
        ));
        continue;
      }

      // 3. Danh sách có số (1. 2. 3.)
      final numberMatch = RegExp(r'^(\d+)\.\s+(.*)$').firstMatch(line);
      if (numberMatch != null) {
        final numStr = numberMatch.group(1) ?? '1';
        final content = numberMatch.group(2) ?? '';
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$numStr. ',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              Expanded(
                child: _buildRichSpanText(context, content),
              ),
            ],
          ),
        ));
        continue;
      }

      // 4. Dòng văn bản bình thường (có thể chứa **bold**)
      widgets.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: _buildRichSpanText(context, line),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _buildRichSpanText(BuildContext context, String content) {
    final spans = <TextSpan>[];
    final regExp = RegExp(r'(\*\*[^*]+\*\*|\*[^*]+\*)');
    int lastMatchEnd = 0;

    for (final match in regExp.allMatches(content)) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(
          text: content.substring(lastMatchEnd, match.start),
          style: TextStyle(
            color: context.appTextPrimary,
            fontSize: 13.5,
            height: 1.45,
          ),
        ));
      }

      final matchedStr = match.group(0)!;
      if (matchedStr.startsWith('**') && matchedStr.endsWith('**')) {
        spans.add(TextSpan(
          text: matchedStr.substring(2, matchedStr.length - 2),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: context.appTextPrimary,
            fontSize: 13.5,
            height: 1.45,
          ),
        ));
      } else if (matchedStr.startsWith('*') && matchedStr.endsWith('*')) {
        spans.add(TextSpan(
          text: matchedStr.substring(1, matchedStr.length - 1),
          style: TextStyle(
            fontStyle: FontStyle.italic,
            color: context.appTextPrimary,
            fontSize: 13.5,
            height: 1.45,
          ),
        ));
      }

      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < content.length) {
      spans.add(TextSpan(
        text: content.substring(lastMatchEnd),
        style: TextStyle(
          color: context.appTextPrimary,
          fontSize: 13.5,
          height: 1.45,
        ),
      ));
    }

    return RichText(
      text: TextSpan(children: spans),
    );
  }
}

/// Typing indicator 3 chấm hoạt họa mượt mà
class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            margin: const EdgeInsets.only(top: 2, right: 10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome,
                color: AppColors.primary, size: 18),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: context.appCard,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
              border: Border.all(color: context.appBorder),
            ),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (_, __) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (i) {
                    final delay = i / 3;
                    final offset = ((_controller.value + delay) % 1.0);
                    final dy = offset < 0.5
                        ? -3.5 * (offset / 0.5)
                        : -3.5 * (1 - (offset - 0.5) / 0.5);
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Transform.translate(
                        offset: Offset(0, dy),
                        child: Container(
                          width: 6.5,
                          height: 6.5,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

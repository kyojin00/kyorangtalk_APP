import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../shared/widgets/skeleton_widget.dart';
import '../../friends/screens/friends_screen.dart';
import '../../reports/widgets/report_dialog.dart';
import '../models/chat_room_model.dart';
import '../models/message_model.dart';
import '../providers/chat_provider.dart';
import '../providers/reaction_provider.dart';
import '../services/plan_service.dart';
import '../services/pending_message_store.dart';
import '../services/draft_store.dart';
import 'multi_image_viewer_screen.dart';
import 'room_gallery_screen.dart';
import 'room_memory_screen.dart';
import '../../profile/screens/user_profile_screen.dart';
import '../services/audio_service.dart';
import '../utils/file_helper.dart';
import '../utils/multi_image_helper.dart';
import '../widgets/voice_record_screen.dart';
import '../widgets/attachment_menu.dart';
import '../widgets/game_select_sheet.dart';
import '../widgets/chat_message_bubble.dart';
import '../widgets/chat_blocked_banner.dart';
import '../widgets/chat_app_bar.dart';
import '../widgets/chat_room_sheets.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/chat_pinned_reply.dart';
import '../widgets/reaction_picker_bar.dart';
import '../widgets/summary_banner.dart';
import '../widgets/smart_reply_bar.dart';
import '../widgets/plan_card_widget.dart';
import '../widgets/failed_message_bubble.dart';
import '../../polls/widgets/create_poll_sheet.dart';

class ChatRoomScreen extends ConsumerStatefulWidget {
  final ChatRoomModel room;
  const ChatRoomScreen({super.key, required this.room});

  @override
  ConsumerState<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends ConsumerState<ChatRoomScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  final _myId = Supabase.instance.client.auth.currentUser!.id;

  bool _sending = false;
  bool _searchMode = false;
  String _searchQuery = '';
  int _searchIndex = 0;
  List<int> _searchResults = [];
  MessageModel? _replyTo;
  bool _initialScrolled = false;
  String? _pinnedMessage;
  bool _isMuted = false;
  bool _disposed = false;
  bool _summaryDismissed = false;

  // ⭐ Summary 활성화 임계값 (D)
  static const int kSummaryMinUnread = 5;

  String? _smartReplyDismissedFor;
  bool _inputIsEmpty = true;

  final Map<String, PlanModel> _detectedPlans = <String, PlanModel>{};
  final Set<String> _planExtractInProgress = <String>{};

  bool _isPaginating = false;
  bool _noMoreMessages = false;

  double? _lockedScrollPos;
  bool _scrollLocked = false;

  bool? _isBlocked;
  bool? _isBlockedByPartner;
  String? _friendStatus;
  bool _friendRequestSending = false;

  RealtimeChannel? _blockChannel;

  final Map<String, GlobalKey> _messageKeys = {};
  List<MessageModel>? _lastMessages;
  List<MessageGroup> _cachedGroups = [];

  // ⭐ 캐싱 (C): build 안에서 매번 정렬/필터하지 않도록
  List<MessageModel> _sortedMessages = const [];
  List<String> _recentContextCache = const [];

  // 실패한 메시지 (영구 저장)
  List<PendingMessage> _failedMessages = [];
  final Set<String> _retryingIds = <String>{};

  // Draft 자동 저장용 디바운서
  Timer? _draftSaveDebouncer;

  // ⭐ markAllRead debounce (B)
  Timer? _markReadDebouncer;

  bool get _isStatusLoaded =>
      _isBlocked != null &&
      _isBlockedByPartner != null &&
      _friendStatus != null;

  @override
  void initState() {
    super.initState();
    currentOpenRoomId = widget.room.roomId;
    _pinnedMessage = widget.room.pinnedMessage;

    // 진입 시 첫 호출은 즉시 (그 이후는 debounce)
    _markAllRead();

    _loadMuteStatus();
    _loadAllStatus();
    _listenBlockChanges();
    _loadFailedMessages();
    _loadDraft();

    _inputController.addListener(_onInputChanged);

    _focusNode.addListener(() {
      if (_focusNode.hasFocus && _isNearBottom()) {
        Future.delayed(const Duration(milliseconds: 300), _animateToBottom);
      }
    });

    _scrollController.addListener(_handleScroll);
  }

  void _onInputChanged() {
    final text = _inputController.text;
    final isEmpty = text.trim().isEmpty;
    if (isEmpty != _inputIsEmpty) {
      setState(() => _inputIsEmpty = isEmpty);
    }

    _draftSaveDebouncer?.cancel();
    _draftSaveDebouncer = Timer(const Duration(milliseconds: 500), () {
      DraftStore.save(
        roomId: widget.room.roomId,
        isGroup: false,
        text: text,
      );
    });
  }

  Future<void> _loadDraft() async {
    final draft = await DraftStore.load(
      roomId: widget.room.roomId,
      isGroup: false,
    );
    if (!_disposed && mounted && draft.isNotEmpty) {
      _inputController.text = draft;
      _inputController.selection = TextSelection.fromPosition(
        TextPosition(offset: draft.length),
      );
      setState(() => _inputIsEmpty = draft.trim().isEmpty);
    }
  }

  Future<void> _loadFailedMessages() async {
    final messages = await PendingMessageStore.getForRoom(
      roomId: widget.room.roomId,
      isGroup: false,
    );
    if (!_disposed && mounted) {
      setState(() => _failedMessages = messages);
    }
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position.pixels;
    final maxPos = _scrollController.position.maxScrollExtent;
    final fromBottom = maxPos - pos;

    if (fromBottom > 100) {
      _lockedScrollPos = pos;
      _scrollLocked = true;
    } else {
      _lockedScrollPos = null;
      _scrollLocked = false;
    }

    if (pos < 200 && !_isPaginating && !_noMoreMessages) {
      _triggerPagination();
    }
  }

  Future<void> _triggerPagination() async {
    if (_isPaginating || _noMoreMessages) return;
    setState(() => _isPaginating = true);

    final beforeMaxExtent = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;

    final loaded = await loadOlderMessages(widget.room.roomId);

    if (!_disposed && mounted) {
      setState(() {
        _isPaginating = false;
        if (!loaded) _noMoreMessages = true;
      });

      if (loaded) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_disposed || !mounted) return;
          if (!_scrollController.hasClients) return;
          final afterMaxExtent =
              _scrollController.position.maxScrollExtent;
          final diff = afterMaxExtent - beforeMaxExtent;
          if (diff > 0) {
            _scrollController.jumpTo(
              _scrollController.position.pixels + diff,
            );
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    currentOpenRoomId = null;
    _draftSaveDebouncer?.cancel();
    _markReadDebouncer?.cancel();
    DraftStore.save(
      roomId: widget.room.roomId,
      isGroup: false,
      text: _inputController.text,
    );
    _inputController.removeListener(_onInputChanged);
    _inputController.dispose();
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _searchController.dispose();
    _focusNode.dispose();
    if (_blockChannel != null) {
      Supabase.instance.client.removeChannel(_blockChannel!);
    }
    super.dispose();
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    final pos = _scrollController.position;
    return pos.pixels >= pos.maxScrollExtent - 300;
  }

  void _jumpToBottom() {
    if (_scrollLocked) return;
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
  }

  void _forceScrollToBottom() {
    if (_initialScrolled) return;
    _initialScrolled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!_disposed && mounted) _jumpToBottom();
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!_disposed && mounted) _jumpToBottom();
    });
    Future.delayed(const Duration(milliseconds: 700), () {
      if (!_disposed && mounted) _jumpToBottom();
    });
  }

  void _animateToBottom() {
    if (_scrollLocked) return;
    Future.delayed(const Duration(milliseconds: 150), () {
      if (_disposed || !mounted) return;
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _loadAllStatus() async {
    try {
      final results = await Future.wait([
        _fetchBlockStatus(),
        _fetchFriendStatus(),
      ]);
      if (!_disposed && mounted) {
        setState(() {
          final b = results[0] as Map<String, bool>;
          _isBlocked = b['myBlock'];
          _isBlockedByPartner = b['partnerBlock'];
          _friendStatus = results[1] as String;
        });
      }
    } catch (e) {
      if (!_disposed && mounted) {
        setState(() {
          _isBlocked ??= false;
          _isBlockedByPartner ??= false;
          _friendStatus ??= 'none';
        });
      }
    }
  }

  Future<Map<String, bool>> _fetchBlockStatus() async {
    final sb = Supabase.instance.client;
    final my = await sb
        .from('kyorangtalk_blocks')
        .select('id')
        .eq('blocker_id', _myId)
        .eq('blocked_id', widget.room.partnerId)
        .maybeSingle();
    final partner = await sb
        .from('kyorangtalk_blocks')
        .select('id')
        .eq('blocker_id', widget.room.partnerId)
        .eq('blocked_id', _myId)
        .maybeSingle();
    return {'myBlock': my != null, 'partnerBlock': partner != null};
  }

  Future<String> _fetchFriendStatus() async {
    final data = await Supabase.instance.client
        .from('kyorangtalk_friends')
        .select('status')
        .or('and(requester_id.eq.$_myId,receiver_id.eq.${widget.room.partnerId}),'
            'and(requester_id.eq.${widget.room.partnerId},receiver_id.eq.$_myId)')
        .maybeSingle();
    return data?['status'] as String? ?? 'none';
  }

  Future<void> _reloadBlockStatus() async {
    try {
      final b = await _fetchBlockStatus();
      if (!_disposed && mounted) {
        setState(() {
          _isBlocked = b['myBlock'];
          _isBlockedByPartner = b['partnerBlock'];
        });
      }
    } catch (_) {}
  }

  Future<void> _reloadFriendStatus() async {
    try {
      final s = await _fetchFriendStatus();
      if (!_disposed && mounted) setState(() => _friendStatus = s);
    } catch (_) {}
  }

  Future<void> _loadMuteStatus() async {
    final muted =
        await NotificationService.isMuted(roomId: widget.room.roomId);
    if (!_disposed && mounted) setState(() => _isMuted = muted);
  }

  Future<void> _markAllRead() async {
    try {
      await Supabase.instance.client
          .from('kyorangtalk_messages')
          .update({'is_read': true})
          .eq('room_id', widget.room.roomId)
          .neq('sender_id', _myId)
          .eq('is_read', false);
      if (!_disposed && mounted) ref.invalidate(chatRoomsProvider);
    } catch (_) {}
  }

  // ⭐ B: debounce 적용된 호출
  void _scheduleMarkAllRead() {
    _markReadDebouncer?.cancel();
    _markReadDebouncer = Timer(const Duration(seconds: 1), () {
      if (!_disposed && mounted) _markAllRead();
    });
  }

  void _listenBlockChanges() {
    try {
      _blockChannel = Supabase.instance.client
          .channel('blocks_${widget.room.roomId}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'kyorangtalk_blocks',
            callback: (_) {
              if (!_disposed && mounted) _reloadBlockStatus();
            },
          )
          .subscribe();
    } catch (_) {}
  }

  Future<void> _tryExtractPlan(MessageModel msg) async {
    if (_disposed) return;
    if (msg.isDeleted) return;
    if (msg.imageUrl != null ||
        msg.isMultiImageMessage ||
        msg.fileUrl != null ||
        msg.gameData != null ||
        msg.pollId != null) return;

    final text = msg.audioUrl != null
        ? (msg.audioTranscript ?? '')
        : msg.content;
    if (text.trim().length < 10) return;

    if (_planExtractInProgress.contains(msg.id)) return;
    if (_detectedPlans.containsKey(msg.id)) return;

    _planExtractInProgress.add(msg.id);

    try {
      final cached = await PlanService.fetchByMessageId(msg.id);
      if (cached != null) {
        if (!_disposed && mounted && !cached.isDismissed) {
          setState(() => _detectedPlans[msg.id] = cached);
        }
        return;
      }

      final senderName = msg.senderId == _myId ? '나' : widget.room.partnerName;
      final plan = await PlanService.extractFromMessage(
        roomId: widget.room.roomId,
        isGroup: false,
        messageId: msg.id,
        messageText: text,
        senderName: senderName,
        context: _recentContextCache,
      );

      if (plan != null && !_disposed && mounted) {
        setState(() => _detectedPlans[msg.id] = plan);
      }
    } finally {
      _planExtractInProgress.remove(msg.id);
    }
  }

  // ⭐ A: 입장 시 30개 한꺼번에 추출하는 함수 제거됨.
  //       대신 itemBuilder가 화면에 빌드할 때만 _tryExtractPlan 호출.
  //       (캐시 히트면 즉시, 미스면 백그라운드 1건만)

  Future<void> _sendFriendRequest() async {
    if (_friendRequestSending) return;
    setState(() => _friendRequestSending = true);
    try {
      await Supabase.instance.client.from('kyorangtalk_friends').insert({
        'requester_id': _myId,
        'receiver_id': widget.room.partnerId,
        'status': 'pending',
      });
      if (!_disposed && mounted) {
        setState(() {
          _friendStatus = 'pending';
          _friendRequestSending = false;
        });
        _showSnack('${widget.room.partnerName}님에게 친구 요청을 보냈어요');
        ref.invalidate(friendsProvider);
        ref.invalidate(sentRequestsProvider);
      }
    } catch (e) {
      if (!_disposed && mounted) {
        setState(() => _friendRequestSending = false);
        _showSnack('친구 요청 실패: $e');
      }
    }
  }

  Future<void> _blockUser() async {
    final ok =
        await showBlockConfirmDialog(context, widget.room.partnerName);
    if (!ok) return;
    try {
      final sb = Supabase.instance.client;
      await sb.from('kyorangtalk_blocks').insert({
        'blocker_id': _myId,
        'blocked_id': widget.room.partnerId,
      });
      await sb
          .from('kyorangtalk_friends')
          .delete()
          .or('and(requester_id.eq.$_myId,receiver_id.eq.${widget.room.partnerId}),'
              'and(requester_id.eq.${widget.room.partnerId},receiver_id.eq.$_myId)');
      if (!_disposed && mounted) {
        setState(() {
          _isBlocked = true;
          _friendStatus = 'none';
        });
        ref.invalidate(chatRoomsProvider);
        ref.invalidate(friendsProvider);
        _showSnack('${widget.room.partnerName}님을 차단했어요');
      }
    } catch (e) {
      if (!_disposed && mounted) _showSnack('차단 실패: $e');
    }
  }

  Future<void> _unblockUser() async {
    final ok =
        await showUnblockConfirmDialog(context, widget.room.partnerName);
    if (!ok) return;
    try {
      await Supabase.instance.client
          .from('kyorangtalk_blocks')
          .delete()
          .eq('blocker_id', _myId)
          .eq('blocked_id', widget.room.partnerId);
      if (!_disposed && mounted) {
        setState(() => _isBlocked = false);
        ref.invalidate(chatRoomsProvider);
        _showSnack('${widget.room.partnerName}님의 차단을 해제했어요');
      }
    } catch (e) {
      if (!_disposed && mounted) _showSnack('해제 실패: $e');
    }
  }

  Future<void> _reportUser() async {
    await showReportUserDialog(
      context: context,
      reportedUserId: widget.room.partnerId,
      reportedNickname: widget.room.partnerName,
    );
  }

  Future<void> _reportMessage(MessageModel msg) async {
    await showReportMessageDialog(
      context: context,
      messageId: msg.id,
      senderId: msg.senderId,
      roomId: widget.room.roomId,
      messageContent: msg.content,
      senderNickname: widget.room.partnerName,
    );
  }

  void _onSearch(String query, List<MessageModel> messages) {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _searchIndex = 0;
      });
      return;
    }
    final results = <int>[];
    for (int i = 0; i < messages.length; i++) {
      if (messages[i]
          .content
          .toLowerCase()
          .contains(query.toLowerCase())) {
        results.add(i);
      }
    }
    setState(() {
      _searchResults = results;
      _searchIndex = results.isEmpty ? 0 : results.length - 1;
    });
    if (results.isNotEmpty) {
      _scrollToMessageById(messages[results.last].id);
    }
  }

  void _scrollToMessageById(String id) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _messageKeys[id];
      if (key?.currentContext != null) {
        Scrollable.ensureVisible(
          key!.currentContext!,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          alignment: 0.5,
        );
      }
    });
  }

  // ⭐ C: 캐시된 정렬 결과 반환 (build 안에서 매번 sort 안 함)
  List<MessageModel> _getSortedMessages() => _sortedMessages;

  // ⭐ C: 캐시된 컨텍스트 반환
  List<String> _getRecentMessagesForContext() => _recentContextCache;

  // ⭐ ref.listen에서 메시지 변경 시 한 번만 정렬/필터
  void _updateMessageCaches(List<MessageModel> msgs) {
    final sorted = [...msgs]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    _sortedMessages = sorted;

    // 최근 5개 텍스트 메시지로 컨텍스트 구성
    final recent = sorted.reversed
        .where((m) =>
            !m.isDeleted &&
            !m.isImageMessage &&
            m.audioUrl == null &&
            m.fileUrl == null &&
            m.gameData == null &&
            m.pollId == null &&
            m.content.trim().isNotEmpty)
        .take(5)
        .toList()
        .reversed
        .toList();

    _recentContextCache = recent.map((m) {
      final speaker =
          m.senderId == _myId ? '나' : widget.room.partnerName;
      return '$speaker: ${m.content}';
    }).toList();
  }

  // ⭐ C: build에서 시간 조건만 평가, 정렬은 안 함
  MessageModel? _computeSmartReplyTarget() {
    if (!_inputIsEmpty) return null;
    if (_sortedMessages.isEmpty) return null;

    final last = _sortedMessages.last;

    if (last.senderId == _myId) return null;
    if (last.isDeleted) return null;
    if (_smartReplyDismissedFor == last.id) return null;

    final diff = DateTime.now().difference(last.createdAt);
    if (diff.inMinutes >= 1) return null;

    final hasText = last.audioUrl != null
        ? (last.audioTranscript?.isNotEmpty ?? false)
        : (!last.isImageMessage &&
            last.fileUrl == null &&
            last.gameData == null &&
            last.pollId == null &&
            last.content.trim().isNotEmpty);
    if (!hasText) return null;

    return last;
  }

  String _getSmartReplyText(MessageModel msg) {
    if (msg.audioUrl != null && msg.audioTranscript != null) {
      return msg.audioTranscript!;
    }
    return msg.content;
  }

  Future<void> _handleAttachment() async {
    if (_isBlocked == true || _isBlockedByPartner == true) return;
    final action = await showAttachmentMenu(context);
    if (!mounted || action == null) return;
    switch (action) {
      case 'gallery': await _pickAndSendImage(ImageSource.gallery); break;
      case 'camera':  await _pickAndSendImage(ImageSource.camera);  break;
      case 'voice':   await _recordVoice();                          break;
      case 'game':    await _sendGame();                             break;
      case 'poll':    await _sendPoll();                             break;
      case 'file':    await _sendFile();                             break;
    }
  }

  Future<void> _sendGame() async {
    if (!mounted) return;
    final gameData = await showGameSheet(context);
    if (gameData == null || !mounted) return;
    try {
      await sendMessage(
        myId: _myId,
        roomId: widget.room.roomId,
        content: _getGamePreviewText(gameData),
        gameData: gameData,
      );
      _animateToBottom();
    } catch (e) {
      if (mounted) _showSnack('게임 전송 실패: $e');
    }
  }

  String _getGamePreviewText(Map<String, dynamic> gameData) {
    final type = gameData['type'] as String?;
    switch (type) {
      case 'dice':     return '🎲 주사위';
      case 'coin':     return '🪙 동전';
      case 'rps':      return '✂️ 가위바위보';
      case 'roulette': return '🎡 룰렛';
      default:         return '🎮 게임';
    }
  }

  Future<void> _sendPoll() async {
    if (!mounted) return;
    final pollId = await showCreatePollDialog(
      context,
      roomId: widget.room.roomId,
      roomType: 'dm',
    );
    if (pollId == null || !mounted) return;
    try {
      await sendMessage(
        myId: _myId,
        roomId: widget.room.roomId,
        content: '투표가 생성됐어요',
        pollId: pollId,
      );
      _animateToBottom();
    } catch (e) {
      if (mounted) _showSnack('투표 전송 실패: $e');
    }
  }

  Future<void> _sendFile() async {
    if (!mounted) return;
    final picked = await pickFile(context);
    if (picked == null || !mounted) return;
    setState(() => _sending = true);
    _showUploadDialog(picked.name);
    try {
      final fileUrl = await uploadFile(
        file: picked.file,
        fileName: picked.name,
        roomId: widget.room.roomId,
        roomType: 'dm',
      );
      await sendMessage(
        myId: _myId,
        roomId: widget.room.roomId,
        content: '[파일]',
        fileUrl: fileUrl,
        fileName: picked.name,
        fileSize: picked.size,
        fileType: picked.extension,
      );
      if (mounted) {
        Navigator.pop(context);
        setState(() => _sending = false);
        _animateToBottom();
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        setState(() => _sending = false);
        _showSnack('파일 전송 실패: $e');
      }
    }
  }

  void _showUploadDialog(String fileName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppTheme.primary),
              const SizedBox(height: 16),
              Text('파일 업로드 중...',
                  style: TextStyle(
                      color: AppTheme.textMain,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(fileName,
                  style:
                      TextStyle(color: AppTheme.textSub, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _recordVoice() async {
    if (_isBlocked == true || _isBlockedByPartner == true) return;
    final result = await showVoiceRecordSheet(context);
    if (result == null) return;
    if (!_disposed && mounted) setState(() => _sending = true);
    try {
      final audioUrl = await uploadAudioFile(
        localPath: result.path,
        roomId: widget.room.roomId,
      );
      sendMessage(
        myId: _myId,
        roomId: widget.room.roomId,
        content: '[음성 메시지]',
        audioUrl: audioUrl,
        audioDuration: result.duration,
      );
      if (!_disposed && mounted) {
        setState(() => _sending = false);
        _animateToBottom();
      }
    } catch (e) {
      if (!_disposed && mounted) {
        setState(() => _sending = false);
        _showSnack('음성 전송 실패: $e');
      }
    }
  }

  Future<void> _send() async {
    final content = _inputController.text.trim();
    if (content.isEmpty || _sending) return;
    if (_isBlocked == true || _isBlockedByPartner == true) return;

    final reply = _replyTo;

    final pending = PendingMessage(
      id: PendingMessageStore.generateLocalId(),
      roomId: widget.room.roomId,
      isGroup: false,
      content: content,
      replyToId: reply?.id,
      replyToContent: reply?.content,
      createdAt: DateTime.now(),
    );

    _inputController.clear();
    setState(() => _replyTo = null);

    DraftStore.clear(roomId: widget.room.roomId, isGroup: false);

    try {
      await sendMessage(
        myId: _myId,
        roomId: widget.room.roomId,
        content: content,
        replyToId: reply?.id,
        replyToContent: reply?.content,
      );
      if (!_disposed && mounted) {
        ref.invalidate(messagesProvider(widget.room.roomId));
        ref.invalidate(chatRoomsProvider);
      }
      _animateToBottom();
    } catch (e) {
      if (_disposed) return;
      final failed = pending.copyWith(errorMessage: e.toString());
      await PendingMessageStore.upsert(failed);
      if (mounted) {
        setState(() => _failedMessages = [..._failedMessages, failed]);
        _animateToBottom();
      }
    }
  }

  Future<void> _retryFailedMessage(PendingMessage msg) async {
    if (_retryingIds.contains(msg.id)) return;
    if (_isBlocked == true || _isBlockedByPartner == true) {
      _showSnack('차단된 사용자에게는 메시지를 보낼 수 없어요');
      return;
    }

    setState(() => _retryingIds.add(msg.id));

    try {
      await sendMessage(
        myId: _myId,
        roomId: msg.roomId,
        content: msg.content,
        replyToId: msg.replyToId,
        replyToContent: msg.replyToContent,
      );
      await PendingMessageStore.remove(msg.id);
      if (!_disposed && mounted) {
        setState(() {
          _failedMessages.removeWhere((m) => m.id == msg.id);
          _retryingIds.remove(msg.id);
        });
        ref.invalidate(messagesProvider(widget.room.roomId));
        ref.invalidate(chatRoomsProvider);
        _animateToBottom();
      }
    } catch (e) {
      if (_disposed) return;
      final updated = msg.copyWith(
        retryCount: msg.retryCount + 1,
        errorMessage: e.toString(),
      );
      await PendingMessageStore.upsert(updated);
      if (mounted) {
        setState(() {
          final idx = _failedMessages.indexWhere((m) => m.id == msg.id);
          if (idx >= 0) _failedMessages[idx] = updated;
          _retryingIds.remove(msg.id);
        });
        _showSnack('재전송에 실패했어요. 잠시 후 다시 시도해주세요');
      }
    }
  }

  Future<void> _cancelFailedMessage(PendingMessage msg) async {
    await PendingMessageStore.remove(msg.id);
    if (!_disposed && mounted) {
      setState(() {
        _failedMessages.removeWhere((m) => m.id == msg.id);
        _retryingIds.remove(msg.id);
      });
    }
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    if (_isBlocked == true || _isBlockedByPartner == true) return;

    if (source == ImageSource.camera) {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 90,
      );
      if (picked == null || !mounted) return;
      setState(() => _sending = true);
      try {
        final file = File(picked.path);
        final ext = picked.path.split('.').last;
        final path =
            'dm/${widget.room.roomId}/${DateTime.now().millisecondsSinceEpoch}.$ext';
        await Supabase.instance.client.storage
            .from('kyorangtalk')
            .upload(path, file,
                fileOptions: const FileOptions(upsert: true));
        final url = Supabase.instance.client.storage
            .from('kyorangtalk')
            .getPublicUrl(path);
        await sendMessage(
          myId: _myId,
          roomId: widget.room.roomId,
          content: '[이미지]',
          imageUrl: url,
        );
        if (!_disposed && mounted) {
          ref.invalidate(messagesProvider(widget.room.roomId));
          ref.invalidate(chatRoomsProvider);
          setState(() => _sending = false);
          _animateToBottom();
        }
      } catch (e) {
        if (!_disposed && mounted) {
          _showSnack('이미지 전송 실패: $e');
          setState(() => _sending = false);
        }
      }
      return;
    }

    final picked = await pickMultipleImagesFromGallery();
    if (picked.isEmpty || !mounted) return;

    final result = await showMultiImagePreview(
      context: context,
      initialImages: picked,
    );
    if (result == null || result.isEmpty || !mounted) return;

    final urls = await uploadMultipleImagesWithProgress(
      context: context,
      files: result.files,
      roomId: widget.room.roomId,
      roomType: 'dm',
      isOriginal: result.isOriginal,
    );
    if (urls == null || urls.isEmpty || !mounted) return;

    try {
      await sendMessage(
        myId: _myId,
        roomId: widget.room.roomId,
        content: urls.length == 1 ? '[이미지]' : '[이미지 ${urls.length}장]',
        imageUrls: urls,
      );
      if (!_disposed && mounted) {
        ref.invalidate(messagesProvider(widget.room.roomId));
        ref.invalidate(chatRoomsProvider);
        _animateToBottom();
      }
    } catch (e) {
      if (mounted) _showSnack('이미지 전송 실패: $e');
    }
  }

  Future<void> _deleteMessage(String messageId) async {
    await Supabase.instance.client
        .from('kyorangtalk_messages')
        .update({'is_deleted': true, 'content': '삭제된 메시지예요'})
        .eq('id', messageId)
        .eq('sender_id', _myId);
  }

  void _copyMessage(String content) {
    Clipboard.setData(ClipboardData(text: content));
    _showSnack('메시지가 복사됐어요');
  }

  Future<void> _pinMessage(String content) async {
    await setPinnedMessage(widget.room.roomId, content);
    if (!_disposed && mounted) {
      setState(() => _pinnedMessage = content);
      _showSnack('메시지를 고정했어요');
    }
  }

  Future<void> _unpinMessage() async {
    await setPinnedMessage(widget.room.roomId, null);
    if (!_disposed && mounted) setState(() => _pinnedMessage = null);
  }

  Future<void> _leaveChatRoom() async {
    final ok = await showLeaveChatConfirmDialog(context);
    if (!ok) return;
    await hideChatRoom(widget.room.roomId);
    if (!_disposed && mounted) {
      ref.invalidate(chatRoomsProvider);
      Navigator.pop(context);
    }
  }

  Future<void> _handleMute() async {
    final result = await showMuteOptionsSheet(context, isMuted: _isMuted);
    if (result == null || _disposed || !mounted) return;
    if (result == 'unmute') {
      await NotificationService.unmute(roomId: widget.room.roomId);
      if (!_disposed && mounted) {
        setState(() => _isMuted = false);
        _showSnack('알림이 켜졌어요');
      }
    } else {
      Duration? duration;
      String label;
      switch (result) {
        case '1h':  duration = const Duration(hours: 1);  label = '1시간'; break;
        case '8h':  duration = const Duration(hours: 8);  label = '8시간'; break;
        case '24h': duration = const Duration(hours: 24); label = '24시간'; break;
        default:    duration = null;                      label = '계속';
      }
      await NotificationService.mute(
          roomId: widget.room.roomId, duration: duration);
      if (!_disposed && mounted) {
        setState(() => _isMuted = true);
        _showSnack('$label 알림을 껐어요');
      }
    }
    if (!_disposed && mounted) ref.invalidate(mutedRoomsProvider);
  }

  void _showSnack(String msg) {
    if (_disposed || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  void _handleMessageOptions(MessageModel msg) {
    final isMe = msg.senderId == _myId;
    final isAnyBlocked = _isBlocked == true || _isBlockedByPartner == true;
    final isSpecial = msg.isImageMessage ||
        msg.audioUrl != null ||
        msg.gameData != null ||
        msg.pollId != null ||
        msg.fileUrl != null;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            if (!isAnyBlocked && !msg.isDeleted)
              ReactionPickerBar(
                onSelected: (emoji) {
                  Navigator.pop(sheetCtx);
                  toggleReaction(
                    messageId: msg.id,
                    roomId: widget.room.roomId,
                    emoji: emoji,
                    isGroup: false,
                  );
                },
              ),

            if (!isAnyBlocked && !msg.isDeleted)
              ListTile(
                leading: Icon(Icons.reply_rounded, color: AppTheme.textMain),
                title: Text('답장',
                    style: TextStyle(color: AppTheme.textMain)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  setState(() => _replyTo = msg);
                  _focusNode.requestFocus();
                },
              ),

            if (!isSpecial && !msg.isDeleted)
              ListTile(
                leading:
                    Icon(Icons.copy_outlined, color: AppTheme.textMain),
                title: Text('복사',
                    style: TextStyle(color: AppTheme.textMain)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _copyMessage(msg.content);
                },
              ),

            if (!isSpecial && !msg.isDeleted)
              ListTile(
                leading: Icon(Icons.push_pin_outlined,
                    color: AppTheme.textMain),
                title: Text('고정',
                    style: TextStyle(color: AppTheme.textMain)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _pinMessage(msg.content);
                },
              ),

            if (!isMe && !msg.isDeleted)
              ListTile(
                leading: const Icon(Icons.flag_outlined,
                    color: Color(0xFFFBBF24)),
                title: Text('신고',
                    style: TextStyle(color: AppTheme.textMain)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _reportMessage(msg);
                },
              ),

            if (isMe && !msg.isDeleted)
              ListTile(
                leading: const Icon(Icons.delete_outline,
                    color: Color(0xFFEF4444)),
                title: const Text('삭제',
                    style: TextStyle(
                        color: Color(0xFFEF4444),
                        fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _deleteMessage(msg.id);
                },
              ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _openPartnerProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(
          userId: widget.room.partnerId,
          nickname: widget.room.partnerName,
          avatarUrl: widget.room.partnerAvatar,
        ),
      ),
    ).then((_) {
      if (!_disposed && mounted) {
        _reloadBlockStatus();
        _reloadFriendStatus();
      }
    });
  }

  void _handleNotFriendTap() {
    showNotFriendActions(
      context,
      partnerName: widget.room.partnerName,
      partnerAvatar: widget.room.partnerAvatar,
      friendStatus: _friendStatus ?? 'none',
      onAddFriend: _sendFriendRequest,
      onBlock: _blockUser,
    );
  }

  String _timeStr(DateTime dt) {
    final local = dt.isUtc ? dt.toLocal() : dt;
    final ampm = local.hour < 12 ? '오전' : '오후';
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    return '$ampm $hour:${local.minute.toString().padLeft(2, '0')}';
  }

  String _dateLabel(DateTime dt) {
    final local = dt.isUtc ? dt.toLocal() : dt;
    final now = DateTime.now();
    final diff = DateTime(now.year, now.month, now.day)
        .difference(DateTime(local.year, local.month, local.day))
        .inDays;
    if (diff == 0) return '오늘';
    if (diff == 1) return '어제';
    return '${local.year}.${local.month}.${local.day}';
  }

  List<MessageGroup> _getGroupedMessages(List<MessageModel> messages) {
    if (_lastMessages != null &&
        _lastMessages!.length == messages.length &&
        identical(_lastMessages!.last, messages.last)) {
      return _cachedGroups;
    }
    final sorted = [...messages]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final groups = <MessageGroup>[];
    String? currentLabel;
    List<MessageModel> currentItems = [];
    for (final msg in sorted) {
      final label = _dateLabel(msg.createdAt);
      if (label != currentLabel) {
        if (currentItems.isNotEmpty) {
          groups.add(MessageGroup(currentLabel!, currentItems));
        }
        currentLabel = label;
        currentItems = [msg];
      } else {
        currentItems.add(msg);
      }
    }
    if (currentItems.isNotEmpty) {
      groups.add(MessageGroup(currentLabel!, currentItems));
    }
    _lastMessages = messages;
    _cachedGroups = groups;
    return groups;
  }

  GlobalKey _getKeyFor(String id) {
    return _messageKeys.putIfAbsent(id, () => GlobalKey());
  }

  @override
  Widget build(BuildContext context) {
    final msgsAsync = ref.watch(messagesProvider(widget.room.roomId));

    ref.listen(messagesProvider(widget.room.roomId), (prev, next) {
      if (_disposed) return;
      next.whenData((msgs) {
        if (_disposed) return;

        // ⭐ C: 메시지 변경 시점에 한 번만 정렬/컨텍스트 갱신
        _updateMessageCaches(msgs);

        if (prev?.value == null) {
          _forceScrollToBottom();
          // ⭐ A: 입장 시 30개 일괄 추출 안 함. itemBuilder가 처리.
          return;
        }

        final prevIds = prev!.value!.map((m) => m.id).toSet();
        final newMessages =
            msgs.where((m) => !prevIds.contains(m.id)).toList();

        if (newMessages.isNotEmpty) {
          final sortedNew = [...newMessages]
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
          final latestNew = sortedNew.last;
          final allSorted = _sortedMessages;
          final isAtBottom = allSorted.isNotEmpty &&
              allSorted.last.id == latestNew.id;

          if (isAtBottom) {
            final isMyMessage = latestNew.senderId == _myId;
            if (isMyMessage || _isNearBottom()) {
              Future.delayed(const Duration(milliseconds: 300), () {
                if (!_disposed && mounted) _animateToBottom();
              });
            }
          }
          final unread =
              msgs.where((m) => m.senderId != _myId && !m.isRead).toList();
          // ⭐ B: 매번 즉시 호출 → debounce 1초
          if (unread.isNotEmpty) _scheduleMarkAllRead();

          // 새 메시지만 plan 추출 시도 (1건씩)
          for (final msg in newMessages) {
            _tryExtractPlan(msg);
          }
        }
      });
    });

    final isAnyBlocked = _isBlocked == true || _isBlockedByPartner == true;
    final smartReplyTarget = _computeSmartReplyTarget();

    // ⭐ D: SummaryBanner는 unread가 임계값 이상일 때만
    final showSummary = !_summaryDismissed &&
        widget.room.unreadCount >= kSummaryMinUnread;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      resizeToAvoidBottomInset: true,
      appBar: _searchMode ? _buildSearchBar() : _buildNormalBar(),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (_pinnedMessage != null)
              PinnedMessageBanner(
                pinnedMessage: _pinnedMessage!,
                onUnpin: _unpinMessage,
              ),

            if (showSummary)
              SummaryBanner(
                roomId: widget.room.roomId,
                isGroup: false,
                unreadCount: widget.room.unreadCount,
                onDismiss: () =>
                    setState(() => _summaryDismissed = true),
              ),

            Expanded(
              child: msgsAsync.when(
                loading: () => const MessageSkeleton(),
                error: (e, _) => Center(
                  child: Text('오류: $e',
                      style: TextStyle(color: AppTheme.textSub)),
                ),
                data: _buildMessageList,
              ),
            ),

            if (_replyTo != null && !isAnyBlocked)
              ReplyPreview(
                replyTo: _replyTo!,
                isMyReply: _replyTo!.senderId == _myId,
                partnerName: widget.room.partnerName,
                onCancel: () => setState(() => _replyTo = null),
              ),

            if (!_searchMode)
              if (!_isStatusLoaded)
                ChatInputBar(
                  controller: _inputController,
                  focusNode: _focusNode,
                  enabled: false,
                  sending: false,
                  onAttachment: () {},
                  onSend: () {},
                )
              else if (isAnyBlocked)
                BlockedBanner(
                  isBlockedByMe: _isBlocked == true,
                  partnerName: widget.room.partnerName,
                  onUnblock: _isBlocked == true ? _unblockUser : null,
                )
              else ...[
                if (smartReplyTarget != null)
                  SmartReplyBar(
                    key: ValueKey('smart_reply_${smartReplyTarget.id}'),
                    roomId: widget.room.roomId,
                    isGroup: false,
                    lastMessageId: smartReplyTarget.id,
                    lastMessageText: _getSmartReplyText(smartReplyTarget),
                    senderName: widget.room.partnerName,
                    contextMessages: _getRecentMessagesForContext(),
                    onSelected: (text) {
                      _inputController.text = text;
                      _inputController.selection =
                          TextSelection.fromPosition(
                        TextPosition(offset: text.length),
                      );
                      _focusNode.requestFocus();
                      setState(() =>
                          _smartReplyDismissedFor = smartReplyTarget.id);
                    },
                    onDismiss: () {
                      setState(() =>
                          _smartReplyDismissedFor = smartReplyTarget.id);
                    },
                  ),
                ChatInputBar(
                  controller: _inputController,
                  focusNode: _focusNode,
                  enabled: true,
                  sending: _sending,
                  onAttachment: _handleAttachment,
                  onSend: _send,
                ),
              ],
          ],
        ),
      ),
    );
  }

  AppBar _buildNormalBar() => buildChatAppBar(
        context: context,
        room: widget.room,
        isStatusLoaded: _isStatusLoaded,
        isBlocked: _isBlocked,
        isBlockedByPartner: _isBlockedByPartner,
        friendStatus: _friendStatus,
        isMuted: _isMuted,
        onProfileTap: _openPartnerProfile,
        onSearchTap: () {
          setState(() {
            _searchMode = true;
            _searchQuery = '';
            _searchResults = [];
          });
        },
        onLeave: _leaveChatRoom,
        onMute: _handleMute,
        onUnblock: _unblockUser,
        onAddFriend: _sendFriendRequest,
        onBlock: _blockUser,
        onReport: _reportUser,
        onNotFriendTap: _handleNotFriendTap,
        onGallery: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RoomGalleryScreen(
                roomId: widget.room.roomId,
                isGroup: false,
                roomName: widget.room.partnerName,
                myId: _myId,
                partnerId: widget.room.partnerId,
                partnerName: widget.room.partnerName,
              ),
            ),
          );
        },
        onMemory: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RoomMemoryScreen(
                roomId: widget.room.roomId,
                isGroup: false,
                roomName: widget.room.partnerName,
                myId: _myId,
                partnerId: widget.room.partnerId,
                partnerName: widget.room.partnerName,
              ),
            ),
          );
        },
      );

  PreferredSizeWidget _buildSearchBar() {
    final sorted = _getSortedMessages();
    return buildChatSearchAppBar(
      context: context,
      searchController: _searchController,
      messages: sorted,
      searchIndex: _searchIndex,
      searchResults: _searchResults,
      onClose: () {
        setState(() {
          _searchMode = false;
          _searchQuery = '';
          _searchResults = [];
          _searchIndex = 0;
        });
        _searchController.clear();
      },
      onSearch: (v) {
        setState(() => _searchQuery = v);
        _onSearch(v, sorted);
      },
      onPrev: () {
        if (_searchResults.isEmpty) return;
        setState(() =>
            _searchIndex = (_searchIndex + 1) % _searchResults.length);
        _scrollToMessageById(sorted[_searchResults[_searchIndex]].id);
      },
      onNext: () {
        if (_searchResults.isEmpty) return;
        setState(() => _searchIndex =
            (_searchIndex - 1 + _searchResults.length) %
                _searchResults.length);
        _scrollToMessageById(sorted[_searchResults[_searchIndex]].id);
      },
    );
  }

  Widget _buildMessageList(List<MessageModel> messages) {
    if (messages.isEmpty && _failedMessages.isEmpty) {
      return EmptyChatState(partnerName: widget.room.partnerName);
    }

    final groups = _getGroupedMessages(messages);

    if (_searchMode && _searchQuery.isNotEmpty) {
      final sorted = groups.expand((g) => g.items).toList();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed && mounted) _onSearch(_searchQuery, sorted);
      });
    }

    final items = <_ListItem>[];
    if (_isPaginating) {
      items.add(_ListItem.loadingIndicator());
    } else if (_noMoreMessages) {
      items.add(_ListItem.startOfChatMarker());
    }

    for (final group in groups) {
      items.add(_ListItem.dateDivider(group.label));
      for (final msg in group.items) {
        items.add(_ListItem.message(msg));
      }
    }

    if (_failedMessages.isNotEmpty) {
      final sortedFailed = [..._failedMessages]
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      for (final f in sortedFailed) {
        items.add(_ListItem.failedMessage(f));
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || !mounted) return;
      if (!_scrollController.hasClients) return;
      if (_scrollLocked && _lockedScrollPos != null) {
        final currentPos = _scrollController.position.pixels;
        final diff = (currentPos - _lockedScrollPos!).abs();
        if (diff > 5) {
          _scrollController.jumpTo(_lockedScrollPos!);
        }
      }
    });

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: items.length,
      cacheExtent: 1000,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      itemBuilder: (ctx, index) {
        final item = items[index];

        if (item.isLoadingIndicator) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.primary,
                ),
              ),
            ),
          );
        }

        if (item.isStartOfChatMarker) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                '대화의 시작이에요',
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 11,
                ),
              ),
            ),
          );
        }

        if (item.isDivider) {
          return DateDivider(label: item.dateLabel!);
        }

        if (item.isFailedMessage) {
          final f = item.failedMessage!;
          return RepaintBoundary(
            key: ValueKey('failed_${f.id}'),
            child: FailedMessageBubble(
              message: f,
              timeStr: _timeStr(f.createdAt),
              isRetrying: _retryingIds.contains(f.id),
              onRetry: () => _retryFailedMessage(f),
              onCancel: () => _cancelFailedMessage(f),
            ),
          );
        }

        final msg = item.message!;

        // ⭐ A: 화면에 빌드되는 메시지에 대해서만 plan 추출 시도
        // (가드: in-progress, 캐시 hit, 30일 등 기존 _tryExtractPlan 안에서 처리)
        // → cacheExtent 1000px 안에 있는 메시지만 호출됨
        _tryExtractPlan(msg);

        final isMe = msg.senderId == _myId;
        final isHighlighted = _searchMode &&
            _searchQuery.isNotEmpty &&
            msg.content
                .toLowerCase()
                .contains(_searchQuery.toLowerCase());

        final detectedPlan = _detectedPlans[msg.id];

        return RepaintBoundary(
          key: ValueKey('msg_${msg.id}'),
          child: Column(
            crossAxisAlignment: isMe
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              GestureDetector(
                key: _getKeyFor(msg.id),
                onLongPress: () => _handleMessageOptions(msg),
                child: MessageBubble(
                  msg: msg,
                  roomId: widget.room.roomId,
                  isMe: isMe,
                  timeStr: _timeStr(msg.createdAt),
                  isHighlighted: isHighlighted,
                  searchQuery: _searchQuery,
                  partnerName: widget.room.partnerName,
                  partnerAvatar: widget.room.partnerAvatar,
                  onImageLoad: () {
                    if (_disposed) return;
                    if (_isNearBottom()) _jumpToBottom();
                  },
                  onImageTap: (url) {
                    final allUrls = msg.allImageUrls;
                    final initialIndex =
                        allUrls.indexOf(url).clamp(0, allUrls.length - 1);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MultiImageViewerScreen(
                          imageUrls: allUrls.isEmpty ? [url] : allUrls,
                          initialIndex: initialIndex < 0 ? 0 : initialIndex,
                          senderName: isMe ? '나' : widget.room.partnerName,
                          time: _timeStr(msg.createdAt),
                        ),
                      ),
                    );
                  },
                  onAvatarTap: isMe ? null : _openPartnerProfile,
                ),
              ),

              if (detectedPlan != null) ...[
                const SizedBox(height: 4),
                Padding(
                  padding: EdgeInsets.only(
                    left: isMe ? 40 : 36,
                    right: isMe ? 4 : 40,
                    bottom: 4,
                  ),
                  child: PlanCard(
                    plan: detectedPlan,
                    onDismissed: () {
                      if (!_disposed && mounted) {
                        setState(() => _detectedPlans.remove(msg.id));
                      }
                    },
                    onUpdated: (updated) {
                      if (!_disposed && mounted) {
                        setState(() => _detectedPlans[msg.id] = updated);
                      }
                    },
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ListItem {
  final String? dateLabel;
  final MessageModel? message;
  final PendingMessage? failedMessage;
  final bool isLoadingIndicator;
  final bool isStartOfChatMarker;

  _ListItem.dateDivider(this.dateLabel)
      : message = null,
        failedMessage = null,
        isLoadingIndicator = false,
        isStartOfChatMarker = false;

  _ListItem.message(this.message)
      : dateLabel = null,
        failedMessage = null,
        isLoadingIndicator = false,
        isStartOfChatMarker = false;

  _ListItem.failedMessage(this.failedMessage)
      : dateLabel = null,
        message = null,
        isLoadingIndicator = false,
        isStartOfChatMarker = false;

  _ListItem.loadingIndicator()
      : dateLabel = null,
        message = null,
        failedMessage = null,
        isLoadingIndicator = true,
        isStartOfChatMarker = false;

  _ListItem.startOfChatMarker()
      : dateLabel = null,
        message = null,
        failedMessage = null,
        isLoadingIndicator = false,
        isStartOfChatMarker = true;

  bool get isDivider =>
      dateLabel != null &&
      !isLoadingIndicator &&
      !isStartOfChatMarker;

  bool get isFailedMessage => failedMessage != null;
}
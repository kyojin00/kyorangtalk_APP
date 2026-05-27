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
import '../widgets/failed_message_bubble.dart';
import '../widgets/deleted_message_dialog.dart'; // ⭐ NEW
import '../../polls/widgets/create_poll_sheet.dart';
import '../../location/widgets/location_share_start_sheet.dart';
import '../../schedule/widgets/schedule_create_sheet.dart';
import '../../call/widgets/call_return_bubble.dart';

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

  bool _inputIsEmpty = true;

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

  List<MessageModel> _sortedMessages = const [];

  List<PendingMessage> _failedMessages = [];
  final Set<String> _retryingIds = <String>{};

  final Map<String, _OptimisticMessage> _optimisticMessages = {};

  Timer? _draftSaveDebouncer;
  Timer? _markReadDebouncer;

  // ⭐ NEW: 슬라이드 인 애니메이션 대상 메시지 ID
  //   상대방이 보낸 새 메시지만 잠시 추가되어 부드럽게 슬라이드 인됨
  //   자신 메시지는 옵티미스틱으로 이미 표시되니 애니메이션 불필요
  final Set<String> _animatingMessageIds = {};

  bool get _isStatusLoaded =>
      _isBlocked != null &&
      _isBlockedByPartner != null &&
      _friendStatus != null;

  @override
  void initState() {
    super.initState();
    currentOpenRoomId = widget.room.roomId;
    _pinnedMessage = widget.room.pinnedMessage;
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
    } catch (_) {}
  }

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

  List<MessageModel> _getSortedMessages() => _sortedMessages;

  void _updateMessageCaches(List<MessageModel> msgs) {
    final sorted = [...msgs]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    _sortedMessages = sorted;
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
      case 'location': await _shareLocation();                       break;
      case 'schedule': await _shareSchedule();                      break; 
    }
  }

  // 📅 일정 잡기
Future<void> _shareSchedule() async {
  final event = await showScheduleCreateSheet(
    context,
    roomId:   widget.room.roomId,
    roomType: 'dm',
  );
  if (event == null || !mounted) return;

  await sendMessage(
    myId:            _myId,
    roomId:          widget.room.roomId,
    content:         '일정을 잡고 있어요',
    scheduleEventId: event.id,
  );
}



  // 📍 위치 공유
  Future<void> _shareLocation() async {
    final share = await showLocationShareStartSheet(
      context,
      roomId: widget.room.roomId,
      roomType: 'dm',
    );
    if (share == null || !mounted) return;

    await sendMessage(
      myId: _myId,
      roomId: widget.room.roomId,
      content: '실시간 위치를 공유했어요',
      locationShareId: share.id,
    );
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
    if (content.isEmpty) return;
    if (_isBlocked == true || _isBlockedByPartner == true) return;

    final reply = _replyTo;
    final localId = PendingMessageStore.generateLocalId();
    final now = DateTime.now();

    final optimistic = _OptimisticMessage(
      localId: localId,
      content: content,
      replyToId: reply?.id,
      replyToContent: reply?.content,
      createdAt: now,
    );

    _inputController.clear();
    DraftStore.clear(roomId: widget.room.roomId, isGroup: false);

    setState(() {
      _replyTo = null;
      _optimisticMessages[localId] = optimistic;
    });

    _animateToBottom();

    try {
      await sendMessage(
        myId: _myId,
        roomId: widget.room.roomId,
        content: content,
        replyToId: reply?.id,
        replyToContent: reply?.content,
      );

      if (!_disposed && mounted) {
        setState(() => _optimisticMessages.remove(localId));
      }
    } catch (e) {
      if (_disposed) return;
      final failed = PendingMessage(
        id: localId,
        roomId: widget.room.roomId,
        isGroup: false,
        content: content,
        replyToId: reply?.id,
        replyToContent: reply?.content,
        createdAt: now,
        errorMessage: e.toString(),
      );
      await PendingMessageStore.upsert(failed);

      if (mounted) {
        setState(() {
          _optimisticMessages.remove(localId);
          _failedMessages = [..._failedMessages, failed];
        });
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
      if (!_disposed && mounted) _animateToBottom();
    } catch (e) {
      if (mounted) _showSnack('이미지 전송 실패: $e');
    }
  }

  Future<void> _deleteMessage(String messageId) async {
    await Supabase.instance.client
        .from('kyorangtalk_messages')
        .update({
          'is_deleted': true,
          'deleted_at': DateTime.now().toUtc().toIso8601String(),
          // ⭐ content는 덮어쓰지 않음 — 수신자가 24시간 내 복원 가능
        })
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

            // ⭐ NEW: 삭제된 메시지 — 수신자만 원본 보기 가능
            if (!isMe && msg.isDeleted)
              ListTile(
                leading: Icon(Icons.lock_open_rounded,
                    color: AppTheme.primary),
                title: Text('원본 보기',
                    style: TextStyle(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  showRestoreDeletedDmDialog(
                    context: context,
                    messageId: msg.id,
                    senderId: msg.senderId,
                    roomId: widget.room.roomId,
                    senderNickname: widget.room.partnerName,
                  );
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

        _updateMessageCaches(msgs);

        if (prev?.value == null) {
          _forceScrollToBottom();
          return;
        }

        final prevIds = prev!.value!.map((m) => m.id).toSet();
        final newMessages =
            msgs.where((m) => !prevIds.contains(m.id)).toList();

        if (newMessages.isNotEmpty) {
          if (_optimisticMessages.isNotEmpty) {
            final myNewMessages =
                newMessages.where((m) => m.senderId == _myId).toList();
            if (myNewMessages.isNotEmpty) {
              setState(() {
                for (final newMsg in myNewMessages) {
                  final matchKey = _optimisticMessages.entries
                      .where((e) =>
                          e.value.content == newMsg.content &&
                          newMsg.createdAt
                                  .difference(e.value.createdAt)
                                  .inSeconds
                                  .abs() <
                              30)
                      .map((e) => e.key)
                      .firstOrNull;
                  if (matchKey != null) {
                    _optimisticMessages.remove(matchKey);
                  }
                }
              });
            }
          }

          // ⭐ NEW: 상대방이 보낸 새 메시지에 슬라이드 인 효과
          //   자신 메시지는 옵티미스틱으로 이미 표시되어 있어 제외
          final newOtherMessages =
              newMessages.where((m) => m.senderId != _myId).toList();
          if (newOtherMessages.isNotEmpty) {
            setState(() {
              for (final m in newOtherMessages) {
                _animatingMessageIds.add(m.id);
              }
            });
            // 800ms 후 set에서 제거 (애니메이션은 ~280ms로 그 전에 완료됨)
            Future.delayed(const Duration(milliseconds: 800), () {
              if (!_disposed && mounted) {
                setState(() {
                  _animatingMessageIds
                      .removeAll(newOtherMessages.map((m) => m.id));
                });
              }
            });
          }

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
          if (unread.isNotEmpty) _scheduleMarkAllRead();
        }
      });
    });

    final isAnyBlocked = _isBlocked == true || _isBlockedByPartner == true;

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

            Expanded(
              child: msgsAsync.when(
                // ⭐ 카톡식: 로딩 스켈레톤 대신 빈 채팅창
                loading: () => const SizedBox.expand(),
                error: (e, _) => Center(
                  child: Text('오류: $e',
                      style: TextStyle(color: AppTheme.textSub)),
                ),
                data: _buildMessageList,
              ),
            ),

            CallReturnBubble(roomId: widget.room.roomId),

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
              else
                ChatInputBar(
                  controller: _inputController,
                  focusNode: _focusNode,
                  enabled: true,
                  sending: false,
                  onAttachment: _handleAttachment,
                  onSend: _send,
                ),
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

  // ⭐ NEW: 빈 채팅창 ↔ 메시지 리스트를 AnimatedSwitcher로 부드럽게 전환
  //   카톡처럼 첫 진입 시 비어있다가 메시지가 슬그머니 등장
  Widget _buildMessageList(List<MessageModel> messages) {
    final isEmpty = messages.isEmpty &&
        _failedMessages.isEmpty &&
        _optimisticMessages.isEmpty;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: isEmpty
          ? KeyedSubtree(
              key: const ValueKey('empty_state'),
              child: EmptyChatState(partnerName: widget.room.partnerName),
            )
          : KeyedSubtree(
              key: const ValueKey('message_list'),
              child: _buildListView(messages),
            ),
    );
  }

  Widget _buildListView(List<MessageModel> messages) {
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

    if (_optimisticMessages.isNotEmpty) {
      final sortedOptimistic = _optimisticMessages.values.toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      for (final o in sortedOptimistic) {
        items.add(_ListItem.optimistic(o));
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

        if (item.isOptimistic) {
          final o = item.optimistic!;
          return RepaintBoundary(
            key: ValueKey('opt_${o.localId}'),
            child: _OptimisticBubble(
              content: o.content,
              timeStr: _timeStr(o.createdAt),
            ),
          );
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
        final isMe = msg.senderId == _myId;
        final isHighlighted = _searchMode &&
            _searchQuery.isNotEmpty &&
            msg.content
                .toLowerCase()
                .contains(_searchQuery.toLowerCase());

        final bubble = GestureDetector(
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
        );

        // ⭐ NEW: 막 도착한 메시지에만 슬라이드 인 효과
        final shouldAnimate = _animatingMessageIds.contains(msg.id);

        return RepaintBoundary(
          key: ValueKey('msg_${msg.id}'),
          child: shouldAnimate ? _SlideInWrapper(child: bubble) : bubble,
        );
      },
    );
  }
}

class _OptimisticMessage {
  final String localId;
  final String content;
  final String? replyToId;
  final String? replyToContent;
  final DateTime createdAt;

  _OptimisticMessage({
    required this.localId,
    required this.content,
    this.replyToId,
    this.replyToContent,
    required this.createdAt,
  });
}

class _OptimisticBubble extends StatelessWidget {
  final String content;
  final String timeStr;

  const _OptimisticBubble({
    required this.content,
    required this.timeStr,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6, bottom: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.schedule,
                  size: 11,
                  color: AppTheme.textMuted,
                ),
                const SizedBox(height: 2),
                Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: 10,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: Opacity(
              opacity: 0.65,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(4),
                  ),
                ),
                child: Text(
                  content,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ListItem {
  final String? dateLabel;
  final MessageModel? message;
  final PendingMessage? failedMessage;
  final _OptimisticMessage? optimistic;
  final bool isLoadingIndicator;
  final bool isStartOfChatMarker;

  _ListItem.dateDivider(this.dateLabel)
      : message = null,
        failedMessage = null,
        optimistic = null,
        isLoadingIndicator = false,
        isStartOfChatMarker = false;

  _ListItem.message(this.message)
      : dateLabel = null,
        failedMessage = null,
        optimistic = null,
        isLoadingIndicator = false,
        isStartOfChatMarker = false;

  _ListItem.failedMessage(this.failedMessage)
      : dateLabel = null,
        message = null,
        optimistic = null,
        isLoadingIndicator = false,
        isStartOfChatMarker = false;

  _ListItem.optimistic(this.optimistic)
      : dateLabel = null,
        message = null,
        failedMessage = null,
        isLoadingIndicator = false,
        isStartOfChatMarker = false;

  _ListItem.loadingIndicator()
      : dateLabel = null,
        message = null,
        failedMessage = null,
        optimistic = null,
        isLoadingIndicator = true,
        isStartOfChatMarker = false;

  _ListItem.startOfChatMarker()
      : dateLabel = null,
        message = null,
        failedMessage = null,
        optimistic = null,
        isLoadingIndicator = false,
        isStartOfChatMarker = true;

  bool get isDivider =>
      dateLabel != null &&
      !isLoadingIndicator &&
      !isStartOfChatMarker;

  bool get isFailedMessage => failedMessage != null;
  bool get isOptimistic => optimistic != null;
}

// ═══════════════════════════════════════════════════
// ⭐ NEW: 새 메시지 슬라이드 인 애니메이션 wrapper
// 막 도착한 메시지가 살짝 아래에서 떠오르며 fade-in되는 효과
// ═══════════════════════════════════════════════════
class _SlideInWrapper extends StatefulWidget {
  final Widget child;
  const _SlideInWrapper({required this.child});

  @override
  State<_SlideInWrapper> createState() => _SlideInWrapperState();
}

class _SlideInWrapperState extends State<_SlideInWrapper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _offset;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _offset = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));
    _opacity = Tween<double>(begin: 0, end: 1).animate(_controller);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _offset,
        child: widget.child,
      ),
    );
  }
}